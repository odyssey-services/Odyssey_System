create extension if not exists pgcrypto;

create table if not exists public.odyssey_resource_pool_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  source_type text not null default 'fixed' check (source_type in ('attribute', 'fixed', 'custom')),
  attribute_def_id uuid null references public.odyssey_attribute_defs(id) on delete set null,
  default_max_value integer not null default 0 check (default_max_value >= 0),
  default_current_value integer null check (default_current_value is null or default_current_value >= 0),
  recovery_mode text not null default 'manual' check (recovery_mode in ('manual', 'full_rest', 'scene', 'custom')),
  description text not null default '',
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_resource_pools (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  resource_pool_def_id uuid not null references public.odyssey_resource_pool_defs(id) on delete cascade,
  current_value integer not null default 0 check (current_value >= 0),
  max_value integer not null default 0 check (max_value >= 0),
  reserved_value integer not null default 0 check (reserved_value >= 0),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_id, resource_pool_def_id)
);

create table if not exists public.odyssey_ability_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  ability_kind text not null check (ability_kind in ('attack', 'buff', 'defense', 'utility', 'narrative', 'custom')),
  source_type text not null check (source_type in ('psionic', 'implant', 'prosthetic', 'equipment', 'item', 'innate', 'custom')),
  activation_type text not null default 'manual' check (activation_type in ('manual', 'passive', 'on_attack', 'on_hit', 'always', 'custom')),
  target_type text not null default 'self' check (target_type in ('self', 'character', 'body_part', 'none', 'custom')),
  effect_mode text not null default 'narrative' check (effect_mode in ('attack', 'apply_effect', 'grant_special', 'narrative', 'custom')),
  attack_type text null check (attack_type is null or attack_type in ('ranged', 'melee', 'custom')),
  linked_skill_id uuid null references public.odyssey_skill_defs(id) on delete set null,
  resource_mode text not null default 'none' check (resource_mode in ('none', 'pool', 'item', 'cooldown', 'custom')),
  resource_pool_code text null,
  resource_item_code text null,
  description text not null default '',
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  effect_data jsonb not null default '{}'::jsonb check (jsonb_typeof(effect_data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_ability_level_defs (
  id uuid primary key default gen_random_uuid(),
  ability_def_id uuid not null references public.odyssey_ability_defs(id) on delete cascade,
  ability_level integer not null check (ability_level >= 1),
  resource_cost integer not null default 0 check (resource_cost >= 0),
  cooldown_rounds integer null check (cooldown_rounds is null or cooldown_rounds >= 0),
  range_profile_id uuid null references public.odyssey_range_profile_defs(id) on delete set null,
  attack_accuracy_bonus integer not null default 0,
  attack_damage_bonus integer not null default 0,
  attack_armor_pierce integer not null default 0,
  ignore_armor boolean not null default false,
  special_armor_value integer null check (special_armor_value is null or special_armor_value >= 0),
  special_max_critical integer null check (special_max_critical is null or special_max_critical >= 0),
  duration_rounds integer null check (duration_rounds is null or duration_rounds >= 0),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  effect_data jsonb not null default '{}'::jsonb check (jsonb_typeof(effect_data) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (ability_def_id, ability_level)
);

create table if not exists public.odyssey_character_abilities (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  ability_def_id uuid not null references public.odyssey_ability_defs(id) on delete cascade,
  character_skill_id uuid null references public.odyssey_character_skills(id) on delete set null,
  learned_level integer not null default 0 check (learned_level >= 0),
  source_equipment_item_id uuid null references public.odyssey_character_equipment_items(id) on delete set null,
  source_character_item_id uuid null references public.odyssey_character_items(id) on delete set null,
  is_enabled boolean not null default true,
  is_hidden boolean not null default false,
  current_cooldown_rounds integer not null default 0 check (current_cooldown_rounds >= 0),
  current_charges integer null check (current_charges is null or current_charges >= 0),
  max_charges integer null check (max_charges is null or max_charges >= 0),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists odyssey_character_abilities_unique_source_idx
  on public.odyssey_character_abilities (
    character_id,
    ability_def_id,
    coalesce(source_equipment_item_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(source_character_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists odyssey_character_resource_pools_character_idx
  on public.odyssey_character_resource_pools (character_id, resource_pool_def_id);

create index if not exists odyssey_ability_defs_kind_idx
  on public.odyssey_ability_defs (ability_kind, source_type, sort_order, code);

create index if not exists odyssey_ability_level_defs_ability_idx
  on public.odyssey_ability_level_defs (ability_def_id, ability_level);

create index if not exists odyssey_character_abilities_character_idx
  on public.odyssey_character_abilities (character_id, ability_def_id, sort_order, created_at);

alter table public.odyssey_resource_pool_defs enable row level security;
alter table public.odyssey_character_resource_pools enable row level security;
alter table public.odyssey_ability_defs enable row level security;
alter table public.odyssey_ability_level_defs enable row level security;
alter table public.odyssey_character_abilities enable row level security;

drop policy if exists "odyssey_resource_pool_defs_full_access" on public.odyssey_resource_pool_defs;
create policy "odyssey_resource_pool_defs_full_access"
on public.odyssey_resource_pool_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_resource_pools_full_access" on public.odyssey_character_resource_pools;
create policy "odyssey_character_resource_pools_full_access"
on public.odyssey_character_resource_pools
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_ability_defs_full_access" on public.odyssey_ability_defs;
create policy "odyssey_ability_defs_full_access"
on public.odyssey_ability_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_ability_level_defs_full_access" on public.odyssey_ability_level_defs;
create policy "odyssey_ability_level_defs_full_access"
on public.odyssey_ability_level_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_abilities_full_access" on public.odyssey_character_abilities;
create policy "odyssey_character_abilities_full_access"
on public.odyssey_character_abilities
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_resource_pool_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_resource_pools to anon, authenticated;
grant select, insert, update, delete on public.odyssey_ability_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_ability_level_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_abilities to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_resource_pool_defs on public.odyssey_resource_pool_defs;
create trigger odyssey_touch_updated_at_resource_pool_defs
before update on public.odyssey_resource_pool_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_resource_pools on public.odyssey_character_resource_pools;
create trigger odyssey_touch_updated_at_character_resource_pools
before update on public.odyssey_character_resource_pools
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_ability_defs on public.odyssey_ability_defs;
create trigger odyssey_touch_updated_at_ability_defs
before update on public.odyssey_ability_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_ability_level_defs on public.odyssey_ability_level_defs;
create trigger odyssey_touch_updated_at_ability_level_defs
before update on public.odyssey_ability_level_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_abilities on public.odyssey_character_abilities;
create trigger odyssey_touch_updated_at_character_abilities
before update on public.odyssey_character_abilities
for each row
execute function public.odyssey_touch_updated_at();

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

create or replace function public.odyssey_get_character_ability_effective_level(
  p_character_ability_id uuid
)
returns integer
language sql
stable
as $$
  select greatest(
    coalesce(
      linked_skill.level,
      direct_skill.level,
      ability.learned_level,
      0
    ),
    0
  )::integer
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  left join public.odyssey_character_skills direct_skill
    on direct_skill.id = ability.character_skill_id
  left join public.odyssey_character_skills linked_skill
    on ability.character_skill_id is null
   and linked_skill.character_id = ability.character_id
   and linked_skill.skill_def_id = def.linked_skill_id
  where ability.id = p_character_ability_id;
$$;

create or replace function public.odyssey_recalculate_character_body_part_caps(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_endurance integer := 0;
  v_bonus_steps integer := 0;
  v_updated_count integer := 0;
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

  select coalesce(a.value, 0)
  into v_endurance
  from public.odyssey_attribute_defs d
  left join public.odyssey_character_attributes a
    on a.attribute_def_id = d.id
   and a.character_id = p_character_id
  where d.code = 'endurance'
  limit 1;

  v_bonus_steps := floor(greatest(v_endurance - 10, 0)::numeric / 5::numeric)::integer;

  with updated_rows as (
    update public.odyssey_character_body_parts b
    set
      max_critical = case
        when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) = 'head'
          then greatest(1 + v_bonus_steps, 0)
        when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) in ('torso', 'l_arm', 'r_arm', 'l_leg', 'r_leg')
          then greatest(2 + v_bonus_steps, 0)
        else greatest(coalesce(b.max_critical, d.default_max_critical, 0), 0)
      end,
      disabled = case
        when b.destroyed then true
        when b.critical > 0 then true
        else false
      end,
      destroyed = case
        when case
          when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) = 'head'
            then greatest(1 + v_bonus_steps, 0)
          when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) in ('torso', 'l_arm', 'r_arm', 'l_leg', 'r_leg')
            then greatest(2 + v_bonus_steps, 0)
          else greatest(coalesce(b.max_critical, d.default_max_critical, 0), 0)
        end > 0
        and b.critical >= case
          when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) = 'head'
            then greatest(1 + v_bonus_steps, 0)
          when coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) in ('torso', 'l_arm', 'r_arm', 'l_leg', 'r_leg')
            then greatest(2 + v_bonus_steps, 0)
          else greatest(coalesce(b.max_critical, d.default_max_critical, 0), 0)
        end
          then true
        else b.destroyed
      end
    from public.odyssey_body_part_defs d
    where b.character_id = p_character_id
      and d.id = b.body_part_def_id
    returning 1
  )
  select count(*) into v_updated_count from updated_rows;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'endurance', v_endurance,
    'bonus_steps', v_bonus_steps,
    'updated_body_parts', v_updated_count
  );
end;
$$;

create or replace function public.odyssey_normalize_body_part_damage(
  p_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_part record;
  v_extra_serious integer := 0;
  v_extra_critical integer := 0;
  v_new_minor integer := 0;
  v_new_serious integer := 0;
  v_new_critical integer := 0;
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
begin
  select
    b.id,
    b.character_id,
    b.part_key,
    b.minor,
    b.serious,
    b.critical,
    b.max_critical,
    b.disabled,
    b.destroyed,
    coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
    coalesce(d.name, b.part_key) as part_name
  into v_part
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

  v_extra_serious := floor(greatest(coalesce(v_part.minor, 0), 0)::numeric / 4::numeric)::integer;
  v_new_minor := mod(greatest(coalesce(v_part.minor, 0), 0), 4);
  v_new_serious := greatest(coalesce(v_part.serious, 0), 0) + v_extra_serious;
  v_extra_critical := floor(v_new_serious::numeric / 2::numeric)::integer;
  v_new_serious := mod(v_new_serious, 2);
  v_new_critical := greatest(coalesce(v_part.critical, 0), 0) + v_extra_critical;
  v_new_destroyed := case
    when coalesce(v_part.max_critical, 0) > 0 and v_new_critical >= coalesce(v_part.max_critical, 0) then true
    else coalesce(v_part.destroyed, false)
  end;
  v_new_disabled := case
    when v_new_destroyed then true
    when v_new_critical > 0 then true
    else false
  end;

  update public.odyssey_character_body_parts
  set
    minor = v_new_minor,
    serious = v_new_serious,
    critical = v_new_critical,
    disabled = v_new_disabled,
    destroyed = v_new_destroyed
  where id = p_body_part_id;

  return jsonb_build_object(
    'ok', true,
    'body_part_id', p_body_part_id,
    'character_id', v_part.character_id,
    'part_code', v_part.part_code,
    'part_name', v_part.part_name,
    'minor', v_new_minor,
    'serious', v_new_serious,
    'critical', v_new_critical,
    'max_critical', coalesce(v_part.max_critical, 0),
    'disabled', v_new_disabled,
    'destroyed', v_new_destroyed,
    'converted_minor_to_serious', v_extra_serious,
    'converted_serious_to_critical', v_extra_critical
  );
end;
$$;

create or replace function public.odyssey_sync_character_resource_pools(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_inserted_count integer := 0;
  v_updated_count integer := 0;
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

  with pool_defaults as (
    select
      d.id as resource_pool_def_id,
      case
        when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
        else greatest(coalesce(d.default_max_value, 0), 0)
      end as computed_max_value,
      case
        when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
        when d.default_current_value is not null then greatest(d.default_current_value, 0)
        else greatest(coalesce(d.default_max_value, 0), 0)
      end as computed_current_value
    from public.odyssey_resource_pool_defs d
    left join public.odyssey_character_attributes a
      on a.character_id = p_character_id
     and a.attribute_def_id = d.attribute_def_id
  ),
  inserted as (
    insert into public.odyssey_character_resource_pools (
      character_id,
      resource_pool_def_id,
      current_value,
      max_value,
      reserved_value,
      data,
      notes
    )
    select
      p_character_id,
      pd.resource_pool_def_id,
      least(pd.computed_current_value, pd.computed_max_value),
      pd.computed_max_value,
      0,
      '{}'::jsonb,
      ''
    from pool_defaults pd
    where not exists (
      select 1
      from public.odyssey_character_resource_pools p
      where p.character_id = p_character_id
        and p.resource_pool_def_id = pd.resource_pool_def_id
    )
    returning 1
  ),
  updated as (
    update public.odyssey_character_resource_pools p
    set
      max_value = pd.computed_max_value,
      current_value = least(greatest(p.current_value, 0), pd.computed_max_value),
      reserved_value = least(greatest(p.reserved_value, 0), pd.computed_max_value),
      updated_at = timezone('utc', now())
    from pool_defaults pd
    where p.character_id = p_character_id
      and p.resource_pool_def_id = pd.resource_pool_def_id
    returning 1
  )
  select
    coalesce((select count(*) from inserted), 0),
    coalesce((select count(*) from updated), 0)
  into
    v_inserted_count,
    v_updated_count;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'inserted_pools', v_inserted_count,
    'updated_pools', v_updated_count
  );
end;
$$;

create or replace function public.get_character_abilities(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_exists boolean := false;
  v_resource_pools jsonb := '[]'::jsonb;
  v_abilities jsonb := '[]'::jsonb;
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
      'character_id', p_character_id,
      'resource_pools', '[]'::jsonb,
      'abilities', '[]'::jsonb
    );
  end if;

  with resource_rows as (
    select
      d.sort_order,
      d.code,
      jsonb_build_object(
        'id', p.id,
        'resource_pool_def_id', d.id,
        'code', d.code,
        'name', d.name,
        'source_type', d.source_type,
        'attribute_code', attr.code,
        'recovery_mode', d.recovery_mode,
        'current_value',
          coalesce(
            p.current_value,
            case
              when d.default_current_value is not null then least(d.default_current_value, case
                when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
                else greatest(coalesce(d.default_max_value, 0), 0)
              end)
              when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
              else greatest(coalesce(d.default_max_value, 0), 0)
            end,
            0
          ),
        'max_value',
          case
            when d.source_type = 'attribute' and d.attribute_def_id is not null then greatest(coalesce(a.value, d.default_max_value, 0), 0)
            else greatest(coalesce(d.default_max_value, 0), 0)
          end,
        'reserved_value', coalesce(p.reserved_value, 0),
        'description', d.description,
        'data', coalesce(p.data, '{}'::jsonb),
        'notes', coalesce(p.notes, ''),
        'tags', d.tags
      ) as payload
    from public.odyssey_resource_pool_defs d
    left join public.odyssey_attribute_defs attr on attr.id = d.attribute_def_id
    left join public.odyssey_character_attributes a
      on a.character_id = p_character_id
     and a.attribute_def_id = d.attribute_def_id
    left join public.odyssey_character_resource_pools p
      on p.character_id = p_character_id
     and p.resource_pool_def_id = d.id
  )
  select coalesce(jsonb_agg(payload order by sort_order, code), '[]'::jsonb)
  into v_resource_pools
  from resource_rows;

  with ability_rows as (
    select
      ability.sort_order,
      def.sort_order as def_sort_order,
      def.code,
      jsonb_build_object(
        'id', ability.id,
        'character_id', ability.character_id,
        'ability_def_id', def.id,
        'code', def.code,
        'name', def.name,
        'ability_kind', def.ability_kind,
        'source_type', def.source_type,
        'activation_type', def.activation_type,
        'target_type', def.target_type,
        'effect_mode', def.effect_mode,
        'attack_type', def.attack_type,
        'description', def.description,
        'linked_skill_id', def.linked_skill_id,
        'linked_skill_code', linked_def.code,
        'linked_skill_name', linked_def.name,
        'character_skill_id', coalesce(direct_skill.id, linked_skill.id),
        'character_skill_level', coalesce(direct_skill.level, linked_skill.level, 0),
        'learned_level', ability.learned_level,
        'effective_level', greatest(coalesce(direct_skill.level, linked_skill.level, ability.learned_level, 0), 0),
        'is_enabled', ability.is_enabled,
        'is_hidden', ability.is_hidden,
        'current_cooldown_rounds', ability.current_cooldown_rounds,
        'current_charges', ability.current_charges,
        'max_charges', ability.max_charges,
        'resource',
          jsonb_build_object(
            'mode', def.resource_mode,
            'pool_code', def.resource_pool_code,
            'item_code', def.resource_item_code,
            'cost', coalesce(level_data.resource_cost, 0)
          ),
        'source_equipment_item_id', ability.source_equipment_item_id,
        'source_character_item_id', ability.source_character_item_id,
        'data', ability.data,
        'notes', ability.notes,
        'tags', def.tags,
        'level_data',
          case
            when level_data.id is null then null
            else jsonb_build_object(
              'id', level_data.id,
              'ability_level', level_data.ability_level,
              'resource_cost', level_data.resource_cost,
              'cooldown_rounds', level_data.cooldown_rounds,
              'range_profile_id', level_data.range_profile_id,
              'attack_accuracy_bonus', level_data.attack_accuracy_bonus,
              'attack_damage_bonus', level_data.attack_damage_bonus,
              'attack_armor_pierce', level_data.attack_armor_pierce,
              'ignore_armor', level_data.ignore_armor,
              'special_armor_value', level_data.special_armor_value,
              'special_max_critical', level_data.special_max_critical,
              'duration_rounds', level_data.duration_rounds,
              'data', level_data.data,
              'effect_data', level_data.effect_data
            )
          end
      ) as payload
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    left join public.odyssey_skill_defs linked_def on linked_def.id = def.linked_skill_id
    left join public.odyssey_character_skills direct_skill
      on direct_skill.id = ability.character_skill_id
    left join public.odyssey_character_skills linked_skill
      on ability.character_skill_id is null
     and linked_skill.character_id = ability.character_id
     and linked_skill.skill_def_id = def.linked_skill_id
    left join lateral (
      select level_entry.*
      from public.odyssey_ability_level_defs level_entry
      where level_entry.ability_def_id = def.id
        and level_entry.ability_level <= greatest(coalesce(direct_skill.level, linked_skill.level, ability.learned_level, 0), 0)
      order by level_entry.ability_level desc
      limit 1
    ) level_data on true
    where ability.character_id = p_character_id
  )
  select coalesce(jsonb_agg(payload order by sort_order, def_sort_order, code), '[]'::jsonb)
  into v_abilities
  from ability_rows;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'resource_pools', v_resource_pools,
    'abilities', v_abilities
  );
end;
$$;

create or replace function public.odyssey_consume_character_ability_cost(
  p_character_ability_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_ability record;
  v_effective_level integer := 0;
  v_level record;
  v_pool record;
  v_sync jsonb := '{}'::jsonb;
  v_item_result jsonb := '{}'::jsonb;
begin
  select
    ability.id,
    ability.character_id,
    ability.current_cooldown_rounds,
    ability.current_charges,
    ability.max_charges,
    def.code as ability_code,
    def.name as ability_name,
    def.resource_mode,
    def.resource_pool_code,
    def.resource_item_code
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = p_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', p_character_ability_id
    );
  end if;

  if coalesce(v_ability.current_cooldown_rounds, 0) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_ON_COOLDOWN',
      'character_ability_id', p_character_ability_id,
      'cooldown_rounds_left', v_ability.current_cooldown_rounds
    );
  end if;

  v_effective_level := public.odyssey_get_character_ability_effective_level(p_character_ability_id);

  select *
  into v_level
  from public.odyssey_ability_level_defs level_data
  join public.odyssey_character_abilities ability on ability.ability_def_id = level_data.ability_def_id
  where ability.id = p_character_ability_id
    and level_data.ability_level <= v_effective_level
  order by level_data.ability_level desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_LEVEL_NOT_AVAILABLE',
      'character_ability_id', p_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  if coalesce(v_level.resource_cost, 0) <= 0 or v_ability.resource_mode in ('none', 'cooldown', 'custom') then
    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'resource_consumed', false
    );
  end if;

  if v_ability.resource_mode = 'pool' then
    v_sync := public.odyssey_sync_character_resource_pools(v_ability.character_id);

    select
      p.id,
      p.current_value,
      p.max_value,
      d.code,
      d.name
    into v_pool
    from public.odyssey_character_resource_pools p
    join public.odyssey_resource_pool_defs d on d.id = p.resource_pool_def_id
    where p.character_id = v_ability.character_id
      and d.code = v_ability.resource_pool_code
    for update of p;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_POOL_NOT_FOUND',
        'character_ability_id', p_character_ability_id,
        'resource_pool_code', v_ability.resource_pool_code,
        'sync', v_sync
      );
    end if;

    if coalesce(v_pool.current_value, 0) < coalesce(v_level.resource_cost, 0) then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_ENERGY',
        'character_ability_id', p_character_ability_id,
        'resource_pool_code', v_pool.code,
        'required', v_level.resource_cost,
        'available', coalesce(v_pool.current_value, 0)
      );
    end if;

    update public.odyssey_character_resource_pools
    set current_value = greatest(current_value - coalesce(v_level.resource_cost, 0), 0)
    where id = v_pool.id;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_consumed', true,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'resource_pool',
        jsonb_build_object(
          'id', v_pool.id,
          'code', v_pool.code,
          'name', v_pool.name,
          'before', coalesce(v_pool.current_value, 0),
          'after', greatest(coalesce(v_pool.current_value, 0) - coalesce(v_level.resource_cost, 0), 0),
          'max', coalesce(v_pool.max_value, 0)
        )
    );
  end if;

  if v_ability.resource_mode = 'item' then
    if nullif(trim(coalesce(v_ability.resource_item_code, '')), '') is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_ITEM_CODE_REQUIRED',
        'character_ability_id', p_character_ability_id
      );
    end if;

    v_item_result := public.remove_character_item_quantity(
      v_ability.character_id,
      v_ability.resource_item_code,
      coalesce(v_level.resource_cost, 0)
    );

    if coalesce((v_item_result->>'ok')::boolean, false) = false then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_ITEM_NOT_AVAILABLE',
        'character_ability_id', p_character_ability_id,
        'resource_item_code', v_ability.resource_item_code,
        'details', v_item_result
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_consumed', true,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'item', v_item_result
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', p_character_ability_id,
    'resource_mode', v_ability.resource_mode,
    'resource_cost', coalesce(v_level.resource_cost, 0),
    'resource_consumed', false
  );
end;
$$;

create or replace function public.advance_character_ability_states(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_changed jsonb := '[]'::jsonb;
begin
  with updated_rows as (
    update public.odyssey_character_abilities ability
    set
      current_cooldown_rounds = greatest(coalesce(ability.current_cooldown_rounds, 0) - 1, 0),
      updated_at = timezone('utc', now())
    where ability.character_id = p_character_id
      and coalesce(ability.current_cooldown_rounds, 0) > 0
    returning ability.id, ability.current_cooldown_rounds
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'character_ability_id', u.id,
        'cooldown_rounds_left', u.current_cooldown_rounds
      )
      order by u.id
    ),
    '[]'::jsonb
  )
  into v_changed
  from updated_rows u;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'changed_abilities', v_changed
  );
end;
$$;

create or replace function public.advance_character_effects(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_changed_effects jsonb := '[]'::jsonb;
  v_expired_effects jsonb := '[]'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_ability_states jsonb := '{}'::jsonb;
  v_weapon_feature_states jsonb := '{}'::jsonb;
begin
  with updated_effects as (
    update public.odyssey_character_effects e
    set
      rounds_left = case
        when e.duration_type = 'rounds' and e.rounds_left is not null
          then greatest(e.rounds_left - 1, 0)
        else e.rounds_left
      end,
      is_active = case
        when coalesce(nullif(e.data#>>'{flags,expires_after_turn}', '')::boolean, false) then false
        when e.duration_type = 'rounds' and e.rounds_left is not null and e.rounds_left - 1 <= 0 then false
        else e.is_active
      end,
      updated_at = timezone('utc', now())
    where e.character_id = p_character_id
      and e.is_active = true
      and (
        (e.duration_type = 'rounds' and e.rounds_left is not null)
        or coalesce(nullif(e.data#>>'{flags,expires_after_turn}', '')::boolean, false)
      )
    returning e.*
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', u.id,
          'effect_key', u.effect_key,
          'name', u.name,
          'duration_type', u.duration_type,
          'rounds_left', u.rounds_left,
          'is_active', u.is_active
        )
        order by u.updated_at desc, u.id
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', u.id,
          'effect_key', u.effect_key,
          'name', u.name,
          'duration_type', u.duration_type,
          'rounds_left', u.rounds_left
        )
        order by u.updated_at desc, u.id
      ) filter (where u.is_active = false),
      '[]'::jsonb
    )
  into
    v_changed_effects,
    v_expired_effects
  from updated_effects u;

  v_ability_states := public.advance_character_ability_states(p_character_id);
  v_weapon_feature_states := public.advance_weapon_feature_states(p_character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(p_character_id);
  v_effective_stats := public.get_effective_character_stats(p_character_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'changed_effects', v_changed_effects,
    'expired_effects', v_expired_effects,
    'ability_states', coalesce(v_ability_states->'changed_abilities', '[]'::jsonb),
    'weapon_feature_states', coalesce(v_weapon_feature_states->'states', '[]'::jsonb),
    'effective_stats', v_effective_stats,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
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
    'abilities', coalesce(public.get_character_abilities(c.id)->'abilities', '[]'::jsonb),
    'resource_pools', coalesce(public.get_character_abilities(c.id)->'resource_pools', '[]'::jsonb),
    'armor_summary', public.get_character_armor_summary(c.id),
    'equipment_summary', coalesce(public.get_character_equipment(c.id)->'summary', '{}'::jsonb)
  )
  from selected_character c;
$$;

create or replace function public.get_character_inventory(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_armory jsonb := '{}'::jsonb;
  v_equipment jsonb := '{}'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_ammo_stock jsonb := '[]'::jsonb;
  v_item_summary jsonb := '{}'::jsonb;
  v_ammo_summary jsonb := '{}'::jsonb;
  v_abilities jsonb := '{}'::jsonb;
begin
  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id,
      'items', '[]'::jsonb,
      'ammo_stock', '[]'::jsonb,
      'weapons', '[]'::jsonb,
      'magazines', '[]'::jsonb,
      'equipment', '[]'::jsonb,
      'resource_pools', '[]'::jsonb,
      'abilities', '[]'::jsonb
    );
  end if;

  select
    coalesce(
      jsonb_agg(public.odyssey_get_character_item_row(i.id) order by i.sort_order, i.created_at, i.id),
      '[]'::jsonb
    ),
    jsonb_build_object(
      'stack_count', count(*)::integer,
      'total_quantity', coalesce(sum(i.quantity), 0)::integer
    )
  into
    v_items,
    v_item_summary
  from public.odyssey_character_items i
  where i.character_id = p_character_id;

  select
    coalesce(
      jsonb_agg(public.odyssey_get_character_ammo_stock_row(s.id) order by s.display_name, s.created_at, s.id),
      '[]'::jsonb
    ),
    jsonb_build_object(
      'stock_row_count', count(*)::integer,
      'total_quantity', coalesce(sum(s.quantity), 0)::integer
    )
  into
    v_ammo_stock,
    v_ammo_summary
  from public.odyssey_character_ammo_stock s
  where s.character_id = p_character_id;

  v_armory := public.get_character_armory(p_character_id);
  v_equipment := public.get_character_equipment(p_character_id);
  v_abilities := public.get_character_abilities(p_character_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'items', v_items,
    'item_summary', coalesce(v_item_summary, '{}'::jsonb),
    'ammo_stock', v_ammo_stock,
    'ammo_stock_summary', coalesce(v_ammo_summary, '{}'::jsonb),
    'weapons', coalesce(v_armory->'weapons', '[]'::jsonb),
    'magazines', coalesce(v_armory->'magazines', '[]'::jsonb),
    'equipment', coalesce(v_equipment->'items', '[]'::jsonb),
    'equipment_summary', coalesce(v_equipment->'summary', '{}'::jsonb),
    'armor_summary', coalesce(v_equipment->'armor_summary', '{}'::jsonb),
    'resource_pools', coalesce(v_abilities->'resource_pools', '[]'::jsonb),
    'abilities', coalesce(v_abilities->'abilities', '[]'::jsonb)
  );
end;
$$;

create or replace function public.initialize_character_combat_defaults(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_rule_defaults jsonb := '{}'::jsonb;
  v_unarmed_model_id uuid := null;
  v_melee_strike_id uuid := null;
  v_unarmed_weapon_id uuid := null;
  v_unarmed_created boolean := false;
  v_caps jsonb := '{}'::jsonb;
  v_pools jsonb := '{}'::jsonb;
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

  v_rule_defaults := public.initialize_character_rule_defaults(p_character_id);
  v_caps := public.odyssey_recalculate_character_body_part_caps(p_character_id);
  v_pools := public.odyssey_sync_character_resource_pools(p_character_id);

  select wm.id
  into v_unarmed_model_id
  from public.odyssey_weapon_model_defs wm
  where wm.code = 'unarmed';

  if v_unarmed_model_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'UNARMED_MODEL_NOT_FOUND',
      'character_id', p_character_id,
      'rule_defaults', v_rule_defaults,
      'critical_caps', v_caps,
      'resource_pools_sync', v_pools
    );
  end if;

  select fm.id
  into v_melee_strike_id
  from public.odyssey_fire_mode_defs fm
  where fm.code = 'melee_strike';

  if v_melee_strike_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'MELEE_STRIKE_NOT_FOUND',
      'character_id', p_character_id,
      'rule_defaults', v_rule_defaults,
      'critical_caps', v_caps,
      'resource_pools_sync', v_pools
    );
  end if;

  select w.id
  into v_unarmed_weapon_id
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  where w.character_id = p_character_id
    and wm.code = 'unarmed'
  order by w.sort_order, w.created_at, w.id
  limit 1;

  if v_unarmed_weapon_id is null then
    insert into public.odyssey_character_weapons (
      character_id,
      weapon_model_id,
      custom_name,
      loaded_magazine_id,
      selected_fire_mode_id,
      notes,
      sort_order
    )
    values (
      p_character_id,
      v_unarmed_model_id,
      null,
      null,
      v_melee_strike_id,
      '',
      5
    )
    returning id into v_unarmed_weapon_id;

    v_unarmed_created := true;
  else
    update public.odyssey_character_weapons
    set
      loaded_magazine_id = null,
      selected_fire_mode_id = v_melee_strike_id
    where id = v_unarmed_weapon_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'rule_defaults', v_rule_defaults,
    'critical_caps', v_caps,
    'resource_pools_sync', v_pools,
    'unarmed_weapon_id', v_unarmed_weapon_id,
    'unarmed_created', v_unarmed_created,
    'rule_sheet', public.get_character_rule_sheet(p_character_id),
    'armory', public.get_character_armory(p_character_id),
    'abilities', public.get_character_abilities(p_character_id)
  );
end;
$$;

create or replace function public.use_ability(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_ability_id uuid := nullif(trim(coalesce(p_payload->>'character_ability_id', '')), '')::uuid;
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_ability_code text := lower(trim(coalesce(p_payload->>'ability_code', '')));
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_created_by text := coalesce(nullif(trim(coalesce(p_payload->>'created_by', '')), ''), '');
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_ability record;
  v_level record;
  v_effective_level integer := 0;
  v_target_part record;
  v_resource_result jsonb := '{}'::jsonb;
  v_effect_result jsonb := '{}'::jsonb;
  v_merged_ability_data jsonb := '{}'::jsonb;
  v_effect_payload_data jsonb := '{}'::jsonb;
  v_effect_code text := '';
  v_refresh jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_log_data jsonb := '{}'::jsonb;
  v_message text := '';
begin
  if v_character_ability_id is null then
    if v_character_id is null or v_ability_code = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_FOUND',
        'message', 'character_ability_id or character_id + ability_code is required.'
      );
    end if;

    select ability.id
    into v_character_ability_id
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.character_id = v_character_id
      and def.code = v_ability_code
      and ability.is_enabled = true
    order by ability.sort_order, ability.created_at, ability.id
    limit 1;
  end if;

  select
    ability.*,
    def.code as ability_code,
    def.name as ability_name,
    def.ability_kind,
    def.source_type,
    def.activation_type,
    def.target_type,
    def.effect_mode,
    def.attack_type,
    def.resource_mode,
    def.resource_pool_code,
    def.resource_item_code,
    def.description as ability_description,
    def.effect_data as def_effect_data,
    def.data as def_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = v_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', v_character_ability_id
    );
  end if;

  v_character_id := v_ability.character_id;
  v_effective_level := public.odyssey_get_character_ability_effective_level(v_character_ability_id);

  select *
  into v_level
  from public.odyssey_ability_level_defs level_data
  where level_data.ability_def_id = v_ability.ability_def_id
    and level_data.ability_level <= v_effective_level
  order by level_data.ability_level desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_LEVEL_NOT_AVAILABLE',
      'character_ability_id', v_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  v_merged_ability_data :=
    coalesce(v_ability.def_data, '{}'::jsonb)
    || coalesce(v_ability.data, '{}'::jsonb)
    || coalesce(v_level.data, '{}'::jsonb);

  v_effect_payload_data := public.odyssey_merge_effect_data(
    public.odyssey_merge_effect_data(
      coalesce(v_ability.def_effect_data, '{}'::jsonb),
      case
        when jsonb_typeof(v_ability.data->'effect_data') = 'object' then v_ability.data->'effect_data'
        else '{}'::jsonb
      end
    ),
    coalesce(v_level.effect_data, '{}'::jsonb)
  );

  v_effect_code := lower(trim(coalesce(
    nullif(v_merged_ability_data->>'effect_code', ''),
    nullif(v_effect_payload_data->>'effect_code', ''),
    ''
  )));

  if v_ability.ability_kind = 'attack' or v_ability.effect_mode = 'attack' then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_REQUIRES_ATTACK_RESOLUTION',
      'message', 'Attack abilities must be resolved through perform_attack.',
      'character_ability_id', v_character_ability_id
    );
  end if;

  if v_ability.target_type = 'self' then
    v_target_character_id := v_character_id;
  elsif v_target_character_id is null then
    v_target_character_id := v_character_id;
  end if;

  v_resource_result := public.odyssey_consume_character_ability_cost(v_character_ability_id);
  if coalesce((v_resource_result->>'ok')::boolean, false) = false then
    return v_resource_result;
  end if;

  if coalesce(v_level.cooldown_rounds, 0) > 0 then
    update public.odyssey_character_abilities
    set current_cooldown_rounds = v_level.cooldown_rounds
    where id = v_character_ability_id;
  end if;

  if v_ability.effect_mode = 'apply_effect' then
    v_effect_result := public.add_character_effect(
      jsonb_build_object(
        'character_id', v_target_character_id,
        'effect_code', v_effect_code,
        'effect_key', v_ability.ability_code,
        'name', v_ability.ability_name,
        'description', v_ability.ability_description,
        'category',
          case
            when v_ability.source_type = 'psionic' then 'psionic'
            when v_ability.source_type in ('implant', 'prosthetic', 'equipment') then 'equipment'
            else 'custom'
          end,
        'duration_type', case when v_level.duration_rounds is not null and v_level.duration_rounds > 0 then 'rounds' else 'manual' end,
        'rounds_left', v_level.duration_rounds,
        'source', v_ability.ability_name,
        'source_type', v_ability.source_type,
        'source_id', v_character_ability_id::text,
        'source_character_id', v_character_id::text,
        'data', v_effect_payload_data,
        'created_by', v_created_by
      )
    );

    if coalesce((v_effect_result->>'ok')::boolean, false) = false then
      return v_effect_result;
    end if;

    v_refresh := coalesce(v_effect_result->'combat_state', '{}'::jsonb);
  elsif v_ability.effect_mode = 'grant_special' then
    select
      b.id,
      b.character_id,
      b.part_key,
      b.max_critical,
      b.critical
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_target_character_id
      and coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) = 'special'
    limit 1
    for update of b;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'SPECIAL_BODY_PART_NOT_FOUND',
        'target_character_id', v_target_character_id
      );
    end if;

    update public.odyssey_character_body_parts
    set
      natural_armor_value = greatest(coalesce(v_level.special_armor_value, 0), 0),
      max_critical = greatest(coalesce(v_level.special_max_critical, max_critical), 0),
      critical = 0,
      serious = 0,
      minor = 0,
      disabled = false,
      destroyed = false
    where id = v_target_part.id;

    perform public.recompute_character_armor(v_target_character_id);
    v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
    v_effect_result := jsonb_build_object(
      'ok', true,
      'special', public.odyssey_get_character_body_part_state(v_target_part.id),
      'combat_state', v_refresh
    );
  else
    v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
    v_effect_result := jsonb_build_object(
      'ok', true,
      'narrative_only', true,
      'combat_state', v_refresh
    );
  end if;

  v_message := format(
    '%s uses %s.',
    coalesce(
      (
        select coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key)
        from public.odyssey_characters c
        where c.id = v_character_id
      ),
      v_character_id::text
    ),
    v_ability.ability_name
  );

  v_log_data := jsonb_build_object(
    'type', 'ability_use',
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_character_id,
    'target_character_id', v_target_character_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', v_effect_result
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
    coalesce((select c.campaign_id from public.odyssey_characters c where c.id = v_character_id), ''),
    coalesce((select c.room_id from public.odyssey_characters c where c.id = v_character_id), ''),
    v_scene_id,
    v_encounter_id,
    v_character_id,
    v_target_character_id,
    'ability_use',
    v_message,
    v_log_data,
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, coalesce((select c.room_id from public.odyssey_characters c where c.id = v_character_id), ''));

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_character_id,
    'target_character_id', v_target_character_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', v_effect_result,
    'combat_state', v_refresh,
    'log_id', v_log_id
  );
end;
$$;

create or replace function public.odyssey_finalize_attack_result(
  p_result jsonb,
  p_target_character_id uuid,
  p_target_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb := coalesce(p_result, '{}'::jsonb);
  v_body_part jsonb := '{}'::jsonb;
  v_target_state jsonb := '{}'::jsonb;
  v_pending_checks jsonb := '[]'::jsonb;
  v_auto text := null;
  v_attack_roll integer := 0;
  v_hit boolean := false;
  v_body_critical_delta integer := 0;
begin
  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  if p_target_character_id is not null then
    perform public.odyssey_recalculate_character_body_part_caps(p_target_character_id);
  end if;

  if p_target_body_part_id is not null then
    perform public.odyssey_normalize_body_part_damage(p_target_body_part_id);
    v_body_part := coalesce(public.odyssey_get_character_body_part_state(p_target_body_part_id), '{}'::jsonb);
  end if;

  if p_target_character_id is not null then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(p_target_character_id)->'combat_state', '{}'::jsonb);
  end if;

  v_attack_roll := coalesce(nullif(jsonb_extract_path_text(v_result, 'attack', 'roll'), '')::integer, 0);
  v_hit := coalesce((v_result->>'hit')::boolean, false);
  v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_critical_delta'), '')::integer, 0);

  if v_hit and v_attack_roll >= 95 then
    v_auto := 'crit';
  elsif v_attack_roll > 0 and v_attack_roll <= 5 then
    v_auto := 'fail';
  end if;

  if v_body_critical_delta > 0 then
    v_pending_checks := jsonb_build_array(
      jsonb_build_object(
        'type', 'manual_check',
        'skill_code', 'endurance',
        'reason', 'critical_damage',
        'message', 'Resolve an Endurance check manually because body critical damage was applied.'
      )
    );
  end if;

  return v_result
    || jsonb_build_object(
      'body_part', v_body_part,
      'target_state', v_target_state,
      'auto', to_jsonb(v_auto),
      'pending_checks', v_pending_checks
    );
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'perform_attack'
      and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb'
  ) and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'odyssey_perform_weapon_attack'
      and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb'
  ) then
    alter function public.perform_attack(jsonb) rename to odyssey_perform_weapon_attack;
  end if;
end;
$$;

create or replace function public.odyssey_perform_ability_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_ability_id uuid := nullif(trim(coalesce(p_payload->>'character_ability_id', '')), '')::uuid;
  v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', p_payload->>'character_id', '')), '')::uuid;
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
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
  v_created_by text := coalesce(nullif(trim(coalesce(p_payload->>'created_by', '')), ''), '');
  v_ability record;
  v_level record;
  v_attacker public.odyssey_characters%rowtype;
  v_target public.odyssey_characters%rowtype;
  v_target_part record;
  v_attacker_effective_stats jsonb := '{}'::jsonb;
  v_target_effective_stats jsonb := '{}'::jsonb;
  v_attacker_effect_summary jsonb := '{}'::jsonb;
  v_target_effect_summary jsonb := '{}'::jsonb;
  v_target_armor_summary jsonb := '{}'::jsonb;
  v_resource_result jsonb := '{}'::jsonb;
  v_target_helpless boolean := false;
  v_target_armor_class text := 'none';
  v_target_defense_modifier integer := 0;
  v_target_armor_modifier integer := 0;
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
  v_attacker_attack_accuracy_modifier integer := 0;
  v_attacker_damage_modifier integer := 0;
  v_attacker_aim_difficulty_modifier integer := 0;
  v_attacker_range_effect_modifier integer := 0;
  v_helpless_defense_penalty integer := 0;
  v_effective_aim_difficulty integer := 0;
  v_raw_armor_value integer := 0;
  v_effective_armor integer := 0;
  v_hit boolean := false;
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
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
  v_armor_damage_json jsonb := '{}'::jsonb;
  v_armor_item_updates jsonb := '[]'::jsonb;
  v_target_state jsonb := '{}'::jsonb;
  v_attacker_state jsonb := '{}'::jsonb;
  v_expired_attack_effects jsonb := '[]'::jsonb;
  v_message text := '';
  v_error_code text := null;
  v_error_message text := null;
  v_log_data jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_character_ability_id is null then
    if v_attacker_character_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_FOUND',
        'message', 'character_ability_id or attacker_character_id is required.'
      );
    end if;

    select ability.id
    into v_character_ability_id
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.character_id = v_attacker_character_id
      and def.code = lower(trim(coalesce(p_payload->>'ability_code', '')))
      and ability.is_enabled = true
      order by ability.sort_order, ability.created_at, ability.id
      limit 1;
  end if;

  if v_attacker_character_id is null and v_character_ability_id is not null then
    select ability.character_id
    into v_attacker_character_id
    from public.odyssey_character_abilities ability
    where ability.id = v_character_ability_id;
  end if;

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
    select
      ability.*,
      def.code as ability_code,
      def.name as ability_name,
      def.ability_kind,
      def.source_type,
      def.target_type,
      def.effect_mode,
      def.attack_type,
      def.linked_skill_id,
      def.resource_mode,
      def.resource_pool_code,
      def.resource_item_code,
      def.description as ability_description
    into v_ability
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.id = v_character_ability_id
      and ability.character_id = v_attacker_character_id
      and ability.is_enabled = true
    for update of ability;

    if not found then
      v_error_code := 'ABILITY_NOT_FOUND';
      v_error_message := 'Attack ability was not found for the attacker.';
    elsif v_ability.ability_kind <> 'attack' or v_ability.effect_mode <> 'attack' then
      v_error_code := 'ABILITY_NOT_ATTACK';
      v_error_message := 'Selected ability is not configured as an attack ability.';
    end if;
  end if;

  if v_error_code is null then
    v_attack_skill_level := public.odyssey_get_character_ability_effective_level(v_character_ability_id);

    select *
    into v_level
    from public.odyssey_ability_level_defs level_data
    where level_data.ability_def_id = v_ability.ability_def_id
      and level_data.ability_level <= v_attack_skill_level
    order by level_data.ability_level desc
    limit 1;

    if not found then
      v_error_code := 'ABILITY_LEVEL_NOT_AVAILABLE';
      v_error_message := 'No attack level data is available for this ability.';
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

  if v_error_code is null then
    v_attacker_effective_stats := public.get_effective_character_stats(v_attacker_character_id);
    v_target_effective_stats := public.get_effective_character_stats(v_target_character_id);
    v_attacker_effect_summary := coalesce(v_attacker_effective_stats->'effect_summary', '{}'::jsonb);
    v_target_effect_summary := coalesce(v_target_effective_stats->'effect_summary', '{}'::jsonb);
    v_target_armor_summary := public.get_character_armor_summary(v_target_character_id);

    if not v_override_ignore_action_restrictions
      and (
        coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_alive'), '')::boolean, true) = false
        or coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_conscious'), '')::boolean, true) = false
        or coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'helpless'), '')::boolean, false) = true
        or coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false) = true
      ) then
      v_error_code := 'ATTACKER_CANNOT_ACT';
      v_error_message := 'Attacker cannot act because of current effects or combat state.';
    end if;
  end if;

  if v_error_code is null then
    v_target_helpless := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'helpless'), '')::boolean, false);
    v_target_armor_class := coalesce(jsonb_extract_path_text(v_target_armor_summary, 'armor_class'), 'none');
    v_attacker_attack_accuracy_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'attack_accuracy_modifier'), '')::integer, 0);
    v_attacker_damage_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'damage_modifier'), '')::integer, 0);
    v_attacker_aim_difficulty_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'aim_difficulty_modifier'), '')::integer, 0);
    v_attacker_range_effect_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'range_modifier'), '')::integer, 0);
    v_target_defense_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'defense_modifier'), '')::integer, 0);
    v_target_armor_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'armor_modifier'), '')::integer, 0);
  end if;

  if v_error_code is null and v_ability.linked_skill_id is not null then
    select d.code
    into v_defense_skill_code
    from public.odyssey_skill_defs d
    where d.id = v_ability.linked_skill_id;

    v_attack_skill_modifier := coalesce(
      nullif(jsonb_extract_path_text(v_attacker_effect_summary, 'modifiers', 'skills', coalesce(v_defense_skill_code, '')), '')::integer,
      0
    );
  end if;

  if v_error_code is null then
    v_attack_skill_level := greatest(coalesce(v_attack_skill_level, 0) + v_attack_skill_modifier, 0);
    v_attack_skill_bonus := v_attack_skill_level * 10;
    if v_level.range_profile_id is not null then
      v_range_json := public.odyssey_get_range_profile_modifier(v_level.range_profile_id, v_distance_m);
      v_range_band := nullif(coalesce(v_range_json->>'range_band', ''), '');
      v_range_modifier := coalesce((v_range_json->>'modifier')::integer, 0) + v_attacker_range_effect_modifier;
    else
      v_range_band := null;
      v_range_modifier := v_attacker_range_effect_modifier;
    end if;
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
    elsif v_ability.attack_type = 'melee' then
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
    end if;
  end if;

  if v_error_code is null then
    v_resource_result := public.odyssey_consume_character_ability_cost(v_character_ability_id);
    if coalesce((v_resource_result->>'ok')::boolean, false) = false then
      v_error_code := coalesce(v_resource_result->>'error', 'ABILITY_RESOURCE_ERROR');
      v_error_message := coalesce(v_resource_result->>'message', v_resource_result->>'error', 'Unable to spend ability resource.');
    elsif coalesce(v_level.cooldown_rounds, 0) > 0 then
      update public.odyssey_character_abilities
      set current_cooldown_rounds = v_level.cooldown_rounds
      where id = v_character_ability_id;
    end if;
  end if;

  if v_error_code is null then
    v_raw_armor_value := greatest(coalesce(v_target_part.armor_value, 0) + v_target_armor_modifier, 0);
    if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    end if;

    v_attack_roll := floor(random() * 100)::integer + 1;
    if v_target_helpless and v_target_armor_class in ('none', 'light') then
      v_defense_roll := 1;
    else
      v_defense_roll := floor(random() * 100)::integer + 1;
      if v_target_helpless and v_target_armor_class in ('medium', 'heavy', 'superheavy') then
        v_helpless_defense_penalty := -60;
      end if;
    end if;

    v_effective_aim_difficulty := greatest(coalesce(v_target_part.aim_difficulty, 0) - v_attacker_aim_difficulty_modifier, 0);

    v_attack_total :=
      v_attack_roll
      + v_attack_skill_bonus
      + coalesce(v_level.attack_accuracy_bonus, 0)
      + v_attacker_attack_accuracy_modifier
      + coalesce(v_range_modifier, 0)
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

    v_hit := v_attack_total > v_defense_total;
  end if;

  v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);

  if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_attacker_damage_modifier;
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

    if v_critical_delta > 0 then
      v_armor_damage_json := public.odyssey_apply_equipment_critical_damage(v_target_part.id, v_critical_delta);
      v_armor_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'absorbed'), '')::integer, 0);
      v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_armor_damage_json, 'remaining'), '')::integer, v_critical_delta - v_armor_critical_delta);
      v_armor_item_updates := coalesce(v_armor_damage_json->'updated_items', '[]'::jsonb);

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0 or v_serious_delta > 0 or v_body_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;
    end if;
  elsif v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total;
    v_damage_defense_total := v_defense_total;
    v_damage_diff := 0;
    v_damage_level := 'no_damage';
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
      'character_ability_id', v_character_ability_id,
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
      coalesce(v_created_by, v_actor_token_id, '')
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

  v_target_state := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);

  if not v_hit then
    v_message := format(
      '%s attacks %s with %s and misses.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_ability.ability_name
    );
  elsif v_damage_level = 'no_damage' then
    v_message := format(
      '%s hits %s in %s with %s but deals no damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      v_ability.ability_name
    );
  else
    v_message := format(
      '%s hits %s in %s with %s for %s damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      v_ability.ability_name,
      v_damage_level
    );
  end if;

  v_log_data := jsonb_build_object(
    'type', 'attack',
    'ok', true,
    'hit', v_hit,
    'attack_type', v_ability.attack_type,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'character_ability_id', v_character_ability_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'level', v_attack_skill_level,
        'source_type', v_ability.source_type
      ),
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
    'damage_level', v_damage_level,
    'damage_diff', v_damage_diff,
    'minor_delta', v_minor_delta,
    'serious_delta', v_serious_delta,
    'critical_delta', v_critical_delta,
    'armor_critical_delta', v_armor_critical_delta,
    'resource', v_resource_result,
    'expired_attack_effects', v_expired_attack_effects
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
    coalesce(v_created_by, v_actor_token_id, '')
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

  v_result := jsonb_build_object(
    'ok', true,
    'hit', v_hit,
    'attack_type', v_ability.attack_type,
    'ability',
      jsonb_build_object(
        'character_ability_id', v_character_ability_id,
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'level', v_attack_skill_level,
        'source_type', v_ability.source_type,
        'resource_mode', v_ability.resource_mode
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
        'body_critical_delta', v_body_critical_delta
      ),
    'body_part', public.odyssey_get_character_body_part_state(v_target_part.id),
    'resource', v_resource_result,
    'target_state', v_target_state,
    'attacker_state', v_attacker_state,
    'expired_attack_effects', v_expired_attack_effects,
    'log_id', v_log_id
  );

  return public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_ability_id uuid := nullif(trim(coalesce(p_payload->>'character_ability_id', '')), '')::uuid;
  v_ability_code text := lower(trim(coalesce(p_payload->>'ability_code', '')));
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_result jsonb := '{}'::jsonb;
begin
  if v_character_ability_id is not null or v_ability_code <> '' then
    return public.odyssey_perform_ability_attack(p_payload);
  end if;

  v_result := public.odyssey_perform_weapon_attack(p_payload);

  if coalesce((v_result->>'ok')::boolean, false) = true then
    return public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
  end if;

  return v_result;
end;
$$;

grant execute on function public.odyssey_get_character_body_part_state(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_ability_effective_level(uuid) to anon, authenticated;
grant execute on function public.odyssey_recalculate_character_body_part_caps(uuid) to anon, authenticated;
grant execute on function public.odyssey_normalize_body_part_damage(uuid) to anon, authenticated;
grant execute on function public.odyssey_sync_character_resource_pools(uuid) to anon, authenticated;
grant execute on function public.get_character_abilities(uuid) to anon, authenticated;
grant execute on function public.odyssey_consume_character_ability_cost(uuid) to anon, authenticated;
grant execute on function public.advance_character_ability_states(uuid) to anon, authenticated;
grant execute on function public.use_ability(jsonb) to anon, authenticated;
grant execute on function public.odyssey_finalize_attack_result(jsonb, uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_perform_weapon_attack(jsonb) to anon, authenticated;
grant execute on function public.odyssey_perform_ability_attack(jsonb) to anon, authenticated;
grant execute on function public.perform_attack(jsonb) to anon, authenticated;
