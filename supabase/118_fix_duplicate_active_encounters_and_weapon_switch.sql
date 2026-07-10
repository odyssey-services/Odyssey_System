-- Stage 118: prevent duplicate active encounters per character and block
-- ambiguous weapon switching / reload economy bypass.

create or replace function public.odyssey_cleanup_character_active_participation(
  p_character_ids uuid[],
  p_keep_encounter_id uuid default null
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_character_ids uuid[] := coalesce(p_character_ids, array[]::uuid[]);
  v_old_entry_ids uuid[] := array[]::uuid[];
  v_old_encounter_ids uuid[] := array[]::uuid[];
  v_affected_encounter_id uuid;
  v_deactivated_count integer := 0;
  v_finished_count integer := 0;
  v_reactivated_count integer := 0;
begin
  if coalesce(array_length(v_character_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'ok', true,
      'deactivated_count', 0,
      'finished_count', 0,
      'reactivated_count', 0,
      'affected_encounter_ids', '[]'::jsonb
    );
  end if;

  with duplicate_entries as (
    select
      i.id as entry_id,
      i.encounter_id
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e
      on e.id = i.encounter_id
    where i.character_id = any(v_character_ids)
      and i.is_active = true
      and e.status = 'active'
      and e.ended_at is null
      and (p_keep_encounter_id is null or e.id <> p_keep_encounter_id)
    for update of i, e
  )
  select
    coalesce(array_agg(distinct duplicate_entries.entry_id), array[]::uuid[]),
    coalesce(array_agg(distinct duplicate_entries.encounter_id), array[]::uuid[])
  into
    v_old_entry_ids,
    v_old_encounter_ids
  from duplicate_entries;

  if coalesce(array_length(v_old_entry_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'ok', true,
      'deactivated_count', 0,
      'finished_count', 0,
      'reactivated_count', 0,
      'affected_encounter_ids', '[]'::jsonb
    );
  end if;

  update public.odyssey_initiative_entries i
  set
    is_active = false,
    updated_at = timezone('utc', now())
  where i.id = any(v_old_entry_ids)
    and i.is_active = true;
  get diagnostics v_deactivated_count = row_count;

  for v_affected_encounter_id in
    select unnest(v_old_encounter_ids)
  loop
    if not exists (
      select 1
      from public.odyssey_initiative_entries i
      where i.encounter_id = v_affected_encounter_id
        and i.is_active = true
    ) then
      update public.odyssey_combat_encounters e
      set
        status = 'finished',
        ended_at = timezone('utc', now()),
        active_entry_id = null,
        active_character_id = null,
        updated_at = timezone('utc', now()),
        last_transition_at = timezone('utc', now())
      where e.id = v_affected_encounter_id
        and e.status = 'active'
        and e.ended_at is null;

      if found then
        v_finished_count := v_finished_count + 1;
        perform public.odyssey_increment_encounter_state_version(v_affected_encounter_id);
      end if;
    else
      update public.odyssey_combat_encounters e
      set
        active_entry_id = null,
        active_character_id = null,
        updated_at = timezone('utc', now()),
        last_transition_at = timezone('utc', now())
      where e.id = v_affected_encounter_id
        and e.status = 'active'
        and e.ended_at is null
        and (
          e.active_character_id = any(v_character_ids)
          or e.active_entry_id = any(v_old_entry_ids)
        );

      if found then
        perform public.odyssey_increment_encounter_state_version(v_affected_encounter_id);
        perform public.odyssey_start_next_eligible_turn(v_affected_encounter_id);
        v_reactivated_count := v_reactivated_count + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'deactivated_count', v_deactivated_count,
    'finished_count', v_finished_count,
    'reactivated_count', v_reactivated_count,
    'affected_encounter_ids', to_jsonb(v_old_encounter_ids)
  );
end;
$$;

create or replace function public.odyssey_apply_weapon_operation_session_cost(
  p_character_id uuid,
  p_operation text,
  p_feed_mode text default null,
  p_expected_session_version integer default null,
  p_encounter_id uuid default null
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_cost_mode text := public.odyssey_get_weapon_operation_cost_mode(
    p_character_id,
    p_operation,
    p_feed_mode
  );
  v_active_encounter_count integer := 0;
  v_participation record;
  v_move_current integer := 0;
  v_move_max integer := 0;
begin
  select count(distinct e.id)
  into v_active_encounter_count
  from public.odyssey_initiative_entries i
  join public.odyssey_combat_encounters e
    on e.id = i.encounter_id
  where i.character_id = p_character_id
    and i.is_active = true
    and e.status = 'active'
    and e.ended_at is null;

  if p_encounter_id is not null then
    select
      e.id as encounter_id,
      e.state_version,
      e.current_round,
      e.active_character_id,
      i.id as entry_id,
      i.action_current,
      i.move_current,
      i.move_max,
      i.reaction_action_current
    into v_participation
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e
      on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.id = p_encounter_id
      and e.status = 'active'
      and e.ended_at is null
    limit 1
    for update of i, e;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'ENCOUNTER_NOT_ACTIVE_FOR_CHARACTER',
        'message', 'The selected encounter is not active for this character.',
        'cost_mode', v_cost_mode,
        'combat_session', null
      );
    end if;
  else
    if v_active_encounter_count > 1 then
      return jsonb_build_object(
        'ok', false,
        'error', 'COMBAT_CONTEXT_AMBIGUOUS',
        'message', 'Multiple active encounters found for this character. Pass encounter_id explicitly.',
        'cost_mode', v_cost_mode,
        'combat_session', null,
        'combat_context', jsonb_build_object(
          'mode', 'ambiguous',
          'active_encounter_count', v_active_encounter_count,
          'warning', 'Multiple active encounters found for this character. Pass encounter_id explicitly.'
        )
      );
    end if;

    select
      e.id as encounter_id,
      e.state_version,
      e.current_round,
      e.active_character_id,
      i.id as entry_id,
      i.action_current,
      i.move_current,
      i.move_max,
      i.reaction_action_current
    into v_participation
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e
      on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.status = 'active'
      and e.ended_at is null
    order by e.created_at desc, e.id desc
    limit 1
    for update of i, e;
  end if;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'spent', false,
      'cost_mode', v_cost_mode,
      'combat_session', null
    );
  end if;

  if p_expected_session_version is not null
     and p_expected_session_version <> coalesce(v_participation.state_version, 0) then
    return jsonb_build_object(
      'ok', false,
      'error', 'STATE_VERSION_CONFLICT',
      'message', 'Combat state changed. Reload authoritative runtime.',
      'encounter_state_version', coalesce(v_participation.state_version, 0)
    );
  end if;

  if coalesce(v_participation.active_character_id = p_character_id, false) = false then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_CURRENT_TURN',
      'message', 'It is not this character''s turn.'
    );
  end if;

  if v_cost_mode = 'free' then
    return jsonb_build_object(
      'ok', true,
      'spent', false,
      'cost_mode', v_cost_mode,
      'combat_session', public.odyssey_build_session_cost_summary(
        jsonb_build_object(
          'encounter_id', v_participation.encounter_id,
          'state_version', v_participation.state_version,
          'current_round', v_participation.current_round,
          'entry_id', v_participation.entry_id
        ),
        false
      )
    );
  end if;

  v_move_current := coalesce(v_participation.move_current, 0);
  v_move_max := coalesce(v_participation.move_max, 0);

  if v_move_max <= 0 or v_move_current < v_move_max then
    return jsonb_build_object(
      'ok', false,
      'error', 'FULL_MOVE_NOT_AVAILABLE',
      'message', 'FULL MOVE is already spent.'
    );
  end if;

  perform public.odyssey_apply_turn_costs(
    v_participation.entry_id,
    0,
    v_move_current,
    false
  );
  perform public.odyssey_increment_encounter_state_version(v_participation.encounter_id);

  return jsonb_build_object(
    'ok', true,
    'spent', true,
    'cost_mode', v_cost_mode,
    'combat_session', public.odyssey_build_session_cost_summary(
      jsonb_build_object(
        'encounter_id', v_participation.encounter_id,
        'state_version', v_participation.state_version,
        'current_round', v_participation.current_round,
        'entry_id', v_participation.entry_id
      ),
      false
    )
  );
end;
$$;

create or replace function public.odyssey_apply_weapon_operation_session_cost(
  p_character_id uuid,
  p_operation text,
  p_feed_mode text default null,
  p_expected_session_version integer default null
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
begin
  return public.odyssey_apply_weapon_operation_session_cost(
    p_character_id,
    p_operation,
    p_feed_mode,
    p_expected_session_version,
    null::uuid
  );
end;
$$;

do $$
declare
  v_row record;
begin
  for v_row in
    with ranked as (
      select
        i.character_id,
        i.encounter_id,
        row_number() over (
          partition by i.character_id
          order by e.created_at desc, e.id desc
        ) as rn,
        count(*) over (partition by i.character_id) as active_count
      from public.odyssey_initiative_entries i
      join public.odyssey_combat_encounters e
        on e.id = i.encounter_id
      where i.is_active = true
        and e.status = 'active'
        and e.ended_at is null
    )
    select
      ranked.character_id,
      ranked.encounter_id
    from ranked
    where ranked.rn = 1
      and ranked.active_count > 1
  loop
    perform public.odyssey_cleanup_character_active_participation(
      array[v_row.character_id],
      v_row.encounter_id
    );
  end loop;
end;
$$;

create or replace function public.switch_active_weapon(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(
    coalesce(p_payload->>'character_weapon_id', p_payload->>'weapon_id')
  );
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_encounter_id uuid := public.odyssey_try_parse_uuid(p_payload->>'encounter_id');
  v_weapon public.odyssey_character_weapons%rowtype;
  v_current_active_weapon_id uuid := null;
  v_cost_result jsonb := '{}'::jsonb;
begin
  if v_character_id is null or v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id and character_weapon_id are required.'
    );
  end if;

  select *
  into v_weapon
  from public.odyssey_character_weapons weapon
  where weapon.id = v_character_weapon_id
    and weapon.character_id = v_character_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', 'Weapon was not found for this character.'
    );
  end if;

  v_current_active_weapon_id := public.odyssey_get_character_active_weapon_id(v_character_id);
  if v_current_active_weapon_id = v_character_weapon_id then
    return jsonb_build_object(
      'ok', true,
      'weapon_id', v_character_weapon_id,
      'active_weapon_id', v_character_weapon_id,
      'cost_mode', public.odyssey_get_weapon_operation_cost_mode(v_character_id, 'switch_weapon', null),
      'combat_session', null,
      'armory', public.get_character_armory(v_character_id)
    );
  end if;

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_character_id,
    'switch_weapon',
    null,
    v_expected_session_version,
    v_encounter_id
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
  end if;

  update public.odyssey_character_weapons weapon
  set
    equipped_slot = case
      when weapon.id = v_character_weapon_id then 'primary'
      when v_current_active_weapon_id is not null and weapon.id = v_current_active_weapon_id then 'secondary'
      when weapon.equipped_slot = 'primary' then null
      else weapon.equipped_slot
    end,
    updated_at = timezone('utc', now())
  where weapon.character_id = v_character_id
    and (
      weapon.id = v_character_weapon_id
      or (v_current_active_weapon_id is not null and weapon.id = v_current_active_weapon_id)
      or weapon.equipped_slot = 'primary'
    );

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_character_weapon_id,
    'active_weapon_id', v_character_weapon_id,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'armory', public.get_character_armory(v_character_id)
  );
end;
$$;

create or replace function public.combat_start_encounter(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_name text := coalesce(nullif(trim(coalesce(p_payload->>'name', '')), ''), 'Combat');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(p_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_actor_player_id text := coalesce(nullif(trim(coalesce(p_payload->>'actor_player_id', '')), ''), '');
  v_hidden_token_ids jsonb := coalesce(p_payload->'hidden_token_ids', '[]'::jsonb);
  v_existing public.odyssey_combat_encounters;
  v_encounter_id uuid := null;
  v_entry record;
  v_roll integer := 0;
  v_reaction integer := 0;
  v_new_character_ids uuid[] := array[]::uuid[];
begin
  if not v_actor_is_gm then
    return jsonb_build_object(
      'ok', false,
      'error', 'CONTROL_DENIED',
      'message', 'Only the GM may start an encounter.'
    );
  end if;

  if v_campaign_id = '' or v_room_id = '' or v_scene_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'campaign_id, room_id and scene_id are required.'
    );
  end if;

  select *
  into v_existing
  from public.odyssey_get_active_encounter(v_campaign_id, v_room_id, v_scene_id);

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'ENCOUNTER_ALREADY_ACTIVE',
      'message', 'An active encounter already exists for this scene.',
      'encounter_id', v_existing.id
    );
  end if;

  insert into public.odyssey_combat_encounters (
    campaign_id,
    room_id,
    scene_id,
    name,
    status,
    current_round,
    created_by,
    started_at,
    last_transition_at
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_name,
    'active',
    1,
    coalesce(v_actor_player_id, 'gm'),
    timezone('utc', now()),
    timezone('utc', now())
  )
  returning id into v_encounter_id;

  for v_entry in
    select
      t.token_id,
      t.token_name,
      t.character_id,
      c.character_bucket
    from public.odyssey_token_links t
    join public.odyssey_characters c on c.id = t.character_id
    where t.campaign_id = v_campaign_id
      and t.room_id = v_room_id
      and t.scene_id = v_scene_id
      and t.is_active = true
      and coalesce(c.is_deleted, false) = false
  loop
    if v_entry.character_bucket = 'npc_template' then
      continue;
    end if;

    if v_entry.character_bucket not in ('player', 'npc_active') then
      continue;
    end if;

    v_roll := floor(random() * 20 + 1)::integer;
    v_reaction := public.odyssey_get_character_reaction_value(v_entry.character_id);

    insert into public.odyssey_initiative_entries (
      encounter_id,
      character_id,
      initiative_value,
      reaction_value,
      roll_value,
      bonus_value,
      order_index,
      has_acted,
      is_active,
      action_max,
      action_current,
      move_max,
      move_current,
      reaction_action_max,
      reaction_action_current,
      action_converted_to_move,
      hide_from_initiative_ui,
      joined_round,
      movement_version,
      turn_version
    )
    values (
      v_encounter_id,
      v_entry.character_id,
      v_roll + v_reaction,
      v_reaction,
      v_roll,
      0,
      0,
      false,
      true,
      1,
      1,
      10,
      10,
      0,
      0,
      false,
      exists (
        select 1
        from jsonb_array_elements_text(v_hidden_token_ids) as hidden(token_id)
        where hidden.token_id = v_entry.token_id
      ),
      1,
      0,
      0
    );

    if not (v_entry.character_id = any(v_new_character_ids)) then
      v_new_character_ids := array_append(v_new_character_ids, v_entry.character_id);
    end if;
  end loop;

  perform public.odyssey_cleanup_character_active_participation(
    v_new_character_ids,
    v_encounter_id
  );

  with ranked as (
    select
      e.id,
      row_number() over (
        order by
          e.initiative_value desc,
          case when c.character_bucket = 'player' then 1 else 0 end desc,
          e.roll_value desc,
          e.character_id asc,
          e.id asc
      ) - 1 as next_order_index
    from public.odyssey_initiative_entries e
    join public.odyssey_characters c on c.id = e.character_id
    where e.encounter_id = v_encounter_id
      and e.is_active = true
  )
  update public.odyssey_initiative_entries e
  set order_index = ranked.next_order_index
  from ranked
  where ranked.id = e.id;

  perform public.odyssey_combat_log_insert(
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_encounter_id,
    1,
    null,
    null,
    null,
    'public',
    'encounter_started',
    'Encounter started.',
    jsonb_build_object('name', v_name),
    jsonb_build_object('name', v_name),
    coalesce(v_actor_player_id, 'gm')
  );

  perform public.odyssey_start_next_eligible_turn(v_encounter_id);

  return public.odyssey_build_combat_runtime(
    v_encounter_id,
    v_actor_player_id,
    true,
    true,
    5
  );
end;
$$;

create or replace function public.combat_add_participant(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_encounter_id uuid := public.odyssey_try_parse_uuid(p_payload->>'encounter_id');
  v_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'token_id', '')), ''), '');
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(p_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_hide boolean := coalesce(nullif(trim(coalesce(p_payload->>'hide_from_initiative_ui', '')), '')::boolean, false);
  v_encounter public.odyssey_combat_encounters%rowtype;
  v_link record;
  v_roll integer := 0;
  v_reaction integer := 0;
begin
  if not v_actor_is_gm then
    return jsonb_build_object('ok', false, 'error', 'CONTROL_DENIED', 'message', 'Only the GM may add participants.');
  end if;

  select *
  into v_encounter
  from public.odyssey_combat_encounters
  where id = v_encounter_id
    and status = 'active'
    and ended_at is null
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'ENCOUNTER_NOT_ACTIVE', 'message', 'Encounter is not active.');
  end if;

  select
    t.*,
    c.character_bucket
  into v_link
  from public.odyssey_token_links t
  join public.odyssey_characters c on c.id = t.character_id
  where t.room_id = v_encounter.room_id
    and t.scene_id = v_encounter.scene_id
    and t.is_active = true
    and (
      (v_token_id <> '' and t.token_id = v_token_id)
      or (v_character_id is not null and t.character_id = v_character_id)
    )
  order by t.updated_at desc, t.created_at desc, t.id desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'TOKEN_LINK_REQUIRED', 'message', 'Participant must have an active token link in this scene.');
  end if;

  if v_link.character_bucket = 'npc_template' then
    return jsonb_build_object('ok', false, 'error', 'NPC_TEMPLATE_NOT_ALLOWED', 'message', 'NPC templates cannot join encounters directly.');
  end if;

  if v_link.character_bucket not in ('player', 'npc_active') then
    return jsonb_build_object('ok', false, 'error', 'PARTICIPANT_NOT_ELIGIBLE', 'message', 'Only linked players and active NPCs can join encounters.');
  end if;

  if exists (
    select 1
    from public.odyssey_initiative_entries e
    where e.encounter_id = v_encounter_id
      and e.character_id = v_link.character_id
      and e.is_active = true
  ) then
    return public.odyssey_build_combat_runtime(v_encounter_id, p_payload->>'actor_player_id', true, true, 5);
  end if;

  v_roll := floor(random() * 20 + 1)::integer;
  v_reaction := public.odyssey_get_character_reaction_value(v_link.character_id);

  insert into public.odyssey_initiative_entries (
    encounter_id,
    character_id,
    initiative_value,
    reaction_value,
    roll_value,
    bonus_value,
    order_index,
    has_acted,
    is_active,
    action_max,
    action_current,
    move_max,
    move_current,
    reaction_action_max,
    reaction_action_current,
    action_converted_to_move,
    hide_from_initiative_ui,
    joined_round,
    movement_version,
    turn_version
  )
  values (
    v_encounter_id,
    v_link.character_id,
    v_roll + v_reaction,
    v_reaction,
    v_roll,
    0,
    9999,
    false,
    true,
    1,
    1,
    10,
    10,
    0,
    0,
    false,
    v_hide,
    v_encounter.current_round + 1,
    0,
    0
  );

  perform public.odyssey_cleanup_character_active_participation(
    array[v_link.character_id],
    v_encounter_id
  );

  with ranked as (
    select
      e.id,
      row_number() over (
        order by
          e.initiative_value desc,
          case when c.character_bucket = 'player' then 1 else 0 end desc,
          e.roll_value desc,
          e.character_id asc,
          e.id asc
      ) - 1 as next_order_index
    from public.odyssey_initiative_entries e
    join public.odyssey_characters c on c.id = e.character_id
    where e.encounter_id = v_encounter_id
      and e.is_active = true
  )
  update public.odyssey_initiative_entries e
  set order_index = ranked.next_order_index
  from ranked
  where ranked.id = e.id;

  perform public.odyssey_increment_encounter_state_version(v_encounter_id);

  return public.odyssey_build_combat_runtime(v_encounter_id, p_payload->>'actor_player_id', true, true, 5);
end;
$$;
