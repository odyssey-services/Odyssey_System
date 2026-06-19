alter table public.odyssey_characters
  add column if not exists campaign_id text not null default '',
  add column if not exists room_id text not null default '',
  add column if not exists active_combat_state_version integer not null default 0,
  add column if not exists is_deleted boolean not null default false;

alter table public.odyssey_character_body_parts
  add column if not exists critical integer not null default 0,
  add column if not exists max_critical integer not null default 0,
  add column if not exists destroyed boolean not null default false,
  add column if not exists disabled boolean not null default false,
  add column if not exists notes text not null default '',
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

create table if not exists public.odyssey_character_effects (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  effect_key text not null default '',
  name text not null,
  description text not null default '',
  source text not null default '',
  source_character_id uuid null references public.odyssey_characters(id) on delete set null,
  duration_type text not null default 'manual' check (duration_type in ('manual', 'rounds', 'until_turn_start', 'until_turn_end', 'scene')),
  rounds_left integer null,
  data jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_by text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_combat_state (
  character_id uuid primary key references public.odyssey_characters(id) on delete cascade,
  campaign_id text not null default '',
  room_id text not null default '',
  body_summary jsonb not null default '{}'::jsonb,
  armor_summary jsonb not null default '{}'::jsonb,
  active_effects jsonb not null default '[]'::jsonb,
  active_penalties jsonb not null default '[]'::jsonb,
  overlay_text text not null default '',
  overlay_data jsonb not null default '{}'::jsonb,
  tracker_minor integer not null default 0,
  tracker_serious integer not null default 0,
  is_alive boolean not null default true,
  is_conscious boolean not null default true,
  state_version integer not null default 0,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_combat_log (
  id uuid primary key default gen_random_uuid(),
  campaign_id text not null default '',
  room_id text not null default '',
  scene_id text not null default '',
  encounter_id uuid null,
  round_number integer null,
  actor_character_id uuid null references public.odyssey_characters(id) on delete set null,
  target_character_id uuid null references public.odyssey_characters(id) on delete set null,
  event_type text not null,
  message text not null default '',
  data jsonb not null default '{}'::jsonb,
  created_by text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_token_links (
  id uuid primary key default gen_random_uuid(),
  campaign_id text not null default '',
  room_id text not null default '',
  scene_id text not null default '',
  token_id text not null,
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  character_key text not null default '',
  token_name text not null default '',
  token_layer text not null default '',
  is_active boolean not null default true,
  last_seen_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

do $body$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'odyssey_token_links_room_scene_token_key'
  ) then
    alter table public.odyssey_token_links
      add constraint odyssey_token_links_room_scene_token_key unique (room_id, scene_id, token_id);
  end if;
end;
$body$;

create table if not exists public.odyssey_combat_encounters (
  id uuid primary key default gen_random_uuid(),
  campaign_id text not null default '',
  room_id text not null default '',
  scene_id text not null default '',
  name text not null default 'Combat',
  status text not null default 'active' check (status in ('active', 'paused', 'finished')),
  current_round integer not null default 1,
  active_character_id uuid null references public.odyssey_characters(id) on delete set null,
  active_entry_id uuid null,
  created_by text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz null
);

create table if not exists public.odyssey_initiative_entries (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid not null references public.odyssey_combat_encounters(id) on delete cascade,
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  initiative_value integer not null default 0,
  reaction_value integer not null default 0,
  roll_value integer not null default 0,
  bonus_value integer not null default 0,
  order_index integer not null default 0,
  has_acted boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

do $body$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'odyssey_initiative_entries_encounter_character_key'
  ) then
    alter table public.odyssey_initiative_entries
      add constraint odyssey_initiative_entries_encounter_character_key unique (encounter_id, character_id);
  end if;
end;
$body$;

create index if not exists odyssey_combat_log_room_created_idx
  on public.odyssey_combat_log (campaign_id, room_id, created_at desc);

create index if not exists odyssey_combat_log_target_created_idx
  on public.odyssey_combat_log (target_character_id, created_at desc);

create index if not exists odyssey_combat_log_actor_created_idx
  on public.odyssey_combat_log (actor_character_id, created_at desc);

create index if not exists odyssey_character_effects_character_active_idx
  on public.odyssey_character_effects (character_id, is_active, updated_at desc);

create index if not exists odyssey_token_links_character_idx
  on public.odyssey_token_links (character_id);

create index if not exists odyssey_token_links_room_scene_idx
  on public.odyssey_token_links (room_id, scene_id);

create index if not exists odyssey_token_links_room_scene_token_idx
  on public.odyssey_token_links (room_id, scene_id, token_id);

drop trigger if exists odyssey_touch_updated_at_body_parts on public.odyssey_character_body_parts;
create trigger odyssey_touch_updated_at_body_parts
before update on public.odyssey_character_body_parts
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_effects on public.odyssey_character_effects;
create trigger odyssey_touch_updated_at_effects
before update on public.odyssey_character_effects
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_combat_state on public.odyssey_character_combat_state;
create trigger odyssey_touch_updated_at_combat_state
before update on public.odyssey_character_combat_state
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_token_links on public.odyssey_token_links;
create trigger odyssey_touch_updated_at_token_links
before update on public.odyssey_token_links
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_encounters on public.odyssey_combat_encounters;
create trigger odyssey_touch_updated_at_encounters
before update on public.odyssey_combat_encounters
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_initiative_entries on public.odyssey_initiative_entries;
create trigger odyssey_touch_updated_at_initiative_entries
before update on public.odyssey_initiative_entries
for each row
execute function public.odyssey_touch_updated_at();
