create extension if not exists pgcrypto;

alter table public.odyssey_perk_defs
  add column if not exists sort_order integer not null default 0;

alter table public.odyssey_item_defs
  drop constraint if exists odyssey_item_defs_use_action_type_check;

alter table public.odyssey_item_defs
  add constraint odyssey_item_defs_use_action_type_check
  check (use_action_type in ('none', 'consume', 'heal', 'reload_feature_resource', 'manual', 'custom'));

create index if not exists odyssey_perk_defs_sort_idx
  on public.odyssey_perk_defs (sort_order, name, code);

create table if not exists public.odyssey_weapon_model_abilities (
  id uuid primary key default gen_random_uuid(),
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete cascade,
  profile_id uuid null references public.odyssey_weapon_model_profiles(id) on delete cascade,
  ability_def_id uuid not null references public.odyssey_ability_defs(id) on delete restrict,
  grant_mode text not null default 'available' check (grant_mode in ('available', 'passive', 'activated')),
  is_enabled boolean not null default true,
  sort_order integer not null default 0,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists odyssey_weapon_model_abilities_unique_idx
  on public.odyssey_weapon_model_abilities (
    weapon_model_id,
    ability_def_id,
    coalesce(profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists odyssey_weapon_model_abilities_weapon_idx
  on public.odyssey_weapon_model_abilities (weapon_model_id, sort_order, created_at);

create index if not exists odyssey_weapon_model_abilities_profile_idx
  on public.odyssey_weapon_model_abilities (profile_id, sort_order, created_at);

create index if not exists odyssey_weapon_model_abilities_ability_idx
  on public.odyssey_weapon_model_abilities (ability_def_id, sort_order, created_at);

create table if not exists public.odyssey_equipment_model_abilities (
  id uuid primary key default gen_random_uuid(),
  equipment_model_id uuid not null references public.odyssey_equipment_model_defs(id) on delete cascade,
  ability_def_id uuid not null references public.odyssey_ability_defs(id) on delete restrict,
  grant_mode text not null default 'available' check (grant_mode in ('available', 'passive', 'activated')),
  is_enabled boolean not null default true,
  sort_order integer not null default 0,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (equipment_model_id, ability_def_id)
);

create index if not exists odyssey_equipment_model_abilities_equipment_idx
  on public.odyssey_equipment_model_abilities (equipment_model_id, sort_order, created_at);

create index if not exists odyssey_equipment_model_abilities_ability_idx
  on public.odyssey_equipment_model_abilities (ability_def_id, sort_order, created_at);

create table if not exists public.odyssey_item_def_abilities (
  id uuid primary key default gen_random_uuid(),
  item_def_id uuid not null references public.odyssey_item_defs(id) on delete cascade,
  ability_def_id uuid not null references public.odyssey_ability_defs(id) on delete restrict,
  grant_mode text not null default 'activated' check (grant_mode in ('available', 'passive', 'activated')),
  is_enabled boolean not null default true,
  sort_order integer not null default 0,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (item_def_id, ability_def_id)
);

create index if not exists odyssey_item_def_abilities_item_idx
  on public.odyssey_item_def_abilities (item_def_id, sort_order, created_at);

create index if not exists odyssey_item_def_abilities_ability_idx
  on public.odyssey_item_def_abilities (ability_def_id, sort_order, created_at);

alter table public.odyssey_weapon_model_abilities enable row level security;
alter table public.odyssey_equipment_model_abilities enable row level security;
alter table public.odyssey_item_def_abilities enable row level security;

drop policy if exists "odyssey_weapon_model_abilities_full_access" on public.odyssey_weapon_model_abilities;
create policy "odyssey_weapon_model_abilities_full_access"
on public.odyssey_weapon_model_abilities
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_equipment_model_abilities_full_access" on public.odyssey_equipment_model_abilities;
create policy "odyssey_equipment_model_abilities_full_access"
on public.odyssey_equipment_model_abilities
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_item_def_abilities_full_access" on public.odyssey_item_def_abilities;
create policy "odyssey_item_def_abilities_full_access"
on public.odyssey_item_def_abilities
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_weapon_model_abilities to anon, authenticated;
grant select, insert, update, delete on public.odyssey_equipment_model_abilities to anon, authenticated;
grant select, insert, update, delete on public.odyssey_item_def_abilities to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_weapon_model_abilities on public.odyssey_weapon_model_abilities;
create trigger odyssey_touch_updated_at_weapon_model_abilities
before update on public.odyssey_weapon_model_abilities
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_equipment_model_abilities on public.odyssey_equipment_model_abilities;
create trigger odyssey_touch_updated_at_equipment_model_abilities
before update on public.odyssey_equipment_model_abilities
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_item_def_abilities on public.odyssey_item_def_abilities;
create trigger odyssey_touch_updated_at_item_def_abilities
before update on public.odyssey_item_def_abilities
for each row
execute function public.odyssey_touch_updated_at();

create or replace function public.odyssey_ensure_default_weapon_profile(
  p_weapon_model_id uuid
)
returns uuid
language plpgsql
as $$
declare
  v_profile_id uuid := null;
begin
  select p.id
  into v_profile_id
  from public.odyssey_weapon_model_profiles p
  where p.weapon_model_id = p_weapon_model_id
    and p.is_default = true
  order by p.sort_order, p.created_at, p.id
  limit 1;

  if v_profile_id is not null then
    return v_profile_id;
  end if;

  insert into public.odyssey_weapon_model_profiles (
    weapon_model_id,
    code,
    name,
    description,
    weapon_class_id,
    linked_skill_id,
    caliber_id,
    range_profile_id,
    accuracy_modifier,
    base_melee_damage,
    attack_type,
    is_default,
    data,
    tags,
    sort_order
  )
  select
    wm.id,
    'default',
    'Default',
    'Auto-generated default weapon profile.',
    wm.weapon_class_id,
    wm.linked_skill_id,
    wm.caliber_id,
    wm.range_profile_id,
    wm.base_accuracy_bonus,
    coalesce(wm.base_melee_damage, 0),
    case
      when wm.caliber_id is null then 'melee'
      else 'ranged'
    end,
    true,
    '{}'::jsonb,
    coalesce(wm.tags, '[]'::jsonb),
    0
  from public.odyssey_weapon_model_defs wm
  where wm.id = p_weapon_model_id
  on conflict (weapon_model_id, code) do update
  set
    name = excluded.name,
    description = excluded.description,
    weapon_class_id = excluded.weapon_class_id,
    linked_skill_id = excluded.linked_skill_id,
    caliber_id = excluded.caliber_id,
    range_profile_id = excluded.range_profile_id,
    accuracy_modifier = excluded.accuracy_modifier,
    base_melee_damage = excluded.base_melee_damage,
    attack_type = excluded.attack_type,
    is_default = true,
    data = excluded.data,
    tags = excluded.tags,
    sort_order = excluded.sort_order
  returning id into v_profile_id;

  update public.odyssey_weapon_model_profiles
  set is_default = (id = v_profile_id)
  where weapon_model_id = p_weapon_model_id
    and is_default is distinct from (id = v_profile_id);

  return v_profile_id;
end;
$$;

do $$
declare
  v_has_legacy_fire_modes boolean := to_regclass('public.odyssey_weapon_model_fire_modes') is not null;
  v_has_legacy_magazines boolean := to_regclass('public.odyssey_weapon_model_magazines') is not null;
begin
  if v_has_legacy_fire_modes or v_has_legacy_magazines then
    perform public.odyssey_ensure_default_weapon_profile(wm.id)
    from public.odyssey_weapon_model_defs wm;
  end if;

  if v_has_legacy_fire_modes then
    insert into public.odyssey_weapon_profile_fire_modes (
      profile_id,
      fire_mode_id,
      is_default,
      sort_order
    )
    select
      p.id,
      legacy.fire_mode_id,
      legacy.is_default,
      row_number() over (
        partition by p.id
        order by legacy.is_default desc, legacy.created_at, legacy.id
      ) * 10
    from public.odyssey_weapon_model_profiles p
    join public.odyssey_weapon_model_fire_modes legacy
      on legacy.weapon_model_id = p.weapon_model_id
    where p.code = 'default'
    on conflict (profile_id, fire_mode_id) do update
    set
      is_default = excluded.is_default,
      sort_order = excluded.sort_order;
  end if;

  if v_has_legacy_magazines then
    insert into public.odyssey_weapon_profile_magazines (
      profile_id,
      magazine_def_id,
      is_default,
      sort_order
    )
    select
      p.id,
      legacy.magazine_def_id,
      legacy.is_default,
      row_number() over (
        partition by p.id
        order by legacy.is_default desc, legacy.created_at, legacy.id
      ) * 10
    from public.odyssey_weapon_model_profiles p
    join public.odyssey_weapon_model_magazines legacy
      on legacy.weapon_model_id = p.weapon_model_id
    where p.code = 'default'
    on conflict (profile_id, magazine_def_id) do update
    set
      is_default = excluded.is_default,
      sort_order = excluded.sort_order;
  end if;
end;
$$;

drop table if exists public.odyssey_weapon_model_fire_modes cascade;
drop table if exists public.odyssey_weapon_model_magazines cascade;

grant execute on function public.odyssey_ensure_default_weapon_profile(uuid) to anon, authenticated;
