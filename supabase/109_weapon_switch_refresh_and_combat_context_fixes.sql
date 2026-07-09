-- ===== BEGIN 109_weapon_switch_refresh_and_combat_context_fixes.sql =====
--
-- Fixes backing the "weapon switching / overlay refresh / Skills cleanup /
-- Debug Console / error handling" work:
--
--   1. Encounter-context ambiguity: get_character_armory / switch_active_weapon
--      no longer silently pick the newest active encounter when a character
--      has more than one (e.g. a stale encounter that was never ended). An
--      explicit p_encounter_id is honored when given; otherwise ambiguity is
--      surfaced via combat_context and switch/reload gating is treated as
--      neutral (never wrongly blocked by an unrelated encounter).
--   2. odyssey_get_character_quick_actions_runtime now exposes combatCost /
--      combatResourceState and folds action-economy into available/
--      disabledReason when the character is in an unambiguous active
--      encounter.
--   3. perform_attack rejects a weapon-attack payload whose character_weapon_id
--      is not the character's current active weapon (WEAPON_NOT_ACTIVE).
--   4. odyssey_merge_weapon_feature_data: an override's own modifiers/on_hit
--      array now REPLACES the base definition's instead of concatenating with
--      it (this was doubling Plasma Edge's damage/armor-pierce modifiers).

-- ---------------------------------------------------------------------------
-- 1a. odyssey_get_active_participation: optional p_encounter_id + ambiguity
--     detection. Existing single-arg callers (perform_attack,
--     odyssey_apply_weapon_operation_session_cost, load_weapon_profile_magazine)
--     keep their current "pick newest active encounter" behavior unchanged —
--     only the NEW active_encounter_count/is_ambiguous fields are additive.
-- ---------------------------------------------------------------------------

drop function if exists public.odyssey_get_active_participation(uuid);

create or replace function public.odyssey_get_active_participation(
  p_character_id uuid,
  p_encounter_id uuid default null
)
returns jsonb
language plpgsql
as $$
declare
  v_row record;
  v_active_count integer := 0;
begin
  if p_character_id is null then
    return null;
  end if;

  select count(*)
  into v_active_count
  from public.odyssey_initiative_entries i
  join public.odyssey_combat_encounters e on e.id = i.encounter_id
  where i.character_id = p_character_id
    and i.is_active = true
    and e.status = 'active'
    and e.ended_at is null;

  select
    e.id as encounter_id,
    e.state_version,
    e.current_round,
    e.active_character_id,
    i.id as entry_id,
    i.action_current,
    i.move_current,
    i.reaction_action_current
  into v_row
  from public.odyssey_initiative_entries i
  join public.odyssey_combat_encounters e on e.id = i.encounter_id
  where i.character_id = p_character_id
    and i.is_active = true
    and e.status = 'active'
    and e.ended_at is null
    and (p_encounter_id is null or e.id = p_encounter_id)
  order by e.created_at desc, e.id desc
  limit 1
  for update of i, e;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'encounter_id', v_row.encounter_id,
    'state_version', v_row.state_version,
    'current_round', v_row.current_round,
    'is_current_turn', v_row.active_character_id is not distinct from p_character_id,
    'entry_id', v_row.entry_id,
    'action_current', coalesce(v_row.action_current, 0),
    'move_current', coalesce(v_row.move_current, 0),
    'reaction_action_current', coalesce(v_row.reaction_action_current, 0),
    'active_encounter_count', v_active_count,
    'is_ambiguous', (p_encounter_id is null and v_active_count > 1)
  );
end;
$$;

grant execute on function public.odyssey_get_active_participation(uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1b. odyssey_apply_weapon_operation_session_cost: optional p_encounter_id
--     passthrough. When the character's participation is ambiguous (multiple
--     active encounters, no explicit encounter_id given), the switch/reload
--     is treated as free/out-of-session rather than guessing which encounter
--     to charge — this is the "never silently choose newest" rule applied to
--     the COST side, mirroring get_character_armory's DISPLAY side below.
-- ---------------------------------------------------------------------------

drop function if exists public.odyssey_apply_weapon_operation_session_cost(uuid, text, text, integer);

create or replace function public.odyssey_apply_weapon_operation_session_cost(
  p_character_id uuid,
  p_operation text,
  p_feed_mode text default null,
  p_expected_session_version integer default null,
  p_encounter_id uuid default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_participation jsonb := public.odyssey_get_active_participation(p_character_id, p_encounter_id);
  v_cost_mode text := public.odyssey_get_weapon_operation_cost_mode(
    p_character_id,
    p_operation,
    p_feed_mode
  );
  v_entry_id uuid := public.odyssey_try_parse_uuid(v_participation->>'entry_id');
  v_encounter_id uuid := public.odyssey_try_parse_uuid(v_participation->>'encounter_id');
  v_move_current integer := 0;
  v_move_max integer := 0;
begin
  if v_participation is null then
    return jsonb_build_object(
      'ok', true,
      'spent', false,
      'cost_mode', v_cost_mode,
      'combat_session', null
    );
  end if;

  if coalesce((v_participation->>'is_ambiguous')::boolean, false) then
    return jsonb_build_object(
      'ok', true,
      'spent', false,
      'cost_mode', v_cost_mode,
      'combat_session', null,
      'combat_context', jsonb_build_object(
        'mode', 'ambiguous',
        'active_encounter_count', (v_participation->>'active_encounter_count')::integer,
        'warning', 'Multiple active encounters found for this character. Pass encounter_id explicitly.'
      )
    );
  end if;

  if p_expected_session_version is not null
     and p_expected_session_version <> coalesce((v_participation->>'state_version')::integer, 0) then
    return jsonb_build_object(
      'ok', false,
      'error', 'STATE_VERSION_CONFLICT',
      'message', 'Combat state changed. Reload authoritative runtime.',
      'encounter_state_version', (v_participation->>'state_version')::integer
    );
  end if;

  if coalesce((v_participation->>'is_current_turn')::boolean, false) = false then
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
      'combat_session', public.odyssey_build_session_cost_summary(v_participation, false)
    );
  end if;

  select
    coalesce(i.move_current, 0),
    coalesce(i.move_max, 0)
  into
    v_move_current,
    v_move_max
  from public.odyssey_initiative_entries i
  where i.id = v_entry_id
  for update;

  if v_move_max <= 0 or v_move_current < v_move_max then
    return jsonb_build_object(
      'ok', false,
      'error', 'FULL_MOVE_NOT_AVAILABLE',
      'message', 'FULL MOVE is already spent.'
    );
  end if;

  perform public.odyssey_apply_turn_costs(
    v_entry_id,
    0,
    v_move_current,
    false
  );
  perform public.odyssey_increment_encounter_state_version(v_encounter_id);

  return jsonb_build_object(
    'ok', true,
    'spent', true,
    'cost_mode', v_cost_mode,
    'combat_session', public.odyssey_build_session_cost_summary(v_participation, false)
  );
end;
$$;

grant execute on function public.odyssey_apply_weapon_operation_session_cost(uuid, text, text, integer, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1c. switch_active_weapon: accept an optional `encounter_id` in the payload
--     and pass it through to both the cost function and the armory it
--     returns, so the charged encounter and the displayed encounter always
--     agree.
-- ---------------------------------------------------------------------------

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
      'armory', public.get_character_armory(v_character_id, v_encounter_id)
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
    'combat_context', v_cost_result->'combat_context',
    'armory', public.get_character_armory(v_character_id, v_encounter_id)
  );
end;
$$;

grant execute on function public.switch_active_weapon(jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1d. get_character_armory: optional p_encounter_id + combat_context. Never
--     silently picks "newest active encounter" when more than one exists and
--     no explicit encounter_id was given — treats switch/reload as neutral
--     (free) instead, and reports the ambiguity so the caller can retry with
--     an explicit encounter_id.
-- ---------------------------------------------------------------------------

drop function if exists public.get_character_armory(uuid);

create or replace function public.get_character_armory(
  p_character_id uuid,
  p_encounter_id uuid default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_weapons jsonb := '[]'::jsonb;
  v_magazines jsonb := '[]'::jsonb;
  v_active_weapon_id uuid := public.odyssey_get_character_active_weapon_id(p_character_id);
  v_switch_cost text := public.odyssey_get_weapon_operation_cost_mode(p_character_id, 'switch_weapon', null);
  v_detachable_reload_cost text := public.odyssey_get_weapon_operation_cost_mode(p_character_id, 'reload', 'detachable_magazine');
  v_internal_reload_cost text := public.odyssey_get_weapon_operation_cost_mode(p_character_id, 'reload', 'internal_magazine');
  v_has_active_session boolean := false;
  v_is_current_turn boolean := false;
  v_move_current integer := 0;
  v_move_max integer := 0;
  v_switch_block_reason text := null;
  v_detachable_reload_block_reason text := null;
  v_internal_reload_block_reason text := null;
  v_active_encounter_count integer := 0;
  v_resolved_encounter_id uuid := null;
  v_combat_context jsonb := jsonb_build_object('mode', 'none', 'active_encounter_count', 0, 'encounter_id', null);
begin
  perform public.initialize_character_weapon_abilities(weapon.id)
  from public.odyssey_character_weapons weapon
  where weapon.character_id = p_character_id;

  select count(*)
  into v_active_encounter_count
  from public.odyssey_initiative_entries i
  join public.odyssey_combat_encounters e on e.id = i.encounter_id
  where i.character_id = p_character_id
    and i.is_active = true
    and e.status = 'active'
    and e.ended_at is null;

  if p_encounter_id is not null then
    select
      true,
      e.active_character_id is not distinct from p_character_id,
      coalesce(i.move_current, 0),
      coalesce(i.move_max, 0),
      e.id
    into
      v_has_active_session,
      v_is_current_turn,
      v_move_current,
      v_move_max,
      v_resolved_encounter_id
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.status = 'active'
      and e.ended_at is null
      and e.id = p_encounter_id
    limit 1;

    v_combat_context := jsonb_build_object(
      'mode', case when v_has_active_session then 'single' else 'none' end,
      'active_encounter_count', v_active_encounter_count,
      'encounter_id', v_resolved_encounter_id
    );
  elsif v_active_encounter_count > 1 then
    -- Ambiguous: never guess which encounter to gate on. Switch/reload stay
    -- free (v_has_active_session remains false) and the caller is told why.
    v_combat_context := jsonb_build_object(
      'mode', 'ambiguous',
      'active_encounter_count', v_active_encounter_count,
      'encounter_id', null,
      'warning', 'Multiple active encounters found for this character. Pass encounter_id explicitly.'
    );
  else
    select
      true,
      e.active_character_id is not distinct from p_character_id,
      coalesce(i.move_current, 0),
      coalesce(i.move_max, 0),
      e.id
    into
      v_has_active_session,
      v_is_current_turn,
      v_move_current,
      v_move_max,
      v_resolved_encounter_id
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.status = 'active'
      and e.ended_at is null
    order by e.created_at desc, e.id desc
    limit 1;

    v_combat_context := jsonb_build_object(
      'mode', case when v_has_active_session then 'single' else 'none' end,
      'active_encounter_count', v_active_encounter_count,
      'encounter_id', v_resolved_encounter_id
    );
  end if;

  if v_has_active_session then
    if not v_is_current_turn then
      v_switch_block_reason := 'Waiting for your turn';
      v_detachable_reload_block_reason := 'Waiting for your turn';
      v_internal_reload_block_reason := 'Waiting for your turn';
    else
      if v_switch_cost <> 'free' and (v_move_max <= 0 or v_move_current < v_move_max) then
        v_switch_block_reason := 'FULL MOVE already spent';
      end if;
      if v_detachable_reload_cost <> 'free' and (v_move_max <= 0 or v_move_current < v_move_max) then
        v_detachable_reload_block_reason := 'FULL MOVE already spent';
      end if;
      if v_internal_reload_cost <> 'free' and (v_move_max <= 0 or v_move_current < v_move_max) then
        v_internal_reload_block_reason := 'FULL MOVE already spent';
      end if;
    end if;
  end if;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', w.id,
          'character_id', w.character_id,
          'custom_name', w.custom_name,
          'name', coalesce(nullif(trim(w.custom_name), ''), wm.name),
          'notes', w.notes,
          'sort_order', w.sort_order,
          'active_profile_id', w.active_profile_id,
          'data', coalesce(w.data, '{}'::jsonb),
          'equipped_slot', w.equipped_slot,
          'is_active', w.id = v_active_weapon_id,
          'switch_cost', v_switch_cost,
          'can_switch_to',
            case
              when w.id = v_active_weapon_id then false
              when v_switch_block_reason is not null then false
              else true
            end,
          'switch_block_reason',
            case
              when w.id = v_active_weapon_id then null
              else v_switch_block_reason
            end,
          'model',
            jsonb_build_object(
              'id', wm.id,
              'code', wm.code,
              'name', wm.name,
              'weapon_class', mwc.code,
              'weapon_class_name', mwc.name,
              'linked_skill', mskill.code,
              'linked_skill_name', mskill.name,
              'caliber', mcal.code,
              'caliber_name', mcal.name,
              'base_accuracy_bonus', wm.base_accuracy_bonus,
              'base_melee_damage', wm.base_melee_damage,
              'range_profile', mrp.code,
              'range_profile_name', mrp.name,
              'tags', wm.tags
            ),
          'feed_mode', coalesce(runtime.active_profile_json->>'feed_mode', 'detachable_magazine'),
          'internal_capacity', coalesce(nullif(runtime.active_profile_json->>'internal_capacity', '')::integer, 0),
          'internal_current_rounds', coalesce(nullif(runtime.active_profile_json->>'internal_current_rounds', '')::integer, 0),
          'internal_max_rounds', coalesce(nullif(runtime.active_profile_json->>'internal_max_rounds', '')::integer, 0),
          'internal_ammo_type', coalesce(runtime.active_profile_json->'internal_ammo_type', 'null'::jsonb),
          'ammo', coalesce(runtime.active_profile_json->'ammo', 'null'::jsonb),
          'uses_magazine',
            case
              when coalesce(runtime.active_profile_json->>'attack_type', 'ranged') <> 'ranged' then false
              when coalesce(runtime.active_profile_json->>'feed_mode', 'detachable_magazine') = 'internal_magazine' then false
              else true
            end,
          'requires_ammo',
            coalesce(runtime.active_profile_json->>'attack_type', 'ranged') = 'ranged',
          'can_reload',
            case
              when coalesce(runtime.active_profile_json->>'attack_type', 'ranged') <> 'ranged' then false
              when coalesce(runtime.active_profile_json->>'feed_mode', 'detachable_magazine') = 'internal_magazine' then false
              else true
            end,
          'reload_cost',
            case
              when coalesce(runtime.active_profile_json->>'feed_mode', 'detachable_magazine') = 'internal_magazine' then v_internal_reload_cost
              else v_detachable_reload_cost
            end,
          'reload_block_reason',
            case
              when coalesce(runtime.active_profile_json->>'attack_type', 'ranged') <> 'ranged' then null
              when coalesce(runtime.active_profile_json->>'feed_mode', 'detachable_magazine') = 'internal_magazine' then v_internal_reload_block_reason
              else v_detachable_reload_block_reason
            end,
          'active_profile', runtime.active_profile_json,
          'profiles', runtime.profiles_json,
          'features', coalesce(runtime.features_bundle->'features', '[]'::jsonb),
          'loaded_magazine', coalesce(runtime.active_profile_json->'loaded_magazine', 'null'::jsonb),
          'selected_fire_mode', coalesce(runtime.active_profile_json->'selected_fire_mode', 'null'::jsonb),
          'available_fire_modes', coalesce(runtime.active_profile_json->'available_fire_modes', '[]'::jsonb),
          'compatible_magazines', coalesce(runtime.active_profile_json->'compatible_magazines', '[]'::jsonb),
          'lock_state', public.odyssey_get_weapon_lock_state(w.character_id, w.id),
          'weapon_abilities',
            coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'id', ability.id,
                    'character_weapon_id', w.id,
                    'ability_def_id', ability.ability_def_id,
                    'code', def.code,
                    'name', def.name,
                    'ability_kind', def.ability_kind,
                    'activation_type', def.activation_type,
                    'effect_mode', def.effect_mode,
                    'attack_type', def.attack_type,
                    'effective_level', greatest(coalesce(skill.level, ability.learned_level, 0), 0),
                    'is_enabled', ability.is_enabled,
                    'is_hidden', ability.is_hidden,
                    'current_cooldown_rounds', ability.current_cooldown_rounds,
                    'current_charges', ability.current_charges,
                    'max_charges', ability.max_charges,
                    'required_profile_id', nullif(trim(coalesce(ability.data->>'required_profile_id', '')), ''),
                    'required_profile_code', nullif(trim(coalesce(ability.data->>'required_profile_code', '')), ''),
                    'is_available_for_active_profile',
                      case
                        when nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '') is null then true
                        else w.active_profile_id::text = nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '')
                      end
                  )
                  order by ability.sort_order, def.sort_order, def.code
                )
                from public.odyssey_character_abilities ability
                join public.odyssey_ability_defs def on def.id = ability.ability_def_id
                left join public.odyssey_character_skills skill
                  on skill.character_id = ability.character_id
                 and skill.skill_def_id = def.linked_skill_id
                where ability.character_id = p_character_id
                  and ability.source_character_weapon_id = w.id
              ),
              '[]'::jsonb
            )
        )
        order by w.sort_order, coalesce(nullif(trim(w.custom_name), ''), wm.name), w.id
      ),
      '[]'::jsonb
    )
  into v_weapons
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
  join public.odyssey_skill_defs mskill on mskill.id = wm.linked_skill_id
  left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
  join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
  left join lateral (
    select
      public.odyssey_get_active_character_weapon_profile(w.id) as active_profile_json,
      public.odyssey_get_character_weapon_profiles(w.id) as profiles_json,
      public.get_character_weapon_features(w.id) as features_bundle
  ) runtime on true
  where w.character_id = p_character_id;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', cm.id,
          'character_id', cm.character_id,
          'custom_name', cm.custom_name,
          'name', coalesce(nullif(trim(cm.custom_name), ''), md.name),
          'notes', cm.notes,
          'current_rounds', cm.current_rounds,
          'magazine_def',
            jsonb_build_object(
              'id', md.id,
              'code', md.code,
              'name', md.name,
              'capacity', md.capacity,
              'caliber', caliber.code,
              'caliber_name', caliber.name
            ),
          'ammo_type',
            jsonb_build_object(
              'id', ammo.id,
              'code', ammo.code,
              'name', ammo.name,
              'caliber', ammo_caliber.code,
              'caliber_name', ammo_caliber.name
            )
        )
        order by md.sort_order, md.name, cm.created_at, cm.id
      ),
      '[]'::jsonb
    )
  into v_magazines
  from public.odyssey_character_magazines cm
  join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  join public.odyssey_caliber_defs ammo_caliber on ammo_caliber.id = ammo.caliber_id
  where cm.character_id = p_character_id;

  return jsonb_build_object(
    'character_id', p_character_id,
    'active_weapon_id', v_active_weapon_id,
    'weapons', coalesce(v_weapons, '[]'::jsonb),
    'magazines', coalesce(v_magazines, '[]'::jsonb),
    'combat_context', v_combat_context
  );
end;
$$;

grant execute on function public.get_character_armory(uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. odyssey_get_character_quick_actions_runtime: expose combatCost /
--    combatResourceState and fold action-economy into available/
--    disabledReason when in an unambiguous active encounter. Signature is
--    unchanged (still a single p_character_id) — additive fields only.
-- ---------------------------------------------------------------------------

create or replace function public.odyssey_get_character_quick_actions_runtime(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_exists boolean;
  v_is_alive boolean;
  v_is_conscious boolean;
  v_has_skip_turn_effect boolean;
  v_quick_actions jsonb := '[]'::jsonb;
  v_layout jsonb;
  v_version integer := 1;
  v_participation jsonb;
  v_in_combat boolean := false;
  v_action_current integer := null;
  v_move_current integer := null;
begin
  -- Validate character exists.
  select exists(
    select 1 from public.odyssey_characters where id = p_character_id and not coalesce(is_deleted, false)
  ) into v_character_exists;

  if not v_character_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character does not exist or is deleted',
      'characterId', p_character_id,
      'quickActions', '[]'::jsonb,
      'quickbar', jsonb_build_object('slots', '[]'::jsonb, 'maxSlots', 20, 'version', 1)
    );
  end if;

  -- Check character state eligibility. Alive/conscious live on the combat-state
  -- table (odyssey_character_combat_state), NOT on odyssey_characters; a character
  -- with no combat-state row yet is treated as alive + conscious (defaults).
  select coalesce(cs.is_alive, true), coalesce(cs.is_conscious, true)
  into v_is_alive, v_is_conscious
  from public.odyssey_characters c
  left join public.odyssey_character_combat_state cs on cs.character_id = c.id
  where c.id = p_character_id;

  -- Check for a skip_turn effect via the canonical engine helper (reads the
  -- effect's data.flags.skip_turn — the same source the turn engine uses).
  v_has_skip_turn_effect := public.odyssey_character_has_active_effect_flag(p_character_id, 'skip_turn');

  -- Combat action economy (ticket: quickbar must not claim available=true
  -- when the server would reject the action for lack of ACTION/MOVE). An
  -- ambiguous multi-encounter participation is treated the same as
  -- out-of-combat here — never guessed against the wrong encounter.
  v_participation := public.odyssey_get_active_participation(p_character_id);
  v_in_combat := v_participation is not null and not coalesce((v_participation->>'is_ambiguous')::boolean, false);
  if v_in_combat then
    v_action_current := coalesce((v_participation->>'action_current')::integer, 0);
    v_move_current := coalesce((v_participation->>'move_current')::integer, 0);
  end if;

  -- Fetch quickbar layout and version (qualified — see the save function for why).
  select t.layout, t.version into v_layout, v_version
  from public.odyssey_character_quickbar_layouts t
  where t.character_id = p_character_id;

  v_layout := coalesce(v_layout, jsonb_build_object('slots', '[]'::jsonb));
  -- No saved layout yet -> version 0, matching odyssey_save_character_quickbar_layout's
  -- own "no row" default. A client that reads version 0 here and saves with
  -- expected_version=0 must succeed (first insert bumps it to 1) — these two
  -- functions must never disagree on what "nothing saved yet" means.
  v_version := coalesce(v_version, 0);

  -- Build quick-actions list from odyssey_character_abilities.
  -- Disabled reasons are server-determined, never fabricated.
  v_quick_actions := coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'characterActionId', ca.id,
          'definitionId', ca.ability_def_id,
          'sourceType', ad.source_type,
          -- Canonical action type (one of attack_technique|directed|instant|toggle),
          -- derived from the definition. activation_type ('manual') is NOT the type.
          -- Toggle has no schema marker yet → deferred to Phase 4.1 (data convention).
          'type', case
            when coalesce(ad.effect_mode, '') = 'attack' or ad.ability_kind = 'attack' then 'attack_technique'
            when coalesce(ad.target_type, 'none') in ('character', 'body_part') then 'directed'
            else 'instant'
          end,
          'name', ad.name,
          'shortDescription', substring(ad.description, 1, 100),
          'fullDescription', ad.description,
          'iconKey', coalesce(ad.data->>'icon_key', 'bolt'),
          'semanticKind', ad.ability_kind,

          'targeting', jsonb_build_object(
            'mode', coalesce(ad.target_type, 'none'),
            'minTargets', 1,
            'maxTargets', 1,
            'allowAllies', true,
            'allowSelf', ad.target_type = 'self',
            'requiresBodyZone', ad.target_type = 'body_part'
          ),

          'costs', jsonb_build_object(
            'main', case when ad.resource_mode = 'pool' then 1 else 0 end,
            'move', 0,
            'psi', case when ad.resource_pool_code = 'psi' then coalesce((ald.data->>'psi_cost')::int, 0) else 0 end,
            'charges', case when ad.resource_mode = 'item' then coalesce(ca.current_charges, 0) else 0 end
          ),

          -- combat_cost / combat_resource_state (ticket #11): explicit action/
          -- move cost + the character's CURRENT action/move economy, so the
          -- client never has to re-derive "is this affordable" itself.
          'combatCost', jsonb_build_object(
            'actionCost', case when ad.resource_mode = 'pool' then 1 else 0 end,
            'moveCost', 0
          ),
          'combatResourceState', jsonb_build_object(
            'actionCurrent', v_action_current,
            'moveCurrent', v_move_current
          ),

          'cooldown', jsonb_build_object(
            'current', ca.current_cooldown_rounds,
            'max', coalesce(ald.cooldown_rounds, 0),
            'unit', 'turn'
          ),

          -- Phase 4.1A.2: available/disabledReason now factor in cooldown and
          -- resource sufficiency (previously display-only via disabledReason's
          -- cooldown text — never part of `available` itself), plus the new
          -- unsupported-effect check. exec.unsupported_effect and
          -- res.insufficient_* are computed once per row (LEFT JOIN LATERAL
          -- below) and reused here rather than repeating the expressions.
          -- Ticket #11: also factors in combat action economy (ACTION only —
          -- every current action's moveCost is 0) when in an unambiguous
          -- active encounter.
          'state', jsonb_build_object(
            'available',
              ca.is_enabled
              and not v_has_skip_turn_effect
              and (v_is_alive or ad.target_type = 'none')
              and coalesce(ca.current_cooldown_rounds, 0) <= 0
              and not coalesce(res.insufficient_pool, false)
              and not coalesce(res.insufficient_charges, false)
              and not coalesce(exec.unsupported_effect, false)
              and not (v_in_combat and ad.resource_mode = 'pool' and coalesce(v_action_current, 0) < 1),
            'active', false, -- Phase 4.1
            'disabledReason', case
              when not ca.is_enabled then 'Ability is disabled'
              when v_has_skip_turn_effect then 'Skipping turn'
              when not v_is_alive and ad.target_type <> 'none' then 'Character is dead'
              when coalesce(exec.unsupported_effect, false) then 'Attack effect is not supported yet'
              when v_in_combat and ad.resource_mode = 'pool' and coalesce(v_action_current, 0) < 1 then 'No ACTION available'
              when coalesce(ca.current_cooldown_rounds, 0) > 0 then format('Cooldown: %s turns', ca.current_cooldown_rounds)
              when coalesce(res.insufficient_pool, false) then format('Not enough %s', coalesce(ad.resource_pool_code, 'resource'))
              when coalesce(res.insufficient_charges, false) then 'No charges left'
              else null
            end,
            'selectable',
              ca.is_enabled
              and not v_has_skip_turn_effect
              and (v_is_alive or ad.target_type = 'none')
              and coalesce(ca.current_cooldown_rounds, 0) <= 0
              and not coalesce(res.insufficient_pool, false)
              and not coalesce(res.insufficient_charges, false)
              and not coalesce(exec.unsupported_effect, false)
              and not (v_in_combat and ad.resource_mode = 'pool' and coalesce(v_action_current, 0) < 1),
            -- Distinct from `available`: whether this ability's OWN effect can
            -- run on the current execution path at all, independent of
            -- cooldown/resources/turn state. Reuses the exact same
            -- odyssey_ability_level_defs columns perform_attack (migration
            -- 100) checks — one shared definition, never a client-side guess
            -- or a name-based check.
            'executionAvailable', not coalesce(exec.unsupported_effect, false),
            'executionReason', case when coalesce(exec.unsupported_effect, false) then 'ACTION_EFFECT_NOT_IMPLEMENTED' else null end,
            -- Structural signal so the client can tell "insufficient resource"
            -- apart from any other reason WITHOUT parsing disabledReason text.
            'resourceSufficient', not (coalesce(res.insufficient_pool, false) or coalesce(res.insufficient_charges, false))
          ),

          'requirements', jsonb_build_object(
            'weaponClass', null, -- Phase 4.1: weapon-linked actions
            'weaponId', null,
            'conditionSummary', null
          )
        )
        order by ca.sort_order, ca.created_at
      )
    ),
    '[]'::jsonb
  )
  from public.odyssey_character_abilities ca
  join public.odyssey_ability_defs ad on ad.id = ca.ability_def_id
  left join public.odyssey_ability_level_defs ald on ald.ability_def_id = ad.id and ald.ability_level = ca.learned_level
  left join lateral (
    select (
      coalesce(ald.attack_damage_bonus, 0) <> 0
      or coalesce(ald.attack_armor_pierce, 0) <> 0
      or coalesce(ald.ignore_armor, false)
    ) as unsupported_effect
  ) exec on true
  -- Character's PSI (or other pool) balance, when this ability spends one —
  -- (character_id, resource_pool_def_id) is at most one row, same assumption
  -- migration 100's odyssey_consume_character_ability_cost call site makes.
  left join public.odyssey_resource_pool_defs rpd on rpd.code = ad.resource_pool_code
  left join public.odyssey_character_resource_pools rp
    on rp.character_id = ca.character_id and rp.resource_pool_def_id = rpd.id
  left join lateral (
    select
      (ad.resource_mode = 'pool' and coalesce(rp.current_value, 0) < coalesce(ald.resource_cost, 0)) as insufficient_pool,
      (ad.resource_mode = 'item' and ca.current_charges is not null and ca.current_charges <= 0) as insufficient_charges
  ) res on true
  where ca.character_id = p_character_id
    and ca.is_hidden = false
    and ca.is_enabled = true
    and ad.ability_kind != 'passive'
    and ad.activation_type in ('manual', 'custom');

  return jsonb_build_object(
    'ok', true,
    'error', null,
    'characterId', p_character_id,
    'quickActions', v_quick_actions,
    'quickbar', jsonb_build_object(
      'slots', coalesce(v_layout->'slots', '[]'::jsonb),
      'maxSlots', 20,
      'version', v_version
    )
  );
end;
$$;

comment on function public.odyssey_get_character_quick_actions_runtime is
  'Fetch full quick-actions runtime for a character, including quickbar layout. '
  'Returns only eligible actions (manual, non-passive, enabled, not-hidden). '
  'available/disabledReason/executionAvailable/executionReason are all '
  'server-determined (cooldown, resource sufficiency, combat action economy, '
  'and effect-grammar support). Layout has version for optimistic locking.';

grant execute on function public.odyssey_get_character_quick_actions_runtime(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. perform_attack: reject a weapon-attack payload whose character_weapon_id
--    is not the character's active weapon. Hot-patched via pg_get_functiondef
--    (same pattern migration 90 used for combat_execute_action /
--    odyssey_start_next_eligible_turn) rather than a full create-or-replace,
--    since this function has been redefined across many migrations and the
--    safest way to change one line is to patch whatever is truly live.
-- ---------------------------------------------------------------------------

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'perform_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.perform_attack(jsonb) was not found.';
  end if;

  if position('WEAPON_NOT_ACTIVE' in v_function_def) > 0 then
    -- Already patched (re-running this migration) — nothing to do.
    return;
  end if;

  if position($needle$v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_character_weapon_id);$needle$ in v_function_def) = 0 then
    raise exception 'Could not find the weapon-lock anchor in public.perform_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_character_weapon_id);$old$,
    $new$if v_character_weapon_id <> public.odyssey_get_character_active_weapon_id(v_attacker_character_id) then
      return jsonb_build_object(
        'ok', false,
        'error', 'WEAPON_NOT_ACTIVE',
        'message', 'This weapon is not currently active.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_character_weapon_id);$new$
  );
  execute v_function_def;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. odyssey_merge_weapon_feature_data: override REPLACES base modifiers/
--    on_hit instead of concatenating with them. This was the root cause of
--    Plasma Edge showing +40 damage / +40 armor_pierce instead of +20/+20
--    when a weapon_model_features link row redundantly repeated the base
--    feature def's own modifiers.
-- ---------------------------------------------------------------------------

create or replace function public.odyssey_merge_weapon_feature_data(
  p_base jsonb,
  p_override jsonb
)
returns jsonb
language sql
immutable
as $$
  with normalized as (
    select
      coalesce(case when jsonb_typeof(p_base) = 'object' then p_base else '{}'::jsonb end, '{}'::jsonb) as base_data,
      coalesce(case when jsonb_typeof(p_override) = 'object' then p_override else '{}'::jsonb end, '{}'::jsonb) as override_data
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          ((base_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions') || (override_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions')),
          '{modifiers}',
          case
            -- Override wins outright when it specifies its own modifiers —
            -- it is expected to be a COMPLETE replacement, never an addend,
            -- so base and override are never concatenated together.
            when jsonb_typeof(override_data->'modifiers') = 'array'
              then override_data->'modifiers'
            when jsonb_typeof(base_data->'modifiers') = 'array'
              then base_data->'modifiers'
            else '[]'::jsonb
          end,
          true
        ),
        '{on_hit}',
        case
          when jsonb_typeof(override_data->'on_hit') = 'array'
            then override_data->'on_hit'
          when jsonb_typeof(base_data->'on_hit') = 'array'
            then base_data->'on_hit'
          else '[]'::jsonb
        end,
        true
      ),
      '{flags}',
      case
        when jsonb_typeof(base_data->'flags') = 'object'
          or jsonb_typeof(override_data->'flags') = 'object'
          then coalesce(base_data->'flags', '{}'::jsonb) || coalesce(override_data->'flags', '{}'::jsonb)
        else '{}'::jsonb
      end,
      true
    ),
    '{conditions}',
    case
      when jsonb_typeof(base_data->'conditions') = 'object'
        or jsonb_typeof(override_data->'conditions') = 'object'
        then coalesce(base_data->'conditions', '{}'::jsonb) || coalesce(override_data->'conditions', '{}'::jsonb)
      else '{}'::jsonb
    end,
    true
  )
  from normalized;
$$;

grant execute on function public.odyssey_merge_weapon_feature_data(jsonb, jsonb) to anon, authenticated;

-- Data hygiene: clear any EXISTING weapon_model_features.data.modifiers array
-- that is provably a duplicate of its linked feature_def's own modifiers (a
-- set-equal array of {target,value} pairs) — this can only ever have been an
-- accidental copy-paste, never an intentional override that differs from the
-- base, so it is safe to clear automatically.
update public.odyssey_weapon_model_features link
set data = (coalesce(link.data, '{}'::jsonb) - 'modifiers')
from public.odyssey_weapon_feature_defs def
where def.id = link.feature_def_id
  and jsonb_typeof(link.data->'modifiers') = 'array'
  and jsonb_typeof(def.data->'modifiers') = 'array'
  and (
    select coalesce(jsonb_agg(m order by m), '[]'::jsonb)
    from jsonb_array_elements(link.data->'modifiers') m
  ) = (
    select coalesce(jsonb_agg(m order by m), '[]'::jsonb)
    from jsonb_array_elements(def.data->'modifiers') m
  );

-- ===== END 109_weapon_switch_refresh_and_combat_context_fixes.sql =====
