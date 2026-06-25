-- Stage 68: force runtime bundle Character sections to use the latest rule sheet.
-- This keeps Character UI attributes/skills aligned with the newest effective-value logic
-- even when legacy runtime-bundle implementations still exist in the database history.

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
