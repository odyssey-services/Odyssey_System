-- Stage 72: ensure exoskeleton and closed_suit are always body-part equipable.

update public.odyssey_equipment_model_defs
set
  can_equip = true,
  can_equip_to_body_part = true,
  updated_at = timezone('utc', now())
where item_type in ('exoskeleton', 'closed_suit')
  and (
    coalesce(can_equip, false) = false
    or coalesce(can_equip_to_body_part, false) = false
  );

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

  if not coalesce(v_model.can_equip_to_body_part, true)
    and lower(trim(coalesce(v_model.item_type, ''))) not in ('exoskeleton', 'closed_suit') then
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
    'special_protection',
    'exoskeleton',
    'closed_suit'
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
        'special_protection',
        'exoskeleton',
        'closed_suit'
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

create or replace function public.creator_upsert_equipment_model(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_item_type text := lower(trim(coalesce(v_payload->>'item_type', 'armor')));
  v_description text := coalesce(v_payload->>'description', '');
  v_armor_value integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_value', '')), '')::integer, 0);
  v_armor_max_minor integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_max_minor', '')), '')::integer, 0);
  v_armor_max_serious integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_max_serious', '')), '')::integer, 0);
  v_armor_max_critical integer := coalesce(nullif(trim(coalesce(v_payload->>'armor_max_critical', '')), '')::integer, 0);
  v_default_body_part_code text := nullif(lower(trim(coalesce(v_payload->>'default_body_part_code', ''))), '');
  v_can_equip boolean := coalesce(nullif(trim(coalesce(v_payload->>'can_equip', '')), '')::boolean, true);
  v_can_equip_to_body_part boolean := coalesce(nullif(trim(coalesce(v_payload->>'can_equip_to_body_part', '')), '')::boolean, true);
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_flags jsonb := public.odyssey_creator_normalize_json_object(v_payload->'flags');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_ability_links jsonb := public.odyssey_creator_normalize_json_array(v_payload->'ability_links');
  v_entity_id uuid := null;
  v_existing_item_type text := null;
  v_result jsonb := '{}'::jsonb;
  v_processed_link_ids uuid[] := '{}'::uuid[];
  v_entry jsonb := '{}'::jsonb;
  v_ability_id uuid := null;
  v_link_id uuid := null;
  v_grant_mode text := '';
  v_is_enabled boolean := true;
  v_link_sort integer := 0;
  v_link_data jsonb := '{}'::jsonb;
begin
  if v_item_type not in ('armor', 'shield', 'implant', 'prosthetic', 'device', 'exoskeleton', 'closed_suit') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'item_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'Unsupported equipment item_type.'))
    );
  end if;

  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_armor_value < 0
    or v_armor_max_minor < 0
    or v_armor_max_serious < 0
    or v_armor_max_critical < 0 then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'armor_value and armor tier caps must be >= 0.',
      jsonb_build_array(jsonb_build_object('field', 'armor_value', 'message', 'Values cannot be negative.'))
    );
  end if;

  if v_item_type in ('exoskeleton', 'closed_suit') then
    v_can_equip := true;
    v_can_equip_to_body_part := true;
  end if;

  if v_default_body_part_code is not null and not exists (
    select 1
    from public.odyssey_body_part_defs body_part
    where body_part.code = v_default_body_part_code
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'default_body_part_code references an unknown body part.',
      jsonb_build_array(jsonb_build_object('field', 'default_body_part_code', 'message', 'Unknown body part code.'))
    );
  end if;

  if v_id is not null then
    select model.id, model.item_type
    into v_entity_id, v_existing_item_type
    from public.odyssey_equipment_model_defs model
    where model.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'EQUIPMENT_MODEL_NOT_FOUND',
        'Equipment model was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown equipment model id.'))
      );
    end if;
  else
    select model.id, model.item_type
    into v_entity_id, v_existing_item_type
    from public.odyssey_equipment_model_defs model
    where model.code = v_code
    limit 1;
  end if;

  if v_entity_id is not null and v_existing_item_type not in ('armor', 'shield', 'implant', 'prosthetic', 'device', 'exoskeleton', 'closed_suit') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'The selected equipment model belongs to another module.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'This equipment model cannot be edited by the equipment creator.'))
    );
  end if;

  if exists (
    select 1
    from public.odyssey_equipment_model_defs model
    where model.code = v_code
      and model.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Equipment model code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate equipment model code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_equipment_model_defs (
      code,
      name,
      item_type,
      description,
      armor_value,
      armor_max_minor,
      armor_max_serious,
      armor_max_critical,
      default_body_part_code,
      can_equip,
      can_equip_to_body_part,
      effect_data,
      flags,
      tags,
      is_custom,
      sort_order
    )
    values (
      v_code,
      v_name,
      v_item_type,
      v_description,
      v_armor_value,
      v_armor_max_minor,
      v_armor_max_serious,
      v_armor_max_critical,
      v_default_body_part_code,
      v_can_equip,
      v_can_equip_to_body_part,
      v_effect_data,
      v_flags,
      v_tags,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_equipment_model_defs
    set
      code = v_code,
      name = v_name,
      item_type = v_item_type,
      description = v_description,
      armor_value = v_armor_value,
      armor_max_minor = v_armor_max_minor,
      armor_max_serious = v_armor_max_serious,
      armor_max_critical = v_armor_max_critical,
      default_body_part_code = v_default_body_part_code,
      can_equip = v_can_equip,
      can_equip_to_body_part = v_can_equip_to_body_part,
      effect_data = v_effect_data,
      flags = v_flags,
      tags = v_tags,
      sort_order = v_sort_order,
      updated_at = timezone('utc', now())
    where id = v_entity_id;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_ability_links)
  loop
    v_ability_id := public.odyssey_try_parse_uuid(v_entry->>'ability_def_id');
    v_link_id := public.odyssey_try_parse_uuid(v_entry->>'id');
    v_grant_mode := lower(trim(coalesce(v_entry->>'grant_mode', 'available')));
    v_is_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled', '')), '')::boolean, true);
    v_link_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_link_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_ability_id is null then
      continue;
    end if;

    select link.id
    into v_link_id
    from public.odyssey_equipment_model_abilities link
    where link.equipment_model_id = v_entity_id
      and link.ability_def_id = v_ability_id
    for update;

    if v_link_id is null then
      insert into public.odyssey_equipment_model_abilities (
        equipment_model_id,
        ability_def_id,
        grant_mode,
        is_enabled,
        sort_order,
        data
      )
      values (
        v_entity_id,
        v_ability_id,
        v_grant_mode,
        v_is_enabled,
        v_link_sort,
        v_link_data
      )
      returning id into v_link_id;
    else
      update public.odyssey_equipment_model_abilities
      set
        grant_mode = v_grant_mode,
        is_enabled = v_is_enabled,
        sort_order = v_link_sort,
        data = v_link_data
      where id = v_link_id;
    end if;

    v_processed_link_ids := array_append(v_processed_link_ids, v_link_id);
  end loop;

  delete from public.odyssey_equipment_model_abilities
  where equipment_model_id = v_entity_id
    and not (id = any(v_processed_link_ids));

  v_result := public.creator_get_equipment_model(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;
