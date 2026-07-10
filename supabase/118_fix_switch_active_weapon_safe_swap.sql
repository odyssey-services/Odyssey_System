create or replace function public.switch_active_weapon(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
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
      'armory', public.get_character_armory_context(v_character_id, v_encounter_id)
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

  update public.odyssey_character_weapons
  set
    equipped_slot = null,
    updated_at = timezone('utc', now())
  where character_id = v_character_id
    and equipped_slot in ('primary', 'secondary');

  update public.odyssey_character_weapons
  set
    equipped_slot = 'primary',
    updated_at = timezone('utc', now())
  where id = v_character_weapon_id
    and character_id = v_character_id;

  if v_current_active_weapon_id is not null
     and v_current_active_weapon_id <> v_character_weapon_id then
    update public.odyssey_character_weapons
    set
      equipped_slot = 'secondary',
      updated_at = timezone('utc', now())
    where id = v_current_active_weapon_id
      and character_id = v_character_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_character_weapon_id,
    'active_weapon_id', v_character_weapon_id,
    'cost_mode', v_cost_result->>'cost_mode',
    'combat_session', v_cost_result->'combat_session',
    'armory', public.get_character_armory_context(v_character_id, v_encounter_id)
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_SLOT_CONFLICT',
      'message', 'Weapon slot conflict detected while switching the active weapon.'
    );
end;
$$;
