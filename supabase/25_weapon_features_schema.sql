create extension if not exists pgcrypto;

create table if not exists public.odyssey_weapon_model_profiles (
  id uuid primary key default gen_random_uuid(),
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete cascade,
  code text not null,
  name text not null,
  description text not null default '',
  weapon_class_id uuid null references public.odyssey_weapon_class_defs(id) on delete set null,
  linked_skill_id uuid null references public.odyssey_skill_defs(id) on delete set null,
  caliber_id uuid null references public.odyssey_caliber_defs(id) on delete set null,
  range_profile_id uuid null references public.odyssey_range_profile_defs(id) on delete set null,
  accuracy_modifier integer not null default 0,
  base_melee_damage integer not null default 0 check (base_melee_damage >= 0),
  attack_type text not null default 'ranged' check (attack_type in ('ranged', 'melee', 'hybrid', 'custom')),
  is_default boolean not null default false,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (weapon_model_id, code)
);

create unique index if not exists odyssey_weapon_model_profiles_one_default_idx
  on public.odyssey_weapon_model_profiles (weapon_model_id)
  where is_default = true;

create table if not exists public.odyssey_weapon_profile_fire_modes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.odyssey_weapon_model_profiles(id) on delete cascade,
  fire_mode_id uuid not null references public.odyssey_fire_mode_defs(id) on delete cascade,
  is_default boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  unique (profile_id, fire_mode_id)
);

create unique index if not exists odyssey_weapon_profile_fire_modes_one_default_idx
  on public.odyssey_weapon_profile_fire_modes (profile_id)
  where is_default = true;

create table if not exists public.odyssey_weapon_profile_magazines (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.odyssey_weapon_model_profiles(id) on delete cascade,
  magazine_def_id uuid not null references public.odyssey_magazine_defs(id) on delete cascade,
  is_default boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  unique (profile_id, magazine_def_id)
);

create unique index if not exists odyssey_weapon_profile_magazines_one_default_idx
  on public.odyssey_weapon_profile_magazines (profile_id)
  where is_default = true;

create table if not exists public.odyssey_character_weapon_profile_states (
  id uuid primary key default gen_random_uuid(),
  character_weapon_id uuid not null references public.odyssey_character_weapons(id) on delete cascade,
  profile_id uuid not null references public.odyssey_weapon_model_profiles(id) on delete cascade,
  loaded_magazine_id uuid null references public.odyssey_character_magazines(id) on delete set null,
  selected_fire_mode_id uuid null references public.odyssey_fire_mode_defs(id) on delete set null,
  is_active boolean not null default false,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_weapon_id, profile_id)
);

create unique index if not exists odyssey_character_weapon_profile_states_one_active_idx
  on public.odyssey_character_weapon_profile_states (character_weapon_id)
  where is_active = true;

create table if not exists public.odyssey_weapon_feature_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  feature_type text not null check (feature_type in ('passive', 'active', 'one_attack', 'duration', 'profile_switch', 'on_hit', 'narrative', 'custom')),
  activation_type text not null default 'passive' check (activation_type in ('passive', 'manual', 'on_attack', 'on_hit', 'profile_switch', 'always', 'custom')),
  description text not null default '',
  default_max_charges integer null check (default_max_charges is null or default_max_charges >= 0),
  default_current_charges integer null check (default_current_charges is null or default_current_charges >= 0),
  default_recharge_rounds integer null check (default_recharge_rounds is null or default_recharge_rounds >= 0),
  default_cooldown_rounds integer null check (default_cooldown_rounds is null or default_cooldown_rounds >= 0),
  default_active_rounds integer null check (default_active_rounds is null or default_active_rounds >= 0),
  default_active_uses integer null check (default_active_uses is null or default_active_uses >= 0),
  requires_reload_item_code text null,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  effect_data jsonb not null default '{}'::jsonb check (jsonb_typeof(effect_data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_weapon_model_features (
  id uuid primary key default gen_random_uuid(),
  weapon_model_id uuid not null references public.odyssey_weapon_model_defs(id) on delete cascade,
  feature_def_id uuid not null references public.odyssey_weapon_feature_defs(id) on delete cascade,
  profile_id uuid null references public.odyssey_weapon_model_profiles(id) on delete cascade,
  is_enabled_by_default boolean not null default true,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists odyssey_weapon_model_features_unique_idx
  on public.odyssey_weapon_model_features (
    weapon_model_id,
    feature_def_id,
    coalesce(profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table if not exists public.odyssey_character_weapon_feature_states (
  id uuid primary key default gen_random_uuid(),
  character_weapon_id uuid not null references public.odyssey_character_weapons(id) on delete cascade,
  feature_def_id uuid not null references public.odyssey_weapon_feature_defs(id) on delete cascade,
  profile_id uuid null references public.odyssey_weapon_model_profiles(id) on delete set null,
  is_active boolean not null default false,
  is_enabled boolean not null default true,
  current_charges integer null check (current_charges is null or current_charges >= 0),
  max_charges integer null check (max_charges is null or max_charges >= 0),
  recharge_rounds_left integer null check (recharge_rounds_left is null or recharge_rounds_left >= 0),
  cooldown_rounds_left integer null check (cooldown_rounds_left is null or cooldown_rounds_left >= 0),
  active_rounds_left integer null check (active_rounds_left is null or active_rounds_left >= 0),
  active_uses_left integer null check (active_uses_left is null or active_uses_left >= 0),
  requires_reload boolean not null default false,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists odyssey_character_weapon_feature_states_unique_idx
  on public.odyssey_character_weapon_feature_states (
    character_weapon_id,
    feature_def_id,
    coalesce(profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists odyssey_weapon_model_profiles_weapon_model_idx
  on public.odyssey_weapon_model_profiles (weapon_model_id, sort_order, created_at);

create index if not exists odyssey_character_weapon_profile_states_weapon_idx
  on public.odyssey_character_weapon_profile_states (character_weapon_id, created_at);

create index if not exists odyssey_character_weapon_feature_states_weapon_idx
  on public.odyssey_character_weapon_feature_states (character_weapon_id, created_at);

alter table public.odyssey_character_weapons
  add column if not exists active_profile_id uuid null references public.odyssey_weapon_model_profiles(id) on delete set null;

alter table public.odyssey_weapon_model_profiles enable row level security;
alter table public.odyssey_weapon_profile_fire_modes enable row level security;
alter table public.odyssey_weapon_profile_magazines enable row level security;
alter table public.odyssey_character_weapon_profile_states enable row level security;
alter table public.odyssey_weapon_feature_defs enable row level security;
alter table public.odyssey_weapon_model_features enable row level security;
alter table public.odyssey_character_weapon_feature_states enable row level security;

drop policy if exists "odyssey_weapon_model_profiles_full_access" on public.odyssey_weapon_model_profiles;
create policy "odyssey_weapon_model_profiles_full_access"
on public.odyssey_weapon_model_profiles
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_profile_fire_modes_full_access" on public.odyssey_weapon_profile_fire_modes;
create policy "odyssey_weapon_profile_fire_modes_full_access"
on public.odyssey_weapon_profile_fire_modes
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_profile_magazines_full_access" on public.odyssey_weapon_profile_magazines;
create policy "odyssey_weapon_profile_magazines_full_access"
on public.odyssey_weapon_profile_magazines
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_weapon_profile_states_full_access" on public.odyssey_character_weapon_profile_states;
create policy "odyssey_character_weapon_profile_states_full_access"
on public.odyssey_character_weapon_profile_states
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_feature_defs_full_access" on public.odyssey_weapon_feature_defs;
create policy "odyssey_weapon_feature_defs_full_access"
on public.odyssey_weapon_feature_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_weapon_model_features_full_access" on public.odyssey_weapon_model_features;
create policy "odyssey_weapon_model_features_full_access"
on public.odyssey_weapon_model_features
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_weapon_feature_states_full_access" on public.odyssey_character_weapon_feature_states;
create policy "odyssey_character_weapon_feature_states_full_access"
on public.odyssey_character_weapon_feature_states
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_weapon_model_profiles to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_profile_fire_modes to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_profile_magazines to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_weapon_profile_states to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_feature_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_weapon_model_features to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_weapon_feature_states to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_weapon_model_profiles on public.odyssey_weapon_model_profiles;
create trigger odyssey_touch_updated_at_weapon_model_profiles
before update on public.odyssey_weapon_model_profiles
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_weapon_profile_states on public.odyssey_character_weapon_profile_states;
create trigger odyssey_touch_updated_at_character_weapon_profile_states
before update on public.odyssey_character_weapon_profile_states
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_weapon_feature_defs on public.odyssey_weapon_feature_defs;
create trigger odyssey_touch_updated_at_weapon_feature_defs
before update on public.odyssey_weapon_feature_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_weapon_feature_states on public.odyssey_character_weapon_feature_states;
create trigger odyssey_touch_updated_at_character_weapon_feature_states
before update on public.odyssey_character_weapon_feature_states
for each row
execute function public.odyssey_touch_updated_at();

create or replace function public.odyssey_get_range_profile_modifier(
  p_range_profile_id uuid,
  p_distance_m numeric
)
returns jsonb
language sql
stable
as $$
  with distance_input as (
    select greatest(coalesce(p_distance_m, 0), 0)::numeric as distance_m
  ),
  profile_data as (
    select rp.id, rp.code
    from public.odyssey_range_profile_defs rp
    where rp.id = p_range_profile_id
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
        'range_profile', pd.code,
        'modifier',
          case
            when rpm.scaling_mode = 'flat' then rpm.flat_modifier
            when rpm.scaling_mode = 'scaling' then
              round(
                rpm.scaling_start_modifier
                + greatest(
                    least((di.distance_m - 51)::numeric / 49::numeric, 1),
                    0
                  ) * (rpm.scaling_end_modifier - rpm.scaling_start_modifier)
              )::integer
            else null
          end,
        'scaling_mode', rpm.scaling_mode,
        'scaling_start_modifier', rpm.scaling_start_modifier,
        'scaling_end_modifier', rpm.scaling_end_modifier
      )
      from profile_data pd
      join distance_input di on true
      left join range_band rb on true
      left join public.odyssey_range_profile_modifiers rpm
        on rpm.range_profile_id = pd.id
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

create or replace function public.odyssey_get_default_weapon_profile_id(
  p_weapon_model_id uuid
)
returns uuid
language sql
stable
as $$
  select p.id
  from public.odyssey_weapon_model_profiles p
  where p.weapon_model_id = p_weapon_model_id
  order by p.is_default desc, p.sort_order, p.created_at, p.id
  limit 1;
$$;

create or replace function public.odyssey_get_default_profile_fire_mode_id(
  p_profile_id uuid
)
returns uuid
language sql
stable
as $$
  select pfm.fire_mode_id
  from public.odyssey_weapon_profile_fire_modes pfm
  where pfm.profile_id = p_profile_id
  order by pfm.is_default desc, pfm.sort_order, pfm.created_at, pfm.id
  limit 1;
$$;

create or replace function public.odyssey_merge_weapon_feature_data(
  p_base jsonb,
  p_override jsonb
)
returns jsonb
language sql
immutable
as $$
  with normalized as (
    select
      coalesce(case when jsonb_typeof(p_base) = 'object' then p_base else '{}'::jsonb end, '{}'::jsonb) as base_data,
      coalesce(case when jsonb_typeof(p_override) = 'object' then p_override else '{}'::jsonb end, '{}'::jsonb) as override_data
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          ((base_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions') || (override_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions')),
          '{modifiers}',
          case
            when jsonb_typeof(base_data->'modifiers') = 'array'
              and jsonb_typeof(override_data->'modifiers') = 'array'
              then (base_data->'modifiers') || (override_data->'modifiers')
            when jsonb_typeof(override_data->'modifiers') = 'array'
              then override_data->'modifiers'
            when jsonb_typeof(base_data->'modifiers') = 'array'
              then base_data->'modifiers'
            else '[]'::jsonb
          end,
          true
        ),
        '{on_hit}',
        case
          when jsonb_typeof(base_data->'on_hit') = 'array'
            and jsonb_typeof(override_data->'on_hit') = 'array'
            then (base_data->'on_hit') || (override_data->'on_hit')
          when jsonb_typeof(override_data->'on_hit') = 'array'
            then override_data->'on_hit'
          when jsonb_typeof(base_data->'on_hit') = 'array'
            then base_data->'on_hit'
          else '[]'::jsonb
        end,
        true
      ),
      '{flags}',
      case
        when jsonb_typeof(base_data->'flags') = 'object'
          or jsonb_typeof(override_data->'flags') = 'object'
          then coalesce(base_data->'flags', '{}'::jsonb) || coalesce(override_data->'flags', '{}'::jsonb)
        else '{}'::jsonb
      end,
      true
    ),
    '{conditions}',
    case
      when jsonb_typeof(base_data->'conditions') = 'object'
        or jsonb_typeof(override_data->'conditions') = 'object'
        then coalesce(base_data->'conditions', '{}'::jsonb) || coalesce(override_data->'conditions', '{}'::jsonb)
      else '{}'::jsonb
    end,
    true
  )
  from normalized;
$$;

create or replace function public.odyssey_is_fire_mode_allowed_for_profile(
  p_profile_id uuid,
  p_fire_mode_id uuid
)
returns boolean
language sql
stable
as $$
  select exists(
    select 1
    from public.odyssey_weapon_profile_fire_modes pfm
    where pfm.profile_id = p_profile_id
      and pfm.fire_mode_id = p_fire_mode_id
  );
$$;

create or replace function public.odyssey_is_magazine_compatible_with_profile(
  p_profile_id uuid,
  p_character_magazine_id uuid
)
returns boolean
language sql
stable
as $$
  select exists(
    select 1
    from public.odyssey_character_magazines cm
    join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
    join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
    join public.odyssey_weapon_model_profiles p on p.id = p_profile_id
    join public.odyssey_weapon_profile_magazines ppm
      on ppm.profile_id = p.id
     and ppm.magazine_def_id = cm.magazine_def_id
    where cm.id = p_character_magazine_id
      and (p.caliber_id is null or md.caliber_id = p.caliber_id)
      and ammo.caliber_id = md.caliber_id
  );
$$;

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
    wm.base_melee_damage,
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
  returning id into v_profile_id;

  if v_profile_id is null then
    return null;
  end if;

  insert into public.odyssey_weapon_profile_fire_modes (
    profile_id,
    fire_mode_id,
    is_default,
    sort_order
  )
  select
    v_profile_id,
    wmfm.fire_mode_id,
    wmfm.is_default,
    row_number() over (order by wmfm.is_default desc, wmfm.created_at, wmfm.id) * 10
  from public.odyssey_weapon_model_fire_modes wmfm
  where wmfm.weapon_model_id = p_weapon_model_id
  on conflict (profile_id, fire_mode_id) do update
  set
    is_default = excluded.is_default,
    sort_order = excluded.sort_order;

  insert into public.odyssey_weapon_profile_magazines (
    profile_id,
    magazine_def_id,
    is_default,
    sort_order
  )
  select
    v_profile_id,
    wmm.magazine_def_id,
    wmm.is_default,
    row_number() over (order by wmm.is_default desc, wmm.created_at, wmm.id) * 10
  from public.odyssey_weapon_model_magazines wmm
  where wmm.weapon_model_id = p_weapon_model_id
  on conflict (profile_id, magazine_def_id) do update
  set
    is_default = excluded.is_default,
    sort_order = excluded.sort_order;

  return v_profile_id;
end;
$$;

create or replace function public.odyssey_sync_character_weapon_profile_cache(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_default_profile_id uuid := null;
  v_active_state public.odyssey_character_weapon_profile_states%rowtype;
  v_resolved_fire_mode_id uuid := null;
  v_resolved_magazine_id uuid := null;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'weapon_id', p_character_weapon_id
    );
  end if;

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(v_weapon.weapon_model_id);

  if v_weapon.active_profile_id is null then
    update public.odyssey_character_weapons
    set active_profile_id = v_default_profile_id
    where id = v_weapon.id;

    v_weapon.active_profile_id := v_default_profile_id;
  end if;

  select *
  into v_active_state
  from public.odyssey_character_weapon_profile_states s
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = coalesce(v_weapon.active_profile_id, v_default_profile_id)
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'PROFILE_STATE_NOT_FOUND',
      'weapon_id', p_character_weapon_id,
      'profile_id', coalesce(v_weapon.active_profile_id, v_default_profile_id)
    );
  end if;

  update public.odyssey_character_weapon_profile_states
  set is_active = (id = v_active_state.id)
  where character_weapon_id = v_weapon.id
    and is_active is distinct from (id = v_active_state.id);

  if v_active_state.selected_fire_mode_id is not null
     and public.odyssey_is_fire_mode_allowed_for_profile(v_active_state.profile_id, v_active_state.selected_fire_mode_id) then
    v_resolved_fire_mode_id := v_active_state.selected_fire_mode_id;
  else
    v_resolved_fire_mode_id := public.odyssey_get_default_profile_fire_mode_id(v_active_state.profile_id);

    update public.odyssey_character_weapon_profile_states
    set selected_fire_mode_id = v_resolved_fire_mode_id
    where id = v_active_state.id
      and selected_fire_mode_id is distinct from v_resolved_fire_mode_id;
  end if;

  if v_active_state.loaded_magazine_id is not null
     and public.odyssey_is_magazine_compatible_with_profile(v_active_state.profile_id, v_active_state.loaded_magazine_id) then
    v_resolved_magazine_id := v_active_state.loaded_magazine_id;
  else
    v_resolved_magazine_id := null;

    update public.odyssey_character_weapon_profile_states
    set loaded_magazine_id = null
    where id = v_active_state.id
      and loaded_magazine_id is not null;
  end if;

  update public.odyssey_character_weapons
  set
    active_profile_id = v_active_state.profile_id,
    loaded_magazine_id = v_resolved_magazine_id,
    selected_fire_mode_id = v_resolved_fire_mode_id
  where id = v_weapon.id;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'active_profile_id', v_active_state.profile_id,
    'loaded_magazine_id', v_resolved_magazine_id,
    'selected_fire_mode_id', v_resolved_fire_mode_id
  );
end;
$$;

create or replace function public.initialize_character_weapon_profile_states(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_default_profile_id uuid := null;
  v_active_profile_id uuid := null;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'weapon_id', p_character_weapon_id
    );
  end if;

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(v_weapon.weapon_model_id);
  v_active_profile_id := coalesce(v_weapon.active_profile_id, v_default_profile_id);

  if not exists(
    select 1
    from public.odyssey_weapon_model_profiles p
    where p.id = v_active_profile_id
      and p.weapon_model_id = v_weapon.weapon_model_id
  ) then
    v_active_profile_id := v_default_profile_id;
  end if;

  insert into public.odyssey_character_weapon_profile_states (
    character_weapon_id,
    profile_id,
    loaded_magazine_id,
    selected_fire_mode_id,
    is_active,
    data
  )
  select
    v_weapon.id,
    p.id,
    case
      when p.id = v_active_profile_id then v_weapon.loaded_magazine_id
      else null
    end,
    case
      when p.id = v_active_profile_id
           and v_weapon.selected_fire_mode_id is not null
           and public.odyssey_is_fire_mode_allowed_for_profile(p.id, v_weapon.selected_fire_mode_id)
        then v_weapon.selected_fire_mode_id
      else public.odyssey_get_default_profile_fire_mode_id(p.id)
    end,
    p.id = v_active_profile_id,
    '{}'::jsonb
  from public.odyssey_weapon_model_profiles p
  where p.weapon_model_id = v_weapon.weapon_model_id
  on conflict (character_weapon_id, profile_id) do nothing;

  update public.odyssey_character_weapon_profile_states
  set is_active = (profile_id = v_active_profile_id)
  where character_weapon_id = v_weapon.id;

  update public.odyssey_character_weapons
  set active_profile_id = v_active_profile_id
  where id = v_weapon.id
    and active_profile_id is distinct from v_active_profile_id;

  return public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);
end;
$$;

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
  wm.base_melee_damage,
  case
    when wm.caliber_id is null then 'melee'
    else 'ranged'
  end,
  true,
  '{}'::jsonb,
  coalesce(wm.tags, '[]'::jsonb),
  0
from public.odyssey_weapon_model_defs wm
where not exists (
  select 1
  from public.odyssey_weapon_model_profiles p
  where p.weapon_model_id = wm.id
);

update public.odyssey_weapon_model_profiles
set is_default = true
where id in (
  select profile_id
  from (
    select
      p.id as profile_id,
      row_number() over (
        partition by p.weapon_model_id
        order by p.is_default desc, p.sort_order, p.created_at, p.id
      ) as rn
    from public.odyssey_weapon_model_profiles p
  ) ranked
  where ranked.rn = 1
)
and is_default = false;

insert into public.odyssey_weapon_profile_fire_modes (
  profile_id,
  fire_mode_id,
  is_default,
  sort_order
)
select
  p.id,
  wmfm.fire_mode_id,
  wmfm.is_default,
  row_number() over (
    partition by p.id
    order by wmfm.is_default desc, wmfm.created_at, wmfm.id
  ) * 10
from public.odyssey_weapon_model_profiles p
join public.odyssey_weapon_model_fire_modes wmfm
  on wmfm.weapon_model_id = p.weapon_model_id
where p.code = 'default'
on conflict (profile_id, fire_mode_id) do update
set
  is_default = excluded.is_default,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_profile_magazines (
  profile_id,
  magazine_def_id,
  is_default,
  sort_order
)
select
  p.id,
  wmm.magazine_def_id,
  wmm.is_default,
  row_number() over (
    partition by p.id
    order by wmm.is_default desc, wmm.created_at, wmm.id
  ) * 10
from public.odyssey_weapon_model_profiles p
join public.odyssey_weapon_model_magazines wmm
  on wmm.weapon_model_id = p.weapon_model_id
where p.code = 'default'
on conflict (profile_id, magazine_def_id) do update
set
  is_default = excluded.is_default,
  sort_order = excluded.sort_order;

update public.odyssey_character_weapons w
set active_profile_id = coalesce(
  public.odyssey_get_default_weapon_profile_id(w.weapon_model_id),
  public.odyssey_ensure_default_weapon_profile(w.weapon_model_id)
)
where active_profile_id is null;

select public.initialize_character_weapon_profile_states(w.id)
from public.odyssey_character_weapons w;

create or replace function public.odyssey_get_character_weapon_profile(
  p_character_weapon_id uuid,
  p_profile_id uuid
)
returns jsonb
language sql
stable
as $$
  with profile_rows as (
    select
      p.id,
      p.weapon_model_id,
      p.code,
      p.name,
      p.description,
      p.attack_type,
      p.data,
      p.tags,
      p.sort_order,
      p.is_default,
      coalesce(pwc.code, mwc.code) as weapon_class_code,
      coalesce(pwc.name, mwc.name) as weapon_class_name,
      coalesce(pskill.code, mskill.code) as linked_skill_code,
      coalesce(pskill.name, mskill.name) as linked_skill_name,
      coalesce(pcal.code, mcal.code) as caliber_code,
      coalesce(pcal.name, mcal.name) as caliber_name,
      coalesce(prp.code, mrp.code) as range_profile_code,
      coalesce(prp.name, mrp.name) as range_profile_name,
      coalesce(p.accuracy_modifier, wm.base_accuracy_bonus) as accuracy_modifier,
      coalesce(p.base_melee_damage, wm.base_melee_damage) as base_melee_damage,
      coalesce(pcal.base_damage_per_round, mcal.base_damage_per_round, 0) as base_damage_per_round,
      s.loaded_magazine_id,
      s.selected_fire_mode_id,
      s.is_active
    from public.odyssey_character_weapon_profile_states s
    join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
    join public.odyssey_character_weapons w on w.id = s.character_weapon_id
    join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
    left join public.odyssey_weapon_class_defs pwc on pwc.id = p.weapon_class_id
    left join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
    left join public.odyssey_skill_defs pskill on pskill.id = p.linked_skill_id
    left join public.odyssey_skill_defs mskill on mskill.id = wm.linked_skill_id
    left join public.odyssey_caliber_defs pcal on pcal.id = p.caliber_id
    left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
    left join public.odyssey_range_profile_defs prp on prp.id = p.range_profile_id
    left join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
    where s.character_weapon_id = p_character_weapon_id
      and s.profile_id = p_profile_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'id', pr.id,
        'code', pr.code,
        'name', pr.name,
        'description', pr.description,
        'attack_type', pr.attack_type,
        'weapon_class', pr.weapon_class_code,
        'weapon_class_name', pr.weapon_class_name,
        'linked_skill', pr.linked_skill_code,
        'linked_skill_name', pr.linked_skill_name,
        'caliber', pr.caliber_code,
        'caliber_name', pr.caliber_name,
        'range_profile', pr.range_profile_code,
        'range_profile_name', pr.range_profile_name,
        'accuracy_modifier', pr.accuracy_modifier,
        'base_melee_damage', pr.base_melee_damage,
        'base_damage_per_round', pr.base_damage_per_round,
        'data', pr.data,
        'tags', pr.tags,
        'sort_order', pr.sort_order,
        'is_default', pr.is_default,
        'is_active', pr.is_active,
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
                  'is_default', pfm.is_default
                )
                order by pfm.is_default desc, pfm.sort_order, afm.sort_order, afm.name
              )
              from public.odyssey_weapon_profile_fire_modes pfm
              join public.odyssey_fire_mode_defs afm on afm.id = pfm.fire_mode_id
              where pfm.profile_id = pr.id
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
                  'is_default', ppm.is_default
                )
                order by ppm.is_default desc, ppm.sort_order, cmd.sort_order, cmd.name
              )
              from public.odyssey_weapon_profile_magazines ppm
              join public.odyssey_magazine_defs cmd on cmd.id = ppm.magazine_def_id
              join public.odyssey_caliber_defs cmdc on cmdc.id = cmd.caliber_id
              where ppm.profile_id = pr.id
            ),
            '[]'::jsonb
          )
      )
      from profile_rows pr
      left join public.odyssey_character_magazines cm on cm.id = pr.loaded_magazine_id
      left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
      left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
      left join public.odyssey_fire_mode_defs fm on fm.id = pr.selected_fire_mode_id
    ),
    null
  );
$$;

create or replace function public.odyssey_get_character_weapon_profiles(
  p_character_weapon_id uuid
)
returns jsonb
language sql
stable
as $$
  select coalesce(
    (
      select jsonb_agg(profile_json order by sort_order, code)
      from (
        select
          p.sort_order,
          p.code,
          public.odyssey_get_character_weapon_profile(p_character_weapon_id, p.id) as profile_json
        from public.odyssey_character_weapon_profile_states s
        join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
        where s.character_weapon_id = p_character_weapon_id
      ) q
    ),
    '[]'::jsonb
  );
$$;

create or replace function public.odyssey_get_active_character_weapon_profile(
  p_character_weapon_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_get_character_weapon_profile(
    p_character_weapon_id,
    (
      select s.profile_id
      from public.odyssey_character_weapon_profile_states s
      where s.character_weapon_id = p_character_weapon_id
        and s.is_active = true
      order by s.updated_at desc, s.created_at desc, s.id
      limit 1
    )
  );
$$;

create or replace function public.initialize_character_weapon_feature_states(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'weapon_id', p_character_weapon_id
    );
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);

  insert into public.odyssey_character_weapon_feature_states (
    character_weapon_id,
    feature_def_id,
    profile_id,
    is_active,
    is_enabled,
    current_charges,
    max_charges,
    recharge_rounds_left,
    cooldown_rounds_left,
    active_rounds_left,
    active_uses_left,
    requires_reload,
    data
  )
  select
    v_weapon.id,
    link.feature_def_id,
    link.profile_id,
    false,
    link.is_enabled_by_default,
    def.default_current_charges,
    def.default_max_charges,
    null,
    null,
    null,
    null,
    false,
    '{}'::jsonb
  from public.odyssey_weapon_model_features link
  join public.odyssey_weapon_feature_defs def on def.id = link.feature_def_id
  where link.weapon_model_id = v_weapon.weapon_model_id
    and not exists (
      select 1
      from public.odyssey_character_weapon_feature_states s
      where s.character_weapon_id = v_weapon.id
        and s.feature_def_id = link.feature_def_id
        and coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

  return jsonb_build_object(
    'ok', true,
    'character_weapon_id', v_weapon.id
  );
end;
$$;

update public.odyssey_character_weapon_feature_states s
set data = '{}'::jsonb
from public.odyssey_character_weapons w,
     public.odyssey_weapon_model_features link
where s.character_weapon_id = w.id
  and link.weapon_model_id = w.weapon_model_id
  and link.feature_def_id = s.feature_def_id
  and coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  and s.data = coalesce(link.data, '{}'::jsonb);

create or replace function public.get_character_weapon_features(
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
  v_active_profile_id uuid := null;
  v_features jsonb := '[]'::jsonb;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'character_weapon_id', p_character_weapon_id,
      'active_profile_id', null,
      'features', '[]'::jsonb
    );
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);
  perform public.initialize_character_weapon_feature_states(v_weapon.id);

  select active_profile_id
  into v_active_profile_id
  from public.odyssey_character_weapons
  where id = v_weapon.id;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'state_id', s.id,
          'feature_def_id', def.id,
          'code', def.code,
          'name', def.name,
          'feature_type', def.feature_type,
          'activation_type', def.activation_type,
          'description', def.description,
          'profile_id', s.profile_id,
          'profile_code', profile.code,
          'profile_name', profile.name,
          'is_active', s.is_active,
          'is_enabled', s.is_enabled,
          'current_charges', s.current_charges,
          'max_charges', s.max_charges,
          'recharge_rounds_left', s.recharge_rounds_left,
          'cooldown_rounds_left', s.cooldown_rounds_left,
          'active_rounds_left', s.active_rounds_left,
          'active_uses_left', s.active_uses_left,
          'requires_reload', s.requires_reload,
          'data',
            public.odyssey_merge_weapon_feature_data(
              public.odyssey_merge_weapon_feature_data(def.data, coalesce(link.data, '{}'::jsonb)),
              s.data
            ),
          'definition_data', def.data,
          'model_data', coalesce(link.data, '{}'::jsonb),
          'state_data', s.data,
          'effect_data', def.effect_data,
          'tags', def.tags
        )
        order by
          case when s.profile_id = v_active_profile_id then 0 when s.profile_id is null then 1 else 2 end,
          coalesce(profile.sort_order, 0),
          def.sort_order,
          def.code
      ),
      '[]'::jsonb
    )
  into v_features
  from public.odyssey_character_weapon_feature_states s
  join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
  left join public.odyssey_weapon_model_profiles profile on profile.id = s.profile_id
  left join public.odyssey_weapon_model_features link
    on link.weapon_model_id = v_weapon.weapon_model_id
   and link.feature_def_id = s.feature_def_id
   and coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
  where s.character_weapon_id = v_weapon.id;

  return jsonb_build_object(
    'character_weapon_id', v_weapon.id,
    'active_profile_id', v_active_profile_id,
    'features', v_features
  );
end;
$$;

create or replace function public.activate_weapon_feature(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_weapon_id uuid := nullif(trim(coalesce(p_payload->>'character_weapon_id', '')), '')::uuid;
  v_feature_code text := coalesce(nullif(trim(coalesce(p_payload->>'feature_code', '')), ''), '');
  v_weapon public.odyssey_character_weapons%rowtype;
  v_state record;
  v_active_uses integer := null;
  v_active_rounds integer := null;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  if not found then
    raise exception 'Weapon % was not found', v_character_weapon_id;
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);
  perform public.initialize_character_weapon_feature_states(v_weapon.id);

  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  select
    s.id,
    s.character_weapon_id,
    s.feature_def_id,
    s.profile_id,
    s.is_active,
    s.is_enabled,
    s.current_charges,
    s.max_charges,
    s.recharge_rounds_left,
    s.cooldown_rounds_left,
    s.active_rounds_left,
    s.active_uses_left,
    s.requires_reload,
    s.data,
    def.code,
    def.name,
    def.feature_type,
    def.activation_type,
    def.default_active_rounds,
    def.default_active_uses,
    def.requires_reload_item_code
  into v_state
  from public.odyssey_character_weapon_feature_states s
  join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
  where s.character_weapon_id = v_weapon.id
    and def.code = v_feature_code
    and (s.profile_id = v_weapon.active_profile_id or s.profile_id is null)
  order by case when s.profile_id = v_weapon.active_profile_id then 0 else 1 end
  limit 1;

  if not found then
    raise exception 'Feature % is not available for weapon %', v_feature_code, v_character_weapon_id;
  end if;

  if not coalesce(v_state.is_enabled, true) then
    raise exception 'Feature % is disabled for weapon %', v_feature_code, v_character_weapon_id;
  end if;

  if v_state.activation_type <> 'manual' then
    raise exception 'Feature % must be used through % activation, not manual activation', v_feature_code, v_state.activation_type;
  end if;

  if coalesce(v_state.requires_reload, false) then
    raise exception 'Feature % requires manual reload before activation', v_feature_code;
  end if;

  if coalesce(v_state.recharge_rounds_left, 0) > 0 then
    raise exception 'Feature % is still recharging', v_feature_code;
  end if;

  if coalesce(v_state.cooldown_rounds_left, 0) > 0 then
    raise exception 'Feature % is still cooling down', v_feature_code;
  end if;

  if v_state.current_charges is not null and v_state.current_charges <= 0 then
    raise exception 'Feature % has no charges left', v_feature_code;
  end if;

  v_active_uses := coalesce(v_state.default_active_uses, v_state.active_uses_left);
  v_active_rounds := coalesce(v_state.default_active_rounds, v_state.active_rounds_left);

  update public.odyssey_character_weapon_feature_states
  set
    is_active = true,
    current_charges =
      case
        when current_charges is null then null
        else greatest(current_charges - 1, 0)
      end,
    active_uses_left = v_active_uses,
    active_rounds_left = v_active_rounds,
    recharge_rounds_left = null,
    cooldown_rounds_left = null,
    requires_reload = false
  where id = v_state.id;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'feature', (
      select feature
      from jsonb_array_elements(public.get_character_weapon_features(v_weapon.id)->'features') feature
      where nullif(feature->>'state_id', '')::uuid = v_state.id
      limit 1
    )
  );
end;
$$;

create or replace function public.deactivate_weapon_feature(
  p_state_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_id uuid := null;
begin
  update public.odyssey_character_weapon_feature_states
  set
    is_active = false,
    active_rounds_left = null,
    active_uses_left = null
  where id = p_state_id
  returning character_weapon_id into v_weapon_id;

  if v_weapon_id is null then
    raise exception 'Feature state % was not found', p_state_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon_id,
    'feature', (
      select feature
      from jsonb_array_elements(public.get_character_weapon_features(v_weapon_id)->'features') feature
      where nullif(feature->>'state_id', '')::uuid = p_state_id
      limit 1
    )
  );
end;
$$;

create or replace function public.reload_feature_resource(
  p_state_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_id uuid := null;
begin
  update public.odyssey_character_weapon_feature_states
  set
    is_active = false,
    current_charges = max_charges,
    recharge_rounds_left = null,
    cooldown_rounds_left = null,
    active_rounds_left = null,
    active_uses_left = null,
    requires_reload = false
  where id = p_state_id
  returning character_weapon_id into v_weapon_id;

  if v_weapon_id is null then
    raise exception 'Feature state % was not found', p_state_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon_id,
    'feature', (
      select feature
      from jsonb_array_elements(public.get_character_weapon_features(v_weapon_id)->'features') feature
      where nullif(feature->>'state_id', '')::uuid = p_state_id
      limit 1
    )
  );
end;
$$;

create or replace function public.advance_weapon_feature_states(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_state record;
  v_changed jsonb := '[]'::jsonb;
  v_next_recharge integer := null;
  v_next_cooldown integer := null;
  v_next_active_rounds integer := null;
  v_next_is_active boolean := false;
  v_next_current_charges integer := null;
  v_next_requires_reload boolean := false;
begin
  for v_state in
    select
      s.id,
      s.character_weapon_id,
      s.is_active,
      s.current_charges,
      s.max_charges,
      s.recharge_rounds_left,
      s.cooldown_rounds_left,
      s.active_rounds_left,
      s.active_uses_left,
      s.requires_reload,
      def.code,
      def.default_recharge_rounds,
      def.requires_reload_item_code
    from public.odyssey_character_weapon_feature_states s
    join public.odyssey_character_weapons w on w.id = s.character_weapon_id
    join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
    where w.character_id = p_character_id
  loop
    v_next_recharge := v_state.recharge_rounds_left;
    v_next_cooldown := v_state.cooldown_rounds_left;
    v_next_active_rounds := v_state.active_rounds_left;
    v_next_is_active := v_state.is_active;
    v_next_current_charges := v_state.current_charges;
    v_next_requires_reload := v_state.requires_reload;

    if v_state.active_rounds_left is not null then
      v_next_active_rounds := greatest(v_state.active_rounds_left - 1, 0);
      if v_next_active_rounds <= 0 then
        v_next_active_rounds := null;
        if coalesce(v_state.active_uses_left, 0) <= 0 then
          v_next_is_active := false;
        end if;
      end if;
    end if;

    if v_state.recharge_rounds_left is not null then
      v_next_recharge := greatest(v_state.recharge_rounds_left - 1, 0);
      if v_next_recharge <= 0 then
        v_next_recharge := null;
        v_next_current_charges := coalesce(v_state.max_charges, v_state.current_charges, 0);
        v_next_requires_reload := false;
      end if;
    end if;

    if v_state.cooldown_rounds_left is not null then
      v_next_cooldown := greatest(v_state.cooldown_rounds_left - 1, 0);
      if v_next_cooldown <= 0 then
        v_next_cooldown := null;
      end if;
    end if;

    if v_next_recharge is distinct from v_state.recharge_rounds_left
       or v_next_cooldown is distinct from v_state.cooldown_rounds_left
       or v_next_active_rounds is distinct from v_state.active_rounds_left
       or v_next_is_active is distinct from v_state.is_active
       or v_next_current_charges is distinct from v_state.current_charges
       or v_next_requires_reload is distinct from v_state.requires_reload then
      update public.odyssey_character_weapon_feature_states
      set
        is_active = v_next_is_active,
        current_charges = v_next_current_charges,
        recharge_rounds_left = v_next_recharge,
        cooldown_rounds_left = v_next_cooldown,
        active_rounds_left = v_next_active_rounds,
        requires_reload = v_next_requires_reload
      where id = v_state.id;

      v_changed := v_changed || jsonb_build_array(
        (
          select feature
          from jsonb_array_elements(public.get_character_weapon_features(v_state.character_weapon_id)->'features') feature
          where nullif(feature->>'state_id', '')::uuid = v_state.id
          limit 1
        )
      );
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'states', v_changed
  );
end;
$$;

create or replace function public.switch_weapon_profile(
  p_character_weapon_id uuid,
  p_profile_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon public.odyssey_character_weapons%rowtype;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = p_character_weapon_id;

  if not found then
    raise exception 'Weapon % was not found', p_character_weapon_id;
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);

  if not exists(
    select 1
    from public.odyssey_weapon_model_profiles p
    where p.id = p_profile_id
      and p.weapon_model_id = v_weapon.weapon_model_id
  ) then
    raise exception 'Profile % does not belong to weapon %', p_profile_id, p_character_weapon_id;
  end if;

  update public.odyssey_character_weapon_profile_states
  set is_active = (profile_id = p_profile_id)
  where character_weapon_id = v_weapon.id;

  update public.odyssey_character_weapons
  set active_profile_id = p_profile_id
  where id = v_weapon.id;

  perform public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'active_profile_id', p_profile_id,
    'active_profile', public.odyssey_get_active_character_weapon_profile(v_weapon.id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.load_weapon_profile_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_weapon_id uuid := nullif(trim(coalesce(p_payload->>'character_weapon_id', '')), '')::uuid;
  v_profile_id uuid := nullif(trim(coalesce(p_payload->>'profile_id', '')), '')::uuid;
  v_character_magazine_id uuid := nullif(trim(coalesce(p_payload->>'character_magazine_id', '')), '')::uuid;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_target_state_id uuid := null;
  v_affected_weapons uuid[];
  v_item uuid;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  if not found then
    raise exception 'Weapon % was not found', v_character_weapon_id;
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);

  select s.id
  into v_target_state_id
  from public.odyssey_character_weapon_profile_states s
  join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
  where s.character_weapon_id = v_weapon.id
    and s.profile_id = v_profile_id
    and p.weapon_model_id = v_weapon.weapon_model_id
  limit 1;

  if v_target_state_id is null then
    raise exception 'Profile % was not found for weapon %', v_profile_id, v_character_weapon_id;
  end if;

  if not exists(
    select 1
    from public.odyssey_character_magazines cm
    where cm.id = v_character_magazine_id
      and cm.character_id = v_weapon.character_id
  ) then
    raise exception 'Magazine % was not found for character %', v_character_magazine_id, v_weapon.character_id;
  end if;

  if not public.odyssey_is_magazine_compatible_with_profile(v_profile_id, v_character_magazine_id) then
    raise exception 'Magazine % is not compatible with profile %', v_character_magazine_id, v_profile_id;
  end if;

  with cleared as (
    update public.odyssey_character_weapon_profile_states
    set loaded_magazine_id = null
    where loaded_magazine_id = v_character_magazine_id
      and id <> v_target_state_id
    returning character_weapon_id
  )
  select coalesce(array_agg(distinct character_weapon_id), '{}'::uuid[])
  into v_affected_weapons
  from cleared;

  update public.odyssey_character_weapon_profile_states
  set loaded_magazine_id = v_character_magazine_id
  where id = v_target_state_id;

  for v_item in
    select distinct weapon_id
    from (
      select unnest(coalesce(v_affected_weapons, '{}'::uuid[])) as weapon_id
      union all
      select v_weapon.id
    ) q
  loop
    perform public.odyssey_sync_character_weapon_profile_cache(v_item);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'profile_id', v_profile_id,
    'profile', public.odyssey_get_character_weapon_profile(v_weapon.id, v_profile_id),
    'armory', public.get_character_armory(v_weapon.character_id)
  );
end;
$$;

create or replace function public.get_character_armory(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_id uuid;
  v_weapons jsonb := '[]'::jsonb;
  v_magazines jsonb := '[]'::jsonb;
begin
  for v_weapon_id in
    select w.id
    from public.odyssey_character_weapons w
    where w.character_id = p_character_id
  loop
    perform public.initialize_character_weapon_profile_states(v_weapon_id);
    perform public.initialize_character_weapon_feature_states(v_weapon_id);
  end loop;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', w.id,
          'character_id', w.character_id,
          'custom_name', w.custom_name,
          'name', coalesce(nullif(trim(w.custom_name), ''), wm.name),
          'notes', w.notes,
          'sort_order', w.sort_order,
          'active_profile_id', w.active_profile_id,
          'model',
            jsonb_build_object(
              'id', wm.id,
              'code', wm.code,
              'name', wm.name,
              'weapon_class', mwc.code,
              'weapon_class_name', mwc.name,
              'linked_skill', mskill.code,
              'linked_skill_name', mskill.name,
              'caliber', mcal.code,
              'caliber_name', mcal.name,
              'base_accuracy_bonus', wm.base_accuracy_bonus,
              'base_melee_damage', wm.base_melee_damage,
              'range_profile', mrp.code,
              'range_profile_name', mrp.name,
              'tags', wm.tags
            ),
          'active_profile', public.odyssey_get_active_character_weapon_profile(w.id),
          'profiles', public.odyssey_get_character_weapon_profiles(w.id),
          'features', coalesce(public.get_character_weapon_features(w.id)->'features', '[]'::jsonb),
          'loaded_magazine', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'loaded_magazine', 'null'::jsonb),
          'selected_fire_mode', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'selected_fire_mode', 'null'::jsonb),
          'available_fire_modes', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'available_fire_modes', '[]'::jsonb),
          'compatible_magazines', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'compatible_magazines', '[]'::jsonb)
        )
        order by w.sort_order, coalesce(nullif(trim(w.custom_name), ''), wm.name), w.id
      ),
      '[]'::jsonb
    )
  into v_weapons
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
  join public.odyssey_skill_defs mskill on mskill.id = wm.linked_skill_id
  left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
  join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
  where w.character_id = p_character_id;

  select
    coalesce(
      jsonb_agg(
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
      ),
      '[]'::jsonb
    )
  into v_magazines
  from public.odyssey_character_magazines cm
  join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  join public.odyssey_caliber_defs ammo_caliber on ammo_caliber.id = ammo.caliber_id
  where cm.character_id = p_character_id;

  return jsonb_build_object(
    'character_id', p_character_id,
    'weapons', coalesce(v_weapons, '[]'::jsonb),
    'magazines', coalesce(v_magazines, '[]'::jsonb)
  );
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
  v_default_profile_id uuid := null;
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

  v_default_profile_id := public.odyssey_ensure_default_weapon_profile(p_weapon_model_id);

  select coalesce(max(w.sort_order), 0) + 10
  into v_sort_order
  from public.odyssey_character_weapons w
  where w.character_id = p_character_id;

  insert into public.odyssey_character_weapons (
    character_id,
    weapon_model_id,
    custom_name,
    active_profile_id,
    loaded_magazine_id,
    selected_fire_mode_id,
    notes,
    sort_order
  )
  values (
    p_character_id,
    p_weapon_model_id,
    nullif(trim(p_custom_name), ''),
    v_default_profile_id,
    null,
    null,
    '',
    v_sort_order
  )
  returning id into v_weapon_id;

  perform public.initialize_character_weapon_profile_states(v_weapon_id);
  perform public.initialize_character_weapon_feature_states(v_weapon_id);

  return jsonb_build_object(
    'weapon_id', v_weapon_id,
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
  v_profile_id uuid := null;
begin
  select active_profile_id
  into v_profile_id
  from public.odyssey_character_weapons w
  where w.id = p_weapon_id
    and w.character_id = p_character_id;

  if v_profile_id is null then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  return public.load_weapon_profile_magazine(
    jsonb_build_object(
      'character_weapon_id', p_weapon_id,
      'profile_id', v_profile_id,
      'character_magazine_id', p_magazine_id
    )
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
declare
  v_profile_id uuid := null;
begin
  select active_profile_id
  into v_profile_id
  from public.odyssey_character_weapons w
  where w.id = p_weapon_id
    and w.character_id = p_character_id;

  if v_profile_id is null then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  update public.odyssey_character_weapon_profile_states
  set loaded_magazine_id = null
  where character_weapon_id = p_weapon_id
    and profile_id = v_profile_id;

  perform public.odyssey_sync_character_weapon_profile_cache(p_weapon_id);

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
  v_profile_id uuid := null;
begin
  select active_profile_id
  into v_profile_id
  from public.odyssey_character_weapons w
  where w.id = p_weapon_id
    and w.character_id = p_character_id;

  if v_profile_id is null then
    raise exception 'Weapon % was not found for character %', p_weapon_id, p_character_id;
  end if;

  if not public.odyssey_is_fire_mode_allowed_for_profile(v_profile_id, p_fire_mode_id) then
    raise exception 'Fire mode % is not allowed for active profile %', p_fire_mode_id, v_profile_id;
  end if;

  update public.odyssey_character_weapon_profile_states
  set selected_fire_mode_id = p_fire_mode_id
  where character_weapon_id = p_weapon_id
    and profile_id = v_profile_id;

  perform public.odyssey_sync_character_weapon_profile_cache(p_weapon_id);

  return jsonb_build_object(
    'weapon_id', p_weapon_id,
    'selected_fire_mode_id', p_fire_mode_id,
    'armory', public.get_character_armory(p_character_id)
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
  v_activated_feature_state_ids uuid[] := '{}'::uuid[];
  v_activated_feature_codes text[] := '{}'::text[];
  v_attacker public.odyssey_characters%rowtype;
  v_target public.odyssey_characters%rowtype;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_weapon_model record;
  v_weapon_profile record;
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
  v_feature_attack_accuracy_modifier integer := 0;
  v_feature_damage_modifier integer := 0;
  v_feature_armor_pierce_modifier integer := 0;
  v_feature_aim_difficulty_modifier integer := 0;
  v_feature_range_modifier integer := 0;
  v_pending_saves jsonb := '[]'::jsonb;
  v_pending_effects jsonb := '[]'::jsonb;
  v_feature_usage_log jsonb := '[]'::jsonb;
  v_feature_consumptions jsonb := '[]'::jsonb;
  v_on_hit_templates jsonb := '[]'::jsonb;
  v_skip_damage boolean := false;
  v_feature_state record;
  v_feature_entry jsonb;
  v_modifier_entry jsonb;
  v_on_hit_entry jsonb;
  v_consumption_entry jsonb;
  v_next_feature_uses integer;
  v_next_feature_charges integer;
  v_next_feature_recharge integer;
  v_next_feature_requires_reload boolean;
begin
  v_created_by := coalesce(v_actor_token_id, '');

  select coalesce(array_agg(value::uuid), '{}'::uuid[])
  into v_activated_feature_state_ids
  from jsonb_array_elements_text(coalesce(p_payload->'activated_feature_state_ids', '[]'::jsonb)) value;

  select coalesce(array_agg(value), '{}'::text[])
  into v_activated_feature_codes
  from jsonb_array_elements_text(coalesce(p_payload->'activated_feature_codes', '[]'::jsonb)) value;

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
    perform public.initialize_character_weapon_profile_states(v_weapon.id);
    perform public.initialize_character_weapon_feature_states(v_weapon.id);
    perform public.odyssey_sync_character_weapon_profile_cache(v_weapon.id);

    select *
    into v_weapon
    from public.odyssey_character_weapons w
    where w.id = v_weapon_id
      and w.character_id = v_attacker_character_id;
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
    select
      s.id as profile_state_id,
      p.id as profile_id,
      p.code,
      p.name,
      p.attack_type,
      coalesce(p.weapon_class_id, v_weapon_model.weapon_class_id) as weapon_class_id,
      coalesce(pwc.code, v_weapon_model.weapon_class_code) as weapon_class_code,
      coalesce(pwc.name, v_weapon_model.weapon_class_name) as weapon_class_name,
      coalesce(p.linked_skill_id, v_weapon_model.linked_skill_id) as linked_skill_id,
      coalesce(pskill.code, v_weapon_model.linked_skill_code) as linked_skill_code,
      coalesce(pskill.name, v_weapon_model.linked_skill_name) as linked_skill_name,
      coalesce(p.caliber_id, v_weapon_model.caliber_id) as caliber_id,
      coalesce(pcal.code, v_weapon_model.caliber_code) as caliber_code,
      coalesce(pcal.name, v_weapon_model.caliber_name) as caliber_name,
      coalesce(pcal.base_damage_per_round, v_weapon_model.base_damage_per_round, 0) as base_damage_per_round,
      coalesce(p.range_profile_id, v_weapon_model.range_profile_id) as range_profile_id,
      coalesce(prp.code, v_weapon_model.range_profile_code) as range_profile_code,
      coalesce(prp.name, v_weapon_model.range_profile_name) as range_profile_name,
      coalesce(p.accuracy_modifier, v_weapon_model.base_accuracy_bonus) as accuracy_modifier,
      coalesce(p.base_melee_damage, v_weapon_model.base_melee_damage) as base_melee_damage
    into v_weapon_profile
    from public.odyssey_character_weapon_profile_states s
    join public.odyssey_weapon_model_profiles p on p.id = s.profile_id
    left join public.odyssey_weapon_class_defs pwc on pwc.id = p.weapon_class_id
    left join public.odyssey_skill_defs pskill on pskill.id = p.linked_skill_id
    left join public.odyssey_caliber_defs pcal on pcal.id = p.caliber_id
    left join public.odyssey_range_profile_defs prp on prp.id = p.range_profile_id
    where s.character_weapon_id = v_weapon.id
      and s.is_active = true
    order by s.updated_at desc, s.created_at desc, s.id
    limit 1;

    if not found then
      v_error_code := 'PROFILE_NOT_FOUND';
      v_error_message := 'Active weapon profile state was not found.';
    end if;
  end if;

  if v_error_code is null then
    v_attack_type := coalesce(v_weapon_profile.attack_type, '');
    if v_attack_type not in ('ranged', 'melee') then
      v_error_code := 'ATTACK_TYPE_REQUIRED_FOR_PROFILE';
      v_error_message := 'Active weapon profile must be a strict ranged or melee profile.';
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
      from public.odyssey_weapon_profile_fire_modes pfm
      join public.odyssey_fire_mode_defs fm on fm.id = pfm.fire_mode_id
      where pfm.profile_id = v_weapon_profile.profile_id
        and pfm.fire_mode_id = v_weapon.selected_fire_mode_id
      limit 1;
    end if;

    if not found then
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
      from public.odyssey_weapon_profile_fire_modes pfm
      join public.odyssey_fire_mode_defs fm on fm.id = pfm.fire_mode_id
      where pfm.profile_id = v_weapon_profile.profile_id
        and pfm.is_default = true
      order by pfm.sort_order, pfm.created_at, pfm.id
      limit 1;
    end if;

    if not found then
      v_error_code := 'FIRE_MODE_NOT_ALLOWED_FOR_ACTIVE_PROFILE';
      v_error_message := 'Active profile has no valid fire mode selected.';
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
    select coalesce(s.level, 0)
    into v_attack_skill_level
    from public.odyssey_skill_defs d
    left join public.odyssey_character_skills s
      on s.skill_def_id = d.id
     and s.character_id = v_attacker_character_id
    where d.id = v_weapon_profile.linked_skill_id;

    v_attack_skill_modifier := coalesce(
      nullif(jsonb_extract_path_text(v_attacker_effect_summary, 'modifiers', 'skills', v_weapon_profile.linked_skill_code), '')::integer,
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
    v_range_json := public.odyssey_get_range_profile_modifier(v_weapon_profile.range_profile_id, v_distance_m);
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
        if not public.odyssey_is_magazine_compatible_with_profile(v_weapon_profile.profile_id, v_magazine.id)
           or (v_weapon_profile.caliber_id is not null and v_magazine.magazine_caliber_id <> v_weapon_profile.caliber_id)
           or v_magazine.ammo_caliber_id <> v_magazine.magazine_caliber_id then
          v_error_code := 'INVALID_MAGAZINE';
          v_error_message := 'Loaded magazine is incompatible with the active profile.';
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
            v_bullet_damage := greatest(coalesce(v_weapon_profile.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;
            v_remaining_rounds := v_magazine.current_rounds - v_bullets_spent;
          end if;
        end if;
      end if;
    end if;
  elsif v_error_code is null then
    v_strength_value := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'attribute_values', 'strength'), '')::integer, 0);
    v_melee_strength_bonus := greatest(v_strength_value - 10, 0);
    v_total_weapon_damage := coalesce(v_weapon_profile.base_melee_damage, 0) + v_melee_strength_bonus;
    v_bullet_damage := 0;
    v_ammo_accuracy_modifier := 0;
    v_ammo_damage_modifier := 0;
    v_armor_pierce := 0;
    v_magazine_id := null;
    v_ammo_code := null;
    v_remaining_rounds := null;
  end if;

  if v_error_code is null then
    for v_feature_state in
      select
        s.id,
        s.profile_id,
        s.is_active,
        s.is_enabled,
        s.current_charges,
        s.max_charges,
        s.recharge_rounds_left,
        s.cooldown_rounds_left,
        s.active_rounds_left,
        s.active_uses_left,
        s.requires_reload,
        s.data as state_data,
        coalesce(link.data, '{}'::jsonb) as model_data,
        def.data as definition_data,
        public.odyssey_merge_weapon_feature_data(
          public.odyssey_merge_weapon_feature_data(def.data, coalesce(link.data, '{}'::jsonb)),
          s.data
        ) as merged_data,
        def.code,
        def.name,
        def.feature_type,
        def.activation_type,
        def.default_recharge_rounds,
        def.default_cooldown_rounds,
        def.default_active_rounds,
        def.default_active_uses,
        def.requires_reload_item_code,
        def.effect_data
      from public.odyssey_character_weapon_feature_states s
      join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
      left join public.odyssey_weapon_model_features link
        on link.weapon_model_id = v_weapon.weapon_model_id
       and link.feature_def_id = s.feature_def_id
       and coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
           = coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
      where s.character_weapon_id = v_weapon.id
        and s.is_enabled = true
        and (
          (
            s.is_active = true
            and (s.profile_id = v_weapon.active_profile_id or s.profile_id is null)
          )
          or (
            s.id = any(v_activated_feature_state_ids)
            and (s.profile_id = v_weapon.active_profile_id or s.profile_id is null)
          )
          or (
            array_length(v_activated_feature_codes, 1) is not null
            and def.code = any(v_activated_feature_codes)
            and (s.profile_id = v_weapon.active_profile_id or s.profile_id is null)
          )
        )
      order by
        case
          when s.id = any(v_activated_feature_state_ids) then 0
          when array_length(v_activated_feature_codes, 1) is not null and def.code = any(v_activated_feature_codes) then 0
          when s.is_active then 1
          else 2
        end,
        def.sort_order,
        def.code
    loop
      if coalesce(v_feature_state.merged_data->'conditions'->>'attack_type', v_attack_type) <> v_attack_type then
        continue;
      end if;

      if not v_feature_state.is_active then
        if v_feature_state.activation_type not in ('on_attack', 'on_hit', 'custom') then
          v_error_code := 'WEAPON_FEATURE_NOT_AVAILABLE';
          v_error_message := format('Feature % cannot be activated directly during attack.', v_feature_state.code);
          exit;
        end if;

        if coalesce(v_feature_state.requires_reload, false) then
          v_error_code := 'WEAPON_FEATURE_NOT_AVAILABLE';
          v_error_message := format('Feature % requires manual reload before use.', v_feature_state.code);
          exit;
        end if;

        if coalesce(v_feature_state.recharge_rounds_left, 0) > 0
           or coalesce(v_feature_state.cooldown_rounds_left, 0) > 0
           or (v_feature_state.current_charges is not null and v_feature_state.current_charges <= 0) then
          v_error_code := 'WEAPON_FEATURE_NOT_AVAILABLE';
          v_error_message := format('Feature % is not ready for use.', v_feature_state.code);
          exit;
        end if;
      end if;

      for v_modifier_entry in
        select value
        from jsonb_array_elements(coalesce(v_feature_state.merged_data->'modifiers', '[]'::jsonb))
      loop
        case coalesce(v_modifier_entry->>'target', '')
          when 'attack_accuracy' then
            v_feature_attack_accuracy_modifier := v_feature_attack_accuracy_modifier + coalesce((v_modifier_entry->>'value')::integer, 0);
          when 'damage' then
            v_feature_damage_modifier := v_feature_damage_modifier + coalesce((v_modifier_entry->>'value')::integer, 0);
          when 'armor_pierce' then
            v_feature_armor_pierce_modifier := v_feature_armor_pierce_modifier + coalesce((v_modifier_entry->>'value')::integer, 0);
          when 'aim_difficulty' then
            v_feature_aim_difficulty_modifier := v_feature_aim_difficulty_modifier + coalesce((v_modifier_entry->>'value')::integer, 0);
          when 'range' then
            v_feature_range_modifier := v_feature_range_modifier + coalesce((v_modifier_entry->>'value')::integer, 0);
          else
            null;
        end case;
      end loop;

      if coalesce(v_feature_state.merged_data->>'skip_damage', 'false') in ('true', '1', 'yes', 'on') then
        v_skip_damage := true;
      end if;

      for v_on_hit_entry in
        select value
        from jsonb_array_elements(coalesce(v_feature_state.merged_data->'on_hit', '[]'::jsonb))
      loop
        v_on_hit_templates := v_on_hit_templates || jsonb_build_array(
          jsonb_build_object(
            'feature_code', v_feature_state.code,
            'feature_name', v_feature_state.name,
            'entry', v_on_hit_entry
          )
        );
      end loop;

      v_feature_usage_log := v_feature_usage_log || jsonb_build_array(
        jsonb_build_object(
          'state_id', v_feature_state.id,
          'code', v_feature_state.code,
          'name', v_feature_state.name,
          'source',
            case
              when v_feature_state.is_active then 'active'
              else 'attack_activation'
            end,
          'profile_id', v_feature_state.profile_id,
          'modifiers', coalesce(v_feature_state.merged_data->'modifiers', '[]'::jsonb),
          'skip_damage', coalesce(v_feature_state.merged_data->>'skip_damage', 'false')
        )
      );

      if v_feature_state.is_active and v_feature_state.active_uses_left is not null then
        v_feature_consumptions := v_feature_consumptions || jsonb_build_array(
          jsonb_build_object(
            'state_id', v_feature_state.id,
            'mode', 'active_use',
            'requires_reload_item_code', v_feature_state.requires_reload_item_code
          )
        );
      elsif not v_feature_state.is_active then
        v_feature_consumptions := v_feature_consumptions || jsonb_build_array(
          jsonb_build_object(
            'state_id', v_feature_state.id,
            'mode', 'attack_activation',
            'default_recharge_rounds', v_feature_state.default_recharge_rounds,
            'default_cooldown_rounds', v_feature_state.default_cooldown_rounds,
            'requires_reload_item_code', v_feature_state.requires_reload_item_code
          )
        );
      end if;
    end loop;
  end if;

  if v_error_code is null then
    v_total_weapon_damage := greatest(v_total_weapon_damage + v_attacker_damage_modifier + v_feature_damage_modifier, 0);
    v_armor_pierce := greatest(v_armor_pierce + v_feature_armor_pierce_modifier, 0);
    v_range_modifier := v_range_modifier + v_feature_range_modifier;
    v_attacker_attack_accuracy_modifier := v_attacker_attack_accuracy_modifier + v_feature_attack_accuracy_modifier;
    v_attacker_aim_difficulty_modifier := v_attacker_aim_difficulty_modifier + v_feature_aim_difficulty_modifier;
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
    v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);

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
      + coalesce(v_weapon_profile.accuracy_modifier, 0)
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

  if v_error_code is null and v_hit and not v_skip_damage then
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
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
  end if;

  if v_error_code is null and v_hit then
    for v_feature_entry in
      select value
      from jsonb_array_elements(coalesce(v_on_hit_templates, '[]'::jsonb))
    loop
      if coalesce(v_feature_entry->'entry'->>'type', '') = 'pending_save' then
        v_pending_saves := v_pending_saves || jsonb_build_array(
          jsonb_build_object(
            'source', 'weapon_feature',
            'feature_code', v_feature_entry->>'feature_code',
            'target_character_id', v_target_character_id,
            'attribute', coalesce(v_feature_entry->'entry'->>'attribute', ''),
            'reason', coalesce(v_feature_entry->'entry'->>'reason', v_feature_entry->>'feature_code'),
            'suggested_effect_code', v_feature_entry->'entry'->>'suggested_effect_code',
            'notes', coalesce(
              nullif(v_feature_entry->'entry'->>'notes', ''),
              'GM/player should resolve the save manually and apply the effect if needed.'
            )
          )
        );
      else
        v_pending_effects := v_pending_effects || jsonb_build_array(
          jsonb_build_object(
            'source', 'weapon_feature',
            'feature_code', v_feature_entry->>'feature_code',
            'target_character_id', v_target_character_id,
            'payload', coalesce(v_feature_entry->'entry', '{}'::jsonb)
          )
        );
      end if;
    end loop;
  end if;

  if v_error_code is null then
    for v_consumption_entry in
      select value
      from jsonb_array_elements(coalesce(v_feature_consumptions, '[]'::jsonb))
    loop
      if coalesce(v_consumption_entry->>'mode', '') = 'active_use' then
        select active_uses_left
        into v_next_feature_uses
        from public.odyssey_character_weapon_feature_states
        where id = nullif(v_consumption_entry->>'state_id', '')::uuid;

        if v_next_feature_uses is not null then
          v_next_feature_uses := greatest(v_next_feature_uses - 1, 0);

          update public.odyssey_character_weapon_feature_states
          set
            active_uses_left = case when v_next_feature_uses <= 0 then 0 else v_next_feature_uses end,
            is_active = case when v_next_feature_uses <= 0 then false else is_active end,
            requires_reload =
              case
                when v_next_feature_uses <= 0 and coalesce(v_consumption_entry->>'requires_reload_item_code', '') <> '' then true
                else requires_reload
              end
          where id = nullif(v_consumption_entry->>'state_id', '')::uuid;
        end if;
      elsif coalesce(v_consumption_entry->>'mode', '') = 'attack_activation' then
        select current_charges
        into v_next_feature_charges
        from public.odyssey_character_weapon_feature_states
        where id = nullif(v_consumption_entry->>'state_id', '')::uuid;

        v_next_feature_charges := case when v_next_feature_charges is null then null else greatest(v_next_feature_charges - 1, 0) end;
        v_next_feature_recharge := nullif(v_consumption_entry->>'default_recharge_rounds', '')::integer;
        v_next_feature_requires_reload :=
          coalesce(v_consumption_entry->>'requires_reload_item_code', '') <> ''
          and coalesce(v_next_feature_recharge, 0) = 0
          and coalesce(v_next_feature_charges, 0) <= 0;

        update public.odyssey_character_weapon_feature_states
        set
          is_active = false,
          current_charges = v_next_feature_charges,
          recharge_rounds_left =
            case
              when coalesce(v_next_feature_recharge, 0) > 0 then v_next_feature_recharge
              else recharge_rounds_left
            end,
          cooldown_rounds_left =
            case
              when nullif(v_consumption_entry->>'default_cooldown_rounds', '')::integer is not null
                then nullif(v_consumption_entry->>'default_cooldown_rounds', '')::integer
              else cooldown_rounds_left
            end,
          requires_reload = v_next_feature_requires_reload
        where id = nullif(v_consumption_entry->>'state_id', '')::uuid;
      end if;
    end loop;
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
    'weapon_features',
      jsonb_build_object(
        'active_profile', public.odyssey_get_active_character_weapon_profile(v_weapon.id),
        'activated_features', v_feature_usage_log,
        'applied_feature_modifiers',
          jsonb_build_object(
            'attack_accuracy', v_feature_attack_accuracy_modifier,
            'damage', v_feature_damage_modifier,
            'armor_pierce', v_feature_armor_pierce_modifier,
            'aim_difficulty', v_feature_aim_difficulty_modifier,
            'range', v_feature_range_modifier
          ),
        'pending_saves', v_pending_saves,
        'pending_effects', v_pending_effects
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
        'base_melee_damage', v_weapon_model.base_melee_damage,
        'active_profile', public.odyssey_get_active_character_weapon_profile(v_weapon.id)
      ),
    'fire_mode',
      jsonb_build_object(
        'id', v_fire_mode.id,
        'code', v_fire_mode.code,
        'accuracy_modifier', v_fire_mode.accuracy_modifier
      ),
    'ammo',
      jsonb_build_object(
        'caliber', v_weapon_profile.caliber_code,
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
    'weapon_features',
      jsonb_build_object(
        'active_profile', public.odyssey_get_active_character_weapon_profile(v_weapon.id),
        'activated_features', v_feature_usage_log,
        'applied_feature_modifiers',
          jsonb_build_object(
            'attack_accuracy', v_feature_attack_accuracy_modifier,
            'damage', v_feature_damage_modifier,
            'armor_pierce', v_feature_armor_pierce_modifier,
            'aim_difficulty', v_feature_aim_difficulty_modifier,
            'range', v_feature_range_modifier
          ),
        'pending_saves', v_pending_saves,
        'pending_effects', v_pending_effects
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
    'pending_saves', v_pending_saves,
    'pending_effects', v_pending_effects,
    'target_state', v_target_state,
    'attacker_state', v_attacker_state,
    'execution', v_execution_info,
    'log_id', v_log_id
  )
  into v_result;

  return v_result;
end;
$$;

grant execute on function public.odyssey_get_range_profile_modifier(uuid, numeric) to anon, authenticated;
grant execute on function public.odyssey_get_default_weapon_profile_id(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_default_profile_fire_mode_id(uuid) to anon, authenticated;
grant execute on function public.odyssey_merge_weapon_feature_data(jsonb, jsonb) to anon, authenticated;
grant execute on function public.odyssey_is_fire_mode_allowed_for_profile(uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_is_magazine_compatible_with_profile(uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_ensure_default_weapon_profile(uuid) to anon, authenticated;
grant execute on function public.odyssey_sync_character_weapon_profile_cache(uuid) to anon, authenticated;
grant execute on function public.initialize_character_weapon_profile_states(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_weapon_profile(uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_weapon_profiles(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_active_character_weapon_profile(uuid) to anon, authenticated;
grant execute on function public.initialize_character_weapon_feature_states(uuid) to anon, authenticated;
grant execute on function public.get_character_weapon_features(uuid) to anon, authenticated;
grant execute on function public.activate_weapon_feature(jsonb) to anon, authenticated;
grant execute on function public.deactivate_weapon_feature(uuid) to anon, authenticated;
grant execute on function public.reload_feature_resource(uuid) to anon, authenticated;
grant execute on function public.advance_weapon_feature_states(uuid) to anon, authenticated;
grant execute on function public.switch_weapon_profile(uuid, uuid) to anon, authenticated;
grant execute on function public.load_weapon_profile_magazine(jsonb) to anon, authenticated;
grant execute on function public.get_character_armory(uuid) to anon, authenticated;
grant execute on function public.create_character_weapon(uuid, uuid, text) to anon, authenticated;
grant execute on function public.load_magazine(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.unload_magazine(uuid, uuid) to anon, authenticated;
grant execute on function public.switch_weapon_fire_mode(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.perform_attack(jsonb) to anon, authenticated;
