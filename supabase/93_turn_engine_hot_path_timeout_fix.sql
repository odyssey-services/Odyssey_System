create or replace function public.odyssey_start_next_eligible_turn(
  p_encounter_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_encounter public.odyssey_combat_encounters%rowtype;
  v_entry_ids uuid[] := array[]::uuid[];
  v_entry_count integer := 0;
  v_current_pos integer := -1;
  v_candidate_pos integer := -1;
  v_loops integer := 0;
  v_now timestamptz := timezone('utc', now());
  v_candidate public.odyssey_initiative_entries%rowtype;
  v_skip_turn boolean := false;
  v_wrapped boolean := false;
  v_round_for_candidate integer := 1;
  v_candidate_is_alive boolean := true;
  v_candidate_is_conscious boolean := true;
begin
  select *
  into v_encounter
  from public.odyssey_combat_encounters
  where id = p_encounter_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ENCOUNTER_NOT_FOUND',
      'message', 'Encounter was not found.'
    );
  end if;

  if v_encounter.status <> 'active' or v_encounter.ended_at is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'ENCOUNTER_NOT_ACTIVE',
      'message', 'Encounter is not active.'
    );
  end if;

  select coalesce(array_agg(e.id order by e.order_index, e.created_at, e.id), array[]::uuid[])
  into v_entry_ids
  from public.odyssey_initiative_entries e
  where e.encounter_id = p_encounter_id
    and e.is_active = true;

  v_entry_count := cardinality(v_entry_ids);
  if v_entry_count = 0 then
    update public.odyssey_combat_encounters
    set
      active_entry_id = null,
      active_character_id = null
    where id = p_encounter_id;

    perform public.odyssey_increment_encounter_state_version(p_encounter_id);

    return jsonb_build_object(
      'ok', true,
      'encounter_id', p_encounter_id,
      'active_entry', null
    );
  end if;

  if v_encounter.active_entry_id is not null then
    select ordinality - 1
    into v_current_pos
    from unnest(v_entry_ids) with ordinality as t(entry_id, ordinality)
    where t.entry_id = v_encounter.active_entry_id
    limit 1;
  end if;

  loop
    exit when v_loops >= v_entry_count + 1;
    v_candidate_pos := coalesce(v_current_pos, -1) + 1;
    if v_candidate_pos >= v_entry_count then
      v_candidate_pos := 0;
      v_wrapped := true;
      update public.odyssey_combat_encounters
      set current_round = current_round + 1
      where id = p_encounter_id
      returning current_round into v_round_for_candidate;
    else
      v_round_for_candidate := v_encounter.current_round;
    end if;

    select *
    into v_candidate
    from public.odyssey_initiative_entries e
    where e.id = v_entry_ids[v_candidate_pos + 1]
    for update;

    if not found then
      v_current_pos := v_candidate_pos;
      v_loops := v_loops + 1;
      continue;
    end if;

    if v_candidate.joined_round > v_round_for_candidate then
      v_current_pos := v_candidate_pos;
      v_loops := v_loops + 1;
      continue;
    end if;

    update public.odyssey_initiative_entries
    set
      action_current = action_max,
      move_current = move_max,
      reaction_action_current = reaction_action_max,
      action_converted_to_move = false,
      turn_version = coalesce(turn_version, 0) + 1,
      last_turn_started_at = v_now
    where id = v_candidate.id
    returning * into v_candidate;

    select
      coalesce(s.is_alive, true),
      coalesce(s.is_conscious, true)
    into
      v_candidate_is_alive,
      v_candidate_is_conscious
    from public.odyssey_character_combat_state s
    where s.character_id = v_candidate.character_id;

    if not found then
      v_candidate_is_alive := true;
      v_candidate_is_conscious := true;
    end if;

    v_skip_turn := public.odyssey_character_has_active_effect_flag(v_candidate.character_id, 'skip_turn');

    if v_candidate_is_alive = false then
      update public.odyssey_initiative_entries
      set
        is_active = false,
        removed_at = v_now,
        removed_reason = 'dead'
      where id = v_candidate.id;

      perform public.odyssey_combat_log_insert(
        v_encounter.campaign_id,
        v_encounter.room_id,
        v_encounter.scene_id,
        v_encounter.id,
        v_round_for_candidate,
        null,
        v_candidate.character_id,
        v_candidate.character_id,
        'gm_only',
        'system',
        public.odyssey_character_display_name(v_candidate.character_id) || ' is removed from initiative because they are dead.',
        jsonb_build_object('reason', 'dead', 'character_id', v_candidate.character_id),
        jsonb_build_object('reason', 'dead'),
        'system'
      );

      v_current_pos := v_candidate_pos;
      v_loops := v_loops + 1;
      continue;
    end if;

    if v_candidate_is_conscious = false or v_skip_turn then
      perform public.odyssey_combat_log_insert(
        v_encounter.campaign_id,
        v_encounter.room_id,
        v_encounter.scene_id,
        v_encounter.id,
        v_round_for_candidate,
        null,
        v_candidate.character_id,
        v_candidate.character_id,
        case when v_candidate.hide_from_initiative_ui then 'gm_only' else 'public' end,
        'turn_skipped',
        public.odyssey_character_display_name(v_candidate.character_id) || ' cannot act this turn.',
        jsonb_build_object(
          'reason', case when v_skip_turn then 'skip_turn' else 'unconscious' end,
          'character_id', v_candidate.character_id
        ),
        jsonb_build_object(
          'reason', case when v_skip_turn then 'skip_turn' else 'unconscious' end
        ),
        'system'
      );

      v_current_pos := v_candidate_pos;
      v_loops := v_loops + 1;
      continue;
    end if;

    update public.odyssey_combat_encounters
    set
      active_entry_id = v_candidate.id,
      active_character_id = v_candidate.character_id,
      current_round = v_round_for_candidate,
      last_transition_at = v_now
    where id = p_encounter_id;

    perform public.odyssey_increment_encounter_state_version(p_encounter_id);

    perform public.odyssey_combat_log_insert(
      v_encounter.campaign_id,
      v_encounter.room_id,
      v_encounter.scene_id,
      v_encounter.id,
      v_round_for_candidate,
      v_candidate.character_id,
      null,
      v_candidate.character_id,
      case when v_candidate.hide_from_initiative_ui then 'gm_only' else 'public' end,
      'turn_started',
      public.odyssey_character_display_name(v_candidate.character_id) || ' starts their turn.',
      jsonb_build_object(
        'initiative_entry_id', v_candidate.id,
        'character_id', v_candidate.character_id,
        'wrapped', v_wrapped
      ),
      jsonb_build_object(
        'initiative_entry_id', v_candidate.id,
        'character_id', v_candidate.character_id,
        'wrapped', v_wrapped
      ),
      'system'
    );

    return jsonb_build_object(
      'ok', true,
      'encounter_id', p_encounter_id,
      'active_entry_id', v_candidate.id,
      'active_character_id', v_candidate.character_id,
      'current_round', v_round_for_candidate
    );
  end loop;

  update public.odyssey_combat_encounters
  set
    active_entry_id = null,
    active_character_id = null
  where id = p_encounter_id;

  perform public.odyssey_increment_encounter_state_version(p_encounter_id);

  return jsonb_build_object(
    'ok', true,
    'encounter_id', p_encounter_id,
    'active_entry_id', null,
    'active_character_id', null,
    'message', 'No eligible turn target was found.'
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
  v_excluded_character_ids jsonb := coalesce(p_payload->'excluded_character_ids', '[]'::jsonb);
  v_existing public.odyssey_combat_encounters;
  v_encounter_id uuid := null;
  v_candidates jsonb := '[]'::jsonb;
  v_candidate_count integer := 0;
  v_missing_reaction_character_id uuid := null;
  v_missing_reaction_display_name text := '';
  v_start_turn jsonb := '{}'::jsonb;
  v_encounter_row public.odyssey_combat_encounters%rowtype;
  v_viewer_character_ids uuid[] := array[]::uuid[];
  v_current_turn jsonb := null;
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

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'token_id', candidate.token_id,
          'token_name', candidate.token_name,
          'character_id', candidate.character_id,
          'character_bucket', candidate.character_bucket,
          'reaction_value', candidate.reaction_value
        )
        order by candidate.character_id
      ),
      '[]'::jsonb
    ),
    count(*),
    (
      array_agg(candidate.character_id order by candidate.character_id)
      filter (where candidate.reaction_value is null)
    )[1]
  into
    v_candidates,
    v_candidate_count,
    v_missing_reaction_character_id
  from (
    select distinct on (t.character_id)
      t.token_id,
      t.token_name,
      t.character_id,
      c.character_bucket,
      public.odyssey_get_character_reaction_value_strict(t.character_id) as reaction_value
    from public.odyssey_token_links t
    join public.odyssey_characters c on c.id = t.character_id
    where t.campaign_id = v_campaign_id
      and t.room_id = v_room_id
      and t.scene_id = v_scene_id
      and t.is_active = true
      and coalesce(c.is_deleted, false) = false
      and c.character_bucket in ('player', 'npc_active')
      and not exists (
        select 1
        from jsonb_array_elements_text(v_excluded_character_ids) as excluded(character_id)
        where public.odyssey_try_parse_uuid(excluded.character_id) = t.character_id
      )
    order by t.character_id, t.updated_at desc, t.created_at desc, t.id desc
  ) candidate;

  if v_candidate_count = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_PARTICIPANTS',
      'message', 'No linked, eligible characters remain for this scene.'
    );
  end if;

  if v_missing_reaction_character_id is not null then
    v_missing_reaction_display_name := public.odyssey_character_display_name(v_missing_reaction_character_id);
    return jsonb_build_object(
      'ok', false,
      'error', 'REACTION_UNAVAILABLE',
      'message', v_missing_reaction_display_name
        || ' has no Reaction attribute in effective stats; combat cannot start.',
      'character_id', v_missing_reaction_character_id
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
  select
    v_encounter_id,
    candidate.character_id,
    candidate.roll_value + candidate.reaction_value,
    candidate.reaction_value,
    candidate.roll_value,
    0,
    0,
    false,
    true,
    1,
    1,
    1,
    1,
    0,
    0,
    false,
    exists (
      select 1
      from jsonb_array_elements_text(v_hidden_token_ids) as hidden(token_id)
      where hidden.token_id = candidate.token_id
    ),
    1,
    0,
    0
  from (
    select
      entry.token_id,
      entry.character_id,
      coalesce(entry.reaction_value, 0) as reaction_value,
      floor(random() * 20 + 1)::integer as roll_value
    from jsonb_to_recordset(v_candidates) as entry(
      token_id text,
      token_name text,
      character_id uuid,
      character_bucket text,
      reaction_value integer
    )
  ) candidate
  on conflict on constraint odyssey_initiative_entries_encounter_character_key do nothing;

  perform public.odyssey_reroll_full_initiative_ties(v_encounter_id);

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

  v_start_turn := public.odyssey_start_next_eligible_turn(v_encounter_id);
  if coalesce((v_start_turn->>'ok')::boolean, false) = false then
    return v_start_turn;
  end if;

  select *
  into v_encounter_row
  from public.odyssey_combat_encounters
  where id = v_encounter_id;

  if v_actor_player_id <> '' then
    select coalesce(array_agg(c.id), array[]::uuid[])
    into v_viewer_character_ids
    from public.odyssey_characters c
    where coalesce(c.is_deleted, false) = false
      and c.owner_player_id = v_actor_player_id;
  end if;

  if v_encounter_row.active_entry_id is not null then
    select
      jsonb_build_object(
        'initiative_entry_id', e.id,
        'character_id', c.id,
        'character_key', c.character_key,
        'display_name', public.odyssey_character_display_name(c.id),
        'character_bucket', c.character_bucket,
        'owner_player_id', c.owner_player_id,
        'owner_player_name', c.owner_player_name,
        'initiative_value', e.initiative_value,
        'reaction_value', e.reaction_value,
        'roll_value', e.roll_value,
        'bonus_value', e.bonus_value,
        'order_index', e.order_index,
        'is_active', e.is_active,
        'is_current_turn', true,
        'action_current', e.action_current,
        'action_max', e.action_max,
        'move_current', e.move_current,
        'move_max', e.move_max,
        'reaction_action_current', e.reaction_action_current,
        'reaction_action_max', e.reaction_action_max,
        'action_converted_to_move', e.action_converted_to_move,
        'hide_from_initiative_ui', e.hide_from_initiative_ui,
        'joined_round', e.joined_round,
        'movement_version', e.movement_version,
        'turn_version', e.turn_version,
        'removed_at', e.removed_at,
        'removed_reason', e.removed_reason,
        'control', public.odyssey_can_control_character(c.id, v_actor_player_id, true),
        'state',
          jsonb_build_object(
            'state_version', coalesce(s.state_version, c.active_combat_state_version, 0),
            'status_summary', coalesce(nullif(trim(s.status_summary), ''), public.odyssey_build_character_status_summary(c.id)),
            'is_alive', coalesce(s.is_alive, true),
            'is_conscious', coalesce(s.is_conscious, true)
          )
      )
    into v_current_turn
    from public.odyssey_initiative_entries e
    join public.odyssey_characters c on c.id = e.character_id
    left join public.odyssey_character_combat_state s on s.character_id = c.id
    where e.id = v_encounter_row.active_entry_id
    limit 1;
  end if;

  return jsonb_build_object(
    'ok', true,
    'partial_refresh_required', true,
    'encounter',
      jsonb_build_object(
        'id', v_encounter_row.id,
        'campaign_id', v_encounter_row.campaign_id,
        'room_id', v_encounter_row.room_id,
        'scene_id', v_encounter_row.scene_id,
        'name', v_encounter_row.name,
        'status', v_encounter_row.status,
        'current_round', v_encounter_row.current_round,
        'active_character_id', v_encounter_row.active_character_id,
        'active_entry_id', v_encounter_row.active_entry_id,
        'state_version', v_encounter_row.state_version,
        'action_default', v_encounter_row.action_default,
        'move_default', v_encounter_row.move_default,
        'started_at', v_encounter_row.started_at,
        'last_transition_at', v_encounter_row.last_transition_at
      ),
    'current_turn', v_current_turn,
    'visible_participants',
      case
        when v_current_turn is null then '[]'::jsonb
        else jsonb_build_array(v_current_turn)
      end,
    'viewer_controlled_character_ids', to_jsonb(v_viewer_character_ids),
    'log', '[]'::jsonb,
    'state_version', coalesce(v_encounter_row.state_version, 0),
    'turn_result', v_start_turn
  );
end;
$$;
