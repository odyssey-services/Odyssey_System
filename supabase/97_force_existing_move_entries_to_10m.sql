-- Hard-normalize initiative movement to the fixed 10m baseline while preserving
-- already-spent movement on active encounters.

alter table public.odyssey_initiative_entries
  alter column move_max set default 10,
  alter column move_current set default 10;

update public.odyssey_initiative_entries e
set
  move_max = 10,
  move_current = case
    when coalesce(e.move_current, 0) <= 0 then 0
    when coalesce(e.move_current, 0) = coalesce(e.move_max, 0) then 10
    else least(coalesce(e.move_current, 0), 10)
  end
where coalesce(e.move_max, 0) <> 10
   or coalesce(e.move_current, 0) > 10
   or (
     coalesce(e.move_current, 0) = coalesce(e.move_max, 0)
     and coalesce(e.move_current, 0) <> 10
   );
