create or replace function public.add_character_ammo_stock(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_ammo_type_id uuid := public.odyssey_try_parse_uuid(p_payload->>'ammo_type_id');
  v_caliber_id uuid := public.odyssey_try_parse_uuid(p_payload->>'caliber_id');
  v_display_name_input text := nullif(trim(coalesce(p_payload->>'display_name', '')), '');
  v_caliber_code text := lower(trim(coalesce(p_payload->>'caliber_code', '')));
  v_ammo_type_code text := lower(trim(coalesce(p_payload->>'ammo_type_code', '')));
  v_quantity integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, 0), 0);
  v_location_data jsonb := case
    when jsonb_typeof(p_payload->'location_data') = 'object' then p_payload->'location_data'
    else '{}'::jsonb
  end;
  v_data jsonb := case
    when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    else '{}'::jsonb
  end;
  v_notes text := coalesce(p_payload->>'notes', '');
  v_caliber public.odyssey_caliber_defs%rowtype;
  v_ammo_type public.odyssey_ammo_type_defs%rowtype;
  v_existing_stock public.odyssey_character_ammo_stock%rowtype;
  v_stock_id uuid := null;
  v_effective_display_name text := null;
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'character_id is required.'
    );
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
      'character_id', v_character_id
    );
  end if;

  if v_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_QUANTITY',
      'quantity', v_quantity
    );
  end if;

  if v_ammo_type_id is not null then
    select *
    into v_ammo_type
    from public.odyssey_ammo_type_defs a
    where a.id = v_ammo_type_id;
  else
    select *
    into v_ammo_type
    from public.odyssey_ammo_type_defs a
    where a.code = v_ammo_type_code;
  end if;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_TYPE_NOT_FOUND',
      'ammo_type_id', v_ammo_type_id,
      'ammo_type_code', v_ammo_type_code
    );
  end if;

  if v_caliber_id is not null then
    select *
    into v_caliber
    from public.odyssey_caliber_defs c
    where c.id = v_caliber_id;
  elsif v_caliber_code <> '' then
    select *
    into v_caliber
    from public.odyssey_caliber_defs c
    where c.code = v_caliber_code;
  else
    select *
    into v_caliber
    from public.odyssey_caliber_defs c
    where c.id = v_ammo_type.caliber_id;
  end if;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_NOT_FOUND',
      'caliber_id', v_caliber_id,
      'caliber_code', v_caliber_code
    );
  end if;

  if v_ammo_type.caliber_id <> v_caliber.id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'caliber_id', v_caliber.id,
      'caliber_code', v_caliber.code,
      'ammo_type_id', v_ammo_type.id,
      'ammo_type_code', v_ammo_type.code
    );
  end if;

  v_effective_display_name := coalesce(v_display_name_input, v_ammo_type.name);

  select *
  into v_existing_stock
  from public.odyssey_character_ammo_stock s
  where s.character_id = v_character_id
    and s.caliber_id = v_caliber.id
    and s.ammo_type_id = v_ammo_type.id
  order by s.created_at, s.id
  limit 1
  for update;

  if found then
    update public.odyssey_character_ammo_stock
    set
      display_name = case
        when v_display_name_input is not null then v_display_name_input
        else display_name
      end,
      quantity = quantity + v_quantity,
      location_data = case
        when v_location_data <> '{}'::jsonb then v_location_data
        else location_data
      end,
      data = data || v_data,
      notes = case
        when nullif(trim(v_notes), '') is not null then v_notes
        else notes
      end
    where id = v_existing_stock.id;

    v_stock_id := v_existing_stock.id;
  else
    insert into public.odyssey_character_ammo_stock (
      character_id,
      display_name,
      caliber_id,
      ammo_type_id,
      quantity,
      location_data,
      data,
      notes
    )
    values (
      v_character_id,
      v_effective_display_name,
      v_caliber.id,
      v_ammo_type.id,
      v_quantity,
      v_location_data,
      v_data,
      v_notes
    )
    returning id into v_stock_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'ammo_stock', public.odyssey_get_character_ammo_stock_row(v_stock_id)
  );
end;
$$;
