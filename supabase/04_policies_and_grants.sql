alter table public.odyssey_characters enable row level security;
alter table public.odyssey_character_characteristics enable row level security;
alter table public.odyssey_character_skills enable row level security;
alter table public.odyssey_character_weapons enable row level security;
alter table public.odyssey_character_body_parts enable row level security;

drop policy if exists "odyssey_characters_full_access" on public.odyssey_characters;
create policy "odyssey_characters_full_access"
on public.odyssey_characters
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_characteristics_full_access" on public.odyssey_character_characteristics;
create policy "odyssey_character_characteristics_full_access"
on public.odyssey_character_characteristics
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_skills_full_access" on public.odyssey_character_skills;
create policy "odyssey_character_skills_full_access"
on public.odyssey_character_skills
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_weapons_full_access" on public.odyssey_character_weapons;
create policy "odyssey_character_weapons_full_access"
on public.odyssey_character_weapons
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "odyssey_character_body_parts_full_access" on public.odyssey_character_body_parts;
create policy "odyssey_character_body_parts_full_access"
on public.odyssey_character_body_parts
for all
to anon, authenticated
using (true)
with check (true);

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.odyssey_characters to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_characteristics to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_skills to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_weapons to anon, authenticated;
grant select, insert, update, delete on public.odyssey_character_body_parts to anon, authenticated;
grant execute on function public.get_odyssey_character_sheet(text) to anon, authenticated;
grant execute on function public.upsert_odyssey_character_sheet(jsonb) to anon, authenticated;
