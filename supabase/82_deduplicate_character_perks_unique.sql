do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_id_perk_def_id_key'
  ) and exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_perk_key'
  ) then
    alter table public.odyssey_character_perks
      drop constraint odyssey_character_perks_character_id_perk_def_id_key;
  elsif exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_id_perk_def_id_key'
  ) and not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_perk_key'
  ) then
    alter table public.odyssey_character_perks
      rename constraint odyssey_character_perks_character_id_perk_def_id_key
      to odyssey_character_perks_character_perk_key;
  elsif not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_perk_key'
  ) then
    alter table public.odyssey_character_perks
      add constraint odyssey_character_perks_character_perk_key unique (character_id, perk_def_id);
  end if;
end;
$$;
