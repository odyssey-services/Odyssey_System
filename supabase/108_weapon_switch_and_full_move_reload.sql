-- ===== BEGIN 108_weapon_switch_and_full_move_reload.sql =====
--
-- Server-authoritative weapon switching + full-move reload economy.
-- Scope:
--   - active weapon switch is an RPC, not a local HUD illusion;
--   - detachable and internal reload/unload share the same
--     full_move/free cost model;
--   - armory exposes active weapon + operation-cost metadata;
--   - the first weapon created for a character becomes primary.

create or replace function public.odyssey_get_weapon_operation_cost_mode(
  p_character_id uuid,
  p_operation text,
  p_feed_mode text default null
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_summary jsonb := '{}'::jsonb;
  v_flags jsonb := '{}'::jsonb;
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_feed_mode text := lower(trim(coalesce(p_feed_mode, '')));
begin
  if p_character_id is not null then
    v_summary := coalesce(public.get_character_effect_summary(p_character_id), '{}'::jsonb);
    v_flags := coalesce(v_summary->'flags', '{}'::jsonb);
  end if;

  if v_operation in ('switch', 'switch_weapon', 'weapon_switch') then
    if coalesce((v_flags->>'free_weapon_switch')::boolean, false) then
      return 'free';
    end if;
    return 'full_move';
  end if;

  if v_operation in ('reload', 'weapon_reload', 'reload_weapon') then
    if v_feed_mode = 'internal_magazine'
       and coalesce((v_flags->>'free_internal_reload')::boolean, false) then
      return 'free';
    end if;
    if coalesce((v_flags->>'free_weapon_reload')::boolean, false) then
      return 'free';
    end if;
    return 'full_move';
  end if;

  return 'full_move';
end;
$$;

create or replace function public.odyssey_apply_weapon_operation_session_cost(
  p_character_id uuid,
  p_operation text,
  p_feed_mode text default null,
  p_expected_session_version integer default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_participation jsonb := public.odyssey_get_active_participation(p_character_id);
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
      'armory', public.get_character_armory(v_character_id)
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
    'armory', public.get_character_armory(v_character_id)
  );
end;
$$;

with ranked_weapons as (
  select
    weapon.id,
    weapon.character_id,
    row_number() over (
      partition by weapon.character_id
      order by weapon.sort_order, weapon.created_at, weapon.id
    ) as rn,
    max(case when weapon.equipped_slot = 'primary' then 1 else 0 end) over (
      partition by weapon.character_id
    ) as has_primary
  from public.odyssey_character_weapons weapon
)
update public.odyssey_character_weapons weapon
set
  equipped_slot = 'primary',
  updated_at = timezone('utc', now())
from ranked_weapons ranked
where weapon.id = ranked.id
  and ranked.has_primary = 0
  and ranked.rn = 1;

create or replace function public.create_character_weapon(
  p_character_id uuid,
  p_weapon_model_id uuid,
  p_custom_name text default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_exists boolean := false;
  v_default_profile_id uuid := null;
  v_sort_order integer := 0;
  v_weapon_id uuid;
  v_has_primary boolean := false;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  into v_character_exists;

  if not v_character_exists then
    raise exception 'Character % was not found', p_character_id;
  end if;

  if not exists(
    select 1
    from public.odyssey_weapon_model_defs wm
    where wm.id = p_weapon_model_id
  ) then
    raise exception 'Weapon model % was not found', p_weapon_model_id;
  end if;

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(p_weapon_model_id);

  select coalesce(max(w.sort_order), 0) + 10
  into v_sort_order
  from public.odyssey_character_weapons w
  where w.character_id = p_character_id;

  select exists(
    select 1
    from public.odyssey_character_weapons w
    where w.character_id = p_character_id
      and w.equipped_slot = 'primary'
  )
  into v_has_primary;

  insert into public.odyssey_character_weapons (
    character_id,
    weapon_model_id,
    custom_name,
    active_profile_id,
    loaded_magazine_id,
    selected_fire_mode_id,
    notes,
    sort_order,
    equipped_slot
  )
  values (
    p_character_id,
    p_weapon_model_id,
    nullif(trim(p_custom_name), ''),
    v_default_profile_id,
    null,
    null,
    '',
    v_sort_order,
    case when v_has_primary then null else 'primary' end
  )
  returning id into v_weapon_id;

  perform public.initialize_character_weapon_profile_states(v_weapon_id);
  perform public.initialize_character_weapon_feature_states(v_weapon_id);

  return jsonb_build_object(
    'weapon_id', v_weapon_id,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.load_weapon_profile_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_profile_id uuid := public.odyssey_try_parse_uuid(p_payload->>'profile_id');
  v_character_magazine_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_magazine_id');
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_target_state_id uuid := null;
  v_target_feed_mode text := 'detachable_magazine';
  v_affected_weapons uuid[];
  v_item uuid;
  v_magazine public.odyssey_character_magazines%rowtype;
  v_cost_result jsonb := '{}'::jsonb;
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

  select
    s.id,
    coalesce(p.feed_mode, 'detachable_magazine')
  into
    v_target_state_id,
    v_target_feed_mode
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

  if v_target_feed_mode <> 'detachable_magazine' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEED_MODE_INVALID',
      'message', 'This weapon profile uses an internal magazine and cannot load detachable magazines.'
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

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_weapon.character_id,
    'reload',
    v_target_feed_mode,
    v_expected_session_version
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
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
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.unload_weapon_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_profile_id uuid := public.odyssey_try_parse_uuid(p_payload->>'profile_id');
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_target_state_id uuid := null;
  v_target_feed_mode text := 'detachable_magazine';
  v_loaded_magazine_id uuid := null;
  v_cost_result jsonb := '{}'::jsonb;
begin
  if v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_WEAPON_ID_REQUIRED',
      'message', 'character_weapon_id is required.'
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

  if v_profile_id is null then
    v_profile_id := v_weapon.active_profile_id;
  end if;

  select
    s.id,
    coalesce(p.feed_mode, 'detachable_magazine'),
    s.loaded_magazine_id
  into
    v_target_state_id,
    v_target_feed_mode,
    v_loaded_magazine_id
  from public.odyssey_character_weapon_profile_states s
  join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = v_profile_id
  limit 1;

  if v_target_state_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_NOT_FOUND',
      'message', 'Selected profile was not found for this weapon.'
    );
  end if;

  if v_target_feed_mode <> 'detachable_magazine' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEED_MODE_INVALID',
      'message', 'This weapon profile uses an internal magazine and has no detachable magazine to unload.'
    );
  end if;

  if v_loaded_magazine_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_MAGAZINE',
      'message', 'No magazine is currently loaded.'
    );
  end if;

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_weapon.character_id,
    'reload',
    v_target_feed_mode,
    v_expected_session_version
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
  end if;

  update public.odyssey_character_weapon_profile_states
  set loaded_magazine_id = null
  where id = v_target_state_id;

  perform public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'profile_id', v_profile_id,
    'character_magazine_id', v_loaded_magazine_id,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.load_weapon_internal_rounds(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_profile_id uuid := public.odyssey_try_parse_uuid(p_payload->>'profile_id');
  v_ammo_stock_id uuid := public.odyssey_try_parse_uuid(p_payload->>'ammo_stock_id');
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_quantity integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, 0), 0);
  v_allow_partial boolean := coalesce(nullif(trim(coalesce(p_payload->>'allow_partial', '')), '')::boolean, false);
  v_weapon public.odyssey_character_weapons%rowtype;
  v_state record;
  v_stock record;
  v_capacity integer := 0;
  v_missing_rounds integer := 0;
  v_available_rounds integer := 0;
  v_requested_quantity integer := 0;
  v_loaded_quantity integer := 0;
  v_rounds_after integer := 0;
  v_stock_quantity_after integer := 0;
  v_cost_result jsonb := '{}'::jsonb;
begin
  if v_character_weapon_id is null or v_profile_id is null or v_ammo_stock_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_weapon_id, profile_id and ammo_stock_id are required.'
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

  select
    s.id,
    s.character_weapon_id,
    s.profile_id,
    s.internal_ammo_type_id,
    greatest(coalesce(s.internal_current_rounds, 0), 0) as internal_current_rounds,
    greatest(coalesce(s.internal_max_rounds, p.internal_capacity, 0), 0) as internal_max_rounds,
    coalesce(p.feed_mode, 'detachable_magazine') as feed_mode,
    coalesce(p.caliber_id, wm.caliber_id) as caliber_id
  into v_state
  from public.odyssey_character_weapon_profile_states s
  join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
  join public.odyssey_weapon_model_defs wm on wm.id = p.weapon_model_id
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = v_profile_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_NOT_FOUND',
      'message', 'Selected profile was not found for this weapon.'
    );
  end if;

  if v_state.feed_mode <> 'internal_magazine' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEED_MODE_INVALID',
      'message', 'This weapon profile uses detachable magazines.'
    );
  end if;

  select
    s.id,
    s.character_id,
    s.display_name,
    s.caliber_id,
    s.ammo_type_id,
    s.quantity,
    ammo.code as ammo_type_code,
    ammo.name as ammo_type_name,
    ammo.caliber_id as ammo_caliber_id
  into v_stock
  from public.odyssey_character_ammo_stock s
  join public.odyssey_ammo_type_defs ammo on ammo.id = s.ammo_type_id
  where s.id = v_ammo_stock_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_STOCK_NOT_FOUND',
      'message', 'Ammo stock was not found.'
    );
  end if;

  if v_stock.character_id <> v_weapon.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_MISMATCH',
      'message', 'Ammo stock does not belong to the weapon owner.'
    );
  end if;

  if v_state.caliber_id is null or v_stock.ammo_caliber_id is null or v_state.caliber_id <> v_stock.ammo_caliber_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'message', 'Ammo caliber does not match the weapon profile caliber.'
    );
  end if;

  if v_state.internal_current_rounds > 0
     and v_state.internal_ammo_type_id is not null
     and v_state.internal_ammo_type_id <> v_stock.ammo_type_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_HAS_DIFFERENT_AMMO_TYPE',
      'message', 'The internal magazine already contains a different ammo type.'
    );
  end if;

  v_capacity := greatest(coalesce(v_state.internal_max_rounds, 0), 0);
  v_missing_rounds := greatest(v_capacity - v_state.internal_current_rounds, 0);
  if v_missing_rounds <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INTERNAL_MAGAZINE_FULL',
      'message', 'The internal magazine is already full.'
    );
  end if;

  v_available_rounds := greatest(coalesce(v_stock.quantity, 0), 0);
  if v_quantity <= 0 then
    v_requested_quantity := v_missing_rounds;
  else
    v_requested_quantity := least(v_quantity, v_missing_rounds);
  end if;

  if v_requested_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Requested quantity must resolve to at least one round.'
    );
  end if;

  if v_available_rounds <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'requested_quantity', v_requested_quantity,
      'available_quantity', v_available_rounds
    );
  end if;

  if not v_allow_partial and v_available_rounds < v_requested_quantity then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'requested_quantity', v_requested_quantity,
      'available_quantity', v_available_rounds
    );
  end if;

  v_loaded_quantity := least(v_requested_quantity, v_available_rounds);
  if v_loaded_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'requested_quantity', v_requested_quantity,
      'available_quantity', v_available_rounds
    );
  end if;

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_weapon.character_id,
    'reload',
    v_state.feed_mode,
    v_expected_session_version
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
  end if;

  v_rounds_after := v_state.internal_current_rounds + v_loaded_quantity;
  v_stock_quantity_after := greatest(v_available_rounds - v_loaded_quantity, 0);

  if v_stock_quantity_after <= 0 then
    delete from public.odyssey_character_ammo_stock
    where id = v_stock.id;
  else
    update public.odyssey_character_ammo_stock
    set quantity = v_stock_quantity_after
    where id = v_stock.id;
  end if;

  update public.odyssey_character_weapon_profile_states
  set
    internal_ammo_type_id = case
      when internal_current_rounds <= 0 then v_stock.ammo_type_id
      else internal_ammo_type_id
    end,
    internal_current_rounds = v_rounds_after,
    internal_max_rounds = v_capacity
  where id = v_state.id;

  perform public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'profile_id', v_profile_id,
    'loaded_quantity', v_loaded_quantity,
    'requested_quantity', v_requested_quantity,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.unload_weapon_internal_rounds(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_weapon_id');
  v_profile_id uuid := public.odyssey_try_parse_uuid(p_payload->>'profile_id');
  v_expected_session_version integer := nullif(trim(coalesce(p_payload->>'expected_encounter_version', '')), '')::integer;
  v_quantity integer := coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, 0);
  v_weapon public.odyssey_character_weapons%rowtype;
  v_state record;
  v_unload_quantity integer := 0;
  v_rounds_after integer := 0;
  v_stock record;
  v_stock_id uuid := null;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
  v_cost_result jsonb := '{}'::jsonb;
begin
  if v_character_weapon_id is null or v_profile_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_weapon_id and profile_id are required.'
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

  select
    s.id,
    s.character_weapon_id,
    s.profile_id,
    s.internal_ammo_type_id,
    greatest(coalesce(s.internal_current_rounds, 0), 0) as internal_current_rounds,
    greatest(coalesce(s.internal_max_rounds, p.internal_capacity, 0), 0) as internal_max_rounds,
    coalesce(p.feed_mode, 'detachable_magazine') as feed_mode,
    coalesce(p.caliber_id, wm.caliber_id) as caliber_id
  into v_state
  from public.odyssey_character_weapon_profile_states s
  join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
  join public.odyssey_weapon_model_defs wm on wm.id = p.weapon_model_id
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = v_profile_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_NOT_FOUND',
      'message', 'Selected profile was not found for this weapon.'
    );
  end if;

  if v_state.feed_mode <> 'internal_magazine' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEED_MODE_INVALID',
      'message', 'This weapon profile uses detachable magazines.'
    );
  end if;

  if v_state.internal_current_rounds <= 0 or v_state.internal_ammo_type_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_AMMO',
      'message', 'The internal magazine is empty.'
    );
  end if;

  if v_quantity <= 0 then
    v_unload_quantity := v_state.internal_current_rounds;
  else
    v_unload_quantity := least(v_quantity, v_state.internal_current_rounds);
  end if;

  if v_unload_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Requested quantity must resolve to at least one round.'
    );
  end if;

  v_cost_result := public.odyssey_apply_weapon_operation_session_cost(
    v_weapon.character_id,
    'reload',
    v_state.feed_mode,
    v_expected_session_version
  );
  if coalesce((v_cost_result->>'ok')::boolean, false) = false then
    return v_cost_result;
  end if;

  select *
  into v_stock
  from public.odyssey_character_ammo_stock s
  where s.character_id = v_weapon.character_id
    and s.caliber_id = v_state.caliber_id
    and s.ammo_type_id = v_state.internal_ammo_type_id
  order by s.created_at, s.id
  limit 1
  for update;

  if found then
    v_stock_id := v_stock.id;
    v_stock_quantity_before := coalesce(v_stock.quantity, 0);
    v_stock_quantity_after := v_stock_quantity_before + v_unload_quantity;

    update public.odyssey_character_ammo_stock
    set quantity = v_stock_quantity_after
    where id = v_stock_id;
  else
    insert into public.odyssey_character_ammo_stock (
      character_id,
      display_name,
      caliber_id,
      ammo_type_id,
      quantity
    )
    select
      v_weapon.character_id,
      coalesce(ammo.name, ammo.code),
      v_state.caliber_id,
      v_state.internal_ammo_type_id,
      v_unload_quantity
    from public.odyssey_ammo_type_defs ammo
    where ammo.id = v_state.internal_ammo_type_id
    returning id into v_stock_id;

    v_stock_quantity_before := 0;
    v_stock_quantity_after := v_unload_quantity;
  end if;

  v_rounds_after := greatest(v_state.internal_current_rounds - v_unload_quantity, 0);

  update public.odyssey_character_weapon_profile_states
  set
    internal_current_rounds = v_rounds_after,
    internal_ammo_type_id = case
      when v_rounds_after <= 0 then null
      else internal_ammo_type_id
    end,
    internal_max_rounds = greatest(coalesce(internal_max_rounds, 0), 0)
  where id = v_state.id;

  perform public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'profile_id', v_profile_id,
    'unloaded_quantity', v_unload_quantity,
    'ammo_stock_id', v_stock_id,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
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
begin
  perform public.initialize_character_weapon_abilities(weapon.id)
  from public.odyssey_character_weapons weapon
  where weapon.character_id = p_character_id;

  select
    true,
    e.active_character_id is not distinct from p_character_id,
    coalesce(i.move_current, 0),
    coalesce(i.move_max, 0)
  into
    v_has_active_session,
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
    'magazines', coalesce(v_magazines, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.switch_active_weapon(jsonb) to anon, authenticated;
grant execute on function public.load_weapon_profile_magazine(jsonb) to anon, authenticated;
grant execute on function public.unload_weapon_magazine(jsonb) to anon, authenticated;
grant execute on function public.load_weapon_internal_rounds(jsonb) to anon, authenticated;
grant execute on function public.unload_weapon_internal_rounds(jsonb) to anon, authenticated;

-- ===== END 108_weapon_switch_and_full_move_reload.sql =====
