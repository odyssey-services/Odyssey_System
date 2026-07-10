-- ===== BEGIN 115_perform_attack_feed_mode_profile_hotfix.sql =====
-- Some databases ended up with a partially upgraded
-- public.odyssey_perform_weapon_attack(jsonb): the function reads
-- v_weapon_profile.feed_mode even when the transient record does not expose that
-- field yet. That breaks all attacks, including melee/unarmed.
--
-- This hotfix stops relying on the record shape and resolves feed mode +
-- internal-ammo state directly from the canonical profile/profile_state rows.

do $do$
declare
  v_function_def text := null;
  v_old_block text := $old$
    v_profile_feed_mode := coalesce(v_weapon_profile.feed_mode, 'detachable_magazine');
    v_internal_ammo_type_id := v_weapon_profile.internal_ammo_type_id;
    v_internal_current_rounds := greatest(coalesce(v_weapon_profile.internal_current_rounds, 0), 0);
    v_internal_max_rounds := greatest(coalesce(v_weapon_profile.internal_max_rounds, v_weapon_profile.internal_capacity, 0), 0);
$old$;
  v_new_block text := $new$
    select
      coalesce(profile.feed_mode, 'detachable_magazine'),
      state.internal_ammo_type_id,
      greatest(coalesce(state.internal_current_rounds, 0), 0),
      greatest(coalesce(state.internal_max_rounds, profile.internal_capacity, 0), 0)
    into
      v_profile_feed_mode,
      v_internal_ammo_type_id,
      v_internal_current_rounds,
      v_internal_max_rounds
    from public.odyssey_weapon_model_profiles profile
    left join public.odyssey_character_weapon_profile_states state
      on state.id = v_weapon_profile.profile_state_id
    where profile.id = v_weapon_profile.profile_id;

    if not found then
      v_profile_feed_mode := 'detachable_magazine';
      v_internal_ammo_type_id := null;
      v_internal_current_rounds := 0;
      v_internal_max_rounds := 0;
    end if;
$new$;
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

  if position(v_old_block in v_function_def) = 0 then
    return;
  end if;

  v_function_def := replace(v_function_def, v_old_block, v_new_block);
  execute v_function_def;
end;
$do$;

-- ===== END 115_perform_attack_feed_mode_profile_hotfix.sql =====
