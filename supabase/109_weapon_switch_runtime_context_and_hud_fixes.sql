-- ===== BEGIN 109_weapon_switch_runtime_context_and_hud_fixes.sql =====
--
-- Fixes:
--   - safe primary/secondary slot swap for switch_active_weapon()
--   - explicit/ambiguous combat context handling for armory runtime
--   - prevents unrelated active encounters from poisoning switch/reload availability

create or replace function public.get_character_armory_context(
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
  v_selected_encounter_id uuid := null;
  v_context_mode text := 'out_of_combat';
  v_context_warning text := null;
begin
  perform public.initialize_character_weapon_abilities(weapon.id)
  from public.odyssey_character_weapons weapon
  where weapon.character_id = p_character_id;

  select count(distinct e.id)
  into v_active_encounter_count
  from public.odyssey_initiative_entries i
  join public.odyssey_combat_encounters e on e.id = i.encounter_id
  where i.character_id = p_character_id
    and i.is_active = true
    and e.status = 'active'
    and e.ended_at is null;

  if p_encounter_id is not null then
    select
      e.id,
      e.active_character_id is not distinct from p_character_id,
      coalesce(i.move_current, 0),
      coalesce(i.move_max, 0)
    into
      v_selected_encounter_id,
      v_is_current_turn,
      v_move_current,
      v_move_max
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.id = p_encounter_id
      and e.status = 'active'
      and e.ended_at is null
    limit 1;

    if found then
      v_context_mode := 'explicit';
      v_has_active_session := true;
    else
      v_context_mode := 'explicit_missing';
      v_context_warning := 'Provided encounter_id is not active for this character.';
    end if;
  elsif v_active_encounter_count = 1 then
    select
      e.id,
      e.active_character_id is not distinct from p_character_id,
      coalesce(i.move_current, 0),
      coalesce(i.move_max, 0)
    into
      v_selected_encounter_id,
      v_is_current_turn,
      v_move_current,
      v_move_max
    from public.odyssey_initiative_entries i
    join public.odyssey_combat_encounters e on e.id = i.encounter_id
    where i.character_id = p_character_id
      and i.is_active = true
      and e.status = 'active'
      and e.ended_at is null
    order by e.created_at desc, e.id desc
    limit 1;

    v_context_mode := 'single_active';
    v_has_active_session := v_selected_encounter_id is not null;
  elsif v_active_encounter_count > 1 then
    v_context_mode := 'ambiguous';
    v_context_warning := 'Multiple active encounters found for this character. Pass encounter_id explicitly.';
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
    'combat_context', jsonb_build_object(
      'mode', v_context_mode,
      'encounter_id', v_selected_encounter_id,
      'active_encounter_count', v_active_encounter_count,
      'warning', v_context_warning,
      'is_current_turn', case when v_selected_encounter_id is null then null else v_is_current_turn end,
      'move_current', case when v_selected_encounter_id is null then null else v_move_current end,
      'move_max', case when v_selected_encounter_id is null then null else v_move_max end
    )
  );
end;
$$;

create or replace function public.get_character_armory(
  p_character_id uuid
)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  return public.get_character_armory_context(p_character_id, null::uuid);
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
  v_requested_encounter_id uuid := public.odyssey_try_parse_uuid(p_payload->>'encounter_id');
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_current_active_weapon_id uuid := null;
  v_cost_result jsonb := '{}'::jsonb;
  v_response_encounter_id uuid := null;
begin
  if v_character_id is null or v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id and character_weapon_id are required.'
    );
  end if;

  perform 1
  from public.odyssey_character_weapons weapon
  where weapon.character_id = v_character_id
  for update;

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
      'armory', public.get_character_armory_context(v_character_id, v_requested_encounter_id)
    );
  end if;

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_character_id,
    'switch_weapon',
    null,
    v_expected_session_version
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
  end if;

  v_response_encounter_id := coalesce(
    public.odyssey_try_parse_uuid(v_cost_result->'combat_session'->>'encounter_id'),
    v_requested_encounter_id
  );

  update public.odyssey_character_weapons weapon
  set
    equipped_slot = null,
    updated_at = timezone('utc', now())
  where weapon.character_id = v_character_id
    and weapon.equipped_slot in ('primary', 'secondary');

  update public.odyssey_character_weapons weapon
  set
    equipped_slot = 'primary',
    updated_at = timezone('utc', now())
  where weapon.id = v_character_weapon_id
    and weapon.character_id = v_character_id;

  if v_current_active_weapon_id is not null and v_current_active_weapon_id <> v_character_weapon_id then
    update public.odyssey_character_weapons weapon
    set
      equipped_slot = 'secondary',
      updated_at = timezone('utc', now())
    where weapon.id = v_current_active_weapon_id
      and weapon.character_id = v_character_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_character_weapon_id,
    'active_weapon_id', v_character_weapon_id,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'armory', public.get_character_armory_context(v_character_id, v_response_encounter_id)
  );
end;
$$;

grant execute on function public.get_character_armory(uuid) to anon, authenticated;
grant execute on function public.get_character_armory_context(uuid, uuid) to anon, authenticated;
grant execute on function public.switch_active_weapon(jsonb) to anon, authenticated;

-- ===== END 109_weapon_switch_runtime_context_and_hud_fixes.sql =====
