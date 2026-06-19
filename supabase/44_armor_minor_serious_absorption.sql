alter table public.odyssey_equipment_model_defs
  add column if not exists armor_max_minor integer not null default 0,
  add column if not exists armor_max_serious integer not null default 0;

alter table public.odyssey_equipment_model_defs
  drop constraint if exists odyssey_equipment_model_defs_armor_tier_check;

alter table public.odyssey_equipment_model_defs
  add constraint odyssey_equipment_model_defs_armor_tier_check
  check (
    armor_value >= 0
    and armor_max_minor >= 0
    and armor_max_serious >= 0
    and armor_max_critical >= 0
  );

alter table public.odyssey_character_equipment_items
  add column if not exists armor_minor integer not null default 0,
  add column if not exists armor_max_minor integer not null default 0,
  add column if not exists armor_serious integer not null default 0,
  add column if not exists armor_max_serious integer not null default 0;

alter table public.odyssey_character_equipment_items
  drop constraint if exists odyssey_character_equipment_items_armor_tier_check;

alter table public.odyssey_character_equipment_items
  add constraint odyssey_character_equipment_items_armor_tier_check
  check (
    armor_value >= 0
    and armor_minor >= 0
    and armor_max_minor >= 0
    and armor_serious >= 0
    and armor_max_serious >= 0
    and armor_critical >= 0
    and armor_max_critical >= 0
  );

alter table public.odyssey_character_body_parts
  add column if not exists armor_minor integer not null default 0,
  add column if not exists armor_max_minor integer not null default 0,
  add column if not exists armor_serious integer not null default 0,
  add column if not exists armor_max_serious integer not null default 0;

alter table public.odyssey_character_body_parts
  drop constraint if exists odyssey_character_body_parts_armor_tier_check;

alter table public.odyssey_character_body_parts
  add constraint odyssey_character_body_parts_armor_tier_check
  check (
    armor_value >= 0
    and armor_minor >= 0
    and armor_max_minor >= 0
    and armor_serious >= 0
    and armor_max_serious >= 0
    and armor_critical >= 0
    and armor_max_critical >= 0
  );

update public.odyssey_equipment_model_defs
set
  armor_max_minor = case
    when coalesce(armor_max_minor, 0) <= 0 then greatest(coalesce(armor_max_critical, 0), 0)
    else armor_max_minor
  end,
  armor_max_serious = case
    when coalesce(armor_max_serious, 0) <= 0 then greatest(coalesce(armor_max_critical, 0), 0)
    else armor_max_serious
  end
where true;

update public.odyssey_character_equipment_items e
set
  armor_minor = least(
    greatest(coalesce(e.armor_minor, 0), 0),
    case
      when coalesce(e.armor_max_minor, 0) <= 0 then greatest(coalesce(e.armor_max_critical, 0), 0)
      else greatest(coalesce(e.armor_max_minor, 0), 0)
    end
  ),
  armor_max_minor = case
    when coalesce(e.armor_max_minor, 0) <= 0 then greatest(coalesce(e.armor_max_critical, 0), 0)
    else e.armor_max_minor
  end,
  armor_serious = least(
    greatest(coalesce(e.armor_serious, 0), 0),
    case
      when coalesce(e.armor_max_serious, 0) <= 0 then greatest(coalesce(e.armor_max_critical, 0), 0)
      else greatest(coalesce(e.armor_max_serious, 0), 0)
    end
  ),
  armor_max_serious = case
    when coalesce(e.armor_max_serious, 0) <= 0 then greatest(coalesce(e.armor_max_critical, 0), 0)
    else e.armor_max_serious
  end
where true;

create or replace function public.odyssey_equipment_item_has_remaining_armor_capacity(
  p_armor_minor integer,
  p_armor_max_minor integer,
  p_armor_serious integer,
  p_armor_max_serious integer,
  p_armor_critical integer,
  p_armor_max_critical integer
)
returns boolean
language sql
immutable
as $$
  select
    case
      when coalesce(p_armor_max_critical, 0) > 0 then
        coalesce(p_armor_critical, 0) < coalesce(p_armor_max_critical, 0)
      when coalesce(p_armor_max_serious, 0) > 0
        or coalesce(p_armor_max_minor, 0) > 0 then
        coalesce(p_armor_serious, 0) < coalesce(p_armor_max_serious, 0)
        or coalesce(p_armor_minor, 0) < coalesce(p_armor_max_minor, 0)
      else false
    end;
$$;

create or replace function public.odyssey_equipment_item_is_destroyed(
  p_armor_minor integer,
  p_armor_max_minor integer,
  p_armor_serious integer,
  p_armor_max_serious integer,
  p_armor_critical integer,
  p_armor_max_critical integer
)
returns boolean
language sql
immutable
as $$
  select not public.odyssey_equipment_item_has_remaining_armor_capacity(
    p_armor_minor,
    p_armor_max_minor,
    p_armor_serious,
    p_armor_max_serious,
    p_armor_critical,
    p_armor_max_critical
  );
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

    if coalesce(v_item.armor_destroyed, false) then
      continue;
    end if;

    v_new_armor_minor := coalesce(v_item.armor_minor, 0);
    v_new_armor_serious := coalesce(v_item.armor_serious, 0);
    v_new_armor_critical := coalesce(v_item.armor_critical, 0);
    v_capacity := 0;

    if v_damage_tier = 'minor' then
      v_capacity := greatest(coalesce(v_item.armor_max_minor, 0) - coalesce(v_item.armor_minor, 0), 0);
      if v_capacity <= 0 then
        continue;
      end if;
      v_absorb := least(v_remaining, v_capacity);
      v_new_armor_minor := coalesce(v_item.armor_minor, 0) + v_absorb;
    elsif v_damage_tier = 'serious' then
      v_capacity := greatest(coalesce(v_item.armor_max_serious, 0) - coalesce(v_item.armor_serious, 0), 0);
      if v_capacity <= 0 then
        continue;
      end if;
      v_absorb := least(v_remaining, v_capacity);
      v_new_armor_serious := coalesce(v_item.armor_serious, 0) + v_absorb;
    else
      v_capacity := greatest(coalesce(v_item.armor_max_critical, 0) - coalesce(v_item.armor_critical, 0), 0);
      if v_capacity <= 0 then
        continue;
      end if;
      v_absorb := least(v_remaining, v_capacity);
      v_new_armor_critical := coalesce(v_item.armor_critical, 0) + v_absorb;
    end if;

    if v_absorb <= 0 then
      continue;
    end if;

    v_new_armor_destroyed := public.odyssey_equipment_item_is_destroyed(
      v_new_armor_minor,
      coalesce(v_item.armor_max_minor, 0),
      v_new_armor_serious,
      coalesce(v_item.armor_max_serious, 0),
      v_new_armor_critical,
      coalesce(v_item.armor_max_critical, 0)
    );

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
        'armor_max_minor', coalesce(v_item.armor_max_minor, 0),
        'armor_serious', v_new_armor_serious,
        'armor_max_serious', coalesce(v_item.armor_max_serious, 0),
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

create or replace function public.odyssey_apply_equipment_critical_damage(
  p_body_part_id uuid,
  p_critical_delta integer
)
returns jsonb
language sql
as $$
  select public.odyssey_apply_equipment_damage_tier(
    p_body_part_id,
    'critical',
    p_critical_delta
  );
$$;

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
    coalesce(
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
    )
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
      e.id,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      public.odyssey_equipment_item_has_remaining_armor_capacity(
        e.armor_minor,
        e.armor_max_minor,
        e.armor_serious,
        e.armor_max_serious,
        e.armor_critical,
        e.armor_max_critical
      ) as has_remaining_capacity,
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
    coalesce(bool_or(body_part_code = 'head' and has_remaining_capacity), false),
    coalesce(bool_or(body_part_code = 'torso' and has_remaining_capacity), false),
    coalesce(
      bool_or(
        has_remaining_capacity
        and lower(coalesce(effective_flags->>'protects_helpless_execution', 'false')) in ('true', '1', 'yes', 'on')
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

create or replace function public.recompute_character_armor(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_body_parts jsonb := '[]'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_penalty_effect_data jsonb := '{}'::jsonb;
  v_penalty_has_modifiers boolean := false;
  v_penalty_has_flags boolean := false;
  v_existing_penalty_effect_id uuid := null;
  v_description text := '';
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

  with equipped_totals as (
    select
      e.equipped_body_part_id as body_part_id,
      coalesce(
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
      )::integer as equipped_armor_value,
      coalesce(sum(coalesce(e.armor_minor, 0)), 0)::integer as armor_minor,
      coalesce(sum(coalesce(e.armor_max_minor, 0)), 0)::integer as armor_max_minor,
      coalesce(sum(coalesce(e.armor_serious, 0)), 0)::integer as armor_serious,
      coalesce(sum(coalesce(e.armor_max_serious, 0)), 0)::integer as armor_max_serious,
      coalesce(sum(coalesce(e.armor_critical, 0)), 0)::integer as armor_critical,
      coalesce(sum(coalesce(e.armor_max_critical, 0)), 0)::integer as armor_max_critical,
      count(*)::integer as item_count,
      (
        count(*) filter (
          where public.odyssey_equipment_item_has_remaining_armor_capacity(
            e.armor_minor,
            e.armor_max_minor,
            e.armor_serious,
            e.armor_max_serious,
            e.armor_critical,
            e.armor_max_critical
          )
        )
      )::integer as remaining_capacity_count
    from public.odyssey_character_equipment_items e
    where e.character_id = p_character_id
      and e.is_equipped = true
      and e.equipped_body_part_id is not null
    group by e.equipped_body_part_id
  ),
  snapshot_source as (
    select
      b.id,
      b.part_key,
      b.sort_order,
      coalesce(b.natural_armor_value, 0) as natural_armor_value,
      coalesce(t.equipped_armor_value, 0) as equipped_armor_value,
      coalesce(t.armor_minor, 0) as armor_minor,
      coalesce(t.armor_max_minor, 0) as armor_max_minor,
      coalesce(t.armor_serious, 0) as armor_serious,
      coalesce(t.armor_max_serious, 0) as armor_max_serious,
      coalesce(t.armor_critical, 0) as armor_critical,
      coalesce(t.armor_max_critical, 0) as armor_max_critical,
      coalesce(t.item_count, 0) as item_count,
      coalesce(t.remaining_capacity_count, 0) as remaining_capacity_count
    from public.odyssey_character_body_parts b
    left join equipped_totals t on t.body_part_id = b.id
    where b.character_id = p_character_id
  ),
  updated_parts as (
    update public.odyssey_character_body_parts b
    set
      armor_value = greatest(snapshot_source.natural_armor_value + snapshot_source.equipped_armor_value, 0),
      armor_minor = greatest(snapshot_source.armor_minor, 0),
      armor_max_minor = greatest(snapshot_source.armor_max_minor, 0),
      armor_serious = greatest(snapshot_source.armor_serious, 0),
      armor_max_serious = greatest(snapshot_source.armor_max_serious, 0),
      armor_critical = greatest(snapshot_source.armor_critical, 0),
      armor_max_critical = greatest(snapshot_source.armor_max_critical, 0),
      armor_destroyed = case
        when snapshot_source.item_count <= 0 then false
        when snapshot_source.remaining_capacity_count > 0 then false
        else true
      end,
      updated_at = timezone('utc', now())
    from snapshot_source
    where b.id = snapshot_source.id
    returning
      b.id,
      b.part_key,
      b.natural_armor_value,
      snapshot_source.equipped_armor_value,
      b.armor_value,
      b.armor_minor,
      b.armor_max_minor,
      b.armor_serious,
      b.armor_max_serious,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.sort_order
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', u.id,
          'name', u.part_key,
          'natural_armor_value', u.natural_armor_value,
          'equipped_armor_value', u.equipped_armor_value,
          'armor_value', u.armor_value,
          'armor_minor', u.armor_minor,
          'armor_max_minor', u.armor_max_minor,
          'armor_serious', u.armor_serious,
          'armor_max_serious', u.armor_max_serious,
          'armor_critical', u.armor_critical,
          'armor_max_critical', u.armor_max_critical,
          'armor_destroyed', u.armor_destroyed
        )
        order by u.sort_order, u.part_key
      ),
      '[]'::jsonb
    )
  into v_body_parts
  from updated_parts u;

  v_armor_summary := public.get_character_armor_summary(p_character_id);
  v_penalty_effect_data := case
    when jsonb_typeof(v_armor_summary->'penalty_effect_data') = 'object' then v_armor_summary->'penalty_effect_data'
    else '{}'::jsonb
  end;
  v_penalty_has_modifiers :=
    jsonb_typeof(v_penalty_effect_data->'modifiers') = 'array'
    and jsonb_array_length(v_penalty_effect_data->'modifiers') > 0;

  select exists(
    select 1
    from jsonb_each(
      case
        when jsonb_typeof(v_penalty_effect_data->'flags') = 'object' then v_penalty_effect_data->'flags'
        else '{}'::jsonb
      end
    )
  )
  into v_penalty_has_flags;

  if coalesce(v_armor_summary->>'armor_class', 'none') = 'none'
    or not (v_penalty_has_modifiers or v_penalty_has_flags) then
    update public.odyssey_character_effects
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where character_id = p_character_id
      and is_active = true
      and effect_key = 'armor_penalty';
  else
    v_description := format(
      'Armor penalty for %s armor (%s profile).',
      coalesce(v_armor_summary->>'armor_class', 'none'),
      coalesce(v_armor_summary->>'penalty_profile', 'none')
    );

    select e.id
    into v_existing_penalty_effect_id
    from public.odyssey_character_effects e
    where e.character_id = p_character_id
      and e.effect_key = 'armor_penalty'
      and e.is_active = true
    order by e.created_at desc, e.id desc
    limit 1;

    update public.odyssey_character_effects
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where character_id = p_character_id
      and effect_key = 'armor_penalty'
      and is_active = true
      and (v_existing_penalty_effect_id is null or id <> v_existing_penalty_effect_id);

    if v_existing_penalty_effect_id is null then
      insert into public.odyssey_character_effects (
        character_id,
        effect_def_id,
        effect_key,
        name,
        description,
        source,
        source_type,
        source_id,
        source_character_id,
        duration_type,
        rounds_left,
        stacks,
        data,
        is_active,
        created_by
      )
      values (
        p_character_id,
        null,
        'armor_penalty',
        'Armor Penalty',
        v_description,
        'armor_class',
        'armor',
        null,
        null,
        'manual',
        null,
        1,
        jsonb_set(
          jsonb_set(v_penalty_effect_data, '{category}', to_jsonb('armor'::text), true),
          '{armor_penalty_meta}',
          jsonb_build_object(
            'armor_class', coalesce(v_armor_summary->>'armor_class', 'none'),
            'required_skill_code', nullif(trim(coalesce(v_armor_summary->>'required_skill_code', '')), ''),
            'has_required_skill', coalesce(nullif(trim(coalesce(v_armor_summary->>'has_required_skill', '')), '')::boolean, false),
            'penalty_profile', coalesce(v_armor_summary->>'penalty_profile', 'none')
          ),
          true
        ),
        true,
        'system'
      );
    else
      update public.odyssey_character_effects
      set
        effect_def_id = null,
        name = 'Armor Penalty',
        description = v_description,
        source = 'armor_class',
        source_type = 'armor',
        source_id = null,
        source_character_id = null,
        duration_type = 'manual',
        rounds_left = null,
        stacks = 1,
        data = jsonb_set(
          jsonb_set(v_penalty_effect_data, '{category}', to_jsonb('armor'::text), true),
          '{armor_penalty_meta}',
          jsonb_build_object(
            'armor_class', coalesce(v_armor_summary->>'armor_class', 'none'),
            'required_skill_code', nullif(trim(coalesce(v_armor_summary->>'required_skill_code', '')), ''),
            'has_required_skill', coalesce(nullif(trim(coalesce(v_armor_summary->>'has_required_skill', '')), '')::boolean, false),
            'penalty_profile', coalesce(v_armor_summary->>'penalty_profile', 'none')
          ),
          true
        ),
        is_active = true,
        updated_at = timezone('utc', now())
      where id = v_existing_penalty_effect_id;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'body_parts', v_body_parts,
    'armor_summary', v_armor_summary
  );
end;
$$;

create or replace function public.odyssey_get_equipment_item_json(
  p_item_id uuid
)
returns jsonb
language sql
stable
as $$
  with selected_item as (
    select
      e.id,
      e.character_id,
      e.equipment_model_id,
      e.equipped_body_part_id,
      e.custom_name,
      e.is_equipped,
      e.armor_value,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.current_charges,
      e.max_charges,
      e.data,
      e.notes,
      e.sort_order,
      e.created_at,
      e.updated_at,
      m.code as equipment_model_code,
      m.name as equipment_model_name,
      m.item_type,
      m.description as model_description,
      m.armor_value as model_armor_value,
      m.armor_max_minor as model_armor_max_minor,
      m.armor_max_serious as model_armor_max_serious,
      m.armor_max_critical as model_armor_max_critical,
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code,
      public.odyssey_equipment_item_has_remaining_armor_capacity(
        e.armor_minor,
        e.armor_max_minor,
        e.armor_serious,
        e.armor_max_serious,
        e.armor_critical,
        e.armor_max_critical
      ) as has_remaining_armor_capacity
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    left join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs body_def on body_def.id = b.body_part_def_id
    where e.id = p_item_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'id', s.id,
        'character_id', s.character_id,
        'custom_name', s.custom_name,
        'name', coalesce(nullif(trim(s.custom_name), ''), s.equipment_model_name),
        'is_equipped', s.is_equipped,
        'armor_value', s.armor_value,
        'armor_minor', s.armor_minor,
        'armor_max_minor', s.armor_max_minor,
        'armor_serious', s.armor_serious,
        'armor_max_serious', s.armor_max_serious,
        'armor_critical', s.armor_critical,
        'armor_max_critical', s.armor_max_critical,
        'armor_destroyed', s.armor_destroyed,
        'has_remaining_armor_capacity', s.has_remaining_armor_capacity,
        'current_charges', s.current_charges,
        'max_charges', s.max_charges,
        'data', s.data,
        'notes', s.notes,
        'sort_order', s.sort_order,
        'created_at', s.created_at,
        'updated_at', s.updated_at,
        'model',
          jsonb_build_object(
            'id', s.equipment_model_id,
            'code', s.equipment_model_code,
            'name', s.equipment_model_name,
            'item_type', s.item_type,
            'description', s.model_description,
            'armor_value', s.model_armor_value,
            'armor_max_minor', s.model_armor_max_minor,
            'armor_max_serious', s.model_armor_max_serious,
            'armor_max_critical', s.model_armor_max_critical,
            'default_body_part_code', s.default_body_part_code,
            'can_equip', s.can_equip,
            'can_equip_to_body_part', s.can_equip_to_body_part,
            'effect_data', s.effect_data,
            'flags', s.model_flags,
            'tags', s.tags
          ),
        'effective_flags',
          case
            when jsonb_typeof(s.data->'flags') = 'object' then coalesce(s.model_flags, '{}'::jsonb) || (s.data->'flags')
            else coalesce(s.model_flags, '{}'::jsonb)
          end,
        'body_part',
          case
            when s.equipped_body_part_id is null then null
            else jsonb_build_object(
              'id', s.equipped_body_part_id,
              'part_key', s.part_key,
              'code', s.body_part_code,
              'name', s.body_part_name
            )
          end
      )
      from selected_item s
    ),
    '{}'::jsonb
  );
$$;

create or replace function public.get_character_equipment(
  p_character_id uuid
)
returns jsonb
language sql
stable
as $$
  with item_rows as (
    select
      e.id,
      e.character_id,
      e.equipment_model_id,
      e.equipped_body_part_id,
      e.custom_name,
      e.is_equipped,
      e.armor_value,
      e.armor_minor,
      e.armor_max_minor,
      e.armor_serious,
      e.armor_max_serious,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.current_charges,
      e.max_charges,
      e.data,
      e.notes,
      e.sort_order,
      e.created_at,
      e.updated_at,
      m.code as equipment_model_code,
      m.name as equipment_model_name,
      m.item_type,
      m.description as model_description,
      m.armor_value as model_armor_value,
      m.armor_max_minor as model_armor_max_minor,
      m.armor_max_serious as model_armor_max_serious,
      m.armor_max_critical as model_armor_max_critical,
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code,
      public.odyssey_equipment_item_has_remaining_armor_capacity(
        e.armor_minor,
        e.armor_max_minor,
        e.armor_serious,
        e.armor_max_serious,
        e.armor_critical,
        e.armor_max_critical
      ) as has_remaining_armor_capacity
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    left join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs body_def on body_def.id = b.body_part_def_id
    where e.character_id = p_character_id
  ),
  item_json as (
    select
      id,
      sort_order,
      created_at,
      is_equipped,
      equipped_body_part_id is not null as has_body_part,
      has_remaining_armor_capacity,
      jsonb_build_object(
        'id', id,
        'character_id', character_id,
        'custom_name', custom_name,
        'name', coalesce(nullif(trim(custom_name), ''), equipment_model_name),
        'is_equipped', is_equipped,
        'armor_value', armor_value,
        'armor_minor', armor_minor,
        'armor_max_minor', armor_max_minor,
        'armor_serious', armor_serious,
        'armor_max_serious', armor_max_serious,
        'armor_critical', armor_critical,
        'armor_max_critical', armor_max_critical,
        'armor_destroyed', armor_destroyed,
        'has_remaining_armor_capacity', has_remaining_armor_capacity,
        'current_charges', current_charges,
        'max_charges', max_charges,
        'data', data,
        'notes', notes,
        'sort_order', sort_order,
        'created_at', created_at,
        'updated_at', updated_at,
        'model',
          jsonb_build_object(
            'id', equipment_model_id,
            'code', equipment_model_code,
            'name', equipment_model_name,
            'item_type', item_type,
            'description', model_description,
            'armor_value', model_armor_value,
            'armor_max_minor', model_armor_max_minor,
            'armor_max_serious', model_armor_max_serious,
            'armor_max_critical', model_armor_max_critical,
            'default_body_part_code', default_body_part_code,
            'can_equip', can_equip,
            'can_equip_to_body_part', can_equip_to_body_part,
            'effect_data', effect_data,
            'flags', model_flags,
            'tags', tags
          ),
        'effective_flags',
          case
            when jsonb_typeof(data->'flags') = 'object' then coalesce(model_flags, '{}'::jsonb) || (data->'flags')
            else coalesce(model_flags, '{}'::jsonb)
          end,
        'body_part',
          case
            when equipped_body_part_id is null then null
            else jsonb_build_object(
              'id', equipped_body_part_id,
              'part_key', part_key,
              'code', body_part_code,
              'name', body_part_name
            )
          end
      ) as item_payload
    from item_rows
  ),
  summary_row as (
    select jsonb_build_object(
      'total_item_count', count(*)::integer,
      'equipped_item_count', (count(*) filter (where is_equipped))::integer,
      'equipped_body_part_item_count', (count(*) filter (where is_equipped and has_body_part))::integer,
      'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part and has_remaining_armor_capacity))::integer, 0),
      'equipped_armor_minor_total', coalesce((sum(coalesce((item_payload->>'armor_minor')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),
      'equipped_armor_max_minor_total', coalesce((sum(coalesce((item_payload->>'armor_max_minor')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),
      'equipped_armor_serious_total', coalesce((sum(coalesce((item_payload->>'armor_serious')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),
      'equipped_armor_max_serious_total', coalesce((sum(coalesce((item_payload->>'armor_max_serious')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),
      'equipped_armor_critical_total', coalesce((sum(coalesce((item_payload->>'armor_critical')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0),
      'equipped_armor_max_critical_total', coalesce((sum(coalesce((item_payload->>'armor_max_critical')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0)
    ) as summary_payload
    from item_json
  )
  select jsonb_build_object(
    'character_id', p_character_id,
    'items',
      coalesce(
        (
          select jsonb_agg(item_payload order by sort_order, created_at, id)
          from item_json
        ),
        '[]'::jsonb
      ),
    'equipped',
      coalesce(
        (
          select jsonb_agg(item_payload order by sort_order, created_at, id)
          from item_json
          where is_equipped = true
        ),
        '[]'::jsonb
      ),
    'summary', coalesce((select summary_payload from summary_row), '{}'::jsonb),
    'armor_summary', public.get_character_armor_summary(p_character_id)
  );
$$;

create or replace function public.create_character_equipment_item(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_equipment_model_code text := lower(trim(coalesce(p_payload->>'equipment_model_code', '')));
  v_custom_name text := nullif(trim(coalesce(p_payload->>'custom_name', '')), '');
  v_equipped_body_part_id uuid := nullif(trim(coalesce(p_payload->>'equipped_body_part_id', '')), '')::uuid;
  v_is_equipped boolean := coalesce(nullif(trim(coalesce(p_payload->>'is_equipped', '')), '')::boolean, false);
  v_data jsonb := case
    when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    else '{}'::jsonb
  end;
  v_notes text := coalesce(p_payload->>'notes', '');
  v_sort_order integer := coalesce(nullif(trim(coalesce(p_payload->>'sort_order', '')), '')::integer, 0);
  v_model public.odyssey_equipment_model_defs%rowtype;
  v_item_id uuid := null;
  v_refresh jsonb := '{}'::jsonb;
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

  select *
  into v_model
  from public.odyssey_equipment_model_defs m
  where m.code = v_equipment_model_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_MODEL_NOT_FOUND',
      'equipment_model_code', v_equipment_model_code
    );
  end if;

  insert into public.odyssey_character_equipment_items (
    character_id,
    equipment_model_id,
    equipped_body_part_id,
    custom_name,
    is_equipped,
    armor_value,
    armor_minor,
    armor_max_minor,
    armor_serious,
    armor_max_serious,
    armor_critical,
    armor_max_critical,
    armor_destroyed,
    current_charges,
    max_charges,
    data,
    notes,
    sort_order
  )
  values (
    v_character_id,
    v_model.id,
    null,
    v_custom_name,
    false,
    coalesce(v_model.armor_value, 0),
    0,
    coalesce(v_model.armor_max_minor, 0),
    0,
    coalesce(v_model.armor_max_serious, 0),
    0,
    coalesce(v_model.armor_max_critical, 0),
    false,
    null,
    null,
    v_data,
    v_notes,
    v_sort_order
  )
  returning id into v_item_id;

  if v_is_equipped and v_equipped_body_part_id is not null then
    v_refresh := public.equip_character_equipment_item(v_item_id, v_equipped_body_part_id);
    if coalesce(nullif(trim(coalesce(v_refresh->>'ok', '')), '')::boolean, false) = false then
      return jsonb_build_object(
        'ok', false,
        'created', true,
        'character_id', v_character_id,
        'item', public.odyssey_get_equipment_item_json(v_item_id),
        'equip_result', v_refresh
      );
    end if;
    return jsonb_build_object(
      'ok', true,
      'created', true,
      'character_id', v_character_id,
      'item', public.odyssey_get_equipment_item_json(v_item_id),
      'armor_summary', public.get_character_armor_summary(v_character_id),
      'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'created', true,
    'character_id', v_character_id,
    'item', public.odyssey_get_equipment_item_json(v_item_id),
    'armor_summary', public.get_character_armor_summary(v_character_id)
  );
end;
$$;

create or replace function public.update_character_equipment_item(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_item_id uuid := nullif(trim(coalesce(p_payload->>'item_id', '')), '')::uuid;
  v_custom_name text := nullif(trim(coalesce(p_payload->>'custom_name', '')), '');
  v_has_custom_name boolean := p_payload ? 'custom_name';
  v_has_notes boolean := p_payload ? 'notes';
  v_notes text := coalesce(p_payload->>'notes', '');
  v_has_sort_order boolean := p_payload ? 'sort_order';
  v_sort_order integer := coalesce(nullif(trim(coalesce(p_payload->>'sort_order', '')), '')::integer, 0);
  v_has_armor_value boolean := false;
  v_has_armor_minor boolean := false;
  v_has_armor_max_minor boolean := false;
  v_has_armor_serious boolean := false;
  v_has_armor_max_serious boolean := false;
  v_has_armor_critical boolean := false;
  v_has_armor_max_critical boolean := false;
  v_has_armor_destroyed boolean := false;
  v_has_current_charges boolean := p_payload ? 'current_charges';
  v_has_max_charges boolean := p_payload ? 'max_charges';
  v_has_data boolean := p_payload ? 'data';
  v_data jsonb := case
    when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    else null
  end;
  v_item public.odyssey_character_equipment_items%rowtype;
  v_new_armor_value integer;
  v_new_armor_minor integer;
  v_new_armor_max_minor integer;
  v_new_armor_serious integer;
  v_new_armor_max_serious integer;
  v_new_armor_critical integer;
  v_new_armor_max_critical integer;
  v_new_armor_destroyed boolean;
  v_new_current_charges integer;
  v_new_max_charges integer;
  v_refresh jsonb := '{}'::jsonb;
begin
  if v_item_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_ITEM_NOT_FOUND',
      'message', 'item_id is required.'
    );
  end if;

  select *
  into v_item
  from public.odyssey_character_equipment_items e
  where e.id = v_item_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_ITEM_NOT_FOUND',
      'item_id', v_item_id
    );
  end if;

  v_has_armor_value := p_payload ? 'armor_value';
  v_has_armor_minor := p_payload ? 'armor_minor';
  v_has_armor_max_minor := p_payload ? 'armor_max_minor';
  v_has_armor_serious := p_payload ? 'armor_serious';
  v_has_armor_max_serious := p_payload ? 'armor_max_serious';
  v_has_armor_critical := p_payload ? 'armor_critical';
  v_has_armor_max_critical := p_payload ? 'armor_max_critical';
  v_has_armor_destroyed := p_payload ? 'armor_destroyed';

  v_new_armor_value := case
    when v_has_armor_value then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_value', '')), '')::integer, v_item.armor_value), 0)
    else v_item.armor_value
  end;

  v_new_armor_max_minor := case
    when v_has_armor_max_minor then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_max_minor', '')), '')::integer, v_item.armor_max_minor), 0)
    else v_item.armor_max_minor
  end;
  v_new_armor_minor := case
    when v_has_armor_minor then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_minor', '')), '')::integer, v_item.armor_minor), 0)
    else v_item.armor_minor
  end;
  if v_new_armor_minor > v_new_armor_max_minor then
    v_new_armor_minor := v_new_armor_max_minor;
  end if;

  v_new_armor_max_serious := case
    when v_has_armor_max_serious then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_max_serious', '')), '')::integer, v_item.armor_max_serious), 0)
    else v_item.armor_max_serious
  end;
  v_new_armor_serious := case
    when v_has_armor_serious then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_serious', '')), '')::integer, v_item.armor_serious), 0)
    else v_item.armor_serious
  end;
  if v_new_armor_serious > v_new_armor_max_serious then
    v_new_armor_serious := v_new_armor_max_serious;
  end if;

  v_new_armor_max_critical := case
    when v_has_armor_max_critical then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_max_critical', '')), '')::integer, v_item.armor_max_critical), 0)
    else v_item.armor_max_critical
  end;
  v_new_armor_critical := case
    when v_has_armor_critical then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_critical', '')), '')::integer, v_item.armor_critical), 0)
    else v_item.armor_critical
  end;
  if v_new_armor_critical > v_new_armor_max_critical then
    v_new_armor_critical := v_new_armor_max_critical;
  end if;

  v_new_armor_destroyed := case
    when v_has_armor_destroyed then coalesce(nullif(trim(coalesce(p_payload->>'armor_destroyed', '')), '')::boolean, false)
    else public.odyssey_equipment_item_is_destroyed(
      v_new_armor_minor,
      v_new_armor_max_minor,
      v_new_armor_serious,
      v_new_armor_max_serious,
      v_new_armor_critical,
      v_new_armor_max_critical
    )
  end;

  v_new_current_charges := case
    when v_has_current_charges then nullif(trim(coalesce(p_payload->>'current_charges', '')), '')::integer
    else v_item.current_charges
  end;
  if v_new_current_charges is not null then
    v_new_current_charges := greatest(v_new_current_charges, 0);
  end if;

  v_new_max_charges := case
    when v_has_max_charges then nullif(trim(coalesce(p_payload->>'max_charges', '')), '')::integer
    else v_item.max_charges
  end;
  if v_new_max_charges is not null then
    v_new_max_charges := greatest(v_new_max_charges, 0);
  end if;
  if v_new_current_charges is not null
    and v_new_max_charges is not null
    and v_new_current_charges > v_new_max_charges then
    v_new_current_charges := v_new_max_charges;
  end if;

  update public.odyssey_character_equipment_items
  set
    custom_name = case when v_has_custom_name then v_custom_name else custom_name end,
    notes = case when v_has_notes then v_notes else notes end,
    sort_order = case when v_has_sort_order then v_sort_order else sort_order end,
    armor_value = v_new_armor_value,
    armor_minor = v_new_armor_minor,
    armor_max_minor = v_new_armor_max_minor,
    armor_serious = v_new_armor_serious,
    armor_max_serious = v_new_armor_max_serious,
    armor_critical = v_new_armor_critical,
    armor_max_critical = v_new_armor_max_critical,
    armor_destroyed = v_new_armor_destroyed,
    current_charges = v_new_current_charges,
    max_charges = v_new_max_charges,
    data = case when v_has_data and v_data is not null then v_data else data end,
    updated_at = timezone('utc', now())
  where id = v_item_id;

  perform public.recompute_character_armor(v_item.character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_item.character_id);

  return jsonb_build_object(
    'ok', true,
    'item', public.odyssey_get_equipment_item_json(v_item_id),
    'armor_summary', public.get_character_armor_summary(v_item.character_id),
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_get_character_body_part_state(
  p_body_part_id uuid
)
returns jsonb
language sql
stable
as $$
  select
    case
      when b.id is null then null
      else jsonb_build_object(
        'id', b.id,
        'character_id', b.character_id,
        'body_part_def_id', b.body_part_def_id,
        'code', coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        'name', coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key),
        'part_key', b.part_key,
        'minor', b.minor,
        'serious', b.serious,
        'critical', b.critical,
        'max_critical', b.max_critical,
        'natural_armor_value', coalesce(b.natural_armor_value, 0),
        'armor_value', b.armor_value,
        'armor_minor', b.armor_minor,
        'armor_max_minor', b.armor_max_minor,
        'armor_serious', b.armor_serious,
        'armor_max_serious', b.armor_max_serious,
        'armor_critical', b.armor_critical,
        'armor_max_critical', b.armor_max_critical,
        'armor_destroyed', b.armor_destroyed,
        'disabled', b.disabled,
        'destroyed', b.destroyed,
        'can_be_targeted', coalesce(d.can_be_targeted, true),
        'aim_difficulty', coalesce(d.aim_difficulty, 0),
        'sort_order', b.sort_order
      )
    end
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.id = p_body_part_id;
$$;

create or replace function public.gm_repair_character_armor(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id_text text := trim(coalesce(p_payload->>'character_id', ''));
  v_character_id uuid := null;
  v_actor text := coalesce(nullif(trim(coalesce(p_payload->>'actor', '')), ''), 'gm');
  v_reason text := coalesce(nullif(trim(coalesce(p_payload->>'reason', '')), ''), 'manual_gm_action');
  v_character public.odyssey_characters%rowtype;
  v_repaired_parts integer := 0;
  v_excluded_parts jsonb := '[]'::jsonb;
  v_excluded_part_codes jsonb := '[]'::jsonb;
  v_recompute jsonb := '{}'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_state_version integer := 0;
  v_encounter_id uuid := null;
  v_scene_id text := '';
  v_log_id uuid := null;
begin
  if v_character_id_text = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_ID_REQUIRED',
      'message', 'Character ID is required.'
    );
  end if;

  begin
    v_character_id := v_character_id_text::uuid;
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_CHARACTER_ID',
        'message', 'Character ID must be a valid UUID.'
      );
  end;

  select *
  into v_character
  from public.odyssey_characters c
  where c.id = v_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character not found.'
    );
  end if;

  with classified_parts as (
    select
      b.id,
      b.sort_order,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as display_name,
      public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      ) as is_excluded
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
  )
  select
    count(*) filter (where not is_excluded),
    coalesce(jsonb_agg(display_name order by sort_order) filter (where is_excluded), '[]'::jsonb),
    coalesce(jsonb_agg(part_code order by sort_order) filter (where is_excluded), '[]'::jsonb)
  into
    v_repaired_parts,
    v_excluded_parts,
    v_excluded_part_codes
  from classified_parts;

  with target_parts as (
    select b.id
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
      and not public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      )
  )
  update public.odyssey_character_equipment_items e
  set
    armor_minor = 0,
    armor_serious = 0,
    armor_critical = 0,
    armor_destroyed = false,
    updated_at = timezone('utc', now())
  where e.character_id = v_character_id
    and e.is_equipped = true
    and e.equipped_body_part_id in (select id from target_parts);

  v_recompute := public.recompute_character_armor(v_character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
  v_state_version := coalesce(
    nullif(jsonb_extract_path_text(v_refresh, 'state_version'), '')::integer,
    nullif(jsonb_extract_path_text(v_refresh, 'combat_state', 'state_version'), '')::integer,
    0
  );

  select
    e.id,
    coalesce(e.scene_id, '')
  into
    v_encounter_id,
    v_scene_id
  from public.odyssey_combat_encounters e
  where e.campaign_id = coalesce(v_character.campaign_id, '')
    and e.room_id = coalesce(v_character.room_id, '')
    and e.status = 'active'
  order by e.updated_at desc, e.created_at desc, e.id desc
  limit 1;

  begin
    insert into public.odyssey_combat_log (
      campaign_id,
      room_id,
      scene_id,
      encounter_id,
      actor_character_id,
      target_character_id,
      event_type,
      message,
      data,
      created_by
    )
    values (
      coalesce(v_character.campaign_id, ''),
      coalesce(v_character.room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      null,
      v_character_id,
      'gm_repair_character_armor',
      'GM repaired all armor parts.',
      jsonb_build_object(
        'action', 'gm_repair_character_armor',
        'character_id', v_character_id,
        'actor', v_actor,
        'reason', v_reason,
        'repaired_parts', v_repaired_parts,
        'excluded_parts', v_excluded_part_codes,
        'armor_refresh', v_recompute
      ),
      v_actor
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, coalesce(v_character.room_id, ''));
  exception
    when others then
      v_log_id := null;
  end;

  return jsonb_build_object(
    'ok', true,
    'action', 'gm_repair_character_armor',
    'character_id', v_character_id,
    'repaired_parts', v_repaired_parts,
    'excluded_parts', v_excluded_parts,
    'state_version', v_state_version,
    'log_id', v_log_id
  );
end;
$$;

create or replace function public.odyssey_apply_resolved_body_damage(
  p_body_part_id uuid,
  p_minor_delta integer,
  p_serious_delta integer,
  p_critical_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_body_part record;
  v_requested_minor integer := greatest(coalesce(p_minor_delta, 0), 0);
  v_requested_serious integer := greatest(coalesce(p_serious_delta, 0), 0);
  v_requested_critical integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_body_minor_delta integer := 0;
  v_body_serious_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_armor_minor_absorbed integer := 0;
  v_armor_serious_absorbed integer := 0;
  v_armor_critical_absorbed integer := 0;
  v_armor_item_updates jsonb := '[]'::jsonb;
  v_armor_result jsonb := '{}'::jsonb;
  v_refresh_result jsonb := '{}'::jsonb;
  v_body_state jsonb := '{}'::jsonb;
  v_next_minor integer := 0;
  v_next_serious integer := 0;
  v_next_critical integer := 0;
  v_next_disabled boolean := false;
  v_next_destroyed boolean := false;
  v_has_body_delta boolean := false;
  v_armor_items_changed boolean := false;
begin
  select
    b.id,
    b.character_id,
    b.minor,
    b.serious,
    b.critical,
    b.max_critical,
    b.disabled,
    b.destroyed
  into v_body_part
  from public.odyssey_character_body_parts b
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'message', 'Body part was not found.',
      'body_part_id', p_body_part_id
    );
  end if;

  if v_requested_minor > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'minor',
      v_requested_minor
    );
    v_armor_minor_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_minor_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_minor - v_armor_minor_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  if v_requested_serious > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'serious',
      v_requested_serious
    );
    v_armor_serious_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_serious_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_serious - v_armor_serious_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  if v_requested_critical > 0 then
    v_armor_result := public.odyssey_apply_equipment_damage_tier(
      p_body_part_id,
      'critical',
      v_requested_critical
    );
    v_armor_critical_absorbed := coalesce(nullif(v_armor_result->>'absorbed', '')::integer, 0);
    v_body_critical_delta := coalesce(
      nullif(v_armor_result->>'remaining', '')::integer,
      greatest(v_requested_critical - v_armor_critical_absorbed, 0)
    );
    v_armor_item_updates := v_armor_item_updates || coalesce(v_armor_result->'updated_items', '[]'::jsonb);
    v_armor_items_changed := v_armor_items_changed or coalesce((v_armor_result->>'items_changed')::boolean, false);
  end if;

  v_has_body_delta :=
    v_body_minor_delta > 0
    or v_body_serious_delta > 0
    or v_body_critical_delta > 0;

  if v_has_body_delta then
    v_next_minor := coalesce(v_body_part.minor, 0) + v_body_minor_delta;
    v_next_serious := coalesce(v_body_part.serious, 0) + v_body_serious_delta;
    v_next_critical := coalesce(v_body_part.critical, 0) + v_body_critical_delta;
    v_next_destroyed := coalesce(v_body_part.destroyed, false)
      or (
        coalesce(v_body_part.max_critical, 0) > 0
        and v_next_critical >= coalesce(v_body_part.max_critical, 0)
      );
    v_next_disabled := coalesce(v_body_part.disabled, false)
      or v_next_critical > 0
      or v_next_destroyed;

    update public.odyssey_character_body_parts
    set
      minor = v_next_minor,
      serious = v_next_serious,
      critical = v_next_critical,
      disabled = v_next_disabled,
      destroyed = v_next_destroyed
    where id = p_body_part_id;

    perform public.odyssey_normalize_body_part_damage(p_body_part_id);
  end if;

  if v_armor_items_changed then
    perform public.recompute_character_armor(v_body_part.character_id);
  end if;

  if v_has_body_delta or v_armor_items_changed then
    v_refresh_result := public.odyssey_refresh_character_combat_state(v_body_part.character_id);
  end if;

  v_body_state := coalesce(public.odyssey_get_character_body_part_state(p_body_part_id), '{}'::jsonb);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_body_part.character_id,
    'body_part_id', p_body_part_id,
    'raw_minor_delta', v_requested_minor,
    'raw_serious_delta', v_requested_serious,
    'raw_critical_delta', v_requested_critical,
    'body_minor_delta', v_body_minor_delta,
    'body_serious_delta', v_body_serious_delta,
    'body_critical_delta', v_body_critical_delta,
    'armor_minor_absorbed', v_armor_minor_absorbed,
    'armor_serious_absorbed', v_armor_serious_absorbed,
    'armor_critical_absorbed', v_armor_critical_absorbed,
    'armor_item_updates', v_armor_item_updates,
    'body_part', v_body_state,
    'target_state', coalesce(v_refresh_result->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_refresh_character_combat_state(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character public.odyssey_characters%rowtype;
  v_existing_state public.odyssey_character_combat_state%rowtype;
  v_rule_sheet jsonb := '{}'::jsonb;
  v_body_summary jsonb := '[]'::jsonb;
  v_equipment_bundle jsonb := '{}'::jsonb;
  v_equipment_summary jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_summary jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
  v_armor_parts jsonb := '[]'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_active_penalties jsonb := '[]'::jsonb;
  v_combat_flags jsonb := '{}'::jsonb;
  v_tracker_minor integer := 0;
  v_tracker_serious integer := 0;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_next_state_version integer := 1;
  v_updated_at timestamptz := timezone('utc', now());
  v_overlay_data jsonb := '{}'::jsonb;
begin
  select *
  into v_character
  from public.odyssey_characters c
  where c.id = p_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id
    );
  end if;

  select *
  into v_existing_state
  from public.odyssey_character_combat_state s
  where s.character_id = p_character_id;

  v_rule_sheet := public.get_character_rule_sheet(p_character_id);
  v_body_summary := coalesce(v_rule_sheet->'body_parts', '[]'::jsonb);
  v_armor_summary := public.get_character_armor_summary(p_character_id);
  v_equipment_bundle := public.get_character_equipment(p_character_id);
  v_equipment_summary := case
    when jsonb_typeof(v_equipment_bundle->'summary') = 'object' then v_equipment_bundle->'summary'
    else '{}'::jsonb
  end;
  v_effective_stats := public.get_effective_character_stats(p_character_id);
  v_effect_summary := coalesce(v_effective_stats->'effect_summary', '{}'::jsonb);
  v_active_effects := coalesce(v_effective_stats->'active_effects', '[]'::jsonb);
  v_active_penalties := coalesce(v_effect_summary->'modifier_rows', '[]'::jsonb);

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'part_key', b.part_key,
          'natural_armor_value', b.natural_armor_value,
          'armor_value', b.armor_value,
          'armor_minor', b.armor_minor,
          'armor_max_minor', b.armor_max_minor,
          'armor_serious', b.armor_serious,
          'armor_max_serious', b.armor_max_serious,
          'armor_critical', b.armor_critical,
          'armor_max_critical', b.armor_max_critical,
          'armor_destroyed', b.armor_destroyed
        )
        order by b.sort_order, b.part_key
      ),
      '[]'::jsonb
    ),
    coalesce(sum(b.minor), 0),
    coalesce(sum(b.serious), 0)
  into
    v_armor_parts,
    v_tracker_minor,
    v_tracker_serious
  from public.odyssey_character_body_parts b
  where b.character_id = p_character_id;

  v_is_alive := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_alive'), '')::boolean, true);
  v_is_conscious := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_conscious'), '')::boolean, true);

  v_armor_summary := jsonb_set(
    coalesce(v_armor_summary, '{}'::jsonb),
    '{parts}',
    v_armor_parts,
    true
  );

  v_combat_flags := jsonb_build_object(
    'helpless', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'helpless'), '')::boolean, false),
    'skip_main_action', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false),
    'skip_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_movement'), '')::boolean, false),
    'consumes_full_turn', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'consumes_full_turn'), '')::boolean, false),
    'suppress_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'suppress_movement'), '')::boolean, false),
    'cannot_leave_cover', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'cannot_leave_cover'), '')::boolean, false),
    'requires_concentration', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'requires_concentration'), '')::boolean, false)
  );

  v_next_state_version := coalesce(v_existing_state.state_version, 0) + 1;
  v_overlay_data := coalesce(v_existing_state.overlay_data, '{}'::jsonb)
    || jsonb_build_object(
      'armor_summary', v_armor_summary,
      'equipment_summary', v_equipment_summary
    );

  insert into public.odyssey_character_combat_state (
    character_id,
    campaign_id,
    room_id,
    body_summary,
    armor_summary,
    equipment_summary,
    active_effects,
    active_penalties,
    effective_stats,
    combat_flags,
    overlay_text,
    overlay_data,
    tracker_minor,
    tracker_serious,
    is_alive,
    is_conscious,
    state_version,
    updated_at
  )
  values (
    p_character_id,
    coalesce(v_character.campaign_id, ''),
    coalesce(v_character.room_id, ''),
    v_body_summary,
    v_armor_summary,
    v_equipment_summary,
    v_active_effects,
    v_active_penalties,
    v_effective_stats,
    v_combat_flags,
    coalesce(v_existing_state.overlay_text, ''),
    v_overlay_data,
    v_tracker_minor,
    v_tracker_serious,
    v_is_alive,
    v_is_conscious,
    v_next_state_version,
    v_updated_at
  )
  on conflict (character_id) do update
  set
    campaign_id = excluded.campaign_id,
    room_id = excluded.room_id,
    body_summary = excluded.body_summary,
    armor_summary = excluded.armor_summary,
    equipment_summary = excluded.equipment_summary,
    active_effects = excluded.active_effects,
    active_penalties = excluded.active_penalties,
    effective_stats = excluded.effective_stats,
    combat_flags = excluded.combat_flags,
    overlay_text = excluded.overlay_text,
    overlay_data = excluded.overlay_data,
    tracker_minor = excluded.tracker_minor,
    tracker_serious = excluded.tracker_serious,
    is_alive = excluded.is_alive,
    is_conscious = excluded.is_conscious,
    state_version = excluded.state_version,
    updated_at = excluded.updated_at;

  update public.odyssey_characters
  set active_combat_state_version = v_next_state_version
  where id = p_character_id;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'state_version', v_next_state_version,
    'combat_state',
      jsonb_build_object(
        'character_id', p_character_id,
        'character_key', v_character.character_key,
        'campaign_id', coalesce(v_character.campaign_id, ''),
        'room_id', coalesce(v_character.room_id, ''),
        'body_summary', v_body_summary,
        'armor_summary', v_armor_summary,
        'equipment_summary', v_equipment_summary,
        'active_effects', v_active_effects,
        'active_penalties', v_active_penalties,
        'effective_stats', v_effective_stats,
        'combat_flags', v_combat_flags,
        'overlay_text', coalesce(v_existing_state.overlay_text, ''),
        'overlay_data', v_overlay_data,
        'tracker_minor', v_tracker_minor,
        'tracker_serious', v_tracker_serious,
        'is_alive', v_is_alive,
        'is_conscious', v_is_conscious,
        'state_version', v_next_state_version,
        'updated_at', v_updated_at
      )
  );
end;
$$;

create or replace function public.get_character_rule_sheet(
  p_character_id uuid
)
returns jsonb
language sql
stable
as $$
  with selected_character as (
    select
      c.id,
      c.character_key,
      c.character_bucket,
      c.enabled,
      c.owner_player_id,
      c.owner_player_name,
      c.resources,
      coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key) as character_name
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  ),
  effect_summary as (
    select public.get_character_effect_summary(p_character_id) as effect_summary
    from selected_character
  ),
  progression as (
    select
      coalesce(p.development_points, 0) as development_points,
      coalesce(p.lifetime_points_granted, 0) as lifetime_points_granted,
      coalesce(p.lifetime_points_spent, 0) as lifetime_points_spent
    from selected_character c
    left join public.odyssey_character_progression p on p.character_id = c.id
  )
  select jsonb_build_object(
    'character',
      jsonb_build_object(
        'id', c.id,
        'character_key', c.character_key,
        'character_bucket', c.character_bucket,
        'name', c.character_name,
        'enabled', c.enabled,
        'owner_player_id', c.owner_player_id,
        'owner_player_name', c.owner_player_name,
        'resources', c.resources
      ),
    'progression',
      jsonb_build_object(
        'development_points', coalesce((select development_points from progression), 0),
        'lifetime_points_granted', coalesce((select lifetime_points_granted from progression), 0),
        'lifetime_points_spent', coalesce((select lifetime_points_spent from progression), 0)
      ),
    'attributes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', d.id,
              'attribute_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'value', coalesce(a.value, d.default_value, 0),
              'base_value', coalesce(a.value, d.default_value, 0),
              'effect_modifier',
                case
                  when d.code is null then 0
                  else coalesce(
                    nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', d.code), '')::integer,
                    0
                  )
                end,
              'effective_value',
                coalesce(a.value, d.default_value, 0)
                + case
                    when d.code is null then 0
                    else coalesce(
                      nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', d.code), '')::integer,
                      0
                    )
                  end,
              'default_value', d.default_value,
              'max_value', d.max_value,
              'cost_per_level', d.cost_per_level,
              'description', d.description,
              'sort_order', d.sort_order,
              'is_custom', d.is_custom
            )
            order by d.sort_order, d.name
          )
          from public.odyssey_attribute_defs d
          left join public.odyssey_character_attributes a
            on a.attribute_def_id = d.id
           and a.character_id = c.id
          cross join effect_summary
        ),
        '[]'::jsonb
      ),
    'skills',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', skill_state.skill_def_id,
              'character_skill_id', skill_state.character_skill_id,
              'skill_def_id', skill_state.skill_def_id,
              'code', skill_state.skill_code,
              'name', skill_state.skill_name,
              'custom_name', skill_state.custom_name,
              'category', skill_state.skill_category,
              'level', skill_state.purchased_level,
              'purchased_level', skill_state.purchased_level,
              'base_effective_level', skill_state.base_effective_level,
              'effect_level_modifier', skill_state.effect_level_modifier,
              'effective_level', skill_state.effective_level,
              'skill_bonus', skill_state.skill_bonus,
              'effect_skill_bonus', skill_state.effect_skill_bonus,
              'max_level', skill_state.max_level,
              'is_passive', skill_state.is_passive,
              'is_trained', skill_state.is_trained,
              'requirements_met', skill_state.current_level_requirements_met,
              'main_attribute',
                case
                  when skill_state.main_attribute_def_id is null then 'null'::jsonb
                  else jsonb_build_object(
                    'id', skill_state.main_attribute_def_id,
                    'code', skill_state.main_attribute_code,
                    'name', skill_state.main_attribute_name,
                    'base_value', skill_state.main_base_value,
                    'effect_modifier', skill_state.main_effect_modifier,
                    'effective_value', skill_state.main_effective_value
                  )
                end,
              'secondary_attribute',
                case
                  when skill_state.secondary_attribute_def_id is null then 'null'::jsonb
                  else jsonb_build_object(
                    'id', skill_state.secondary_attribute_def_id,
                    'code', skill_state.secondary_attribute_code,
                    'name', skill_state.secondary_attribute_name,
                    'base_value', skill_state.secondary_base_value,
                    'effect_modifier', skill_state.secondary_effect_modifier,
                    'effective_value', skill_state.secondary_effective_value
                  )
                end,
              'governing_attribute', governing_attr.code,
              'tags', skill_state.skill_tags,
              'description', skill_state.description,
              'notes', skill_state.notes,
              'next_level',
                case
                  when skill_state.purchased_level >= skill_state.max_level then 'null'::jsonb
                  else jsonb_build_object(
                    'target_level', skill_state.purchased_level + 1,
                    'cost', next_purchase_req.development_point_cost,
                    'advancement_mode', next_purchase_req.advancement_mode,
                    'main_attribute_required', next_purchase_req.main_attribute_required,
                    'secondary_attribute_required', next_purchase_req.secondary_attribute_required
                  )
                end
            )
            order by skill_state.skill_category, skill_state.sort_order, skill_state.skill_name
          )
          from public.odyssey_get_effective_character_skill_states(c.id) skill_state
          left join public.odyssey_attribute_defs governing_attr on governing_attr.id = skill_state.governing_attribute_def_id
          left join public.odyssey_skill_level_requirements next_purchase_req
            on next_purchase_req.skill_def_id = skill_state.skill_def_id
           and next_purchase_req.level = case
             when skill_state.purchased_level >= skill_state.max_level then null
             else skill_state.purchased_level + 1
           end
        ),
        '[]'::jsonb
      ),
    'perks',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', owned.id,
              'perk_def_id', perk.id,
              'code', perk.code,
              'name', perk.name,
              'skill_code', skill.code,
              'required_skill_level', perk.required_skill_level,
              'effect_type', perk.effect_type,
              'effect_data', perk.effect_data,
              'tags', perk.tags,
              'notes', owned.notes,
              'acquired_at', owned.acquired_at
            )
            order by perk.name
          )
          from public.odyssey_character_perks owned
          join public.odyssey_perk_defs perk on perk.id = owned.perk_def_id
          left join public.odyssey_skill_defs skill on skill.id = perk.skill_def_id
          where owned.character_id = c.id
        ),
        '[]'::jsonb
      ),
    'body_parts',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', b.id,
              'body_part_def_id', d.id,
              'code', d.code,
              'name', coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key),
              'custom_name', b.custom_name,
              'part_key', b.part_key,
              'minor', b.minor,
              'serious', b.serious,
              'critical', b.critical,
              'max_critical', b.max_critical,
              'armor_value', b.armor_value,
              'armor_minor', b.armor_minor,
              'armor_max_minor', b.armor_max_minor,
              'armor_serious', b.armor_serious,
              'armor_max_serious', b.armor_max_serious,
              'armor_critical', b.armor_critical,
              'armor_max_critical', b.armor_max_critical,
              'armor_destroyed', b.armor_destroyed,
              'disabled', b.disabled,
              'destroyed', b.destroyed,
              'can_be_targeted', coalesce(d.can_be_targeted, true),
              'aim_difficulty', coalesce(d.aim_difficulty, 0),
              'serious_counts_as_critical', coalesce(d.serious_counts_as_critical, false),
              'category', d.category,
              'tags', coalesce(d.tags, '[]'::jsonb),
              'sort_order', b.sort_order
            )
            order by b.sort_order, b.part_key
          )
          from public.odyssey_character_body_parts b
          left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
          where b.character_id = c.id
        ),
        '[]'::jsonb
      )
  )
  from selected_character c;
$$;

create or replace function public.odyssey_creator_build_equipment_model_bundle(
  p_equipment_model_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_model jsonb := null;
  v_ability_links jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'id', m.id,
    'code', m.code,
    'name', m.name,
    'item_type', m.item_type,
    'description', m.description,
    'armor_value', m.armor_value,
    'armor_max_minor', m.armor_max_minor,
    'armor_max_serious', m.armor_max_serious,
    'armor_max_critical', m.armor_max_critical,
    'default_body_part_code', m.default_body_part_code,
    'can_equip', m.can_equip,
    'can_equip_to_body_part', m.can_equip_to_body_part,
    'effect_data', coalesce(m.effect_data, '{}'::jsonb),
    'flags', coalesce(m.flags, '{}'::jsonb),
    'tags', coalesce(m.tags, '[]'::jsonb),
    'is_custom', m.is_custom,
    'sort_order', m.sort_order,
    'created_at', m.created_at,
    'updated_at', m.updated_at
  )
  into v_model
  from public.odyssey_equipment_model_defs m
  where m.id = p_equipment_model_id
    and m.item_type in ('armor', 'shield');

  if v_model is null then
    return public.odyssey_creator_error(
      'ARMOR_MODEL_NOT_FOUND',
      'Armor model was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown armor model id.'))
    );
  end if;

  select coalesce(
    jsonb_agg(item order by sort_order, ability_name, ability_code),
    '[]'::jsonb
  )
  into v_ability_links
  from (
    select
      link.sort_order,
      ability.name as ability_name,
      ability.code as ability_code,
      jsonb_build_object(
        'id', link.id,
        'ability_def_id', link.ability_def_id,
        'ability_code', ability.code,
        'ability_name', ability.name,
        'ability_kind', ability.ability_kind,
        'source_type', ability.source_type,
        'grant_mode', link.grant_mode,
        'is_enabled', link.is_enabled,
        'sort_order', link.sort_order,
        'data', coalesce(link.data, '{}'::jsonb)
      ) as item
    from public.odyssey_equipment_model_abilities link
    join public.odyssey_ability_defs ability on ability.id = link.ability_def_id
    where link.equipment_model_id = p_equipment_model_id
  ) rows;

  return jsonb_build_object(
    'ok', true,
    'armor_model', v_model,
    'ability_links', v_ability_links
  );
end;
$$;

create or replace function public.creator_list_armor_models(
  p_search text default null
)
returns jsonb
language sql
stable
as $$
  with search_input as (
    select nullif(trim(coalesce(p_search, '')), '') as search_text
  ),
  filtered as (
    select
      model.id,
      model.code,
      model.name,
      model.sort_order,
      model.item_type,
      model.armor_value,
      model.armor_max_minor,
      model.armor_max_serious,
      model.armor_max_critical,
      model.default_body_part_code,
      coalesce(model.tags, '[]'::jsonb) as tags
    from public.odyssey_equipment_model_defs model
    cross join search_input
    where model.item_type in ('armor', 'shield')
      and (
        search_input.search_text is null
        or model.code ilike '%' || search_input.search_text || '%'
        or model.name ilike '%' || search_input.search_text || '%'
        or model.item_type ilike '%' || search_input.search_text || '%'
        or model.tags::text ilike '%' || search_input.search_text || '%'
      )
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'item_type', item_type,
            'armor_value', armor_value,
            'armor_max_minor', armor_max_minor,
            'armor_max_serious', armor_max_serious,
            'armor_max_critical', armor_max_critical,
            'default_body_part_code', default_body_part_code,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_upsert_armor_model(
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
  if v_item_type not in ('armor', 'shield') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'item_type must be armor or shield.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'Use armor or shield.'))
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
        'ARMOR_MODEL_NOT_FOUND',
        'Armor model was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown armor model id.'))
      );
    end if;
  else
    select model.id, model.item_type
    into v_entity_id, v_existing_item_type
    from public.odyssey_equipment_model_defs model
    where model.code = v_code
    limit 1;
  end if;

  if v_entity_id is not null and v_existing_item_type not in ('armor', 'shield') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Armor module can edit only armor or shield equipment models.',
      jsonb_build_array(jsonb_build_object('field', 'item_type', 'message', 'The selected equipment model belongs to another module.'))
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
      'Armor model code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate armor model code.'))
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
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(v_ability_links)
  loop
    v_link_id := nullif(trim(coalesce(v_entry->>'id', '')), '')::uuid;
    v_ability_id := nullif(trim(coalesce(v_entry->>'ability_def_id', '')), '')::uuid;
    v_grant_mode := lower(trim(coalesce(v_entry->>'grant_mode', 'grant')));
    v_is_enabled := coalesce(nullif(trim(coalesce(v_entry->>'is_enabled', '')), '')::boolean, true);
    v_link_sort := coalesce(nullif(trim(coalesce(v_entry->>'sort_order', '')), '')::integer, 0);
    v_link_data := public.odyssey_creator_normalize_json_object(v_entry->'data');

    if v_ability_id is null or not exists (
      select 1
      from public.odyssey_ability_defs ability
      where ability.id = v_ability_id
    ) then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'Each ability link must reference a valid ability_def_id.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Unknown ability_def_id in armor model link.'))
      );
    end if;

    if v_grant_mode not in ('grant', 'unlock', 'passive') then
      return public.odyssey_creator_error(
        'VALIDATION_ERROR',
        'grant_mode is invalid.',
        jsonb_build_array(jsonb_build_object('field', 'ability_links', 'message', 'Use grant, unlock, or passive.'))
      );
    end if;

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
        ability_def_id = v_ability_id,
        grant_mode = v_grant_mode,
        is_enabled = v_is_enabled,
        sort_order = v_link_sort,
        data = v_link_data
      where id = v_link_id
        and equipment_model_id = v_entity_id;
    end if;

    v_processed_link_ids := array_append(v_processed_link_ids, v_link_id);
  end loop;

  delete from public.odyssey_equipment_model_abilities link
  where link.equipment_model_id = v_entity_id
    and not (link.id = any (coalesce(v_processed_link_ids, '{}'::uuid[])));

  v_result := public.creator_get_armor_model(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', coalesce(v_result->'armor_model', '{}'::jsonb),
    'ability_links', coalesce(v_result->'ability_links', '[]'::jsonb),
    'warnings', '[]'::jsonb
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
    and p.proname = 'odyssey_perform_weapon_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_weapon_attack(jsonb) was not found.';
  end if;

  if position($needle$v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$needle$ in v_function_def) = 0 then
    raise exception 'Could not find armor delta declarations in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$old$,
    $new$v_armor_minor_delta integer := 0;
  v_armor_serious_delta integer := 0;
  v_armor_critical_delta integer := 0;
  v_body_minor_delta integer := 0;
  v_body_serious_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$new$
  );

  if position($needle$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
        v_body_changed := true;
        v_armor_items_changed := false;
      end if;
    end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find resolved damage block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
        v_body_changed := true;
        v_armor_items_changed := false;
      end if;
    end if;$old$,
    $new$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_minor_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_minor_absorbed'), '')::integer, 0);
        v_armor_serious_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_serious_absorbed'), '')::integer, 0);
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_minor_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_minor_delta'), '')::integer, 0);
        v_body_serious_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_serious_delta'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
        v_body_changed := (v_body_minor_delta > 0 or v_body_serious_delta > 0 or v_body_critical_delta > 0);
        v_armor_items_changed := (
          v_armor_minor_delta > 0
          or v_armor_serious_delta > 0
          or v_armor_critical_delta > 0
        );
      end if;
    end if;$new$
  );

  if position($needle$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used', case when v_attack_type = 'ranged' then v_armor_pierce else 0 end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates,
        'melee_strength_bonus', v_melee_strength_bonus
      ),$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage response block in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used', case when v_attack_type = 'ranged' then v_armor_pierce else 0 end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates,
        'melee_strength_bonus', v_melee_strength_bonus
      ),$old$,
    $new$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_body_minor_delta,
        'body_serious_delta', v_body_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used', case when v_attack_type = 'ranged' then v_armor_pierce else 0 end,
        'armor_minor_delta', v_armor_minor_delta,
        'armor_minor_absorbed', v_armor_minor_delta,
        'armor_serious_delta', v_armor_serious_delta,
        'armor_serious_absorbed', v_armor_serious_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates,
        'melee_strength_bonus', v_melee_strength_bonus
      ),$new$
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
    and p.proname = 'odyssey_perform_ability_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_ability_attack(jsonb) was not found.';
  end if;

  if position($needle$v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$needle$ in v_function_def) = 0 then
    raise exception 'Could not find armor delta declarations in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$old$,
    $new$v_armor_minor_delta integer := 0;
  v_armor_serious_delta integer := 0;
  v_armor_critical_delta integer := 0;
  v_body_minor_delta integer := 0;
  v_body_serious_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';$new$
  );

  if position($needle$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
      end if;
    end if;$needle$ in v_function_def) = 0 then
    raise exception 'Could not find resolved damage block in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
      end if;
    end if;$old$,
    $new$if v_minor_delta > 0 or v_serious_delta > 0 or v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_resolved_body_damage(
        v_target_part.id,
        v_minor_delta,
        v_serious_delta,
        v_critical_delta
      );

      if coalesce((v_armor_damage_json->>'ok')::boolean, false) = false then
        v_error_code := coalesce(v_armor_damage_json->>'error', 'DAMAGE_APPLY_FAILED');
        v_error_message := coalesce(v_armor_damage_json->>'message', 'Unable to apply damage.');
      else
        v_armor_minor_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_minor_absorbed'), '')::integer, 0);
        v_armor_serious_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_serious_absorbed'), '')::integer, 0);
        v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'armor_critical_absorbed'), '')::integer, 0);
        v_body_minor_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_minor_delta'), '')::integer, 0);
        v_body_serious_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_serious_delta'), '')::integer, 0);
        v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'body_critical_delta'), '')::integer, 0);
        v_armor_item_updates := coalesce(v_armor_damage_json->'armor_item_updates', '[]'::jsonb);
      end if;
    end if;$new$
  );

  if position($needle$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates
      ),$needle$ in v_function_def) = 0 then
    raise exception 'Could not find damage response block in public.odyssey_perform_ability_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    $old$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_minor_delta,
        'body_serious_delta', v_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates
      ),$old$,
    $new$'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'raw_minor_delta', v_minor_delta,
        'raw_serious_delta', v_serious_delta,
        'raw_critical_delta', v_critical_delta,
        'body_minor_delta', v_body_minor_delta,
        'body_serious_delta', v_body_serious_delta,
        'body_critical_delta', v_body_critical_delta,
        'armor_value_used', v_raw_armor_value,
        'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,
        'armor_minor_delta', v_armor_minor_delta,
        'armor_minor_absorbed', v_armor_minor_delta,
        'armor_serious_delta', v_armor_serious_delta,
        'armor_serious_absorbed', v_armor_serious_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'armor_critical_absorbed', v_armor_critical_delta,
        'armor_item_updates', v_armor_item_updates
      ),$new$
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

grant execute on function public.odyssey_equipment_item_has_remaining_armor_capacity(integer, integer, integer, integer, integer, integer) to anon, authenticated;
grant execute on function public.odyssey_equipment_item_is_destroyed(integer, integer, integer, integer, integer, integer) to anon, authenticated;
grant execute on function public.odyssey_apply_equipment_damage_tier(uuid, text, integer) to anon, authenticated;
