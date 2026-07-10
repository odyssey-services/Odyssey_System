-- ===== BEGIN 110_readonly_quick_actions_and_armory_hotfix.sql =====
-- Hotfix goals:
-- 1. Keep odyssey_get_character_quick_actions_runtime(uuid) strictly read-only.
-- 2. Keep get_character_armory_context/get_character_armory strictly read-only.
-- 3. Avoid helper chains that may attempt row locks from STABLE RPCs.

create or replace function public.odyssey_get_character_quick_actions_runtime(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_character_exists boolean := false;
  v_is_alive boolean := true;
  v_has_skip_turn_effect boolean := false;
  v_quick_actions jsonb := '[]'::jsonb;
  v_layout jsonb := jsonb_build_object('slots', '[]'::jsonb);
  v_version integer := 0;
  v_selected_weapon_id uuid := null;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and not coalesce(c.is_deleted, false)
  )
  into v_character_exists;

  if not v_character_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character does not exist or is deleted',
      'characterId', p_character_id,
      'quickActions', '[]'::jsonb,
      'quickbar', jsonb_build_object('slots', '[]'::jsonb, 'maxSlots', 20, 'version', 0)
    );
  end if;

  select coalesce(cs.is_alive, true)
  into v_is_alive
  from public.odyssey_characters c
  left join public.odyssey_character_combat_state cs on cs.character_id = c.id
  where c.id = p_character_id;

  v_has_skip_turn_effect := public.odyssey_character_has_active_effect_flag(
    p_character_id,
    'skip_turn'
  );

  v_selected_weapon_id := public.odyssey_get_character_active_weapon_id(p_character_id);

  select t.layout, t.version
  into v_layout, v_version
  from public.odyssey_character_quickbar_layouts t
  where t.character_id = p_character_id;

  v_layout := coalesce(v_layout, jsonb_build_object('slots', '[]'::jsonb));
  v_version := coalesce(v_version, 0);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'characterActionId', ability.id,
        'definitionId', def.id,
        'characterSkillId', ability.character_skill_id,
        'sourceCharacterWeaponId',
          case when ability.source_character_weapon_id is not null then ability.source_character_weapon_id::text else null end,
        'sourceEquipmentItemId',
          case when ability.source_equipment_item_id is not null then ability.source_equipment_item_id::text else null end,
        'sourceCharacterItemId',
          case when ability.source_character_item_id is not null then ability.source_character_item_id::text else null end,
        'sourceType',
          case
            when ability.source_character_weapon_id is not null then 'weapon'
            when ability.source_equipment_item_id is not null then case
              when equipment_model.item_type in ('armor', 'shield', 'special_protection') then 'armor'
              when equipment_model.item_type = 'implant' then 'implant'
              when equipment_model.item_type = 'prosthetic' then 'prosthetic'
              else coalesce(nullif(trim(coalesce(ability.data->>'generated_from', '')), ''), 'equipment')
            end
            when ability.source_character_item_id is not null then 'item'
            else coalesce(
              nullif(trim(coalesce(ability.data->>'generated_from', '')), ''),
              nullif(trim(coalesce(def.source_type, '')), ''),
              'custom'
            )
          end,
        'sourceLabel',
          case
            when ability.source_character_weapon_id is not null then coalesce(
              nullif(trim(coalesce(weapon.custom_name, '')), ''),
              weapon_model.name,
              def.name
            )
            when ability.source_equipment_item_id is not null then coalesce(
              nullif(trim(coalesce(equipment.custom_name, '')), ''),
              equipment_model.name,
              def.name
            )
            when ability.source_character_item_id is not null then coalesce(
              nullif(trim(coalesce(item.custom_name, '')), ''),
              item_def.name,
              def.name
            )
            else coalesce(
              nullif(trim(coalesce(ability.data->>'source_label', '')), ''),
              def.name
            )
          end,
        'type',
          case
            when coalesce(def.effect_mode, '') = 'attack' or def.ability_kind = 'attack' then 'attack_technique'
            when coalesce(def.target_type, 'none') in ('character', 'body_part') then 'directed'
            else 'instant'
          end,
        'name', def.name,
        'shortDescription', substring(def.description, 1, 100),
        'fullDescription', def.description,
        'iconKey', coalesce(def.data->>'icon_key', 'bolt'),
        'semanticKind', def.ability_kind,
        'targeting',
          jsonb_build_object(
            'mode', coalesce(def.target_type, 'none'),
            'minTargets', 1,
            'maxTargets', 1,
            'allowAllies', true,
            'allowSelf', def.target_type = 'self',
            'requiresBodyZone', def.target_type = 'body_part'
          ),
        'costs',
          jsonb_build_object(
            'main', case when def.resource_mode = 'pool' then 1 else 0 end,
            'move', 0,
            'psi',
              case
                when def.resource_pool_code = 'psi'
                  then coalesce((level_data.data->>'psi_cost')::integer, coalesce(level_data.resource_cost, 0), 0)
                else 0
              end,
            'charges', coalesce(ability.current_charges, 0)
          ),
        'cooldown',
          jsonb_build_object(
            'current', coalesce(ability.current_cooldown_rounds, 0),
            'max', coalesce(level_data.cooldown_rounds, 0),
            'unit', 'turn'
          ),
        'reload',
          jsonb_strip_nulls(
            jsonb_build_object(
              'required',
                ability.max_charges is not null
                and coalesce(ability.current_charges, 0) <= 0,
              'itemCode',
                coalesce(
                  nullif(trim(coalesce(ability.data#>>'{reload,item_code}', '')), ''),
                  nullif(trim(coalesce(ability.data->>'reload_item_code', '')), ''),
                  nullif(trim(coalesce(ability.data->>'requires_reload_item_code', '')), ''),
                  nullif(trim(coalesce(def.resource_item_code, '')), '')
                ),
              'itemCost',
                case
                  when coalesce(ability.data#>>'{reload,item_cost_per_reload}', '') ~ '^-?[0-9]+$'
                    then greatest((ability.data#>>'{reload,item_cost_per_reload}')::integer, 1)
                  when coalesce(ability.data->>'reload_item_cost', '') ~ '^-?[0-9]+$'
                    then greatest((ability.data->>'reload_item_cost')::integer, 1)
                  else 1
                end
            )
          ),
        'state',
          jsonb_build_object(
            'available',
              ability.is_enabled
              and not v_has_skip_turn_effect
              and (v_is_alive or def.target_type = 'none')
              and coalesce(ability.current_cooldown_rounds, 0) <= 0
              and not coalesce(resource_state.insufficient_pool, false)
              and not coalesce(resource_state.insufficient_charges, false)
              and coalesce(source_state.available, true),
            'active', false,
            'disabledReason',
              case
                when not ability.is_enabled then 'Ability is disabled'
                when v_has_skip_turn_effect then 'Skipping turn'
                when not v_is_alive and def.target_type <> 'none' then 'Character is dead'
                when coalesce(ability.current_cooldown_rounds, 0) > 0
                  then format('Cooldown: %s turns', ability.current_cooldown_rounds)
                when coalesce(resource_state.insufficient_pool, false)
                  then format('Not enough %s', coalesce(def.resource_pool_code, 'resource'))
                when coalesce(resource_state.insufficient_charges, false) then coalesce(
                  case
                    when nullif(trim(coalesce(source_state.reload_item_code, '')), '') is not null
                      then format('Reload with %s.', source_state.reload_item_code)
                    else 'No charges left'
                  end,
                  'No charges left'
                )
                when coalesce(source_state.available, true) = false then source_state.disabled_reason
                else null
              end,
            'selectable',
              ability.is_enabled
              and not v_has_skip_turn_effect
              and (v_is_alive or def.target_type = 'none')
              and coalesce(ability.current_cooldown_rounds, 0) <= 0
              and not coalesce(resource_state.insufficient_pool, false)
              and not coalesce(resource_state.insufficient_charges, false)
              and coalesce(source_state.available, true),
            'executionAvailable', true,
            'executionReason', null,
            'resourceSufficient',
              not (
                coalesce(resource_state.insufficient_pool, false)
                or coalesce(resource_state.insufficient_charges, false)
              )
          ),
        'requirements',
          jsonb_strip_nulls(
            jsonb_build_object(
              'weaponClass', null,
              'weaponId',
                case when ability.source_character_weapon_id is not null then ability.source_character_weapon_id::text else null end,
              'equipmentItemId',
                case when ability.source_equipment_item_id is not null then ability.source_equipment_item_id::text else null end,
              'itemId',
                case when ability.source_character_item_id is not null then ability.source_character_item_id::text else null end,
              'requiresSelectedSource', coalesce(source_state.requires_selected_source, false),
              'requiresEquipped', coalesce(source_state.requires_equipped, false),
              'requiresInstalled', coalesce(source_state.requires_installed, false),
              'conditionSummary', source_state.disabled_reason
            )
          )
      )
      order by ability.sort_order, ability.created_at, ability.id
    ),
    '[]'::jsonb
  )
  into v_quick_actions
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  left join public.odyssey_character_skills direct_skill on direct_skill.id = ability.character_skill_id
  left join lateral (
    select states.skill_def_id, states.effective_level
    from public.odyssey_get_effective_character_skill_states(ability.character_id) states
    where states.skill_def_id = coalesce(direct_skill.skill_def_id, def.linked_skill_id)
    order by states.effective_level desc, states.skill_def_id
    limit 1
  ) effective_skill on true
  left join lateral (
    select level_entry.*
    from public.odyssey_ability_level_defs level_entry
    where level_entry.ability_def_id = def.id
      and level_entry.ability_level <= greatest(
        coalesce(effective_skill.effective_level, 0),
        coalesce(ability.learned_level, 0),
        0
      )
    order by level_entry.ability_level desc
    limit 1
  ) level_data on true
  left join public.odyssey_resource_pool_defs rpd on rpd.code = def.resource_pool_code
  left join public.odyssey_character_resource_pools rp
    on rp.character_id = ability.character_id
   and rp.resource_pool_def_id = rpd.id
  left join public.odyssey_character_weapons weapon on weapon.id = ability.source_character_weapon_id
  left join public.odyssey_weapon_model_defs weapon_model on weapon_model.id = weapon.weapon_model_id
  left join public.odyssey_character_equipment_items equipment on equipment.id = ability.source_equipment_item_id
  left join public.odyssey_equipment_model_defs equipment_model on equipment_model.id = equipment.equipment_model_id
  left join public.odyssey_character_items item on item.id = ability.source_character_item_id
  left join public.odyssey_item_defs item_def on item_def.id = item.item_def_id
  left join lateral (
    select
      case
        when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('true', '1', 'yes', 'on') then true
        when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('false', '0', 'no', 'off') then false
        else ability.source_character_weapon_id is not null
      end as requires_selected_source,
      case
        when lower(coalesce(ability.data->>'requires_equipped', '')) in ('true', '1', 'yes', 'on') then true
        when lower(coalesce(ability.data->>'requires_equipped', '')) in ('false', '0', 'no', 'off') then false
        else coalesce(nullif(trim(coalesce(ability.data->>'generated_from', '')), ''), '') = 'armor'
      end as requires_equipped,
      case
        when lower(coalesce(ability.data->>'requires_installed', '')) in ('true', '1', 'yes', 'on') then true
        when lower(coalesce(ability.data->>'requires_installed', '')) in ('false', '0', 'no', 'off') then false
        else coalesce(nullif(trim(coalesce(ability.data->>'generated_from', '')), ''), '') in ('equipment', 'implant', 'prosthetic')
      end as requires_installed,
      coalesce(
        nullif(trim(coalesce(ability.data#>>'{reload,item_code}', '')), ''),
        nullif(trim(coalesce(ability.data->>'reload_item_code', '')), ''),
        nullif(trim(coalesce(ability.data->>'requires_reload_item_code', '')), ''),
        nullif(trim(coalesce(def.resource_item_code, '')), '')
      ) as reload_item_code,
      case
        when ability.source_character_weapon_id is not null then
          case
            when coalesce((ability.data->>'source_removed')::boolean, false) or weapon.id is null
              then false
            when nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '') is not null
              and weapon.active_profile_id::text <> nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '')
              then false
            when (
              case
                when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('false', '0', 'no', 'off') then false
                else true
              end
            ) and v_selected_weapon_id is distinct from ability.source_character_weapon_id
              then false
            else true
          end
        when ability.source_equipment_item_id is not null then
          case
            when coalesce((ability.data->>'source_removed')::boolean, false) or equipment.id is null
              then false
            when (
              case
                when lower(coalesce(ability.data->>'requires_equipped', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_equipped', '')) in ('false', '0', 'no', 'off') then false
                else false
              end
            ) and not coalesce(equipment.is_equipped, false)
              then false
            when (
              case
                when lower(coalesce(ability.data->>'requires_installed', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_installed', '')) in ('false', '0', 'no', 'off') then false
                else coalesce(equipment_model.item_type, '') in ('implant', 'prosthetic')
              end
            )
              and not coalesce(equipment.is_equipped, false)
              and equipment.equipped_body_part_id is null
              then false
            else true
          end
        when ability.source_character_item_id is not null then
          not (
            coalesce((ability.data->>'source_removed')::boolean, false)
            or item.id is null
            or coalesce(item.quantity, 0) <= 0
          )
        else
          not coalesce((ability.data->>'source_removed')::boolean, false)
      end as available,
      case
        when ability.source_character_weapon_id is not null then
          case
            when coalesce((ability.data->>'source_removed')::boolean, false) or weapon.id is null
              then format(
                '%s is no longer available.',
                coalesce(nullif(trim(coalesce(weapon.custom_name, '')), ''), weapon_model.name, def.name)
              )
            when nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '') is not null
              and weapon.active_profile_id::text <> nullif(trim(coalesce(ability.data->>'required_profile_id', '')), '')
              then format(
                'Switch %s profile.',
                coalesce(nullif(trim(coalesce(weapon.custom_name, '')), ''), weapon_model.name, def.name)
              )
            when (
              case
                when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_selected_source', '')) in ('false', '0', 'no', 'off') then false
                else true
              end
            ) and v_selected_weapon_id is distinct from ability.source_character_weapon_id
              then format(
                'Select %s.',
                coalesce(nullif(trim(coalesce(weapon.custom_name, '')), ''), weapon_model.name, def.name)
              )
            else null
          end
        when ability.source_equipment_item_id is not null then
          case
            when coalesce((ability.data->>'source_removed')::boolean, false) or equipment.id is null
              then format(
                '%s is no longer available.',
                coalesce(nullif(trim(coalesce(equipment.custom_name, '')), ''), equipment_model.name, def.name)
              )
            when (
              case
                when lower(coalesce(ability.data->>'requires_equipped', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_equipped', '')) in ('false', '0', 'no', 'off') then false
                else false
              end
            ) and not coalesce(equipment.is_equipped, false)
              then format(
                'Equip %s.',
                coalesce(nullif(trim(coalesce(equipment.custom_name, '')), ''), equipment_model.name, def.name)
              )
            when (
              case
                when lower(coalesce(ability.data->>'requires_installed', '')) in ('true', '1', 'yes', 'on') then true
                when lower(coalesce(ability.data->>'requires_installed', '')) in ('false', '0', 'no', 'off') then false
                else coalesce(equipment_model.item_type, '') in ('implant', 'prosthetic')
              end
            )
              and not coalesce(equipment.is_equipped, false)
              and equipment.equipped_body_part_id is null
              then format(
                'Install %s.',
                coalesce(nullif(trim(coalesce(equipment.custom_name, '')), ''), equipment_model.name, def.name)
              )
            else null
          end
        when ability.source_character_item_id is not null then
          case
            when coalesce((ability.data->>'source_removed')::boolean, false)
               or item.id is null
               or coalesce(item.quantity, 0) <= 0
              then format(
                '%s is no longer available.',
                coalesce(nullif(trim(coalesce(item.custom_name, '')), ''), item_def.name, def.name)
              )
            else null
          end
        else
          case
            when coalesce((ability.data->>'source_removed')::boolean, false)
              then format(
                '%s is no longer available.',
                coalesce(nullif(trim(coalesce(ability.data->>'source_label', '')), ''), def.name)
              )
            else null
          end
      end as disabled_reason
  ) source_state on true
  left join lateral (
    select
      (def.resource_mode = 'pool' and coalesce(rp.current_value, 0) < coalesce(level_data.resource_cost, 0)) as insufficient_pool,
      (ability.max_charges is not null and coalesce(ability.current_charges, 0) <= 0) as insufficient_charges
  ) resource_state on true
  where ability.character_id = p_character_id
    and ability.is_hidden = false
    and ability.is_enabled = true
    and def.ability_kind != 'passive'
    and def.activation_type in ('manual', 'custom');

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

grant execute on function public.odyssey_get_character_quick_actions_runtime(uuid) to anon, authenticated;
grant execute on function public.get_character_armory_context(uuid, uuid) to anon, authenticated;
grant execute on function public.get_character_armory(uuid) to anon, authenticated;

-- ===== END 110_readonly_quick_actions_and_armory_hotfix.sql =====
