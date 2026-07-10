-- ===== BEGIN 112_armory_runtime_and_abilities_ambiguity_hotfix.sql =====
--
-- Hotfix goals:
--   1. Re-assert read-only armory runtime path so old 109-style initialization
--      logic cannot leak back into the active RPC.
--   2. Remove ambiguous column references from get_character_abilities(),
--      where level_data.* introduced duplicate names such as id/data/sort_order.

create or replace function public.get_character_armory_context(
  p_character_id uuid,
  p_encounter_id uuid default null
)
returns jsonb
language plpgsql
stable
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
stable
set search_path = public
as $$
begin
  return public.get_character_armory_context(p_character_id, null::uuid);
end;
$$;

drop function if exists public.get_character_armory(uuid, uuid);

create or replace function public.get_character_abilities(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_character_exists boolean := false;
  v_resource_pools jsonb := '[]'::jsonb;
  v_abilities jsonb := '[]'::jsonb;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  into v_character_exists;

  if not v_character_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id,
      'resource_pools', '[]'::jsonb,
      'abilities', '[]'::jsonb
    );
  end if;

  with resource_rows as (
    select
      d.sort_order,
      d.code,
      jsonb_build_object(
        'id', p.id,
        'resource_pool_def_id', d.id,
        'code', d.code,
        'name', d.name,
        'source_type', d.source_type,
        'attribute_code', attr.code,
        'recovery_mode', d.recovery_mode,
        'current_value',
          coalesce(
            p.current_value,
            case
              when d.default_current_value is not null then least(d.default_current_value, case
                when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
                else greatest(coalesce(d.default_max_value, 0), 0)
              end)
              when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
              else greatest(coalesce(d.default_max_value, 0), 0)
            end,
            0
          ),
        'max_value',
          case
            when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
            else greatest(coalesce(d.default_max_value, 0), 0)
          end,
        'reserved_value', coalesce(p.reserved_value, 0),
        'description', d.description,
        'data', coalesce(p.data, '{}'::jsonb),
        'notes', coalesce(p.notes, ''),
        'tags', d.tags
      ) as payload
    from public.odyssey_resource_pool_defs d
    left join public.odyssey_attribute_defs attr on attr.id = d.attribute_def_id
    left join public.odyssey_character_attributes a
      on a.character_id = p_character_id
     and a.attribute_def_id = d.attribute_def_id
    left join public.odyssey_character_resource_pools p
      on p.character_id = p_character_id
     and p.resource_pool_def_id = d.id
  )
  select coalesce(jsonb_agg(payload order by sort_order, code), '[]'::jsonb)
  into v_resource_pools
  from resource_rows;

  with ability_rows as (
    select
      ability.sort_order as character_sort_order,
      def.sort_order as def_sort_order,
      def.code as ability_code,
      ability.id as character_ability_id,
      ability.character_id,
      def.id as ability_def_id,
      def.name as ability_name,
      def.ability_kind,
      def.source_type as ability_source_type,
      def.activation_type,
      def.target_type,
      def.effect_mode,
      def.attack_type,
      def.description,
      def.linked_skill_id,
      def.resource_mode as ability_resource_mode,
      def.resource_pool_code as ability_resource_pool_code,
      def.resource_item_code as ability_resource_item_code,
      linked_def.code as linked_skill_code,
      linked_def.name as linked_skill_name,
      coalesce(direct_skill.id, linked_skill.id) as resolved_character_skill_id,
      coalesce(direct_skill.level, linked_skill.level, 0) as resolved_character_skill_level,
      ability.learned_level,
      greatest(coalesce(direct_skill.level, linked_skill.level, ability.learned_level, 0), 0) as effective_level,
      ability.is_enabled,
      ability.is_hidden,
      ability.current_cooldown_rounds,
      ability.current_charges,
      ability.max_charges,
      ability.source_equipment_item_id,
      ability.source_character_item_id,
      ability.source_character_weapon_id,
      ability.data as ability_runtime_data,
      ability.notes as ability_notes,
      def.tags as ability_tags,
      level_data.ability_level as level_ability_level,
      level_data.resource_cost as level_resource_cost,
      level_data.cooldown_rounds as level_cooldown_rounds,
      level_data.range_profile_id as level_range_profile_id,
      level_data.attack_accuracy_bonus as level_attack_accuracy_bonus,
      level_data.attack_damage_bonus as level_attack_damage_bonus,
      level_data.attack_armor_pierce as level_attack_armor_pierce,
      level_data.ignore_armor as level_ignore_armor,
      level_data.special_armor_value as level_special_armor_value,
      level_data.special_max_critical as level_special_max_critical,
      level_data.duration_rounds as level_duration_rounds,
      level_data.data as level_payload_data,
      level_data.effect_data as level_effect_payload,
      source_weapon.custom_name as source_weapon_custom_name,
      source_weapon_model.id as source_weapon_model_id,
      source_weapon_model.code as source_weapon_model_code,
      source_weapon_model.name as source_weapon_model_name,
      source_weapon_profile.id as source_weapon_active_profile_id,
      source_weapon_profile.code as source_weapon_active_profile_code
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    left join public.odyssey_skill_defs linked_def on linked_def.id = def.linked_skill_id
    left join public.odyssey_character_skills direct_skill
      on direct_skill.id = ability.character_skill_id
    left join public.odyssey_character_skills linked_skill
      on ability.character_skill_id is null
     and linked_skill.character_id = ability.character_id
     and linked_skill.skill_def_id = def.linked_skill_id
    left join lateral (
      select
        level_entry.ability_level,
        level_entry.resource_cost,
        level_entry.cooldown_rounds,
        level_entry.range_profile_id,
        level_entry.attack_accuracy_bonus,
        level_entry.attack_damage_bonus,
        level_entry.attack_armor_pierce,
        level_entry.ignore_armor,
        level_entry.special_armor_value,
        level_entry.special_max_critical,
        level_entry.duration_rounds,
        level_entry.data,
        level_entry.effect_data
      from public.odyssey_ability_level_defs level_entry
      where level_entry.ability_def_id = def.id
        and level_entry.ability_level <= greatest(coalesce(direct_skill.level, linked_skill.level, ability.learned_level, 0), 0)
      order by level_entry.ability_level desc
      limit 1
    ) level_data on true
    left join public.odyssey_character_weapons source_weapon on source_weapon.id = ability.source_character_weapon_id
    left join public.odyssey_weapon_model_defs source_weapon_model on source_weapon_model.id = source_weapon.weapon_model_id
    left join public.odyssey_weapon_model_profiles source_weapon_profile on source_weapon_profile.id = source_weapon.active_profile_id
    where ability.character_id = p_character_id
      and ability.is_hidden = false
      and ability.is_enabled = true
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ability_rows.character_ability_id,
        'character_id', ability_rows.character_id,
        'ability_def_id', ability_rows.ability_def_id,
        'code', ability_rows.ability_code,
        'name', ability_rows.ability_name,
        'ability_kind', ability_rows.ability_kind,
        'source_type', ability_rows.ability_source_type,
        'activation_type', ability_rows.activation_type,
        'target_type', ability_rows.target_type,
        'effect_mode', ability_rows.effect_mode,
        'attack_type', ability_rows.attack_type,
        'description', ability_rows.description,
        'linked_skill_id', ability_rows.linked_skill_id,
        'linked_skill_code', ability_rows.linked_skill_code,
        'linked_skill_name', ability_rows.linked_skill_name,
        'character_skill_id', ability_rows.resolved_character_skill_id,
        'character_skill_level', ability_rows.resolved_character_skill_level,
        'learned_level', ability_rows.learned_level,
        'effective_level', ability_rows.effective_level,
        'is_enabled', ability_rows.is_enabled,
        'is_hidden', ability_rows.is_hidden,
        'current_cooldown_rounds', ability_rows.current_cooldown_rounds,
        'current_charges', ability_rows.current_charges,
        'max_charges', ability_rows.max_charges,
        'resource',
          jsonb_build_object(
            'mode', coalesce(nullif(ability_rows.ability_resource_mode, ''), 'none'),
            'pool_code', coalesce(nullif(ability_rows.ability_resource_pool_code, ''), null),
            'item_code', coalesce(nullif(ability_rows.ability_resource_item_code, ''), null),
            'cost', coalesce(ability_rows.level_resource_cost, 0)
          ),
        'source_equipment_item_id', ability_rows.source_equipment_item_id,
        'source_character_item_id', ability_rows.source_character_item_id,
        'source_character_weapon_id', ability_rows.source_character_weapon_id,
        'source',
          case
            when ability_rows.source_character_weapon_id is not null then jsonb_strip_nulls(
              jsonb_build_object(
                'type', 'weapon',
                'character_weapon_id', ability_rows.source_character_weapon_id,
                'weapon_name', coalesce(nullif(trim(ability_rows.source_weapon_custom_name), ''), ability_rows.source_weapon_model_name),
                'weapon_model_id', ability_rows.source_weapon_model_id,
                'weapon_model_code', ability_rows.source_weapon_model_code,
                'required_profile_id', nullif(trim(coalesce(ability_rows.ability_runtime_data->>'required_profile_id', '')), ''),
                'required_profile_code', nullif(trim(coalesce(ability_rows.ability_runtime_data->>'required_profile_code', '')), ''),
                'is_available_for_active_profile',
                  case
                    when nullif(trim(coalesce(ability_rows.ability_runtime_data->>'required_profile_id', '')), '') is null then true
                    else ability_rows.source_weapon_active_profile_id::text = nullif(trim(coalesce(ability_rows.ability_runtime_data->>'required_profile_id', '')), '')
                  end
              )
            )
            when ability_rows.source_equipment_item_id is not null then jsonb_strip_nulls(
              jsonb_build_object(
                'type', 'equipment',
                'character_equipment_item_id', ability_rows.source_equipment_item_id
              )
            )
            when ability_rows.source_character_item_id is not null then jsonb_strip_nulls(
              jsonb_build_object(
                'type', 'item',
                'character_item_id', ability_rows.source_character_item_id
              )
            )
            else jsonb_strip_nulls(
              jsonb_build_object(
                'type', coalesce(nullif(trim(coalesce(ability_rows.ability_runtime_data->>'generated_from', '')), ''), ability_rows.ability_source_type)
              )
            )
          end,
        'data', ability_rows.ability_runtime_data,
        'notes', ability_rows.ability_notes,
        'tags', ability_rows.ability_tags,
        'level',
          jsonb_strip_nulls(
            jsonb_build_object(
              'ability_level', ability_rows.level_ability_level,
              'resource_cost', ability_rows.level_resource_cost,
              'cooldown_rounds', ability_rows.level_cooldown_rounds,
              'range_profile_id', ability_rows.level_range_profile_id,
              'attack_accuracy_bonus', ability_rows.level_attack_accuracy_bonus,
              'attack_damage_bonus', ability_rows.level_attack_damage_bonus,
              'attack_armor_pierce', ability_rows.level_attack_armor_pierce,
              'ignore_armor', ability_rows.level_ignore_armor,
              'special_armor_value', ability_rows.level_special_armor_value,
              'special_max_critical', ability_rows.level_special_max_critical,
              'duration_rounds', ability_rows.level_duration_rounds,
              'data', ability_rows.level_payload_data,
              'effect_data', ability_rows.level_effect_payload
            )
          )
      )
      order by ability_rows.character_sort_order, ability_rows.def_sort_order, ability_rows.ability_code, ability_rows.character_ability_id
    ),
    '[]'::jsonb
  )
  into v_abilities
  from ability_rows;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'resource_pools', v_resource_pools,
    'abilities', v_abilities
  );
end;
$$;

grant execute on function public.get_character_armory_context(uuid, uuid) to anon, authenticated;
grant execute on function public.get_character_armory(uuid) to anon, authenticated;
grant execute on function public.get_character_abilities(uuid) to anon, authenticated;

-- ===== END 112_armory_runtime_and_abilities_ambiguity_hotfix.sql =====
