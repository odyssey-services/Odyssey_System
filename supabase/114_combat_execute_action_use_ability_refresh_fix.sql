create or replace function public.combat_execute_action(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $body$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_encounter_id uuid := public.odyssey_try_parse_uuid(v_payload->>'encounter_id');
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_kind text := lower(trim(coalesce(v_payload->>'kind', '')));
  v_include_runtime boolean := coalesce(nullif(trim(coalesce(v_payload->>'include_runtime', '')), '')::boolean, false);
  v_actor_player_id text := coalesce(nullif(trim(coalesce(v_payload->>'actor_player_id', '')), ''), '');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(v_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_intent jsonb := case when jsonb_typeof(v_payload->'intent') = 'object' then v_payload->'intent' else '{}'::jsonb end;
  v_encounter public.odyssey_combat_encounters%rowtype;
  v_entry public.odyssey_initiative_entries%rowtype;
  v_control jsonb := '{}'::jsonb;
  v_versions jsonb := '{}'::jsonb;
  v_cost jsonb := '{}'::jsonb;
  v_result jsonb := '{}'::jsonb;
  v_action_cost integer := 0;
  v_move_cost integer := 0;
  v_use_reaction boolean := false;
  v_post_refresh jsonb := '{}'::jsonb;
  v_result_target_character_id uuid := null;
  v_result_character_id uuid := null;
  v_result_combat_state jsonb := '{}'::jsonb;
  v_lock_stage text := 'start';
begin
  perform set_config('lock_timeout', '1500ms', true);

  if v_kind not in ('attack', 'reload', 'ability', 'perk', 'item', 'move') then
    return jsonb_build_object('ok', false, 'error', 'INVALID_ACTION_KIND', 'message', 'Unsupported action kind.');
  end if;

  v_lock_stage := 'lock_encounter';
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

  v_lock_stage := 'lock_initiative_entry';
  select *
  into v_entry
  from public.odyssey_initiative_entries
  where encounter_id = v_encounter_id
    and character_id = v_character_id
    and is_active = true
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'PARTICIPANT_NOT_FOUND', 'message', 'Participant was not found.');
  end if;

  v_control := public.odyssey_can_control_character(v_character_id, v_actor_player_id, v_actor_is_gm);
  if coalesce((v_control->>'allowed')::boolean, false) = false then
    return jsonb_build_object('ok', false, 'error', 'CONTROL_DENIED', 'message', 'You cannot control this participant.');
  end if;

  if v_encounter.active_entry_id is distinct from v_entry.id then
    if coalesce(v_entry.reaction_action_current, 0) > 0 then
      v_use_reaction := true;
    else
      return jsonb_build_object('ok', false, 'error', 'NOT_CURRENT_TURN', 'message', 'It is not this participant''s turn.');
    end if;
  end if;

  v_lock_stage := 'validate_versions';
  v_versions := public.odyssey_validate_combat_versions(
    v_encounter_id,
    nullif(trim(coalesce(v_payload->>'expected_encounter_version', '')), '')::integer,
    v_character_id,
    nullif(trim(coalesce(v_payload->>'expected_character_state_version', '')), '')::integer
  );
  if coalesce((v_versions->>'ok')::boolean, false) = false then
    return v_versions;
  end if;

  v_cost := public.odyssey_get_combat_action_cost_context(
    v_encounter_id,
    v_character_id,
    v_kind,
    case when v_kind in ('ability', 'perk', 'item') then v_kind else null end,
    public.odyssey_try_parse_uuid(coalesce(v_intent->>'character_ability_id', v_intent->>'character_perk_id', v_intent->>'character_item_id')),
    v_intent
  );

  v_action_cost := greatest(coalesce(nullif(trim(coalesce(v_cost->>'action_cost', '')), '')::integer, 0), 0);
  v_move_cost := greatest(coalesce(nullif(trim(coalesce(v_cost->>'move_cost', '')), '')::integer, 0), 0);

  if not v_use_reaction and coalesce(v_entry.action_current, 0) < v_action_cost then
    return jsonb_build_object('ok', false, 'error', 'ACTION_NOT_AVAILABLE', 'message', 'Not enough ACTION is available.');
  end if;

  if coalesce(v_entry.move_current, 0) < v_move_cost then
    return jsonb_build_object('ok', false, 'error', 'MOVE_NOT_AVAILABLE', 'message', 'Not enough MOVE is available.');
  end if;

  if v_use_reaction and coalesce(v_entry.reaction_action_current, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'REACTION_NOT_AVAILABLE', 'message', 'No reaction action is available.');
  end if;

  v_lock_stage := 'execute_action';
  case v_kind
    when 'attack' then
      v_result := public.perform_attack(
        v_intent
        || jsonb_build_object(
          'encounter_id', v_encounter_id,
          'attacker_character_id', v_character_id
        )
      );
    when 'reload' then
      v_result := public.load_weapon_profile_magazine(v_intent);
    when 'ability' then
      v_result := public.use_ability(v_intent || jsonb_build_object('encounter_id', v_encounter_id));
    when 'perk' then
      v_result := public.use_character_perk(v_intent || jsonb_build_object('encounter_id', v_encounter_id));
    when 'item' then
      v_result := public.use_character_item(v_intent || jsonb_build_object('encounter_id', v_encounter_id));
    when 'move' then
      v_result := public.combat_spend_move(
        jsonb_build_object(
          'encounter_id', v_encounter_id,
          'character_id', v_character_id,
          'actor_player_id', v_actor_player_id,
          'actor_is_gm', v_actor_is_gm,
          'move_cost', v_move_cost
        ) || v_intent
      );
  end case;

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  if v_kind <> 'move' then
    perform public.odyssey_apply_turn_costs(v_entry.id, v_action_cost, v_move_cost, v_use_reaction);
    perform public.odyssey_increment_encounter_state_version(v_encounter_id);
  end if;

  v_result_target_character_id := public.odyssey_try_parse_uuid(v_result->>'target_character_id');
  v_result_character_id := coalesce(
    public.odyssey_try_parse_uuid(v_result->>'character_id'),
    public.odyssey_try_parse_uuid(v_result#>>'{combat_state,character_id}')
  );
  v_result_combat_state := case
    when jsonb_typeof(v_result->'combat_state') = 'object' then v_result->'combat_state'
    else '{}'::jsonb
  end;

  v_lock_stage := 'refresh_character_combat_state';
  if v_kind = 'ability'
     and v_result_character_id = v_character_id
     and v_result_combat_state <> '{}'::jsonb then
    v_post_refresh := jsonb_build_object(
      'ok', true,
      'character_id', v_character_id,
      'combat_state', v_result_combat_state,
      'state_version', nullif(v_result#>>'{combat_state,state_version}', '')::integer
    );
  else
    v_post_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
  end if;

  if v_kind = 'perk'
     and coalesce(nullif(v_result->>'force_end_turn', '')::boolean, false)
     and not v_use_reaction then
    perform public.odyssey_start_next_eligible_turn(v_encounter_id);
  end if;

  v_lock_stage := 'build_runtime';
  return jsonb_build_object(
    'ok', true,
    'encounter_state_version', (select state_version from public.odyssey_combat_encounters where id = v_encounter_id),
    'character_state_version', coalesce((v_post_refresh->>'state_version')::integer, null),
    'spent',
      jsonb_build_object(
        'action_cost', v_action_cost,
        'move_cost', v_move_cost,
        'used_reaction', v_use_reaction
      ),
    'result', v_result,
    'acting_combat_state', coalesce(v_post_refresh->'combat_state', '{}'::jsonb),
    'runtime', case
      when v_include_runtime then public.odyssey_build_combat_runtime(v_encounter_id, v_actor_player_id, v_actor_is_gm, v_actor_is_gm, 5)
      else null
    end
  );
exception
  when lock_not_available then
    return jsonb_build_object(
      'ok', false,
      'error', 'ACTION_BUSY_RETRY',
      'message', 'Character state is busy. Please retry.',
      'stage', v_lock_stage
    );
  when query_canceled then
    if SQLERRM ilike '%statement timeout%' or SQLERRM ilike '%lock timeout%' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ACTION_BUSY_RETRY',
        'message', 'Character state is busy. Please retry.',
        'stage', v_lock_stage
      );
    end if;
    raise;
end;
$body$;
