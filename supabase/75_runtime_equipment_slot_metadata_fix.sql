-- Stage 75:
-- - ensure runtime bundle equipment items always include slot metadata from equipment models
-- - keep Creator/Schema item types free of exoskeleton and closed_suit
-- - preserve server-side equip validation in equip_character_equipment_item(...)

alter table public.odyssey_equipment_model_defs
  drop constraint if exists odyssey_equipment_model_defs_item_type_check;

alter table public.odyssey_equipment_model_defs
  add constraint odyssey_equipment_model_defs_item_type_check
  check (item_type in ('armor', 'shield', 'special_protection', 'device', 'implant', 'prosthetic', 'custom'));

create or replace function public.odyssey_get_equipment_item_json(
  p_item_id uuid
)
returns jsonb
language sql
stable
as $$
  with selected_item as (
    select
      e.id,
      e.character_id,
      e.equipment_model_id,
      e.equipped_body_part_id,
      e.custom_name,
      e.is_equipped,
      e.armor_value,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.current_charges,
      e.max_charges,
      e.data,
      e.notes,
      e.sort_order,
      e.created_at,
      e.updated_at,
      m.code as equipment_model_code,
      m.name as equipment_model_name,
      m.item_type,
      m.description as model_description,
      m.armor_value as model_armor_value,
      m.armor_max_minor as model_armor_max_minor,
      m.armor_max_serious as model_armor_max_serious,
      m.armor_max_critical as model_armor_max_critical,
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code,
      public.odyssey_equipment_item_has_remaining_armor_capacity(
        e.armor_minor,
        e.armor_max_minor,
        e.armor_serious,
        e.armor_max_serious,
        e.armor_critical,
        e.armor_max_critical
      ) as has_remaining_armor_capacity
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    left join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs body_def on body_def.id = b.body_part_def_id
    where e.id = p_item_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'id', s.id,
        'character_id', s.character_id,
        'equipment_model_id', s.equipment_model_id,
        'code', s.equipment_model_code,
        'item_type', s.item_type,
        'custom_name', s.custom_name,
        'name', coalesce(nullif(trim(s.custom_name), ''), s.equipment_model_name),
        'is_equipped', s.is_equipped,
        'equipped_body_part_id', s.equipped_body_part_id,
        'equipped_body_part_code', coalesce(s.body_part_code, ''),
        'equipped_body_part_name', s.body_part_name,
        'armor_value', s.armor_value,
        'armor_minor', s.armor_minor,
        'armor_max_minor', s.armor_max_minor,
        'armor_serious', s.armor_serious,
        'armor_max_serious', s.armor_max_serious,
        'armor_critical', s.armor_critical,
        'armor_max_critical', s.armor_max_critical,
        'armor_destroyed', s.armor_destroyed,
        'has_remaining_armor_capacity', s.has_remaining_armor_capacity,
        'current_charges', s.current_charges,
        'max_charges', s.max_charges,
        'data', s.data,
        'effect_data', coalesce(s.effect_data, '{}'::jsonb),
        'flags', coalesce(s.model_flags, '{}'::jsonb),
        'tags', coalesce(s.tags, '[]'::jsonb),
        'default_body_part_code', s.default_body_part_code,
        'can_equip', s.can_equip,
        'can_equip_to_body_part', s.can_equip_to_body_part,
        'notes', s.notes,
        'sort_order', s.sort_order,
        'created_at', s.created_at,
        'updated_at', s.updated_at,
        'model',
          jsonb_build_object(
            'id', s.equipment_model_id,
            'code', s.equipment_model_code,
            'name', s.equipment_model_name,
            'item_type', s.item_type,
            'description', s.model_description,
            'armor_value', s.model_armor_value,
            'armor_max_minor', s.model_armor_max_minor,
            'armor_max_serious', s.model_armor_max_serious,
            'armor_max_critical', s.model_armor_max_critical,
            'default_body_part_code', s.default_body_part_code,
            'can_equip', s.can_equip,
            'can_equip_to_body_part', s.can_equip_to_body_part,
            'effect_data', s.effect_data,
            'flags', s.model_flags,
            'tags', s.tags
          ),
        'effective_flags',
          case
            when jsonb_typeof(s.data->'flags') = 'object' then coalesce(s.model_flags, '{}'::jsonb) || (s.data->'flags')
            else coalesce(s.model_flags, '{}'::jsonb)
          end,
        'body_part',
          case
            when s.equipped_body_part_id is null then null
            else jsonb_build_object(
              'id', s.equipped_body_part_id,
              'part_key', s.part_key,
              'code', s.body_part_code,
              'name', s.body_part_name
            )
          end
      )
      from selected_item s
    ),
    '{}'::jsonb
  );
$$;

create or replace function public.get_character_equipment(
  p_character_id uuid
)
returns jsonb
language sql
stable
as $$
  with item_rows as (
    select
      e.id,
      e.character_id,
      e.equipment_model_id,
      e.equipped_body_part_id,
      e.custom_name,
      e.is_equipped,
      e.armor_value,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.current_charges,
      e.max_charges,
      e.data,
      e.notes,
      e.sort_order,
      e.created_at,
      e.updated_at,
      m.code as equipment_model_code,
      m.name as equipment_model_name,
      m.item_type,
      m.description as model_description,
      m.armor_value as model_armor_value,
      m.armor_max_minor as model_armor_max_minor,
      m.armor_max_serious as model_armor_max_serious,
      m.armor_max_critical as model_armor_max_critical,
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code,
      public.odyssey_equipment_item_has_remaining_armor_capacity(
        e.armor_minor,
        e.armor_max_minor,
        e.armor_serious,
        e.armor_max_serious,
        e.armor_critical,
        e.armor_max_critical
      ) as has_remaining_armor_capacity
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    left join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs body_def on body_def.id = b.body_part_def_id
    where e.character_id = p_character_id
  ),
  item_json as (
    select
      id,
      sort_order,
      created_at,
      is_equipped,
      equipped_body_part_id is not null as has_body_part,
      has_remaining_armor_capacity,
      jsonb_build_object(
        'id', id,
        'character_id', character_id,
        'equipment_model_id', equipment_model_id,
        'code', equipment_model_code,
        'item_type', item_type,
        'custom_name', custom_name,
        'name', coalesce(nullif(trim(custom_name), ''), equipment_model_name),
        'is_equipped', is_equipped,
        'equipped_body_part_id', equipped_body_part_id,
        'equipped_body_part_code', coalesce(body_part_code, ''),
        'equipped_body_part_name', body_part_name,
        'armor_value', armor_value,
        'armor_minor', armor_minor,
        'armor_max_minor', armor_max_minor,
        'armor_serious', armor_serious,
        'armor_max_serious', armor_max_serious,
        'armor_critical', armor_critical,
        'armor_max_critical', armor_max_critical,
        'armor_destroyed', armor_destroyed,
        'has_remaining_armor_capacity', has_remaining_armor_capacity,
        'current_charges', current_charges,
        'max_charges', max_charges,
        'data', data,
        'effect_data', coalesce(effect_data, '{}'::jsonb),
        'flags', coalesce(model_flags, '{}'::jsonb),
        'tags', coalesce(tags, '[]'::jsonb),
        'default_body_part_code', default_body_part_code,
        'can_equip', can_equip,
        'can_equip_to_body_part', can_equip_to_body_part,
        'notes', notes,
        'sort_order', sort_order,
        'created_at', created_at,
        'updated_at', updated_at,
        'model',
          jsonb_build_object(
            'id', equipment_model_id,
            'code', equipment_model_code,
            'name', equipment_model_name,
            'item_type', item_type,
            'description', model_description,
            'armor_value', model_armor_value,
            'armor_max_minor', model_armor_max_minor,
            'armor_max_serious', model_armor_max_serious,
            'armor_max_critical', model_armor_max_critical,
            'default_body_part_code', default_body_part_code,
            'can_equip', can_equip,
            'can_equip_to_body_part', can_equip_to_body_part,
            'effect_data', effect_data,
            'flags', model_flags,
            'tags', tags
          ),
        'effective_flags',
          case
            when jsonb_typeof(data->'flags') = 'object' then coalesce(model_flags, '{}'::jsonb) || (data->'flags')
            else coalesce(model_flags, '{}'::jsonb)
          end,
        'body_part',
          case
            when equipped_body_part_id is null then null
            else jsonb_build_object(
              'id', equipped_body_part_id,
              'part_key', part_key,
              'code', body_part_code,
              'name', body_part_name
            )
          end
      ) as item_payload
    from item_rows
  ),
  summary_row as (
    select jsonb_build_object(
      'total_item_count', count(*)::integer,
      'equipped_item_count', (count(*) filter (where is_equipped))::integer,
      'equipped_body_part_item_count', (count(*) filter (where is_equipped and has_body_part))::integer,
      'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part and has_remaining_armor_capacity))::integer, 0),
      'destroyed_armor_item_count', (count(*) filter (where coalesce((item_payload->>'armor_destroyed')::boolean, false)))::integer
    ) as summary_payload
    from item_json
  ),
  armor_summary as (
    select public.get_character_armor_summary(p_character_id) as payload
  )
  select jsonb_build_object(
    'character_id', p_character_id,
    'items',
      coalesce(
        (
          select jsonb_agg(item_payload order by is_equipped desc, has_body_part desc, sort_order, created_at, id)
          from item_json
        ),
        '[]'::jsonb
      ),
    'summary', coalesce((select summary_payload from summary_row), '{}'::jsonb),
    'armor_summary', coalesce((select payload from armor_summary), '{}'::jsonb)
  );
$$;

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

do $$
begin
  if to_regprocedure('public.get_character_runtime_bundle(jsonb)') is not null
     and to_regprocedure('public.odyssey_get_character_runtime_bundle_legacy(jsonb)') is null then
    alter function public.get_character_runtime_bundle(jsonb)
      rename to odyssey_get_character_runtime_bundle_legacy;
  end if;
end;
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
        v_sections := jsonb_set(
          v_sections,
          '{attributes}',
          coalesce(v_rule_sheet->'attributes', '[]'::jsonb),
          true
        );
      end if;
      if v_sections ? 'skills' then
        v_sections := jsonb_set(
          v_sections,
          '{skills}',
          coalesce(v_rule_sheet->'skills', '[]'::jsonb),
          true
        );
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

grant execute on function public.odyssey_get_equipment_item_json(uuid) to anon, authenticated;
grant execute on function public.get_character_equipment(uuid) to anon, authenticated;
grant execute on function public.odyssey_runtime_flatten_equipment_item(jsonb) to anon, authenticated;
grant execute on function public.get_character_runtime_bundle(jsonb) to anon, authenticated;
