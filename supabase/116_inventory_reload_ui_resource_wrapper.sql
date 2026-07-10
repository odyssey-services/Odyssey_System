create or replace function public.reload_inventory_resource(
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_kind text := lower(trim(coalesce(v_payload->>'kind', '')));
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_quantity_text text := nullif(trim(coalesce(v_payload->>'quantity', '')), '');
  v_state_id uuid := public.odyssey_try_parse_uuid(
    coalesce(
      nullif(trim(coalesce(v_payload->>'state_id', '')), ''),
      nullif(trim(coalesce(v_payload->>'feature_state_id', '')), ''),
      nullif(trim(coalesce(v_payload->>'feature_instance_id', '')), '')
    )
  );
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(
    coalesce(
      nullif(trim(coalesce(v_payload->>'character_ability_id', '')), ''),
      nullif(trim(coalesce(v_payload->>'feature_instance_id', '')), '')
    )
  );
  v_quantity integer := 1;
  v_result jsonb := '{}'::jsonb;
  v_item_code text := null;
  v_item_name text := null;
begin
  if v_quantity_text is not null then
    if v_quantity_text !~ '^[0-9]+$' then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_RELOAD_QUANTITY',
        'message', 'quantity must be a positive integer.'
      );
    end if;
    v_quantity := greatest(v_quantity_text::integer, 1);
  end if;

  if v_kind not in ('weapon_feature', 'character_ability') then
    return jsonb_build_object(
      'ok', false,
      'error', 'UNSUPPORTED_RELOAD_KIND',
      'message', 'kind must be weapon_feature or character_ability.',
      'kind', v_kind
    );
  end if;

  if v_kind = 'weapon_feature' then
    if v_state_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_STATE_ID_REQUIRED',
        'message', 'state_id is required for weapon_feature reload.',
        'kind', v_kind
      );
    end if;

    if v_character_id is not null and not exists (
      select 1
      from public.odyssey_character_weapon_feature_states state_row
      join public.odyssey_character_weapons weapon on weapon.id = state_row.character_weapon_id
      where state_row.id = v_state_id
        and weapon.character_id = v_character_id
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_NOT_OWNED',
        'message', 'Feature does not belong to the specified character.',
        'kind', v_kind,
        'state_id', v_state_id
      );
    end if;

    v_result := public.reload_feature_resource(
      jsonb_build_object(
        'feature_instance_type', 'weapon_feature',
        'feature_instance_id', v_state_id::text,
        'quantity', v_quantity
      )
    );

    v_item_code := nullif(trim(coalesce(v_result#>>'{resource,item_code}', '')), '');
  else
    if v_character_ability_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'CHARACTER_ABILITY_ID_REQUIRED',
        'message', 'character_ability_id is required for character_ability reload.',
        'kind', v_kind
      );
    end if;

    if v_character_id is not null and not exists (
      select 1
      from public.odyssey_character_abilities ability
      where ability.id = v_character_ability_id
        and ability.character_id = v_character_id
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_OWNED',
        'message', 'Ability does not belong to the specified character.',
        'kind', v_kind,
        'character_ability_id', v_character_ability_id
      );
    end if;

    v_result := public.reload_character_ability(
      jsonb_build_object(
        'character_ability_id', v_character_ability_id::text,
        'quantity', v_quantity
      )
    );

    v_item_code := nullif(trim(coalesce(v_result#>>'{resource,item_code}', '')), '');
  end if;

  if v_item_code is not null then
    select item_def.name
    into v_item_name
    from public.odyssey_item_defs item_def
    where item_def.code = v_item_code
    limit 1;
  end if;

  return jsonb_strip_nulls(
    v_result || jsonb_build_object(
      'kind', v_kind,
      'state_id', case when v_kind = 'weapon_feature' then v_state_id else null end,
      'character_ability_id', case when v_kind = 'character_ability' then v_character_ability_id else null end,
      'item_name', v_item_name
    )
  );
end;
$$;

grant execute on function public.reload_inventory_resource(jsonb) to anon, authenticated;
