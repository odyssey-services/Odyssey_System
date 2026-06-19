alter table public.odyssey_skill_level_requirements
  add column if not exists development_point_cost integer,
  add column if not exists advancement_mode text not null default 'development_points';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'odyssey_skill_level_requirements_advancement_mode_check'
  ) then
    alter table public.odyssey_skill_level_requirements
      add constraint odyssey_skill_level_requirements_advancement_mode_check
      check (advancement_mode in ('development_points', 'gm_only'));
  end if;
end;
$$;

create table if not exists public.odyssey_character_progression (
  character_id uuid primary key references public.odyssey_characters(id) on delete cascade,
  development_points integer not null default 0 check (development_points >= 0),
  lifetime_points_granted integer not null default 0 check (lifetime_points_granted >= 0),
  lifetime_points_spent integer not null default 0 check (lifetime_points_spent >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.odyssey_character_progression_ledger (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.odyssey_characters(id) on delete cascade,
  transaction_type text not null
    check (
      transaction_type in (
        'grant',
        'spend_attribute',
        'spend_skill',
        'spend_perk',
        'gm_legendary_skill_grant',
        'adjustment'
      )
    ),
  amount integer not null,
  balance_after integer not null check (balance_after >= 0),
  reason text,
  source_type text,
  source_id uuid null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists odyssey_character_progression_ledger_character_idx
  on public.odyssey_character_progression_ledger (character_id, created_at desc, id desc);

create or replace function public.odyssey_prevent_progression_ledger_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'odyssey_character_progression_ledger rows are immutable.';
end;
$$;

drop trigger if exists odyssey_touch_updated_at_character_progression on public.odyssey_character_progression;
create trigger odyssey_touch_updated_at_character_progression
before update on public.odyssey_character_progression
for each row
execute function public.odyssey_touch_updated_at();

drop trigger if exists odyssey_prevent_progression_ledger_update on public.odyssey_character_progression_ledger;
create trigger odyssey_prevent_progression_ledger_update
before update on public.odyssey_character_progression_ledger
for each row
execute function public.odyssey_prevent_progression_ledger_mutation();

drop trigger if exists odyssey_prevent_progression_ledger_delete on public.odyssey_character_progression_ledger;
create trigger odyssey_prevent_progression_ledger_delete
before delete on public.odyssey_character_progression_ledger
for each row
execute function public.odyssey_prevent_progression_ledger_mutation();

alter table public.odyssey_character_progression enable row level security;
alter table public.odyssey_character_progression_ledger enable row level security;

drop policy if exists "odyssey_character_progression_full_access" on public.odyssey_character_progression;
create policy "odyssey_character_progression_full_access"
on public.odyssey_character_progression
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_progression_ledger_full_access" on public.odyssey_character_progression_ledger;
create policy "odyssey_character_progression_ledger_full_access"
on public.odyssey_character_progression_ledger
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_character_progression to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_progression_ledger to anon, authenticated;
