create or replace function public.odyssey_apply_resolved_body_damage(
  p_body_part_id uuid,
  p_minor_delta integer,
  p_serious_delta integer,
  p_critical_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_body_part record;
  v_requested_minor integer := greatest(coalesce(p_minor_delta, 0), 0);
  v_requested_serious integer := greatest(coalesce(p_serious_delta, 0), 0);
  v_requested_critical integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_body_minor_delta integer := 0;
  v_body_serious_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_armor_minor_absorbed integer := 0;
  v_armor_serious_absorbed integer := 0;
  v_armor_critical_absorbed integer := 0;
  v_armor_item_updates jsonb := '[]'::jsonb;
  v_armor_result jsonb := '{}'::jsonb;
  v_body_state jsonb := '{}'::jsonb;
  v_next_minor integer := 0;
  v_next_serious integer := 0;
  v_next_critical integer := 0;
  v_next_disabled boolean := false;
  v_next_destroyed boolean := false;
  v_has_body_delta boolean := false;
  v_armor_items_changed boolean := false;
begin
  select
    b.id,
    b.character_id,
    b.minor,
    b.serious,
    b.critical,
    b.max_critical,
    b.disabled,
    b.destroyed
  into v_body_part
  from public.odyssey_character_body_parts b
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'message', 'Body part was not found.',
      'body_part_id', p_body_part_id
    );
  end if;

  if v_requested_minor > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'minor',
      v_requested_minor
    );
    v_armor_minor_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_minor_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_minor - v_armor_minor_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  if v_requested_serious > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'serious',
      v_requested_serious
    );
    v_armor_serious_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_serious_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_serious - v_armor_serious_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  if v_requested_critical > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'critical',
      v_requested_critical
    );
    v_armor_critical_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_critical_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_critical - v_armor_critical_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  v_has_body_delta :=
    v_body_minor_delta > 0
    or v_body_serious_delta > 0
    or v_body_critical_delta > 0;

  if v_has_body_delta then
    v_next_minor := coalesce(v_body_part.minor, 0) + v_body_minor_delta;
    v_next_serious := coalesce(v_body_part.serious, 0) + v_body_serious_delta;
    v_next_critical := coalesce(v_body_part.critical, 0) + v_body_critical_delta;
    v_next_destroyed := coalesce(v_body_part.destroyed, false)
      or (
        coalesce(v_body_part.max_critical, 0) > 0
        and v_next_critical >= coalesce(v_body_part.max_critical, 0)
      );
    v_next_disabled := coalesce(v_body_part.disabled, false)
      or v_next_critical > 0
      or v_next_destroyed;

    update public.odyssey_character_body_parts
    set
      minor = v_next_minor,
      serious = v_next_serious,
      critical = v_next_critical,
      disabled = v_next_disabled,
      destroyed = v_next_destroyed
    where id = p_body_part_id;

    perform public.odyssey_normalize_body_part_damage(p_body_part_id);
  end if;

  if v_armor_items_changed then
    perform public.recompute_character_armor(v_body_part.character_id);
  end if;

  v_body_state := coalesce(public.odyssey_get_character_body_part_state(p_body_part_id), '{}'::jsonb);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_body_part.character_id,
    'body_part_id', p_body_part_id,
    'raw_minor_delta', v_requested_minor,
    'raw_serious_delta', v_requested_serious,
    'raw_critical_delta', v_requested_critical,
    'body_minor_delta', v_body_minor_delta,
    'body_serious_delta', v_body_serious_delta,
    'body_critical_delta', v_body_critical_delta,
    'armor_minor_absorbed', v_armor_minor_absorbed,
    'armor_serious_absorbed', v_armor_serious_absorbed,
    'armor_critical_absorbed', v_armor_critical_absorbed,
    'armor_item_updates', v_armor_item_updates,
    'body_part', v_body_state,
    'body_changed', v_has_body_delta,
    'armor_changed', v_armor_items_changed,
    'effects_changed', false,
    'target_state', '{}'::jsonb
  );
end;
$$;

create or replace function public.odyssey_apply_perk_post_attack_hooks(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_attacker_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'attacker_character_id');
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_target_alive_before boolean := coalesce(nullif(trim(coalesce(p_payload->>'target_alive_before', '')), '')::boolean, true);
  v_target_alive_after boolean := coalesce(nullif(trim(coalesce(p_payload->>'target_alive_after', '')), '')::boolean, true);
  v_has_calibrating boolean := false;
  v_attacker_changed boolean := false;
begin
  if v_attacker_character_id is null or v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', true,
      'applied', false,
      'attacker_changed', false,
      'target_changed', false,
      'changed_effect_ids', '[]'::jsonb,
      'changed_weapon_ids', '[]'::jsonb
    );
  end if;

  update public.odyssey_character_effects
  set
    is_active = false,
    rounds_left = 0,
    updated_at = timezone('utc', now())
  where character_id = v_attacker_character_id
    and is_active = true
    and coalesce(data->>'character_weapon_id', '') = v_character_weapon_id::text
    and coalesce(data->>'perk_code', '') = 'patient_hunter';

  if found then
    v_attacker_changed := true;
  end if;

  if v_target_alive_before and not v_target_alive_after then
    select exists(
      select 1
      from public.odyssey_character_perks owned
      join public.odyssey_perk_defs perk on perk.id = owned.perk_def_id
      where owned.character_id = v_attacker_character_id
        and perk.code = 'calibrating'
        and coalesce(perk.is_enabled, true) = true
    )
    into v_has_calibrating;

    if v_has_calibrating then
      update public.odyssey_character_weapons
      set data = jsonb_set(
        jsonb_set(
          coalesce(data, '{}'::jsonb),
          '{perk_modifiers,calibrating,kill_count}',
          to_jsonb(
            coalesce(nullif(data#>>'{perk_modifiers,calibrating,kill_count}', '')::integer, 0) + 1
          ),
          true
        ),
        '{perk_modifiers,calibrating,accuracy_bonus}',
        to_jsonb(
          coalesce(nullif(data#>>'{perk_modifiers,calibrating,accuracy_bonus}', '')::integer, 0) + 1
        ),
        true
      )
      where id = v_character_weapon_id;

      v_attacker_changed := true;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'applied', v_attacker_changed,
    'attacker_changed', v_attacker_changed,
    'target_changed', false,
    'changed_effect_ids', '[]'::jsonb,
    'changed_weapon_ids', case when v_has_calibrating then jsonb_build_array(v_character_weapon_id) else '[]'::jsonb end
  );
end;
$$;

create or replace function public.odyssey_finalize_attack_result(
  p_result jsonb,
  p_target_character_id uuid,
  p_target_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb := coalesce(p_result, '{}'::jsonb);
  v_body_part jsonb := case
    when jsonb_typeof(v_result->'body_part') = 'object' then v_result->'body_part'
    else '{}'::jsonb
  end;
  v_pending_checks jsonb := case
    when jsonb_typeof(v_result->'pending_checks') = 'array' then v_result->'pending_checks'
    else '[]'::jsonb
  end;
  v_execution jsonb := case
    when jsonb_typeof(v_result->'execution') = 'object' then v_result->'execution'
    else '{}'::jsonb
  end;
  v_auto text := null;
  v_attack_roll integer := 0;
  v_hit boolean := false;
  v_body_critical_delta integer := 0;
  v_possible_death boolean := false;
  v_should_recalc_caps boolean := false;
begin
  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  v_attack_roll := coalesce(nullif(jsonb_extract_path_text(v_result, 'attack', 'roll'), '')::integer, 0);
  v_hit := coalesce((v_result->>'hit')::boolean, false);
  v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_critical_delta'), '')::integer, 0);
  v_should_recalc_caps :=
    coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_minor_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_serious_delta'), '')::integer, 0) > 0
    or v_body_critical_delta > 0;

  if p_target_character_id is not null and v_should_recalc_caps then
    perform public.odyssey_recalculate_character_body_part_caps(p_target_character_id);
  end if;

  if p_target_body_part_id is not null then
    v_body_part := coalesce(public.odyssey_get_character_body_part_state(p_target_body_part_id), v_body_part, '{}'::jsonb);
  end if;

  if v_hit and v_attack_roll >= 95 then
    v_auto := 'crit';
  elsif v_attack_roll > 0 and v_attack_roll <= 5 then
    v_auto := 'fail';
  end if;

  if v_body_critical_delta > 0 then
    v_pending_checks := v_pending_checks || jsonb_build_array(
      jsonb_build_object(
        'type', 'manual_check',
        'skill_code', 'endurance',
        'reason', 'critical_damage',
        'message', 'Resolve an Endurance check manually because body critical damage was applied.'
      )
    );
  end if;

  v_possible_death :=
    coalesce(nullif(jsonb_extract_path_text(v_body_part, 'destroyed'), '')::boolean, false)
    and lower(coalesce(jsonb_extract_path_text(v_body_part, 'code'), '')) in ('head', 'torso');

  if v_possible_death then
    v_execution := v_execution || jsonb_build_object(
      'fatal_triggered', true,
      'death_application_suppressed', true
    );

    v_pending_checks := v_pending_checks || jsonb_build_array(
      jsonb_build_object(
        'type', 'manual_check',
        'reason', 'possible_death',
        'message', 'Death was not applied automatically. Resolve manually.'
      )
    );
  end if;

  return v_result
    || jsonb_build_object(
      'body_part', v_body_part,
      'auto', to_jsonb(v_auto),
      'pending_checks', v_pending_checks
    )
    || case
      when jsonb_typeof(v_execution) = 'object' and v_execution <> '{}'::jsonb
        then jsonb_build_object('execution', v_execution)
      else '{}'::jsonb
    end;
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_ability_id');
  v_ability_code text := lower(trim(coalesce(v_payload->>'ability_code', '')));
  v_attacker_character_id uuid := public.odyssey_try_parse_uuid(coalesce(v_payload->>'attacker_character_id', v_payload->>'character_id'));
  v_target_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_body_part_id');
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(coalesce(v_payload->>'character_weapon_id', v_payload->>'weapon_id'));
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(v_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_encounter_id uuid := public.odyssey_try_parse_uuid(v_payload->>'encounter_id');
  v_debug boolean := coalesce(nullif(trim(coalesce(v_payload->>'debug', '')), '')::boolean, false);
  v_lock_state jsonb := '{}'::jsonb;
  v_perk_context_result jsonb := jsonb_build_object(
    'ok', true,
    'attack_accuracy_bonus', 0,
    'ammo_base_damage_multiplier', 1,
    'flags', '{}'::jsonb,
    'perk_modifiers', '[]'::jsonb,
    'consume_effect_ids', '[]'::jsonb
  );
  v_attack_context jsonb := '{}'::jsonb;
  v_existing_bonus integer := 0;
  v_perk_bonus integer := 0;
  v_result jsonb := '{}'::jsonb;
  v_retry_effect jsonb := jsonb_build_object('ok', true, 'applied', false);
  v_post_hooks jsonb := jsonb_build_object(
    'ok', true,
    'attacker_changed', false,
    'target_changed', false,
    'changed_effect_ids', '[]'::jsonb,
    'changed_weapon_ids', '[]'::jsonb
  );
  v_refresh_attacker boolean := false;
  v_refresh_target boolean := false;
  v_target_alive_before boolean := true;
  v_target_alive_after boolean := true;
  v_target_movement_version integer := 0;
  v_finalized jsonb := '{}'::jsonb;
  v_attacker_refresh_result jsonb := '{}'::jsonb;
  v_target_refresh_result jsonb := '{}'::jsonb;
  v_started_at timestamptz := clock_timestamp();
  v_stage_started_at timestamptz := clock_timestamp();
  v_weapon_validation_ms numeric := 0;
  v_damage_apply_ms numeric := 0;
  v_perk_hooks_ms numeric := 0;
  v_final_refresh_attacker_ms numeric := 0;
  v_final_refresh_target_ms numeric := 0;
  v_finalize_result_ms numeric := 0;
begin
  if v_target_character_id is not null then
    select coalesce(s.is_alive, true)
    into v_target_alive_before
    from public.odyssey_character_combat_state s
    where s.character_id = v_target_character_id;

    if v_encounter_id is not null then
      select coalesce(e.movement_version, 0)
      into v_target_movement_version
      from public.odyssey_initiative_entries e
      where e.encounter_id = v_encounter_id
        and e.character_id = v_target_character_id
        and e.is_active = true
      order by e.updated_at desc, e.id desc
      limit 1;
    end if;
  end if;

  if v_character_ability_id is not null or v_ability_code <> '' then
    return public.odyssey_perform_ability_attack(v_payload);
  end if;

  v_stage_started_at := clock_timestamp();

  if v_attacker_character_id is not null and v_character_weapon_id is not null then
    v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_character_weapon_id);
    if coalesce((v_lock_state->>'locked')::boolean, false)
       or coalesce((v_lock_state->>'actor_attack_locked')::boolean, false) then
      return jsonb_build_object(
        'ok', false,
        'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
        'message', coalesce(v_lock_state->>'message', 'Weapon is currently locked.'),
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_perk_context_result := public.odyssey_get_character_attack_perk_context(
      v_attacker_character_id,
      v_character_weapon_id,
      v_target_character_id,
      v_target_body_part_id,
      v_distance_m,
      nullif(trim(coalesce(v_payload->>'fire_mode_code', '')), ''),
      nullif(trim(coalesce(v_payload->>'attack_type', '')), ''),
      v_encounter_id
    );

    if coalesce((v_perk_context_result->>'ok')::boolean, false) = false then
      return v_perk_context_result;
    end if;
  end if;

  v_weapon_validation_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;

  v_attack_context := case
    when jsonb_typeof(v_payload->'attack_context') = 'object' then v_payload->'attack_context'
    else '{}'::jsonb
  end;
  v_existing_bonus := coalesce(nullif(trim(coalesce(v_attack_context->>'manual_attack_bonus', '')), '')::integer, 0);
  v_perk_bonus := coalesce(nullif(trim(coalesce(v_perk_context_result->>'attack_accuracy_bonus', '')), '')::integer, 0);

  if v_perk_bonus <> 0 then
    v_attack_context := v_attack_context || jsonb_build_object('manual_attack_bonus', v_existing_bonus + v_perk_bonus);
    v_payload := v_payload || jsonb_build_object('attack_context', v_attack_context);
  end if;

  v_payload := v_payload || jsonb_build_object('perk_context', v_perk_context_result - 'ok');

  v_stage_started_at := clock_timestamp();
  v_result := public.odyssey_perform_weapon_attack(v_payload);
  v_damage_apply_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  if jsonb_array_length(coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb)) > 0 then
    update public.odyssey_character_effects e
    set
      is_active = false,
      rounds_left = 0,
      updated_at = timezone('utc', now())
    where e.character_id = v_attacker_character_id
      and e.id in (
        select public.odyssey_try_parse_uuid(value)
        from jsonb_array_elements_text(coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb)) value
      );
    v_refresh_attacker := true;
  end if;

  if v_target_character_id is not null then
    v_target_alive_after := coalesce(
      nullif(v_result#>>'{target_state,is_alive}', '')::boolean,
      nullif(v_result#>>'{target_state,combat_state,is_alive}', '')::boolean,
      v_target_alive_before
    );
  end if;

  v_stage_started_at := clock_timestamp();
  v_post_hooks := public.odyssey_apply_perk_post_attack_hooks(
    jsonb_build_object(
      'attacker_character_id', v_attacker_character_id,
      'character_weapon_id', v_character_weapon_id,
      'target_character_id', v_target_character_id,
      'target_movement_version', v_target_movement_version,
      'created_by', coalesce(v_payload->>'actor_token_id', ''),
      'hit', coalesce(v_result->>'hit', 'false'),
      'target_alive_before', v_target_alive_before,
      'target_alive_after', v_target_alive_after
    )
  );
  v_perk_hooks_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;

  if not coalesce((v_result->>'hit')::boolean, false) then
    v_retry_effect := public.odyssey_grant_first_time_no_retry_effect(
      v_attacker_character_id,
      v_character_weapon_id,
      v_target_character_id,
      v_target_movement_version,
      coalesce(v_payload->>'actor_token_id', '')
    );
    if coalesce((v_retry_effect->>'applied')::boolean, false) = true then
      v_refresh_attacker := true;
    end if;
  end if;

  if jsonb_array_length(coalesce(v_result->'expired_attack_effects', '[]'::jsonb)) > 0 then
    v_refresh_attacker := true;
  end if;

  if coalesce((v_post_hooks->>'attacker_changed')::boolean, false) then
    v_refresh_attacker := true;
  end if;

  v_refresh_target :=
    coalesce((v_post_hooks->>'target_changed')::boolean, false)
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_minor_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_serious_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_critical_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'armor_minor_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'armor_serious_delta'), '')::integer, 0) > 0
    or coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'armor_critical_delta'), '')::integer, 0) > 0;

  v_result := v_result || jsonb_build_object(
    'post_attack_perks',
      jsonb_build_object(
        'consumed_effect_ids', coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb),
        'retry_effect', v_retry_effect,
        'post_hooks', v_post_hooks
      )
  );

  v_stage_started_at := clock_timestamp();
  v_finalized := public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
  v_finalize_result_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;

  if v_refresh_target and v_target_character_id is not null then
    v_stage_started_at := clock_timestamp();
    v_target_refresh_result := public.odyssey_refresh_character_combat_state(v_target_character_id);
    v_final_refresh_target_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;
    v_finalized := v_finalized || jsonb_build_object(
      'target_state',
      coalesce(v_target_refresh_result->'combat_state', '{}'::jsonb)
    );
  end if;

  if v_refresh_attacker and v_attacker_character_id is not null then
    v_stage_started_at := clock_timestamp();
    v_attacker_refresh_result := public.odyssey_refresh_character_combat_state(v_attacker_character_id);
    v_final_refresh_attacker_ms := extract(epoch from (clock_timestamp() - v_stage_started_at)) * 1000.0;
    v_finalized := v_finalized || jsonb_build_object(
      'attacker_state',
      coalesce(v_attacker_refresh_result->'combat_state', '{}'::jsonb)
    );
  end if;

  if v_debug then
    v_finalized := v_finalized || jsonb_build_object(
      'diagnostics',
      jsonb_build_object(
        'total_ms', extract(epoch from (clock_timestamp() - v_started_at)) * 1000.0,
        'stages',
        jsonb_build_object(
          'weapon_validation_ms', v_weapon_validation_ms,
          'attacker_state_ms', 0,
          'target_state_ms', 0,
          'damage_apply_ms', v_damage_apply_ms,
          'perk_hooks_ms', v_perk_hooks_ms,
          'final_refresh_attacker_ms', v_final_refresh_attacker_ms,
          'final_refresh_target_ms', v_final_refresh_target_ms,
          'finalize_result_ms', v_finalize_result_ms
        )
      )
    );
  end if;

  return v_finalized;
end;
$$;

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'odyssey_perform_weapon_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_weapon_attack(jsonb) was not found.';
  end if;

  if position($needle$if v_body_changed or v_armor_items_changed then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);

    select
      b.minor,
      b.serious,
      b.critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed
    into
      v_new_minor,
      v_new_serious,
      v_new_critical,
      v_new_armor_value,
      v_new_armor_critical,
      v_new_armor_max_critical,
      v_new_armor_destroyed,
      v_new_disabled,
      v_new_destroyed
    from public.odyssey_character_body_parts b
    where b.id = v_target_part.id;
  end if;$needle$ in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      $old$if v_body_changed or v_armor_items_changed then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);

    select
      b.minor,
      b.serious,
      b.critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed
    into
      v_new_minor,
      v_new_serious,
      v_new_critical,
      v_new_armor_value,
      v_new_armor_critical,
      v_new_armor_max_critical,
      v_new_armor_destroyed,
      v_new_disabled,
      v_new_destroyed
    from public.odyssey_character_body_parts b
    where b.id = v_target_part.id;
  end if;$old$,
      $new$if v_body_changed or v_armor_items_changed then
    select
      b.minor,
      b.serious,
      b.critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed
    into
      v_new_minor,
      v_new_serious,
      v_new_critical,
      v_new_armor_value,
      v_new_armor_critical,
      v_new_armor_max_critical,
      v_new_armor_destroyed,
      v_new_disabled,
      v_new_destroyed
    from public.odyssey_character_body_parts b
    where b.id = v_target_part.id;
  end if;$new$
    );
  elsif position($needle$if v_body_changed or v_armor_items_changed then
    select
      b.minor,
      b.serious,
      b.critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed
    into
      v_new_minor,
      v_new_serious,
      v_new_critical,
      v_new_armor_value,
      v_new_armor_critical,
      v_new_armor_max_critical,
      v_new_armor_destroyed,
      v_new_disabled,
      v_new_destroyed
    from public.odyssey_character_body_parts b
    where b.id = v_target_part.id;
  end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find target refresh block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  if position($needle$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
    if jsonb_array_length(coalesce(v_expired_attack_effects, '[]'::jsonb)) > 0 then
      v_attacker_state := coalesce(public.odyssey_refresh_character_combat_state(v_attacker_character_id)->'combat_state', '{}'::jsonb);
    end if;
  end if;$needle$ in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      $old$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
    if jsonb_array_length(coalesce(v_expired_attack_effects, '[]'::jsonb)) > 0 then
      v_attacker_state := coalesce(public.odyssey_refresh_character_combat_state(v_attacker_character_id)->'combat_state', '{}'::jsonb);
    end if;
  end if;$old$,
      $new$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
  end if;$new$
    );
  elsif position($needle$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
  end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find attacker refresh block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  execute v_function_def;
end;
$$;
