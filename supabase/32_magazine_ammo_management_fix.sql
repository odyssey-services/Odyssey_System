create or replace function public.odyssey_find_character_ammo_stock_identity(
  p_character_id uuid,
  p_caliber_id uuid,
  p_ammo_type_id uuid
)
returns uuid
language sql
stable
as $$
  select s.id
  from public.odyssey_character_ammo_stock s
  where s.character_id = p_character_id
    and s.caliber_id = p_caliber_id
    and s.ammo_type_id = p_ammo_type_id
  order by s.created_at, s.id
  limit 1;
$$;

create or replace function public.odyssey_is_magazine_loaded_in_weapon(
  p_magazine_id uuid
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.odyssey_character_weapon_profile_states ps
    where ps.loaded_magazine_id = p_magazine_id
    union all
    select 1
    from public.odyssey_character_weapons w
    where w.loaded_magazine_id = p_magazine_id
  );
$$;

create or replace function public.add_character_ammo_stock(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
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

  select *
  into v_caliber
  from public.odyssey_caliber_defs c
  where c.code = v_caliber_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_NOT_FOUND',
      'caliber_code', v_caliber_code
    );
  end if;

  select *
  into v_ammo_type
  from public.odyssey_ammo_type_defs a
  where a.code = v_ammo_type_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_TYPE_NOT_FOUND',
      'ammo_type_code', v_ammo_type_code
    );
  end if;

  if v_ammo_type.caliber_id <> v_caliber.id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'caliber_code', v_caliber_code,
      'ammo_type_code', v_ammo_type_code
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

create or replace function public.load_rounds_to_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_quantity_text text := nullif(trim(coalesce(p_payload->>'quantity', '')), '');
  v_allow_partial_text text := nullif(trim(coalesce(p_payload->>'allow_partial', '')), '');
  v_result jsonb := '{}'::jsonb;
  v_magazine_id uuid := null;
  v_stock_id uuid := null;
begin
  if v_quantity_text is not null then
    begin
      if v_quantity_text::integer <> 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Manual quantity loading is not supported. Use load_magazine_full(jsonb).'
        );
      end if;
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
      if v_allow_partial_text::boolean then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Partial loading is not supported. Use load_magazine_full(jsonb).'
        );
      end if;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'allow_partial must be a valid boolean when provided.'
        );
    end;
  end if;

  v_result := public.load_magazine_full(
    jsonb_build_object(
      'magazine_id', coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id'),
      'ammo_stock_id', p_payload->>'ammo_stock_id'
    )
  );

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  begin
    v_magazine_id := nullif(v_result #>> '{magazine,id}', '')::uuid;
    v_stock_id := nullif(v_result #>> '{ammo_stock,id}', '')::uuid;
  exception
    when others then
      return v_result;
  end;

  return jsonb_build_object(
    'ok', true,
    'character_id', nullif(v_result->>'character_id', '')::uuid,
    'character_magazine_id', v_magazine_id,
    'ammo_stock_id', v_stock_id,
    'loaded_quantity', coalesce((v_result->>'loaded_rounds')::integer, 0),
    'magazine', public.odyssey_get_character_magazine_summary(v_magazine_id),
    'ammo_stock', case
      when coalesce((v_result #>> '{ammo_stock,quantity_after}')::integer, 0) > 0 then public.odyssey_get_character_ammo_stock_row(v_stock_id)
      else null
    end
  );
end;
$$;

create or replace function public.load_magazine_full(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload_magazine_id text := nullif(trim(coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id', '')), '');
  v_payload_ammo_stock_id text := nullif(trim(coalesce(p_payload->>'ammo_stock_id', '')), '');
  v_magazine_id uuid := null;
  v_ammo_stock_id uuid := null;
  v_magazine record;
  v_stock record;
  v_rounds_before integer := 0;
  v_rounds_after integer := 0;
  v_missing_rounds integer := 0;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
begin
  if coalesce(jsonb_typeof(p_payload), 'null') <> 'object' then
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

  if v_stock.caliber_id <> v_stock.ammo_caliber_id or v_magazine.magazine_caliber_id <> v_stock.caliber_id then
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

  v_rounds_after := greatest(coalesce(v_magazine.capacity, 0), 0);
  v_missing_rounds := greatest(v_rounds_after - v_rounds_before, 0);

  if v_missing_rounds <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_FULL',
      'magazine_id', v_magazine_id
    );
  end if;

  if coalesce(v_stock.quantity, 0) < v_missing_rounds then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'requested_quantity', v_missing_rounds,
      'available_quantity', coalesce(v_stock.quantity, 0)
    );
  end if;

  v_stock_quantity_before := coalesce(v_stock.quantity, 0);
  v_stock_quantity_after := greatest(v_stock_quantity_before - v_missing_rounds, 0);

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
    'action', 'load_magazine_full',
    'character_id', v_magazine.character_id,
    'loaded_rounds', v_missing_rounds,
    'magazine',
      jsonb_build_object(
        'id', v_magazine.id,
        'custom_name', v_magazine.custom_name,
        'current_rounds_before', v_rounds_before,
        'current_rounds_after', v_rounds_after,
        'capacity', v_magazine.capacity,
        'caliber_code', v_magazine.caliber_code,
        'ammo_type_code', v_stock.ammo_type_code
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

create or replace function public.unload_rounds_from_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_quantity_text text := nullif(trim(coalesce(p_payload->>'quantity', '')), '');
  v_result jsonb := '{}'::jsonb;
  v_magazine_id uuid := null;
  v_stock_id uuid := null;
begin
  if v_quantity_text is not null then
    begin
      if v_quantity_text::integer <> 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Manual quantity unloading is not supported. Use unload_magazine_all(jsonb).'
        );
      end if;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'quantity must be a valid integer when provided.'
        );
    end;
  end if;

  v_result := public.unload_magazine_all(
    jsonb_build_object(
      'magazine_id', coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id')
    )
  );

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  begin
    v_magazine_id := nullif(v_result #>> '{magazine,id}', '')::uuid;
    v_stock_id := nullif(v_result #>> '{ammo_stock,id}', '')::uuid;
  exception
    when others then
      return v_result;
  end;

  return jsonb_build_object(
    'ok', true,
    'character_id', nullif(v_result->>'character_id', '')::uuid,
    'character_magazine_id', v_magazine_id,
    'unloaded_quantity', coalesce((v_result->>'unloaded_rounds')::integer, 0),
    'magazine', public.odyssey_get_character_magazine_summary(v_magazine_id),
    'ammo_stock', public.odyssey_get_character_ammo_stock_row(v_stock_id)
  );
end;
$$;

create or replace function public.unload_magazine_all(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload_magazine_id text := nullif(trim(coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id', '')), '');
  v_magazine_id uuid := null;
  v_magazine record;
  v_stock record;
  v_rounds_before integer := 0;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
  v_stock_id uuid := null;
begin
  if coalesce(jsonb_typeof(p_payload), 'null') <> 'object' then
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
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'magazine_id must be a valid UUID value.'
      );
  end;

  if v_magazine_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'magazine_id is required.'
    );
  end if;

  select
    cm.id,
    cm.character_id,
    cm.custom_name,
    cm.magazine_def_id,
    cm.ammo_type_id,
    cm.current_rounds,
    md.capacity,
    md.caliber_id,
    caliber.code as caliber_code,
    ammo.code as ammo_type_code,
    ammo.name as ammo_type_name
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

  if public.odyssey_is_magazine_loaded_in_weapon(v_magazine_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_IS_LOADED_IN_WEAPON',
      'message', 'Magazine is currently loaded into a weapon. Remove it or reload the weapon first.'
    );
  end if;

  if v_magazine.magazine_def_id is null or v_magazine.capacity is null or v_magazine.caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_MAGAZINE_DEF',
      'magazine_id', v_magazine_id
    );
  end if;

  v_rounds_before := greatest(coalesce(v_magazine.current_rounds, 0), 0);

  if v_rounds_before <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_EMPTY',
      'magazine_id', v_magazine_id
    );
  end if;

  if v_magazine.ammo_type_id is null or v_magazine.ammo_type_code is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_AMMO_TYPE',
      'magazine_id', v_magazine_id
    );
  end if;

  select *
  into v_stock
  from public.odyssey_character_ammo_stock s
  where s.character_id = v_magazine.character_id
    and s.caliber_id = v_magazine.caliber_id
    and s.ammo_type_id = v_magazine.ammo_type_id
  order by s.created_at, s.id
  limit 1
  for update;

  if found then
    v_stock_id := v_stock.id;
    v_stock_quantity_before := coalesce(v_stock.quantity, 0);
    v_stock_quantity_after := v_stock_quantity_before + v_rounds_before;

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
    values (
      v_magazine.character_id,
      coalesce(v_magazine.ammo_type_name, v_magazine.ammo_type_code),
      v_magazine.caliber_id,
      v_magazine.ammo_type_id,
      v_rounds_before
    )
    returning id into v_stock_id;

    v_stock_quantity_before := 0;
    v_stock_quantity_after := v_rounds_before;
  end if;

  update public.odyssey_character_magazines
  set current_rounds = 0
  where id = v_magazine_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'unload_magazine_all',
    'character_id', v_magazine.character_id,
    'unloaded_rounds', v_rounds_before,
    'magazine',
      jsonb_build_object(
        'id', v_magazine.id,
        'custom_name', v_magazine.custom_name,
        'current_rounds_before', v_rounds_before,
        'current_rounds_after', 0,
        'capacity', v_magazine.capacity,
        'caliber_code', v_magazine.caliber_code,
        'ammo_type_code', v_magazine.ammo_type_code
      ),
    'ammo_stock',
      jsonb_build_object(
        'id', v_stock_id,
        'quantity_before', v_stock_quantity_before,
        'quantity_after', v_stock_quantity_after
      )
  );
end;
$$;

grant execute on function public.odyssey_find_character_ammo_stock_identity(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_is_magazine_loaded_in_weapon(uuid) to anon, authenticated;
grant execute on function public.add_character_ammo_stock(jsonb) to anon, authenticated;
grant execute on function public.load_rounds_to_magazine(jsonb) to anon, authenticated;
grant execute on function public.load_magazine_full(jsonb) to anon, authenticated;
grant execute on function public.unload_rounds_from_magazine(jsonb) to anon, authenticated;
grant execute on function public.unload_magazine_all(jsonb) to anon, authenticated;
