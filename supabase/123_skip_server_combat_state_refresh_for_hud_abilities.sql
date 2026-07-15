create or replace function public.add_character_effect(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_effect_code text := lower(trim(coalesce(p_payload->>'effect_code', '')));
  v_effect_key text := trim(coalesce(p_payload->>'effect_key', ''));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_description text := coalesce(p_payload->>'description', '');
  v_duration_type text := lower(trim(coalesce(p_payload->>'duration_type', '')));
  v_rounds_left integer := nullif(trim(coalesce(p_payload->>'rounds_left', '')), '')::integer;
  v_source text := coalesce(p_payload->>'source', '');
  v_source_type text := coalesce(p_payload->>'source_type', '');
  v_source_id uuid := nullif(trim(coalesce(p_payload->>'source_id', '')), '')::uuid;
  v_source_character_id uuid := nullif(trim(coalesce(p_payload->>'source_character_id', '')), '')::uuid;
  v_source_character_weapon_id uuid := nullif(trim(coalesce(p_payload->>'source_character_weapon_id', '')), '')::uuid;
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_payload_data jsonb := case when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data' else '{}'::jsonb end;
  v_payload_category text := lower(trim(coalesce(p_payload->>'category', '')));
  v_stacks integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'stacks', '')), '')::integer, 1), 1);
  v_include_combat_state boolean := coalesce(nullif(trim(coalesce(p_payload->>'include_combat_state', '')), '')::boolean, true);
  v_effect_def public.odyssey_effect_defs%rowtype;
  v_stacking_mode text := 'stack';
  v_merged_data jsonb := '{}'::jsonb;
  v_existing_effect_id uuid := null;
  v_inserted_id uuid := null;
  v_refresh jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_json jsonb := '{}'::jsonb;
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'character_id is required.'
    );
  end if;

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_character_id
    );
  end if;

  if v_source_character_weapon_id is not null and not exists (
    select 1
    from public.odyssey_character_weapons weapon
    where weapon.id = v_source_character_weapon_id
      and weapon.character_id = v_source_character_id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_ABILITY_SOURCE_NOT_AVAILABLE',
      'message', 'Weapon source was not found for this effect.',
      'source_character_weapon_id', v_source_character_weapon_id
    );
  end if;

  if v_effect_code <> '' then
    select *
    into v_effect_def
    from public.odyssey_effect_defs d
    where d.code = v_effect_code;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'EFFECT_DEF_NOT_FOUND',
        'effect_code', v_effect_code
      );
    end if;
  end if;

  if v_payload_category <> '' and v_payload_category not in ('buff', 'debuff', 'condition', 'combat', 'psionic', 'equipment', 'weapon', 'armor', 'narrative', 'custom') then
    v_payload_category := 'custom';
  end if;

  if v_effect_def.id is not null then
    v_effect_key := coalesce(nullif(v_effect_key, ''), v_effect_def.code);
    v_name := coalesce(nullif(v_name, ''), v_effect_def.name);
    v_description := coalesce(nullif(v_description, ''), v_effect_def.description);
    v_duration_type := coalesce(nullif(v_duration_type, ''), v_effect_def.default_duration_type);
    if v_rounds_left is null then
      v_rounds_left := v_effect_def.default_rounds;
    end if;
    v_stacking_mode := v_effect_def.stacking_mode;
    v_merged_data := public.odyssey_merge_effect_data(v_effect_def.data, v_payload_data);
  else
    v_stacking_mode := 'stack';
    if v_payload_category = '' then
      v_payload_category := 'custom';
    end if;
    v_merged_data := public.odyssey_merge_effect_data('{}'::jsonb, v_payload_data);
  end if;

  if v_payload_category <> '' then
    v_merged_data := jsonb_set(v_merged_data, '{category}', to_jsonb(v_payload_category), true);
  end if;

  v_duration_type := case v_duration_type
    when 'rounds' then 'rounds'
    when 'until_turn_start' then 'until_turn_start'
    when 'until_turn_end' then 'until_turn_end'
    when 'scene' then 'scene'
    when 'until_used' then 'until_used'
    else 'manual'
  end;

  if v_effect_key = '' then
    v_effect_key := regexp_replace(
      regexp_replace(lower(coalesce(nullif(v_name, ''), 'custom_effect')), '[^a-z0-9]+', '_', 'g'),
      '(^_+|_+$)',
      '',
      'g'
    );
  end if;

  if v_effect_key = '' then
    v_effect_key := 'custom_effect';
  end if;

  if v_name = '' then
    v_name := initcap(replace(v_effect_key, '_', ' '));
  end if;

  if v_stacking_mode in ('replace', 'highest', 'lowest') then
    update public.odyssey_character_effects
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where character_id = v_character_id
      and is_active = true
      and effect_key = v_effect_key;
  elsif v_stacking_mode = 'unique' then
    select e.id
    into v_existing_effect_id
    from public.odyssey_character_effects e
    where e.character_id = v_character_id
      and e.is_active = true
      and e.effect_key = v_effect_key
    order by e.created_at desc, e.id desc
    limit 1;

    if v_existing_effect_id is not null then
      if v_include_combat_state then
        v_effective_stats := public.get_effective_character_stats(v_character_id);
      end if;

      select jsonb_build_object(
        'id', e.id,
        'effect_def_id', e.effect_def_id,
        'code', coalesce(d.code, e.effect_key),
        'effect_key', e.effect_key,
        'name', e.name,
        'category', coalesce(d.category, nullif(e.data->>'category', ''), 'custom'),
        'description', e.description,
        'source', e.source,
        'source_type', e.source_type,
        'source_id', e.source_id,
        'source_character_id', e.source_character_id,
        'source_character_weapon_id', e.source_character_weapon_id,
        'duration_type', e.duration_type,
        'rounds_left', e.rounds_left,
        'stacks', e.stacks,
        'data', e.data,
        'created_by', e.created_by,
        'created_at', e.created_at,
        'updated_at', e.updated_at
      )
      into v_effect_json
      from public.odyssey_character_effects e
      left join public.odyssey_effect_defs d on d.id = e.effect_def_id
      where e.id = v_existing_effect_id;

      return jsonb_build_object(
        'ok', true,
        'created', false,
        'character_id', v_character_id,
        'effect', v_effect_json,
        'effective_stats', v_effective_stats,
        'combat_state',
          case
            when v_include_combat_state then
              coalesce(
                (
                  select jsonb_build_object(
                    'character_id', s.character_id,
                    'campaign_id', s.campaign_id,
                    'room_id', s.room_id,
                    'body_summary', s.body_summary,
                    'armor_summary', s.armor_summary,
                    'active_effects', s.active_effects,
                    'active_penalties', s.active_penalties,
                    'effective_stats', s.effective_stats,
                    'combat_flags', s.combat_flags,
                    'overlay_text', s.overlay_text,
                    'overlay_data', s.overlay_data,
                    'tracker_minor', s.tracker_minor,
                    'tracker_serious', s.tracker_serious,
                    'is_alive', s.is_alive,
                    'is_conscious', s.is_conscious,
                    'state_version', s.state_version,
                    'updated_at', s.updated_at
                  )
                  from public.odyssey_character_combat_state s
                  where s.character_id = v_character_id
                ),
                '{}'::jsonb
              )
            else '{}'::jsonb
          end
      );
    end if;
  end if;

  insert into public.odyssey_character_effects (
    character_id,
    effect_def_id,
    effect_key,
    name,
    description,
    source,
    source_type,
    source_id,
    source_character_id,
    source_character_weapon_id,
    duration_type,
    rounds_left,
    stacks,
    data,
    is_active,
    created_by
  )
  values (
    v_character_id,
    v_effect_def.id,
    v_effect_key,
    v_name,
    v_description,
    v_source,
    v_source_type,
    v_source_id,
    v_source_character_id,
    v_source_character_weapon_id,
    v_duration_type,
    v_rounds_left,
    v_stacks,
    v_merged_data,
    true,
    v_created_by
  )
  returning id into v_inserted_id;

  if v_include_combat_state then
    v_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
    v_effective_stats := public.get_effective_character_stats(v_character_id);
  end if;

  select jsonb_build_object(
    'id', e.id,
    'effect_def_id', e.effect_def_id,
    'code', coalesce(d.code, e.effect_key),
    'effect_key', e.effect_key,
    'name', e.name,
    'category', coalesce(d.category, nullif(e.data->>'category', ''), 'custom'),
    'description', e.description,
    'source', e.source,
    'source_type', e.source_type,
    'source_id', e.source_id,
    'source_character_id', e.source_character_id,
    'source_character_weapon_id', e.source_character_weapon_id,
    'duration_type', e.duration_type,
    'rounds_left', e.rounds_left,
    'stacks', e.stacks,
    'data', e.data,
    'created_by', e.created_by,
    'created_at', e.created_at,
    'updated_at', e.updated_at
  )
  into v_effect_json
  from public.odyssey_character_effects e
  left join public.odyssey_effect_defs d on d.id = e.effect_def_id
  where e.id = v_inserted_id;

  return jsonb_build_object(
    'ok', true,
    'created', true,
    'character_id', v_character_id,
    'effect', v_effect_json,
    'effective_stats', v_effective_stats,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_use_ability_with_weapon_support_legacy(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_ability_id uuid := nullif(trim(coalesce(p_payload->>'character_ability_id', '')), '')::uuid;
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_ability_code text := lower(trim(coalesce(p_payload->>'ability_code', '')));
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_target_armor_item_id uuid := nullif(trim(coalesce(p_payload->>'target_armor_item_id', '')), '')::uuid;
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_created_by text := coalesce(nullif(trim(coalesce(p_payload->>'created_by', '')), ''), '');
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_ability record;
  v_level record;
  v_effective_level integer := 0;
  v_target_part record;
  v_resource_result jsonb := '{}'::jsonb;
  v_effect_result jsonb := '{}'::jsonb;
  v_effect_results jsonb := '[]'::jsonb;
  v_merged_ability_data jsonb := '{}'::jsonb;
  v_effect_payload_data jsonb := '{}'::jsonb;
  v_effect_code text := '';
  v_effect_links jsonb := '[]'::jsonb;
  v_effect_link jsonb := '{}'::jsonb;
  v_link_data jsonb := '{}'::jsonb;
  v_link_effect_code text := '';
  v_link_effect_id uuid := null;
  v_effect_instance_data jsonb := '{}'::jsonb;
  v_effect_context jsonb := '{}'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_log_data jsonb := '{}'::jsonb;
  v_message text := '';
  v_source_character_weapon_id uuid := null;
  v_include_combat_state boolean := coalesce(nullif(trim(coalesce(p_payload->>'include_combat_state', '')), '')::boolean, true);
begin
  if v_character_ability_id is null then
    if v_character_id is null or v_ability_code = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_FOUND',
        'message', 'character_ability_id or character_id + ability_code is required.'
      );
    end if;

    select ability.id
    into v_character_ability_id
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.character_id = v_character_id
      and def.code = v_ability_code
      and ability.is_enabled = true
    order by ability.sort_order, ability.created_at, ability.id
    limit 1;
  end if;

  select
    ability.*,
    def.code as ability_code,
    def.name as ability_name,
    def.ability_kind,
    def.source_type,
    def.activation_type,
    def.target_type,
    def.effect_mode,
    def.attack_type,
    def.resource_mode,
    def.resource_pool_code,
    def.resource_item_code,
    def.description as ability_description,
    def.effect_data as def_effect_data,
    def.data as def_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = v_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', v_character_ability_id
    );
  end if;

  v_character_id := v_ability.character_id;
  v_source_character_weapon_id := v_ability.source_character_weapon_id;
  v_effective_level := public.odyssey_get_character_ability_effective_level(v_character_ability_id);

  select *
  into v_level
  from public.odyssey_ability_level_defs level_data
  where level_data.ability_def_id = v_ability.ability_def_id
    and level_data.ability_level <= v_effective_level
  order by level_data.ability_level desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_LEVEL_NOT_AVAILABLE',
      'character_ability_id', v_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  v_merged_ability_data :=
    coalesce(v_ability.def_data, '{}'::jsonb)
    || coalesce(v_ability.data, '{}'::jsonb)
    || coalesce(v_level.data, '{}'::jsonb);

  v_effect_payload_data := public.odyssey_merge_effect_data(
    public.odyssey_merge_effect_data(
      coalesce(v_ability.def_effect_data, '{}'::jsonb),
      case
        when jsonb_typeof(v_ability.data->'effect_data') = 'object' then v_ability.data->'effect_data'
        else '{}'::jsonb
      end
    ),
    coalesce(v_level.effect_data, '{}'::jsonb)
  );

  v_effect_code := lower(trim(coalesce(
    nullif(v_merged_ability_data->>'effect_code', ''),
    nullif(v_effect_payload_data->>'effect_code', ''),
    ''
  )));

  if jsonb_typeof(v_merged_ability_data->'effect_links') = 'array' then
    v_effect_links := v_merged_ability_data->'effect_links';
  end if;

  if v_ability.ability_kind = 'attack' or v_ability.effect_mode = 'attack' then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_REQUIRES_ATTACK_RESOLUTION',
      'message', 'Attack abilities must be resolved through perform_attack.',
      'character_ability_id', v_character_ability_id
    );
  end if;

  if v_ability.target_type = 'self' then
    v_target_character_id := v_character_id;
  elsif v_target_character_id is null then
    v_target_character_id := v_character_id;
  end if;

  v_resource_result := public.odyssey_consume_character_ability_cost(v_character_ability_id);
  if coalesce((v_resource_result->>'ok')::boolean, false) = false then
    return v_resource_result;
  end if;

  if coalesce(v_level.cooldown_rounds, 0) > 0 then
    update public.odyssey_character_abilities
    set current_cooldown_rounds = v_level.cooldown_rounds
    where id = v_character_ability_id;
  end if;

  v_effect_context := jsonb_strip_nulls(
    jsonb_build_object(
      'selected_body_part_id', case when v_target_body_part_id is not null then v_target_body_part_id::text else null end,
      'selected_armor_item_id', case when v_target_armor_item_id is not null then v_target_armor_item_id::text else null end,
      'source_character_weapon_id', case when v_source_character_weapon_id is not null then v_source_character_weapon_id::text else null end
    )
  );

  if v_ability.effect_mode = 'apply_effect' then
    if jsonb_typeof(v_effect_links) = 'array' and jsonb_array_length(v_effect_links) > 0 then
      for v_effect_link in
        select value
        from jsonb_array_elements(v_effect_links)
        order by coalesce(nullif(value->>'sort_order', '')::integer, 0)
      loop
        v_link_effect_code := lower(trim(coalesce(v_effect_link->>'effect_code', '')));
        v_link_effect_id := nullif(trim(coalesce(v_effect_link->>'effect_def_id', '')), '')::uuid;
        if v_link_effect_code = '' and v_link_effect_id is not null then
          select effect_def.code
          into v_link_effect_code
          from public.odyssey_effect_defs effect_def
          where effect_def.id = v_link_effect_id;
        end if;

        if v_link_effect_code = '' then
          return jsonb_build_object(
            'ok', false,
            'error', 'ABILITY_EFFECT_NOT_CONFIGURED',
            'message', 'One of the linked effects is missing effect_def_id/effect_code.',
            'character_ability_id', v_character_ability_id
          );
        end if;

        v_link_data := case
          when jsonb_typeof(v_effect_link->'data') = 'object' then v_effect_link->'data'
          else '{}'::jsonb
        end;
        v_effect_instance_data := public.odyssey_merge_effect_data(v_effect_payload_data, v_link_data);
        if v_effect_context <> '{}'::jsonb then
          v_effect_instance_data := public.odyssey_merge_effect_data(
            v_effect_instance_data,
            jsonb_build_object('context', v_effect_context)
          );
        end if;

        v_effect_result := public.add_character_effect(
          jsonb_build_object(
            'character_id', v_target_character_id,
            'effect_code', v_link_effect_code,
            'effect_key',
              case
                when v_source_character_weapon_id is not null
                  then public.odyssey_build_weapon_ability_effect_key(v_source_character_weapon_id, v_ability.ability_code, v_link_effect_code)
                else v_ability.ability_code || ':' || v_link_effect_code
              end,
            'name', v_ability.ability_name,
            'description', v_ability.ability_description,
            'category',
              case
                when v_ability.source_type = 'psionic' then 'psionic'
                when v_ability.source_type in ('implant', 'prosthetic', 'equipment', 'item') then 'equipment'
                when v_source_character_weapon_id is not null then 'weapon'
                else 'custom'
              end,
            'duration_type', case when v_level.duration_rounds is not null and v_level.duration_rounds > 0 then 'rounds' else 'manual' end,
            'rounds_left', v_level.duration_rounds,
            'source', v_ability.ability_name,
            'source_type', case when v_source_character_weapon_id is not null then 'weapon_ability' else v_ability.source_type end,
            'source_id', v_character_ability_id::text,
            'source_character_id', v_character_id::text,
            'source_character_weapon_id', case when v_source_character_weapon_id is not null then v_source_character_weapon_id::text else null end,
            'include_combat_state', v_include_combat_state,
            'data',
              public.odyssey_merge_effect_data(
                v_effect_instance_data,
                jsonb_strip_nulls(jsonb_build_object(
                  'scope', case when v_source_character_weapon_id is not null then 'weapon' else null end,
                  'source_character_weapon_id', case when v_source_character_weapon_id is not null then v_source_character_weapon_id::text else null end,
                  'source_character_ability_id', v_character_ability_id::text
                ))
              ),
            'created_by', v_created_by
          )
        );

        if coalesce((v_effect_result->>'ok')::boolean, false) = false then
          return v_effect_result;
        end if;

        v_refresh := coalesce(v_effect_result->'combat_state', v_refresh);
        v_effect_results := v_effect_results || jsonb_build_array(coalesce(v_effect_result->'effect', '{}'::jsonb));
      end loop;

      v_effect_result := jsonb_build_object(
        'ok', true,
        'effects', v_effect_results,
        'combat_state', v_refresh
      );
    elsif v_effect_code <> '' then
      v_effect_instance_data := v_effect_payload_data;
      if v_effect_context <> '{}'::jsonb then
        v_effect_instance_data := public.odyssey_merge_effect_data(
          v_effect_instance_data,
          jsonb_build_object('context', v_effect_context)
        );
      end if;

      v_effect_result := public.add_character_effect(
        jsonb_build_object(
          'character_id', v_target_character_id,
          'effect_code', v_effect_code,
          'effect_key',
            case
              when v_source_character_weapon_id is not null
                then public.odyssey_build_weapon_ability_effect_key(v_source_character_weapon_id, v_ability.ability_code, null)
              else v_ability.ability_code
            end,
          'name', v_ability.ability_name,
          'description', v_ability.ability_description,
          'category',
            case
              when v_ability.source_type = 'psionic' then 'psionic'
              when v_ability.source_type in ('implant', 'prosthetic', 'equipment', 'item') then 'equipment'
              when v_source_character_weapon_id is not null then 'weapon'
              else 'custom'
            end,
          'duration_type', case when v_level.duration_rounds is not null and v_level.duration_rounds > 0 then 'rounds' else 'manual' end,
          'rounds_left', v_level.duration_rounds,
          'source', v_ability.ability_name,
          'source_type', case when v_source_character_weapon_id is not null then 'weapon_ability' else v_ability.source_type end,
          'source_id', v_character_ability_id::text,
          'source_character_id', v_character_id::text,
          'source_character_weapon_id', case when v_source_character_weapon_id is not null then v_source_character_weapon_id::text else null end,
          'include_combat_state', v_include_combat_state,
          'data',
            public.odyssey_merge_effect_data(
              v_effect_instance_data,
              jsonb_strip_nulls(jsonb_build_object(
                'scope', case when v_source_character_weapon_id is not null then 'weapon' else null end,
                'source_character_weapon_id', case when v_source_character_weapon_id is not null then v_source_character_weapon_id::text else null end,
                'source_character_ability_id', v_character_ability_id::text
              ))
            ),
          'created_by', v_created_by
        )
      );

      if coalesce((v_effect_result->>'ok')::boolean, false) = false then
        return v_effect_result;
      end if;

      v_refresh := coalesce(v_effect_result->'combat_state', '{}'::jsonb);
    else
      if v_include_combat_state then
        v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
      end if;
      v_effect_result := jsonb_build_object(
        'ok', true,
        'narrative_only', true,
        'combat_state', v_refresh
      );
    end if;
  elsif v_ability.effect_mode = 'grant_special' then
    select
      b.id,
      b.character_id,
      b.part_key,
      b.max_critical,
      b.critical
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_target_character_id
      and coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) = 'special'
    limit 1
    for update of b;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'SPECIAL_BODY_PART_NOT_FOUND',
        'target_character_id', v_target_character_id
      );
    end if;

    update public.odyssey_character_body_parts
    set
      natural_armor_value = greatest(coalesce(v_level.special_armor_value, 0), 0),
      max_critical = greatest(coalesce(v_level.special_max_critical, max_critical), 0),
      critical = 0,
      serious = 0,
      minor = 0,
      disabled = false,
      destroyed = false
    where id = v_target_part.id;

    perform public.recompute_character_armor(v_target_character_id);
    if v_include_combat_state then
      v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
    end if;
    v_effect_result := jsonb_build_object(
      'ok', true,
      'special', public.odyssey_get_character_body_part_state(v_target_part.id),
      'combat_state', v_refresh
    );
  else
    if v_include_combat_state then
      v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
    end if;
    v_effect_result := jsonb_build_object(
      'ok', true,
      'narrative_only', true,
      'combat_state', v_refresh
    );
  end if;

  v_message := format(
    '%s uses %s.',
    coalesce(
      (
        select coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key)
        from public.odyssey_characters c
        where c.id = v_character_id
      ),
      v_character_id::text
    ),
    v_ability.ability_name
  );

  v_log_data := jsonb_build_object(
    'type', 'ability_use',
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_character_id,
    'target_character_id', v_target_character_id,
    'target_body_part_id', v_target_body_part_id,
    'target_armor_item_id', v_target_armor_item_id,
    'source_character_weapon_id', v_source_character_weapon_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', v_effect_result
  );

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    actor_character_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    coalesce((select c.campaign_id from public.odyssey_characters c where c.id = v_character_id), ''),
    coalesce((select c.room_id from public.odyssey_characters c where c.id = v_character_id), ''),
    v_scene_id,
    v_encounter_id,
    v_character_id,
    v_target_character_id,
    'ability_use',
    v_message,
    v_log_data,
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, coalesce((select c.room_id from public.odyssey_characters c where c.id = v_character_id), ''));

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_character_id,
    'target_character_id', v_target_character_id,
    'target_body_part_id', v_target_body_part_id,
    'target_armor_item_id', v_target_armor_item_id,
    'source_character_weapon_id', v_source_character_weapon_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', v_effect_result,
    'combat_state', v_refresh,
    'log_id', v_log_id
  );
end;
$$;

create or replace function public.odyssey_use_ability_with_weapon_support(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_ability_id');
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_ability_code text := lower(trim(coalesce(v_payload->>'ability_code', '')));
  v_selected_character_weapon_id uuid := public.odyssey_try_parse_uuid(v_payload->>'selected_character_weapon_id');
  v_source_validation jsonb := '{}'::jsonb;
  v_ability record;
  v_level record;
  v_effective_level integer := 0;
  v_merged_ability_data jsonb := '{}'::jsonb;
  v_resource_result jsonb := '{}'::jsonb;
  v_activation_result jsonb := '{}'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_feature_code text := '';
  v_stage text := 'resolve_character_ability';
  v_include_combat_state boolean := coalesce(nullif(trim(coalesce(v_payload->>'include_combat_state', '')), '')::boolean, true);
begin
  perform set_config('lock_timeout', '1500ms', true);

  if v_character_ability_id is null then
    if v_character_id is null or v_ability_code = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_FOUND',
        'message', 'character_ability_id or character_id + ability_code is required.'
      );
    end if;

    select ability.id
    into v_character_ability_id
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.character_id = v_character_id
      and def.code = v_ability_code
      and ability.is_enabled = true
    order by ability.sort_order, ability.created_at, ability.id
    limit 1;
  end if;

  v_source_validation := public.odyssey_validate_character_ability_source(
    v_character_ability_id,
    v_selected_character_weapon_id
  );
  if coalesce((v_source_validation->>'ok')::boolean, false) = false then
    return v_source_validation;
  end if;

  v_stage := 'lock_character_ability';
  select
    ability.*,
    def.code as ability_code,
    def.name as ability_name,
    def.ability_kind,
    def.source_type,
    def.activation_type,
    def.target_type,
    def.effect_mode,
    def.attack_type,
    def.resource_item_code,
    def.data as def_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = v_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', v_character_ability_id
    );
  end if;

  if v_ability.effect_mode <> 'activate_weapon_feature' then
    v_stage := 'delegate_legacy';
    return public.odyssey_use_ability_with_weapon_support_legacy(v_payload);
  end if;

  v_stage := 'load_ability_level';
  v_effective_level := public.odyssey_get_character_ability_effective_level(v_character_ability_id);
  select *
  into v_level
  from public.odyssey_ability_level_defs level_data
  where level_data.ability_def_id = v_ability.ability_def_id
    and level_data.ability_level <= v_effective_level
  order by level_data.ability_level desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_LEVEL_NOT_AVAILABLE',
      'character_ability_id', v_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  v_merged_ability_data := public.odyssey_merge_runtime_data(
    public.odyssey_merge_runtime_data(
      coalesce(v_ability.def_data, '{}'::jsonb),
      coalesce(v_ability.data, '{}'::jsonb)
    ),
    coalesce(v_level.data, '{}'::jsonb)
  );

  v_feature_code := lower(trim(coalesce(
    nullif(v_merged_ability_data->>'weapon_feature_code', ''),
    nullif(v_merged_ability_data->>'feature_code', ''),
    v_ability.ability_code
  )));

  if v_ability.source_character_weapon_id is null or v_feature_code = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_NOT_CONFIGURED',
      'message', 'The bridge ability does not define a weapon_feature_code.'
    );
  end if;

  v_stage := 'consume_ability_cost';
  v_resource_result := public.odyssey_consume_character_ability_cost(v_character_ability_id);
  if coalesce((v_resource_result->>'ok')::boolean, false) = false then
    return v_resource_result;
  end if;

  if coalesce(v_level.cooldown_rounds, 0) > 0 then
    v_stage := 'set_cooldown';
    update public.odyssey_character_abilities
    set current_cooldown_rounds = v_level.cooldown_rounds
    where id = v_character_ability_id;
  end if;

  v_stage := 'activate_weapon_feature';
  v_activation_result := public.activate_weapon_feature(
    jsonb_build_object(
      'character_weapon_id', v_ability.source_character_weapon_id::text,
      'feature_code', v_feature_code
    )
  );

  if coalesce((v_activation_result->>'ok')::boolean, false) = false then
    return v_activation_result;
  end if;

  if v_include_combat_state then
    v_stage := 'refresh_character_combat_state';
    v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_ability.character_id)->'combat_state', '{}'::jsonb);
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_ability.character_id,
    'source_character_weapon_id', v_ability.source_character_weapon_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', jsonb_build_object('weapon_feature', v_activation_result),
    'combat_state', v_refresh,
    'message', format('%s activated.', v_ability.ability_name)
  );
exception
  when lock_not_available then
    return jsonb_build_object(
      'ok', false,
      'error', 'ACTION_BUSY_RETRY',
      'message', 'Character state is busy. Please retry.',
      'stage', v_stage
    );
  when query_canceled then
    if SQLERRM ilike '%statement timeout%' or SQLERRM ilike '%lock timeout%' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ACTION_BUSY_RETRY',
        'message', 'Character state is busy. Please retry.',
        'stage', v_stage
      );
    end if;
    raise;
end;
$$;
