create extension if not exists pgcrypto;

-- Stage 2 cleanup note:
-- This migration is intentionally destructive for armory tables in the current reset/empty setup.
-- After real armory data exists, future schema changes should use ALTER TABLE or other data-preserving migrations.

drop function if exists public.get_character_armory(uuid);
drop function if exists public.create_character_weapon(uuid, uuid, text);
drop function if exists public.create_character_magazine(uuid, uuid, uuid, integer, text);
drop function if exists public.load_magazine(uuid, uuid, uuid);
drop function if exists public.unload_magazine(uuid, uuid);
drop function if exists public.switch_weapon_fire_mode(uuid, uuid, uuid);
drop function if exists public.calculate_range_band(numeric);
drop function if exists public.get_weapon_range_modifier(uuid, numeric);

drop table if exists public.odyssey_character_magazines cascade;
drop table if exists public.odyssey_weapon_model_magazines cascade;
drop table if exists public.odyssey_magazine_defs cascade;
drop table if exists public.odyssey_weapon_model_fire_modes cascade;
drop table if exists public.odyssey_weapon_model_defs cascade;
drop table if exists public.odyssey_fire_mode_defs cascade;
drop table if exists public.odyssey_range_profile_modifiers cascade;
drop table if exists public.odyssey_range_profile_defs cascade;
drop table if exists public.odyssey_range_band_defs cascade;
drop table if exists public.odyssey_weapon_class_defs cascade;
drop table if exists public.odyssey_ammo_type_defs cascade;
drop table if exists public.odyssey_caliber_defs cascade;
drop table if exists public.odyssey_character_weapons cascade;

create table if not exists public.odyssey_caliber_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  base_damage_per_round integer not null check (base_damage_per_round >= 0),
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_ammo_type_defs (
  id uuid primary key default gen_random_uuid(),
  caliber_id uuid not null references public.odyssey_caliber_defs(id) on delete cascade,
  code text not null,
  name text not null,
  damage_modifier integer not null default 0,
  accuracy_modifier integer not null default 0,
  armor_pierce integer not null default 0,
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (caliber_id, code)
);

create index if not exists odyssey_ammo_type_defs_caliber_idx
  on public.odyssey_ammo_type_defs (caliber_id);

create table if not exists public.odyssey_weapon_class_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_range_band_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  min_distance_m numeric not null check (min_distance_m >= 0),
  max_distance_m numeric check (max_distance_m is null or max_distance_m >= min_distance_m),
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_range_profile_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_range_profile_modifiers (
  id uuid primary key default gen_random_uuid(),
  range_profile_id uuid not null references public.odyssey_range_profile_defs(id) on delete cascade,
  range_band_id uuid not null references public.odyssey_range_band_defs(id) on delete cascade,
  scaling_mode text not null default 'flat' check (scaling_mode in ('flat', 'scaling')),
  flat_modifier integer,
  scaling_start_modifier integer,
  scaling_end_modifier integer,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (range_profile_id, range_band_id),
  check (
    (
      scaling_mode = 'flat'
      and flat_modifier is not null
      and scaling_start_modifier is null
      and scaling_end_modifier is null
    )
    or (
      scaling_mode = 'scaling'
      and flat_modifier is null
      and scaling_start_modifier is not null
      and scaling_end_modifier is not null
    )
  )
);

create index if not exists odyssey_range_profile_modifiers_profile_idx
  on public.odyssey_range_profile_modifiers (range_profile_id);

create index if not exists odyssey_range_profile_modifiers_band_idx
  on public.odyssey_range_profile_modifiers (range_band_id);

create table if not exists public.odyssey_fire_mode_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  fixed_rounds integer check (fixed_rounds is null or fixed_rounds > 0),
  min_rounds integer check (min_rounds is null or min_rounds > 0),
  max_rounds integer check (max_rounds is null or max_rounds > 0),
  is_random boolean not null default false,
  accuracy_modifier integer not null default 0,
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (
      is_random = false
      and fixed_rounds is not null
      and min_rounds is null
      and max_rounds is null
    )
    or (
      is_random = true
      and fixed_rounds is null
      and min_rounds is not null
      and (max_rounds is null or max_rounds >= min_rounds)
    )
  )
);

create table if not exists public.odyssey_weapon_model_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  weapon_class_id uuid not null references public.odyssey_weapon_class_defs(id) on delete restrict,
  linked_skill_id uuid not null references public.odyssey_skill_defs(id) on delete restrict,
  caliber_id uuid references public.odyssey_caliber_defs(id) on delete restrict,
  range_profile_id uuid not null references public.odyssey_range_profile_defs(id) on delete restrict,
  base_accuracy_bonus integer not null default 0 check (base_accuracy_bonus between -99 and 99),
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_weapon_model_defs_class_idx
  on public.odyssey_weapon_model_defs (weapon_class_id);

create index if not exists odyssey_weapon_model_defs_skill_idx
  on public.odyssey_weapon_model_defs (linked_skill_id);

create index if not exists odyssey_weapon_model_defs_caliber_idx
  on public.odyssey_weapon_model_defs (caliber_id);

create index if not exists odyssey_weapon_model_defs_range_profile_idx
  on public.odyssey_weapon_model_defs (range_profile_id);

create table if not exists public.odyssey_weapon_model_fire_modes (
  id uuid primary key default gen_random_uuid(),
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete cascade,
  fire_mode_id uuid not null references public.odyssey_fire_mode_defs(id) on delete cascade,
  is_default boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  unique (weapon_model_id, fire_mode_id)
);

create unique index if not exists odyssey_weapon_model_fire_modes_one_default_idx
  on public.odyssey_weapon_model_fire_modes (weapon_model_id)
  where is_default = true;

create table if not exists public.odyssey_magazine_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  caliber_id uuid not null references public.odyssey_caliber_defs(id) on delete restrict,
  capacity integer not null check (capacity > 0),
  description text,
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_magazine_defs_caliber_idx
  on public.odyssey_magazine_defs (caliber_id);

create table if not exists public.odyssey_weapon_model_magazines (
  id uuid primary key default gen_random_uuid(),
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete cascade,
  magazine_def_id uuid not null references public.odyssey_magazine_defs(id) on delete cascade,
  is_default boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  unique (weapon_model_id, magazine_def_id)
);

create unique index if not exists odyssey_weapon_model_magazines_one_default_idx
  on public.odyssey_weapon_model_magazines (weapon_model_id)
  where is_default = true;

create table if not exists public.odyssey_character_magazines (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  magazine_def_id uuid not null references public.odyssey_magazine_defs(id) on delete restrict,
  ammo_type_id uuid not null references public.odyssey_ammo_type_defs(id) on delete restrict,
  current_rounds integer not null default 0 check (current_rounds >= 0),
  custom_name text,
  notes text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_character_magazines_character_idx
  on public.odyssey_character_magazines (character_id);

create index if not exists odyssey_character_magazines_magazine_def_idx
  on public.odyssey_character_magazines (magazine_def_id);

create index if not exists odyssey_character_magazines_ammo_type_idx
  on public.odyssey_character_magazines (ammo_type_id);

create table if not exists public.odyssey_character_weapons (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete restrict,
  custom_name text,
  loaded_magazine_id uuid references public.odyssey_character_magazines(id) on delete set null,
  selected_fire_mode_id uuid references public.odyssey_fire_mode_defs(id) on delete set null,
  notes text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_character_weapons_character_idx
  on public.odyssey_character_weapons (character_id);

create index if not exists odyssey_character_weapons_weapon_model_idx
  on public.odyssey_character_weapons (weapon_model_id);

create index if not exists odyssey_character_weapons_loaded_magazine_idx
  on public.odyssey_character_weapons (loaded_magazine_id);

create index if not exists odyssey_character_weapons_selected_fire_mode_idx
  on public.odyssey_character_weapons (selected_fire_mode_id);

drop trigger if exists odyssey_touch_updated_at_caliber_defs on public.odyssey_caliber_defs;
create trigger odyssey_touch_updated_at_caliber_defs
before update on public.odyssey_caliber_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_ammo_type_defs on public.odyssey_ammo_type_defs;
create trigger odyssey_touch_updated_at_ammo_type_defs
before update on public.odyssey_ammo_type_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_weapon_class_defs on public.odyssey_weapon_class_defs;
create trigger odyssey_touch_updated_at_weapon_class_defs
before update on public.odyssey_weapon_class_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_range_band_defs on public.odyssey_range_band_defs;
create trigger odyssey_touch_updated_at_range_band_defs
before update on public.odyssey_range_band_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_range_profile_defs on public.odyssey_range_profile_defs;
create trigger odyssey_touch_updated_at_range_profile_defs
before update on public.odyssey_range_profile_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_fire_mode_defs on public.odyssey_fire_mode_defs;
create trigger odyssey_touch_updated_at_fire_mode_defs
before update on public.odyssey_fire_mode_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_weapon_model_defs on public.odyssey_weapon_model_defs;
create trigger odyssey_touch_updated_at_weapon_model_defs
before update on public.odyssey_weapon_model_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_magazine_defs on public.odyssey_magazine_defs;
create trigger odyssey_touch_updated_at_magazine_defs
before update on public.odyssey_magazine_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_magazines on public.odyssey_character_magazines;
create trigger odyssey_touch_updated_at_character_magazines
before update on public.odyssey_character_magazines
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_weapons on public.odyssey_character_weapons;
create trigger odyssey_touch_updated_at_character_weapons
before update on public.odyssey_character_weapons
for each row
execute function public.odyssey_touch_updated_at();

create or replace function public.get_character_armory(p_character_id uuid)
returns jsonb
language sql
stable
as $$
  with selected_character as (
    select c.id
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  select case
    when exists(select 1 from selected_character) then
      jsonb_build_object(
        'character_id', p_character_id,
        'weapons',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', w.id,
                  'character_id', w.character_id,
                  'custom_name', w.custom_name,
                  'name', coalesce(nullif(trim(w.custom_name), ''), wm.name),
                  'notes', w.notes,
                  'sort_order', w.sort_order,
                  'model',
                    jsonb_build_object(
                      'id', wm.id,
                      'code', wm.code,
                      'name', wm.name,
                      'weapon_class', wc.code,
                      'weapon_class_name', wc.name,
                      'linked_skill', skill.code,
                      'linked_skill_name', skill.name,
                      'caliber', caliber.code,
                      'caliber_name', caliber.name,
                      'base_accuracy_bonus', wm.base_accuracy_bonus,
                      'range_profile', rp.code,
                      'range_profile_name', rp.name,
                      'tags', wm.tags
                    ),
                  'loaded_magazine',
                    case
                      when cm.id is null then null
                      else jsonb_build_object(
                        'id', cm.id,
                        'name', coalesce(nullif(trim(cm.custom_name), ''), md.name),
                        'custom_name', cm.custom_name,
                        'current_rounds', cm.current_rounds,
                        'capacity', md.capacity,
                        'ammo_type', ammo.code,
                        'ammo_type_name', ammo.name,
                        'magazine_def', md.code,
                        'magazine_def_name', md.name
                      )
                    end,
                  'selected_fire_mode',
                    case
                      when fm.id is null then null
                      else jsonb_build_object(
                        'id', fm.id,
                        'code', fm.code,
                        'name', fm.name,
                        'fixed_rounds', fm.fixed_rounds,
                        'min_rounds', fm.min_rounds,
                        'max_rounds', fm.max_rounds,
                        'is_random', fm.is_random,
                        'accuracy_modifier', fm.accuracy_modifier
                      )
                    end,
                  'available_fire_modes',
                    coalesce(
                      (
                        select jsonb_agg(
                          jsonb_build_object(
                            'id', afm.id,
                            'code', afm.code,
                            'name', afm.name,
                            'fixed_rounds', afm.fixed_rounds,
                            'min_rounds', afm.min_rounds,
                            'max_rounds', afm.max_rounds,
                            'is_random', afm.is_random,
                            'accuracy_modifier', afm.accuracy_modifier,
                            'is_default', wmfm.is_default
                          )
                          order by wmfm.is_default desc, afm.sort_order, afm.name
                        )
                        from public.odyssey_weapon_model_fire_modes wmfm
                        join public.odyssey_fire_mode_defs afm on afm.id = wmfm.fire_mode_id
                        where wmfm.weapon_model_id = w.weapon_model_id
                      ),
                      '[]'::jsonb
                    ),
                  'compatible_magazines',
                    coalesce(
                      (
                        select jsonb_agg(
                          jsonb_build_object(
                            'id', cmd.id,
                            'code', cmd.code,
                            'name', cmd.name,
                            'capacity', cmd.capacity,
                            'caliber', cmdc.code,
                            'caliber_name', cmdc.name,
                            'is_default', wmm.is_default
                          )
                          order by wmm.is_default desc, cmd.sort_order, cmd.name
                        )
                        from public.odyssey_weapon_model_magazines wmm
                        join public.odyssey_magazine_defs cmd on cmd.id = wmm.magazine_def_id
                        join public.odyssey_caliber_defs cmdc on cmdc.id = cmd.caliber_id
                        where wmm.weapon_model_id = w.weapon_model_id
                      ),
                      '[]'::jsonb
                    )
                )
                order by w.sort_order, coalesce(nullif(trim(w.custom_name), ''), wm.name), w.id
              )
              from public.odyssey_character_weapons w
              join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
              join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
              join public.odyssey_skill_defs skill on skill.id = wm.linked_skill_id
              left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
              join public.odyssey_range_profile_defs rp on rp.id = wm.range_profile_id
              left join public.odyssey_character_magazines cm on cm.id = w.loaded_magazine_id
              left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
              left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
              left join public.odyssey_fire_mode_defs fm on fm.id = w.selected_fire_mode_id
              where w.character_id = p_character_id
            ),
            '[]'::jsonb
          ),
        'magazines',
          coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'id', cm.id,
                  'character_id', cm.character_id,
                  'custom_name', cm.custom_name,
                  'name', coalesce(nullif(trim(cm.custom_name), ''), md.name),
                  'notes', cm.notes,
                  'current_rounds', cm.current_rounds,
                  'magazine_def',
                    jsonb_build_object(
                      'id', md.id,
                      'code', md.code,
                      'name', md.name,
                      'capacity', md.capacity,
                      'caliber', caliber.code,
                      'caliber_name', caliber.name
                    ),
                  'ammo_type',
                    jsonb_build_object(
                      'id', ammo.id,
                      'code', ammo.code,
                      'name', ammo.name,
                      'caliber', ammo_caliber.code,
                      'caliber_name', ammo_caliber.name
                    )
                )
                order by md.sort_order, md.name, cm.created_at, cm.id
              )
              from public.odyssey_character_magazines cm
              join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
              join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
              join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
              join public.odyssey_caliber_defs ammo_caliber on ammo_caliber.id = ammo.caliber_id
              where cm.character_id = p_character_id
            ),
            '[]'::jsonb
          )
      )
    else
      jsonb_build_object(
        'character_id', p_character_id,
        'weapons', '[]'::jsonb,
        'magazines', '[]'::jsonb
      )
  end;
$$;

create or replace function public.create_character_weapon(
  p_character_id uuid,
  p_weapon_model_id uuid,
  p_custom_name text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_default_fire_mode_id uuid := null;
  v_sort_order integer := 0;
  v_weapon_id uuid;
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

  if not exists(
    select 1
    from public.odyssey_weapon_model_defs wm
    where wm.id = p_weapon_model_id
  ) then
    raise exception 'Weapon model % was not found', p_weapon_model_id;
  end if;

  select wmfm.fire_mode_id
  into v_default_fire_mode_id
  from public.odyssey_weapon_model_fire_modes wmfm
  where wmfm.weapon_model_id = p_weapon_model_id
    and wmfm.is_default = true
  order by wmfm.created_at
  limit 1;

  select coalesce(max(w.sort_order), 0) + 10
  into v_sort_order
  from public.odyssey_character_weapons w
  where w.character_id = p_character_id;

  insert into public.odyssey_character_weapons (
    character_id,
    weapon_model_id,
    custom_name,
    selected_fire_mode_id,
    notes,
    sort_order
  )
  values (
    p_character_id,
    p_weapon_model_id,
    nullif(trim(p_custom_name), ''),
    v_default_fire_mode_id,
    '',
    v_sort_order
  )
  returning id into v_weapon_id;

  return jsonb_build_object(
    'weapon_id', v_weapon_id,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.create_character_magazine(
  p_character_id uuid,
  p_magazine_def_id uuid,
  p_ammo_type_id uuid,
  p_current_rounds integer default null,
  p_custom_name text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_capacity integer := 0;
  v_magazine_caliber_id uuid;
  v_ammo_caliber_id uuid;
  v_current_rounds integer := 0;
  v_magazine_id uuid;
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

  select md.capacity, md.caliber_id
  into v_capacity, v_magazine_caliber_id
  from public.odyssey_magazine_defs md
  where md.id = p_magazine_def_id;

  if v_magazine_caliber_id is null then
    raise exception 'Magazine definition % was not found', p_magazine_def_id;
  end if;

  select ammo.caliber_id
  into v_ammo_caliber_id
  from public.odyssey_ammo_type_defs ammo
  where ammo.id = p_ammo_type_id;

  if v_ammo_caliber_id is null then
    raise exception 'Ammo type % was not found', p_ammo_type_id;
  end if;

  if v_magazine_caliber_id <> v_ammo_caliber_id then
    raise exception 'Ammo type % does not match magazine caliber', p_ammo_type_id;
  end if;

  v_current_rounds := coalesce(p_current_rounds, v_capacity);

  if v_current_rounds < 0 then
    raise exception 'Current rounds must be >= 0';
  end if;

  if v_current_rounds > v_capacity then
    raise exception 'Current rounds % exceed magazine capacity %', v_current_rounds, v_capacity;
  end if;

  insert into public.odyssey_character_magazines (
    character_id,
    magazine_def_id,
    ammo_type_id,
    current_rounds,
    custom_name,
    notes
  )
  values (
    p_character_id,
    p_magazine_def_id,
    p_ammo_type_id,
    v_current_rounds,
    nullif(trim(p_custom_name), ''),
    ''
  )
  returning id into v_magazine_id;

  return jsonb_build_object(
    'magazine_id', v_magazine_id,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.load_magazine(
  p_character_id uuid,
  p_weapon_id uuid,
  p_magazine_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_model_id uuid;
  v_weapon_caliber_id uuid;
  v_magazine_def_id uuid;
  v_magazine_caliber_id uuid;
begin
  select w.weapon_model_id, wm.caliber_id
  into v_weapon_model_id, v_weapon_caliber_id
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  where w.id = p_weapon_id
    and w.character_id = p_character_id;

  if v_weapon_model_id is null then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  select cm.magazine_def_id, md.caliber_id
  into v_magazine_def_id, v_magazine_caliber_id
  from public.odyssey_character_magazines cm
  join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  where cm.id = p_magazine_id
    and cm.character_id = p_character_id;

  if v_magazine_def_id is null then
    raise exception 'Magazine % was not found for character %', p_magazine_id, p_character_id;
  end if;

  if v_weapon_caliber_id is null then
    raise exception 'Weapon % does not use a magazine-caliber model', p_weapon_id;
  end if;

  if v_magazine_caliber_id <> v_weapon_caliber_id then
    raise exception 'Magazine % caliber does not match weapon % caliber', p_magazine_id, p_weapon_id;
  end if;

  if not exists(
    select 1
    from public.odyssey_weapon_model_magazines wmm
    where wmm.weapon_model_id = v_weapon_model_id
      and wmm.magazine_def_id = v_magazine_def_id
  ) then
    raise exception 'Magazine % is not compatible with weapon %', p_magazine_id, p_weapon_id;
  end if;

  update public.odyssey_character_weapons
  set loaded_magazine_id = p_magazine_id
  where id = p_weapon_id
    and character_id = p_character_id;

  return jsonb_build_object(
    'weapon_id', p_weapon_id,
    'loaded_magazine_id', p_magazine_id,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.unload_magazine(
  p_character_id uuid,
  p_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
begin
  if not exists(
    select 1
    from public.odyssey_character_weapons w
    where w.id = p_weapon_id
      and w.character_id = p_character_id
  ) then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  update public.odyssey_character_weapons
  set loaded_magazine_id = null
  where id = p_weapon_id
    and character_id = p_character_id;

  return jsonb_build_object(
    'weapon_id', p_weapon_id,
    'loaded_magazine_id', null,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.switch_weapon_fire_mode(
  p_character_id uuid,
  p_weapon_id uuid,
  p_fire_mode_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_model_id uuid;
begin
  select w.weapon_model_id
  into v_weapon_model_id
  from public.odyssey_character_weapons w
  where w.id = p_weapon_id
    and w.character_id = p_character_id;

  if v_weapon_model_id is null then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  if not exists(
    select 1
    from public.odyssey_weapon_model_fire_modes wmfm
    where wmfm.weapon_model_id = v_weapon_model_id
      and wmfm.fire_mode_id = p_fire_mode_id
  ) then
    raise exception 'Fire mode % is not allowed for weapon %', p_fire_mode_id, p_weapon_id;
  end if;

  update public.odyssey_character_weapons
  set selected_fire_mode_id = p_fire_mode_id
  where id = p_weapon_id
    and character_id = p_character_id;

  return jsonb_build_object(
    'weapon_id', p_weapon_id,
    'selected_fire_mode_id', p_fire_mode_id,
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

create or replace function public.calculate_range_band(p_distance_m numeric)
returns jsonb
language sql
stable
as $$
  with distance_input as (
    select greatest(coalesce(p_distance_m, 0), 0)::numeric as distance_m
  )
  select coalesce(
    (
      select jsonb_build_object(
        'range_band', rb.code,
        'distance_m', di.distance_m
      )
      from distance_input di
      join public.odyssey_range_band_defs rb
        on di.distance_m >= rb.min_distance_m
       and (rb.max_distance_m is null or di.distance_m <= rb.max_distance_m)
      order by rb.sort_order
      limit 1
    ),
    jsonb_build_object(
      'range_band', null,
      'distance_m', greatest(coalesce(p_distance_m, 0), 0)::numeric
    )
  );
$$;

create or replace function public.get_weapon_range_modifier(
  p_weapon_model_id uuid,
  p_distance_m numeric
)
returns jsonb
language sql
stable
as $$
  with model_data as (
    select
      wm.id as weapon_model_id,
      rp.id as range_profile_id,
      rp.code as range_profile_code
    from public.odyssey_weapon_model_defs wm
    join public.odyssey_range_profile_defs rp on rp.id = wm.range_profile_id
    where wm.id = p_weapon_model_id
  ),
  distance_input as (
    select greatest(coalesce(p_distance_m, 0), 0)::numeric as distance_m
  ),
  range_band as (
    select
      rb.id,
      rb.code,
      rb.min_distance_m,
      rb.max_distance_m
    from distance_input di
    join public.odyssey_range_band_defs rb
      on di.distance_m >= rb.min_distance_m
     and (rb.max_distance_m is null or di.distance_m <= rb.max_distance_m)
    order by rb.sort_order
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'distance_m', di.distance_m,
        'range_band', rb.code,
        'range_profile', md.range_profile_code,
        'modifier', case when rpm.scaling_mode = 'flat' then rpm.flat_modifier else null end,
        'scaling_mode', rpm.scaling_mode,
        'scaling_start_modifier', rpm.scaling_start_modifier,
        'scaling_end_modifier', rpm.scaling_end_modifier
      )
      from model_data md
      join distance_input di on true
      left join range_band rb on true
      left join public.odyssey_range_profile_modifiers rpm
        on rpm.range_profile_id = md.range_profile_id
       and rpm.range_band_id = rb.id
    ),
    jsonb_build_object(
      'distance_m', greatest(coalesce(p_distance_m, 0), 0)::numeric,
      'range_band', null,
      'range_profile', null,
      'modifier', null,
      'scaling_mode', null,
      'scaling_start_modifier', null,
      'scaling_end_modifier', null
    )
  );
$$;

alter table public.odyssey_caliber_defs enable row level security;
alter table public.odyssey_ammo_type_defs enable row level security;
alter table public.odyssey_weapon_class_defs enable row level security;
alter table public.odyssey_range_band_defs enable row level security;
alter table public.odyssey_range_profile_defs enable row level security;
alter table public.odyssey_range_profile_modifiers enable row level security;
alter table public.odyssey_fire_mode_defs enable row level security;
alter table public.odyssey_weapon_model_defs enable row level security;
alter table public.odyssey_weapon_model_fire_modes enable row level security;
alter table public.odyssey_magazine_defs enable row level security;
alter table public.odyssey_weapon_model_magazines enable row level security;
alter table public.odyssey_character_magazines enable row level security;
alter table public.odyssey_character_weapons enable row level security;

drop policy if exists "odyssey_caliber_defs_full_access" on public.odyssey_caliber_defs;
create policy "odyssey_caliber_defs_full_access"
on public.odyssey_caliber_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_ammo_type_defs_full_access" on public.odyssey_ammo_type_defs;
create policy "odyssey_ammo_type_defs_full_access"
on public.odyssey_ammo_type_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_class_defs_full_access" on public.odyssey_weapon_class_defs;
create policy "odyssey_weapon_class_defs_full_access"
on public.odyssey_weapon_class_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_range_band_defs_full_access" on public.odyssey_range_band_defs;
create policy "odyssey_range_band_defs_full_access"
on public.odyssey_range_band_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_range_profile_defs_full_access" on public.odyssey_range_profile_defs;
create policy "odyssey_range_profile_defs_full_access"
on public.odyssey_range_profile_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_range_profile_modifiers_full_access" on public.odyssey_range_profile_modifiers;
create policy "odyssey_range_profile_modifiers_full_access"
on public.odyssey_range_profile_modifiers
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_fire_mode_defs_full_access" on public.odyssey_fire_mode_defs;
create policy "odyssey_fire_mode_defs_full_access"
on public.odyssey_fire_mode_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_model_defs_full_access" on public.odyssey_weapon_model_defs;
create policy "odyssey_weapon_model_defs_full_access"
on public.odyssey_weapon_model_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_model_fire_modes_full_access" on public.odyssey_weapon_model_fire_modes;
create policy "odyssey_weapon_model_fire_modes_full_access"
on public.odyssey_weapon_model_fire_modes
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_magazine_defs_full_access" on public.odyssey_magazine_defs;
create policy "odyssey_magazine_defs_full_access"
on public.odyssey_magazine_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_model_magazines_full_access" on public.odyssey_weapon_model_magazines;
create policy "odyssey_weapon_model_magazines_full_access"
on public.odyssey_weapon_model_magazines
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_magazines_full_access" on public.odyssey_character_magazines;
create policy "odyssey_character_magazines_full_access"
on public.odyssey_character_magazines
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_weapons_full_access" on public.odyssey_character_weapons;
create policy "odyssey_character_weapons_full_access"
on public.odyssey_character_weapons
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_caliber_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_ammo_type_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_class_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_range_band_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_range_profile_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_range_profile_modifiers to anon, authenticated;
grant select, insert, update, delete on public.odyssey_fire_mode_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_model_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_model_fire_modes to anon, authenticated;
grant select, insert, update, delete on public.odyssey_magazine_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_model_magazines to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_magazines to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_weapons to anon, authenticated;

grant execute on function public.get_character_armory(uuid) to anon, authenticated;
grant execute on function public.create_character_weapon(uuid, uuid, text) to anon, authenticated;
grant execute on function public.create_character_magazine(uuid, uuid, uuid, integer, text) to anon, authenticated;
grant execute on function public.load_magazine(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.unload_magazine(uuid, uuid) to anon, authenticated;
grant execute on function public.switch_weapon_fire_mode(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.calculate_range_band(numeric) to anon, authenticated;
grant execute on function public.get_weapon_range_modifier(uuid, numeric) to anon, authenticated;
