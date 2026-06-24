create or replace function public.odyssey_sync_character_weapon_profile_cache(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_default_profile_id uuid := null;
  v_active_state public.odyssey_character_weapon_profile_states%rowtype;
  v_resolved_fire_mode_id uuid := null;
  v_resolved_magazine_id uuid := null;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'weapon_id', p_character_weapon_id
    );
  end if;

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(v_weapon.weapon_model_id);

  if v_weapon.active_profile_id is null then
    update public.odyssey_character_weapons
    set active_profile_id = v_default_profile_id
    where id = v_weapon.id;

    v_weapon.active_profile_id := v_default_profile_id;
  end if;

  select *
  into v_active_state
  from public.odyssey_character_weapon_profile_states s
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = coalesce(v_weapon.active_profile_id, v_default_profile_id)
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_STATE_NOT_FOUND',
      'weapon_id', p_character_weapon_id,
      'profile_id', coalesce(v_weapon.active_profile_id, v_default_profile_id)
    );
  end if;

  update public.odyssey_character_weapon_profile_states
  set is_active = (id = v_active_state.id)
  where character_weapon_id = v_weapon.id
    and is_active is distinct from (id = v_active_state.id);

  if v_active_state.selected_fire_mode_id is not null
     and public.odyssey_is_fire_mode_allowed_for_profile(v_active_state.profile_id, v_active_state.selected_fire_mode_id) then
    v_resolved_fire_mode_id := v_active_state.selected_fire_mode_id;
  else
    v_resolved_fire_mode_id := public.odyssey_get_default_profile_fire_mode_id(v_active_state.profile_id);

    update public.odyssey_character_weapon_profile_states
    set selected_fire_mode_id = v_resolved_fire_mode_id
    where id = v_active_state.id
      and selected_fire_mode_id is distinct from v_resolved_fire_mode_id;
  end if;

  if v_active_state.loaded_magazine_id is not null
     and public.odyssey_is_magazine_compatible_with_profile(v_active_state.profile_id, v_active_state.loaded_magazine_id) then
    v_resolved_magazine_id := v_active_state.loaded_magazine_id;
  else
    v_resolved_magazine_id := null;

    update public.odyssey_character_weapon_profile_states
    set loaded_magazine_id = null
    where id = v_active_state.id
      and loaded_magazine_id is not null;
  end if;

  update public.odyssey_character_weapons
  set
    active_profile_id = v_active_state.profile_id,
    loaded_magazine_id = v_resolved_magazine_id,
    selected_fire_mode_id = v_resolved_fire_mode_id
  where id = v_weapon.id
    and (
      active_profile_id is distinct from v_active_state.profile_id
      or loaded_magazine_id is distinct from v_resolved_magazine_id
      or selected_fire_mode_id is distinct from v_resolved_fire_mode_id
    );

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'active_profile_id', v_active_state.profile_id,
    'loaded_magazine_id', v_resolved_magazine_id,
    'selected_fire_mode_id', v_resolved_fire_mode_id
  );
end;
$$;

create or replace function public.initialize_character_weapon_profile_states(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_default_profile_id uuid := null;
  v_active_profile_id uuid := null;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'weapon_id', p_character_weapon_id
    );
  end if;

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(v_weapon.weapon_model_id);
  v_active_profile_id := coalesce(v_weapon.active_profile_id, v_default_profile_id);

  if not exists(
    select 1
    from public.odyssey_weapon_model_profiles p
    where p.id = v_active_profile_id
      and p.weapon_model_id = v_weapon.weapon_model_id
  ) then
    v_active_profile_id := v_default_profile_id;
  end if;

  insert into public.odyssey_character_weapon_profile_states (
    character_weapon_id,
    profile_id,
    loaded_magazine_id,
    selected_fire_mode_id,
    is_active,
    data
  )
  select
    v_weapon.id,
    p.id,
    case
      when p.id = v_active_profile_id then v_weapon.loaded_magazine_id
      else null
    end,
    case
      when p.id = v_active_profile_id
           and v_weapon.selected_fire_mode_id is not null
           and public.odyssey_is_fire_mode_allowed_for_profile(p.id, v_weapon.selected_fire_mode_id)
        then v_weapon.selected_fire_mode_id
      else public.odyssey_get_default_profile_fire_mode_id(p.id)
    end,
    p.id = v_active_profile_id,
    '{}'::jsonb
  from public.odyssey_weapon_model_profiles p
  where p.weapon_model_id = v_weapon.weapon_model_id
  on conflict (character_weapon_id, profile_id) do nothing;

  update public.odyssey_character_weapon_profile_states
  set is_active = (profile_id = v_active_profile_id)
  where character_weapon_id = v_weapon.id
    and is_active is distinct from (profile_id = v_active_profile_id);

  update public.odyssey_character_weapons
  set active_profile_id = v_active_profile_id
  where id = v_weapon.id
    and active_profile_id is distinct from v_active_profile_id;

  return public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);
end;
$$;

create or replace function public.get_character_armory(
  p_character_id uuid
)
returns jsonb
language plpgsql
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
          'data', coalesce(w.data, '{}'::jsonb),
          'equipped_slot', w.equipped_slot,
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
          'compatible_magazines', coalesce(runtime.active_profile_json->'compatible_magazines', '[]'::jsonb),
          'lock_state', public.odyssey_get_weapon_lock_state(w.character_id, w.id)
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
