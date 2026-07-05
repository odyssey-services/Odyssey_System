-- ===== BEGIN 96_move_default_10m.sql =====
-- Keep encounter-level move default aligned with the 10m combat movement baseline.

alter table public.odyssey_combat_encounters
  alter column move_default set default 10;

update public.odyssey_combat_encounters
set move_default = 10
where coalesce(move_default, 0) <> 10;
-- ===== END 96_move_default_10m.sql =====
