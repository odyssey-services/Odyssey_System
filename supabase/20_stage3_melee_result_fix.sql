create or replace function public.perform_attack(p_payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_weapon_id uuid := nullif(trim(coalesce(p_payload->>'weapon_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_defense_skill_id uuid := nullif(trim(coalesce(p_payload->>'defense_skill_id', '')), '')::uuid;
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(p_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_actor_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'actor_token_id', '')), ''), '');
  v_target_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'target_token_id', '')), ''), '');
  v_manual_attack_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_bonus}', '')), '')::integer, 0);
  v_manual_attack_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_penalty}', '')), '')::integer, 0);
  v_manual_defense_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_bonus}', '')), '')::integer, 0);
  v_manual_defense_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_penalty}', '')), '')::integer, 0);
  v_hostile_adjacent_count integer := greatest(coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,hostile_adjacent_count}', '')), '')::integer, 1), 1);
  v_ignore_defense_skill boolean := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,ignore_defense_skill}', '')), '')::boolean, false);
  v_attacker public.odyssey_characters%rowtype;
  v_target public.odyssey_characters%rowtype;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_weapon_model record;
  v_fire_mode record;
  v_target_part record;
  v_attack_skill_level integer := 0;
  v_attack_skill_bonus integer := 0;
  v_attack_roll integer := 0;
  v_defense_roll integer := 0;
  v_attack_total integer := 0;
  v_defense_total integer := 0;
  v_defense_skill_level integer := 0;
  v_effective_defense_skill_level integer := 0;
  v_defense_skill_source text := 'none_for_ranged';
  v_range_json jsonb := '{}'::jsonb;
  v_range_band text := null;
  v_range_modifier integer := 0;
  v_attack_type text := null;
  v_magazine record;
  v_magazine_id uuid := null;
  v_ammo_code text := null;
  v_bullets_spent integer := 0;
  v_remaining_rounds integer := null;
  v_bullet_damage integer := 0;
  v_total_weapon_damage integer := 0;
  v_melee_strength_bonus integer := 0;
  v_strength_value integer := 0;
  v_ammo_accuracy_modifier integer := 0;
  v_ammo_damage_modifier integer := 0;
  v_armor_pierce integer := 0;
  v_raw_armor_value integer := 0;
  v_effective_armor integer := 0;
  v_hit boolean := false;
  v_damage_attack_total integer := null;
  v_damage_defense_total integer := null;
  v_damage_diff integer := null;
  v_minor_delta integer := 0;
  v_serious_delta integer := 0;
  v_critical_delta integer := 0;
  v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';
  v_new_minor integer := 0;
  v_new_serious integer := 0;
  v_new_critical integer := 0;
  v_new_armor_critical integer := 0;
  v_new_armor_value integer := 0;
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
  v_new_armor_destroyed boolean := false;
  v_body_changed boolean := false;
  v_target_state jsonb := '{}'::jsonb;
  v_message text := '';
  v_error_code text := null;
  v_error_message text := null;
  v_result jsonb := '{}'::jsonb;
  v_log_data jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_created_by text := '';
begin
  v_created_by := coalesce(v_actor_token_id, '');

  select *
  into v_attacker
  from public.odyssey_characters c
  where c.id = v_attacker_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    v_error_code := 'CHARACTER_NOT_FOUND';
    v_error_message := 'Attacker character was not found.';
  end if;

  if v_error_code is null then
    select *
    into v_target
    from public.odyssey_characters c
    where c.id = v_target_character_id
      and coalesce(c.is_deleted, false) = false;

    if not found then
      v_error_code := 'TARGET_NOT_FOUND';
      v_error_message := 'Target character was not found.';
    end if;
  end if;

  if v_error_code is null then
    select *
    into v_weapon
    from public.odyssey_character_weapons w
    where w.id = v_weapon_id
      and w.character_id = v_attacker_character_id;

    if not found then
      v_error_code := 'WEAPON_NOT_FOUND';
      v_error_message := 'Weapon was not found for the attacker.';
    end if;
  end if;

  if v_error_code is null then
    select
      wm.id,
      wm.code,
      wm.name,
      wm.weapon_class_id,
      wc.code as weapon_class_code,
      wc.name as weapon_class_name,
      wm.linked_skill_id,
      skill.code as linked_skill_code,
      skill.name as linked_skill_name,
      wm.caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      caliber.base_damage_per_round,
      wm.range_profile_id,
      rp.code as range_profile_code,
      rp.name as range_profile_name,
      wm.base_accuracy_bonus,
      wm.base_melee_damage
    into v_weapon_model
    from public.odyssey_weapon_model_defs wm
    join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
    join public.odyssey_skill_defs skill on skill.id = wm.linked_skill_id
    left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
    join public.odyssey_range_profile_defs rp on rp.id = wm.range_profile_id
    where wm.id = v_weapon.weapon_model_id;

    if not found then
      v_error_code := 'INVALID_WEAPON_MODEL';
      v_error_message := 'Weapon model linked to the weapon was not found.';
    end if;
  end if;

  if v_error_code is null then
    if v_weapon.selected_fire_mode_id is not null then
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.fire_mode_id = v_weapon.selected_fire_mode_id
      limit 1;
    else
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.is_default = true
      order by wmfm.created_at
      limit 1;
    end if;

    if not found then
      v_error_code := 'INVALID_FIRE_MODE';
      v_error_message := 'Weapon fire mode is missing or not allowed for this model.';
    end if;
  end if;

  if v_error_code is null then
    select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, b.part_key) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name,
      coalesce(d.can_be_targeted, true) as can_be_targeted,
      coalesce(d.aim_difficulty, 0) as aim_difficulty
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.id = v_target_body_part_id
      and b.character_id = v_target_character_id;

    if not found or not coalesce(v_target_part.can_be_targeted, true) then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part was not found or cannot be targeted.';
    end if;
  end if;

  if coalesce(v_campaign_id, '') = '' then
    v_campaign_id := coalesce(v_attacker.campaign_id, '');
  end if;

  if coalesce(v_room_id, '') = '' then
    v_room_id := coalesce(v_attacker.room_id, '');
  end if;

  if v_error_code is null then
    v_attack_type := case when v_weapon_model.caliber_id is null then 'melee' else 'ranged' end;

    select coalesce(s.level, 0)
    into v_attack_skill_level
    from public.odyssey_skill_defs d
    left join public.odyssey_character_skills s
      on s.skill_def_id = d.id
     and s.character_id = v_attacker_character_id
    where d.id = v_weapon_model.linked_skill_id;

    v_attack_skill_level := coalesce(v_attack_skill_level, 0);
    v_attack_skill_bonus := v_attack_skill_level * 10;
  end if;

  if v_error_code is null then
    v_range_json := public.get_weapon_range_modifier(v_weapon_model.id, v_distance_m);
    v_range_band := nullif(coalesce(v_range_json->>'range_band', ''), '');
    v_range_modifier := coalesce((v_range_json->>'modifier')::integer, 0);
  end if;

  if v_error_code is null and v_attack_type = 'ranged' then
    if v_weapon.loaded_magazine_id is null then
      v_error_code := 'NO_MAGAZINE';
      v_error_message := 'Weapon requires a loaded magazine.';
    else
      select
        cm.id,
        cm.character_id,
        cm.magazine_def_id,
        cm.ammo_type_id,
        cm.current_rounds,
        md.code as magazine_def_code,
        md.name as magazine_def_name,
        md.capacity,
        md.caliber_id as magazine_caliber_id,
        caliber.code as magazine_caliber_code,
        ammo.code as ammo_code,
        ammo.name as ammo_name,
        ammo.caliber_id as ammo_caliber_id,
        ammo.damage_modifier,
        ammo.accuracy_modifier,
        ammo.armor_pierce
      into v_magazine
      from public.odyssey_character_magazines cm
      join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
      join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
      join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
      where cm.id = v_weapon.loaded_magazine_id
        and cm.character_id = v_attacker_character_id;

      if not found then
        v_error_code := 'INVALID_MAGAZINE';
        v_error_message := 'Loaded magazine was not found or does not belong to the attacker.';
      else
        v_magazine_id := v_magazine.id;
        v_ammo_code := v_magazine.ammo_code;
      end if;

      if v_error_code is null then
        if v_magazine.magazine_caliber_id <> v_weapon_model.caliber_id
          or v_magazine.ammo_caliber_id <> v_magazine.magazine_caliber_id
          or not exists (
            select 1
            from public.odyssey_weapon_model_magazines wmm
            where wmm.weapon_model_id = v_weapon.weapon_model_id
              and wmm.magazine_def_id = v_magazine.magazine_def_id
          ) then
          v_error_code := 'INVALID_MAGAZINE';
          v_error_message := 'Loaded magazine is incompatible with the weapon model.';
        elsif coalesce(v_magazine.current_rounds, 0) <= 0 then
          v_error_code := 'NO_AMMO';
          v_error_message := 'Loaded magazine is empty.';
        else
          if coalesce(v_fire_mode.is_random, false) then
            if v_magazine.current_rounds >= coalesce(v_fire_mode.min_rounds, 1) then
              v_bullets_spent :=
                floor(
                  random()
                  * (
                      least(
                        coalesce(v_fire_mode.max_rounds, v_magazine.current_rounds),
                        v_magazine.current_rounds
                      )
                      - coalesce(v_fire_mode.min_rounds, 1)
                      + 1
                    )
                )::integer + coalesce(v_fire_mode.min_rounds, 1);
            else
              v_bullets_spent := v_magazine.current_rounds;
            end if;
          else
            v_bullets_spent := least(coalesce(v_fire_mode.fixed_rounds, 0), v_magazine.current_rounds);
          end if;

          if v_bullets_spent <= 0 then
            v_error_code := 'NO_AMMO';
            v_error_message := 'Attack cannot be made because there is no ammunition to spend.';
          else
            v_ammo_accuracy_modifier := coalesce(v_magazine.accuracy_modifier, 0);
            v_ammo_damage_modifier := coalesce(v_magazine.damage_modifier, 0);
            v_armor_pierce := coalesce(v_magazine.armor_pierce, 0);
            v_bullet_damage := greatest(coalesce(v_weapon_model.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;
            v_remaining_rounds := v_magazine.current_rounds - v_bullets_spent;
          end if;
        end if;
      end if;
    end if;
  elsif v_error_code is null then
    select coalesce(a.value, 0)
    into v_strength_value
    from public.odyssey_attribute_defs d
    left join public.odyssey_character_attributes a
      on a.attribute_def_id = d.id
     and a.character_id = v_attacker_character_id
    where d.code = 'strength';

    v_strength_value := coalesce(v_strength_value, 0);
    v_melee_strength_bonus := greatest(v_strength_value - 10, 0);
    v_total_weapon_damage := coalesce(v_weapon_model.base_melee_damage, 0) + v_melee_strength_bonus;
    v_bullet_damage := 0;
    v_ammo_accuracy_modifier := 0;
    v_ammo_damage_modifier := 0;
    v_armor_pierce := 0;
    v_magazine_id := null;
    v_ammo_code := null;
    v_remaining_rounds := null;
  end if;

  if v_error_code is null then
    if v_ignore_defense_skill then
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'ignored';
    elsif v_defense_skill_id is not null then
      select coalesce(s.level, 0)
      into v_defense_skill_level
      from public.odyssey_character_skills s
      where s.character_id = v_target_character_id
        and s.skill_def_id = v_defense_skill_id;

      v_defense_skill_level := coalesce(v_defense_skill_level, 0);
      v_effective_defense_skill_level := v_defense_skill_level;
      v_defense_skill_source := 'payload';
    elsif v_attack_type = 'melee' then
      select coalesce(s.level, 0)
      into v_defense_skill_level
      from public.odyssey_skill_defs d
      left join public.odyssey_character_skills s
        on s.skill_def_id = d.id
       and s.character_id = v_target_character_id
      where d.code = 'parry';

      v_defense_skill_level := coalesce(v_defense_skill_level, 0);
      v_effective_defense_skill_level := floor(v_defense_skill_level::numeric / v_hostile_adjacent_count)::integer;
      if v_defense_skill_level > 0 and v_effective_defense_skill_level < 1 then
        v_effective_defense_skill_level := 1;
      end if;
      v_defense_skill_source := 'fallback_parry';
    else
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'none_for_ranged';
    end if;
  end if;

  if v_error_code is null then
    v_raw_armor_value := case
      when coalesce(v_target_part.armor_destroyed, false) then 0
      else coalesce(v_target_part.armor_value, 0)
    end;

    if v_attack_type = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;

    v_attack_roll := floor(random() * 100)::integer + 1;
    v_defense_roll := floor(random() * 100)::integer + 1;

    v_attack_total :=
      v_attack_roll
      + v_attack_skill_bonus
      + coalesce(v_weapon_model.base_accuracy_bonus, 0)
      + v_ammo_accuracy_modifier
      + coalesce(v_fire_mode.accuracy_modifier, 0)
      + coalesce(v_range_modifier, 0)
      - coalesce(v_target_part.aim_difficulty, 0)
      + v_manual_attack_bonus
      - v_manual_attack_penalty;

    v_defense_total :=
      v_defense_roll
      + (v_effective_defense_skill_level * 10)
      + v_manual_defense_bonus
      - v_manual_defense_penalty;

    if v_attack_type = 'ranged' then
      update public.odyssey_character_magazines
      set current_rounds = v_remaining_rounds
      where id = v_magazine_id;
    end if;

    v_hit := v_attack_total > v_defense_total;
  end if;

  if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + v_total_weapon_damage;
    v_damage_defense_total := v_defense_total + v_effective_armor;
    v_damage_diff := v_damage_attack_total - v_damage_defense_total;

    if v_damage_diff > 90 then
      v_critical_delta := 3;
      v_damage_level := 'critical';
    elsif v_damage_diff > 60 then
      v_critical_delta := 2;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 31 then
      v_critical_delta := 1;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 6 then
      v_serious_delta := 1;
      v_damage_level := 'serious';
    elsif v_damage_diff > 0 then
      v_minor_delta := 1;
      v_damage_level := 'minor';
    else
      v_damage_level := 'no_damage';
    end if;

    v_new_minor := coalesce(v_target_part.minor, 0) + v_minor_delta;
    v_new_serious := coalesce(v_target_part.serious, 0) + v_serious_delta;
    v_new_critical := coalesce(v_target_part.critical, 0);
    v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
    v_new_armor_value := coalesce(v_target_part.armor_value, 0);
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);
    v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);

    if v_critical_delta > 0 then
      if coalesce(v_target_part.armor_value, 0) > 0
        and not coalesce(v_target_part.armor_destroyed, false)
        and coalesce(v_target_part.armor_max_critical, 0) > 0 then
        v_armor_critical_delta := least(
          v_critical_delta,
          greatest(coalesce(v_target_part.armor_max_critical, 0) - coalesce(v_target_part.armor_critical, 0), 0)
        );
        v_new_armor_critical := coalesce(v_target_part.armor_critical, 0) + v_armor_critical_delta;
        v_body_critical_delta := v_critical_delta - v_armor_critical_delta;

        if v_new_armor_critical >= coalesce(v_target_part.armor_max_critical, 0)
          and coalesce(v_target_part.armor_max_critical, 0) > 0 then
          v_new_armor_destroyed := true;
          v_new_armor_value := 0;
        end if;
      else
        v_body_critical_delta := v_critical_delta;
      end if;

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0
      or v_serious_delta > 0
      or v_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        armor_critical = v_new_armor_critical,
        armor_value = v_new_armor_value,
        armor_destroyed = v_new_armor_destroyed,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;

      v_body_changed := true;
    end if;
  end if;

  if v_body_changed then
    v_target_state := public.odyssey_refresh_character_combat_state(v_target_character_id);
  end if;

  if v_error_code is not null then
    v_log_data := jsonb_build_object(
      'type', 'attack',
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'attacker_character_id', v_attacker_character_id,
      'target_character_id', v_target_character_id,
      'weapon_id', v_weapon_id,
      'target_body_part_id', v_target_body_part_id,
      'distance_m', v_distance_m,
      'actor_token_id', v_actor_token_id,
      'target_token_id', v_target_token_id
    );

    insert into public.odyssey_combat_log (
      campaign_id,
      room_id,
      scene_id,
      encounter_id,
      actor_character_id,
      target_character_id,
      event_type,
      message,
      data,
      created_by
    )
    values (
      coalesce(v_campaign_id, ''),
      coalesce(v_room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      v_attacker_character_id,
      v_target_character_id,
      'attack',
      v_error_message,
      v_log_data,
      v_created_by
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

    return jsonb_build_object(
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'log_id', v_log_id
    );
  end if;

  if not v_hit then
    v_message := format(
      '%s attacks %s with %s and misses.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  elsif v_damage_level = 'no_damage' then
    v_message := format(
      '%s hits %s in %s with %s but deals no damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  else
    v_message := format(
      '%s hits %s in %s with %s for %s damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
      v_damage_level
    );
  end if;

  v_log_data := jsonb_build_object(
    'type', 'attack',
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon_id', v_weapon_id,
    'weapon_model_id', v_weapon_model.id,
    'weapon_name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
    'attack_type', v_attack_type,
    'target_body_part_id', v_target_part.id,
    'target_body_part_name', v_target_part.part_name,
    'distance_m', v_distance_m,
    'range_band', v_range_band,
    'range_modifier', v_range_modifier,
    'attack_roll', v_attack_roll,
    'attack_skill_level', v_attack_skill_level,
    'attack_total', v_attack_total,
    'defense_roll', v_defense_roll,
    'defense_skill_level', v_defense_skill_level,
    'effective_defense_skill_level', v_effective_defense_skill_level,
    'defense_skill_source', v_defense_skill_source,
    'hostile_adjacent_count', v_hostile_adjacent_count,
    'defense_total', v_defense_total,
    'hit', v_hit,
    'fire_mode', v_fire_mode.code,
    'bullets_spent', v_bullets_spent,
    'bullet_damage', v_bullet_damage,
    'total_weapon_damage', v_total_weapon_damage,
    'armor_value', v_raw_armor_value,
    'armor_pierce', v_armor_pierce,
    'effective_armor', v_effective_armor,
    'damage_attack_total', v_damage_attack_total,
    'damage_defense_total', v_damage_defense_total,
    'damage_diff', v_damage_diff,
    'damage_level', v_damage_level,
    'minor_delta', v_minor_delta,
    'serious_delta', v_serious_delta,
    'critical_delta', v_critical_delta,
    'armor_critical_delta', v_armor_critical_delta,
    'body_critical_delta', v_body_critical_delta,
    'remaining_magazine_rounds', v_remaining_rounds,
    'actor_token_id', v_actor_token_id,
    'target_token_id', v_target_token_id
  );

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    actor_character_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    coalesce(v_campaign_id, ''),
    coalesce(v_room_id, ''),
    coalesce(v_scene_id, ''),
    v_encounter_id,
    v_attacker_character_id,
    v_target_character_id,
    'attack',
    v_message,
    v_log_data,
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

  select
    b.minor,
    b.serious,
    b.critical,
    b.armor_value,
    b.armor_critical,
    b.armor_destroyed,
    b.disabled,
    b.destroyed
  into
    v_new_minor,
    v_new_serious,
    v_new_critical,
    v_new_armor_value,
    v_new_armor_critical,
    v_new_armor_destroyed,
    v_new_disabled,
    v_new_destroyed
  from public.odyssey_character_body_parts b
  where b.id = v_target_part.id;

  v_result := jsonb_build_object(
    'ok', true,
    'attack_type', v_attack_type,
    'hit', v_hit,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon',
      jsonb_build_object(
        'id', v_weapon_id,
        'model_id', v_weapon_model.id,
        'name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
        'base_accuracy_bonus', v_weapon_model.base_accuracy_bonus,
        'base_melee_damage', v_weapon_model.base_melee_damage
      ),
    'fire_mode',
      jsonb_build_object(
        'id', v_fire_mode.id,
        'code', v_fire_mode.code,
        'accuracy_modifier', v_fire_mode.accuracy_modifier
      ),
    'ammo',
      jsonb_build_object(
        'caliber', v_weapon_model.caliber_code,
        'ammo_type', case when v_attack_type = 'ranged' then v_ammo_code else null end,
        'bullet_damage', v_bullet_damage,
        'damage_modifier', v_ammo_damage_modifier,
        'accuracy_modifier', v_ammo_accuracy_modifier,
        'armor_pierce', v_armor_pierce
      ),
    'range',
      jsonb_build_object(
        'distance_m', v_distance_m,
        'band', v_range_band,
        'modifier', v_range_modifier
      ),
    'attack',
      jsonb_build_object(
        'roll', v_attack_roll,
        'skill_level', v_attack_skill_level,
        'skill_bonus', v_attack_skill_bonus,
        'manual_bonus', v_manual_attack_bonus,
        'manual_penalty', v_manual_attack_penalty,
        'total', v_attack_total
      ),
    'defense',
      jsonb_build_object(
        'roll', v_defense_roll,
        'skill_level', v_defense_skill_level,
        'effective_skill_level', v_effective_defense_skill_level,
        'skill_source', v_defense_skill_source,
        'hostile_adjacent_count', v_hostile_adjacent_count,
        'manual_bonus', v_manual_defense_bonus,
        'manual_penalty', v_manual_defense_penalty,
        'total', v_defense_total
      ),
    'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'body_critical_delta', v_body_critical_delta,
        'melee_strength_bonus', v_melee_strength_bonus
      ),
    'body_part',
      jsonb_build_object(
        'id', v_target_part.id,
        'name', v_target_part.part_name,
        'armor_value', v_new_armor_value,
        'effective_armor', v_effective_armor,
        'armor_critical', v_new_armor_critical,
        'armor_max_critical', coalesce(v_target_part.armor_max_critical, 0),
        'armor_destroyed', v_new_armor_destroyed,
        'minor', v_new_minor,
        'serious', v_new_serious,
        'critical', v_new_critical,
        'max_critical', coalesce(v_target_part.max_critical, 0),
        'disabled', v_new_disabled,
        'destroyed', v_new_destroyed
      ),
    'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'target_state', v_target_state,
    'log_id', v_log_id
  );

  return v_result;
end;
$$;
