-- Stage 74:
-- - flatten runtime bundle equipment metadata for slot selection UI
-- - support effect modifier mode = set_min for source-bound skill grants
-- - migrate exoskeleton models/items to torso prosthetics with superheavy_armor minimum 1
-- - remove closed_suit models/items from active data paths

do $$
declare
  v_invalid_exo_unequipped integer := 0;
  v_closed_suit_items_deleted integer := 0;
  v_closed_suit_models_deleted integer := 0;
  v_closed_suit_links_deleted integer := 0;
  v_closed_suit_item_defs_deleted integer := 0;
  v_recomputed_characters integer := 0;
  v_character_id uuid;
begin
  create temp table if not exists tmp_odyssey_stage74_affected_characters (
    character_id uuid primary key
  ) on commit drop;

  truncate table tmp_odyssey_stage74_affected_characters;

  insert into tmp_odyssey_stage74_affected_characters (character_id)
  select distinct item.character_id
  from public.odyssey_character_equipment_items item
  join public.odyssey_equipment_model_defs model on model.id = item.equipment_model_id
  where model.code in ('prot_exo_01', 'basic_exoskeleton_frame')
     or model.item_type = 'closed_suit'
  on conflict do nothing;

  update public.odyssey_equipment_model_defs model
  set
    item_type = 'prosthetic',
    description = case
      when model.code = 'basic_exoskeleton_frame' then 'Torso prosthetic frame that grants Superheavy Armor Training while installed.'
      when model.code = 'prot_exo_01' then 'Torso prosthetic exo-frame that grants Superheavy Armor Training while installed.'
      else model.description
    end,
    default_body_part_code = 'torso',
    can_equip = true,
    can_equip_to_body_part = true,
    effect_data = public.odyssey_merge_effect_data(
      '{}'::jsonb,
      jsonb_build_object(
        'modifiers',
        jsonb_build_array(
          jsonb_build_object(
            'target', 'skill',
            'skill_code', 'superheavy_armor',
            'mode', 'set_min',
            'value', 1
          )
        )
      )
    ),
    flags = jsonb_build_object(
      'allowed_body_part_codes', jsonb_build_array('torso')
    ),
    tags = '["prosthetic","torso","equipable","body_part"]'::jsonb,
    updated_at = timezone('utc', now())
  where model.code in ('prot_exo_01', 'basic_exoskeleton_frame')
     or model.name in ('Prot-EXO-01', 'Basic Exoskeleton Frame');

  update public.odyssey_character_equipment_items item
  set
    is_equipped = false,
    equipped_body_part_id = null,
    updated_at = timezone('utc', now())
  where item.id in (
    select item2.id
    from public.odyssey_character_equipment_items item2
    join public.odyssey_equipment_model_defs model on model.id = item2.equipment_model_id
    left join public.odyssey_character_body_parts body_part on body_part.id = item2.equipped_body_part_id
    left join public.odyssey_body_part_defs body_def on body_def.id = body_part.body_part_def_id
    where (model.code in ('prot_exo_01', 'basic_exoskeleton_frame') or model.name in ('Prot-EXO-01', 'Basic Exoskeleton Frame'))
      and item2.is_equipped = true
      and item2.equipped_body_part_id is not null
      and public.odyssey_resolve_body_part_code(body_part.part_key, body_def.code) <> 'torso'
  );
  get diagnostics v_invalid_exo_unequipped = row_count;

  delete from public.odyssey_equipment_model_abilities link
  using public.odyssey_equipment_model_defs model
  where model.id = link.equipment_model_id
    and model.item_type = 'closed_suit';
  get diagnostics v_closed_suit_links_deleted = row_count;

  delete from public.odyssey_character_equipment_items item
  using public.odyssey_equipment_model_defs model
  where model.id = item.equipment_model_id
    and model.item_type = 'closed_suit';
  get diagnostics v_closed_suit_items_deleted = row_count;

  delete from public.odyssey_item_defs item_def
  where item_def.item_type = 'closed_suit';
  get diagnostics v_closed_suit_item_defs_deleted = row_count;

  delete from public.odyssey_equipment_model_defs model
  where model.item_type = 'closed_suit';
  get diagnostics v_closed_suit_models_deleted = row_count;

  for v_character_id in
    select character_id
    from tmp_odyssey_stage74_affected_characters
    order by character_id
  loop
    perform public.recompute_character_armor(v_character_id);
    perform public.odyssey_refresh_character_combat_state(v_character_id);
    v_recomputed_characters := v_recomputed_characters + 1;
  end loop;

  raise notice 'stage74_invalid_exo_unequipped=%', v_invalid_exo_unequipped;
  raise notice 'stage74_closed_suit_items_deleted=%', v_closed_suit_items_deleted;
  raise notice 'stage74_closed_suit_model_links_deleted=%', v_closed_suit_links_deleted;
  raise notice 'stage74_closed_suit_item_defs_deleted=%', v_closed_suit_item_defs_deleted;
  raise notice 'stage74_closed_suit_models_deleted=%', v_closed_suit_models_deleted;
  raise notice 'stage74_recomputed_characters=%', v_recomputed_characters;
end;
$$;

alter table public.odyssey_equipment_model_defs
  drop constraint if exists odyssey_equipment_model_defs_item_type_check;

alter table public.odyssey_equipment_model_defs
  add constraint odyssey_equipment_model_defs_item_type_check
  check (item_type in ('armor', 'shield', 'special_protection', 'device', 'implant', 'prosthetic', 'custom'));

create or replace function public.odyssey_runtime_flatten_equipment_item(
  p_item jsonb
)
returns jsonb
language sql
immutable
as $$
  with normalized as (
    select
      case when jsonb_typeof(p_item) = 'object' then p_item else '{}'::jsonb end as item_data
  ),
  split as (
    select
      item_data,
      case when jsonb_typeof(item_data->'model') = 'object' then item_data->'model' else '{}'::jsonb end as model_data,
      case when jsonb_typeof(item_data->'body_part') = 'object' then item_data->'body_part' else '{}'::jsonb end as body_part_data
    from normalized
  )
  select item_data || jsonb_build_object(
    'equipment_model_id', coalesce(nullif(item_data->>'equipment_model_id', ''), nullif(model_data->>'id', '')),
    'code', coalesce(nullif(item_data->>'code', ''), nullif(model_data->>'code', '')),
    'name', coalesce(nullif(item_data->>'name', ''), nullif(model_data->>'name', '')),
    'item_type', coalesce(nullif(item_data->>'item_type', ''), nullif(model_data->>'item_type', '')),
    'is_equipped', coalesce((item_data->>'is_equipped')::boolean, false),
    'equipped_body_part_id', coalesce(nullif(item_data->>'equipped_body_part_id', ''), nullif(body_part_data->>'id', '')),
    'equipped_body_part_code', coalesce(nullif(item_data->>'equipped_body_part_code', ''), nullif(body_part_data->>'code', ''), ''),
    'equipped_body_part_name', coalesce(nullif(item_data->>'equipped_body_part_name', ''), nullif(body_part_data->>'name', '')),
    'can_equip', coalesce((item_data->>'can_equip')::boolean, (model_data->>'can_equip')::boolean, true),
    'can_equip_to_body_part', coalesce((item_data->>'can_equip_to_body_part')::boolean, (model_data->>'can_equip_to_body_part')::boolean, true),
    'default_body_part_code', coalesce(nullif(item_data->>'default_body_part_code', ''), nullif(model_data->>'default_body_part_code', '')),
    'flags',
      case
        when jsonb_typeof(item_data->'flags') = 'object' then item_data->'flags'
        when jsonb_typeof(model_data->'flags') = 'object' then model_data->'flags'
        else '{}'::jsonb
      end,
    'tags',
      case
        when jsonb_typeof(item_data->'tags') = 'array' then item_data->'tags'
        when jsonb_typeof(model_data->'tags') = 'array' then model_data->'tags'
        else '[]'::jsonb
      end,
    'effect_data',
      case
        when jsonb_typeof(item_data->'effect_data') = 'object' then item_data->'effect_data'
        when jsonb_typeof(model_data->'effect_data') = 'object' then model_data->'effect_data'
        else '{}'::jsonb
      end
  )
  from split;
$$;

create or replace function public.get_character_runtime_bundle(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_sections_raw jsonb := v_payload->'sections';
  v_filtered_sections jsonb := '[]'::jsonb;
  v_item text;
  v_bundle jsonb := '{}'::jsonb;
  v_sections jsonb := '{}'::jsonb;
  v_rule_sheet jsonb := '{}'::jsonb;
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_campaign_id text := coalesce(nullif(trim(coalesce(v_payload->>'campaign_id', '')), ''), '');
  v_room_id text := coalesce(nullif(trim(coalesce(v_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(v_payload->>'scene_id', '')), ''), '');
  v_actor_player_id text := coalesce(nullif(trim(coalesce(v_payload->>'actor_player_id', '')), ''), '');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(v_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_wants_combat_session boolean := false;
  v_encounter public.odyssey_combat_encounters;
  v_participant jsonb := null;
  v_combat_session jsonb := null;
begin
  if jsonb_typeof(v_sections_raw) = 'array' then
    for v_item in
      select section_name
      from jsonb_array_elements_text(v_sections_raw) as section_rows(section_name)
    loop
      if lower(trim(v_item)) = 'combat_session' then
        v_wants_combat_session := true;
      else
        v_filtered_sections := v_filtered_sections || to_jsonb(v_item);
      end if;
    end loop;

    if jsonb_array_length(v_filtered_sections) = 0 then
      v_bundle := public.odyssey_get_character_runtime_bundle_legacy(
        (v_payload - 'sections') || jsonb_build_object('sections', jsonb_build_array('summary'))
      );
    else
      v_bundle := public.odyssey_get_character_runtime_bundle_legacy(
        (v_payload - 'sections') || jsonb_build_object('sections', v_filtered_sections)
      );
    end if;
  else
    v_wants_combat_session := true;
    v_bundle := public.odyssey_get_character_runtime_bundle_legacy(v_payload);
  end if;

  if coalesce((v_bundle->>'ok')::boolean, false) = false then
    return v_bundle;
  end if;

  if v_character_id is null then
    v_character_id := public.odyssey_try_parse_uuid(v_bundle#>>'{character,id}');
  end if;

  if v_campaign_id = '' then
    v_campaign_id := coalesce(v_bundle#>>'{character,campaign_id}', '');
  end if;
  if v_room_id = '' then
    v_room_id := coalesce(v_bundle#>>'{character,room_id}', '');
  end if;

  if v_wants_combat_session and v_character_id is not null and v_room_id <> '' and v_scene_id <> '' then
    select *
    into v_encounter
    from public.odyssey_get_active_encounter(v_campaign_id, v_room_id, v_scene_id);

    if found then
      select participant
      into v_participant
      from jsonb_array_elements(
        coalesce(
          public.odyssey_build_combat_runtime(
            v_encounter.id,
            v_actor_player_id,
            v_actor_is_gm,
            v_actor_is_gm,
            1
          )->'visible_participants',
          '[]'::jsonb
        )
      ) as participant_rows(participant)
      where public.odyssey_try_parse_uuid(participant_rows.participant->>'character_id') = v_character_id
      limit 1;

      if v_participant is not null then
        v_combat_session := jsonb_build_object(
          'encounter_id', v_encounter.id,
          'encounter_state_version', v_encounter.state_version,
          'participant',
            jsonb_build_object(
              'initiative_entry_id', public.odyssey_try_parse_uuid(v_participant->>'initiative_entry_id'),
              'initiative_value', coalesce(nullif(v_participant->>'initiative_value', '')::integer, 0),
              'order_index', coalesce(nullif(v_participant->>'order_index', '')::integer, 0),
              'is_current_turn', coalesce(nullif(v_participant->>'is_current_turn', '')::boolean, false),
              'action_current', coalesce(nullif(v_participant->>'action_current', '')::integer, 0),
              'action_max', coalesce(nullif(v_participant->>'action_max', '')::integer, 0),
              'move_current', coalesce(nullif(v_participant->>'move_current', '')::integer, 0),
              'move_max', coalesce(nullif(v_participant->>'move_max', '')::integer, 0),
              'reaction_action_current', coalesce(nullif(v_participant->>'reaction_action_current', '')::integer, 0),
              'action_converted_to_move', coalesce(nullif(v_participant->>'action_converted_to_move', '')::boolean, false),
              'hide_from_initiative_ui', coalesce(nullif(v_participant->>'hide_from_initiative_ui', '')::boolean, false),
              'movement_version', coalesce(nullif(v_participant->>'movement_version', '')::integer, 0)
            )
        );
      end if;
    end if;
  end if;

  v_sections := coalesce(v_bundle->'sections', '{}'::jsonb);
  if v_character_id is not null then
    v_rule_sheet := public.get_character_rule_sheet(v_character_id);
    if jsonb_typeof(v_rule_sheet) = 'object' then
      if v_sections ? 'attributes' then
        v_sections := jsonb_set(v_sections, '{attributes}', coalesce(v_rule_sheet->'attributes', '[]'::jsonb), true);
      end if;
      if v_sections ? 'skills' then
        v_sections := jsonb_set(v_sections, '{skills}', coalesce(v_rule_sheet->'skills', '[]'::jsonb), true);
      end if;
    end if;
  end if;

  if v_wants_combat_session then
    v_sections := v_sections || jsonb_build_object('combat_session', coalesce(v_combat_session, 'null'::jsonb));
  end if;

  if v_sections ? 'equipment' and jsonb_typeof(v_sections->'equipment') = 'array' then
    v_sections := jsonb_set(
      v_sections,
      '{equipment}',
      coalesce(
        (
          select jsonb_agg(public.odyssey_runtime_flatten_equipment_item(item_value))
          from jsonb_array_elements(v_sections->'equipment') as equipment_rows(item_value)
        ),
        '[]'::jsonb
      ),
      true
    );
  end if;

  return v_bundle || jsonb_build_object('sections', v_sections);
end;
$$;

create or replace function public.get_character_effect_summary(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_active_effects jsonb := '[]'::jsonb;
  v_modifier_rows jsonb := '[]'::jsonb;
  v_attribute_modifiers jsonb := '{}'::jsonb;
  v_skill_modifiers jsonb := '{}'::jsonb;
  v_skill_minimums jsonb := '{}'::jsonb;
  v_attack_accuracy integer := 0;
  v_defense integer := 0;
  v_damage integer := 0;
  v_armor integer := 0;
  v_movement_m integer := 0;
  v_action_count integer := 0;
  v_concentration_slots integer := 0;
  v_aim_difficulty integer := 0;
  v_range integer := 0;
  v_skip_main_action boolean := false;
  v_skip_movement boolean := false;
  v_consumes_full_turn boolean := false;
  v_helpless boolean := false;
  v_fatal_on_any_damage_if_unprotected boolean := false;
  v_suppress_movement boolean := false;
  v_cannot_leave_cover boolean := false;
  v_expires_after_attack boolean := false;
  v_expires_after_turn boolean := false;
  v_requires_concentration boolean := false;
begin
  with active_effect_rows as (
    select
      effect_rows.id,
      effect_rows.character_id,
      effect_rows.effect_def_id,
      effect_rows.code,
      effect_rows.effect_key,
      effect_rows.name,
      effect_rows.category,
      effect_rows.description,
      effect_rows.source,
      effect_rows.source_type,
      effect_rows.source_id,
      effect_rows.source_character_id,
      effect_rows.duration_type,
      effect_rows.rounds_left,
      effect_rows.stacks,
      effect_rows.data,
      effect_rows.stacking_mode,
      effect_rows.is_negative,
      effect_rows.is_narrative,
      effect_rows.created_by,
      effect_rows.created_at,
      effect_rows.updated_at
    from (
      select
        e.id,
        e.character_id,
        e.effect_def_id,
        coalesce(d.code, nullif(e.effect_key, ''), 'custom') as code,
        e.effect_key,
        e.name,
        coalesce(d.category, nullif(e.data->>'category', ''), 'custom') as category,
        e.description,
        e.source,
        coalesce(e.source_type, '') as source_type,
        e.source_id,
        e.source_character_id,
        e.duration_type,
        e.rounds_left,
        e.stacks,
        e.data,
        coalesce(d.stacking_mode, 'stack') as stacking_mode,
        coalesce(d.is_negative, false) as is_negative,
        coalesce(d.is_narrative, false) as is_narrative,
        e.created_by,
        e.created_at,
        e.updated_at
      from public.odyssey_character_effects e
      left join public.odyssey_effect_defs d on d.id = e.effect_def_id
      where e.character_id = p_character_id
        and e.is_active = true

      union all

      select
        item.id,
        item.character_id,
        null::uuid as effect_def_id,
        coalesce(nullif(trim(model.code), ''), 'equipment') as code,
        'equipment:' || item.id::text as effect_key,
        coalesce(nullif(trim(item.custom_name), ''), model.name) as name,
        coalesce(nullif(trim(item_effect.effect_data->>'category'), ''), 'equipment') as category,
        coalesce(
          nullif(trim(item_effect.effect_data->>'description'), ''),
          nullif(trim(model.description), ''),
          coalesce(nullif(trim(item.custom_name), ''), model.name)
        ) as description,
        coalesce(nullif(trim(item.custom_name), ''), model.name) as source,
        coalesce(nullif(trim(model.item_type), ''), 'equipment') as source_type,
        item.id as source_id,
        item.character_id as source_character_id,
        'manual'::text as duration_type,
        null::integer as rounds_left,
        1 as stacks,
        item_effect.effect_data as data,
        coalesce(nullif(trim(item_effect.effect_data->>'stacking_mode'), ''), 'stack') as stacking_mode,
        coalesce(nullif(trim(item_effect.effect_data->>'is_negative'), '')::boolean, false) as is_negative,
        coalesce(nullif(trim(item_effect.effect_data->>'is_narrative'), '')::boolean, false) as is_narrative,
        ''::text as created_by,
        item.created_at,
        item.updated_at
      from public.odyssey_character_equipment_items item
      join public.odyssey_equipment_model_defs model on model.id = item.equipment_model_id
      cross join lateral (
        select public.odyssey_merge_effect_data(
          coalesce(model.effect_data, '{}'::jsonb),
          case
            when jsonb_typeof(item.data->'effect_data') = 'object' then item.data->'effect_data'
            else '{}'::jsonb
          end
        ) as effect_data
      ) item_effect
      where item.character_id = p_character_id
        and item.is_equipped = true
        and (
          (
            jsonb_typeof(item_effect.effect_data->'modifiers') = 'array'
            and jsonb_array_length(item_effect.effect_data->'modifiers') > 0
          )
          or (
            jsonb_typeof(item_effect.effect_data->'flags') = 'object'
            and item_effect.effect_data->'flags' <> '{}'::jsonb
          )
        )
    ) effect_rows
  ),
  modifier_raw as (
    select
      aer.effect_key,
      aer.code,
      aer.category,
      aer.stacking_mode,
      lower(coalesce(modifier.value->>'target', '')) as target,
      lower(coalesce(modifier.value->>'mode', '')) as mode,
      nullif(trim(coalesce(modifier.value->>'attribute', '')), '') as attribute_ref,
      nullif(trim(coalesce(modifier.value->>'skill_code', modifier.value->>'skill', '')), '') as skill_ref,
      coalesce(nullif(trim(coalesce(modifier.value->>'value', '')), '')::integer, 0) as value
    from active_effect_rows aer
    join lateral jsonb_array_elements(
      case
        when jsonb_typeof(aer.data->'modifiers') = 'array' then aer.data->'modifiers'
        else '[]'::jsonb
      end
    ) modifier(value) on true
  ),
  modifier_resolved as (
    select
      raw.effect_key,
      raw.code,
      raw.category,
      raw.stacking_mode,
      raw.target,
      raw.mode,
      case
        when raw.target = 'attribute' then coalesce(attribute_by_id.code, attribute_by_code.code, lower(raw.attribute_ref))
        else null
      end as attribute_code,
      case
        when raw.target = 'skill' then coalesce(skill_by_id.code, skill_by_code.code, lower(raw.skill_ref))
        else null
      end as skill_code,
      raw.value
    from modifier_raw raw
    left join public.odyssey_attribute_defs attribute_by_id
      on attribute_by_id.id = public.odyssey_try_parse_uuid(raw.attribute_ref)
    left join public.odyssey_attribute_defs attribute_by_code
      on lower(attribute_by_code.code) = lower(raw.attribute_ref)
    left join public.odyssey_skill_defs skill_by_id
      on skill_by_id.id = public.odyssey_try_parse_uuid(raw.skill_ref)
    left join public.odyssey_skill_defs skill_by_code
      on lower(skill_by_code.code) = lower(raw.skill_ref)
  ),
  modifier_summary as (
    select
      target,
      attribute_code,
      skill_code,
      array_remove(array_agg(distinct effect_key), null) as effect_keys,
      array_remove(array_agg(distinct code), null) as effect_codes,
      case
        when bool_or(stacking_mode = 'lowest') then min(value)
        when bool_or(stacking_mode = 'highest') then max(value)
        else sum(value)
      end as resolved_value,
      case
        when bool_or(stacking_mode = 'lowest') then 'lowest'
        when bool_or(stacking_mode = 'highest') then 'highest'
        when bool_or(stacking_mode = 'replace') then 'replace'
        when bool_or(stacking_mode = 'unique') then 'unique'
        else 'stack'
      end as aggregation
    from modifier_resolved
    where target <> ''
      and coalesce(mode, '') <> 'set_min'
    group by target, attribute_code, skill_code
  ),
  skill_minimum_summary as (
    select
      skill_code,
      max(value) as minimum_value
    from modifier_resolved
    where target = 'skill'
      and skill_code is not null
      and mode = 'set_min'
    group by skill_code
  ),
  flag_raw as (
    select
      lower(flags.key) as flag_key,
      case
        when jsonb_typeof(flags.value) = 'boolean' then (flags.value #>> '{}')::boolean
        when lower(coalesce(flags.value #>> '{}', 'false')) in ('true', '1', 'yes', 'on') then true
        else false
      end as flag_value
    from active_effect_rows aer
    join lateral jsonb_each(
      case
        when jsonb_typeof(aer.data->'flags') = 'object' then aer.data->'flags'
        else '{}'::jsonb
      end
    ) flags(key, value) on true
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'effect_def_id', effect_def_id,
            'code', code,
            'effect_key', effect_key,
            'name', name,
            'category', category,
            'description', description,
            'source', source,
            'source_type', source_type,
            'source_id', source_id,
            'source_character_id', source_character_id,
            'duration_type', duration_type,
            'rounds_left', rounds_left,
            'stacks', stacks,
            'data', data,
            'is_negative', is_negative,
            'is_narrative', is_narrative,
            'created_by', created_by,
            'created_at', created_at,
            'updated_at', updated_at
          )
          order by created_at desc, id
        )
        from active_effect_rows
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'effect_keys', to_jsonb(effect_keys),
            'effect_codes', to_jsonb(effect_codes),
            'target', target,
            'attribute', attribute_code,
            'skill_code', skill_code,
            'value', resolved_value,
            'aggregation', aggregation,
            'mode', aggregation
          )
          order by target, attribute_code, skill_code
        )
        from modifier_summary
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_object_agg(attribute_code, resolved_value)
        from modifier_summary
        where target = 'attribute'
          and attribute_code is not null
      ),
      '{}'::jsonb
    ),
    coalesce(
      (
        select jsonb_object_agg(skill_code, resolved_value)
        from modifier_summary
        where target = 'skill'
          and skill_code is not null
      ),
      '{}'::jsonb
    ),
    coalesce(
      (
        select jsonb_object_agg(skill_code, minimum_value)
        from skill_minimum_summary
      ),
      '{}'::jsonb
    ),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'attack_accuracy'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'defense'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'damage'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'armor'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'movement_m'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'action_count'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'concentration_slots'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'aim_difficulty'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'range'), 0),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'skip_main_action'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'skip_movement'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'consumes_full_turn'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'helpless'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'fatal_on_any_damage_if_unprotected'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'suppress_movement'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'cannot_leave_cover'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'expires_after_attack'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'expires_after_turn'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'requires_concentration'), false)
  into
    v_active_effects,
    v_modifier_rows,
    v_attribute_modifiers,
    v_skill_modifiers,
    v_skill_minimums,
    v_attack_accuracy,
    v_defense,
    v_damage,
    v_armor,
    v_movement_m,
    v_action_count,
    v_concentration_slots,
    v_aim_difficulty,
    v_range,
    v_skip_main_action,
    v_skip_movement,
    v_consumes_full_turn,
    v_helpless,
    v_fatal_on_any_damage_if_unprotected,
    v_suppress_movement,
    v_cannot_leave_cover,
    v_expires_after_attack,
    v_expires_after_turn,
    v_requires_concentration;

  return jsonb_build_object(
    'character_id', p_character_id,
    'active_effects', v_active_effects,
    'modifier_rows', v_modifier_rows,
    'modifiers',
      jsonb_build_object(
        'attributes', v_attribute_modifiers,
        'skills', v_skill_modifiers,
        'skills_set_min', v_skill_minimums,
        'attack_accuracy', v_attack_accuracy,
        'defense', v_defense,
        'damage', v_damage,
        'armor', v_armor,
        'movement_m', v_movement_m,
        'action_count', v_action_count,
        'concentration_slots', v_concentration_slots,
        'aim_difficulty', v_aim_difficulty,
        'range', v_range
      ),
    'flags',
      jsonb_build_object(
        'helpless', v_helpless,
        'skip_main_action', v_skip_main_action,
        'skip_movement', v_skip_movement,
        'consumes_full_turn', v_consumes_full_turn,
        'fatal_on_any_damage_if_unprotected', v_fatal_on_any_damage_if_unprotected,
        'suppress_movement', v_suppress_movement,
        'cannot_leave_cover', v_cannot_leave_cover,
        'expires_after_attack', v_expires_after_attack,
        'expires_after_turn', v_expires_after_turn,
        'requires_concentration', v_requires_concentration
      )
  );
end;
$$;

create or replace function public.odyssey_get_effective_character_skill_states(
  p_character_id uuid
)
returns table (
  character_skill_id uuid,
  skill_def_id uuid,
  skill_code text,
  skill_name text,
  skill_category text,
  description text,
  skill_tags jsonb,
  sort_order integer,
  max_level integer,
  is_passive boolean,
  is_trained boolean,
  purchased_level integer,
  base_effective_level integer,
  effect_level_modifier integer,
  effect_skill_bonus integer,
  effective_level integer,
  skill_bonus integer,
  highest_available_level integer,
  current_level_requirements_met boolean,
  next_available_level integer,
  governing_attribute_def_id uuid,
  main_attribute_def_id uuid,
  main_attribute_code text,
  main_attribute_name text,
  main_base_value integer,
  main_effect_modifier integer,
  main_effective_value integer,
  secondary_attribute_def_id uuid,
  secondary_attribute_code text,
  secondary_attribute_name text,
  secondary_base_value integer,
  secondary_effect_modifier integer,
  secondary_effective_value integer,
  custom_name text,
  notes text
)
language sql
stable
as $$
  with selected_character as (
    select c.id
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  ),
  effect_summary as (
    select public.get_character_effect_summary(p_character_id) as effect_summary
    from selected_character
  ),
  skill_rows as (
    select
      s.id as character_skill_id,
      d.id as skill_def_id,
      d.code as skill_code,
      d.name as skill_name,
      d.category as skill_category,
      d.description,
      d.tags as skill_tags,
      d.sort_order,
      d.max_level,
      (d.category = 'passive' or d.max_level = 1) as is_passive,
      (s.id is not null) as is_trained,
      coalesce(s.level, 0) as purchased_level,
      s.governing_attribute_def_id,
      d.main_attribute_id as configured_main_attribute_def_id,
      d.secondary_attribute_id as configured_secondary_attribute_def_id,
      s.custom_name,
      s.notes
    from selected_character c
    cross join public.odyssey_skill_defs d
    left join public.odyssey_character_skills s
      on s.character_id = c.id
     and s.skill_def_id = d.id
  ),
  resolved_rows as (
    select
      skill_rows.*,
      case
        when skill_rows.governing_attribute_def_id is not null
          and skill_rows.configured_secondary_attribute_def_id is not null
          and skill_rows.governing_attribute_def_id in (
            skill_rows.configured_main_attribute_def_id,
            skill_rows.configured_secondary_attribute_def_id
          )
          then skill_rows.governing_attribute_def_id
        else skill_rows.configured_main_attribute_def_id
      end as resolved_main_attribute_def_id,
      case
        when skill_rows.governing_attribute_def_id is not null
          and skill_rows.configured_secondary_attribute_def_id is not null
          and skill_rows.governing_attribute_def_id in (
            skill_rows.configured_main_attribute_def_id,
            skill_rows.configured_secondary_attribute_def_id
          )
          then case
            when skill_rows.governing_attribute_def_id = skill_rows.configured_main_attribute_def_id
              then skill_rows.configured_secondary_attribute_def_id
            else skill_rows.configured_main_attribute_def_id
          end
        else skill_rows.configured_secondary_attribute_def_id
      end as resolved_secondary_attribute_def_id
    from skill_rows
  ),
  attribute_rows as (
    select
      resolved_rows.*,
      main_attr.code as main_attribute_code,
      main_attr.name as main_attribute_name,
      coalesce(main_value.value, main_attr.default_value, 0) as main_base_value,
      case
        when main_attr.code is null then 0
        else coalesce(
          nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', main_attr.code), '')::integer,
          0
        )
      end as main_effect_modifier,
      coalesce(main_value.value, main_attr.default_value, 0)
        + case
            when main_attr.code is null then 0
            else coalesce(
              nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', main_attr.code), '')::integer,
              0
            )
          end as main_effective_value,
      secondary_attr.code as secondary_attribute_code,
      secondary_attr.name as secondary_attribute_name,
      coalesce(secondary_value.value, secondary_attr.default_value, 0) as secondary_base_value,
      case
        when secondary_attr.code is null then 0
        else coalesce(
          nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', secondary_attr.code), '')::integer,
          0
        )
      end as secondary_effect_modifier,
      coalesce(secondary_value.value, secondary_attr.default_value, 0)
        + case
            when secondary_attr.code is null then 0
            else coalesce(
              nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', secondary_attr.code), '')::integer,
              0
            )
          end as secondary_effective_value,
      coalesce(
        nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'skills', resolved_rows.skill_code), '')::integer,
        0
      ) as effect_level_modifier,
      coalesce(
        nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'skills_set_min', resolved_rows.skill_code), '')::integer,
        0
      ) as effect_level_minimum
    from resolved_rows
    cross join effect_summary
    left join public.odyssey_attribute_defs main_attr on main_attr.id = resolved_rows.resolved_main_attribute_def_id
    left join public.odyssey_character_attributes main_value
      on main_value.character_id = p_character_id
     and main_value.attribute_def_id = main_attr.id
    left join public.odyssey_attribute_defs secondary_attr on secondary_attr.id = resolved_rows.resolved_secondary_attribute_def_id
    left join public.odyssey_character_attributes secondary_value
      on secondary_value.character_id = p_character_id
     and secondary_value.attribute_def_id = secondary_attr.id
  ),
  availability as (
    select
      attribute_rows.*,
      case
        when attribute_rows.is_passive then attribute_rows.purchased_level
        else coalesce(
          (
            select max(req.level)
            from public.odyssey_skill_level_requirements req
            where req.skill_def_id = attribute_rows.skill_def_id
              and (
                req.main_attribute_required is null
                or coalesce(attribute_rows.main_effective_value, 0) >= req.main_attribute_required
              )
              and (
                req.secondary_attribute_required is null
                or coalesce(attribute_rows.secondary_effective_value, 0) >= req.secondary_attribute_required
              )
          ),
          0
        )
      end as highest_available_level,
      case
        when attribute_rows.purchased_level <= 0 then true
        when attribute_rows.is_passive then true
        else coalesce(
          (
            select
              (
                (req.main_attribute_required is null or coalesce(attribute_rows.main_effective_value, 0) >= req.main_attribute_required)
                and (req.secondary_attribute_required is null or coalesce(attribute_rows.secondary_effective_value, 0) >= req.secondary_attribute_required)
              )
            from public.odyssey_skill_level_requirements req
            where req.skill_def_id = attribute_rows.skill_def_id
              and req.level = attribute_rows.purchased_level
            limit 1
          ),
          false
        )
      end as current_level_requirements_met,
      (
        select min(req.level)
        from public.odyssey_skill_level_requirements req
        where req.skill_def_id = attribute_rows.skill_def_id
          and req.level > case
            when attribute_rows.is_passive then attribute_rows.purchased_level
            else coalesce(
              (
                select max(req2.level)
                from public.odyssey_skill_level_requirements req2
                where req2.skill_def_id = attribute_rows.skill_def_id
                  and (
                    req2.main_attribute_required is null
                    or coalesce(attribute_rows.main_effective_value, 0) >= req2.main_attribute_required
                  )
                  and (
                    req2.secondary_attribute_required is null
                    or coalesce(attribute_rows.secondary_effective_value, 0) >= req2.secondary_attribute_required
                  )
              ),
              0
            )
          end
      ) as next_available_level
    from attribute_rows
  ),
  final_rows as (
    select
      availability.character_skill_id,
      availability.skill_def_id,
      availability.skill_code,
      availability.skill_name,
      availability.skill_category,
      availability.description,
      availability.skill_tags,
      availability.sort_order,
      availability.max_level,
      availability.is_passive,
      availability.is_trained,
      availability.purchased_level,
      case
        when availability.is_passive then availability.purchased_level
        else least(availability.purchased_level, greatest(availability.highest_available_level, 0))
      end as base_effective_level,
      availability.effect_level_modifier as effect_level_modifier,
      0 as effect_skill_bonus,
      least(
        greatest(
          case
            when availability.is_passive then availability.purchased_level
            else least(availability.purchased_level, greatest(availability.highest_available_level, 0))
          end + availability.effect_level_modifier,
          availability.effect_level_minimum,
          0
        ),
        case
          when availability.max_level >= 5 then 10
          when availability.max_level = 3 then 5
          else availability.max_level
        end
      ) as effective_level,
      availability.highest_available_level,
      availability.current_level_requirements_met,
      availability.next_available_level,
      availability.governing_attribute_def_id,
      availability.resolved_main_attribute_def_id as main_attribute_def_id,
      availability.main_attribute_code,
      availability.main_attribute_name,
      availability.main_base_value,
      availability.main_effect_modifier,
      availability.main_effective_value,
      availability.resolved_secondary_attribute_def_id as secondary_attribute_def_id,
      availability.secondary_attribute_code,
      availability.secondary_attribute_name,
      availability.secondary_base_value,
      availability.secondary_effect_modifier,
      availability.secondary_effective_value,
      availability.custom_name,
      availability.notes
    from availability
  )
  select
    final_rows.character_skill_id,
    final_rows.skill_def_id,
    final_rows.skill_code,
    final_rows.skill_name,
    final_rows.skill_category,
    final_rows.description,
    final_rows.skill_tags,
    final_rows.sort_order,
    final_rows.max_level,
    final_rows.is_passive,
    final_rows.is_trained,
    final_rows.purchased_level,
    final_rows.base_effective_level,
    final_rows.effect_level_modifier,
    final_rows.effect_skill_bonus,
    final_rows.effective_level,
    case
      when final_rows.is_passive then 0
      else final_rows.effective_level * 10
    end as skill_bonus,
    final_rows.highest_available_level,
    final_rows.current_level_requirements_met,
    final_rows.next_available_level,
    final_rows.governing_attribute_def_id,
    final_rows.main_attribute_def_id,
    final_rows.main_attribute_code,
    final_rows.main_attribute_name,
    final_rows.main_base_value,
    final_rows.main_effect_modifier,
    final_rows.main_effective_value,
    final_rows.secondary_attribute_def_id,
    final_rows.secondary_attribute_code,
    final_rows.secondary_attribute_name,
    final_rows.secondary_base_value,
    final_rows.secondary_effect_modifier,
    final_rows.secondary_effective_value,
    final_rows.custom_name,
    final_rows.notes
  from final_rows
  order by final_rows.skill_category, final_rows.sort_order, final_rows.skill_name;
$$;

create or replace function public.equip_character_equipment_item(
  p_item_id uuid,
  p_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_item public.odyssey_character_equipment_items%rowtype;
  v_model public.odyssey_equipment_model_defs%rowtype;
  v_body_part record;
  v_allowed_codes text[] := '{}'::text[];
  v_effective_part_code text := '';
  v_refresh jsonb := '{}'::jsonb;
  v_is_armor_protection boolean := false;
  v_existing_equipped record;
begin
  select *
  into v_item
  from public.odyssey_character_equipment_items e
  where e.id = p_item_id
  for update of e;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'EQUIPMENT_ITEM_NOT_FOUND', 'item_id', p_item_id);
  end if;

  select *
  into v_model
  from public.odyssey_equipment_model_defs m
  where m.id = v_item.equipment_model_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'EQUIPMENT_MODEL_NOT_FOUND', 'item_id', p_item_id);
  end if;

  select
    b.id,
    b.character_id,
    b.part_key,
    public.odyssey_resolve_body_part_code(b.part_key, d.code) as part_code
  into v_body_part
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'BODY_PART_NOT_FOUND', 'body_part_id', p_body_part_id);
  end if;

  if v_body_part.character_id <> v_item.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_CHARACTER_MISMATCH',
      'item_id', p_item_id,
      'body_part_id', p_body_part_id
    );
  end if;

  if not coalesce(v_model.can_equip, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_CANNOT_BE_EQUIPPED',
      'item_id', p_item_id,
      'equipment_model_code', v_model.code
    );
  end if;

  if not coalesce(v_model.can_equip_to_body_part, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_CANNOT_EQUIP_TO_BODY_PART',
      'item_id', p_item_id,
      'equipment_model_code', v_model.code
    );
  end if;

  v_effective_part_code := public.odyssey_normalize_body_part_slot_code(v_body_part.part_code);

  if jsonb_typeof(v_model.flags->'allowed_body_part_codes') = 'array' then
    select coalesce(
      array_agg(distinct public.odyssey_normalize_body_part_slot_code(body_code.value))
      filter (where public.odyssey_normalize_body_part_slot_code(body_code.value) <> ''),
      '{}'::text[]
    )
    into v_allowed_codes
    from jsonb_array_elements_text(v_model.flags->'allowed_body_part_codes') as body_code(value);
  end if;

  if coalesce(array_length(v_allowed_codes, 1), 0) > 0 then
    if not (v_effective_part_code = any (v_allowed_codes)) then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_NOT_ALLOWED',
        'item_id', p_item_id,
        'equipment_model_code', v_model.code,
        'body_part_code', v_effective_part_code,
        'allowed_body_part_codes', to_jsonb(v_allowed_codes)
      );
    end if;
  elsif nullif(trim(coalesce(v_model.default_body_part_code, '')), '') is not null then
    if public.odyssey_normalize_body_part_slot_code(v_model.default_body_part_code) <> v_effective_part_code then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_NOT_ALLOWED',
        'item_id', p_item_id,
        'equipment_model_code', v_model.code,
        'body_part_code', v_effective_part_code,
        'default_body_part_code', public.odyssey_normalize_body_part_slot_code(v_model.default_body_part_code)
      );
    end if;
  end if;

  v_is_armor_protection := lower(trim(coalesce(v_model.item_type, ''))) in (
    'armor',
    'shield',
    'special_protection'
  );

  if v_is_armor_protection then
    select
      e.id,
      coalesce(nullif(trim(e.custom_name), ''), occupied_model.name) as item_name
    into v_existing_equipped
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs occupied_model on occupied_model.id = e.equipment_model_id
    where e.character_id = v_item.character_id
      and e.is_equipped = true
      and e.equipped_body_part_id = p_body_part_id
      and e.id <> p_item_id
      and lower(trim(coalesce(occupied_model.item_type, ''))) in (
        'armor',
        'shield',
        'special_protection'
      )
    order by e.updated_at desc nulls last, e.created_at desc, e.id
    for update of e
    limit 1;

    if found then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_ARMOR_SLOT_OCCUPIED',
        'message', 'This body part already has an equipped armor item.',
        'body_part_id', p_body_part_id,
        'body_part_code', v_effective_part_code,
        'equipped_item', jsonb_build_object('id', v_existing_equipped.id, 'name', v_existing_equipped.item_name)
      );
    end if;
  end if;

  update public.odyssey_character_equipment_items
  set
    is_equipped = true,
    equipped_body_part_id = p_body_part_id,
    updated_at = timezone('utc', now())
  where id = p_item_id;

  perform public.recompute_character_armor(v_item.character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_item.character_id);

  return jsonb_build_object(
    'ok', true,
    'item', public.odyssey_get_equipment_item_json(p_item_id),
    'armor_summary', public.get_character_armor_summary(v_item.character_id),
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

grant execute on function public.odyssey_runtime_flatten_equipment_item(jsonb) to anon, authenticated;
grant execute on function public.get_character_runtime_bundle(jsonb) to anon, authenticated;
grant execute on function public.get_character_effect_summary(uuid) to anon, authenticated;
grant execute on function public.equip_character_equipment_item(uuid, uuid) to anon, authenticated;
