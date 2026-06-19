create or replace function public.odyssey_try_parse_uuid(
  p_value text
)
returns uuid
language plpgsql
immutable
as $$
declare
  v_trimmed text := nullif(trim(coalesce(p_value, '')), '');
begin
  if v_trimmed is null then
    return null;
  end if;

  begin
    return v_trimmed::uuid;
  exception
    when invalid_text_representation then
      return null;
  end;
end;
$$;

update public.odyssey_body_part_defs
set serious_counts_as_critical = false
where code in (
  'head',
  'torso',
  'l_arm',
  'r_arm',
  'l_leg',
  'r_leg',
  'shield',
  'special'
);

do $$
begin
  perform public.initialize_character_weapon_profile_states(w.id)
  from public.odyssey_character_weapons w;

  perform public.initialize_character_weapon_feature_states(w.id)
  from public.odyssey_character_weapons w;
end;
$$;

create or replace function public.odyssey_get_character_weapon_profile(
  p_character_weapon_id uuid,
  p_profile_id uuid
)
returns jsonb
language sql
stable
as $$
  with weapon_row as (
    select
      w.id,
      w.weapon_model_id,
      w.active_profile_id,
      w.loaded_magazine_id,
      w.selected_fire_mode_id
    from public.odyssey_character_weapons w
    where w.id = p_character_weapon_id
  ),
  profile_rows as (
    select
      p.id,
      p.weapon_model_id,
      p.code,
      p.name,
      p.description,
      p.attack_type,
      p.data,
      p.tags,
      p.sort_order,
      p.is_default,
      coalesce(pwc.code, mwc.code) as weapon_class_code,
      coalesce(pwc.name, mwc.name) as weapon_class_name,
      coalesce(pskill.code, mskill.code) as linked_skill_code,
      coalesce(pskill.name, mskill.name) as linked_skill_name,
      coalesce(pcal.code, mcal.code) as caliber_code,
      coalesce(pcal.name, mcal.name) as caliber_name,
      coalesce(prp.code, mrp.code) as range_profile_code,
      coalesce(prp.name, mrp.name) as range_profile_name,
      coalesce(p.accuracy_modifier, wm.base_accuracy_bonus) as accuracy_modifier,
      coalesce(p.base_melee_damage, wm.base_melee_damage) as base_melee_damage,
      coalesce(pcal.base_damage_per_round, mcal.base_damage_per_round, 0) as base_damage_per_round,
      case
        when s.id is not null then s.loaded_magazine_id
        when coalesce(w.active_profile_id = p.id, p.is_default) then w.loaded_magazine_id
        else null
      end as candidate_loaded_magazine_id,
      case
        when s.id is not null
             and s.selected_fire_mode_id is not null
             and public.odyssey_is_fire_mode_allowed_for_profile(p.id, s.selected_fire_mode_id)
          then s.selected_fire_mode_id
        when coalesce(w.active_profile_id = p.id, p.is_default)
             and w.selected_fire_mode_id is not null
             and public.odyssey_is_fire_mode_allowed_for_profile(p.id, w.selected_fire_mode_id)
          then w.selected_fire_mode_id
        else public.odyssey_get_default_profile_fire_mode_id(p.id)
      end as candidate_selected_fire_mode_id,
      coalesce(
        s.is_active,
        case
          when w.active_profile_id is not null then w.active_profile_id = p.id
          else p.is_default
        end,
        false
      ) as is_active
    from weapon_row w
    join public.odyssey_weapon_model_profiles p
      on p.weapon_model_id = w.weapon_model_id
     and p.id = p_profile_id
    join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
    left join public.odyssey_weapon_class_defs pwc on pwc.id = p.weapon_class_id
    left join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
    left join public.odyssey_skill_defs pskill on pskill.id = p.linked_skill_id
    left join public.odyssey_skill_defs mskill on mskill.id = wm.linked_skill_id
    left join public.odyssey_caliber_defs pcal on pcal.id = p.caliber_id
    left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
    left join public.odyssey_range_profile_defs prp on prp.id = p.range_profile_id
    left join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
    left join public.odyssey_character_weapon_profile_states s
      on s.character_weapon_id = w.id
     and s.profile_id = p.id
  ),
  resolved_profile as (
    select
      pr.*,
      case
        when pr.candidate_loaded_magazine_id is not null
             and public.odyssey_is_magazine_compatible_with_profile(pr.id, pr.candidate_loaded_magazine_id)
          then pr.candidate_loaded_magazine_id
        else null
      end as loaded_magazine_id,
      case
        when pr.candidate_selected_fire_mode_id is not null
             and public.odyssey_is_fire_mode_allowed_for_profile(pr.id, pr.candidate_selected_fire_mode_id)
          then pr.candidate_selected_fire_mode_id
        else public.odyssey_get_default_profile_fire_mode_id(pr.id)
      end as selected_fire_mode_id
    from profile_rows pr
  )
  select coalesce(
    (
      select jsonb_build_object(
        'id', pr.id,
        'code', pr.code,
        'name', pr.name,
        'description', pr.description,
        'attack_type', pr.attack_type,
        'weapon_class', pr.weapon_class_code,
        'weapon_class_name', pr.weapon_class_name,
        'linked_skill', pr.linked_skill_code,
        'linked_skill_name', pr.linked_skill_name,
        'caliber', pr.caliber_code,
        'caliber_name', pr.caliber_name,
        'range_profile', pr.range_profile_code,
        'range_profile_name', pr.range_profile_name,
        'accuracy_modifier', pr.accuracy_modifier,
        'base_melee_damage', pr.base_melee_damage,
        'base_damage_per_round', pr.base_damage_per_round,
        'data', pr.data,
        'tags', pr.tags,
        'sort_order', pr.sort_order,
        'is_default', pr.is_default,
        'is_active', pr.is_active,
        'loaded_magazine',
          case
            when cm.id is null then null
            else jsonb_build_object(
              'id', cm.id,
              'name', coalesce(nullif(trim(cm.custom_name), ''), md.name),
              'custom_name', cm.custom_name,
              'current_rounds', cm.current_rounds,
              'capacity', md.capacity,
              'ammo_type', ammo.code,
              'ammo_type_name', ammo.name,
              'magazine_def', md.code,
              'magazine_def_name', md.name
            )
          end,
        'selected_fire_mode',
          case
            when fm.id is null then null
            else jsonb_build_object(
              'id', fm.id,
              'code', fm.code,
              'name', fm.name,
              'fixed_rounds', fm.fixed_rounds,
              'min_rounds', fm.min_rounds,
              'max_rounds', fm.max_rounds,
              'is_random', fm.is_random,
              'accuracy_modifier', fm.accuracy_modifier
            )
          end,
        'available_fire_modes',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', afm.id,
                  'code', afm.code,
                  'name', afm.name,
                  'fixed_rounds', afm.fixed_rounds,
                  'min_rounds', afm.min_rounds,
                  'max_rounds', afm.max_rounds,
                  'is_random', afm.is_random,
                  'accuracy_modifier', afm.accuracy_modifier,
                  'is_default', pfm.is_default
                )
                order by pfm.is_default desc, pfm.sort_order, afm.sort_order, afm.name
              )
              from public.odyssey_weapon_profile_fire_modes pfm
              join public.odyssey_fire_mode_defs afm on afm.id = pfm.fire_mode_id
              where pfm.profile_id = pr.id
            ),
            '[]'::jsonb
          ),
        'compatible_magazines',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', cmd.id,
                  'code', cmd.code,
                  'name', cmd.name,
                  'capacity', cmd.capacity,
                  'caliber', cmdc.code,
                  'caliber_name', cmdc.name,
                  'is_default', ppm.is_default
                )
                order by ppm.is_default desc, ppm.sort_order, cmd.sort_order, cmd.name
              )
              from public.odyssey_weapon_profile_magazines ppm
              join public.odyssey_magazine_defs cmd on cmd.id = ppm.magazine_def_id
              join public.odyssey_caliber_defs cmdc on cmdc.id = cmd.caliber_id
              where ppm.profile_id = pr.id
            ),
            '[]'::jsonb
          )
      )
      from resolved_profile pr
      left join public.odyssey_character_magazines cm on cm.id = pr.loaded_magazine_id
      left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
      left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
      left join public.odyssey_fire_mode_defs fm on fm.id = pr.selected_fire_mode_id
    ),
    null
  );
$$;

create or replace function public.odyssey_get_character_weapon_profiles(
  p_character_weapon_id uuid
)
returns jsonb
language sql
stable
as $$
  with weapon_row as (
    select w.weapon_model_id
    from public.odyssey_character_weapons w
    where w.id = p_character_weapon_id
  )
  select coalesce(
    (
      select jsonb_agg(profile_json order by sort_order, code)
      from (
        select
          p.sort_order,
          p.code,
          public.odyssey_get_character_weapon_profile(p_character_weapon_id, p.id) as profile_json
        from weapon_row w
        join public.odyssey_weapon_model_profiles p on p.weapon_model_id = w.weapon_model_id
      ) q
      where profile_json is not null
    ),
    '[]'::jsonb
  );
$$;

create or replace function public.odyssey_get_active_character_weapon_profile(
  p_character_weapon_id uuid
)
returns jsonb
language sql
stable
as $$
  with weapon_row as (
    select
      w.id,
      w.weapon_model_id,
      w.active_profile_id
    from public.odyssey_character_weapons w
    where w.id = p_character_weapon_id
  ),
  resolved_profile as (
    select
      coalesce(
        (
          select s.profile_id
          from public.odyssey_character_weapon_profile_states s
          where s.character_weapon_id = w.id
            and s.is_active = true
          order by s.updated_at desc, s.created_at desc, s.id
          limit 1
        ),
        w.active_profile_id,
        (
          select p.id
          from public.odyssey_weapon_model_profiles p
          where p.weapon_model_id = w.weapon_model_id
            and p.is_default = true
          order by p.sort_order, p.created_at, p.id
          limit 1
        ),
        (
          select p.id
          from public.odyssey_weapon_model_profiles p
          where p.weapon_model_id = w.weapon_model_id
          order by p.is_default desc, p.sort_order, p.created_at, p.id
          limit 1
        )
      ) as profile_id
    from weapon_row w
  )
  select public.odyssey_get_character_weapon_profile(
    p_character_weapon_id,
    rp.profile_id
  )
  from resolved_profile rp;
$$;

create or replace function public.get_character_weapon_features(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_active_profile_id uuid := null;
  v_features jsonb := '[]'::jsonb;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'character_weapon_id', p_character_weapon_id,
      'active_profile_id', null,
      'features', '[]'::jsonb
    );
  end if;

  v_active_profile_id := coalesce(
    (
      select s.profile_id
      from public.odyssey_character_weapon_profile_states s
      where s.character_weapon_id = v_weapon.id
        and s.is_active = true
      order by s.updated_at desc, s.created_at desc, s.id
      limit 1
    ),
    v_weapon.active_profile_id
  );

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'state_id', s.id,
          'feature_def_id', def.id,
          'code', def.code,
          'name', def.name,
          'feature_type', def.feature_type,
          'activation_type', def.activation_type,
          'description', def.description,
          'profile_id', link.profile_id,
          'profile_code', profile.code,
          'profile_name', profile.name,
          'is_active', coalesce(s.is_active, false),
          'is_enabled', coalesce(s.is_enabled, link.is_enabled_by_default, true),
          'current_charges', coalesce(s.current_charges, def.default_current_charges),
          'max_charges', coalesce(s.max_charges, def.default_max_charges),
          'recharge_rounds_left', s.recharge_rounds_left,
          'cooldown_rounds_left', s.cooldown_rounds_left,
          'active_rounds_left', s.active_rounds_left,
          'active_uses_left', s.active_uses_left,
          'requires_reload', coalesce(s.requires_reload, false),
          'data',
            public.odyssey_merge_weapon_feature_data(
              public.odyssey_merge_weapon_feature_data(def.data, coalesce(link.data, '{}'::jsonb)),
              coalesce(s.data, '{}'::jsonb)
            ),
          'definition_data', def.data,
          'model_data', coalesce(link.data, '{}'::jsonb),
          'state_data', coalesce(s.data, '{}'::jsonb),
          'effect_data', def.effect_data,
          'tags', def.tags
        )
        order by
          case when link.profile_id = v_active_profile_id then 0 when link.profile_id is null then 1 else 2 end,
          coalesce(profile.sort_order, 0),
          def.sort_order,
          def.code
      ),
      '[]'::jsonb
    )
  into v_features
  from public.odyssey_weapon_model_features link
  join public.odyssey_weapon_feature_defs def on def.id = link.feature_def_id
  left join public.odyssey_character_weapon_feature_states s
    on s.character_weapon_id = v_weapon.id
   and s.feature_def_id = link.feature_def_id
   and coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  left join public.odyssey_weapon_model_profiles profile on profile.id = link.profile_id
  where link.weapon_model_id = v_weapon.weapon_model_id;

  return jsonb_build_object(
    'character_weapon_id', v_weapon.id,
    'active_profile_id', v_active_profile_id,
    'features', v_features
  );
end;
$$;

create or replace function public.get_character_armory(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_weapons jsonb := '[]'::jsonb;
  v_magazines jsonb := '[]'::jsonb;
begin
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
          'active_profile', runtime.active_profile_json,
          'profiles', runtime.profiles_json,
          'features', coalesce(runtime.features_bundle->'features', '[]'::jsonb),
          'loaded_magazine', coalesce(runtime.active_profile_json->'loaded_magazine', 'null'::jsonb),
          'selected_fire_mode', coalesce(runtime.active_profile_json->'selected_fire_mode', 'null'::jsonb),
          'available_fire_modes', coalesce(runtime.active_profile_json->'available_fire_modes', '[]'::jsonb),
          'compatible_magazines', coalesce(runtime.active_profile_json->'compatible_magazines', '[]'::jsonb)
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
    'weapons', coalesce(v_weapons, '[]'::jsonb),
    'magazines', coalesce(v_magazines, '[]'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_apply_equipment_critical_damage(
  p_body_part_id uuid,
  p_critical_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_item record;
  v_body_part record;
  v_requested integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_remaining integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_absorbed integer := 0;
  v_absorb integer := 0;
  v_updates jsonb := '[]'::jsonb;
  v_new_item_armor_critical integer := 0;
  v_new_item_armor_destroyed boolean := false;
  v_items_changed boolean := false;
begin
  if v_requested <= 0 then
    return jsonb_build_object(
      'absorbed', 0,
      'remaining', 0,
      'updated_items', '[]'::jsonb,
      'items_changed', false,
      'body_part', null
    );
  end if;

  select
    b.id,
    b.character_id
  into v_body_part
  from public.odyssey_character_body_parts b
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'absorbed', 0,
      'remaining', v_requested,
      'updated_items', '[]'::jsonb,
      'items_changed', false,
      'body_part', null
    );
  end if;

  for v_item in
    select
      e.id,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.sort_order,
      e.created_at,
      coalesce(nullif(trim(e.custom_name), ''), m.name) as item_name
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    where e.equipped_body_part_id = p_body_part_id
      and e.is_equipped = true
    order by e.sort_order, e.created_at, e.id
    for update of e
  loop
    exit when v_remaining <= 0;

    if coalesce(v_item.armor_max_critical, 0) <= coalesce(v_item.armor_critical, 0) then
      continue;
    end if;

    v_absorb := least(
      v_remaining,
      greatest(coalesce(v_item.armor_max_critical, 0) - coalesce(v_item.armor_critical, 0), 0)
    );

    if v_absorb <= 0 then
      continue;
    end if;

    v_new_item_armor_critical := coalesce(v_item.armor_critical, 0) + v_absorb;
    v_new_item_armor_destroyed := case
      when coalesce(v_item.armor_max_critical, 0) > 0
           and v_new_item_armor_critical >= coalesce(v_item.armor_max_critical, 0)
        then true
      else coalesce(v_item.armor_destroyed, false)
    end;

    update public.odyssey_character_equipment_items
    set
      armor_critical = v_new_item_armor_critical,
      armor_destroyed = v_new_item_armor_destroyed,
      updated_at = timezone('utc', now())
    where id = v_item.id;

    v_updates := v_updates || jsonb_build_array(
      jsonb_build_object(
        'id', v_item.id,
        'name', v_item.item_name,
        'absorbed_critical', v_absorb,
        'armor_critical', v_new_item_armor_critical,
        'armor_max_critical', coalesce(v_item.armor_max_critical, 0),
        'armor_destroyed', v_new_item_armor_destroyed
      )
    );

    v_absorbed := v_absorbed + v_absorb;
    v_remaining := v_remaining - v_absorb;
    v_items_changed := true;
  end loop;

  return jsonb_build_object(
    'absorbed', v_absorbed,
    'remaining', greatest(v_requested - v_absorbed, 0),
    'updated_items', v_updates,
    'items_changed', v_items_changed,
    'body_part',
      jsonb_build_object(
        'id', v_body_part.id,
        'character_id', v_body_part.character_id,
        'absorbed_by_items', v_absorbed
      )
  );
end;
$$;

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
  v_body_critical_delta integer := 0;
  v_armor_critical_absorbed integer := 0;
  v_armor_item_updates jsonb := '[]'::jsonb;
  v_armor_result jsonb := '{}'::jsonb;
  v_refresh_result jsonb := '{}'::jsonb;
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

  if v_requested_critical > 0 then
    v_armor_result := public.odyssey_apply_equipment_critical_damage(
      p_body_part_id,
      v_requested_critical
    );
    v_armor_critical_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_critical_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_critical - v_armor_critical_absorbed, 0)
    );
    v_armor_item_updates := coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  v_has_body_delta :=
    v_requested_minor > 0
    or v_requested_serious > 0
    or v_body_critical_delta > 0;

  if v_has_body_delta then
    v_next_minor := coalesce(v_body_part.minor, 0) + v_requested_minor;
    v_next_serious := coalesce(v_body_part.serious, 0) + v_requested_serious;
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

  if v_has_body_delta or v_armor_items_changed then
    v_refresh_result := public.odyssey_refresh_character_combat_state(v_body_part.character_id);
  end if;

  v_body_state := coalesce(public.odyssey_get_character_body_part_state(p_body_part_id), '{}'::jsonb);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_body_part.character_id,
    'body_part_id', p_body_part_id,
    'raw_minor_delta', v_requested_minor,
    'raw_serious_delta', v_requested_serious,
    'raw_critical_delta', v_requested_critical,
    'body_minor_delta', v_requested_minor,
    'body_serious_delta', v_requested_serious,
    'body_critical_delta', v_body_critical_delta,
    'armor_critical_absorbed', v_armor_critical_absorbed,
    'armor_item_updates', v_armor_item_updates,
    'body_part', v_body_state,
    'target_state', coalesce(v_refresh_result->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.load_weapon_profile_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_profile_id uuid := public.odyssey_try_parse_uuid(p_payload->>'profile_id');
  v_character_magazine_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_magazine_id');
  v_weapon public.odyssey_character_weapons%rowtype;
  v_target_state_id uuid := null;
  v_affected_weapons uuid[];
  v_item uuid;
  v_magazine public.odyssey_character_magazines%rowtype;
begin
  if v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_WEAPON_ID_REQUIRED',
      'message', 'character_weapon_id is required.'
    );
  end if;

  if v_profile_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_ID_REQUIRED',
      'message', 'profile_id is required.'
    );
  end if;

  if v_character_magazine_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_MAGAZINE_ID_REQUIRED',
      'message', 'character_magazine_id is required.'
    );
  end if;

  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', 'Weapon was not found.'
    );
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);

  select s.id
  into v_target_state_id
  from public.odyssey_character_weapon_profile_states s
  join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = v_profile_id
    and p.weapon_model_id = v_weapon.weapon_model_id
  limit 1;

  if v_target_state_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_NOT_FOUND',
      'message', 'Selected profile was not found for this weapon.'
    );
  end if;

  select *
  into v_magazine
  from public.odyssey_character_magazines cm
  where cm.id = v_character_magazine_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_NOT_FOUND',
      'message', 'Magazine was not found.'
    );
  end if;

  if v_magazine.character_id <> v_weapon.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_CHARACTER_MISMATCH',
      'message', 'Magazine does not belong to the weapon owner.'
    );
  end if;

  if not public.odyssey_is_magazine_compatible_with_profile(v_profile_id, v_character_magazine_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_INCOMPATIBLE',
      'message', 'Magazine is not compatible with the selected weapon profile.'
    );
  end if;

  with cleared as (
    update public.odyssey_character_weapon_profile_states
    set loaded_magazine_id = null
    where loaded_magazine_id = v_character_magazine_id
      and id <> v_target_state_id
    returning character_weapon_id
  )
  select coalesce(array_agg(distinct character_weapon_id), '{}'::uuid[])
  into v_affected_weapons
  from cleared;

  update public.odyssey_character_weapon_profile_states
  set loaded_magazine_id = v_character_magazine_id
  where id = v_target_state_id;

  for v_item in
    select distinct weapon_id
    from (
      select unnest(coalesce(v_affected_weapons, '{}'::uuid[])) as weapon_id
      union all
      select v_weapon.id
    ) q
  loop
    perform public.odyssey_sync_character_weapon_profile_cache(v_item);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'profile_id', v_profile_id,
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.gm_update_character_attribute(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_attribute_def_id uuid := public.odyssey_try_parse_uuid(v_payload->>'attribute_def_id');
  v_attribute_code text := lower(trim(coalesce(v_payload->>'attribute_code', '')));
  v_operation text := lower(trim(coalesce(v_payload->>'operation', '')));
  v_value_text text := nullif(trim(coalesce(v_payload->>'value', '')), '');
  v_value integer := 0;
  v_reason text := nullif(trim(coalesce(v_payload->>'reason', '')), '');
  v_actor text := coalesce(nullif(trim(coalesce(v_payload->>'actor', '')), ''), 'gm');
  v_attribute_def record;
  v_attribute_row public.odyssey_character_attributes%rowtype;
  v_previous_value integer := 0;
  v_new_value integer := 0;
  v_refresh_result jsonb := '{}'::jsonb;
  v_state_version integer := 0;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id is required and must be a valid UUID.'
    );
  end if;

  if v_operation not in ('set', 'adjust') then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_OPERATION',
      'message', 'operation must be set or adjust.'
    );
  end if;

  if v_attribute_code = '' and v_attribute_def_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Provide attribute_code or attribute_def_id.'
    );
  end if;

  if v_value_text is not null then
    if v_value_text !~ '^-?[0-9]+$' then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_VALUE',
        'message', 'value must be an integer.'
      );
    end if;
    v_value := v_value_text::integer;
  end if;

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character not found.'
    );
  end if;

  if v_attribute_code <> '' then
    select
      d.id,
      d.code,
      d.name,
      d.max_value
    into v_attribute_def
    from public.odyssey_attribute_defs d
    where d.code = v_attribute_code;
  else
    select
      d.id,
      d.code,
      d.name,
      d.max_value
    into v_attribute_def
    from public.odyssey_attribute_defs d
    where d.id = v_attribute_def_id;
  end if;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ATTRIBUTE_NOT_FOUND',
      'message', 'Attribute definition not found.'
    );
  end if;

  if v_attribute_def_id is not null and v_attribute_code <> '' and v_attribute_def.id <> v_attribute_def_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'REFERENCE_MISMATCH',
      'message', 'attribute_code and attribute_def_id refer to different attributes.'
    );
  end if;

  select *
  into v_attribute_row
  from public.odyssey_character_attributes a
  where a.character_id = v_character_id
    and a.attribute_def_id = v_attribute_def.id
  for update of a;

  if not found then
    insert into public.odyssey_character_attributes (
      character_id,
      attribute_def_id,
      value
    )
    values (
      v_character_id,
      v_attribute_def.id,
      0
    )
    on conflict (character_id, attribute_def_id) do nothing;

    select *
    into v_attribute_row
    from public.odyssey_character_attributes a
    where a.character_id = v_character_id
      and a.attribute_def_id = v_attribute_def.id
    for update of a;
  end if;

  v_previous_value := coalesce(v_attribute_row.value, 0);
  if v_operation = 'set' then
    v_new_value := v_value;
  else
    v_new_value := v_previous_value + v_value;
  end if;

  if v_new_value < 0 or v_new_value > coalesce(v_attribute_def.max_value, 0) then
    return jsonb_build_object(
      'ok', false,
      'error', 'ATTRIBUTE_VALUE_OUT_OF_RANGE',
      'message', 'Attribute value is outside the allowed range.',
      'details', jsonb_build_object(
        'attribute_code', v_attribute_def.code,
        'minimum', 0,
        'maximum', v_attribute_def.max_value,
        'attempted', v_new_value
      )
    );
  end if;

  update public.odyssey_character_attributes
  set
    value = v_new_value,
    updated_at = timezone('utc', now())
  where id = v_attribute_row.id;

  if v_attribute_def.code = 'endurance' then
    perform public.odyssey_recalculate_character_body_part_caps(v_character_id);
  end if;

  perform public.odyssey_sync_character_resource_pools(v_character_id);
  v_refresh_result := public.odyssey_refresh_character_combat_state(v_character_id);
  v_state_version := coalesce(nullif(v_refresh_result->>'state_version', '')::integer, 0);

  return jsonb_build_object(
    'ok', true,
    'action', 'gm_update_character_attribute',
    'character_id', v_character_id,
    'actor', v_actor,
    'reason', v_reason,
    'attribute',
      jsonb_build_object(
        'code', v_attribute_def.code,
        'name', v_attribute_def.name,
        'value', v_new_value,
        'max_value', coalesce(v_attribute_def.max_value, 0),
        'operation', v_operation,
        'previous_value', v_previous_value
      ),
    'state_version', v_state_version
  );
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_ability_id');
  v_ability_code text := lower(trim(coalesce(p_payload->>'ability_code', '')));
  v_target_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_body_part_id');
  v_result jsonb := '{}'::jsonb;
begin
  if v_character_ability_id is not null or v_ability_code <> '' then
    return public.odyssey_perform_ability_attack(p_payload);
  end if;

  v_result := public.odyssey_perform_weapon_attack(p_payload);

  if coalesce((v_result->>'ok')::boolean, false) = true then
    return public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
  end if;

  return v_result;
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

  if position($needle$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find attacker uuid declaration in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;$old$,
    $new$v_attacker_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'attacker_character_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;$old$,
    $new$v_target_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_character_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_weapon_id uuid := nullif(trim(coalesce(p_payload->>'weapon_id', '')), '')::uuid;$old$,
    $new$v_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'weapon_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;$old$,
    $new$v_target_body_part_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_body_part_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_defense_skill_id uuid := nullif(trim(coalesce(p_payload->>'defense_skill_id', '')), '')::uuid;$old$,
    $new$v_defense_skill_id uuid := public.odyssey_try_parse_uuid(p_payload->>'defense_skill_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;$old$,
    $new$v_encounter_id uuid := public.odyssey_try_parse_uuid(p_payload->>'encounter_id');$new$
  );

  if position($needle$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
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
    end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find body part lookup in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
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
    end if;$old$,
    $new$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name,
      coalesce(d.can_be_targeted, true) as can_be_targeted,
      coalesce(d.aim_difficulty, 0) as aim_difficulty
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.id = v_target_body_part_id;

    if not found then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part was not found.';
    elsif v_target_part.character_id is distinct from v_target_character_id then
      v_error_code := 'BODY_PART_CHARACTER_MISMATCH';
      v_error_message := 'Target body part does not belong to the target character.';
    elsif not coalesce(v_target_part.can_be_targeted, true) then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part cannot be targeted.';
    end if;$new$
  );

  if position($needle$v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
  v_new_armor_max_critical := coalesce(v_target_part.armor_max_critical, 0);
  v_new_armor_value := coalesce(v_target_part.armor_value, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);
  v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);$needle$ in v_function_def) = 0 then
    raise exception 'Could not find body part state initialization in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
  v_new_armor_max_critical := coalesce(v_target_part.armor_max_critical, 0);
  v_new_armor_value := coalesce(v_target_part.armor_value, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);
  v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);$old$,
    $new$if v_error_code is null then
    v_new_minor := coalesce(v_target_part.minor, 0);
    v_new_serious := coalesce(v_target_part.serious, 0);
    v_new_critical := coalesce(v_target_part.critical, 0);
    v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
    v_new_armor_max_critical := coalesce(v_target_part.armor_max_critical, 0);
    v_new_armor_value := coalesce(v_target_part.armor_value, 0);
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);
    v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);
  end if;$new$
  );

  if position($needle$v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);$needle$ in v_function_def) = 0 then
    raise exception 'Could not find armor calculation in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);$old$,
    $new$v_effective_armor := case
      when v_attack_type = 'ranged' then greatest(v_raw_armor_value - v_armor_pierce, 0)
      else v_raw_armor_value
    end;$new$
  );

  if position($needle$if v_error_code is null and v_hit and not v_skip_damage then
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
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);
      v_armor_items_changed := v_armor_critical_delta > 0;

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
      or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;

      v_body_changed := true;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage application block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$if v_error_code is null and v_hit and not v_skip_damage then
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
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);
      v_armor_items_changed := v_armor_critical_delta > 0;

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
      or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;

      v_body_changed := true;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$old$,
    $new$if v_error_code is null and v_hit and not v_skip_damage then
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

    if v_attack_roll >= 95 then
      v_minor_delta := 0;
      v_serious_delta := 0;
      v_critical_delta := greatest(v_critical_delta, 2);
      v_damage_level := 'critical';
    end if;

    if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
        v_body_changed := true;
        v_armor_items_changed := false;
      end if;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$new$
  );

  if position($needle$'damage',
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
      ),$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage response block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$'damage',
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
      ),$old$,
    $new$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used', case when v_attack_type = 'ranged' then v_armor_pierce else 0 end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates,
        'melee_strength_bonus', v_melee_strength_bonus
      ),$new$
  );

  execute v_function_def;
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
    and p.proname = 'odyssey_perform_ability_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_ability_attack(jsonb) was not found.';
  end if;

  if position($needle$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;$needle$ in v_function_def) = 0
     and position($needle$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', p_payload->>'character_id', '')), '')::uuid;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find attacker uuid declaration in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;$old$,
    $new$v_attacker_character_id uuid := public.odyssey_try_parse_uuid(coalesce(p_payload->>'attacker_character_id', p_payload->>'character_id'));$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', p_payload->>'character_id', '')), '')::uuid;$old$,
    $new$v_attacker_character_id uuid := public.odyssey_try_parse_uuid(coalesce(p_payload->>'attacker_character_id', p_payload->>'character_id'));$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;$old$,
    $new$v_target_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_character_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_character_ability_id uuid := nullif(trim(coalesce(p_payload->>'character_ability_id', '')), '')::uuid;$old$,
    $new$v_character_ability_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_ability_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;$old$,
    $new$v_target_body_part_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_body_part_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_defense_skill_id uuid := nullif(trim(coalesce(p_payload->>'defense_skill_id', '')), '')::uuid;$old$,
    $new$v_defense_skill_id uuid := public.odyssey_try_parse_uuid(p_payload->>'defense_skill_id');$new$
  );
  v_function_def := replace(
    v_function_def,
    $old$v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;$old$,
    $new$v_encounter_id uuid := public.odyssey_try_parse_uuid(p_payload->>'encounter_id');$new$
  );

  if position($needle$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
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
    end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find body part lookup in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
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
    end if;$old$,
    $new$select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name,
      coalesce(d.can_be_targeted, true) as can_be_targeted,
      coalesce(d.aim_difficulty, 0) as aim_difficulty
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.id = v_target_body_part_id;

    if not found then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part was not found.';
    elsif v_target_part.character_id is distinct from v_target_character_id then
      v_error_code := 'BODY_PART_CHARACTER_MISMATCH';
      v_error_message := 'Target body part does not belong to the target character.';
    elsif not coalesce(v_target_part.can_be_targeted, true) then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part cannot be targeted.';
    end if;$new$
  );

  if position($needle$v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);$needle$ in v_function_def) = 0 then
    raise exception 'Could not find body part state initialization in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);$old$,
    $new$if v_error_code is null then
    v_new_minor := coalesce(v_target_part.minor, 0);
    v_new_serious := coalesce(v_target_part.serious, 0);
    v_new_critical := coalesce(v_target_part.critical, 0);
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);
  end if;$new$
  );

  if position($needle$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find armor calculation in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    end if;$old$,
    $new$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    elsif coalesce(v_ability.attack_type, '') = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;$new$
  );

  if position($needle$if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_attacker_damage_modifier;
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

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0 or v_serious_delta > 0 or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage application block in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_attacker_damage_modifier;
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

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0 or v_serious_delta > 0 or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$old$,
    $new$if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_attacker_damage_modifier;
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

    if v_attack_roll >= 95 then
      v_minor_delta := 0;
      v_serious_delta := 0;
      v_critical_delta := greatest(v_critical_delta, 2);
      v_damage_level := 'critical';
    end if;

    if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
      end if;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;$new$
  );

  if position($needle$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'body_critical_delta', v_body_critical_delta
      ),$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage response block in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'body_critical_delta', v_body_critical_delta
      ),$old$,
    $new$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates
      ),$new$
  );

  execute v_function_def;
end;
$$;

grant execute on function public.odyssey_try_parse_uuid(text) to anon, authenticated;
grant execute on function public.odyssey_apply_equipment_critical_damage(uuid, integer) to anon, authenticated;
grant execute on function public.odyssey_apply_resolved_body_damage(uuid, integer, integer, integer) to anon, authenticated;

-- Regression checklist for manual SQL verification:
-- 1. Head minor/serious stay in their own tier until universal normalization thresholds are reached.
-- 2. Numeric armor participates in damage_defense_total for melee and ranged, with signed armor pierce only affecting ranged.
-- 3. Armor critical integrity is absorbed only by equipped armor items, never twice through body-part snapshot fields.
-- 4. Inventory/armory reads do not initialize runtime state and remain read-only.
-- 5. Invalid attack or magazine payload IDs return JSON errors instead of raw SQL exceptions.
