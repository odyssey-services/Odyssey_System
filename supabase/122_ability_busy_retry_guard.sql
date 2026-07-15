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
    if coalesce(v_result->>'error', '') = 'ACTION_BUSY_RETRY'
       and nullif(trim(coalesce(v_result->>'stage', '')), '') is null then
      return v_result || jsonb_build_object('stage', v_lock_stage);
    end if;
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

  v_stage := 'refresh_character_combat_state';
  v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_ability.character_id)->'combat_state', '{}'::jsonb);

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
