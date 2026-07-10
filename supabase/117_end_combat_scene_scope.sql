-- Stage 117: end all active encounters for the current scope when GM ends combat.
-- Default scope is scene to prevent stale duplicate encounters from leaving
-- characters "in combat" after the UI says combat ended.

create or replace function public.combat_end_encounter(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_encounter_id uuid := public.odyssey_try_parse_uuid(v_payload->>'encounter_id');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(v_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_scope text := lower(trim(coalesce(v_payload->>'scope', 'scene')));
  v_target public.odyssey_combat_encounters%rowtype;
  v_now timestamptz := timezone('utc', now());
  v_ended_ids uuid[] := array[]::uuid[];
  v_ended_count integer := 0;
  v_deactivated_entries_count integer := 0;
  v_ended_id uuid;
begin
  if not v_actor_is_gm then
    return jsonb_build_object(
      'ok', false,
      'error', 'CONTROL_DENIED',
      'message', 'Only the GM may end the encounter.'
    );
  end if;

  if v_encounter_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'encounter_id is required.'
    );
  end if;

  if v_scope not in ('encounter', 'scene', 'room') then
    v_scope := 'scene';
  end if;

  select *
  into v_target
  from public.odyssey_combat_encounters encounter
  where encounter.id = v_encounter_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ENCOUNTER_NOT_FOUND',
      'message', 'Encounter was not found.'
    );
  end if;

  select coalesce(array_agg(scope_rows.id), array[]::uuid[])
  into v_ended_ids
  from (
    select encounter.id
    from public.odyssey_combat_encounters encounter
    where encounter.status = 'active'
      and encounter.ended_at is null
      and (
        (v_scope = 'encounter' and encounter.id = v_target.id)
        or (
          v_scope = 'scene'
          and encounter.campaign_id = v_target.campaign_id
          and encounter.room_id = v_target.room_id
          and encounter.scene_id = v_target.scene_id
        )
        or (
          v_scope = 'room'
          and encounter.campaign_id = v_target.campaign_id
          and encounter.room_id = v_target.room_id
        )
      )
    for update
  ) as scope_rows;

  v_ended_count := coalesce(array_length(v_ended_ids, 1), 0);

  if v_ended_count > 0 then
    update public.odyssey_combat_encounters encounter
    set
      status = 'finished',
      ended_at = v_now,
      active_entry_id = null,
      active_character_id = null,
      updated_at = v_now,
      last_transition_at = v_now
    where encounter.id = any(v_ended_ids);

    update public.odyssey_initiative_entries entry
    set
      is_active = false
    where entry.encounter_id = any(v_ended_ids)
      and entry.is_active = true;
    get diagnostics v_deactivated_entries_count = row_count;

    foreach v_ended_id in array v_ended_ids
    loop
      perform public.odyssey_increment_encounter_state_version(v_ended_id);
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'encounter_id', v_target.id,
    'scope', v_scope,
    'campaign_id', v_target.campaign_id,
    'room_id', v_target.room_id,
    'scene_id', v_target.scene_id,
    'ended_encounter_ids', to_jsonb(v_ended_ids),
    'ended_count', v_ended_count,
    'deactivated_entries_count', v_deactivated_entries_count,
    'status', 'finished',
    'ended_at', case when v_ended_count > 0 then v_now else v_target.ended_at end
  );
end;
$$;
