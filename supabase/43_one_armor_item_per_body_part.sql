create or replace function public.equip_character_equipment_item(
  p_item_id uuid,
  p_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_item public.odyssey_character_equipment_items%rowtype;
  v_model public.odyssey_equipment_model_defs%rowtype;
  v_body_part record;
  v_allowed_codes text[] := '{}'::text[];
  v_effective_part_code text := '';
  v_refresh jsonb := '{}'::jsonb;
  v_is_armor_protection boolean := false;
  v_existing_equipped record;
begin
  select *
  into v_item
  from public.odyssey_character_equipment_items e
  where e.id = p_item_id
  for update of e;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_ITEM_NOT_FOUND',
      'item_id', p_item_id
    );
  end if;

  select *
  into v_model
  from public.odyssey_equipment_model_defs m
  where m.id = v_item.equipment_model_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_MODEL_NOT_FOUND',
      'item_id', p_item_id
    );
  end if;

  select
    b.id,
    b.character_id,
    b.part_key,
    public.odyssey_resolve_body_part_code(b.part_key, d.code) as part_code
  into v_body_part
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'body_part_id', p_body_part_id
    );
  end if;

  if v_body_part.character_id <> v_item.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_CHARACTER_MISMATCH',
      'item_id', p_item_id,
      'body_part_id', p_body_part_id
    );
  end if;

  if not coalesce(v_model.can_equip, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_CANNOT_BE_EQUIPPED',
      'item_id', p_item_id,
      'equipment_model_code', v_model.code
    );
  end if;

  if not coalesce(v_model.can_equip_to_body_part, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_CANNOT_EQUIP_TO_BODY_PART',
      'item_id', p_item_id,
      'equipment_model_code', v_model.code
    );
  end if;

  v_effective_part_code := coalesce(v_body_part.part_code, '');

  if jsonb_typeof(v_model.flags->'allowed_body_part_codes') = 'array' then
    select coalesce(array_agg(lower(trim(body_code.value))), '{}'::text[])
    into v_allowed_codes
    from jsonb_array_elements_text(v_model.flags->'allowed_body_part_codes') as body_code(value);
  end if;

  if coalesce(array_length(v_allowed_codes, 1), 0) > 0 then
    if not (v_effective_part_code = any (v_allowed_codes)) then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_NOT_ALLOWED',
        'item_id', p_item_id,
        'equipment_model_code', v_model.code,
        'body_part_code', v_effective_part_code,
        'allowed_body_part_codes', to_jsonb(v_allowed_codes)
      );
    end if;
  elsif nullif(trim(coalesce(v_model.default_body_part_code, '')), '') is not null then
    if lower(trim(v_model.default_body_part_code)) <> v_effective_part_code then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_NOT_ALLOWED',
        'item_id', p_item_id,
        'equipment_model_code', v_model.code,
        'body_part_code', v_effective_part_code,
        'default_body_part_code', lower(trim(v_model.default_body_part_code))
      );
    end if;
  end if;

  v_is_armor_protection := lower(trim(coalesce(v_model.item_type, ''))) in (
    'armor',
    'shield',
    'special_protection'
  );

  if v_is_armor_protection then
    select
      e.id,
      coalesce(nullif(trim(e.custom_name), ''), occupied_model.name) as item_name
    into v_existing_equipped
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs occupied_model on occupied_model.id = e.equipment_model_id
    where e.character_id = v_item.character_id
      and e.is_equipped = true
      and e.equipped_body_part_id = p_body_part_id
      and e.id <> p_item_id
      and lower(trim(coalesce(occupied_model.item_type, ''))) in (
        'armor',
        'shield',
        'special_protection'
      )
    order by e.updated_at desc nulls last, e.created_at desc, e.id
    for update of e
    limit 1;

    if found then
      return jsonb_build_object(
        'ok', false,
        'error', 'BODY_PART_ARMOR_SLOT_OCCUPIED',
        'message', 'This body part already has an equipped armor item.',
        'body_part_id', p_body_part_id,
        'body_part_code', v_effective_part_code,
        'equipped_item',
          jsonb_build_object(
            'id', v_existing_equipped.id,
            'name', v_existing_equipped.item_name
          )
      );
    end if;
  end if;

  update public.odyssey_character_equipment_items
  set
    is_equipped = true,
    equipped_body_part_id = p_body_part_id,
    updated_at = timezone('utc', now())
  where id = p_item_id;

  perform public.recompute_character_armor(v_item.character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_item.character_id);

  return jsonb_build_object(
    'ok', true,
    'item', public.odyssey_get_equipment_item_json(p_item_id),
    'armor_summary', public.get_character_armor_summary(v_item.character_id),
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

-- Regression checklist:
-- 1. Equip Helmet A to Head successfully.
-- 2. Equip Helmet B to Head -> BODY_PART_ARMOR_SLOT_OCCUPIED, Helmet A stays equipped, Helmet B stays unequipped.
-- 3. Unequip Helmet A -> is_equipped = false, equipped_body_part_id = null, armor recomputed.
-- 4. Equip Helmet B to Head successfully.
-- 5. L.Arm and R.Arm each accept one separate armor item.
-- 6. Second armor item on same arm is rejected with BODY_PART_ARMOR_SLOT_OCCUPIED.
-- 7. Non-armor items are not blocked by this armor-only restriction.
