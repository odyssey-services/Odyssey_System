create extension if not exists pgcrypto;

create table if not exists public.odyssey_characters (
  id uuid primary key default gen_random_uuid(),
  character_key text not null unique,
  character_bucket text not null default 'player' check (character_bucket in ('player', 'npc_template', 'npc_active')),
  source_template_key text not null default '',
  enabled boolean not null default true,
  tracker_minor integer not null default 0 check (tracker_minor between 0 and 4),
  tracker_serious integer not null default 0 check (tracker_serious between 0 and 2),
  owner_player_id text not null default '',
  owner_player_name text not null default '',
  resources jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_characteristics (
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  key text not null,
  label text not null default '',
  value integer not null default 0 check (value between 0 and 20),
  sort_order integer not null default 0,
  primary key (character_id, key)
);

create table if not exists public.odyssey_character_skills (
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  name text not null,
  value integer not null default 0 check (value between 0 and 10),
  category text not null default 'applied' check (category in ('combat', 'applied', 'abilities')),
  strength_bonus boolean not null default false,
  sort_order integer not null default 0,
  primary key (character_id, name)
);

create table if not exists public.odyssey_character_weapons (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  weapon_kind text not null default 'melee' check (weapon_kind in ('melee', 'ranged')),
  name text not null default 'Weapon',
  damage integer not null default 0 check (damage between -99 and 99),
  accuracy integer not null default 0 check (accuracy between -99 and 99),
  ammo_current integer not null default 0 check (ammo_current >= 0),
  ammo_max integer not null default 0 check (ammo_max >= 0),
  sort_order integer not null default 0
);

create table if not exists public.odyssey_character_body_parts (
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  part_key text not null check (part_key in ('Head', 'L.Arm', 'R.Arm', 'Torso', 'L.Leg', 'R.Leg', 'Shield', 'Special')),
  current_hp integer not null default 0 check (current_hp >= 0),
  max_hp integer not null default 0 check (max_hp >= 0),
  armor integer not null default 0 check (armor >= 0),
  minor integer not null default 0 check (minor between 0 and 3),
  serious integer not null default 0 check (serious between 0 and 1),
  sort_order integer not null default 0,
  primary key (character_id, part_key)
);

create or replace function public.odyssey_touch_updated_at()
returns trigger
language plpgsql
as $body$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$body$;

drop trigger if exists odyssey_touch_updated_at on public.odyssey_characters;

create trigger odyssey_touch_updated_at
before update on public.odyssey_characters
for each row
execute function public.odyssey_touch_updated_at();
