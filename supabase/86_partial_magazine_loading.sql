create or replace function public.load_rounds_to_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_payload_magazine_id text := nullif(trim(coalesce(v_payload->>'magazine_id', v_payload->>'character_magazine_id', '')), '');
  v_payload_ammo_stock_id text := nullif(trim(coalesce(v_payload->>'ammo_stock_id', '')), '');
  v_quantity_text text := nullif(trim(coalesce(v_payload->>'quantity', '')), '');
  v_allow_partial_text text := nullif(trim(coalesce(v_payload->>'allow_partial', '')), '');
  v_magazine_id uuid := null;
  v_ammo_stock_id uuid := null;
  v_requested_input integer := 0;
  v_allow_partial boolean := false;
  v_magazine record;
  v_stock record;
  v_rounds_before integer := 0;
  v_capacity integer := 0;
  v_missing_rounds integer := 0;
  v_available_rounds integer := 0;
  v_requested_quantity integer := 0;
  v_loaded_quantity integer := 0;
  v_rounds_after integer := 0;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
  v_partial boolean := false;
  v_effective_stock_caliber_id uuid := null;
begin
  if coalesce(jsonb_typeof(v_payload), 'null') <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  begin
    if v_payload_magazine_id is not null then
      v_magazine_id := v_payload_magazine_id::uuid;
    end if;
    if v_payload_ammo_stock_id is not null then
      v_ammo_stock_id := v_payload_ammo_stock_id::uuid;
    end if;
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'magazine_id and ammo_stock_id must be valid UUID values.'
      );
  end;

  if v_magazine_id is null or v_ammo_stock_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'magazine_id and ammo_stock_id are required.'
    );
  end if;

  if v_quantity_text is not null then
    begin
      v_requested_input := v_quantity_text::integer;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'quantity must be a valid integer when provided.'
        );
    end;
  end if;

  if v_allow_partial_text is not null then
    begin
      v_allow_partial := v_allow_partial_text::boolean;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'allow_partial must be a valid boolean when provided.'
        );
    end;
  end if;

  select
    cm.id,
    cm.character_id,
    cm.custom_name,
    cm.magazine_def_id,
    cm.ammo_type_id,
    cm.current_rounds,
    md.capacity,
    md.caliber_id as magazine_caliber_id,
    caliber.code as caliber_code,
    ammo.code as ammo_type_code
  into v_magazine
  from public.odyssey_character_magazines cm
  left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  left join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  where cm.id = v_magazine_id
  for update of cm;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_NOT_FOUND',
      'magazine_id', v_magazine_id
    );
  end if;

  select
    s.id,
    s.character_id,
    s.display_name,
    s.caliber_id,
    s.ammo_type_id,
    s.quantity,
    ammo.id as ammo_type_exists_id,
    ammo.code as ammo_type_code,
    ammo.caliber_id as ammo_caliber_id
  into v_stock
  from public.odyssey_character_ammo_stock s
  left join public.odyssey_ammo_type_defs ammo on ammo.id = s.ammo_type_id
  where s.id = v_ammo_stock_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_STOCK_NOT_FOUND',
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  if public.odyssey_is_magazine_loaded_in_weapon(v_magazine_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_IS_LOADED_IN_WEAPON',
      'message', 'Magazine is currently loaded into a weapon. Remove it or reload the weapon first.'
    );
  end if;

  if v_magazine.character_id <> v_stock.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_MISMATCH',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  if v_magazine.magazine_def_id is null or v_magazine.capacity is null or v_magazine.magazine_caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_MAGAZINE_DEF',
      'magazine_id', v_magazine_id
    );
  end if;

  if v_stock.ammo_type_id is null or v_stock.ammo_type_exists_id is null or v_stock.ammo_caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_AMMO_TYPE',
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  v_effective_stock_caliber_id := v_stock.ammo_caliber_id;

  if v_stock.caliber_id is distinct from v_stock.ammo_caliber_id then
    update public.odyssey_character_ammo_stock
    set caliber_id = v_stock.ammo_caliber_id
    where id = v_stock.id;
    v_stock.caliber_id := v_stock.ammo_caliber_id;
  end if;

  if v_magazine.magazine_caliber_id <> v_effective_stock_caliber_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  v_rounds_before := greatest(coalesce(v_magazine.current_rounds, 0), 0);

  if v_rounds_before > 0 and v_magazine.ammo_type_id <> v_stock.ammo_type_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_HAS_DIFFERENT_AMMO_TYPE',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  v_capacity := greatest(coalesce(v_magazine.capacity, 0), 0);
  v_missing_rounds := greatest(v_capacity - v_rounds_before, 0);

  if v_missing_rounds <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_FULL',
      'magazine_id', v_magazine_id
    );
  end if;

  v_available_rounds := greatest(coalesce(v_stock.quantity, 0), 0);

  if v_requested_input <= 0 then
    v_requested_quantity := v_missing_rounds;
  else
    v_requested_quantity := least(v_requested_input, v_missing_rounds);
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

  v_partial := v_loaded_quantity < v_requested_quantity;
  v_rounds_after := v_rounds_before + v_loaded_quantity;
  v_stock_quantity_before := v_available_rounds;
  v_stock_quantity_after := greatest(v_stock_quantity_before - v_loaded_quantity, 0);

  if v_stock_quantity_after <= 0 then
    delete from public.odyssey_character_ammo_stock
    where id = v_stock.id;
  else
    update public.odyssey_character_ammo_stock
    set quantity = v_stock_quantity_after
    where id = v_stock.id;
  end if;

  update public.odyssey_character_magazines
  set
    current_rounds = v_rounds_after,
    ammo_type_id = case
      when v_rounds_before <= 0 then v_stock.ammo_type_id
      else ammo_type_id
    end
  where id = v_magazine_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'load_rounds_to_magazine',
    'character_id', v_magazine.character_id,
    'character_magazine_id', v_magazine_id,
    'ammo_stock_id', v_stock.id,
    'loaded_quantity', v_loaded_quantity,
    'loaded_rounds', v_loaded_quantity,
    'requested_quantity', v_requested_quantity,
    'partial', v_partial,
    'magazine',
      jsonb_build_object(
        'id', v_magazine.id,
        'custom_name', v_magazine.custom_name,
        'current_rounds_before', v_rounds_before,
        'current_rounds_after', v_rounds_after,
        'capacity', v_capacity,
        'ammo_type_code', v_stock.ammo_type_code,
        'caliber_code', v_magazine.caliber_code
      ),
    'ammo_stock',
      jsonb_build_object(
        'id', v_stock.id,
        'quantity_before', v_stock_quantity_before,
        'quantity_after', v_stock_quantity_after
      )
  );
end;
$$;

alter function public.load_rounds_to_magazine(jsonb) security invoker;

grant execute on function public.load_rounds_to_magazine(jsonb) to anon, authenticated;
