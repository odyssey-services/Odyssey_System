create extension if not exists pgcrypto;

create table if not exists public.odyssey_item_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  item_type text not null check (item_type in ('resource', 'consumable', 'medical', 'tool', 'quest', 'custom')),
  description text not null default '',
  is_stackable boolean not null default true,
  default_quantity integer not null default 1 check (default_quantity >= 0),
  max_stack integer null check (max_stack is null or max_stack >= 1),
  default_max_charges integer null check (default_max_charges is null or default_max_charges >= 0),
  default_current_charges integer null check (default_current_charges is null or default_current_charges >= 0),
  use_action_type text not null default 'none' check (use_action_type in ('none', 'consume', 'heal', 'reload_feature_resource', 'custom')),
  effect_data jsonb not null default '{}'::jsonb check (jsonb_typeof(effect_data) = 'object'),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_items (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  item_def_id uuid not null references public.odyssey_item_defs(id) on delete cascade,
  custom_name text null,
  quantity integer not null default 1 check (quantity >= 0),
  current_charges integer null check (current_charges is null or current_charges >= 0),
  max_charges integer null check (max_charges is null or max_charges >= 0),
  location_data jsonb not null default '{}'::jsonb check (jsonb_typeof(location_data) = 'object'),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_ammo_stock (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  display_name text not null,
  caliber_id uuid not null references public.odyssey_caliber_defs(id) on delete restrict,
  ammo_type_id uuid not null references public.odyssey_ammo_type_defs(id) on delete restrict,
  quantity integer not null default 0 check (quantity >= 0),
  location_data jsonb not null default '{}'::jsonb check (jsonb_typeof(location_data) = 'object'),
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  notes text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (character_id, caliber_id, ammo_type_id, display_name)
);

create index if not exists odyssey_item_defs_type_idx
  on public.odyssey_item_defs (item_type, sort_order, code);

create index if not exists odyssey_character_items_character_idx
  on public.odyssey_character_items (character_id, item_def_id, sort_order, created_at);

create index if not exists odyssey_character_ammo_stock_character_idx
  on public.odyssey_character_ammo_stock (character_id, caliber_id, ammo_type_id, created_at);

alter table public.odyssey_item_defs enable row level security;
alter table public.odyssey_character_items enable row level security;
alter table public.odyssey_character_ammo_stock enable row level security;

drop policy if exists "odyssey_item_defs_full_access" on public.odyssey_item_defs;
create policy "odyssey_item_defs_full_access"
on public.odyssey_item_defs
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_items_full_access" on public.odyssey_character_items;
create policy "odyssey_character_items_full_access"
on public.odyssey_character_items
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_ammo_stock_full_access" on public.odyssey_character_ammo_stock;
create policy "odyssey_character_ammo_stock_full_access"
on public.odyssey_character_ammo_stock
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_item_defs to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_items to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_ammo_stock to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_item_defs on public.odyssey_item_defs;
create trigger odyssey_touch_updated_at_item_defs
before update on public.odyssey_item_defs
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_items on public.odyssey_character_items;
create trigger odyssey_touch_updated_at_character_items
before update on public.odyssey_character_items
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_touch_updated_at_character_ammo_stock on public.odyssey_character_ammo_stock;
create trigger odyssey_touch_updated_at_character_ammo_stock
before update on public.odyssey_character_ammo_stock
for each row
execute function public.odyssey_touch_updated_at();

create or replace function public.odyssey_get_character_item_row(
  p_item_id uuid
)
returns jsonb
language sql
stable
as $$
  select
    case
      when item_row.id is null then null
      else jsonb_build_object(
        'id', item_row.id,
        'character_id', item_row.character_id,
        'item_def_id', item_row.item_def_id,
        'code', item_row.code,
        'name', coalesce(nullif(trim(item_row.custom_name), ''), item_row.name),
        'custom_name', item_row.custom_name,
        'item_type', item_row.item_type,
        'description', item_row.description,
        'is_stackable', item_row.is_stackable,
        'quantity', item_row.quantity,
        'current_charges', item_row.current_charges,
        'max_charges', item_row.max_charges,
        'use_action_type', item_row.use_action_type,
        'effect_data', item_row.effect_data,
        'location_data', item_row.location_data,
        'data', item_row.data,
        'notes', item_row.notes,
        'sort_order', item_row.sort_order,
        'tags', item_row.tags,
        'created_at', item_row.created_at,
        'updated_at', item_row.updated_at
      )
    end
  from (
    select
      i.id,
      i.character_id,
      i.item_def_id,
      i.custom_name,
      i.quantity,
      i.current_charges,
      i.max_charges,
      i.location_data,
      i.data,
      i.notes,
      i.sort_order,
      i.created_at,
      i.updated_at,
      d.code,
      d.name,
      d.item_type,
      d.description,
      d.is_stackable,
      d.use_action_type,
      d.effect_data,
      d.tags
    from public.odyssey_character_items i
    join public.odyssey_item_defs d on d.id = i.item_def_id
    where i.id = p_item_id
  ) item_row;
$$;

create or replace function public.odyssey_get_character_ammo_stock_row(
  p_ammo_stock_id uuid
)
returns jsonb
language sql
stable
as $$
  select
    case
      when stock_row.id is null then null
      else jsonb_build_object(
        'id', stock_row.id,
        'character_id', stock_row.character_id,
        'display_name', stock_row.display_name,
        'caliber_id', stock_row.caliber_id,
        'caliber_code', stock_row.caliber_code,
        'caliber_name', stock_row.caliber_name,
        'ammo_type_id', stock_row.ammo_type_id,
        'ammo_type_code', stock_row.ammo_type_code,
        'ammo_type_name', stock_row.ammo_type_name,
        'quantity', stock_row.quantity,
        'location_data', stock_row.location_data,
        'data', stock_row.data,
        'notes', stock_row.notes,
        'created_at', stock_row.created_at,
        'updated_at', stock_row.updated_at
      )
    end
  from (
    select
      s.id,
      s.character_id,
      s.display_name,
      s.caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      s.ammo_type_id,
      ammo.code as ammo_type_code,
      ammo.name as ammo_type_name,
      s.quantity,
      s.location_data,
      s.data,
      s.notes,
      s.created_at,
      s.updated_at
    from public.odyssey_character_ammo_stock s
    join public.odyssey_caliber_defs caliber on caliber.id = s.caliber_id
    join public.odyssey_ammo_type_defs ammo on ammo.id = s.ammo_type_id
    where s.id = p_ammo_stock_id
  ) stock_row;
$$;

create or replace function public.odyssey_get_character_magazine_summary(
  p_character_magazine_id uuid
)
returns jsonb
language sql
stable
as $$
  select
    case
      when cm.id is null then null
      else jsonb_build_object(
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
    end
  from public.odyssey_character_magazines cm
  join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  join public.odyssey_caliber_defs ammo_caliber on ammo_caliber.id = ammo.caliber_id
  where cm.id = p_character_magazine_id;
$$;

create or replace function public.odyssey_find_character_ammo_stock_identity(
  p_character_id uuid,
  p_caliber_id uuid,
  p_ammo_type_id uuid
)
returns uuid
language sql
stable
as $$
  select s.id
  from public.odyssey_character_ammo_stock s
  where s.character_id = p_character_id
    and s.caliber_id = p_caliber_id
    and s.ammo_type_id = p_ammo_type_id
  order by s.created_at, s.id
  limit 1;
$$;

create or replace function public.odyssey_is_magazine_loaded_in_weapon(
  p_magazine_id uuid
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.odyssey_character_weapon_profile_states ps
    where ps.loaded_magazine_id = p_magazine_id
    union all
    select 1
    from public.odyssey_character_weapons w
    where w.loaded_magazine_id = p_magazine_id
  );
$$;

create or replace function public.get_character_item_quantity(
  p_character_id uuid,
  p_item_code text
)
returns integer
language sql
stable
as $$
  select coalesce(sum(i.quantity), 0)::integer
  from public.odyssey_character_items i
  join public.odyssey_item_defs d on d.id = i.item_def_id
  where i.character_id = p_character_id
    and d.code = lower(trim(coalesce(p_item_code, '')));
$$;

create or replace function public.add_character_item(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_item_code text := lower(trim(coalesce(p_payload->>'item_code', '')));
  v_quantity integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, 0), 0);
  v_custom_name text := nullif(trim(coalesce(p_payload->>'custom_name', '')), '');
  v_location_data jsonb := case
    when jsonb_typeof(p_payload->'location_data') = 'object' then p_payload->'location_data'
    else '{}'::jsonb
  end;
  v_data jsonb := case
    when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    else '{}'::jsonb
  end;
  v_notes text := coalesce(p_payload->>'notes', '');
  v_sort_order integer := nullif(trim(coalesce(p_payload->>'sort_order', '')), '')::integer;
  v_item_def public.odyssey_item_defs%rowtype;
  v_item_id uuid := null;
  v_next_sort_order integer := 0;
  v_total_quantity integer := 0;
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
  into v_item_def
  from public.odyssey_item_defs d
  where d.code = v_item_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_DEF_NOT_FOUND',
      'item_code', v_item_code
    );
  end if;

  v_quantity := coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, v_item_def.default_quantity, 1);
  if v_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_QUANTITY',
      'quantity', v_quantity
    );
  end if;

  if v_sort_order is null then
    select coalesce(max(i.sort_order), 0) + 10
    into v_next_sort_order
    from public.odyssey_character_items i
    where i.character_id = v_character_id;
  else
    v_next_sort_order := v_sort_order;
  end if;

  if coalesce(v_item_def.is_stackable, false) then
    select i.id
    into v_item_id
    from public.odyssey_character_items i
    where i.character_id = v_character_id
      and i.item_def_id = v_item_def.id
      and i.custom_name is not distinct from v_custom_name
      and i.location_data = v_location_data
      and i.current_charges is not distinct from coalesce(nullif(trim(coalesce(p_payload->>'current_charges', '')), '')::integer, v_item_def.default_current_charges)
      and i.max_charges is not distinct from coalesce(nullif(trim(coalesce(p_payload->>'max_charges', '')), '')::integer, v_item_def.default_max_charges)
    order by i.sort_order, i.created_at, i.id
    limit 1
    for update;
  end if;

  if v_item_id is not null then
    update public.odyssey_character_items
    set
      quantity = quantity + v_quantity,
      notes = case when nullif(trim(v_notes), '') is not null then v_notes else notes end,
      data = data || v_data
    where id = v_item_id;
  else
    insert into public.odyssey_character_items (
      character_id,
      item_def_id,
      custom_name,
      quantity,
      current_charges,
      max_charges,
      location_data,
      data,
      notes,
      sort_order
    )
    values (
      v_character_id,
      v_item_def.id,
      v_custom_name,
      v_quantity,
      coalesce(nullif(trim(coalesce(p_payload->>'current_charges', '')), '')::integer, v_item_def.default_current_charges),
      coalesce(nullif(trim(coalesce(p_payload->>'max_charges', '')), '')::integer, v_item_def.default_max_charges),
      v_location_data,
      v_data,
      v_notes,
      v_next_sort_order
    )
    returning id into v_item_id;
  end if;

  v_total_quantity := public.get_character_item_quantity(v_character_id, v_item_code);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'item', public.odyssey_get_character_item_row(v_item_id),
    'total_quantity', v_total_quantity
  );
end;
$$;

create or replace function public.remove_character_item_quantity(
  p_character_id uuid,
  p_item_code text,
  p_quantity integer
)
returns jsonb
language plpgsql
as $$
declare
  v_item_code text := lower(trim(coalesce(p_item_code, '')));
  v_total_quantity integer := 0;
  v_remaining_to_remove integer := greatest(coalesce(p_quantity, 0), 0);
  v_current_quantity integer := 0;
  v_removed_stacks jsonb := '[]'::jsonb;
  v_take integer := 0;
  v_item record;
begin
  if p_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'character_id is required.'
    );
  end if;

  if v_item_code = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_DEF_NOT_FOUND',
      'message', 'item_code is required.'
    );
  end if;

  if v_remaining_to_remove <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_QUANTITY',
      'quantity', p_quantity
    );
  end if;

  v_total_quantity := public.get_character_item_quantity(p_character_id, v_item_code);

  if v_total_quantity < v_remaining_to_remove then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_ITEMS',
      'character_id', p_character_id,
      'item_code', v_item_code,
      'requested_quantity', v_remaining_to_remove,
      'available_quantity', v_total_quantity
    );
  end if;

  for v_item in
    select
      i.id,
      i.quantity
    from public.odyssey_character_items i
    join public.odyssey_item_defs d on d.id = i.item_def_id
    where i.character_id = p_character_id
      and d.code = v_item_code
      and i.quantity > 0
    order by i.sort_order, i.created_at, i.id
    for update of i
  loop
    exit when v_remaining_to_remove <= 0;

    v_take := least(v_remaining_to_remove, coalesce(v_item.quantity, 0));

    if v_take >= coalesce(v_item.quantity, 0) then
      delete from public.odyssey_character_items
      where id = v_item.id;
    else
      update public.odyssey_character_items
      set quantity = quantity - v_take
      where id = v_item.id;
    end if;

    v_removed_stacks := v_removed_stacks || jsonb_build_array(
      jsonb_build_object(
        'item_id', v_item.id,
        'removed_quantity', v_take
      )
    );
    v_remaining_to_remove := v_remaining_to_remove - v_take;
  end loop;

  v_current_quantity := public.get_character_item_quantity(p_character_id, v_item_code);

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'item_code', v_item_code,
    'removed_quantity', p_quantity,
    'remaining_quantity', v_current_quantity,
    'removed_stacks', v_removed_stacks
  );
end;
$$;

create or replace function public.add_character_ammo_stock(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_display_name_input text := nullif(trim(coalesce(p_payload->>'display_name', '')), '');
  v_caliber_code text := lower(trim(coalesce(p_payload->>'caliber_code', '')));
  v_ammo_type_code text := lower(trim(coalesce(p_payload->>'ammo_type_code', '')));
  v_quantity integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'quantity', '')), '')::integer, 0), 0);
  v_location_data jsonb := case
    when jsonb_typeof(p_payload->'location_data') = 'object' then p_payload->'location_data'
    else '{}'::jsonb
  end;
  v_data jsonb := case
    when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
    else '{}'::jsonb
  end;
  v_notes text := coalesce(p_payload->>'notes', '');
  v_caliber public.odyssey_caliber_defs%rowtype;
  v_ammo_type public.odyssey_ammo_type_defs%rowtype;
  v_existing_stock public.odyssey_character_ammo_stock%rowtype;
  v_stock_id uuid := null;
  v_effective_display_name text := null;
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

  if v_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_QUANTITY',
      'quantity', v_quantity
    );
  end if;

  select *
  into v_caliber
  from public.odyssey_caliber_defs c
  where c.code = v_caliber_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_NOT_FOUND',
      'caliber_code', v_caliber_code
    );
  end if;

  select *
  into v_ammo_type
  from public.odyssey_ammo_type_defs a
  where a.code = v_ammo_type_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_TYPE_NOT_FOUND',
      'ammo_type_code', v_ammo_type_code
    );
  end if;

  if v_ammo_type.caliber_id <> v_caliber.id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'caliber_code', v_caliber_code,
      'ammo_type_code', v_ammo_type_code
    );
  end if;

  v_effective_display_name := coalesce(v_display_name_input, v_ammo_type.name);

  select *
  into v_existing_stock
  from public.odyssey_character_ammo_stock s
  where s.character_id = v_character_id
    and s.caliber_id = v_caliber.id
    and s.ammo_type_id = v_ammo_type.id
  order by s.created_at, s.id
  limit 1
  for update;

  if found then
    update public.odyssey_character_ammo_stock
    set
      display_name = case
        when v_display_name_input is not null then v_display_name_input
        else display_name
      end,
      quantity = quantity + v_quantity,
      location_data = case
        when v_location_data <> '{}'::jsonb then v_location_data
        else location_data
      end,
      data = data || v_data,
      notes = case
        when nullif(trim(v_notes), '') is not null then v_notes
        else notes
      end
    where id = v_existing_stock.id;

    v_stock_id := v_existing_stock.id;
  else
    insert into public.odyssey_character_ammo_stock (
      character_id,
      display_name,
      caliber_id,
      ammo_type_id,
      quantity,
      location_data,
      data,
      notes
    )
    values (
      v_character_id,
      v_effective_display_name,
      v_caliber.id,
      v_ammo_type.id,
      v_quantity,
      v_location_data,
      v_data,
      v_notes
    )
    returning id into v_stock_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'ammo_stock', public.odyssey_get_character_ammo_stock_row(v_stock_id)
  );
end;
$$;

create or replace function public.remove_character_ammo_stock(
  p_ammo_stock_id uuid,
  p_quantity integer
)
returns jsonb
language plpgsql
as $$
declare
  v_stock public.odyssey_character_ammo_stock%rowtype;
  v_remaining_quantity integer := 0;
begin
  if p_ammo_stock_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_STOCK_NOT_FOUND',
      'message', 'ammo_stock_id is required.'
    );
  end if;

  if coalesce(p_quantity, 0) <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_QUANTITY',
      'quantity', p_quantity
    );
  end if;

  select *
  into v_stock
  from public.odyssey_character_ammo_stock s
  where s.id = p_ammo_stock_id;
  if found then
    perform 1
    from public.odyssey_character_ammo_stock s
    where s.id = p_ammo_stock_id
    for update;
  end if;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_STOCK_NOT_FOUND',
      'ammo_stock_id', p_ammo_stock_id
    );
  end if;

  if coalesce(v_stock.quantity, 0) < p_quantity then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'ammo_stock_id', p_ammo_stock_id,
      'requested_quantity', p_quantity,
      'available_quantity', coalesce(v_stock.quantity, 0)
    );
  end if;

  v_remaining_quantity := coalesce(v_stock.quantity, 0) - p_quantity;

  if v_remaining_quantity <= 0 then
    delete from public.odyssey_character_ammo_stock
    where id = p_ammo_stock_id;
  else
    update public.odyssey_character_ammo_stock
    set quantity = v_remaining_quantity
    where id = p_ammo_stock_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'ammo_stock_id', p_ammo_stock_id,
    'removed_quantity', p_quantity,
    'remaining_quantity', greatest(v_remaining_quantity, 0),
    'stock', case when v_remaining_quantity > 0 then public.odyssey_get_character_ammo_stock_row(p_ammo_stock_id) else null end
  );
end;
$$;

create or replace function public.load_rounds_to_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_quantity_text text := nullif(trim(coalesce(p_payload->>'quantity', '')), '');
  v_allow_partial_text text := nullif(trim(coalesce(p_payload->>'allow_partial', '')), '');
  v_result jsonb := '{}'::jsonb;
  v_magazine_id uuid := null;
  v_stock_id uuid := null;
begin
  if v_quantity_text is not null then
    begin
      if v_quantity_text::integer <> 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Manual quantity loading is not supported. Use load_magazine_full(jsonb).'
        );
      end if;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'quantity must be a valid integer when provided.'
        );
    end;
  end if;

  if v_allow_partial_text is not null then
    begin
      if v_allow_partial_text::boolean then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Partial loading is not supported. Use load_magazine_full(jsonb).'
        );
      end if;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'allow_partial must be a valid boolean when provided.'
        );
    end;
  end if;

  v_result := public.load_magazine_full(
    jsonb_build_object(
      'magazine_id', coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id'),
      'ammo_stock_id', p_payload->>'ammo_stock_id'
    )
  );

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  begin
    v_magazine_id := nullif(v_result #>> '{magazine,id}', '')::uuid;
    v_stock_id := nullif(v_result #>> '{ammo_stock,id}', '')::uuid;
  exception
    when others then
      return v_result;
  end;

  return jsonb_build_object(
    'ok', true,
    'character_id', nullif(v_result->>'character_id', '')::uuid,
    'character_magazine_id', v_magazine_id,
    'ammo_stock_id', v_stock_id,
    'loaded_quantity', coalesce((v_result->>'loaded_rounds')::integer, 0),
    'magazine', public.odyssey_get_character_magazine_summary(v_magazine_id),
    'ammo_stock', case
      when coalesce((v_result #>> '{ammo_stock,quantity_after}')::integer, 0) > 0 then public.odyssey_get_character_ammo_stock_row(v_stock_id)
      else null
    end
  );
end;
$$;

create or replace function public.load_magazine_full(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload_magazine_id text := nullif(trim(coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id', '')), '');
  v_payload_ammo_stock_id text := nullif(trim(coalesce(p_payload->>'ammo_stock_id', '')), '');
  v_magazine_id uuid := null;
  v_ammo_stock_id uuid := null;
  v_magazine record;
  v_stock record;
  v_rounds_before integer := 0;
  v_rounds_after integer := 0;
  v_missing_rounds integer := 0;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
begin
  if coalesce(jsonb_typeof(p_payload), 'null') <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  begin
    if v_payload_magazine_id is not null then
      v_magazine_id := v_payload_magazine_id::uuid;
    end if;
    if v_payload_ammo_stock_id is not null then
      v_ammo_stock_id := v_payload_ammo_stock_id::uuid;
    end if;
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'magazine_id and ammo_stock_id must be valid UUID values.'
      );
  end;

  if v_magazine_id is null or v_ammo_stock_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'magazine_id and ammo_stock_id are required.'
    );
  end if;

  select
    cm.id,
    cm.character_id,
    cm.custom_name,
    cm.magazine_def_id,
    cm.ammo_type_id,
    cm.current_rounds,
    md.capacity,
    md.caliber_id as magazine_caliber_id,
    caliber.code as caliber_code,
    ammo.code as ammo_type_code
  into v_magazine
  from public.odyssey_character_magazines cm
  left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  left join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  where cm.id = v_magazine_id
  for update of cm;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_NOT_FOUND',
      'magazine_id', v_magazine_id
    );
  end if;

  select
    s.id,
    s.character_id,
    s.display_name,
    s.caliber_id,
    s.ammo_type_id,
    s.quantity,
    ammo.id as ammo_type_exists_id,
    ammo.code as ammo_type_code,
    ammo.caliber_id as ammo_caliber_id
  into v_stock
  from public.odyssey_character_ammo_stock s
  left join public.odyssey_ammo_type_defs ammo on ammo.id = s.ammo_type_id
  where s.id = v_ammo_stock_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'AMMO_STOCK_NOT_FOUND',
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  if public.odyssey_is_magazine_loaded_in_weapon(v_magazine_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_IS_LOADED_IN_WEAPON',
      'message', 'Magazine is currently loaded into a weapon. Remove it or reload the weapon first.'
    );
  end if;

  if v_magazine.character_id <> v_stock.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_MISMATCH',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  if v_magazine.magazine_def_id is null or v_magazine.capacity is null or v_magazine.magazine_caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_MAGAZINE_DEF',
      'magazine_id', v_magazine_id
    );
  end if;

  if v_stock.ammo_type_id is null or v_stock.ammo_type_exists_id is null or v_stock.ammo_caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_AMMO_TYPE',
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  if v_stock.caliber_id <> v_stock.ammo_caliber_id or v_magazine.magazine_caliber_id <> v_stock.caliber_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'CALIBER_MISMATCH',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  v_rounds_before := greatest(coalesce(v_magazine.current_rounds, 0), 0);

  if v_rounds_before > 0 and v_magazine.ammo_type_id <> v_stock.ammo_type_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_HAS_DIFFERENT_AMMO_TYPE',
      'magazine_id', v_magazine_id,
      'ammo_stock_id', v_ammo_stock_id
    );
  end if;

  v_rounds_after := greatest(coalesce(v_magazine.capacity, 0), 0);
  v_missing_rounds := greatest(v_rounds_after - v_rounds_before, 0);

  if v_missing_rounds <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_FULL',
      'magazine_id', v_magazine_id
    );
  end if;

  if coalesce(v_stock.quantity, 0) < v_missing_rounds then
    return jsonb_build_object(
      'ok', false,
      'error', 'NOT_ENOUGH_AMMO_STOCK',
      'requested_quantity', v_missing_rounds,
      'available_quantity', coalesce(v_stock.quantity, 0)
    );
  end if;

  v_stock_quantity_before := coalesce(v_stock.quantity, 0);
  v_stock_quantity_after := greatest(v_stock_quantity_before - v_missing_rounds, 0);

  if v_stock_quantity_after <= 0 then
    delete from public.odyssey_character_ammo_stock
    where id = v_stock.id;
  else
    update public.odyssey_character_ammo_stock
    set quantity = v_stock_quantity_after
    where id = v_stock.id;
  end if;

  update public.odyssey_character_magazines
  set
    current_rounds = v_rounds_after,
    ammo_type_id = case
      when v_rounds_before <= 0 then v_stock.ammo_type_id
      else ammo_type_id
    end
  where id = v_magazine_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'load_magazine_full',
    'character_id', v_magazine.character_id,
    'loaded_rounds', v_missing_rounds,
    'magazine',
      jsonb_build_object(
        'id', v_magazine.id,
        'custom_name', v_magazine.custom_name,
        'current_rounds_before', v_rounds_before,
        'current_rounds_after', v_rounds_after,
        'capacity', v_magazine.capacity,
        'caliber_code', v_magazine.caliber_code,
        'ammo_type_code', v_stock.ammo_type_code
      ),
    'ammo_stock',
      jsonb_build_object(
        'id', v_stock.id,
        'quantity_before', v_stock_quantity_before,
        'quantity_after', v_stock_quantity_after
      )
  );
end;
$$;

create or replace function public.unload_rounds_from_magazine(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_quantity_text text := nullif(trim(coalesce(p_payload->>'quantity', '')), '');
  v_result jsonb := '{}'::jsonb;
  v_magazine_id uuid := null;
  v_stock_id uuid := null;
begin
  if v_quantity_text is not null then
    begin
      if v_quantity_text::integer <> 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'Manual quantity unloading is not supported. Use unload_magazine_all(jsonb).'
        );
      end if;
    exception
      when others then
        return jsonb_build_object(
          'ok', false,
          'error', 'INVALID_PAYLOAD',
          'message', 'quantity must be a valid integer when provided.'
        );
    end;
  end if;

  v_result := public.unload_magazine_all(
    jsonb_build_object(
      'magazine_id', coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id')
    )
  );

  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  begin
    v_magazine_id := nullif(v_result #>> '{magazine,id}', '')::uuid;
    v_stock_id := nullif(v_result #>> '{ammo_stock,id}', '')::uuid;
  exception
    when others then
      return v_result;
  end;

  return jsonb_build_object(
    'ok', true,
    'character_id', nullif(v_result->>'character_id', '')::uuid,
    'character_magazine_id', v_magazine_id,
    'unloaded_quantity', coalesce((v_result->>'unloaded_rounds')::integer, 0),
    'magazine', public.odyssey_get_character_magazine_summary(v_magazine_id),
    'ammo_stock', public.odyssey_get_character_ammo_stock_row(v_stock_id)
  );
end;
$$;

create or replace function public.unload_magazine_all(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload_magazine_id text := nullif(trim(coalesce(p_payload->>'magazine_id', p_payload->>'character_magazine_id', '')), '');
  v_magazine_id uuid := null;
  v_magazine record;
  v_stock record;
  v_rounds_before integer := 0;
  v_stock_quantity_before integer := 0;
  v_stock_quantity_after integer := 0;
  v_stock_id uuid := null;
begin
  if coalesce(jsonb_typeof(p_payload), 'null') <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  begin
    if v_payload_magazine_id is not null then
      v_magazine_id := v_payload_magazine_id::uuid;
    end if;
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'magazine_id must be a valid UUID value.'
      );
  end;

  if v_magazine_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'magazine_id is required.'
    );
  end if;

  select
    cm.id,
    cm.character_id,
    cm.custom_name,
    cm.magazine_def_id,
    cm.ammo_type_id,
    cm.current_rounds,
    md.capacity,
    md.caliber_id,
    caliber.code as caliber_code,
    ammo.code as ammo_type_code,
    ammo.name as ammo_type_name
  into v_magazine
  from public.odyssey_character_magazines cm
  left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  left join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  where cm.id = v_magazine_id
  for update of cm;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_NOT_FOUND',
      'magazine_id', v_magazine_id
    );
  end if;

  if public.odyssey_is_magazine_loaded_in_weapon(v_magazine_id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_IS_LOADED_IN_WEAPON',
      'message', 'Magazine is currently loaded into a weapon. Remove it or reload the weapon first.'
    );
  end if;

  if v_magazine.magazine_def_id is null or v_magazine.capacity is null or v_magazine.caliber_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_MAGAZINE_DEF',
      'magazine_id', v_magazine_id
    );
  end if;

  v_rounds_before := greatest(coalesce(v_magazine.current_rounds, 0), 0);

  if v_rounds_before <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'MAGAZINE_EMPTY',
      'magazine_id', v_magazine_id
    );
  end if;

  if v_magazine.ammo_type_id is null or v_magazine.ammo_type_code is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_AMMO_TYPE',
      'magazine_id', v_magazine_id
    );
  end if;

  select *
  into v_stock
  from public.odyssey_character_ammo_stock s
  where s.character_id = v_magazine.character_id
    and s.caliber_id = v_magazine.caliber_id
    and s.ammo_type_id = v_magazine.ammo_type_id
  order by s.created_at, s.id
  limit 1
  for update;

  if found then
    v_stock_id := v_stock.id;
    v_stock_quantity_before := coalesce(v_stock.quantity, 0);
    v_stock_quantity_after := v_stock_quantity_before + v_rounds_before;

    update public.odyssey_character_ammo_stock
    set quantity = v_stock_quantity_after
    where id = v_stock_id;
  else
    insert into public.odyssey_character_ammo_stock (
      character_id,
      display_name,
      caliber_id,
      ammo_type_id,
      quantity
    )
    values (
      v_magazine.character_id,
      coalesce(v_magazine.ammo_type_name, v_magazine.ammo_type_code),
      v_magazine.caliber_id,
      v_magazine.ammo_type_id,
      v_rounds_before
    )
    returning id into v_stock_id;

    v_stock_quantity_before := 0;
    v_stock_quantity_after := v_rounds_before;
  end if;

  update public.odyssey_character_magazines
  set current_rounds = 0
  where id = v_magazine_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'unload_magazine_all',
    'character_id', v_magazine.character_id,
    'unloaded_rounds', v_rounds_before,
    'magazine',
      jsonb_build_object(
        'id', v_magazine.id,
        'custom_name', v_magazine.custom_name,
        'current_rounds_before', v_rounds_before,
        'current_rounds_after', 0,
        'capacity', v_magazine.capacity,
        'caliber_code', v_magazine.caliber_code,
        'ammo_type_code', v_magazine.ammo_type_code
      ),
    'ammo_stock',
      jsonb_build_object(
        'id', v_stock_id,
        'quantity_before', v_stock_quantity_before,
        'quantity_after', v_stock_quantity_after
      )
  );
end;
$$;

create or replace function public.reload_feature_resource(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_state_id uuid := nullif(trim(coalesce(p_payload->>'state_id', '')), '')::uuid;
  v_force boolean := coalesce(nullif(trim(coalesce(p_payload->>'force', '')), '')::boolean, false);
  v_state record;
  v_consumed_item jsonb := null;
  v_item_result jsonb := '{}'::jsonb;
begin
  if v_state_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_STATE_NOT_FOUND',
      'message', 'state_id is required.'
    );
  end if;

  select
    s.id,
    s.character_weapon_id,
    s.current_charges,
    s.max_charges,
    s.requires_reload,
    s.recharge_rounds_left,
    s.cooldown_rounds_left,
    s.active_rounds_left,
    s.active_uses_left,
    s.is_active,
    w.character_id,
    def.code as feature_code,
    def.requires_reload_item_code
  into v_state
  from public.odyssey_character_weapon_feature_states s
  join public.odyssey_character_weapons w on w.id = s.character_weapon_id
  join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
  where s.id = v_state_id
  for update of s;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_STATE_NOT_FOUND',
      'state_id', v_state_id
    );
  end if;

  if not v_force
     and (
       not coalesce(v_state.requires_reload, false)
       or (
         v_state.max_charges is not null
         and coalesce(v_state.current_charges, 0) >= coalesce(v_state.max_charges, 0)
       )
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_RELOAD_NOT_REQUIRED',
      'state_id', v_state_id,
      'feature_code', v_state.feature_code
    );
  end if;

  if nullif(trim(coalesce(v_state.requires_reload_item_code, '')), '') is not null then
    v_item_result := public.remove_character_item_quantity(
      v_state.character_id,
      v_state.requires_reload_item_code,
      1
    );

    if coalesce((v_item_result->>'ok')::boolean, false) = false then
      return jsonb_build_object(
        'ok', false,
        'error', 'MISSING_RELOAD_ITEM',
        'state_id', v_state_id,
        'feature_code', v_state.feature_code,
        'required_item_code', v_state.requires_reload_item_code,
        'details', v_item_result
      );
    end if;

    v_consumed_item := jsonb_build_object(
      'item_code', v_state.requires_reload_item_code,
      'removed_quantity', coalesce((v_item_result->>'removed_quantity')::integer, 1),
      'remaining_quantity', coalesce((v_item_result->>'remaining_quantity')::integer, 0),
      'details', v_item_result
    );
  end if;

  update public.odyssey_character_weapon_feature_states
  set
    is_active = false,
    current_charges = max_charges,
    recharge_rounds_left = null,
    cooldown_rounds_left = null,
    active_rounds_left = null,
    active_uses_left = null,
    requires_reload = false
  where id = v_state_id;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_state.character_weapon_id,
    'state_id', v_state_id,
    'consumed_item', v_consumed_item,
    'feature', (
      select feature
      from jsonb_array_elements(public.get_character_weapon_features(v_state.character_weapon_id)->'features') feature
      where nullif(feature->>'state_id', '')::uuid = v_state_id
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
begin
  return public.reload_feature_resource(
    jsonb_build_object(
      'state_id', p_state_id,
      'force', false
    )
  );
end;
$$;

create or replace function public.use_character_item(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_item_id uuid := nullif(trim(coalesce(p_payload->>'character_item_id', '')), '')::uuid;
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_used_by_character_id uuid := nullif(trim(coalesce(p_payload->>'used_by_character_id', '')), '')::uuid;
  v_action text := lower(trim(coalesce(p_payload->>'action', '')));
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_created_by text := coalesce(nullif(trim(coalesce(p_payload->>'created_by', '')), ''), '');
  v_item record;
  v_target_part record;
  v_user public.odyssey_characters%rowtype;
  v_target_character public.odyssey_characters%rowtype;
  v_before_part jsonb := '{}'::jsonb;
  v_after_part jsonb := '{}'::jsonb;
  v_removed_effect_ids jsonb := '[]'::jsonb;
  v_body_changed boolean := false;
  v_effects_removed boolean := false;
  v_refresh jsonb := '{}'::jsonb;
  v_log_data jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_message text := '';
  v_new_minor integer := 0;
  v_new_serious integer := 0;
  v_new_critical integer := 0;
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
  v_remaining_quantity integer := 0;
  v_applied_healing text := 'none';
begin
  if v_character_item_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_NOT_FOUND',
      'message', 'character_item_id is required.'
    );
  end if;

  select
    i.id,
    i.character_id,
    i.item_def_id,
    i.custom_name,
    i.quantity,
    i.current_charges,
    i.max_charges,
    i.location_data,
    i.data,
    i.notes,
    d.code as item_code,
    d.name as item_name,
    d.item_type,
    d.use_action_type
  into v_item
  from public.odyssey_character_items i
  join public.odyssey_item_defs d on d.id = i.item_def_id
  where i.id = v_character_item_id
  for update of i;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_NOT_FOUND',
      'character_item_id', v_character_item_id
    );
  end if;

  if v_used_by_character_id is null then
    v_used_by_character_id := v_item.character_id;
  end if;

  select *
  into v_user
  from public.odyssey_characters c
  where c.id = v_used_by_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_used_by_character_id
    );
  end if;

  if v_item.character_id <> v_used_by_character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_OWNERSHIP_MISMATCH',
      'character_item_id', v_character_item_id,
      'used_by_character_id', v_used_by_character_id
    );
  end if;

  if coalesce(v_item.quantity, 0) <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_NOT_AVAILABLE',
      'character_item_id', v_character_item_id
    );
  end if;

  if v_action = '' then
    v_action := lower(trim(coalesce(v_item.use_action_type, 'none')));
  end if;

  if v_action <> 'heal' or v_item.item_code <> 'basic_medkit' then
    return jsonb_build_object(
      'ok', false,
      'error', 'ITEM_ACTION_NOT_SUPPORTED',
      'character_item_id', v_character_item_id,
      'item_code', v_item.item_code,
      'action', v_action
    );
  end if;

  if v_target_body_part_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'message', 'target_body_part_id is required.'
    );
  end if;

  select
    b.id,
    b.character_id,
    b.part_key,
    b.custom_name,
    b.minor,
    b.serious,
    b.critical,
    b.disabled,
    b.destroyed,
    b.max_critical,
    coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name
  into v_target_part
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.id = v_target_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_NOT_FOUND',
      'target_body_part_id', v_target_body_part_id
    );
  end if;

  if v_target_character_id is null then
    v_target_character_id := v_target_part.character_id;
  elsif v_target_character_id <> v_target_part.character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_TARGET_MISMATCH',
      'target_body_part_id', v_target_body_part_id,
      'target_character_id', v_target_character_id
    );
  end if;

  if coalesce(v_target_part.destroyed, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'BODY_PART_DESTROYED',
      'character_item_id', v_character_item_id,
      'target_character_id', v_target_character_id,
      'target_body_part_id', v_target_body_part_id
    );
  end if;

  select *
  into v_target_character
  from public.odyssey_characters c
  where c.id = v_target_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'TARGET_NOT_FOUND',
      'target_character_id', v_target_character_id
    );
  end if;

  v_before_part := jsonb_build_object(
    'id', v_target_part.id,
    'part_key', v_target_part.part_key,
    'name', v_target_part.part_name,
    'minor', coalesce(v_target_part.minor, 0),
    'serious', coalesce(v_target_part.serious, 0),
    'critical', coalesce(v_target_part.critical, 0),
    'disabled', coalesce(v_target_part.disabled, false),
    'destroyed', coalesce(v_target_part.destroyed, false)
  );

  v_new_minor := coalesce(v_target_part.minor, 0);
  v_new_serious := coalesce(v_target_part.serious, 0);
  v_new_critical := coalesce(v_target_part.critical, 0);
  v_new_disabled := coalesce(v_target_part.disabled, false);
  v_new_destroyed := coalesce(v_target_part.destroyed, false);

  if coalesce(v_target_part.serious, 0) > 0 then
    v_new_serious := greatest(coalesce(v_target_part.serious, 0) - 1, 0);
    v_applied_healing := 'serious_reduced';
    v_body_changed := true;
  elsif coalesce(v_target_part.critical, 0) > 0 then
    v_new_critical := greatest(coalesce(v_target_part.critical, 0) - 1, 0);
    v_new_serious := coalesce(v_target_part.serious, 0) + 1;
    v_applied_healing := 'critical_to_serious';
    v_body_changed := true;
  elsif coalesce(v_target_part.minor, 0) > 0 then
    v_new_minor := 0;
    v_applied_healing := 'minor_cleared';
    v_body_changed := true;
  end if;

  if v_body_changed then
    if coalesce(v_target_part.destroyed, false) then
      v_new_destroyed := true;
      v_new_disabled := true;
    else
      v_new_destroyed := false;
      v_new_disabled := v_new_critical > 0;
    end if;
  end if;

  with removed_effects as (
    update public.odyssey_character_effects e
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where e.character_id = v_target_character_id
      and e.is_active = true
      and (
        lower(coalesce(e.effect_key, '')) = 'unconscious'
        or exists (
          select 1
          from public.odyssey_effect_defs d
          where d.id = e.effect_def_id
            and d.code = 'unconscious'
        )
      )
    returning e.id
  )
  select coalesce(jsonb_agg(id), '[]'::jsonb)
  into v_removed_effect_ids
  from removed_effects;

  v_effects_removed := jsonb_array_length(v_removed_effect_ids) > 0;

  if not v_body_changed and not v_effects_removed then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_HEALABLE_DAMAGE',
      'character_item_id', v_character_item_id,
      'target_character_id', v_target_character_id,
      'target_body_part_id', v_target_body_part_id
    );
  end if;

  if coalesce(v_item.quantity, 0) <= 1 then
    delete from public.odyssey_character_items
    where id = v_character_item_id;
    v_remaining_quantity := 0;
  else
    update public.odyssey_character_items
    set quantity = quantity - 1
    where id = v_character_item_id;
    v_remaining_quantity := coalesce(v_item.quantity, 0) - 1;
  end if;

  if v_body_changed then
    update public.odyssey_character_body_parts
    set
      minor = v_new_minor,
      serious = v_new_serious,
      critical = v_new_critical,
      disabled = v_new_disabled,
      destroyed = v_new_destroyed
    where id = v_target_body_part_id;
  end if;

  v_after_part := jsonb_build_object(
    'id', v_target_part.id,
    'part_key', v_target_part.part_key,
    'name', v_target_part.part_name,
    'minor', v_new_minor,
    'serious', v_new_serious,
    'critical', v_new_critical,
    'disabled', v_new_disabled,
    'destroyed', v_new_destroyed
  );

  v_refresh := public.odyssey_refresh_character_combat_state(v_target_character_id);

  v_message := format(
    '%s uses %s on %s (%s).',
    coalesce(nullif(trim(v_user.resources->>'name'), ''), v_user.character_key),
    coalesce(nullif(trim(v_item.custom_name), ''), v_item.item_name),
    coalesce(nullif(trim(v_target_character.resources->>'name'), ''), v_target_character.character_key),
    v_target_part.part_name
  );

  v_log_data := jsonb_build_object(
    'type', 'item_use',
    'ok', true,
    'action', v_action,
    'item_code', v_item.item_code,
    'item_name', coalesce(nullif(trim(v_item.custom_name), ''), v_item.item_name),
    'used_by_character_id', v_used_by_character_id,
    'target_character_id', v_target_character_id,
    'target_body_part_id', v_target_body_part_id,
    'target_body_part_name', v_target_part.part_name,
    'healing_action', v_applied_healing,
    'body_part_before', v_before_part,
    'body_part_after', v_after_part,
    'removed_effect_ids', v_removed_effect_ids,
    'remaining_item_quantity', v_remaining_quantity
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
    coalesce(v_user.campaign_id, v_target_character.campaign_id, ''),
    coalesce(v_user.room_id, v_target_character.room_id, ''),
    v_scene_id,
    v_encounter_id,
    v_used_by_character_id,
    v_target_character_id,
    'item_use',
    v_message,
    v_log_data,
    coalesce(v_created_by, v_used_by_character_id::text, '')
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, coalesce(v_user.room_id, v_target_character.room_id, ''));

  return jsonb_build_object(
    'ok', true,
    'character_item_id', v_character_item_id,
    'item_code', v_item.item_code,
    'action', v_action,
    'used_by_character_id', v_used_by_character_id,
    'target_character_id', v_target_character_id,
    'target_body_part_id', v_target_body_part_id,
    'consumed_quantity', 1,
    'remaining_quantity', v_remaining_quantity,
    'healing_action', v_applied_healing,
    'body_part_before', v_before_part,
    'body_part_after', v_after_part,
    'removed_effect_ids', v_removed_effect_ids,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb),
    'log_id', v_log_id
  );
end;
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
      'equipment', '[]'::jsonb
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
    'armor_summary', coalesce(v_equipment->'armor_summary', '{}'::jsonb)
  );
end;
$$;

grant execute on function public.odyssey_get_character_item_row(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_ammo_stock_row(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_magazine_summary(uuid) to anon, authenticated;
grant execute on function public.odyssey_find_character_ammo_stock_identity(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_is_magazine_loaded_in_weapon(uuid) to anon, authenticated;
grant execute on function public.get_character_item_quantity(uuid, text) to anon, authenticated;
grant execute on function public.add_character_item(jsonb) to anon, authenticated;
grant execute on function public.remove_character_item_quantity(uuid, text, integer) to anon, authenticated;
grant execute on function public.add_character_ammo_stock(jsonb) to anon, authenticated;
grant execute on function public.remove_character_ammo_stock(uuid, integer) to anon, authenticated;
grant execute on function public.load_rounds_to_magazine(jsonb) to anon, authenticated;
grant execute on function public.unload_rounds_from_magazine(jsonb) to anon, authenticated;
grant execute on function public.load_magazine_full(jsonb) to anon, authenticated;
grant execute on function public.unload_magazine_all(jsonb) to anon, authenticated;
grant execute on function public.reload_feature_resource(jsonb) to anon, authenticated;
grant execute on function public.reload_feature_resource(uuid) to anon, authenticated;
grant execute on function public.use_character_item(jsonb) to anon, authenticated;
grant execute on function public.get_character_inventory(uuid) to anon, authenticated;
