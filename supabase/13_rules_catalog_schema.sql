create extension if not exists pgcrypto;

drop function if exists public.get_odyssey_character_sheet(text);
drop function if exists public.upsert_odyssey_character_sheet(jsonb);
drop function if exists public.recompute_odyssey_character_combat_state(uuid);
drop function if exists public.apply_damage(jsonb);
drop function if exists public.heal_damage(jsonb);
drop function if exists public.add_effect(jsonb);
drop function if exists public.remove_effect(jsonb);
drop function if exists public.roll_initiative(jsonb);
drop function if exists public.advance_turn(jsonb);
drop function if exists public.clone_odyssey_npc_active(jsonb);
drop function if exists public.get_character_rule_sheet(uuid);
drop function if exists public.initialize_character_rule_defaults(uuid);

drop table if exists public.odyssey_character_perks cascade;
drop table if exists public.odyssey_perk_defs cascade;
drop table if exists public.odyssey_skill_level_requirements cascade;
drop table if exists public.odyssey_character_skills cascade;
drop table if exists public.odyssey_skill_defs cascade;
drop table if exists public.odyssey_character_attributes cascade;
drop table if exists public.odyssey_attribute_defs cascade;
drop table if exists public.odyssey_character_body_parts cascade;
drop table if exists public.odyssey_body_part_defs cascade;
drop table if exists public.odyssey_character_characteristics cascade;

create table if not exists public.odyssey_attribute_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  default_value integer not null default 8 check (default_value >= 0),
  max_value integer not null default 15 check (max_value >= default_value),
  cost_per_level integer not null default 2 check (cost_per_level >= 0),
  description text,
  sort_order integer not null default 0,
  is_custom boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_attributes (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  attribute_def_id uuid not null references public.odyssey_attribute_defs(id) on delete cascade,
  value integer not null check (value >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_id, attribute_def_id)
);

create index if not exists odyssey_character_attributes_character_idx
  on public.odyssey_character_attributes (character_id);

create index if not exists odyssey_character_attributes_attribute_idx
  on public.odyssey_character_attributes (attribute_def_id);

create table if not exists public.odyssey_skill_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text not null check (category in ('combat', 'applied', 'survival', 'vehicle', 'social', 'passive', 'psionic', 'custom')),
  max_level integer not null check (max_level in (1, 3, 5)),
  main_attribute_id uuid references public.odyssey_attribute_defs(id),
  secondary_attribute_id uuid references public.odyssey_attribute_defs(id),
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_skills (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  skill_def_id uuid not null references public.odyssey_skill_defs(id) on delete cascade,
  level integer not null default 0 check (level >= 0),
  governing_attribute_def_id uuid references public.odyssey_attribute_defs(id) on delete set null,
  custom_name text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_id, skill_def_id)
);

create index if not exists odyssey_character_skills_character_idx
  on public.odyssey_character_skills (character_id);

create index if not exists odyssey_character_skills_skill_idx
  on public.odyssey_character_skills (skill_def_id);

create index if not exists odyssey_character_skills_governing_attribute_idx
  on public.odyssey_character_skills (governing_attribute_def_id);

create table if not exists public.odyssey_skill_level_requirements (
  id uuid primary key default gen_random_uuid(),
  skill_def_id uuid not null references public.odyssey_skill_defs(id) on delete cascade,
  level integer not null check (level >= 0),
  main_attribute_required integer,
  secondary_attribute_required integer,
  requires_critical_successes boolean not null default false,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (skill_def_id, level)
);

create index if not exists odyssey_skill_level_requirements_skill_idx
  on public.odyssey_skill_level_requirements (skill_def_id);

create table if not exists public.odyssey_perk_defs (
  id uuid primary key default gen_random_uuid(),
  skill_def_id uuid references public.odyssey_skill_defs(id) on delete set null,
  code text not null unique,
  name text not null,
  required_skill_level integer not null default 0 check (required_skill_level >= 0),
  description text,
  effect_type text check (
    effect_type is null
    or effect_type in (
      'add_modifier',
      'remove_modifier',
      'ignore_penalty',
      'modify_fire_mode',
      'modify_range_penalty',
      'grant_advantage',
      'replace_defense_skill',
      'grant_reaction',
      'special_action'
    )
  ),
  effect_data jsonb not null default '{}'::jsonb,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_perks (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  perk_def_id uuid not null references public.odyssey_perk_defs(id) on delete cascade,
  acquired_at timestamptz not null default timezone('utc', now()),
  notes text,
  unique (character_id, perk_def_id)
);

create index if not exists odyssey_character_perks_character_idx
  on public.odyssey_character_perks (character_id);

create index if not exists odyssey_character_perks_perk_idx
  on public.odyssey_character_perks (perk_def_id);

create table if not exists public.odyssey_body_part_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text not null,
  default_max_critical integer not null default 1,
  default_armor_slot text,
  is_vital boolean not null default false,
  can_hold_weapon boolean not null default false,
  can_use_item boolean not null default false,
  can_be_targeted boolean not null default true,
  aim_difficulty integer not null default 0,
  serious_counts_as_critical boolean not null default false,
  sort_order integer not null default 0,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (default_max_critical >= 0)
);

create table if not exists public.odyssey_character_body_parts (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  body_part_def_id uuid references public.odyssey_body_part_defs(id) on delete set null,
  custom_name text,
  part_key text not null,
  max_critical integer not null default 1 check (max_critical >= 0),
  critical integer not null default 0 check (critical >= 0),
  serious integer not null default 0 check (serious >= 0),
  minor integer not null default 0 check (minor >= 0),
  armor_value integer not null default 0 check (armor_value >= 0),
  armor_item_id uuid,
  disabled boolean not null default false,
  destroyed boolean not null default false,
  sort_order integer not null default 0,
  notes text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_id, part_key)
);

create index if not exists odyssey_character_body_parts_character_idx
  on public.odyssey_character_body_parts (character_id);

create index if not exists odyssey_character_body_parts_def_idx
  on public.odyssey_character_body_parts (body_part_def_id);

create index if not exists odyssey_character_body_parts_part_key_idx
  on public.odyssey_character_body_parts (part_key);

comment on column public.odyssey_perk_defs.effect_data is
  'Simple automatic effect payloads. Future Stage 2 range model uses distance bands clinch/short/medium/long where 1 grid cell equals 1 meter.';

comment on column public.odyssey_body_part_defs.aim_difficulty is
  'Positive aimed-shot penalty value. Example: 30 means -30 to aimed attack.';

comment on column public.odyssey_body_part_defs.default_max_critical is
  'Stage 1 seeded defaults currently use Head=1, Torso=3, Arms/Legs=2, Shield=1, Special=1. Later stages may modify character-specific capacity.';

drop trigger if exists odyssey_touch_updated_at_attribute_defs on public.odyssey_attribute_defs;
create trigger odyssey_touch_updated_at_attribute_defs
before update on public.odyssey_attribute_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_attributes on public.odyssey_character_attributes;
create trigger odyssey_touch_updated_at_character_attributes
before update on public.odyssey_character_attributes
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_skill_defs on public.odyssey_skill_defs;
create trigger odyssey_touch_updated_at_skill_defs
before update on public.odyssey_skill_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_skills on public.odyssey_character_skills;
create trigger odyssey_touch_updated_at_character_skills
before update on public.odyssey_character_skills
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_skill_level_requirements on public.odyssey_skill_level_requirements;
create trigger odyssey_touch_updated_at_skill_level_requirements
before update on public.odyssey_skill_level_requirements
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_perk_defs on public.odyssey_perk_defs;
create trigger odyssey_touch_updated_at_perk_defs
before update on public.odyssey_perk_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_body_part_defs on public.odyssey_body_part_defs;
create trigger odyssey_touch_updated_at_body_part_defs
before update on public.odyssey_body_part_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_body_parts on public.odyssey_character_body_parts;
create trigger odyssey_touch_updated_at_body_parts
before update on public.odyssey_character_body_parts
for each row
execute function public.odyssey_touch_updated_at();

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
              'armor_value', b.armor_value,
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

create or replace function public.initialize_character_rule_defaults(p_character_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_inserted_attributes integer := 0;
  v_inserted_body_parts integer := 0;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  into v_character_exists;

  if not v_character_exists then
    raise exception 'Character % was not found', p_character_id;
  end if;

  with inserted as (
    insert into public.odyssey_character_attributes (
      character_id,
      attribute_def_id,
      value
    )
    select
      p_character_id,
      d.id,
      d.default_value
    from public.odyssey_attribute_defs d
    where d.is_custom = false
      and not exists (
        select 1
        from public.odyssey_character_attributes a
        where a.character_id = p_character_id
          and a.attribute_def_id = d.id
      )
    returning 1
  )
  select count(*) into v_inserted_attributes from inserted;

  with inserted as (
    insert into public.odyssey_character_body_parts (
      character_id,
      body_part_def_id,
      part_key,
      max_critical,
      critical,
      serious,
      minor,
      armor_value,
      disabled,
      destroyed,
      sort_order,
      notes
    )
    select
      p_character_id,
      d.id,
      d.name,
      d.default_max_critical,
      0,
      0,
      0,
      0,
      false,
      false,
      d.sort_order,
      ''
    from public.odyssey_body_part_defs d
    where d.is_custom = false
      and not exists (
        select 1
        from public.odyssey_character_body_parts b
        where b.character_id = p_character_id
          and b.part_key = d.name
      )
    returning 1
  )
  select count(*) into v_inserted_body_parts from inserted;

  return jsonb_build_object(
    'character_id', p_character_id,
    'inserted_attributes', v_inserted_attributes,
    'inserted_body_parts', v_inserted_body_parts,
    'rule_sheet', public.get_character_rule_sheet(p_character_id)
  );
end;
$$;

alter table public.odyssey_attribute_defs enable row level security;
alter table public.odyssey_character_attributes enable row level security;
alter table public.odyssey_skill_defs enable row level security;
alter table public.odyssey_character_skills enable row level security;
alter table public.odyssey_skill_level_requirements enable row level security;
alter table public.odyssey_perk_defs enable row level security;
alter table public.odyssey_character_perks enable row level security;
alter table public.odyssey_body_part_defs enable row level security;
alter table public.odyssey_character_body_parts enable row level security;

drop policy if exists "odyssey_attribute_defs_full_access" on public.odyssey_attribute_defs;
create policy "odyssey_attribute_defs_full_access"
on public.odyssey_attribute_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_attributes_full_access" on public.odyssey_character_attributes;
create policy "odyssey_character_attributes_full_access"
on public.odyssey_character_attributes
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_skill_defs_full_access" on public.odyssey_skill_defs;
create policy "odyssey_skill_defs_full_access"
on public.odyssey_skill_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_skills_full_access" on public.odyssey_character_skills;
create policy "odyssey_character_skills_full_access"
on public.odyssey_character_skills
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_skill_level_requirements_full_access" on public.odyssey_skill_level_requirements;
create policy "odyssey_skill_level_requirements_full_access"
on public.odyssey_skill_level_requirements
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_perk_defs_full_access" on public.odyssey_perk_defs;
create policy "odyssey_perk_defs_full_access"
on public.odyssey_perk_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_perks_full_access" on public.odyssey_character_perks;
create policy "odyssey_character_perks_full_access"
on public.odyssey_character_perks
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_body_part_defs_full_access" on public.odyssey_body_part_defs;
create policy "odyssey_body_part_defs_full_access"
on public.odyssey_body_part_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_body_parts_full_access" on public.odyssey_character_body_parts;
create policy "odyssey_character_body_parts_full_access"
on public.odyssey_character_body_parts
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_attribute_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_attributes to anon, authenticated;
grant select, insert, update, delete on public.odyssey_skill_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_skills to anon, authenticated;
grant select, insert, update, delete on public.odyssey_skill_level_requirements to anon, authenticated;
grant select, insert, update, delete on public.odyssey_perk_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_perks to anon, authenticated;
grant select, insert, update, delete on public.odyssey_body_part_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_body_parts to anon, authenticated;

grant execute on function public.get_character_rule_sheet(uuid) to anon, authenticated;
grant execute on function public.initialize_character_rule_defaults(uuid) to anon, authenticated;
