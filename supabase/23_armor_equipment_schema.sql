create extension if not exists pgcrypto;

alter table public.odyssey_character_body_parts
  add column if not exists natural_armor_value integer not null default 0;

alter table public.odyssey_character_body_parts
  add column if not exists armor_critical integer not null default 0,
  add column if not exists armor_max_critical integer not null default 0,
  add column if not exists armor_destroyed boolean not null default false;

alter table public.odyssey_character_body_parts
  drop constraint if exists odyssey_character_body_parts_natural_armor_value_check;

alter table public.odyssey_character_body_parts
  add constraint odyssey_character_body_parts_natural_armor_value_check
  check (natural_armor_value >= 0);

alter table public.odyssey_character_body_parts
  drop column if exists armor_item_id;

alter table public.odyssey_character_combat_state
  add column if not exists equipment_summary jsonb not null default '{}'::jsonb;

create table if not exists public.odyssey_armor_class_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  min_total_armor integer not null default 0,
  max_total_armor integer null,
  required_skill_code text null,
  trained_penalties jsonb not null default '{}'::jsonb check (jsonb_typeof(trained_penalties) = 'object'),
  untrained_penalties jsonb not null default '{}'::jsonb check (jsonb_typeof(untrained_penalties) = 'object'),
  description text not null default '',
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_equipment_model_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  item_type text not null check (item_type in ('armor', 'shield', 'special_protection', 'device', 'implant', 'prosthetic', 'custom')),
  description text not null default '',
  armor_value integer not null default 0 check (armor_value >= 0),
  armor_max_critical integer not null default 0 check (armor_max_critical >= 0),
  default_body_part_code text null,
  can_equip boolean not null default true,
  can_equip_to_body_part boolean not null default true,
  effect_data jsonb not null default '{}'::jsonb check (jsonb_typeof(effect_data) = 'object'),
  flags jsonb not null default '{}'::jsonb check (jsonb_typeof(flags) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_equipment_items (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  equipment_model_id uuid not null references public.odyssey_equipment_model_defs(id) on delete restrict,
  equipped_body_part_id uuid null references public.odyssey_character_body_parts(id) on delete set null,
  custom_name text null,
  is_equipped boolean not null default false,
  armor_value integer not null default 0 check (armor_value >= 0),
  armor_critical integer not null default 0 check (armor_critical >= 0),
  armor_max_critical integer not null default 0 check (armor_max_critical >= 0),
  armor_destroyed boolean not null default false,
  current_charges integer null check (current_charges is null or current_charges >= 0),
  max_charges integer null check (max_charges is null or max_charges >= 0),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_armor_class_defs_sort_idx
  on public.odyssey_armor_class_defs (sort_order, min_total_armor);

create index if not exists odyssey_equipment_model_defs_type_idx
  on public.odyssey_equipment_model_defs (item_type, sort_order);

create index if not exists odyssey_character_equipment_items_character_idx
  on public.odyssey_character_equipment_items (character_id, sort_order, created_at);

create index if not exists odyssey_character_equipment_items_equipped_body_part_idx
  on public.odyssey_character_equipment_items (equipped_body_part_id, is_equipped);

alter table public.odyssey_armor_class_defs enable row level security;
alter table public.odyssey_equipment_model_defs enable row level security;
alter table public.odyssey_character_equipment_items enable row level security;

drop policy if exists "odyssey_armor_class_defs_full_access" on public.odyssey_armor_class_defs;
create policy "odyssey_armor_class_defs_full_access"
on public.odyssey_armor_class_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_equipment_model_defs_full_access" on public.odyssey_equipment_model_defs;
create policy "odyssey_equipment_model_defs_full_access"
on public.odyssey_equipment_model_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_equipment_items_full_access" on public.odyssey_character_equipment_items;
create policy "odyssey_character_equipment_items_full_access"
on public.odyssey_character_equipment_items
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_armor_class_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_equipment_model_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_equipment_items to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_armor_class_defs on public.odyssey_armor_class_defs;
create trigger odyssey_touch_updated_at_armor_class_defs
before update on public.odyssey_armor_class_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_equipment_model_defs on public.odyssey_equipment_model_defs;
create trigger odyssey_touch_updated_at_equipment_model_defs
before update on public.odyssey_equipment_model_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_equipment_items on public.odyssey_character_equipment_items;
create trigger odyssey_touch_updated_at_character_equipment_items
before update on public.odyssey_character_equipment_items
for each row
execute function public.odyssey_touch_updated_at();

create or replace function public.odyssey_normalize_part_code(
  p_value text
)
returns text
language sql
immutable
as $$
  select regexp_replace(
    regexp_replace(lower(trim(coalesce(p_value, ''))), '[^a-z0-9]+', '_', 'g'),
    '(^_+|_+$)',
    '',
    'g'
  );
$$;

create or replace function public.odyssey_resolve_body_part_code(
  p_part_key text,
  p_body_part_def_code text
)
returns text
language sql
immutable
as $$
  select coalesce(
    nullif(trim(coalesce(p_body_part_def_code, '')), ''),
    public.odyssey_normalize_part_code(p_part_key)
  );
$$;

create or replace function public.odyssey_get_armor_class(
  p_total_armor_value integer
)
returns text
language sql
stable
as $$
  select coalesce(
    (
      select d.code
      from public.odyssey_armor_class_defs d
      where greatest(coalesce(p_total_armor_value, 0), 0) >= d.min_total_armor
        and (d.max_total_armor is null or greatest(coalesce(p_total_armor_value, 0), 0) <= d.max_total_armor)
      order by d.sort_order, d.min_total_armor desc, d.code
      limit 1
    ),
    'none'
  );
$$;

create or replace function public.odyssey_get_armor_class_definition(
  p_total_armor_value integer
)
returns jsonb
language sql
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'id', d.id,
        'code', d.code,
        'name', d.name,
        'min_total_armor', d.min_total_armor,
        'max_total_armor', d.max_total_armor,
        'required_skill_code', d.required_skill_code,
        'trained_penalties', d.trained_penalties,
        'untrained_penalties', d.untrained_penalties,
        'description', d.description,
        'tags', d.tags,
        'sort_order', d.sort_order
      )
      from public.odyssey_armor_class_defs d
      where greatest(coalesce(p_total_armor_value, 0), 0) >= d.min_total_armor
        and (d.max_total_armor is null or greatest(coalesce(p_total_armor_value, 0), 0) <= d.max_total_armor)
      order by d.sort_order, d.min_total_armor desc, d.code
      limit 1
    ),
    jsonb_build_object(
      'id', null,
      'code', 'none',
      'name', 'None',
      'min_total_armor', 0,
      'max_total_armor', null,
      'required_skill_code', null,
      'trained_penalties', '{}'::jsonb,
      'untrained_penalties', '{}'::jsonb,
      'description', '',
      'tags', '[]'::jsonb,
      'sort_order', 0
    )
  );
$$;

create or replace function public.odyssey_build_armor_penalty_effect_data(
  p_penalty_profile jsonb
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_profile jsonb := case
    when jsonb_typeof(p_penalty_profile) = 'object' then p_penalty_profile
    else '{}'::jsonb
  end;
  v_modifiers jsonb := '[]'::jsonb;
  v_flags jsonb := case
    when jsonb_typeof(v_profile->'flags') = 'object' then v_profile->'flags'
    else '{}'::jsonb
  end;
  v_entry record;
  v_value integer := 0;
  v_bool boolean := false;
begin
  if jsonb_typeof(v_profile->'attribute_modifiers') = 'object' then
    for v_entry in
      select key, value
      from jsonb_each(v_profile->'attribute_modifiers')
    loop
      v_value := coalesce(nullif(trim(v_entry.value #>> '{}'), '')::integer, 0);
      v_modifiers := v_modifiers || jsonb_build_array(
        jsonb_build_object(
          'target', 'attribute',
          'attribute', lower(trim(v_entry.key)),
          'value', v_value
        )
      );
    end loop;
  end if;

  if jsonb_typeof(v_profile->'skill_modifiers') = 'object' then
    for v_entry in
      select key, value
      from jsonb_each(v_profile->'skill_modifiers')
    loop
      v_value := coalesce(nullif(trim(v_entry.value #>> '{}'), '')::integer, 0);
      v_modifiers := v_modifiers || jsonb_build_array(
        jsonb_build_object(
          'target', 'skill',
          'skill_code', lower(trim(v_entry.key)),
          'value', v_value
        )
      );
    end loop;
  end if;

  if v_profile ? 'movement_m' then
    v_value := coalesce(nullif(trim(v_profile->>'movement_m'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'movement_m', 'value', v_value)
    );
  end if;

  if v_profile ? 'parry_skill_level_modifier' then
    v_value := coalesce(nullif(trim(v_profile->>'parry_skill_level_modifier'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'skill', 'skill_code', 'parry', 'value', v_value)
    );
  end if;

  if v_profile ? 'attack_accuracy' then
    v_value := coalesce(nullif(trim(v_profile->>'attack_accuracy'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'attack_accuracy', 'value', v_value)
    );
  end if;

  if v_profile ? 'defense' then
    v_value := coalesce(nullif(trim(v_profile->>'defense'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'defense', 'value', v_value)
    );
  end if;

  if v_profile ? 'damage' then
    v_value := coalesce(nullif(trim(v_profile->>'damage'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'damage', 'value', v_value)
    );
  end if;

  if v_profile ? 'armor' then
    v_value := coalesce(nullif(trim(v_profile->>'armor'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'armor', 'value', v_value)
    );
  end if;

  if v_profile ? 'action_count' then
    v_value := coalesce(nullif(trim(v_profile->>'action_count'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'action_count', 'value', v_value)
    );
  end if;

  if v_profile ? 'concentration_slots' then
    v_value := coalesce(nullif(trim(v_profile->>'concentration_slots'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'concentration_slots', 'value', v_value)
    );
  end if;

  if v_profile ? 'aim_difficulty' then
    v_value := coalesce(nullif(trim(v_profile->>'aim_difficulty'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'aim_difficulty', 'value', v_value)
    );
  end if;

  if v_profile ? 'range' then
    v_value := coalesce(nullif(trim(v_profile->>'range'), '')::integer, 0);
    v_modifiers := v_modifiers || jsonb_build_array(
      jsonb_build_object('target', 'range', 'value', v_value)
    );
  end if;

  if v_profile ? 'stealth_auto_fail' then
    v_bool := coalesce(nullif(trim(v_profile->>'stealth_auto_fail'), '')::boolean, false);
    v_flags := v_flags || jsonb_build_object('stealth_auto_fail', v_bool);
  end if;

  if v_profile ? 'standing_up_costs_action_and_movement' then
    v_bool := coalesce(nullif(trim(v_profile->>'standing_up_costs_action_and_movement'), '')::boolean, false);
    v_flags := v_flags || jsonb_build_object('standing_up_costs_action_and_movement', v_bool);
  end if;

  return jsonb_build_object(
    'modifiers', v_modifiers,
    'flags', v_flags
  );
end;
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
      e.id,
      e.armor_critical,
      e.armor_max_critical,
      e.is_equipped,
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
    coalesce(bool_or(body_part_code = 'head' and coalesce(armor_critical, 0) < coalesce(armor_max_critical, 0)), false),
    coalesce(bool_or(body_part_code = 'torso' and coalesce(armor_critical, 0) < coalesce(armor_max_critical, 0)), false),
    coalesce(
      bool_or(
        coalesce(armor_critical, 0) < coalesce(armor_max_critical, 0)
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
      coalesce(sum(coalesce(e.armor_value, 0)), 0)::integer as equipped_armor_value,
      coalesce(sum(coalesce(e.armor_critical, 0)), 0)::integer as armor_critical,
      coalesce(sum(coalesce(e.armor_max_critical, 0)), 0)::integer as armor_max_critical,
      count(*)::integer as item_count,
      (count(*) filter (
        where coalesce(e.armor_max_critical, 0) > coalesce(e.armor_critical, 0)
      ))::integer as remaining_capacity_count
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
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code
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
        'equipment_model_id', s.equipment_model_id,
        'code', s.equipment_model_code,
        'item_type', s.item_type,
        'custom_name', s.custom_name,
        'name', coalesce(nullif(trim(s.custom_name), ''), s.equipment_model_name),
        'is_equipped', s.is_equipped,
        'equipped_body_part_id', s.equipped_body_part_id,
        'equipped_body_part_code', coalesce(s.body_part_code, ''),
        'equipped_body_part_name', s.body_part_name,
        'armor_value', s.armor_value,
        'armor_critical', s.armor_critical,
        'armor_max_critical', s.armor_max_critical,
        'armor_destroyed', s.armor_destroyed,
        'current_charges', s.current_charges,
        'max_charges', s.max_charges,
        'data', s.data,
        'effect_data', coalesce(s.effect_data, '{}'::jsonb),
        'flags', coalesce(s.model_flags, '{}'::jsonb),
        'tags', coalesce(s.tags, '[]'::jsonb),
        'default_body_part_code', s.default_body_part_code,
        'can_equip', s.can_equip,
        'can_equip_to_body_part', s.can_equip_to_body_part,
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
      m.default_body_part_code,
      m.can_equip,
      m.can_equip_to_body_part,
      m.effect_data,
      m.flags as model_flags,
      m.tags,
      b.part_key,
      coalesce(nullif(trim(b.custom_name), ''), body_def.name, b.part_key) as body_part_name,
      public.odyssey_resolve_body_part_code(b.part_key, body_def.code) as body_part_code
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
      jsonb_build_object(
        'id', id,
        'character_id', character_id,
        'equipment_model_id', equipment_model_id,
        'code', equipment_model_code,
        'item_type', item_type,
        'custom_name', custom_name,
        'name', coalesce(nullif(trim(custom_name), ''), equipment_model_name),
        'is_equipped', is_equipped,
        'equipped_body_part_id', equipped_body_part_id,
        'equipped_body_part_code', coalesce(body_part_code, ''),
        'equipped_body_part_name', body_part_name,
        'armor_value', armor_value,
        'armor_critical', armor_critical,
        'armor_max_critical', armor_max_critical,
        'armor_destroyed', armor_destroyed,
        'current_charges', current_charges,
        'max_charges', max_charges,
        'data', data,
        'effect_data', coalesce(effect_data, '{}'::jsonb),
        'flags', coalesce(model_flags, '{}'::jsonb),
        'tags', coalesce(tags, '[]'::jsonb),
        'default_body_part_code', default_body_part_code,
        'can_equip', can_equip,
        'can_equip_to_body_part', can_equip_to_body_part,
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
      'equipped_armor_value_total', coalesce((sum(coalesce((item_payload->>'armor_value')::integer, 0)) filter (where is_equipped and has_body_part))::integer, 0)
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
begin
  select *
  into v_item
  from public.odyssey_character_equipment_items e
  where e.id = p_item_id;

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
  where b.id = p_body_part_id;

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

create or replace function public.unequip_character_equipment_item(
  p_item_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_item public.odyssey_character_equipment_items%rowtype;
  v_refresh jsonb := '{}'::jsonb;
begin
  select *
  into v_item
  from public.odyssey_character_equipment_items e
  where e.id = p_item_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EQUIPMENT_ITEM_NOT_FOUND',
      'item_id', p_item_id
    );
  end if;

  update public.odyssey_character_equipment_items
  set
    is_equipped = false,
    equipped_body_part_id = null,
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

create or replace function public.update_character_equipment_item(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_item_id uuid := nullif(trim(coalesce(p_payload->>'item_id', '')), '')::uuid;
  v_item public.odyssey_character_equipment_items%rowtype;
  v_custom_name text;
  v_has_custom_name boolean := false;
  v_has_armor_value boolean := false;
  v_has_armor_critical boolean := false;
  v_has_armor_max_critical boolean := false;
  v_has_armor_destroyed boolean := false;
  v_has_current_charges boolean := false;
  v_has_max_charges boolean := false;
  v_has_notes boolean := false;
  v_has_data boolean := false;
  v_new_armor_value integer;
  v_new_armor_critical integer;
  v_new_armor_max_critical integer;
  v_new_armor_destroyed boolean;
  v_new_current_charges integer;
  v_new_max_charges integer;
  v_new_data jsonb;
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

  v_has_custom_name := p_payload ? 'custom_name';
  v_has_armor_value := p_payload ? 'armor_value';
  v_has_armor_critical := p_payload ? 'armor_critical';
  v_has_armor_max_critical := p_payload ? 'armor_max_critical';
  v_has_armor_destroyed := p_payload ? 'armor_destroyed';
  v_has_current_charges := p_payload ? 'current_charges';
  v_has_max_charges := p_payload ? 'max_charges';
  v_has_notes := p_payload ? 'notes';
  v_has_data := p_payload ? 'data';

  v_custom_name := case
    when v_has_custom_name then nullif(trim(coalesce(p_payload->>'custom_name', '')), '')
    else v_item.custom_name
  end;
  v_new_armor_value := case
    when v_has_armor_value then greatest(coalesce(nullif(trim(coalesce(p_payload->>'armor_value', '')), '')::integer, v_item.armor_value), 0)
    else v_item.armor_value
  end;
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
    else case
      when v_new_armor_max_critical > 0 and v_new_armor_critical >= v_new_armor_max_critical then true
      else v_item.armor_destroyed
    end
  end;
  v_new_current_charges := case
    when v_has_current_charges then
      case
        when lower(trim(coalesce(p_payload->>'current_charges', ''))) = 'null' then null
        when trim(coalesce(p_payload->>'current_charges', '')) = '' then null
        else greatest((p_payload->>'current_charges')::integer, 0)
      end
    else v_item.current_charges
  end;
  v_new_max_charges := case
    when v_has_max_charges then
      case
        when lower(trim(coalesce(p_payload->>'max_charges', ''))) = 'null' then null
        when trim(coalesce(p_payload->>'max_charges', '')) = '' then null
        else greatest((p_payload->>'max_charges')::integer, 0)
      end
    else v_item.max_charges
  end;
  v_new_data := case
    when v_has_data and jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    when v_has_data then '{}'::jsonb
    else v_item.data
  end;

  update public.odyssey_character_equipment_items
  set
    custom_name = v_custom_name,
    armor_value = v_new_armor_value,
    armor_critical = v_new_armor_critical,
    armor_max_critical = v_new_armor_max_critical,
    armor_destroyed = v_new_armor_destroyed,
    current_charges = v_new_current_charges,
    max_charges = v_new_max_charges,
    data = v_new_data,
    notes = case when v_has_notes then coalesce(p_payload->>'notes', '') else v_item.notes end,
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

create or replace function public.get_character_rule_sheet(p_character_id uuid)
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
    'attributes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'attribute_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'value', a.value,
              'default_value', d.default_value,
              'max_value', d.max_value,
              'cost_per_level', d.cost_per_level,
              'description', d.description,
              'sort_order', d.sort_order,
              'is_custom', d.is_custom
            )
            order by d.sort_order, d.name
          )
          from public.odyssey_character_attributes a
          join public.odyssey_attribute_defs d on d.id = a.attribute_def_id
          where a.character_id = c.id
        ),
        '[]'::jsonb
      ),
    'skills',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', s.id,
              'skill_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'custom_name', s.custom_name,
              'category', d.category,
              'level', s.level,
              'max_level', d.max_level,
              'main_attribute', main_attr.code,
              'secondary_attribute', secondary_attr.code,
              'governing_attribute', governing_attr.code,
              'tags', d.tags,
              'notes', s.notes
            )
            order by d.category, d.sort_order, d.name
          )
          from public.odyssey_character_skills s
          join public.odyssey_skill_defs d on d.id = s.skill_def_id
          left join public.odyssey_attribute_defs main_attr on main_attr.id = d.main_attribute_id
          left join public.odyssey_attribute_defs secondary_attr on secondary_attr.id = d.secondary_attribute_id
          left join public.odyssey_attribute_defs governing_attr on governing_attr.id = s.governing_attribute_def_id
          where s.character_id = c.id
        ),
        '[]'::jsonb
      ),
    'perks',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', cp.id,
              'perk_def_id', p.id,
              'code', p.code,
              'name', p.name,
              'skill_code', skill_def.code,
              'required_skill_level', p.required_skill_level,
              'effect_type', p.effect_type,
              'effect_data', p.effect_data,
              'tags', p.tags,
              'notes', cp.notes,
              'acquired_at', cp.acquired_at
            )
            order by p.name
          )
          from public.odyssey_character_perks cp
          join public.odyssey_perk_defs p on p.id = cp.perk_def_id
          left join public.odyssey_skill_defs skill_def on skill_def.id = p.skill_def_id
          where cp.character_id = c.id
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
              'natural_armor_value', b.natural_armor_value,
              'armor_value', b.armor_value,
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
      ),
    'armor_summary', public.get_character_armor_summary(c.id),
    'equipment_summary', coalesce(public.get_character_equipment(c.id)->'summary', '{}'::jsonb)
  )
  from selected_character c;
$$;

create or replace function public.get_effective_character_stats(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_exists boolean := false;
  v_effect_summary jsonb := '{}'::jsonb;
  v_attributes jsonb := '[]'::jsonb;
  v_attribute_values jsonb := '{}'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_armor_total integer := 0;
  v_armor_class text := 'none';
  v_action_count_modifier integer := 0;
  v_movement_modifier integer := 0;
  v_concentration_modifier integer := 0;
  v_attack_accuracy_modifier integer := 0;
  v_defense_modifier integer := 0;
  v_damage_modifier integer := 0;
  v_armor_modifier integer := 0;
  v_aim_difficulty_modifier integer := 0;
  v_range_modifier integer := 0;
  v_effective_strength integer := 0;
  v_effective_agility integer := 0;
  v_effective_intelligence integer := 0;
  v_main_actions integer := 0;
  v_movement_bonus integer := 0;
  v_movement_available integer := 0;
  v_concentration_slots integer := 0;
  v_helpless boolean := false;
  v_skip_main_action boolean := false;
  v_skip_movement boolean := false;
  v_consumes_full_turn boolean := false;
  v_suppress_movement boolean := false;
  v_cannot_leave_cover boolean := false;
  v_requires_concentration boolean := false;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_has_unconscious_effect boolean := false;
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

  v_effect_summary := public.get_character_effect_summary(p_character_id);
  v_armor_summary := public.get_character_armor_summary(p_character_id);

  with attribute_rows as (
    select
      d.code,
      d.name,
      coalesce(a.value, d.default_value, 0) as base_value,
      coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'attributes', d.code), '')::integer, 0) as modifier_value,
      d.max_value,
      d.sort_order
    from public.odyssey_attribute_defs d
    left join public.odyssey_character_attributes a
      on a.attribute_def_id = d.id
     and a.character_id = p_character_id
    order by d.sort_order, d.name
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'code', code,
          'name', name,
          'base_value', base_value,
          'modifier', modifier_value,
          'effective_value', base_value + modifier_value,
          'max_value', max_value,
          'sort_order', sort_order
        )
        order by sort_order, name
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_object_agg(code, base_value + modifier_value),
      '{}'::jsonb
    )
  into
    v_attributes,
    v_attribute_values
  from attribute_rows;

  select
    coalesce(bool_or(lower(coalesce(d.code, b.part_key)) in ('head', 'torso') and coalesce(b.destroyed, false)), false)
  into v_is_alive
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.character_id = p_character_id;

  v_is_alive := not v_is_alive;

  select exists(
    select 1
    from public.odyssey_character_effects e
    left join public.odyssey_effect_defs d on d.id = e.effect_def_id
    where e.character_id = p_character_id
      and e.is_active = true
      and lower(coalesce(d.code, e.effect_key, '')) = 'unconscious'
  )
  into v_has_unconscious_effect;

  v_is_conscious := v_is_alive and not v_has_unconscious_effect;
  v_armor_total := coalesce(nullif(jsonb_extract_path_text(v_armor_summary, 'total_equipped_armor_value'), '')::integer, 0);
  v_armor_class := coalesce(jsonb_extract_path_text(v_armor_summary, 'armor_class'), 'none');

  v_action_count_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'action_count'), '')::integer, 0);
  v_movement_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'movement_m'), '')::integer, 0);
  v_concentration_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'concentration_slots'), '')::integer, 0);
  v_attack_accuracy_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'attack_accuracy'), '')::integer, 0);
  v_defense_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'defense'), '')::integer, 0);
  v_damage_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'damage'), '')::integer, 0);
  v_armor_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'armor'), '')::integer, 0);
  v_aim_difficulty_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'aim_difficulty'), '')::integer, 0);
  v_range_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'range'), '')::integer, 0);

  v_helpless := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'helpless'), '')::boolean, false);
  v_skip_main_action := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'skip_main_action'), '')::boolean, false);
  v_skip_movement := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'skip_movement'), '')::boolean, false);
  v_consumes_full_turn := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'consumes_full_turn'), '')::boolean, false);
  v_suppress_movement := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'suppress_movement'), '')::boolean, false);
  v_cannot_leave_cover := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'cannot_leave_cover'), '')::boolean, false);
  v_requires_concentration := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'requires_concentration'), '')::boolean, false);

  v_effective_strength := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'strength'), '')::integer, 0);
  v_effective_agility := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'agility'), '')::integer, 0);
  v_effective_intelligence := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'intelligence'), '')::integer, 0);

  v_main_actions := greatest(
    public.odyssey_get_main_actions_from_agility(v_effective_agility) + v_action_count_modifier,
    0
  );
  if not v_is_alive or not v_is_conscious or v_skip_main_action or v_consumes_full_turn then
    v_main_actions := 0;
  end if;

  v_movement_bonus := public.odyssey_get_movement_bonus_from_agility(v_effective_agility);
  v_movement_available := greatest(v_movement_bonus + v_movement_modifier, 0);
  if not v_is_alive or not v_is_conscious or v_skip_movement or v_consumes_full_turn then
    v_movement_available := 0;
  end if;

  v_concentration_slots := greatest(
    public.odyssey_get_concentration_slots_from_intelligence(v_effective_intelligence) + v_concentration_modifier,
    0
  );

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'attributes', v_attributes,
    'attribute_values', v_attribute_values,
    'armor_summary', v_armor_summary,
    'derived',
      jsonb_build_object(
        'base_main_actions', 1,
        'main_actions_per_turn', v_main_actions,
        'action_count_modifier', v_action_count_modifier,
        'movement_bonus_m', v_movement_bonus,
        'movement_modifier_m', v_movement_modifier,
        'movement_available_m', v_movement_available,
        'concentration_slots', v_concentration_slots,
        'concentration_slots_modifier', v_concentration_modifier,
        'armor_total', v_armor_total,
        'armor_class', v_armor_class,
        'attack_accuracy_modifier', v_attack_accuracy_modifier,
        'defense_modifier', v_defense_modifier,
        'damage_modifier', v_damage_modifier,
        'armor_modifier', v_armor_modifier,
        'aim_difficulty_modifier', v_aim_difficulty_modifier,
        'range_modifier', v_range_modifier,
        'helpless', v_helpless,
        'skip_main_action', v_skip_main_action,
        'skip_movement', v_skip_movement,
        'consumes_full_turn', v_consumes_full_turn,
        'suppress_movement', v_suppress_movement,
        'cannot_leave_cover', v_cannot_leave_cover,
        'requires_concentration', v_requires_concentration,
        'is_alive', v_is_alive,
        'is_conscious', v_is_conscious
      ),
    'active_effects', coalesce(v_effect_summary->'active_effects', '[]'::jsonb),
    'effect_summary', v_effect_summary
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
  v_armor_parts jsonb := '[]'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_equipment_bundle jsonb := '{}'::jsonb;
  v_equipment_summary jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_summary jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
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
    'is_alive', v_is_alive,
    'is_conscious', v_is_conscious,
    'tracker_minor', v_tracker_minor,
    'tracker_serious', v_tracker_serious,
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

create or replace function public.odyssey_apply_equipment_critical_damage(
  p_body_part_id uuid,
  p_critical_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_item record;
  v_remaining integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_absorbed integer := 0;
  v_absorb integer := 0;
  v_updates jsonb := '[]'::jsonb;
  v_new_armor_critical integer := 0;
  v_new_armor_destroyed boolean := false;
begin
  if v_remaining <= 0 then
    return jsonb_build_object(
      'absorbed', 0,
      'remaining', 0,
      'updated_items', '[]'::jsonb
    );
  end if;

  for v_item in
    select
      e.id,
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
  loop
    exit when v_remaining <= 0;

    if coalesce(v_item.armor_max_critical, 0) <= coalesce(v_item.armor_critical, 0) then
      continue;
    end if;

    v_absorb := least(
      v_remaining,
      greatest(coalesce(v_item.armor_max_critical, 0) - coalesce(v_item.armor_critical, 0), 0)
    );

    if v_absorb <= 0 then
      continue;
    end if;

    v_new_armor_critical := coalesce(v_item.armor_critical, 0) + v_absorb;
    v_new_armor_destroyed := case
      when coalesce(v_item.armor_max_critical, 0) > 0 and v_new_armor_critical >= coalesce(v_item.armor_max_critical, 0) then true
      else coalesce(v_item.armor_destroyed, false)
    end;

    update public.odyssey_character_equipment_items
    set
      armor_critical = v_new_armor_critical,
      armor_destroyed = v_new_armor_destroyed,
      updated_at = timezone('utc', now())
    where id = v_item.id;

    v_updates := v_updates || jsonb_build_array(
      jsonb_build_object(
        'id', v_item.id,
        'name', v_item.item_name,
        'absorbed_critical', v_absorb,
        'armor_critical', v_new_armor_critical,
        'armor_max_critical', coalesce(v_item.armor_max_critical, 0),
        'armor_destroyed', v_new_armor_destroyed
      )
    );

    v_absorbed := v_absorbed + v_absorb;
    v_remaining := v_remaining - v_absorb;
  end loop;

  return jsonb_build_object(
    'absorbed', v_absorbed,
    'remaining', v_remaining,
    'updated_items', v_updates
  );
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_weapon_id uuid := nullif(trim(coalesce(p_payload->>'weapon_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_defense_skill_id uuid := nullif(trim(coalesce(p_payload->>'defense_skill_id', '')), '')::uuid;
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(p_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_actor_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'actor_token_id', '')), ''), '');
  v_target_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'target_token_id', '')), ''), '');
  v_manual_attack_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_bonus}', '')), '')::integer, 0);
  v_manual_attack_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_penalty}', '')), '')::integer, 0);
  v_manual_defense_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_bonus}', '')), '')::integer, 0);
  v_manual_defense_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_penalty}', '')), '')::integer, 0);
  v_hostile_adjacent_count integer := greatest(coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,hostile_adjacent_count}', '')), '')::integer, 1), 1);
  v_ignore_defense_skill boolean := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,ignore_defense_skill}', '')), '')::boolean, false);
  v_override_ignore_action_restrictions boolean := coalesce(nullif(trim(coalesce(p_payload#>>'{override,ignore_action_restrictions}', '')), '')::boolean, false);
  v_attacker public.odyssey_characters%rowtype;
  v_target public.odyssey_characters%rowtype;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_weapon_model record;
  v_fire_mode record;
  v_target_part record;
  v_attacker_effective_stats jsonb := '{}'::jsonb;
  v_target_effective_stats jsonb := '{}'::jsonb;
  v_attacker_effect_summary jsonb := '{}'::jsonb;
  v_target_effect_summary jsonb := '{}'::jsonb;
  v_target_armor_summary jsonb := '{}'::jsonb;
  v_attacker_is_alive boolean := true;
  v_attacker_is_conscious boolean := true;
  v_attacker_helpless boolean := false;
  v_attacker_skip_main_action boolean := false;
  v_target_helpless boolean := false;
  v_target_armor_total integer := 0;
  v_target_armor_class text := 'none';
  v_target_helpless_execution_protected boolean := false;
  v_target_helpless_source jsonb := '[]'::jsonb;
  v_attack_skill_level integer := 0;
  v_attack_skill_modifier integer := 0;
  v_attack_skill_bonus integer := 0;
  v_attack_roll integer := 0;
  v_defense_roll integer := 0;
  v_attack_total integer := 0;
  v_defense_total integer := 0;
  v_defense_skill_level integer := 0;
  v_defense_skill_modifier integer := 0;
  v_effective_defense_skill_level integer := 0;
  v_defense_skill_source text := 'none_for_ranged';
  v_defense_skill_code text := '';
  v_range_json jsonb := '{}'::jsonb;
  v_range_band text := null;
  v_range_modifier integer := 0;
  v_attack_type text := null;
  v_magazine record;
  v_magazine_id uuid := null;
  v_ammo_code text := null;
  v_bullets_spent integer := 0;
  v_remaining_rounds integer := null;
  v_bullet_damage integer := 0;
  v_total_weapon_damage integer := 0;
  v_melee_strength_bonus integer := 0;
  v_strength_value integer := 0;
  v_ammo_accuracy_modifier integer := 0;
  v_ammo_damage_modifier integer := 0;
  v_armor_pierce integer := 0;
  v_attacker_attack_accuracy_modifier integer := 0;
  v_attacker_damage_modifier integer := 0;
  v_attacker_aim_difficulty_modifier integer := 0;
  v_attacker_range_effect_modifier integer := 0;
  v_target_defense_modifier integer := 0;
  v_target_armor_modifier integer := 0;
  v_helpless_defense_penalty integer := 0;
  v_effective_aim_difficulty integer := 0;
  v_raw_armor_value integer := 0;
  v_effective_armor integer := 0;
  v_hit boolean := false;
  v_hit_source text := 'normal';
  v_damage_attack_total integer := null;
  v_damage_defense_total integer := null;
  v_damage_diff integer := null;
  v_minor_delta integer := 0;
  v_serious_delta integer := 0;
  v_critical_delta integer := 0;
  v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';
  v_new_minor integer := 0;
  v_new_serious integer := 0;
  v_new_critical integer := 0;
  v_new_armor_critical integer := 0;
  v_new_armor_max_critical integer := 0;
  v_new_armor_value integer := 0;
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
  v_new_armor_destroyed boolean := false;
  v_body_changed boolean := false;
  v_armor_items_changed boolean := false;
  v_target_state jsonb := '{}'::jsonb;
  v_attacker_state jsonb := '{}'::jsonb;
  v_expired_attack_effects jsonb := '[]'::jsonb;
  v_message text := '';
  v_error_code text := null;
  v_error_message text := null;
  v_result jsonb := '{}'::jsonb;
  v_log_data jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_created_by text := '';
  v_execution_info jsonb := '{}'::jsonb;
  v_armor_damage_json jsonb := '{}'::jsonb;
  v_armor_item_updates jsonb := '[]'::jsonb;
begin
  v_created_by := coalesce(v_actor_token_id, '');

  select *
  into v_attacker
  from public.odyssey_characters c
  where c.id = v_attacker_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    v_error_code := 'CHARACTER_NOT_FOUND';
    v_error_message := 'Attacker character was not found.';
  end if;

  if v_error_code is null then
    select *
    into v_target
    from public.odyssey_characters c
    where c.id = v_target_character_id
      and coalesce(c.is_deleted, false) = false;

    if not found then
      v_error_code := 'TARGET_NOT_FOUND';
      v_error_message := 'Target character was not found.';
    end if;
  end if;

  if v_error_code is null then
    select *
    into v_weapon
    from public.odyssey_character_weapons w
    where w.id = v_weapon_id
      and w.character_id = v_attacker_character_id;

    if not found then
      v_error_code := 'WEAPON_NOT_FOUND';
      v_error_message := 'Weapon was not found for the attacker.';
    end if;
  end if;

  if v_error_code is null then
    select
      wm.id,
      wm.code,
      wm.name,
      wm.weapon_class_id,
      wc.code as weapon_class_code,
      wc.name as weapon_class_name,
      wm.linked_skill_id,
      skill.code as linked_skill_code,
      skill.name as linked_skill_name,
      wm.caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      caliber.base_damage_per_round,
      wm.range_profile_id,
      rp.code as range_profile_code,
      rp.name as range_profile_name,
      wm.base_accuracy_bonus,
      wm.base_melee_damage
    into v_weapon_model
    from public.odyssey_weapon_model_defs wm
    join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
    join public.odyssey_skill_defs skill on skill.id = wm.linked_skill_id
    left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
    join public.odyssey_range_profile_defs rp on rp.id = wm.range_profile_id
    where wm.id = v_weapon.weapon_model_id;

    if not found then
      v_error_code := 'INVALID_WEAPON_MODEL';
      v_error_message := 'Weapon model linked to the weapon was not found.';
    end if;
  end if;

  if v_error_code is null then
    if v_weapon.selected_fire_mode_id is not null then
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.fire_mode_id = v_weapon.selected_fire_mode_id
      limit 1;
    else
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.is_default = true
      order by wmfm.created_at
      limit 1;
    end if;

    if not found then
      v_error_code := 'INVALID_FIRE_MODE';
      v_error_message := 'Weapon fire mode is missing or not allowed for this model.';
    end if;
  end if;

  if v_error_code is null then
    select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.natural_armor_value,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name,
      coalesce(d.can_be_targeted, true) as can_be_targeted,
      coalesce(d.aim_difficulty, 0) as aim_difficulty
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.id = v_target_body_part_id
      and b.character_id = v_target_character_id;

    if not found or not coalesce(v_target_part.can_be_targeted, true) then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part was not found or cannot be targeted.';
    end if;
  end if;

  if coalesce(v_campaign_id, '') = '' then
    v_campaign_id := coalesce(v_attacker.campaign_id, '');
  end if;

  if coalesce(v_room_id, '') = '' then
    v_room_id := coalesce(v_attacker.room_id, '');
  end if;

  if v_error_code is null then
    v_attacker_effective_stats := public.get_effective_character_stats(v_attacker_character_id);
    v_target_effective_stats := public.get_effective_character_stats(v_target_character_id);
    v_attacker_effect_summary := coalesce(v_attacker_effective_stats->'effect_summary', '{}'::jsonb);
    v_target_effect_summary := coalesce(v_target_effective_stats->'effect_summary', '{}'::jsonb);
    v_target_armor_summary := public.get_character_armor_summary(v_target_character_id);

    v_attacker_is_alive := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_alive'), '')::boolean, true);
    v_attacker_is_conscious := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_conscious'), '')::boolean, true);
    v_attacker_helpless := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'helpless'), '')::boolean, false);
    v_attacker_skip_main_action := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false);

    if not v_override_ignore_action_restrictions
      and (
        not v_attacker_is_alive
        or not v_attacker_is_conscious
        or v_attacker_helpless
        or v_attacker_skip_main_action
      ) then
      v_error_code := 'ATTACKER_CANNOT_ACT';
      v_error_message := 'Attacker cannot act because of current effects or combat state.';
    end if;
  end if;

  if v_error_code is null then
    v_target_helpless := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'helpless'), '')::boolean, false);
    v_target_armor_total := coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'total_equipped_armor_value'), '')::integer, 0);
    v_target_armor_class := coalesce(jsonb_extract_path_text(v_target_armor_summary, 'armor_class'), 'none');
    v_target_helpless_execution_protected := coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'helpless_execution_protected'), '')::boolean, false);

    select
      coalesce(
        jsonb_agg(coalesce(entry->>'code', entry->>'effect_key'))
          filter (
            where lower(coalesce(entry->'data'->'flags'->>'helpless', 'false')) in ('true', '1', 'yes', 'on')
          ),
        '[]'::jsonb
      )
    into v_target_helpless_source
    from jsonb_array_elements(coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb)) entry;
  end if;

  if v_error_code is null then
    v_attack_type := case when v_weapon_model.caliber_id is null then 'melee' else 'ranged' end;

    select coalesce(s.level, 0)
    into v_attack_skill_level
    from public.odyssey_skill_defs d
    left join public.odyssey_character_skills s
      on s.skill_def_id = d.id
     and s.character_id = v_attacker_character_id
    where d.id = v_weapon_model.linked_skill_id;

    v_attack_skill_modifier := coalesce(
      nullif(jsonb_extract_path_text(v_attacker_effect_summary, 'modifiers', 'skills', v_weapon_model.linked_skill_code), '')::integer,
      0
    );
    v_attack_skill_level := coalesce(v_attack_skill_level, 0) + v_attack_skill_modifier;
    if v_attack_skill_level < 0 then
      v_attack_skill_level := 0;
    end if;
    v_attack_skill_bonus := v_attack_skill_level * 10;

    v_attacker_attack_accuracy_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'attack_accuracy_modifier'), '')::integer, 0);
    v_attacker_damage_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'damage_modifier'), '')::integer, 0);
    v_attacker_aim_difficulty_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'aim_difficulty_modifier'), '')::integer, 0);
    v_attacker_range_effect_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'range_modifier'), '')::integer, 0);
    v_target_defense_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'defense_modifier'), '')::integer, 0);
    v_target_armor_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'armor_modifier'), '')::integer, 0);
  end if;

  if v_error_code is null then
    v_range_json := public.get_weapon_range_modifier(v_weapon_model.id, v_distance_m);
    v_range_band := nullif(coalesce(v_range_json->>'range_band', ''), '');
    v_range_modifier := coalesce((v_range_json->>'modifier')::integer, 0) + v_attacker_range_effect_modifier;
  end if;

  if v_error_code is null and v_attack_type = 'ranged' then
    if v_weapon.loaded_magazine_id is null then
      v_error_code := 'NO_MAGAZINE';
      v_error_message := 'Weapon requires a loaded magazine.';
    else
      select
        cm.id,
        cm.character_id,
        cm.magazine_def_id,
        cm.ammo_type_id,
        cm.current_rounds,
        md.code as magazine_def_code,
        md.name as magazine_def_name,
        md.capacity,
        md.caliber_id as magazine_caliber_id,
        caliber.code as magazine_caliber_code,
        ammo.code as ammo_code,
        ammo.name as ammo_name,
        ammo.caliber_id as ammo_caliber_id,
        ammo.damage_modifier,
        ammo.accuracy_modifier,
        ammo.armor_pierce
      into v_magazine
      from public.odyssey_character_magazines cm
      join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
      join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
      join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
      where cm.id = v_weapon.loaded_magazine_id
        and cm.character_id = v_attacker_character_id;

      if not found then
        v_error_code := 'INVALID_MAGAZINE';
        v_error_message := 'Loaded magazine was not found or does not belong to the attacker.';
      else
        v_magazine_id := v_magazine.id;
        v_ammo_code := v_magazine.ammo_code;
      end if;

      if v_error_code is null then
        if v_magazine.magazine_caliber_id <> v_weapon_model.caliber_id
          or v_magazine.ammo_caliber_id <> v_magazine.magazine_caliber_id
          or not exists (
            select 1
            from public.odyssey_weapon_model_magazines wmm
            where wmm.weapon_model_id = v_weapon.weapon_model_id
              and wmm.magazine_def_id = v_magazine.magazine_def_id
          ) then
          v_error_code := 'INVALID_MAGAZINE';
          v_error_message := 'Loaded magazine is incompatible with the weapon model.';
        elsif coalesce(v_magazine.current_rounds, 0) <= 0 then
          v_error_code := 'NO_AMMO';
          v_error_message := 'Loaded magazine is empty.';
        else
          if coalesce(v_fire_mode.is_random, false) then
            if v_magazine.current_rounds >= coalesce(v_fire_mode.min_rounds, 1) then
              v_bullets_spent :=
                floor(
                  random()
                  * (
                      least(
                        coalesce(v_fire_mode.max_rounds, v_magazine.current_rounds),
                        v_magazine.current_rounds
                      )
                      - coalesce(v_fire_mode.min_rounds, 1)
                      + 1
                    )
                )::integer + coalesce(v_fire_mode.min_rounds, 1);
            else
              v_bullets_spent := v_magazine.current_rounds;
            end if;
          else
            v_bullets_spent := least(coalesce(v_fire_mode.fixed_rounds, 0), v_magazine.current_rounds);
          end if;

          if v_bullets_spent <= 0 then
            v_error_code := 'NO_AMMO';
            v_error_message := 'Attack cannot be made because there is no ammunition to spend.';
          else
            v_ammo_accuracy_modifier := coalesce(v_magazine.accuracy_modifier, 0);
            v_ammo_damage_modifier := coalesce(v_magazine.damage_modifier, 0);
            v_armor_pierce := coalesce(v_magazine.armor_pierce, 0);
            v_bullet_damage := greatest(coalesce(v_weapon_model.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;
            v_remaining_rounds := v_magazine.current_rounds - v_bullets_spent;
          end if;
        end if;
      end if;
    end if;
  elsif v_error_code is null then
    v_strength_value := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'attribute_values', 'strength'), '')::integer, 0);
    v_melee_strength_bonus := greatest(v_strength_value - 10, 0);
    v_total_weapon_damage := coalesce(v_weapon_model.base_melee_damage, 0) + v_melee_strength_bonus;
    v_bullet_damage := 0;
    v_ammo_accuracy_modifier := 0;
    v_ammo_damage_modifier := 0;
    v_armor_pierce := 0;
    v_magazine_id := null;
    v_ammo_code := null;
    v_remaining_rounds := null;
  end if;

  if v_error_code is null then
    v_total_weapon_damage := greatest(v_total_weapon_damage + v_attacker_damage_modifier, 0);
  end if;

  if v_error_code is null then
    if v_target_helpless then
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'helpless';
      v_defense_skill_code := '';
    elsif v_ignore_defense_skill then
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'ignored';
      v_defense_skill_code := '';
    elsif v_defense_skill_id is not null then
      select
        d.code,
        coalesce(s.level, 0)
      into
        v_defense_skill_code,
        v_defense_skill_level
      from public.odyssey_skill_defs d
      left join public.odyssey_character_skills s
        on s.skill_def_id = d.id
       and s.character_id = v_target_character_id
      where d.id = v_defense_skill_id;

      v_defense_skill_modifier := coalesce(
        nullif(jsonb_extract_path_text(v_target_effect_summary, 'modifiers', 'skills', coalesce(v_defense_skill_code, '')), '')::integer,
        0
      );
      v_defense_skill_level := greatest(coalesce(v_defense_skill_level, 0) + v_defense_skill_modifier, 0);
      v_effective_defense_skill_level := v_defense_skill_level;
      v_defense_skill_source := 'payload';
    elsif v_attack_type = 'melee' then
      v_defense_skill_code := 'parry';
      select coalesce(s.level, 0)
      into v_defense_skill_level
      from public.odyssey_skill_defs d
      left join public.odyssey_character_skills s
        on s.skill_def_id = d.id
       and s.character_id = v_target_character_id
      where d.code = 'parry';

      v_defense_skill_modifier := coalesce(
        nullif(jsonb_extract_path_text(v_target_effect_summary, 'modifiers', 'skills', 'parry'), '')::integer,
        0
      );
      v_defense_skill_level := greatest(coalesce(v_defense_skill_level, 0) + v_defense_skill_modifier, 0);
      v_effective_defense_skill_level := floor(v_defense_skill_level::numeric / v_hostile_adjacent_count)::integer;
      if v_defense_skill_level > 0 and v_effective_defense_skill_level < 1 then
        v_effective_defense_skill_level := 1;
      end if;
      v_defense_skill_source := 'fallback_parry';
    else
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'none_for_ranged';
      v_defense_skill_code := '';
    end if;
  end if;

  if v_error_code is null then
    v_raw_armor_value := greatest(coalesce(v_target_part.armor_value, 0) + v_target_armor_modifier, 0);

    if v_attack_type = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;

    v_attack_roll := floor(random() * 100)::integer + 1;
    if v_target_helpless and v_target_armor_class in ('none', 'light') then
      v_defense_roll := 1;
      v_hit_source := 'helpless_defense_roll_1';
    else
      v_defense_roll := floor(random() * 100)::integer + 1;
      if v_target_helpless and v_target_armor_class in ('medium', 'heavy', 'superheavy') then
        v_helpless_defense_penalty := -60;
        v_hit_source := 'helpless_defense_penalty_60';
      end if;
    end if;

    v_effective_aim_difficulty := greatest(coalesce(v_target_part.aim_difficulty, 0) - v_attacker_aim_difficulty_modifier, 0);

    v_attack_total :=
      v_attack_roll
      + v_attack_skill_bonus
      + coalesce(v_weapon_model.base_accuracy_bonus, 0)
      + v_ammo_accuracy_modifier
      + coalesce(v_fire_mode.accuracy_modifier, 0)
      + coalesce(v_range_modifier, 0)
      + v_attacker_attack_accuracy_modifier
      - v_effective_aim_difficulty
      + v_manual_attack_bonus
      - v_manual_attack_penalty;

    v_defense_total :=
      v_defense_roll
      + (v_effective_defense_skill_level * 10)
      + v_target_defense_modifier
      + v_helpless_defense_penalty
      + v_manual_defense_bonus
      - v_manual_defense_penalty;

    if v_attack_type = 'ranged' then
      update public.odyssey_character_magazines
      set current_rounds = v_remaining_rounds
      where id = v_magazine_id;
    end if;

    v_hit := v_attack_total > v_defense_total;
  end if;

  v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
  v_new_armor_max_critical := coalesce(v_target_part.armor_max_critical, 0);
  v_new_armor_value := coalesce(v_target_part.armor_value, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);
  v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);

  if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + v_total_weapon_damage;
    v_damage_defense_total := v_defense_total + v_effective_armor;
    v_damage_diff := v_damage_attack_total - v_damage_defense_total;

    if v_damage_diff > 90 then
      v_critical_delta := 3;
      v_damage_level := 'critical';
    elsif v_damage_diff > 60 then
      v_critical_delta := 2;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 31 then
      v_critical_delta := 1;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 6 then
      v_serious_delta := 1;
      v_damage_level := 'serious';
    elsif v_damage_diff > 0 then
      v_minor_delta := 1;
      v_damage_level := 'minor';
    else
      v_damage_level := 'no_damage';
    end if;

    v_new_minor := coalesce(v_target_part.minor, 0) + v_minor_delta;
    v_new_serious := coalesce(v_target_part.serious, 0) + v_serious_delta;
    v_new_critical := coalesce(v_target_part.critical, 0);
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);
      v_armor_items_changed := v_armor_critical_delta > 0;

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0
      or v_serious_delta > 0
      or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;

      v_body_changed := true;
    end if;
  end if;

  if v_armor_items_changed then
    perform public.recompute_character_armor(v_target_character_id);
    v_target_armor_summary := public.get_character_armor_summary(v_target_character_id);
    v_target_armor_total := coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'total_equipped_armor_value'), '')::integer, 0);
    v_target_armor_class := coalesce(jsonb_extract_path_text(v_target_armor_summary, 'armor_class'), 'none');
    v_target_helpless_execution_protected := coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'helpless_execution_protected'), '')::boolean, false);
  end if;

  if v_body_changed or v_armor_items_changed then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);

    select
      b.minor,
      b.serious,
      b.critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed
    into
      v_new_minor,
      v_new_serious,
      v_new_critical,
      v_new_armor_value,
      v_new_armor_critical,
      v_new_armor_max_critical,
      v_new_armor_destroyed,
      v_new_disabled,
      v_new_destroyed
    from public.odyssey_character_body_parts b
    where b.id = v_target_part.id;
  end if;

  if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
    if jsonb_array_length(coalesce(v_expired_attack_effects, '[]'::jsonb)) > 0 then
      v_attacker_state := coalesce(public.odyssey_refresh_character_combat_state(v_attacker_character_id)->'combat_state', '{}'::jsonb);
    end if;
  end if;

  if v_error_code is not null then
    v_log_data := jsonb_build_object(
      'type', 'attack',
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'attacker_character_id', v_attacker_character_id,
      'target_character_id', v_target_character_id,
      'weapon_id', v_weapon_id,
      'target_body_part_id', v_target_body_part_id,
      'distance_m', v_distance_m,
      'actor_token_id', v_actor_token_id,
      'target_token_id', v_target_token_id
    );

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
      coalesce(v_campaign_id, ''),
      coalesce(v_room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      v_attacker_character_id,
      v_target_character_id,
      'attack',
      v_error_message,
      v_log_data,
      v_created_by
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

    return jsonb_build_object(
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'log_id', v_log_id
    );
  end if;

  if not v_hit then
    v_message := format(
      '%s attacks %s with %s and misses.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  elsif v_damage_level = 'no_damage' then
    v_message := format(
      '%s hits %s in %s with %s but deals no damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  else
    v_message := format(
      '%s hits %s in %s with %s for %s damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
      v_damage_level
    );
  end if;

  v_execution_info := jsonb_build_object(
    'auto_hit', false,
    'hit_source', v_hit_source,
    'fatal_on_any_damage', false,
    'fatal_triggered', false,
    'special_rule',
      case
        when v_hit_source = 'helpless_defense_roll_1' then 'helpless_defense_roll_1'
        when v_hit_source = 'helpless_defense_penalty_60' then 'helpless_defense_penalty_60'
        else 'normal'
      end,
    'expired_effects_after_attack', v_expired_attack_effects
  );

  v_log_data := jsonb_build_object(
    'type', 'attack',
    'ok', true,
    'hit', v_hit,
    'hit_source', v_hit_source,
    'attack_type', v_attack_type,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon_id', v_weapon_id,
    'weapon_model_id', v_weapon_model.id,
    'weapon_name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
    'target_body_part_id', v_target_body_part_id,
    'target_body_part_name', v_target_part.part_name,
    'distance_m', v_distance_m,
    'range_band', v_range_band,
    'range_modifier', v_range_modifier,
    'attack_roll', v_attack_roll,
    'attack_skill_level', v_attack_skill_level,
    'attack_total', v_attack_total,
    'defense_roll', v_defense_roll,
    'defense_skill_level', v_defense_skill_level,
    'effective_defense_skill_level', v_effective_defense_skill_level,
    'defense_skill_source', v_defense_skill_source,
    'defense_total', v_defense_total,
    'fire_mode', v_fire_mode.code,
    'bullets_spent', v_bullets_spent,
    'melee_strength_bonus', v_melee_strength_bonus,
    'damage_level', v_damage_level,
    'damage_diff', v_damage_diff,
    'minor_delta', v_minor_delta,
    'serious_delta', v_serious_delta,
    'critical_delta', v_critical_delta,
    'armor_critical_delta', v_armor_critical_delta,
    'armor_item_updates', v_armor_item_updates,
    'remaining_magazine_rounds', v_remaining_rounds,
    'effects',
      jsonb_build_object(
        'attacker',
          jsonb_build_object(
            'active_effects', coalesce(v_attacker_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_attacker_effect_summary->'modifiers', '{}'::jsonb)
          ),
        'target',
          jsonb_build_object(
            'active_effects', coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_target_effect_summary->'modifiers', '{}'::jsonb),
            'flags', coalesce(v_target_effect_summary->'flags', '{}'::jsonb),
            'helpless_source', v_target_helpless_source
          )
      ),
    'armor_summary',
      jsonb_build_object(
        'total_armor_value', v_target_armor_total,
        'armor_class', v_target_armor_class,
        'head_protected', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'head_protected'), '')::boolean, false),
        'torso_protected', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'torso_protected'), '')::boolean, false),
        'special_protection', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'special_protection'), '')::boolean, false),
        'helpless_execution_protected', v_target_helpless_execution_protected
      ),
    'execution', v_execution_info
  );

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
    coalesce(v_campaign_id, ''),
    coalesce(v_room_id, ''),
    coalesce(v_scene_id, ''),
    v_encounter_id,
    v_attacker_character_id,
    v_target_character_id,
    'attack',
    v_message,
    v_log_data,
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

  select jsonb_build_object(
    'ok', true,
    'hit', v_hit,
    'attack_type', v_attack_type,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon',
      jsonb_build_object(
        'id', v_weapon_id,
        'model_id', v_weapon_model.id,
        'name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
        'base_accuracy_bonus', v_weapon_model.base_accuracy_bonus,
        'base_melee_damage', v_weapon_model.base_melee_damage
      ),
    'fire_mode',
      jsonb_build_object(
        'id', v_fire_mode.id,
        'code', v_fire_mode.code,
        'accuracy_modifier', v_fire_mode.accuracy_modifier
      ),
    'ammo',
      jsonb_build_object(
        'caliber', v_weapon_model.caliber_code,
        'ammo_type', case when v_attack_type = 'ranged' then v_ammo_code else null end,
        'bullet_damage', v_bullet_damage,
        'damage_modifier', v_ammo_damage_modifier,
        'accuracy_modifier', v_ammo_accuracy_modifier,
        'armor_pierce', v_armor_pierce
      ),
    'range',
      jsonb_build_object(
        'distance_m', v_distance_m,
        'band', v_range_band,
        'modifier', v_range_modifier
      ),
    'attack',
      jsonb_build_object(
        'roll', v_attack_roll,
        'skill_level', v_attack_skill_level,
        'skill_bonus', v_attack_skill_bonus,
        'manual_bonus', v_manual_attack_bonus,
        'manual_penalty', v_manual_attack_penalty,
        'total', v_attack_total
      ),
    'defense',
      jsonb_build_object(
        'roll', v_defense_roll,
        'skill_level', v_defense_skill_level,
        'effective_skill_level', v_effective_defense_skill_level,
        'skill_source', v_defense_skill_source,
        'hostile_adjacent_count', v_hostile_adjacent_count,
        'manual_bonus', v_manual_defense_bonus,
        'manual_penalty', v_manual_defense_penalty,
        'total', v_defense_total
      ),
    'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'body_critical_delta', v_body_critical_delta,
        'melee_strength_bonus', v_melee_strength_bonus
      ),
    'body_part',
      jsonb_build_object(
        'id', v_target_part.id,
        'name', v_target_part.part_name,
        'natural_armor_value', coalesce(v_target_part.natural_armor_value, 0),
        'armor_value', v_new_armor_value,
        'effective_armor', v_effective_armor,
        'armor_critical', v_new_armor_critical,
        'armor_max_critical', v_new_armor_max_critical,
        'armor_destroyed', v_new_armor_destroyed,
        'armor_items', v_armor_item_updates,
        'minor', v_new_minor,
        'serious', v_new_serious,
        'critical', v_new_critical,
        'max_critical', coalesce(v_target_part.max_critical, 0),
        'disabled', v_new_disabled,
        'destroyed', v_new_destroyed
      ),
    'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'effects',
      jsonb_build_object(
        'attacker',
          jsonb_build_object(
            'active_effects', coalesce(v_attacker_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_attacker_effect_summary->'modifiers', '{}'::jsonb)
          ),
        'target',
          jsonb_build_object(
            'active_effects', coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_target_effect_summary->'modifiers', '{}'::jsonb),
            'flags', coalesce(v_target_effect_summary->'flags', '{}'::jsonb),
            'helpless_source', v_target_helpless_source
          )
      ),
    'armor_summary',
      jsonb_build_object(
        'total_armor_value', v_target_armor_total,
        'armor_class', v_target_armor_class,
        'head_protected', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'head_protected'), '')::boolean, false),
        'torso_protected', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'torso_protected'), '')::boolean, false),
        'special_protection', coalesce(nullif(jsonb_extract_path_text(v_target_armor_summary, 'special_protection'), '')::boolean, false),
        'helpless_execution_protected', v_target_helpless_execution_protected
      ),
    'target_state', v_target_state,
    'attacker_state', v_attacker_state,
    'execution', v_execution_info,
    'log_id', v_log_id
  )
  into v_result;

  return v_result;
end;
$$;

grant execute on function public.odyssey_normalize_part_code(text) to anon, authenticated;
grant execute on function public.odyssey_resolve_body_part_code(text, text) to anon, authenticated;
grant execute on function public.odyssey_get_armor_class(integer) to anon, authenticated;
grant execute on function public.odyssey_get_armor_class_definition(integer) to anon, authenticated;
grant execute on function public.odyssey_build_armor_penalty_effect_data(jsonb) to anon, authenticated;
grant execute on function public.get_character_armor_summary(uuid) to anon, authenticated;
grant execute on function public.recompute_character_armor(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_equipment_item_json(uuid) to anon, authenticated;
grant execute on function public.get_character_equipment(uuid) to anon, authenticated;
grant execute on function public.create_character_equipment_item(jsonb) to anon, authenticated;
grant execute on function public.equip_character_equipment_item(uuid, uuid) to anon, authenticated;
grant execute on function public.unequip_character_equipment_item(uuid) to anon, authenticated;
grant execute on function public.update_character_equipment_item(jsonb) to anon, authenticated;
grant execute on function public.get_character_rule_sheet(uuid) to anon, authenticated;
grant execute on function public.get_effective_character_stats(uuid) to anon, authenticated;
grant execute on function public.odyssey_refresh_character_combat_state(uuid) to anon, authenticated;
grant execute on function public.odyssey_apply_equipment_critical_damage(uuid, integer) to anon, authenticated;
grant execute on function public.perform_attack(jsonb) to anon, authenticated;
