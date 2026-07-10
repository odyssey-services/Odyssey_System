-- ===== BEGIN 111_drop_ambiguous_get_character_armory_overload.sql =====
-- Cleanup hotfix:
-- Remove the legacy overloaded get_character_armory(uuid, uuid) function,
-- because PostgREST cannot reliably choose between it and get_character_armory(uuid).

drop function if exists public.get_character_armory(uuid, uuid);

grant execute on function public.get_character_armory(uuid) to anon, authenticated;
grant execute on function public.get_character_armory_context(uuid, uuid) to anon, authenticated;

-- ===== END 111_drop_ambiguous_get_character_armory_overload.sql =====
