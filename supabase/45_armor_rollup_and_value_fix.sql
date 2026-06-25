update public.odyssey_equipment_model_defs
set
  armor_max_minor = case
    when coalesce(armor_max_minor, 0) <= 0
      or armor_max_minor = coalesce(armor_max_critical, 0)
      then 3
    else armor_max_minor
  end,
  armor_max_serious = case
    when coalesce(armor_max_serious, 0) <= 0
      or armor_max_serious = coalesce(armor_max_critical, 0)
      then 1
    else armor_max_serious
  end
where item_type in ('armor', 'shield', 'special_protection');

update public.odyssey_character_equipment_items e
set
  armor_max_minor = case
    when coalesce(e.armor_max_minor, 0) <= 0
      or e.armor_max_minor = coalesce(e.armor_max_critical, 0)
      then 3
    else e.armor_max_minor
  end,
  armor_max_serious = case
    when coalesce(e.armor_max_serious, 0) <= 0
      or e.armor_max_serious = coalesce(e.armor_max_critical, 0)
      then 1
    else e.armor_max_serious
  end,
  armor_minor = least(greatest(coalesce(e.armor_minor, 0), 0), 3),
  armor_serious = least(greatest(coalesce(e.armor_serious, 0), 0), 1),
  armor_destroyed = case
    when coalesce(e.armor_max_critical, 0) > 0
      and coalesce(e.armor_critical, 0) >= coalesce(e.armor_max_critical, 0)
      then true
    else false
  end
where exists (
  select 1
  from public.odyssey_equipment_model_defs m
  where m.id = e.equipment_model_id
    and m.item_type in ('armor', 'shield', 'special_protection')
);

create or replace function public.get_character_armor_summary(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_exists boolean := false;
  v_total_equipped_armor_value integer := 0;
  v_class_def jsonb := '{}'::jsonb;
  v_required_skill_code text := null;
  v_has_required_skill boolean := false;
  v_penalty_profile text := 'none';
  v_penalty_profile_data jsonb := '{}'::jsonb;
  v_penalty_effect_data jsonb := '{}'::jsonb;
  v_head_protected boolean := false;
  v_torso_protected boolean := false;
  v_special_protection boolean := false;
  v_helpless_execution_protected boolean := false;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  into v_character_exists;

  if not v_character_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id
    );
  end if;

  select
    coalesce(sum(coalesce(e.armor_value, 0)), 0)
  into v_total_equipped_armor_value
  from public.odyssey_character_equipment_items e
  where e.character_id = p_character_id
    and e.is_equipped = true
    and e.equipped_body_part_id is not null;

  v_class_def := public.odyssey_get_armor_class_definition(v_total_equipped_armor_value);
  v_required_skill_code := nullif(trim(coalesce(v_class_def->>'required_skill_code', '')), '');

  if v_required_skill_code is not null then
    select exists(
      select 1
      from public.odyssey_character_skills s
      join public.odyssey_skill_defs d on d.id = s.skill_def_id
      where s.character_id = p_character_id
        and d.code = v_required_skill_code
        and coalesce(s.level, 0) >= 1
    )
    into v_has_required_skill;
  else
    v_has_required_skill := true;
  end if;

  if coalesce(v_class_def->>'code', 'none') = 'none' then
    v_penalty_profile := 'none';
    v_penalty_profile_data := '{}'::jsonb;
  elsif v_has_required_skill then
    v_penalty_profile := 'trained';
    v_penalty_profile_data := coalesce(v_class_def->'trained_penalties', '{}'::jsonb);
  else
    v_penalty_profile := 'untrained';
    v_penalty_profile_data := coalesce(v_class_def->'untrained_penalties', '{}'::jsonb);
  end if;

  v_penalty_effect_data := public.odyssey_build_armor_penalty_effect_data(v_penalty_profile_data);

  with equipped_items as (
    select
      case
        when jsonb_typeof(e.data->'flags') = 'object' then coalesce(m.flags, '{}'::jsonb) || (e.data->'flags')
        else coalesce(m.flags, '{}'::jsonb)
      end as effective_flags,
      public.odyssey_resolve_body_part_code(b.part_key, d.code) as body_part_code
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where e.character_id = p_character_id
      and e.is_equipped = true
      and e.equipped_body_part_id is not null
  )
  select
    coalesce(bool_or(body_part_code = 'head'), false),
    coalesce(bool_or(body_part_code = 'torso'), false),
    coalesce(
      bool_or(
        lower(coalesce(effective_flags->>'protects_helpless_execution', 'false')) in ('true', '1', 'yes', 'on')
      ),
      false
    )
  into
    v_head_protected,
    v_torso_protected,
    v_special_protection
  from equipped_items;

  v_helpless_execution_protected :=
    coalesce(v_class_def->>'code', 'none') in ('medium', 'heavy', 'superheavy')
    and (
      (v_head_protected and v_torso_protected)
      or v_special_protection
    );

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'total_equipped_armor_value', v_total_equipped_armor_value,
    'armor_class', coalesce(v_class_def->>'code', 'none'),
    'required_skill_code', v_required_skill_code,
    'has_required_skill', v_has_required_skill,
    'penalty_profile', v_penalty_profile,
    'head_protected', v_head_protected,
    'torso_protected', v_torso_protected,
    'special_protection', v_special_protection,
    'helpless_execution_protected', v_helpless_execution_protected,
    'penalty_effect_data', v_penalty_effect_data,
    'class_definition', v_class_def
  );
end;
$$;

create or replace function public.odyssey_apply_equipment_damage_tier(
  p_body_part_id uuid,
  p_damage_tier text,
  p_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_damage_tier text := lower(trim(coalesce(p_damage_tier, '')));
  v_item record;
  v_body_part record;
  v_requested integer := greatest(coalesce(p_delta, 0), 0);
  v_remaining integer := greatest(coalesce(p_delta, 0), 0);
  v_absorbed integer := 0;
  v_absorb integer := 0;
  v_capacity integer := 0;
  v_updates jsonb := '[]'::jsonb;
  v_items_changed boolean := false;
  v_new_armor_minor integer := 0;
  v_new_armor_serious integer := 0;
  v_new_armor_critical integer := 0;
  v_new_armor_destroyed boolean := false;
  v_minor_progress integer := 0;
  v_serious_progress integer := 0;
begin
  if v_damage_tier not in ('minor', 'serious', 'critical') then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_DAMAGE_TIER',
      'message', 'damage_tier must be minor, serious, or critical.',
      'damage_tier', v_damage_tier,
      'absorbed', 0,
      'remaining', v_requested,
      'updated_items', '[]'::jsonb,
      'items_changed', false,
      'body_part', null
    );
  end if;

  if v_requested <= 0 then
    return jsonb_build_object(
      'ok', true,
      'damage_tier', v_damage_tier,
      'absorbed', 0,
      'remaining', 0,
      'updated_items', '[]'::jsonb,
      'items_changed', false,
      'body_part', null
    );
  end if;

  select
    b.id,
    b.character_id
  into v_body_part
  from public.odyssey_character_body_parts b
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'message', 'Body part was not found.',
      'damage_tier', v_damage_tier,
      'absorbed', 0,
      'remaining', v_requested,
      'updated_items', '[]'::jsonb,
      'items_changed', false,
      'body_part', null
    );
  end if;

  for v_item in
    select
      e.id,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.sort_order,
      e.created_at,
      coalesce(nullif(trim(e.custom_name), ''), m.name) as item_name
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    where e.equipped_body_part_id = p_body_part_id
      and e.is_equipped = true
    order by e.sort_order, e.created_at, e.id
    for update of e
  loop
    exit when v_remaining <= 0;

    v_minor_progress := greatest(coalesce(v_item.armor_minor, 0), 0)
      + (greatest(coalesce(v_item.armor_serious, 0), 0) * 4);
    v_new_armor_critical := greatest(coalesce(v_item.armor_critical, 0), 0)
      + floor(v_minor_progress::numeric / 8::numeric)::integer;
    v_minor_progress := mod(v_minor_progress, 8);
    v_new_armor_serious := floor(v_minor_progress::numeric / 4::numeric)::integer;
    v_new_armor_minor := mod(v_minor_progress, 4);

    if coalesce(v_item.armor_max_critical, 0) > 0
      and v_new_armor_critical >= coalesce(v_item.armor_max_critical, 0) then
      v_new_armor_critical := coalesce(v_item.armor_max_critical, 0);
      v_new_armor_serious := 0;
      v_new_armor_minor := 0;
    end if;

    if coalesce(v_item.armor_destroyed, false)
      or coalesce(v_item.armor_max_critical, 0) <= coalesce(v_new_armor_critical, 0) then
      continue;
    end if;

    if v_damage_tier = 'minor' then
      v_capacity := greatest(
        ((coalesce(v_item.armor_max_critical, 0) - coalesce(v_new_armor_critical, 0)) * 8)
          - (coalesce(v_new_armor_minor, 0) + (coalesce(v_new_armor_serious, 0) * 4)),
        0
      );

      if v_capacity <= 0 then
        continue;
      end if;

      v_absorb := least(v_remaining, v_capacity);
      v_minor_progress := coalesce(v_new_armor_minor, 0) + (coalesce(v_new_armor_serious, 0) * 4) + v_absorb;
      v_new_armor_critical := coalesce(v_new_armor_critical, 0)
        + floor(v_minor_progress::numeric / 8::numeric)::integer;
      v_minor_progress := mod(v_minor_progress, 8);
      v_new_armor_serious := floor(v_minor_progress::numeric / 4::numeric)::integer;
      v_new_armor_minor := mod(v_minor_progress, 4);
    elsif v_damage_tier = 'serious' then
      v_capacity := greatest(
        ((coalesce(v_item.armor_max_critical, 0) - coalesce(v_new_armor_critical, 0)) * 2)
          - coalesce(v_new_armor_serious, 0),
        0
      );

      if v_capacity <= 0 then
        continue;
      end if;

      v_absorb := least(v_remaining, v_capacity);
      v_serious_progress := coalesce(v_new_armor_serious, 0) + v_absorb;
      v_new_armor_critical := coalesce(v_new_armor_critical, 0)
        + floor(v_serious_progress::numeric / 2::numeric)::integer;
      v_new_armor_serious := mod(v_serious_progress, 2);
    else
      v_capacity := greatest(coalesce(v_item.armor_max_critical, 0) - coalesce(v_new_armor_critical, 0), 0);

      if v_capacity <= 0 then
        continue;
      end if;

      v_absorb := least(v_remaining, v_capacity);
      v_new_armor_critical := coalesce(v_new_armor_critical, 0) + v_absorb;
    end if;

    if v_absorb <= 0 then
      continue;
    end if;

    v_new_armor_destroyed := case
      when coalesce(v_item.armor_max_critical, 0) > 0
        and v_new_armor_critical >= coalesce(v_item.armor_max_critical, 0)
        then true
      else false
    end;

    if v_new_armor_destroyed then
      v_new_armor_serious := 0;
      v_new_armor_minor := 0;
    end if;

    update public.odyssey_character_equipment_items
    set
      armor_minor = v_new_armor_minor,
      armor_serious = v_new_armor_serious,
      armor_critical = v_new_armor_critical,
      armor_destroyed = v_new_armor_destroyed,
      updated_at = timezone('utc', now())
    where id = v_item.id;

    v_updates := v_updates || jsonb_build_array(
      jsonb_build_object(
        'id', v_item.id,
        'name', v_item.item_name,
        'armor_minor', v_new_armor_minor,
        'armor_max_minor', coalesce(v_item.armor_max_minor, 3),
        'armor_serious', v_new_armor_serious,
        'armor_max_serious', coalesce(v_item.armor_max_serious, 1),
        'armor_critical', v_new_armor_critical,
        'armor_max_critical', coalesce(v_item.armor_max_critical, 0),
        'armor_destroyed', v_new_armor_destroyed
      ) || case
        when v_damage_tier = 'minor' then jsonb_build_object('absorbed_minor', v_absorb)
        when v_damage_tier = 'serious' then jsonb_build_object('absorbed_serious', v_absorb)
        else jsonb_build_object('absorbed_critical', v_absorb)
      end
    );

    v_absorbed := v_absorbed + v_absorb;
    v_remaining := v_remaining - v_absorb;
    v_items_changed := true;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'damage_tier', v_damage_tier,
    'absorbed', v_absorbed,
    'remaining', greatest(v_requested - v_absorbed, 0),
    'updated_items', v_updates,
    'items_changed', v_items_changed,
    'body_part',
      jsonb_build_object(
        'id', v_body_part.id,
        'character_id', v_body_part.character_id,
        'absorbed_by_items', v_absorbed
      )
  );
end;
$$;

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'recompute_character_armor'
    and pg_get_function_identity_arguments(p.oid) = 'p_character_id uuid';

  if v_function_def is null then
    raise exception 'Function public.recompute_character_armor(uuid) was not found.';
  end if;

  if position($needle$coalesce(
        sum(
          case
            when public.odyssey_equipment_item_has_remaining_armor_capacity(
              e.armor_minor,
              e.armor_max_minor,
              e.armor_serious,
              e.armor_max_serious,
              e.armor_critical,
              e.armor_max_critical
            ) then coalesce(e.armor_value, 0)
            else 0
          end
        ),
        0
      )::integer as equipped_armor_value,$needle$ in v_function_def) = 0 then
    raise exception 'Could not find equipped_armor_value block in public.recompute_character_armor(uuid).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$coalesce(
        sum(
          case
            when public.odyssey_equipment_item_has_remaining_armor_capacity(
              e.armor_minor,
              e.armor_max_minor,
              e.armor_serious,
              e.armor_max_serious,
              e.armor_critical,
              e.armor_max_critical
            ) then coalesce(e.armor_value, 0)
            else 0
          end
        ),
        0
      )::integer as equipped_armor_value,$old$,
    $new$coalesce(sum(coalesce(e.armor_value, 0)), 0)::integer as equipped_armor_value,$new$
  );

  execute v_function_def;
end;
$$;

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_character_equipment'
    and pg_get_function_identity_arguments(p.oid) = 'p_character_id uuid';

  if v_function_def is null then
    raise exception 'Function public.get_character_equipment(uuid) was not found.';
  end if;

  if position($needle$'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part and has_remaining_armor_capacity))::integer, 0),$needle$ in v_function_def) = 0 then
    raise exception 'Could not find equipped_armor_value_total block in public.get_character_equipment(uuid).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part and has_remaining_armor_capacity))::integer, 0),$old$,
    $new$'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),$new$
  );

  execute v_function_def;
end;
$$;

do $$
begin
  perform public.recompute_character_armor(c.id)
  from public.odyssey_characters c
  where coalesce(c.is_deleted, false) = false;

  perform public.odyssey_refresh_character_combat_state(c.id)
  from public.odyssey_characters c
  where coalesce(c.is_deleted, false) = false;
end;
$$;
