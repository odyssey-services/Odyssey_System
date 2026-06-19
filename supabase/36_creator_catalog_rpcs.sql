create extension if not exists pgcrypto;

create or replace function public.odyssey_creator_error(
  p_error text,
  p_message text,
  p_details jsonb default '[]'::jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'ok', false,
    'error', coalesce(nullif(trim(coalesce(p_error, '')), ''), 'VALIDATION_ERROR'),
    'message', coalesce(nullif(trim(coalesce(p_message, '')), ''), 'Validation failed.'),
    'details',
      case
        when jsonb_typeof(p_details) = 'array' then p_details
        when p_details is null then '[]'::jsonb
        else jsonb_build_array(p_details)
      end
  );
$$;

create or replace function public.odyssey_creator_normalize_code(
  p_code text
)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_code, '')));
$$;

create or replace function public.odyssey_creator_is_valid_code(
  p_code text
)
returns boolean
language sql
immutable
as $$
  select public.odyssey_creator_normalize_code(p_code) ~ '^[a-z][a-z0-9_]*$';
$$;

create or replace function public.odyssey_creator_normalize_json_object(
  p_value jsonb
)
returns jsonb
language sql
immutable
as $$
  select
    case
      when jsonb_typeof(p_value) = 'object' then p_value
      else '{}'::jsonb
    end;
$$;

create or replace function public.odyssey_creator_normalize_json_array(
  p_value jsonb
)
returns jsonb
language sql
immutable
as $$
  select
    case
      when jsonb_typeof(p_value) = 'array' then p_value
      else '[]'::jsonb
    end;
$$;

create or replace function public.odyssey_creator_normalize_text_array(
  p_value jsonb
)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(trim(entry.value)) order by entry.ordinality)
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(p_value) = 'array' then p_value
          else '[]'::jsonb
        end
      ) with ordinality as entry(value, ordinality)
      where trim(entry.value) <> ''
    ),
    '[]'::jsonb
  );
$$;

create or replace function public.odyssey_creator_build_weapon_bundle(
  p_weapon_model_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_weapon jsonb := null;
  v_profiles jsonb := '[]'::jsonb;
  v_fire_modes jsonb := '[]'::jsonb;
  v_magazines jsonb := '[]'::jsonb;
  v_features jsonb := '[]'::jsonb;
  v_ability_links jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'id', wm.id,
    'code', wm.code,
    'name', wm.name,
    'weapon_class_id', wm.weapon_class_id,
    'weapon_class_code', wc.code,
    'weapon_class_name', wc.name,
    'linked_skill_id', wm.linked_skill_id,
    'linked_skill_code', skill.code,
    'linked_skill_name', skill.name,
    'caliber_id', wm.caliber_id,
    'caliber_code', caliber.code,
    'caliber_name', caliber.name,
    'range_profile_id', wm.range_profile_id,
    'range_profile_code', range_profile.code,
    'range_profile_name', range_profile.name,
    'base_accuracy_bonus', wm.base_accuracy_bonus,
    'base_melee_damage', coalesce(wm.base_melee_damage, 0),
    'description', coalesce(wm.description, ''),
    'tags', coalesce(wm.tags, '[]'::jsonb),
    'is_custom', wm.is_custom,
    'sort_order', wm.sort_order,
    'created_at', wm.created_at,
    'updated_at', wm.updated_at
  )
  into v_weapon
  from public.odyssey_weapon_model_defs wm
  left join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
  left join public.odyssey_skill_defs skill on skill.id = wm.linked_skill_id
  left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
  left join public.odyssey_range_profile_defs range_profile on range_profile.id = wm.range_profile_id
  where wm.id = p_weapon_model_id;

  if v_weapon is null then
    return public.odyssey_creator_error(
      'WEAPON_NOT_FOUND',
      'Weapon model was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown weapon model id.'))
    );
  end if;

  select coalesce(
    jsonb_agg(profile_row.item order by profile_row.sort_order, profile_row.name, profile_row.code),
    '[]'::jsonb
  )
  into v_profiles
  from (
    select
      p.sort_order,
      p.name,
      p.code,
      jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'name', p.name,
        'description', p.description,
        'attack_type', p.attack_type,
        'weapon_class_id', p.weapon_class_id,
        'weapon_class_code', wc.code,
        'weapon_class_name', wc.name,
        'linked_skill_id', p.linked_skill_id,
        'linked_skill_code', skill.code,
        'linked_skill_name', skill.name,
        'caliber_id', p.caliber_id,
        'caliber_code', caliber.code,
        'caliber_name', caliber.name,
        'range_profile_id', p.range_profile_id,
        'range_profile_code', range_profile.code,
        'range_profile_name', range_profile.name,
        'accuracy_modifier', p.accuracy_modifier,
        'base_melee_damage', p.base_melee_damage,
        'is_default', p.is_default,
        'sort_order', p.sort_order,
        'data', coalesce(p.data, '{}'::jsonb),
        'tags', coalesce(p.tags, '[]'::jsonb),
        'default_fire_mode_id',
          (
            select pfm.fire_mode_id
            from public.odyssey_weapon_profile_fire_modes pfm
            where pfm.profile_id = p.id
            order by pfm.is_default desc, pfm.sort_order, pfm.created_at, pfm.id
            limit 1
          ),
        'default_magazine_def_id',
          (
            select ppm.magazine_def_id
            from public.odyssey_weapon_profile_magazines ppm
            where ppm.profile_id = p.id
            order by ppm.is_default desc, ppm.sort_order, ppm.created_at, ppm.id
            limit 1
          ),
        'fire_mode_ids',
          coalesce(
            (
              select jsonb_agg(to_jsonb(pfm.fire_mode_id) order by pfm.sort_order, pfm.created_at, pfm.id)
              from public.odyssey_weapon_profile_fire_modes pfm
              where pfm.profile_id = p.id
            ),
            '[]'::jsonb
          ),
        'magazine_def_ids',
          coalesce(
            (
              select jsonb_agg(to_jsonb(ppm.magazine_def_id) order by ppm.sort_order, ppm.created_at, ppm.id)
              from public.odyssey_weapon_profile_magazines ppm
              where ppm.profile_id = p.id
            ),
            '[]'::jsonb
          )
      ) as item
    from public.odyssey_weapon_model_profiles p
    left join public.odyssey_weapon_class_defs wc on wc.id = p.weapon_class_id
    left join public.odyssey_skill_defs skill on skill.id = p.linked_skill_id
    left join public.odyssey_caliber_defs caliber on caliber.id = p.caliber_id
    left join public.odyssey_range_profile_defs range_profile on range_profile.id = p.range_profile_id
    where p.weapon_model_id = p_weapon_model_id
  ) profile_row;

  select coalesce(
    jsonb_agg(item order by sort_order, name, code),
    '[]'::jsonb
  )
  into v_fire_modes
  from (
    select distinct on (fm.id)
      fm.sort_order,
      fm.name,
      fm.code,
      jsonb_build_object(
        'id', fm.id,
        'code', fm.code,
        'name', fm.name,
        'fixed_rounds', fm.fixed_rounds,
        'min_rounds', fm.min_rounds,
        'max_rounds', fm.max_rounds,
        'is_random', fm.is_random,
        'accuracy_modifier', fm.accuracy_modifier,
        'description', coalesce(fm.description, ''),
        'tags', coalesce(fm.tags, '[]'::jsonb),
        'is_custom', fm.is_custom,
        'sort_order', fm.sort_order
      ) as item
    from public.odyssey_weapon_profile_fire_modes pfm
    join public.odyssey_weapon_model_profiles p on p.id = pfm.profile_id
    join public.odyssey_fire_mode_defs fm on fm.id = pfm.fire_mode_id
    where p.weapon_model_id = p_weapon_model_id
    order by fm.id, pfm.sort_order, pfm.created_at, pfm.id
  ) linked_modes;

  select coalesce(
    jsonb_agg(item order by sort_order, name, code),
    '[]'::jsonb
  )
  into v_magazines
  from (
    select distinct on (mag.id)
      mag.sort_order,
      mag.name,
      mag.code,
      jsonb_build_object(
        'id', mag.id,
        'code', mag.code,
        'name', mag.name,
        'caliber_id', mag.caliber_id,
        'caliber_code', caliber.code,
        'caliber_name', caliber.name,
        'capacity', mag.capacity,
        'description', coalesce(mag.description, ''),
        'tags', coalesce(mag.tags, '[]'::jsonb),
        'is_custom', mag.is_custom,
        'sort_order', mag.sort_order
      ) as item
    from public.odyssey_weapon_profile_magazines ppm
    join public.odyssey_weapon_model_profiles p on p.id = ppm.profile_id
    join public.odyssey_magazine_defs mag on mag.id = ppm.magazine_def_id
    join public.odyssey_caliber_defs caliber on caliber.id = mag.caliber_id
    where p.weapon_model_id = p_weapon_model_id
    order by mag.id, ppm.sort_order, ppm.created_at, ppm.id
  ) linked_magazines;

  select coalesce(
    jsonb_agg(item order by sort_order, feature_name, feature_code),
    '[]'::jsonb
  )
  into v_features
  from (
    select
      link.sort_order,
      def.name as feature_name,
      def.code as feature_code,
      jsonb_build_object(
        'id', link.id,
        'feature_def_id', link.feature_def_id,
        'feature_code', def.code,
        'feature_name', def.name,
        'feature_type', def.feature_type,
        'activation_type', def.activation_type,
        'profile_id', link.profile_id,
        'profile_code', profile.code,
        'is_enabled_by_default', link.is_enabled_by_default,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_weapon_model_features link
    join public.odyssey_weapon_feature_defs def on def.id = link.feature_def_id
    left join public.odyssey_weapon_model_profiles profile on profile.id = link.profile_id
    where link.weapon_model_id = p_weapon_model_id
  ) feature_rows;

  select coalesce(
    jsonb_agg(item order by sort_order, ability_name, ability_code),
    '[]'::jsonb
  )
  into v_ability_links
  from (
    select
      link.sort_order,
      ability.name as ability_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'ability_name', ability.name,
        'ability_kind', ability.ability_kind,
        'source_type', ability.source_type,
        'profile_id', link.profile_id,
        'profile_code', profile.code,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_weapon_model_abilities link
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    left join public.odyssey_weapon_model_profiles profile on profile.id = link.profile_id
    where link.weapon_model_id = p_weapon_model_id
  ) ability_rows;

  return jsonb_build_object(
    'ok', true,
    'weapon', v_weapon,
    'profiles', v_profiles,
    'fire_modes', v_fire_modes,
    'magazines', v_magazines,
    'features', v_features,
    'ability_links', v_ability_links
  );
end;
$$;

create or replace function public.odyssey_creator_build_equipment_model_bundle(
  p_equipment_model_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_model jsonb := null;
  v_ability_links jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'id', m.id,
    'code', m.code,
    'name', m.name,
    'item_type', m.item_type,
    'description', m.description,
    'armor_value', m.armor_value,
    'armor_max_critical', m.armor_max_critical,
    'default_body_part_code', m.default_body_part_code,
    'can_equip', m.can_equip,
    'can_equip_to_body_part', m.can_equip_to_body_part,
    'effect_data', coalesce(m.effect_data, '{}'::jsonb),
    'flags', coalesce(m.flags, '{}'::jsonb),
    'tags', coalesce(m.tags, '[]'::jsonb),
    'is_custom', m.is_custom,
    'sort_order', m.sort_order,
    'created_at', m.created_at,
    'updated_at', m.updated_at
  )
  into v_model
  from public.odyssey_equipment_model_defs m
  where m.id = p_equipment_model_id
    and m.item_type in ('armor', 'shield');

  if v_model is null then
    return public.odyssey_creator_error(
      'ARMOR_MODEL_NOT_FOUND',
      'Armor model was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown armor model id.'))
    );
  end if;

  select coalesce(
    jsonb_agg(item order by sort_order, ability_name, ability_code),
    '[]'::jsonb
  )
  into v_ability_links
  from (
    select
      link.sort_order,
      ability.name as ability_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'ability_name', ability.name,
        'ability_kind', ability.ability_kind,
        'source_type', ability.source_type,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_equipment_model_abilities link
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    where link.equipment_model_id = p_equipment_model_id
  ) rows;

  return jsonb_build_object(
    'ok', true,
    'armor_model', v_model,
    'ability_links', v_ability_links
  );
end;
$$;

create or replace function public.odyssey_creator_build_item_def_bundle(
  p_item_def_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_item jsonb := null;
  v_ability_links jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'id', i.id,
    'code', i.code,
    'name', i.name,
    'item_type', i.item_type,
    'description', i.description,
    'is_stackable', i.is_stackable,
    'default_quantity', i.default_quantity,
    'max_stack', i.max_stack,
    'default_max_charges', i.default_max_charges,
    'default_current_charges', i.default_current_charges,
    'use_action_type', i.use_action_type,
    'effect_data', coalesce(i.effect_data, '{}'::jsonb),
    'data', coalesce(i.data, '{}'::jsonb),
    'tags', coalesce(i.tags, '[]'::jsonb),
    'is_custom', i.is_custom,
    'sort_order', i.sort_order,
    'created_at', i.created_at,
    'updated_at', i.updated_at
  )
  into v_item
  from public.odyssey_item_defs i
  where i.id = p_item_def_id;

  if v_item is null then
    return public.odyssey_creator_error(
      'ITEM_DEF_NOT_FOUND',
      'Item definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown item definition id.'))
    );
  end if;

  select coalesce(
    jsonb_agg(item order by sort_order, ability_name, ability_code),
    '[]'::jsonb
  )
  into v_ability_links
  from (
    select
      link.sort_order,
      ability.name as ability_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'ability_name', ability.name,
        'ability_kind', ability.ability_kind,
        'source_type', ability.source_type,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_item_def_abilities link
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    where link.item_def_id = p_item_def_id
  ) rows;

  return jsonb_build_object(
    'ok', true,
    'item_def', v_item,
    'ability_links', v_ability_links
  );
end;
$$;

create or replace function public.odyssey_creator_build_ability_bundle(
  p_ability_def_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_ability jsonb := null;
  v_levels jsonb := '[]'::jsonb;
  v_weapon_links jsonb := '[]'::jsonb;
  v_equipment_links jsonb := '[]'::jsonb;
  v_item_links jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'id', a.id,
    'code', a.code,
    'name', a.name,
    'ability_kind', a.ability_kind,
    'source_type', a.source_type,
    'activation_type', a.activation_type,
    'target_type', a.target_type,
    'effect_mode', a.effect_mode,
    'attack_type', a.attack_type,
    'linked_skill_id', a.linked_skill_id,
    'linked_skill_code', skill.code,
    'linked_skill_name', skill.name,
    'resource_mode', a.resource_mode,
    'resource_pool_code', a.resource_pool_code,
    'resource_item_code', a.resource_item_code,
    'description', a.description,
    'data', coalesce(a.data, '{}'::jsonb),
    'effect_data', coalesce(a.effect_data, '{}'::jsonb),
    'tags', coalesce(a.tags, '[]'::jsonb),
    'is_custom', a.is_custom,
    'sort_order', a.sort_order,
    'created_at', a.created_at,
    'updated_at', a.updated_at
  )
  into v_ability
  from public.odyssey_ability_defs a
  left join public.odyssey_skill_defs skill on skill.id = a.linked_skill_id
  where a.id = p_ability_def_id;

  if v_ability is null then
    return public.odyssey_creator_error(
      'ABILITY_NOT_FOUND',
      'Ability definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown ability definition id.'))
    );
  end if;

  select coalesce(
    jsonb_agg(item order by ability_level, created_at, id),
    '[]'::jsonb
  )
  into v_levels
  from (
    select
      level.id,
      level.ability_level,
      level.created_at,
      jsonb_build_object(
        'id', level.id,
        'ability_level', level.ability_level,
        'resource_cost', level.resource_cost,
        'cooldown_rounds', level.cooldown_rounds,
        'range_profile_id', level.range_profile_id,
        'range_profile_code', range_profile.code,
        'range_profile_name', range_profile.name,
        'attack_accuracy_bonus', level.attack_accuracy_bonus,
        'attack_damage_bonus', level.attack_damage_bonus,
        'attack_armor_pierce', level.attack_armor_pierce,
        'ignore_armor', level.ignore_armor,
        'special_armor_value', level.special_armor_value,
        'special_max_critical', level.special_max_critical,
        'duration_rounds', level.duration_rounds,
        'data', coalesce(level.data, '{}'::jsonb),
        'effect_data', coalesce(level.effect_data, '{}'::jsonb),
        'created_at', level.created_at,
        'updated_at', level.updated_at
      ) as item
    from public.odyssey_ability_level_defs level
    left join public.odyssey_range_profile_defs range_profile on range_profile.id = level.range_profile_id
    where level.ability_def_id = p_ability_def_id
  ) level_rows;

  select coalesce(
    jsonb_agg(item order by sort_order, weapon_name, ability_code),
    '[]'::jsonb
  )
  into v_weapon_links
  from (
    select
      link.sort_order,
      weapon.name as weapon_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'weapon_model_id', link.weapon_model_id,
        'weapon_code', weapon.code,
        'weapon_name', weapon.name,
        'profile_id', link.profile_id,
        'profile_code', profile.code,
        'profile_name', profile.name,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_weapon_model_abilities link
    join public.odyssey_weapon_model_defs weapon on weapon.id = link.weapon_model_id
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    left join public.odyssey_weapon_model_profiles profile on profile.id = link.profile_id
    where link.ability_def_id = p_ability_def_id
  ) weapon_rows;

  select coalesce(
    jsonb_agg(item order by sort_order, equipment_name, ability_code),
    '[]'::jsonb
  )
  into v_equipment_links
  from (
    select
      link.sort_order,
      model.name as equipment_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'equipment_model_id', link.equipment_model_id,
        'equipment_code', model.code,
        'equipment_name', model.name,
        'item_type', model.item_type,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_equipment_model_abilities link
    join public.odyssey_equipment_model_defs model on model.id = link.equipment_model_id
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    where link.ability_def_id = p_ability_def_id
  ) equipment_rows;

  select coalesce(
    jsonb_agg(item order by sort_order, item_name, ability_code),
    '[]'::jsonb
  )
  into v_item_links
  from (
    select
      link.sort_order,
      item_def.name as item_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'item_def_id', link.item_def_id,
        'item_code', item_def.code,
        'item_name', item_def.name,
        'item_type', item_def.item_type,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_item_def_abilities link
    join public.odyssey_item_defs item_def on item_def.id = link.item_def_id
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    where link.ability_def_id = p_ability_def_id
  ) item_rows;

  return jsonb_build_object(
    'ok', true,
    'ability', v_ability,
    'levels', v_levels,
    'weapon_links', v_weapon_links,
    'equipment_links', v_equipment_links,
    'item_links', v_item_links
  );
end;
$$;

create or replace function public.odyssey_creator_build_perk_bundle(
  p_perk_def_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_perk jsonb := null;
begin
  select jsonb_build_object(
    'id', p.id,
    'code', p.code,
    'name', p.name,
    'skill_def_id', p.skill_def_id,
    'skill_code', skill.code,
    'skill_name', skill.name,
    'required_skill_level', p.required_skill_level,
    'description', coalesce(p.description, ''),
    'effect_type', p.effect_type,
    'effect_data', coalesce(p.effect_data, '{}'::jsonb),
    'tags', coalesce(p.tags, '[]'::jsonb),
    'is_custom', p.is_custom,
    'sort_order', p.sort_order,
    'created_at', p.created_at,
    'updated_at', p.updated_at
  )
  into v_perk
  from public.odyssey_perk_defs p
  left join public.odyssey_skill_defs skill on skill.id = p.skill_def_id
  where p.id = p_perk_def_id;

  if v_perk is null then
    return public.odyssey_creator_error(
      'PERK_NOT_FOUND',
      'Perk definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown perk definition id.'))
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'perk', v_perk
  );
end;
$$;

create or replace function public.get_creator_reference_data()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ok', true,
    'attributes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'code', a.code,
              'name', a.name
            )
            order by a.sort_order, a.name, a.code
          )
          from public.odyssey_attribute_defs a
        ),
        '[]'::jsonb
      ),
    'skills',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', s.id,
              'code', s.code,
              'name', s.name,
              'category', s.category
            )
            order by s.category, s.sort_order, s.name, s.code
          )
          from public.odyssey_skill_defs s
        ),
        '[]'::jsonb
      ),
    'calibers',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', c.id,
              'code', c.code,
              'name', c.name,
              'base_damage_per_round', c.base_damage_per_round
            )
            order by c.sort_order, c.name, c.code
          )
          from public.odyssey_caliber_defs c
        ),
        '[]'::jsonb
      ),
    'weapon_classes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', wc.id,
              'code', wc.code,
              'name', wc.name
            )
            order by wc.sort_order, wc.name, wc.code
          )
          from public.odyssey_weapon_class_defs wc
        ),
        '[]'::jsonb
      ),
    'range_profiles',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', rp.id,
              'code', rp.code,
              'name', rp.name
            )
            order by rp.sort_order, rp.name, rp.code
          )
          from public.odyssey_range_profile_defs rp
        ),
        '[]'::jsonb
      ),
    'fire_modes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', fm.id,
              'code', fm.code,
              'name', fm.name,
              'accuracy_modifier', fm.accuracy_modifier
            )
            order by fm.sort_order, fm.name, fm.code
          )
          from public.odyssey_fire_mode_defs fm
        ),
        '[]'::jsonb
      ),
    'magazine_definitions',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', m.id,
              'code', m.code,
              'name', m.name,
              'capacity', m.capacity,
              'caliber_id', m.caliber_id,
              'caliber_code', caliber.code,
              'caliber_name', caliber.name
            )
            order by m.sort_order, m.name, m.code
          )
          from public.odyssey_magazine_defs m
          join public.odyssey_caliber_defs caliber on caliber.id = m.caliber_id
        ),
        '[]'::jsonb
      ),
    'body_part_definitions',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', b.id,
              'code', b.code,
              'name', b.name,
              'category', b.category,
              'can_be_targeted', b.can_be_targeted
            )
            order by b.sort_order, b.name, b.code
          )
          from public.odyssey_body_part_defs b
        ),
        '[]'::jsonb
      ),
    'resource_pools',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', rp.id,
              'code', rp.code,
              'name', rp.name
            )
            order by rp.sort_order, rp.name, rp.code
          )
          from public.odyssey_resource_pool_defs rp
        ),
        '[]'::jsonb
      ),
    'abilities',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'code', a.code,
              'name', a.name,
              'ability_kind', a.ability_kind,
              'source_type', a.source_type
            )
            order by a.sort_order, a.name, a.code
          )
          from public.odyssey_ability_defs a
        ),
        '[]'::jsonb
      ),
    'weapon_feature_definitions',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', f.id,
              'code', f.code,
              'name', f.name,
              'feature_type', f.feature_type,
              'activation_type', f.activation_type
            )
            order by f.sort_order, f.name, f.code
          )
          from public.odyssey_weapon_feature_defs f
        ),
        '[]'::jsonb
      ),
    'armor_classes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'code', a.code,
              'name', a.name,
              'min_total_armor', a.min_total_armor,
              'max_total_armor', a.max_total_armor
            )
            order by a.sort_order, a.min_total_armor, a.code
          )
          from public.odyssey_armor_class_defs a
        ),
        '[]'::jsonb
      )
  );
$$;

create or replace function public.creator_list_weapons(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      wm.id,
      wm.code,
      wm.name,
      wm.sort_order,
      wc.code as weapon_class_code,
      wc.name as weapon_class_name,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      coalesce(wm.tags, '[]'::jsonb) as tags,
      (
        select count(*)::integer
        from public.odyssey_weapon_model_profiles p
        where p.weapon_model_id = wm.id
      ) as profile_count
    from public.odyssey_weapon_model_defs wm
    left join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
    left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
    cross join search_input
    where search_input.search_text is null
      or wm.code ilike '%' || search_input.search_text || '%'
      or wm.name ilike '%' || search_input.search_text || '%'
      or coalesce(wc.name, '') ilike '%' || search_input.search_text || '%'
      or coalesce(caliber.name, '') ilike '%' || search_input.search_text || '%'
      or wm.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'weapon_class_code', weapon_class_code,
            'weapon_class_name', weapon_class_name,
            'caliber_code', caliber_code,
            'caliber_name', caliber_name,
            'profile_count', profile_count,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_weapon(
  p_weapon_model_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_weapon_bundle(p_weapon_model_id);
$$;

create or replace function public.creator_list_ammo_types(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      ammo.id,
      ammo.code,
      ammo.name,
      ammo.sort_order,
      ammo.damage_modifier,
      ammo.accuracy_modifier,
      ammo.armor_pierce,
      caliber.id as caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      coalesce(ammo.tags, '[]'::jsonb) as tags
    from public.odyssey_ammo_type_defs ammo
    join public.odyssey_caliber_defs caliber on caliber.id = ammo.caliber_id
    cross join search_input
    where search_input.search_text is null
      or ammo.code ilike '%' || search_input.search_text || '%'
      or ammo.name ilike '%' || search_input.search_text || '%'
      or caliber.name ilike '%' || search_input.search_text || '%'
      or ammo.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'caliber_id', caliber_id,
            'caliber_code', caliber_code,
            'caliber_name', caliber_name,
            'damage_modifier', damage_modifier,
            'accuracy_modifier', accuracy_modifier,
            'armor_pierce', armor_pierce,
            'tags', tags
          )
          order by sort_order, caliber_name, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_ammo_type(
  p_ammo_type_id uuid
)
returns jsonb
language sql
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'ammo_type',
          jsonb_build_object(
            'id', ammo.id,
            'caliber_id', ammo.caliber_id,
            'caliber_code', caliber.code,
            'caliber_name', caliber.name,
            'code', ammo.code,
            'name', ammo.name,
            'damage_modifier', ammo.damage_modifier,
            'accuracy_modifier', ammo.accuracy_modifier,
            'armor_pierce', ammo.armor_pierce,
            'description', coalesce(ammo.description, ''),
            'tags', coalesce(ammo.tags, '[]'::jsonb),
            'is_custom', ammo.is_custom,
            'sort_order', ammo.sort_order,
            'created_at', ammo.created_at,
            'updated_at', ammo.updated_at
          )
      )
      from public.odyssey_ammo_type_defs ammo
      join public.odyssey_caliber_defs caliber on caliber.id = ammo.caliber_id
      where ammo.id = p_ammo_type_id
    ),
    public.odyssey_creator_error(
      'AMMO_TYPE_NOT_FOUND',
      'Ammo type was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown ammo type id.'))
    )
  );
$$;

create or replace function public.creator_list_magazine_defs(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      mag.id,
      mag.code,
      mag.name,
      mag.sort_order,
      mag.capacity,
      caliber.id as caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      coalesce(mag.tags, '[]'::jsonb) as tags
    from public.odyssey_magazine_defs mag
    join public.odyssey_caliber_defs caliber on caliber.id = mag.caliber_id
    cross join search_input
    where search_input.search_text is null
      or mag.code ilike '%' || search_input.search_text || '%'
      or mag.name ilike '%' || search_input.search_text || '%'
      or caliber.name ilike '%' || search_input.search_text || '%'
      or mag.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'capacity', capacity,
            'caliber_id', caliber_id,
            'caliber_code', caliber_code,
            'caliber_name', caliber_name,
            'tags', tags
          )
          order by sort_order, caliber_name, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_magazine_def(
  p_magazine_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'magazine_def',
          jsonb_build_object(
            'id', mag.id,
            'caliber_id', mag.caliber_id,
            'caliber_code', caliber.code,
            'caliber_name', caliber.name,
            'code', mag.code,
            'name', mag.name,
            'capacity', mag.capacity,
            'description', coalesce(mag.description, ''),
            'tags', coalesce(mag.tags, '[]'::jsonb),
            'is_custom', mag.is_custom,
            'sort_order', mag.sort_order,
            'created_at', mag.created_at,
            'updated_at', mag.updated_at
          )
      )
      from public.odyssey_magazine_defs mag
      join public.odyssey_caliber_defs caliber on caliber.id = mag.caliber_id
      where mag.id = p_magazine_def_id
    ),
    public.odyssey_creator_error(
      'MAGAZINE_DEF_NOT_FOUND',
      'Magazine definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown magazine definition id.'))
    )
  );
$$;

create or replace function public.creator_list_weapon_feature_defs(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      feature.id,
      feature.code,
      feature.name,
      feature.sort_order,
      feature.feature_type,
      feature.activation_type,
      coalesce(feature.tags, '[]'::jsonb) as tags
    from public.odyssey_weapon_feature_defs feature
    cross join search_input
    where search_input.search_text is null
      or feature.code ilike '%' || search_input.search_text || '%'
      or feature.name ilike '%' || search_input.search_text || '%'
      or feature.feature_type ilike '%' || search_input.search_text || '%'
      or feature.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'feature_type', feature_type,
            'activation_type', activation_type,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_weapon_feature_def(
  p_feature_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'weapon_feature_def',
          jsonb_build_object(
            'id', feature.id,
            'code', feature.code,
            'name', feature.name,
            'feature_type', feature.feature_type,
            'activation_type', feature.activation_type,
            'description', coalesce(feature.description, ''),
            'default_max_charges', feature.default_max_charges,
            'default_current_charges', feature.default_current_charges,
            'default_recharge_rounds', feature.default_recharge_rounds,
            'default_cooldown_rounds', feature.default_cooldown_rounds,
            'default_active_rounds', feature.default_active_rounds,
            'default_active_uses', feature.default_active_uses,
            'requires_reload_item_code', feature.requires_reload_item_code,
            'data', coalesce(feature.data, '{}'::jsonb),
            'effect_data', coalesce(feature.effect_data, '{}'::jsonb),
            'tags', coalesce(feature.tags, '[]'::jsonb),
            'is_custom', feature.is_custom,
            'sort_order', feature.sort_order,
            'created_at', feature.created_at,
            'updated_at', feature.updated_at
          )
      )
      from public.odyssey_weapon_feature_defs feature
      where feature.id = p_feature_def_id
    ),
    public.odyssey_creator_error(
      'WEAPON_FEATURE_DEF_NOT_FOUND',
      'Weapon feature definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown weapon feature definition id.'))
    )
  );
$$;

create or replace function public.creator_list_armor_models(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      model.id,
      model.code,
      model.name,
      model.sort_order,
      model.item_type,
      model.armor_value,
      model.armor_max_critical,
      model.default_body_part_code,
      coalesce(model.tags, '[]'::jsonb) as tags
    from public.odyssey_equipment_model_defs model
    cross join search_input
    where model.item_type in ('armor', 'shield')
      and (
        search_input.search_text is null
        or model.code ilike '%' || search_input.search_text || '%'
        or model.name ilike '%' || search_input.search_text || '%'
        or model.item_type ilike '%' || search_input.search_text || '%'
        or model.tags::text ilike '%' || search_input.search_text || '%'
      )
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'item_type', item_type,
            'armor_value', armor_value,
            'armor_max_critical', armor_max_critical,
            'default_body_part_code', default_body_part_code,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_armor_model(
  p_equipment_model_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_equipment_model_bundle(p_equipment_model_id);
$$;

create or replace function public.creator_list_item_defs(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      item.id,
      item.code,
      item.name,
      item.sort_order,
      item.item_type,
      item.is_stackable,
      coalesce(item.tags, '[]'::jsonb) as tags
    from public.odyssey_item_defs item
    cross join search_input
    where search_input.search_text is null
      or item.code ilike '%' || search_input.search_text || '%'
      or item.name ilike '%' || search_input.search_text || '%'
      or item.item_type ilike '%' || search_input.search_text || '%'
      or item.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'item_type', item_type,
            'is_stackable', is_stackable,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_item_def(
  p_item_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_item_def_bundle(p_item_def_id);
$$;

create or replace function public.creator_list_abilities(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      ability.id,
      ability.code,
      ability.name,
      ability.sort_order,
      ability.ability_kind,
      ability.source_type,
      coalesce(ability.tags, '[]'::jsonb) as tags
    from public.odyssey_ability_defs ability
    cross join search_input
    where search_input.search_text is null
      or ability.code ilike '%' || search_input.search_text || '%'
      or ability.name ilike '%' || search_input.search_text || '%'
      or ability.ability_kind ilike '%' || search_input.search_text || '%'
      or ability.source_type ilike '%' || search_input.search_text || '%'
      or ability.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'ability_kind', ability_kind,
            'source_type', source_type,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_ability(
  p_ability_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_ability_bundle(p_ability_def_id);
$$;

create or replace function public.creator_list_perks(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      perk.id,
      perk.code,
      perk.name,
      perk.sort_order,
      perk.required_skill_level,
      skill.code as skill_code,
      skill.name as skill_name,
      coalesce(perk.tags, '[]'::jsonb) as tags
    from public.odyssey_perk_defs perk
    left join public.odyssey_skill_defs skill on skill.id = perk.skill_def_id
    cross join search_input
    where search_input.search_text is null
      or perk.code ilike '%' || search_input.search_text || '%'
      or perk.name ilike '%' || search_input.search_text || '%'
      or coalesce(skill.name, '') ilike '%' || search_input.search_text || '%'
      or perk.tags::text ilike '%' || search_input.search_text || '%'
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'skill_code', skill_code,
            'skill_name', skill_name,
            'required_skill_level', required_skill_level,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_perk(
  p_perk_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_perk_bundle(p_perk_def_id);
$$;

create or replace function public.creator_upsert_ammo_type(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_caliber_id uuid := nullif(trim(coalesce(v_payload->>'caliber_id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_damage_modifier integer := coalesce(nullif(trim(coalesce(v_payload->>'damage_modifier', '')), '')::integer, 0);
  v_accuracy_modifier integer := coalesce(nullif(trim(coalesce(v_payload->>'accuracy_modifier', '')), '')::integer, 0);
  v_armor_pierce integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_pierce', '')), '')::integer, 0);
  v_description text := coalesce(v_payload->>'description', '');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_caliber_id is null or not exists (select 1 from public.odyssey_caliber_defs where id = v_caliber_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'A valid caliber is required.',
      jsonb_build_array(jsonb_build_object('field', 'caliber_id', 'message', 'Unknown caliber.'))
    );
  end if;

  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_id is not null then
    select ammo.id
    into v_entity_id
    from public.odyssey_ammo_type_defs ammo
    where ammo.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'AMMO_TYPE_NOT_FOUND',
        'Ammo type was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown ammo type id.'))
      );
    end if;
  else
    select ammo.id
    into v_entity_id
    from public.odyssey_ammo_type_defs ammo
    where ammo.caliber_id = v_caliber_id
      and ammo.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_ammo_type_defs ammo
    where ammo.caliber_id = v_caliber_id
      and ammo.code = v_code
      and ammo.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Ammo code must be unique within its caliber.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate ammo code for the selected caliber.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_ammo_type_defs (
      caliber_id,
      code,
      name,
      damage_modifier,
      accuracy_modifier,
      armor_pierce,
      description,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_caliber_id,
      v_code,
      v_name,
      v_damage_modifier,
      v_accuracy_modifier,
      v_armor_pierce,
      v_description,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_ammo_type_defs
    set
      caliber_id = v_caliber_id,
      code = v_code,
      name = v_name,
      damage_modifier = v_damage_modifier,
      accuracy_modifier = v_accuracy_modifier,
      armor_pierce = v_armor_pierce,
      description = v_description,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  v_result := public.creator_get_ammo_type(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', coalesce(v_result->'ammo_type', '{}'::jsonb),
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_magazine_def(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_caliber_id uuid := nullif(trim(coalesce(v_payload->>'caliber_id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_capacity integer := coalesce(nullif(trim(coalesce(v_payload->>'capacity', '')), '')::integer, 0);
  v_description text := coalesce(v_payload->>'description', '');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_caliber_id is null or not exists (select 1 from public.odyssey_caliber_defs where id = v_caliber_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'A valid caliber is required.',
      jsonb_build_array(jsonb_build_object('field', 'caliber_id', 'message', 'Unknown caliber.'))
    );
  end if;

  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_capacity < 1 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'capacity must be at least 1.',
      jsonb_build_array(jsonb_build_object('field', 'capacity', 'message', 'Magazine capacity must be at least 1.'))
    );
  end if;

  if v_id is not null then
    select mag.id
    into v_entity_id
    from public.odyssey_magazine_defs mag
    where mag.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'MAGAZINE_DEF_NOT_FOUND',
        'Magazine definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown magazine definition id.'))
      );
    end if;
  else
    select mag.id
    into v_entity_id
    from public.odyssey_magazine_defs mag
    where mag.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_magazine_defs mag
    where mag.code = v_code
      and mag.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Magazine code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate magazine code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_magazine_defs (
      code,
      name,
      caliber_id,
      capacity,
      description,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_caliber_id,
      v_capacity,
      v_description,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_magazine_defs
    set
      code = v_code,
      name = v_name,
      caliber_id = v_caliber_id,
      capacity = v_capacity,
      description = v_description,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  v_result := public.creator_get_magazine_def(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', coalesce(v_result->'magazine_def', '{}'::jsonb),
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_weapon_feature_def(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_feature_type text := trim(coalesce(v_payload->>'feature_type', ''));
  v_activation_type text := trim(coalesce(v_payload->>'activation_type', ''));
  v_description text := coalesce(v_payload->>'description', '');
  v_default_max_charges integer := nullif(trim(coalesce(v_payload->>'default_max_charges', '')), '')::integer;
  v_default_current_charges integer := nullif(trim(coalesce(v_payload->>'default_current_charges', '')), '')::integer;
  v_default_recharge_rounds integer := nullif(trim(coalesce(v_payload->>'default_recharge_rounds', '')), '')::integer;
  v_default_cooldown_rounds integer := nullif(trim(coalesce(v_payload->>'default_cooldown_rounds', '')), '')::integer;
  v_default_active_rounds integer := nullif(trim(coalesce(v_payload->>'default_active_rounds', '')), '')::integer;
  v_default_active_uses integer := nullif(trim(coalesce(v_payload->>'default_active_uses', '')), '')::integer;
  v_requires_reload_item_code text := nullif(trim(coalesce(v_payload->>'requires_reload_item_code', '')), '');
  v_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'data');
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_feature_type not in ('passive', 'active', 'one_attack', 'duration', 'profile_switch', 'on_hit', 'narrative', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'feature_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'feature_type', 'message', 'Unsupported feature_type value.'))
    );
  end if;

  if v_activation_type not in ('passive', 'manual', 'on_attack', 'on_hit', 'profile_switch', 'always', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'activation_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'activation_type', 'message', 'Unsupported activation_type value.'))
    );
  end if;

  if v_requires_reload_item_code is not null and not exists (
    select 1
    from public.odyssey_item_defs item_def
    where item_def.code = public.odyssey_creator_normalize_code(v_requires_reload_item_code)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'requires_reload_item_code references an unknown item definition.',
      jsonb_build_array(jsonb_build_object('field', 'requires_reload_item_code', 'message', 'Unknown item code.'))
    );
  end if;

  if v_id is not null then
    select feature.id
    into v_entity_id
    from public.odyssey_weapon_feature_defs feature
    where feature.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'WEAPON_FEATURE_DEF_NOT_FOUND',
        'Weapon feature definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown weapon feature definition id.'))
      );
    end if;
  else
    select feature.id
    into v_entity_id
    from public.odyssey_weapon_feature_defs feature
    where feature.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_weapon_feature_defs feature
    where feature.code = v_code
      and feature.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Weapon feature code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate weapon feature code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_weapon_feature_defs (
      code,
      name,
      feature_type,
      activation_type,
      description,
      default_max_charges,
      default_current_charges,
      default_recharge_rounds,
      default_cooldown_rounds,
      default_active_rounds,
      default_active_uses,
      requires_reload_item_code,
      data,
      effect_data,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_feature_type,
      v_activation_type,
      v_description,
      v_default_max_charges,
      v_default_current_charges,
      v_default_recharge_rounds,
      v_default_cooldown_rounds,
      v_default_active_rounds,
      v_default_active_uses,
      nullif(public.odyssey_creator_normalize_code(v_requires_reload_item_code), ''),
      v_data,
      v_effect_data,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_weapon_feature_defs
    set
      code = v_code,
      name = v_name,
      feature_type = v_feature_type,
      activation_type = v_activation_type,
      description = v_description,
      default_max_charges = v_default_max_charges,
      default_current_charges = v_default_current_charges,
      default_recharge_rounds = v_default_recharge_rounds,
      default_cooldown_rounds = v_default_cooldown_rounds,
      default_active_rounds = v_default_active_rounds,
      default_active_uses = v_default_active_uses,
      requires_reload_item_code = nullif(public.odyssey_creator_normalize_code(v_requires_reload_item_code), ''),
      data = v_data,
      effect_data = v_effect_data,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  v_result := public.creator_get_weapon_feature_def(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', coalesce(v_result->'weapon_feature_def', '{}'::jsonb),
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_armor_model(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_item_type text := lower(trim(coalesce(v_payload->>'item_type', 'armor')));
  v_description text := coalesce(v_payload->>'description', '');
  v_armor_value integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_value', '')), '')::integer, 0);
  v_armor_max_critical integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_max_critical', '')), '')::integer, 0);
  v_default_body_part_code text := nullif(lower(trim(coalesce(v_payload->>'default_body_part_code', ''))), '');
  v_can_equip boolean := coalesce(nullif(trim(coalesce(v_payload->>'can_equip', '')), '')::boolean, true);
  v_can_equip_to_body_part boolean := coalesce(nullif(trim(coalesce(v_payload->>'can_equip_to_body_part', '')), '')::boolean, true);
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_flags jsonb := public.odyssey_creator_normalize_json_object(v_payload->'flags');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_ability_links jsonb := public.odyssey_creator_normalize_json_array(v_payload->'ability_links');
  v_entity_id uuid := null;
  v_existing_item_type text := null;
  v_result jsonb := '{}'::jsonb;
  v_processed_link_ids uuid[] := '{}'::uuid[];
  v_entry jsonb := '{}'::jsonb;
  v_ability_id uuid := null;
  v_link_id uuid := null;
  v_grant_mode text := '';
  v_is_enabled boolean := true;
  v_link_sort integer := 0;
  v_link_data jsonb := '{}'::jsonb;
begin
  if v_item_type not in ('armor', 'shield') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'item_type must be armor or shield.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'Use armor or shield.'))
    );
  end if;

  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_armor_value < 0 or v_armor_max_critical < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'armor_value and armor_max_critical must be >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'armor_value', 'message', 'Values cannot be negative.'))
    );
  end if;

  if v_default_body_part_code is not null and not exists (
    select 1
    from public.odyssey_body_part_defs body_part
    where body_part.code = v_default_body_part_code
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_body_part_code references an unknown body part.',
      jsonb_build_array(jsonb_build_object('field', 'default_body_part_code', 'message', 'Unknown body part code.'))
    );
  end if;

  if v_id is not null then
    select model.id, model.item_type
    into v_entity_id, v_existing_item_type
    from public.odyssey_equipment_model_defs model
    where model.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'ARMOR_MODEL_NOT_FOUND',
        'Armor model was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown armor model id.'))
      );
    end if;
  else
    select model.id, model.item_type
    into v_entity_id, v_existing_item_type
    from public.odyssey_equipment_model_defs model
    where model.code = v_code
    limit 1;
  end if;

  if v_entity_id is not null and v_existing_item_type not in ('armor', 'shield') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Armor module can edit only armor or shield equipment models.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'The selected equipment model belongs to another module.'))
    );
  end if;

  if exists (
    select 1
    from public.odyssey_equipment_model_defs model
    where model.code = v_code
      and model.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Armor model code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate armor model code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_equipment_model_defs (
      code,
      name,
      item_type,
      description,
      armor_value,
      armor_max_critical,
      default_body_part_code,
      can_equip,
      can_equip_to_body_part,
      effect_data,
      flags,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_item_type,
      v_description,
      v_armor_value,
      v_armor_max_critical,
      v_default_body_part_code,
      v_can_equip,
      v_can_equip_to_body_part,
      v_effect_data,
      v_flags,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_equipment_model_defs
    set
      code = v_code,
      name = v_name,
      item_type = v_item_type,
      description = v_description,
      armor_value = v_armor_value,
      armor_max_critical = v_armor_max_critical,
      default_body_part_code = v_default_body_part_code,
      can_equip = v_can_equip,
      can_equip_to_body_part = v_can_equip_to_body_part,
      effect_data = v_effect_data,
      flags = v_flags,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_ability_links)
  loop
    v_ability_id := nullif(trim(coalesce(v_entry->>'ability_def_id', '')), '')::uuid;
    v_grant_mode := lower(trim(coalesce(v_entry->>'grant_mode', 'available')));
    v_is_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled', '')), '')::boolean, true);
    v_link_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_link_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_ability_id is null or not exists (select 1 from public.odyssey_ability_defs where id = v_ability_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_links contain an unknown ability.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Unknown ability_def_id.'))
      );
    end if;

    if v_grant_mode not in ('available', 'passive', 'activated') then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'grant_mode is invalid.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'grant_mode must be available, passive, or activated.'))
      );
    end if;

    select link.id
    into v_link_id
    from public.odyssey_equipment_model_abilities link
    where link.equipment_model_id = v_entity_id
      and link.ability_def_id = v_ability_id
    for update;

    if v_link_id is null then
      insert into public.odyssey_equipment_model_abilities (
        equipment_model_id,
        ability_def_id,
        grant_mode,
        is_enabled,
        sort_order,
        data
      )
      values (
        v_entity_id,
        v_ability_id,
        v_grant_mode,
        v_is_enabled,
        v_link_sort,
        v_link_data
      )
      returning id into v_link_id;
    else
      update public.odyssey_equipment_model_abilities
      set
        grant_mode = v_grant_mode,
        is_enabled = v_is_enabled,
        sort_order = v_link_sort,
        data = v_link_data
      where id = v_link_id;
    end if;

    v_processed_link_ids := array_append(v_processed_link_ids, v_link_id);
  end loop;

  delete from public.odyssey_equipment_model_abilities
  where equipment_model_id = v_entity_id
    and not (id = any(v_processed_link_ids));

  v_result := public.creator_get_armor_model(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_item_def(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_item_type text := lower(trim(coalesce(v_payload->>'item_type', 'custom')));
  v_description text := coalesce(v_payload->>'description', '');
  v_is_stackable boolean := coalesce(nullif(trim(coalesce(v_payload->>'is_stackable', '')), '')::boolean, true);
  v_default_quantity integer := coalesce(nullif(trim(coalesce(v_payload->>'default_quantity', '')), '')::integer, 1);
  v_max_stack integer := nullif(trim(coalesce(v_payload->>'max_stack', '')), '')::integer;
  v_default_max_charges integer := nullif(trim(coalesce(v_payload->>'default_max_charges', '')), '')::integer;
  v_default_current_charges integer := nullif(trim(coalesce(v_payload->>'default_current_charges', '')), '')::integer;
  v_use_action_type text := lower(trim(coalesce(v_payload->>'use_action_type', 'none')));
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'data');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_ability_links jsonb := public.odyssey_creator_normalize_json_array(v_payload->'ability_links');
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
  v_processed_link_ids uuid[] := '{}'::uuid[];
  v_entry jsonb := '{}'::jsonb;
  v_ability_id uuid := null;
  v_link_id uuid := null;
  v_grant_mode text := '';
  v_is_enabled boolean := true;
  v_link_sort integer := 0;
  v_link_data jsonb := '{}'::jsonb;
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_item_type not in ('resource', 'consumable', 'medical', 'tool', 'quest', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'item_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'Unsupported item_type value.'))
    );
  end if;

  if v_use_action_type not in ('none', 'consume', 'heal', 'reload_feature_resource', 'custom', 'manual') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'use_action_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'use_action_type', 'message', 'Unsupported use_action_type value.'))
    );
  end if;

  if v_default_quantity < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_quantity must be >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'default_quantity', 'message', 'Quantity cannot be negative.'))
    );
  end if;

  if v_max_stack is not null and v_max_stack < 1 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'max_stack must be null or >= 1.',
      jsonb_build_array(jsonb_build_object('field', 'max_stack', 'message', 'max_stack must be null or at least 1.'))
    );
  end if;

  if v_default_max_charges is not null and v_default_max_charges < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_max_charges must be null or >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'default_max_charges', 'message', 'default_max_charges cannot be negative.'))
    );
  end if;

  if v_default_current_charges is not null and v_default_current_charges < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_current_charges must be null or >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'default_current_charges', 'message', 'default_current_charges cannot be negative.'))
    );
  end if;

  if v_default_max_charges is not null
     and v_default_current_charges is not null
     and v_default_current_charges > v_default_max_charges then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_current_charges cannot exceed default_max_charges.',
      jsonb_build_array(jsonb_build_object('field', 'default_current_charges', 'message', 'Current charges cannot exceed max charges.'))
    );
  end if;

  if v_id is not null then
    select item.id
    into v_entity_id
    from public.odyssey_item_defs item
    where item.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'ITEM_DEF_NOT_FOUND',
        'Item definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown item definition id.'))
      );
    end if;
  else
    select item.id
    into v_entity_id
    from public.odyssey_item_defs item
    where item.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_item_defs item
    where item.code = v_code
      and item.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Item code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate item code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_item_defs (
      code,
      name,
      item_type,
      description,
      is_stackable,
      default_quantity,
      max_stack,
      default_max_charges,
      default_current_charges,
      use_action_type,
      effect_data,
      data,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_item_type,
      v_description,
      v_is_stackable,
      v_default_quantity,
      v_max_stack,
      v_default_max_charges,
      v_default_current_charges,
      v_use_action_type,
      v_effect_data,
      v_data,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_item_defs
    set
      code = v_code,
      name = v_name,
      item_type = v_item_type,
      description = v_description,
      is_stackable = v_is_stackable,
      default_quantity = v_default_quantity,
      max_stack = v_max_stack,
      default_max_charges = v_default_max_charges,
      default_current_charges = v_default_current_charges,
      use_action_type = v_use_action_type,
      effect_data = v_effect_data,
      data = v_data,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_ability_links)
  loop
    v_ability_id := nullif(trim(coalesce(v_entry->>'ability_def_id', '')), '')::uuid;
    v_grant_mode := lower(trim(coalesce(v_entry->>'grant_mode', 'activated')));
    v_is_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled', '')), '')::boolean, true);
    v_link_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_link_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_ability_id is null or not exists (select 1 from public.odyssey_ability_defs where id = v_ability_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_links contain an unknown ability.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Unknown ability_def_id.'))
      );
    end if;

    if v_grant_mode not in ('available', 'passive', 'activated') then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'grant_mode is invalid.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'grant_mode must be available, passive, or activated.'))
      );
    end if;

    select link.id
    into v_link_id
    from public.odyssey_item_def_abilities link
    where link.item_def_id = v_entity_id
      and link.ability_def_id = v_ability_id
    for update;

    if v_link_id is null then
      insert into public.odyssey_item_def_abilities (
        item_def_id,
        ability_def_id,
        grant_mode,
        is_enabled,
        sort_order,
        data
      )
      values (
        v_entity_id,
        v_ability_id,
        v_grant_mode,
        v_is_enabled,
        v_link_sort,
        v_link_data
      )
      returning id into v_link_id;
    else
      update public.odyssey_item_def_abilities
      set
        grant_mode = v_grant_mode,
        is_enabled = v_is_enabled,
        sort_order = v_link_sort,
        data = v_link_data
      where id = v_link_id;
    end if;

    v_processed_link_ids := array_append(v_processed_link_ids, v_link_id);
  end loop;

  delete from public.odyssey_item_def_abilities
  where item_def_id = v_entity_id
    and not (id = any(v_processed_link_ids));

  v_result := public.creator_get_item_def(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_perk(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_skill_def_id uuid := nullif(trim(coalesce(v_payload->>'skill_def_id', '')), '')::uuid;
  v_required_skill_level integer := coalesce(nullif(trim(coalesce(v_payload->>'required_skill_level', '')), '')::integer, 0);
  v_description text := coalesce(v_payload->>'description', '');
  v_effect_type text := nullif(trim(coalesce(v_payload->>'effect_type', '')), '');
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_skill_def_id is null or not exists (select 1 from public.odyssey_skill_defs where id = v_skill_def_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'skill_def_id is required and must exist.',
      jsonb_build_array(jsonb_build_object('field', 'skill_def_id', 'message', 'Unknown skill definition.'))
    );
  end if;

  if v_effect_type is not null
     and v_effect_type not in (
       'add_modifier',
       'remove_modifier',
       'ignore_penalty',
       'modify_fire_mode',
       'modify_range_penalty',
       'grant_advantage',
       'replace_defense_skill',
       'grant_reaction',
       'special_action'
     ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'effect_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'effect_type', 'message', 'Unsupported effect_type value.'))
    );
  end if;

  if v_required_skill_level < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'required_skill_level must be >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'required_skill_level', 'message', 'Value cannot be negative.'))
    );
  end if;

  if v_id is not null then
    select perk.id
    into v_entity_id
    from public.odyssey_perk_defs perk
    where perk.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'PERK_NOT_FOUND',
        'Perk definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown perk definition id.'))
      );
    end if;
  else
    select perk.id
    into v_entity_id
    from public.odyssey_perk_defs perk
    where perk.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_perk_defs perk
    where perk.code = v_code
      and perk.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Perk code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate perk code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_perk_defs (
      skill_def_id,
      code,
      name,
      required_skill_level,
      description,
      effect_type,
      effect_data,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_skill_def_id,
      v_code,
      v_name,
      v_required_skill_level,
      v_description,
      v_effect_type,
      v_effect_data,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_perk_defs
    set
      skill_def_id = v_skill_def_id,
      code = v_code,
      name = v_name,
      required_skill_level = v_required_skill_level,
      description = v_description,
      effect_type = v_effect_type,
      effect_data = v_effect_data,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  v_result := public.creator_get_perk(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_ability(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_ability_kind text := lower(trim(coalesce(v_payload->>'ability_kind', 'custom')));
  v_source_type text := lower(trim(coalesce(v_payload->>'source_type', 'custom')));
  v_activation_type text := lower(trim(coalesce(v_payload->>'activation_type', 'manual')));
  v_target_type text := lower(trim(coalesce(v_payload->>'target_type', 'self')));
  v_effect_mode text := lower(trim(coalesce(v_payload->>'effect_mode', 'narrative')));
  v_attack_type text := nullif(lower(trim(coalesce(v_payload->>'attack_type', ''))), '');
  v_linked_skill_id uuid := nullif(trim(coalesce(v_payload->>'linked_skill_id', '')), '')::uuid;
  v_resource_mode text := lower(trim(coalesce(v_payload->>'resource_mode', 'none')));
  v_resource_pool_code text := nullif(public.odyssey_creator_normalize_code(v_payload->>'resource_pool_code'), '');
  v_resource_item_code text := nullif(public.odyssey_creator_normalize_code(v_payload->>'resource_item_code'), '');
  v_description text := coalesce(v_payload->>'description', '');
  v_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'data');
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_levels jsonb := public.odyssey_creator_normalize_json_array(v_payload->'levels');
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
  v_processed_level_ids uuid[] := '{}'::uuid[];
  v_entry jsonb := '{}'::jsonb;
  v_level_id uuid := null;
  v_ability_level integer := 0;
  v_resource_cost integer := 0;
  v_cooldown_rounds integer := null;
  v_range_profile_id uuid := null;
  v_attack_accuracy_bonus integer := 0;
  v_attack_damage_bonus integer := 0;
  v_attack_armor_pierce integer := 0;
  v_ignore_armor boolean := false;
  v_special_armor_value integer := null;
  v_special_max_critical integer := null;
  v_duration_rounds integer := null;
  v_level_data jsonb := '{}'::jsonb;
  v_level_effect_data jsonb := '{}'::jsonb;
  v_seen_levels integer[] := '{}'::integer[];
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_ability_kind not in ('attack', 'buff', 'defense', 'utility', 'narrative', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'ability_kind is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'ability_kind', 'message', 'Unsupported ability_kind value.'))
    );
  end if;

  if v_source_type not in ('psionic', 'implant', 'prosthetic', 'equipment', 'item', 'innate', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'source_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'source_type', 'message', 'Unsupported source_type value.'))
    );
  end if;

  if v_activation_type not in ('manual', 'passive', 'on_attack', 'on_hit', 'always', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'activation_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'activation_type', 'message', 'Unsupported activation_type value.'))
    );
  end if;

  if v_target_type not in ('self', 'character', 'body_part', 'none', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'target_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'target_type', 'message', 'Unsupported target_type value.'))
    );
  end if;

  if v_effect_mode not in ('attack', 'apply_effect', 'grant_special', 'narrative', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'effect_mode is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'effect_mode', 'message', 'Unsupported effect_mode value.'))
    );
  end if;

  if v_attack_type is not null and v_attack_type not in ('ranged', 'melee', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'attack_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'attack_type', 'message', 'Unsupported attack_type value.'))
    );
  end if;

  if v_linked_skill_id is not null and not exists (select 1 from public.odyssey_skill_defs where id = v_linked_skill_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'linked_skill_id references an unknown skill.',
      jsonb_build_array(jsonb_build_object('field', 'linked_skill_id', 'message', 'Unknown skill definition.'))
    );
  end if;

  if v_resource_mode not in ('none', 'pool', 'item', 'cooldown', 'custom') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'resource_mode is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'resource_mode', 'message', 'Unsupported resource_mode value.'))
    );
  end if;

  if v_resource_mode = 'pool' and (
    v_resource_pool_code is null
    or not exists (select 1 from public.odyssey_resource_pool_defs where code = v_resource_pool_code)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'resource_pool_code is required when resource_mode = pool.',
      jsonb_build_array(jsonb_build_object('field', 'resource_pool_code', 'message', 'Unknown resource pool code.'))
    );
  end if;

  if v_resource_item_code is not null and not exists (
    select 1
    from public.odyssey_item_defs item_def
    where item_def.code = v_resource_item_code
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'resource_item_code references an unknown item.',
      jsonb_build_array(jsonb_build_object('field', 'resource_item_code', 'message', 'Unknown item definition code.'))
    );
  end if;

  if jsonb_array_length(v_levels) = 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'At least one ability level is required.',
      jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'Provide at least one level entry.'))
    );
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_levels)
  loop
    v_ability_level := coalesce(nullif(trim(coalesce(v_entry->>'ability_level', '')), '')::integer, 0);
    if v_ability_level < 1 or v_ability_level > 5 then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_level must be between 1 and 5.',
        jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'Each ability level must be between 1 and 5.'))
      );
    end if;

    if v_ability_level = any(v_seen_levels) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_level values must be unique per ability.',
        jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'Duplicate ability_level value found.'))
      );
    end if;

    v_seen_levels := array_append(v_seen_levels, v_ability_level);

    v_resource_cost := coalesce(nullif(trim(coalesce(v_entry->>'resource_cost', '')), '')::integer, 0);
    if v_resource_cost < 0 then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'resource_cost must be >= 0.',
        jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'resource_cost cannot be negative.'))
      );
    end if;

    v_range_profile_id := nullif(trim(coalesce(v_entry->>'range_profile_id', '')), '')::uuid;
    if v_range_profile_id is not null and not exists (select 1 from public.odyssey_range_profile_defs where id = v_range_profile_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'range_profile_id references an unknown range profile.',
        jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'Unknown range_profile_id.'))
      );
    end if;
  end loop;

  if v_id is not null then
    select ability.id
    into v_entity_id
    from public.odyssey_ability_defs ability
    where ability.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'ABILITY_NOT_FOUND',
        'Ability definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown ability definition id.'))
      );
    end if;
  else
    select ability.id
    into v_entity_id
    from public.odyssey_ability_defs ability
    where ability.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_ability_defs ability
    where ability.code = v_code
      and ability.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Ability code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate ability code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_ability_defs (
      code,
      name,
      ability_kind,
      source_type,
      activation_type,
      target_type,
      effect_mode,
      attack_type,
      linked_skill_id,
      resource_mode,
      resource_pool_code,
      resource_item_code,
      description,
      data,
      effect_data,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_ability_kind,
      v_source_type,
      v_activation_type,
      v_target_type,
      v_effect_mode,
      v_attack_type,
      v_linked_skill_id,
      v_resource_mode,
      v_resource_pool_code,
      v_resource_item_code,
      v_description,
      v_data,
      v_effect_data,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_ability_defs
    set
      code = v_code,
      name = v_name,
      ability_kind = v_ability_kind,
      source_type = v_source_type,
      activation_type = v_activation_type,
      target_type = v_target_type,
      effect_mode = v_effect_mode,
      attack_type = v_attack_type,
      linked_skill_id = v_linked_skill_id,
      resource_mode = v_resource_mode,
      resource_pool_code = v_resource_pool_code,
      resource_item_code = v_resource_item_code,
      description = v_description,
      data = v_data,
      effect_data = v_effect_data,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_levels)
  loop
    v_level_id := nullif(trim(coalesce(v_entry->>'id', '')), '')::uuid;
    v_ability_level := coalesce(nullif(trim(coalesce(v_entry->>'ability_level', '')), '')::integer, 0);
    v_resource_cost := coalesce(nullif(trim(coalesce(v_entry->>'resource_cost', '')), '')::integer, 0);
    v_cooldown_rounds := nullif(trim(coalesce(v_entry->>'cooldown_rounds', '')), '')::integer;
    v_range_profile_id := nullif(trim(coalesce(v_entry->>'range_profile_id', '')), '')::uuid;
    v_attack_accuracy_bonus := coalesce(nullif(trim(coalesce(v_entry->>'attack_accuracy_bonus', '')), '')::integer, 0);
    v_attack_damage_bonus := coalesce(nullif(trim(coalesce(v_entry->>'attack_damage_bonus', '')), '')::integer, 0);
    v_attack_armor_pierce := coalesce(nullif(trim(coalesce(v_entry->>'attack_armor_pierce', '')), '')::integer, 0);
    v_ignore_armor := coalesce(nullif(trim(coalesce(v_entry->>'ignore_armor', '')), '')::boolean, false);
    v_special_armor_value := nullif(trim(coalesce(v_entry->>'special_armor_value', '')), '')::integer;
    v_special_max_critical := nullif(trim(coalesce(v_entry->>'special_max_critical', '')), '')::integer;
    v_duration_rounds := nullif(trim(coalesce(v_entry->>'duration_rounds', '')), '')::integer;
    v_level_data := public.odyssey_creator_normalize_json_object(v_entry->'data');
    v_level_effect_data := public.odyssey_creator_normalize_json_object(v_entry->'effect_data');

    if v_level_id is not null then
      if not exists (
        select 1
        from public.odyssey_ability_level_defs level
        where level.id = v_level_id
          and level.ability_def_id = v_entity_id
      ) then
        return public.odyssey_creator_error(
          'VALIDATION_ERROR',
          'Level id does not belong to this ability.',
          jsonb_build_array(jsonb_build_object('field', 'levels', 'message', 'Invalid level id for this ability.'))
        );
      end if;

      update public.odyssey_ability_level_defs
      set
        ability_level = v_ability_level,
        resource_cost = v_resource_cost,
        cooldown_rounds = v_cooldown_rounds,
        range_profile_id = v_range_profile_id,
        attack_accuracy_bonus = v_attack_accuracy_bonus,
        attack_damage_bonus = v_attack_damage_bonus,
        attack_armor_pierce = v_attack_armor_pierce,
        ignore_armor = v_ignore_armor,
        special_armor_value = v_special_armor_value,
        special_max_critical = v_special_max_critical,
        duration_rounds = v_duration_rounds,
        data = v_level_data,
        effect_data = v_level_effect_data
      where id = v_level_id;
    else
      select level.id
      into v_level_id
      from public.odyssey_ability_level_defs level
      where level.ability_def_id = v_entity_id
        and level.ability_level = v_ability_level
      limit 1;

      if v_level_id is null then
        insert into public.odyssey_ability_level_defs (
          ability_def_id,
          ability_level,
          resource_cost,
          cooldown_rounds,
          range_profile_id,
          attack_accuracy_bonus,
          attack_damage_bonus,
          attack_armor_pierce,
          ignore_armor,
          special_armor_value,
          special_max_critical,
          duration_rounds,
          data,
          effect_data
        )
        values (
          v_entity_id,
          v_ability_level,
          v_resource_cost,
          v_cooldown_rounds,
          v_range_profile_id,
          v_attack_accuracy_bonus,
          v_attack_damage_bonus,
          v_attack_armor_pierce,
          v_ignore_armor,
          v_special_armor_value,
          v_special_max_critical,
          v_duration_rounds,
          v_level_data,
          v_level_effect_data
        )
        returning id into v_level_id;
      else
        update public.odyssey_ability_level_defs
        set
          resource_cost = v_resource_cost,
          cooldown_rounds = v_cooldown_rounds,
          range_profile_id = v_range_profile_id,
          attack_accuracy_bonus = v_attack_accuracy_bonus,
          attack_damage_bonus = v_attack_damage_bonus,
          attack_armor_pierce = v_attack_armor_pierce,
          ignore_armor = v_ignore_armor,
          special_armor_value = v_special_armor_value,
          special_max_critical = v_special_max_critical,
          duration_rounds = v_duration_rounds,
          data = v_level_data,
          effect_data = v_level_effect_data
        where id = v_level_id;
      end if;
    end if;

    v_processed_level_ids := array_append(v_processed_level_ids, v_level_id);
  end loop;

  delete from public.odyssey_ability_level_defs
  where ability_def_id = v_entity_id
    and not (id = any(v_processed_level_ids));

  v_result := public.creator_get_ability(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_upsert_weapon(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_weapon_class_id uuid := nullif(trim(coalesce(v_payload->>'weapon_class_id', '')), '')::uuid;
  v_linked_skill_id uuid := nullif(trim(coalesce(v_payload->>'linked_skill_id', '')), '')::uuid;
  v_caliber_id uuid := nullif(trim(coalesce(v_payload->>'caliber_id', '')), '')::uuid;
  v_range_profile_id uuid := nullif(trim(coalesce(v_payload->>'range_profile_id', '')), '')::uuid;
  v_base_accuracy_bonus integer := coalesce(nullif(trim(coalesce(v_payload->>'base_accuracy_bonus', '')), '')::integer, 0);
  v_base_melee_damage integer := coalesce(nullif(trim(coalesce(v_payload->>'base_melee_damage', '')), '')::integer, 0);
  v_description text := coalesce(v_payload->>'description', '');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_profiles jsonb := public.odyssey_creator_normalize_json_array(v_payload->'profiles');
  v_feature_links jsonb := public.odyssey_creator_normalize_json_array(v_payload->'feature_links');
  v_ability_links jsonb := public.odyssey_creator_normalize_json_array(v_payload->'ability_links');
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
  v_profile jsonb := '{}'::jsonb;
  v_profile_id uuid := null;
  v_profile_code text := '';
  v_profile_name text := '';
  v_profile_description text := '';
  v_profile_attack_type text := '';
  v_profile_weapon_class_id uuid := null;
  v_profile_skill_id uuid := null;
  v_profile_caliber_id uuid := null;
  v_profile_range_profile_id uuid := null;
  v_profile_accuracy_modifier integer := 0;
  v_profile_base_melee_damage integer := 0;
  v_profile_is_default boolean := false;
  v_profile_sort_order integer := 0;
  v_profile_data jsonb := '{}'::jsonb;
  v_profile_tags jsonb := '[]'::jsonb;
  v_profile_fire_mode_ids jsonb := '[]'::jsonb;
  v_profile_magazine_ids jsonb := '[]'::jsonb;
  v_profile_ids_by_code jsonb := '{}'::jsonb;
  v_seen_profile_codes text[] := '{}'::text[];
  v_processed_profile_ids uuid[] := '{}'::uuid[];
  v_profile_default_count integer := 0;
  v_fire_mode_entry jsonb := '{}'::jsonb;
  v_magazine_entry jsonb := '{}'::jsonb;
  v_fire_mode_id uuid := null;
  v_magazine_def_id uuid := null;
  v_first_fire_mode_id uuid := null;
  v_first_magazine_def_id uuid := null;
  v_fire_mode_position integer := 0;
  v_magazine_position integer := 0;
  v_processed_feature_link_ids uuid[] := '{}'::uuid[];
  v_processed_ability_link_ids uuid[] := '{}'::uuid[];
  v_entry jsonb := '{}'::jsonb;
  v_feature_link_id uuid := null;
  v_feature_def_id uuid := null;
  v_feature_profile_id uuid := null;
  v_feature_profile_code text := null;
  v_feature_enabled boolean := true;
  v_feature_sort integer := 0;
  v_feature_data jsonb := '{}'::jsonb;
  v_ability_link_id uuid := null;
  v_ability_def_id uuid := null;
  v_ability_profile_id uuid := null;
  v_ability_profile_code text := null;
  v_ability_grant_mode text := '';
  v_ability_enabled boolean := true;
  v_ability_sort integer := 0;
  v_ability_data jsonb := '{}'::jsonb;
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_weapon_class_id is null or not exists (select 1 from public.odyssey_weapon_class_defs where id = v_weapon_class_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'weapon_class_id is required and must exist.',
      jsonb_build_array(jsonb_build_object('field', 'weapon_class_id', 'message', 'Unknown weapon class.'))
    );
  end if;

  if v_linked_skill_id is null or not exists (select 1 from public.odyssey_skill_defs where id = v_linked_skill_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'linked_skill_id is required and must exist.',
      jsonb_build_array(jsonb_build_object('field', 'linked_skill_id', 'message', 'Unknown skill definition.'))
    );
  end if;

  if v_range_profile_id is null or not exists (select 1 from public.odyssey_range_profile_defs where id = v_range_profile_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'range_profile_id is required and must exist.',
      jsonb_build_array(jsonb_build_object('field', 'range_profile_id', 'message', 'Unknown range profile.'))
    );
  end if;

  if v_caliber_id is not null and not exists (select 1 from public.odyssey_caliber_defs where id = v_caliber_id) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'caliber_id references an unknown caliber.',
      jsonb_build_array(jsonb_build_object('field', 'caliber_id', 'message', 'Unknown caliber.'))
    );
  end if;

  if v_base_melee_damage < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'base_melee_damage must be >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'base_melee_damage', 'message', 'base_melee_damage cannot be negative.'))
    );
  end if;

  if jsonb_array_length(v_profiles) = 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'At least one weapon profile is required.',
      jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Provide at least one profile.'))
    );
  end if;

  if v_id is not null then
    select weapon.id
    into v_entity_id
    from public.odyssey_weapon_model_defs weapon
    where weapon.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'WEAPON_NOT_FOUND',
        'Weapon model was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown weapon model id.'))
      );
    end if;
  else
    select weapon.id
    into v_entity_id
    from public.odyssey_weapon_model_defs weapon
    where weapon.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_weapon_model_defs weapon
    where weapon.code = v_code
      and weapon.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Weapon code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate weapon code.'))
    );
  end if;

  for v_profile in
    select value
    from jsonb_array_elements(v_profiles)
  loop
    v_profile_id := nullif(trim(coalesce(v_profile->>'id', '')), '')::uuid;
    v_profile_code := public.odyssey_creator_normalize_code(v_profile->>'code');
    v_profile_name := trim(coalesce(v_profile->>'name', ''));
    v_profile_attack_type := lower(trim(coalesce(v_profile->>'attack_type', 'ranged')));
    v_profile_is_default := coalesce(nullif(trim(coalesce(v_profile->>'is_default', '')), '')::boolean, false);
    v_profile_weapon_class_id := coalesce(nullif(trim(coalesce(v_profile->>'weapon_class_id', '')), '')::uuid, v_weapon_class_id);
    v_profile_skill_id := coalesce(nullif(trim(coalesce(v_profile->>'linked_skill_id', '')), '')::uuid, v_linked_skill_id);
    v_profile_caliber_id := coalesce(nullif(trim(coalesce(v_profile->>'caliber_id', '')), '')::uuid, v_caliber_id);
    v_profile_range_profile_id := coalesce(nullif(trim(coalesce(v_profile->>'range_profile_id', '')), '')::uuid, v_range_profile_id);
    v_profile_accuracy_modifier := coalesce(nullif(trim(coalesce(v_profile->>'accuracy_modifier', '')), '')::integer, 0);
    v_profile_base_melee_damage := coalesce(nullif(trim(coalesce(v_profile->>'base_melee_damage', '')), '')::integer, v_base_melee_damage);
    v_profile_sort_order := coalesce(nullif(trim(coalesce(v_profile->>'sort_order', '')), '')::integer, 0);
    v_profile_description := coalesce(v_profile->>'description', '');
    v_profile_data := public.odyssey_creator_normalize_json_object(v_profile->'data');
    v_profile_tags := public.odyssey_creator_normalize_text_array(v_profile->'tags');
    v_profile_fire_mode_ids := public.odyssey_creator_normalize_json_array(v_profile->'fire_mode_ids');
    v_profile_magazine_ids := public.odyssey_creator_normalize_json_array(v_profile->'magazine_def_ids');

    if v_profile_code = '' or not public.odyssey_creator_is_valid_code(v_profile_code) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile code must match ^[a-z][a-z0-9_]*$.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Invalid profile code found.'))
      );
    end if;

    if v_profile_code = any(v_seen_profile_codes) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Profile codes must be unique within the weapon payload.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Duplicate profile code found in payload.'))
      );
    end if;

    v_seen_profile_codes := array_append(v_seen_profile_codes, v_profile_code);

    if v_profile_name = '' then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile must have a name.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Profile name cannot be empty.'))
      );
    end if;

    if v_profile_attack_type not in ('ranged', 'melee') then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Profile attack_type must be ranged or melee.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unsupported profile attack_type value.'))
      );
    end if;

    if v_profile_weapon_class_id is null or not exists (select 1 from public.odyssey_weapon_class_defs where id = v_profile_weapon_class_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile must resolve to a valid weapon class.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown profile weapon_class_id.'))
      );
    end if;

    if v_profile_skill_id is null or not exists (select 1 from public.odyssey_skill_defs where id = v_profile_skill_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile must resolve to a valid linked skill.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown profile linked_skill_id.'))
      );
    end if;

    if v_profile_range_profile_id is null or not exists (select 1 from public.odyssey_range_profile_defs where id = v_profile_range_profile_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile must resolve to a valid range profile.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown profile range_profile_id.'))
      );
    end if;

    if v_profile_base_melee_damage < 0 then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Profile base_melee_damage must be >= 0.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Profile base_melee_damage cannot be negative.'))
      );
    end if;

    if jsonb_array_length(v_profile_fire_mode_ids) = 0 then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each profile must have at least one fire mode.',
        jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Profile fire_mode_ids cannot be empty.'))
      );
    end if;

    if v_profile_attack_type = 'ranged' then
      if v_profile_caliber_id is null or not exists (select 1 from public.odyssey_caliber_defs where id = v_profile_caliber_id) then
        return public.odyssey_creator_error(
          'VALIDATION_ERROR',
          'Ranged profiles require a valid caliber.',
          jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown or missing caliber_id for a ranged profile.'))
        );
      end if;

      if jsonb_array_length(v_profile_magazine_ids) = 0 then
        return public.odyssey_creator_error(
          'VALIDATION_ERROR',
          'Ranged profiles require at least one magazine definition.',
          jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'magazine_def_ids cannot be empty for ranged profiles.'))
        );
      end if;
    end if;

    if v_profile_is_default then
      v_profile_default_count := v_profile_default_count + 1;
    end if;
  end loop;

  if v_profile_default_count <> 1 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Exactly one default weapon profile is required.',
      jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Set is_default=true on exactly one profile.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_weapon_model_defs (
      code,
      name,
      weapon_class_id,
      linked_skill_id,
      caliber_id,
      range_profile_id,
      base_accuracy_bonus,
      base_melee_damage,
      description,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_weapon_class_id,
      v_linked_skill_id,
      v_caliber_id,
      v_range_profile_id,
      v_base_accuracy_bonus,
      v_base_melee_damage,
      v_description,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_weapon_model_defs
    set
      code = v_code,
      name = v_name,
      weapon_class_id = v_weapon_class_id,
      linked_skill_id = v_linked_skill_id,
      caliber_id = v_caliber_id,
      range_profile_id = v_range_profile_id,
      base_accuracy_bonus = v_base_accuracy_bonus,
      base_melee_damage = v_base_melee_damage,
      description = v_description,
      tags = v_tags,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  delete from public.odyssey_weapon_model_profiles existing_profile
  where existing_profile.weapon_model_id = v_entity_id
    and not exists (
      select 1
      from jsonb_array_elements(v_profiles) payload_profile
      where (
        nullif(trim(coalesce(payload_profile.value->>'id', '')), '')::uuid is not null
        and existing_profile.id = nullif(trim(coalesce(payload_profile.value->>'id', '')), '')::uuid
      )
      or existing_profile.code = public.odyssey_creator_normalize_code(payload_profile.value->>'code')
    );

  update public.odyssey_weapon_model_profiles profile
  set code = 'tmp_' || replace(profile.id::text, '-', '_')
  where profile.weapon_model_id = v_entity_id
    and exists (
      select 1
      from jsonb_array_elements(v_profiles) payload_profile
      where nullif(trim(coalesce(payload_profile.value->>'id', '')), '')::uuid = profile.id
        and public.odyssey_creator_normalize_code(payload_profile.value->>'code') <> profile.code
    );

  for v_profile in
    select value
    from jsonb_array_elements(v_profiles)
  loop
    v_profile_id := nullif(trim(coalesce(v_profile->>'id', '')), '')::uuid;
    v_profile_code := public.odyssey_creator_normalize_code(v_profile->>'code');
    v_profile_name := trim(coalesce(v_profile->>'name', ''));
    v_profile_description := coalesce(v_profile->>'description', '');
    v_profile_attack_type := lower(trim(coalesce(v_profile->>'attack_type', 'ranged')));
    v_profile_is_default := coalesce(nullif(trim(coalesce(v_profile->>'is_default', '')), '')::boolean, false);
    v_profile_weapon_class_id := coalesce(nullif(trim(coalesce(v_profile->>'weapon_class_id', '')), '')::uuid, v_weapon_class_id);
    v_profile_skill_id := coalesce(nullif(trim(coalesce(v_profile->>'linked_skill_id', '')), '')::uuid, v_linked_skill_id);
    v_profile_caliber_id := coalesce(nullif(trim(coalesce(v_profile->>'caliber_id', '')), '')::uuid, v_caliber_id);
    v_profile_range_profile_id := coalesce(nullif(trim(coalesce(v_profile->>'range_profile_id', '')), '')::uuid, v_range_profile_id);
    v_profile_accuracy_modifier := coalesce(nullif(trim(coalesce(v_profile->>'accuracy_modifier', '')), '')::integer, 0);
    v_profile_base_melee_damage := coalesce(nullif(trim(coalesce(v_profile->>'base_melee_damage', '')), '')::integer, v_base_melee_damage);
    v_profile_sort_order := coalesce(nullif(trim(coalesce(v_profile->>'sort_order', '')), '')::integer, 0);
    v_profile_data := public.odyssey_creator_normalize_json_object(v_profile->'data');
    v_profile_tags := public.odyssey_creator_normalize_text_array(v_profile->'tags');
    v_profile_fire_mode_ids := public.odyssey_creator_normalize_json_array(v_profile->'fire_mode_ids');
    v_profile_magazine_ids := public.odyssey_creator_normalize_json_array(v_profile->'magazine_def_ids');

    if v_profile_id is not null then
      if not exists (
        select 1
        from public.odyssey_weapon_model_profiles profile
        where profile.id = v_profile_id
          and profile.weapon_model_id = v_entity_id
      ) then
        return public.odyssey_creator_error(
          'VALIDATION_ERROR',
          'Profile id does not belong to this weapon.',
          jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Invalid profile id for this weapon.'))
        );
      end if;

      update public.odyssey_weapon_model_profiles
      set
        code = v_profile_code,
        name = v_profile_name,
        description = v_profile_description,
        weapon_class_id = v_profile_weapon_class_id,
        linked_skill_id = v_profile_skill_id,
        caliber_id = v_profile_caliber_id,
        range_profile_id = v_profile_range_profile_id,
        accuracy_modifier = v_profile_accuracy_modifier,
        base_melee_damage = v_profile_base_melee_damage,
        attack_type = v_profile_attack_type,
        is_default = v_profile_is_default,
        data = v_profile_data,
        tags = v_profile_tags,
        sort_order = v_profile_sort_order
      where id = v_profile_id;
    else
      select profile.id
      into v_profile_id
      from public.odyssey_weapon_model_profiles profile
      where profile.weapon_model_id = v_entity_id
        and profile.code = v_profile_code
      limit 1;

      if v_profile_id is null then
        insert into public.odyssey_weapon_model_profiles (
          weapon_model_id,
          code,
          name,
          description,
          weapon_class_id,
          linked_skill_id,
          caliber_id,
          range_profile_id,
          accuracy_modifier,
          base_melee_damage,
          attack_type,
          is_default,
          data,
          tags,
          sort_order
        )
        values (
          v_entity_id,
          v_profile_code,
          v_profile_name,
          v_profile_description,
          v_profile_weapon_class_id,
          v_profile_skill_id,
          v_profile_caliber_id,
          v_profile_range_profile_id,
          v_profile_accuracy_modifier,
          v_profile_base_melee_damage,
          v_profile_attack_type,
          v_profile_is_default,
          v_profile_data,
          v_profile_tags,
          v_profile_sort_order
        )
        returning id into v_profile_id;
      else
        update public.odyssey_weapon_model_profiles
        set
          name = v_profile_name,
          description = v_profile_description,
          weapon_class_id = v_profile_weapon_class_id,
          linked_skill_id = v_profile_skill_id,
          caliber_id = v_profile_caliber_id,
          range_profile_id = v_profile_range_profile_id,
          accuracy_modifier = v_profile_accuracy_modifier,
          base_melee_damage = v_profile_base_melee_damage,
          attack_type = v_profile_attack_type,
          is_default = v_profile_is_default,
          data = v_profile_data,
          tags = v_profile_tags,
          sort_order = v_profile_sort_order
        where id = v_profile_id;
      end if;
    end if;

    v_profile_ids_by_code := v_profile_ids_by_code || jsonb_build_object(v_profile_code, v_profile_id::text);
    v_processed_profile_ids := array_append(v_processed_profile_ids, v_profile_id);

    v_first_fire_mode_id := null;
    v_fire_mode_position := 0;
    for v_fire_mode_entry in
      select value
      from jsonb_array_elements(v_profile_fire_mode_ids)
    loop
      v_fire_mode_id := trim(both '"' from v_fire_mode_entry::text)::uuid;
      if not exists (select 1 from public.odyssey_fire_mode_defs where id = v_fire_mode_id) then
        return public.odyssey_creator_error(
          'VALIDATION_ERROR',
          'Profile contains an unknown fire mode.',
          jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown fire_mode_id in profile.'))
        );
      end if;

      v_fire_mode_position := v_fire_mode_position + 1;
      if v_first_fire_mode_id is null then
        v_first_fire_mode_id := v_fire_mode_id;
      end if;

      insert into public.odyssey_weapon_profile_fire_modes (
        profile_id,
        fire_mode_id,
        is_default,
        sort_order
      )
      values (
        v_profile_id,
        v_fire_mode_id,
        v_fire_mode_id = v_first_fire_mode_id,
        v_fire_mode_position * 10
      )
      on conflict (profile_id, fire_mode_id) do update
      set
        is_default = excluded.is_default,
        sort_order = excluded.sort_order;
    end loop;

    delete from public.odyssey_weapon_profile_fire_modes pfm
    where pfm.profile_id = v_profile_id
      and not exists (
        select 1
        from jsonb_array_elements(v_profile_fire_mode_ids) entry
        where trim(both '"' from entry.value::text)::uuid = pfm.fire_mode_id
      );

    v_first_magazine_def_id := null;
    v_magazine_position := 0;
    if v_profile_attack_type = 'ranged' then
      for v_magazine_entry in
        select value
        from jsonb_array_elements(v_profile_magazine_ids)
      loop
        v_magazine_def_id := trim(both '"' from v_magazine_entry::text)::uuid;
        if not exists (select 1 from public.odyssey_magazine_defs where id = v_magazine_def_id) then
          return public.odyssey_creator_error(
            'VALIDATION_ERROR',
            'Profile contains an unknown magazine definition.',
            jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Unknown magazine_def_id in profile.'))
          );
        end if;

        if v_profile_caliber_id is not null and not exists (
          select 1
          from public.odyssey_magazine_defs mag
          where mag.id = v_magazine_def_id
            and mag.caliber_id = v_profile_caliber_id
        ) then
          return public.odyssey_creator_error(
            'VALIDATION_ERROR',
            'Magazine definition caliber must match the ranged profile caliber.',
            jsonb_build_array(jsonb_build_object('field', 'profiles', 'message', 'Magazine caliber does not match profile caliber.'))
          );
        end if;

        v_magazine_position := v_magazine_position + 1;
        if v_first_magazine_def_id is null then
          v_first_magazine_def_id := v_magazine_def_id;
        end if;

        insert into public.odyssey_weapon_profile_magazines (
          profile_id,
          magazine_def_id,
          is_default,
          sort_order
        )
        values (
          v_profile_id,
          v_magazine_def_id,
          v_magazine_def_id = v_first_magazine_def_id,
          v_magazine_position * 10
        )
        on conflict (profile_id, magazine_def_id) do update
        set
          is_default = excluded.is_default,
          sort_order = excluded.sort_order;
      end loop;
    end if;

    delete from public.odyssey_weapon_profile_magazines ppm
    where ppm.profile_id = v_profile_id
      and (
        v_profile_attack_type <> 'ranged'
        or not exists (
          select 1
          from jsonb_array_elements(v_profile_magazine_ids) entry
          where trim(both '"' from entry.value::text)::uuid = ppm.magazine_def_id
        )
      );
  end loop;

  delete from public.odyssey_weapon_model_profiles
  where weapon_model_id = v_entity_id
    and not (id = any(v_processed_profile_ids));

  update public.odyssey_weapon_model_profiles
  set is_default = (id = any(
    array(
      select profile_id
      from (
        select
          p.id as profile_id,
          row_number() over (
            partition by p.weapon_model_id
            order by p.is_default desc, p.sort_order, p.created_at, p.id
          ) as rn
        from public.odyssey_weapon_model_profiles p
        where p.weapon_model_id = v_entity_id
      ) ranked
      where ranked.rn = 1
    )
  ))
  where weapon_model_id = v_entity_id;

  for v_entry in
    select value
    from jsonb_array_elements(v_feature_links)
  loop
    v_feature_def_id := nullif(trim(coalesce(v_entry->>'feature_def_id', '')), '')::uuid;
    v_feature_profile_id := nullif(trim(coalesce(v_entry->>'profile_id', '')), '')::uuid;
    v_feature_profile_code := nullif(public.odyssey_creator_normalize_code(v_entry->>'profile_code'), '');
    v_feature_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled_by_default', '')), '')::boolean, true);
    v_feature_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_feature_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_feature_def_id is null or not exists (select 1 from public.odyssey_weapon_feature_defs where id = v_feature_def_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'feature_links contain an unknown feature definition.',
        jsonb_build_array(jsonb_build_object('field', 'feature_links', 'message', 'Unknown feature_def_id.'))
      );
    end if;

    if v_feature_profile_id is null and v_feature_profile_code is not null then
      v_feature_profile_id := nullif(v_profile_ids_by_code->>v_feature_profile_code, '')::uuid;
    end if;

    if v_feature_profile_id is not null and not exists (
      select 1
      from public.odyssey_weapon_model_profiles profile
      where profile.id = v_feature_profile_id
        and profile.weapon_model_id = v_entity_id
    ) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'feature_links reference an unknown weapon profile.',
        jsonb_build_array(jsonb_build_object('field', 'feature_links', 'message', 'Unknown profile_id/profile_code for feature link.'))
      );
    end if;

    select link.id
    into v_feature_link_id
    from public.odyssey_weapon_model_features link
    where link.weapon_model_id = v_entity_id
      and link.feature_def_id = v_feature_def_id
      and link.profile_id is not distinct from v_feature_profile_id
    for update;

    if v_feature_link_id is null then
      insert into public.odyssey_weapon_model_features (
        weapon_model_id,
        feature_def_id,
        profile_id,
        is_enabled_by_default,
        data,
        sort_order
      )
      values (
        v_entity_id,
        v_feature_def_id,
        v_feature_profile_id,
        v_feature_enabled,
        v_feature_data,
        v_feature_sort
      )
      returning id into v_feature_link_id;
    else
      update public.odyssey_weapon_model_features
      set
        profile_id = v_feature_profile_id,
        is_enabled_by_default = v_feature_enabled,
        data = v_feature_data,
        sort_order = v_feature_sort
      where id = v_feature_link_id;
    end if;

    v_processed_feature_link_ids := array_append(v_processed_feature_link_ids, v_feature_link_id);
  end loop;

  delete from public.odyssey_weapon_model_features
  where weapon_model_id = v_entity_id
    and not (id = any(v_processed_feature_link_ids));

  for v_entry in
    select value
    from jsonb_array_elements(v_ability_links)
  loop
    v_ability_def_id := nullif(trim(coalesce(v_entry->>'ability_def_id', '')), '')::uuid;
    v_ability_profile_id := nullif(trim(coalesce(v_entry->>'profile_id', '')), '')::uuid;
    v_ability_profile_code := nullif(public.odyssey_creator_normalize_code(v_entry->>'profile_code'), '');
    v_ability_grant_mode := lower(trim(coalesce(v_entry->>'grant_mode', 'available')));
    v_ability_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled', '')), '')::boolean, true);
    v_ability_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_ability_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_ability_def_id is null or not exists (select 1 from public.odyssey_ability_defs where id = v_ability_def_id) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_links contain an unknown ability.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Unknown ability_def_id.'))
      );
    end if;

    if v_ability_grant_mode not in ('available', 'passive', 'activated') then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'grant_mode is invalid.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'grant_mode must be available, passive, or activated.'))
      );
    end if;

    if v_ability_profile_id is null and v_ability_profile_code is not null then
      v_ability_profile_id := nullif(v_profile_ids_by_code->>v_ability_profile_code, '')::uuid;
    end if;

    if v_ability_profile_id is not null and not exists (
      select 1
      from public.odyssey_weapon_model_profiles profile
      where profile.id = v_ability_profile_id
        and profile.weapon_model_id = v_entity_id
    ) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'ability_links reference an unknown weapon profile.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Unknown profile_id/profile_code for ability link.'))
      );
    end if;

    select link.id
    into v_ability_link_id
    from public.odyssey_weapon_model_abilities link
    where link.weapon_model_id = v_entity_id
      and link.ability_def_id = v_ability_def_id
      and link.profile_id is not distinct from v_ability_profile_id
    for update;

    if v_ability_link_id is null then
      insert into public.odyssey_weapon_model_abilities (
        weapon_model_id,
        profile_id,
        ability_def_id,
        grant_mode,
        is_enabled,
        sort_order,
        data
      )
      values (
        v_entity_id,
        v_ability_profile_id,
        v_ability_def_id,
        v_ability_grant_mode,
        v_ability_enabled,
        v_ability_sort,
        v_ability_data
      )
      returning id into v_ability_link_id;
    else
      update public.odyssey_weapon_model_abilities
      set
        profile_id = v_ability_profile_id,
        grant_mode = v_ability_grant_mode,
        is_enabled = v_ability_enabled,
        sort_order = v_ability_sort,
        data = v_ability_data
      where id = v_ability_link_id;
    end if;

    v_processed_ability_link_ids := array_append(v_processed_ability_link_ids, v_ability_link_id);
  end loop;

  delete from public.odyssey_weapon_model_abilities
  where weapon_model_id = v_entity_id
    and not (id = any(v_processed_ability_link_ids));

  v_result := public.creator_get_weapon(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

grant execute on function public.odyssey_creator_error(text, text, jsonb) to anon, authenticated;
grant execute on function public.odyssey_creator_normalize_code(text) to anon, authenticated;
grant execute on function public.odyssey_creator_is_valid_code(text) to anon, authenticated;
grant execute on function public.odyssey_creator_normalize_json_object(jsonb) to anon, authenticated;
grant execute on function public.odyssey_creator_normalize_json_array(jsonb) to anon, authenticated;
grant execute on function public.odyssey_creator_normalize_text_array(jsonb) to anon, authenticated;
grant execute on function public.odyssey_creator_build_weapon_bundle(uuid) to anon, authenticated;
grant execute on function public.odyssey_creator_build_equipment_model_bundle(uuid) to anon, authenticated;
grant execute on function public.odyssey_creator_build_item_def_bundle(uuid) to anon, authenticated;
grant execute on function public.odyssey_creator_build_ability_bundle(uuid) to anon, authenticated;
grant execute on function public.odyssey_creator_build_perk_bundle(uuid) to anon, authenticated;
grant execute on function public.get_creator_reference_data() to anon, authenticated;
grant execute on function public.creator_list_weapons(text) to anon, authenticated;
grant execute on function public.creator_get_weapon(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_weapon(jsonb) to anon, authenticated;
grant execute on function public.creator_list_ammo_types(text) to anon, authenticated;
grant execute on function public.creator_get_ammo_type(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_ammo_type(jsonb) to anon, authenticated;
grant execute on function public.creator_list_magazine_defs(text) to anon, authenticated;
grant execute on function public.creator_get_magazine_def(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_magazine_def(jsonb) to anon, authenticated;
grant execute on function public.creator_list_weapon_feature_defs(text) to anon, authenticated;
grant execute on function public.creator_get_weapon_feature_def(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_weapon_feature_def(jsonb) to anon, authenticated;
grant execute on function public.creator_list_armor_models(text) to anon, authenticated;
grant execute on function public.creator_get_armor_model(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_armor_model(jsonb) to anon, authenticated;
grant execute on function public.creator_list_item_defs(text) to anon, authenticated;
grant execute on function public.creator_get_item_def(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_item_def(jsonb) to anon, authenticated;
grant execute on function public.creator_list_abilities(text) to anon, authenticated;
grant execute on function public.creator_get_ability(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_ability(jsonb) to anon, authenticated;
grant execute on function public.creator_list_perks(text) to anon, authenticated;
grant execute on function public.creator_get_perk(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_perk(jsonb) to anon, authenticated;
