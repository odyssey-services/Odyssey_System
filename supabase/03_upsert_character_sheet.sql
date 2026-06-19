create or replace function public.upsert_odyssey_character_sheet(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_character_key text := trim(coalesce(p_payload->>'character_key', ''));
  v_character_id uuid;
  v_character_bucket text := case lower(coalesce(p_payload->>'character_bucket', 'player'))
    when 'npc_template' then 'npc_template'
    when 'npc_active' then 'npc_active'
    else 'player'
  end;
  v_source_template_key text := trim(coalesce(p_payload->>'source_template_key', ''));
  v_enabled boolean := coalesce((p_payload->>'enabled')::boolean, true);
  v_tracker_minor integer := greatest(0, least(4, coalesce((p_payload->>'tracker_minor')::integer, 0)));
  v_tracker_serious integer := greatest(0, least(2, coalesce((p_payload->>'tracker_serious')::integer, 0)));
  v_owner_player_id text := coalesce(p_payload->>'owner_player_id', '');
  v_owner_player_name text := coalesce(p_payload->>'owner_player_name', '');
  v_resources jsonb := case
    when jsonb_typeof(p_payload->'resources') = 'object' then p_payload->'resources'
    else '{}'::jsonb
  end;
begin
  if v_character_key = '' then
    raise exception 'character_key is required';
  end if;

  insert into public.odyssey_characters (
    character_key,
    character_bucket,
    source_template_key,
    enabled,
    tracker_minor,
    tracker_serious,
    owner_player_id,
    owner_player_name,
    resources
  )
  values (
    v_character_key,
    v_character_bucket,
    v_source_template_key,
    v_enabled,
    v_tracker_minor,
    v_tracker_serious,
    v_owner_player_id,
    v_owner_player_name,
    v_resources
  )
  on conflict (character_key) do update
  set
    character_bucket = excluded.character_bucket,
    source_template_key = excluded.source_template_key,
    enabled = excluded.enabled,
    tracker_minor = excluded.tracker_minor,
    tracker_serious = excluded.tracker_serious,
    owner_player_id = excluded.owner_player_id,
    owner_player_name = excluded.owner_player_name,
    resources = excluded.resources
  returning id into v_character_id;

  delete from public.odyssey_character_characteristics where character_id = v_character_id;
  delete from public.odyssey_character_skills where character_id = v_character_id;
  delete from public.odyssey_character_weapons where character_id = v_character_id;
  delete from public.odyssey_character_body_parts where character_id = v_character_id;

  insert into public.odyssey_character_characteristics (
    character_id,
    key,
    label,
    value,
    sort_order
  )
  select
    v_character_id,
    trim(coalesce(entry.value->>'key', '')),
    coalesce(nullif(trim(entry.value->>'label'), ''), trim(coalesce(entry.value->>'key', ''))),
    greatest(0, least(20, coalesce((entry.value->>'value')::integer, 0))),
    coalesce((entry.value->>'sort_order')::integer, entry.ordinality - 1)
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_payload->'characteristics') = 'array' then p_payload->'characteristics'
      else '[]'::jsonb
    end
  ) with ordinality as entry(value, ordinality)
  where trim(coalesce(entry.value->>'key', '')) <> '';

  insert into public.odyssey_character_skills (
    character_id,
    name,
    value,
    category,
    strength_bonus,
    sort_order
  )
  select
    v_character_id,
    trim(coalesce(entry.value->>'name', '')),
    greatest(0, least(10, coalesce((entry.value->>'value')::integer, 0))),
    case lower(coalesce(entry.value->>'category', 'applied'))
      when 'combat' then 'combat'
      when 'abilities' then 'abilities'
      else 'applied'
    end,
    coalesce((entry.value->>'strength_bonus')::boolean, false),
    coalesce((entry.value->>'sort_order')::integer, entry.ordinality - 1)
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_payload->'skills') = 'array' then p_payload->'skills'
      else '[]'::jsonb
    end
  ) with ordinality as entry(value, ordinality)
  where trim(coalesce(entry.value->>'name', '')) <> '';

  insert into public.odyssey_character_weapons (
    character_id,
    weapon_kind,
    name,
    damage,
    accuracy,
    ammo_current,
    ammo_max,
    sort_order
  )
  select
    v_character_id,
    case lower(coalesce(entry.value->>'weapon_kind', 'melee'))
      when 'ranged' then 'ranged'
      else 'melee'
    end,
    coalesce(nullif(trim(entry.value->>'name'), ''), 'Weapon'),
    greatest(-99, least(99, coalesce((entry.value->>'damage')::integer, 0))),
    greatest(-99, least(99, coalesce((entry.value->>'accuracy')::integer, 0))),
    greatest(0, coalesce((entry.value->>'ammoCurrent')::integer, (entry.value->>'ammo_current')::integer, 0)),
    greatest(0, coalesce((entry.value->>'ammoMax')::integer, (entry.value->>'ammo_max')::integer, 0)),
    coalesce((entry.value->>'sort_order')::integer, entry.ordinality - 1)
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_payload->'weapons') = 'array' then p_payload->'weapons'
      else '[]'::jsonb
    end
  ) with ordinality as entry(value, ordinality);

  insert into public.odyssey_character_body_parts (
    character_id,
    part_key,
    current_hp,
    max_hp,
    armor,
    minor,
    serious,
    sort_order
  )
  select
    v_character_id,
    trim(coalesce(entry.value->>'part_key', '')),
    greatest(0, coalesce((entry.value->>'current_hp')::integer, 0)),
    greatest(0, coalesce((entry.value->>'max_hp')::integer, 0)),
    greatest(0, coalesce((entry.value->>'armor')::integer, 0)),
    greatest(0, least(3, coalesce((entry.value->>'minor')::integer, 0))),
    greatest(0, least(1, coalesce((entry.value->>'serious')::integer, 0))),
    coalesce((entry.value->>'sort_order')::integer, entry.ordinality - 1)
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_payload->'body_parts') = 'array' then p_payload->'body_parts'
      else '[]'::jsonb
    end
  ) with ordinality as entry(value, ordinality)
  where trim(coalesce(entry.value->>'part_key', '')) in ('Head', 'L.Arm', 'R.Arm', 'Torso', 'L.Leg', 'R.Leg', 'Shield', 'Special');

  return public.get_odyssey_character_sheet(v_character_key);
end;
$body$;
