alter table public.odyssey_combat_grid_settings enable row level security;
alter table public.odyssey_combat_positions enable row level security;

drop policy if exists "odyssey_combat_grid_settings_full_access" on public.odyssey_combat_grid_settings;
create policy "odyssey_combat_grid_settings_full_access"
on public.odyssey_combat_grid_settings
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_combat_positions_full_access" on public.odyssey_combat_positions;
create policy "odyssey_combat_positions_full_access"
on public.odyssey_combat_positions
for all
to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_combat_grid_settings to anon, authenticated;
grant select, insert, update, delete on public.odyssey_combat_positions to anon, authenticated;
