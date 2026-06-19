alter table public.odyssey_character_effects enable row level security;
alter table public.odyssey_character_combat_state enable row level security;
alter table public.odyssey_combat_log enable row level security;
alter table public.odyssey_token_links enable row level security;
alter table public.odyssey_combat_encounters enable row level security;
alter table public.odyssey_initiative_entries enable row level security;

drop policy if exists "odyssey_character_effects_full_access" on public.odyssey_character_effects;
create policy "odyssey_character_effects_full_access"
on public.odyssey_character_effects
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_combat_state_full_access" on public.odyssey_character_combat_state;
create policy "odyssey_character_combat_state_full_access"
on public.odyssey_character_combat_state
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_combat_log_full_access" on public.odyssey_combat_log;
create policy "odyssey_combat_log_full_access"
on public.odyssey_combat_log
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_token_links_full_access" on public.odyssey_token_links;
create policy "odyssey_token_links_full_access"
on public.odyssey_token_links
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_combat_encounters_full_access" on public.odyssey_combat_encounters;
create policy "odyssey_combat_encounters_full_access"
on public.odyssey_combat_encounters
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_initiative_entries_full_access" on public.odyssey_initiative_entries;
create policy "odyssey_initiative_entries_full_access"
on public.odyssey_initiative_entries
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_character_effects to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_combat_state to anon, authenticated;
grant select, insert, update, delete on public.odyssey_combat_log to anon, authenticated;
grant select, insert, update, delete on public.odyssey_token_links to anon, authenticated;
grant select, insert, update, delete on public.odyssey_combat_encounters to anon, authenticated;
grant select, insert, update, delete on public.odyssey_initiative_entries to anon, authenticated;

grant execute on function public.recompute_odyssey_character_combat_state(uuid) to anon, authenticated;
grant execute on function public.apply_damage(jsonb) to anon, authenticated;
grant execute on function public.heal_damage(jsonb) to anon, authenticated;
grant execute on function public.add_effect(jsonb) to anon, authenticated;
grant execute on function public.remove_effect(jsonb) to anon, authenticated;
grant execute on function public.roll_initiative(jsonb) to anon, authenticated;
grant execute on function public.advance_turn(jsonb) to anon, authenticated;
