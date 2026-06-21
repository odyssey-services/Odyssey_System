create or replace function public.creator_delete_weapon(
  p_weapon_model_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_weapon_model_defs%rowtype;
  v_character_weapon_count integer := 0;
  v_details jsonb := '[]'::jsonb;
begin
  select *
  into v_weapon
  from public.odyssey_weapon_model_defs weapon
  where weapon.id = p_weapon_model_id;

  if not found then
    return public.odyssey_creator_error(
      'WEAPON_NOT_FOUND',
      'Weapon model was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown weapon model id.'))
    );
  end if;

  select count(*)::integer
  into v_character_weapon_count
  from public.odyssey_character_weapons weapon
  where weapon.weapon_model_id = p_weapon_model_id;

  if v_character_weapon_count > 0 then
    v_details := jsonb_build_array(
      jsonb_build_object(
        'field', 'character_weapons',
        'count', v_character_weapon_count,
        'message', 'Weapon model is assigned to one or more character weapons.'
      )
    );
    return public.odyssey_creator_error(
      'WEAPON_MODEL_IN_USE',
      'Weapon model is still referenced and cannot be deleted.',
      v_details
    );
  end if;

  delete from public.odyssey_weapon_model_defs weapon
  where weapon.id = p_weapon_model_id;

  return jsonb_build_object(
    'ok', true,
    'deleted_id', p_weapon_model_id,
    'deleted_code', v_weapon.code
  );
end;
$$;

grant execute on function public.creator_delete_weapon(uuid) to anon, authenticated;
