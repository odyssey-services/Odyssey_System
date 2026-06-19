create extension if not exists pgcrypto;

alter table public.odyssey_characters
  add column if not exists source_template_id uuid null references public.odyssey_characters(id) on delete set null;

alter table public.odyssey_character_combat_state
  add column if not exists status_summary text not null default '';

with unique_templates as (
  select
    c.character_key,
    (array_agg(c.id))[1] as template_id
  from public.odyssey_characters c
  where c.character_bucket = 'npc_template'
    and coalesce(c.is_deleted, false) = false
  group by c.character_key
  having count(*) = 1
)
update public.odyssey_characters active_npc
set source_template_id = unique_templates.template_id
from unique_templates
where active_npc.character_bucket = 'npc_active'
  and active_npc.source_template_id is null
  and nullif(trim(active_npc.source_template_key), '') is not null
  and active_npc.source_template_key = unique_templates.character_key;

create or replace function public.odyssey_build_character_status_summary(
  p_character_id uuid
)
returns text
language sql
stable
as $$
  with state_row as (
    select
      s.is_alive,
      s.is_conscious,
      s.tracker_minor,
      s.tracker_serious,
      s.combat_flags
    from public.odyssey_character_combat_state s
    where s.character_id = p_character_id
  )
  select coalesce(
    (
      select array_to_string(
        array_remove(
          array[
            case
              when coalesce(state_row.is_alive, true) then 'Alive'
              else 'Dead'
            end,
            case
              when coalesce(state_row.is_conscious, true) then 'Conscious'
              else 'Unconscious'
            end,
            case
              when coalesce(
                nullif(jsonb_extract_path_text(state_row.combat_flags, 'helpless'), '')::boolean,
                false
              ) then 'Helpless'
              else null
            end,
            case
              when coalesce(state_row.tracker_serious, 0) > 0 then 'Serious: ' || state_row.tracker_serious::text
              else null
            end,
            case
              when coalesce(state_row.tracker_minor, 0) > 0 then 'Minor: ' || state_row.tracker_minor::text
              else null
            end
          ]::text[],
          null
        ),
        ' | '
      )
      from state_row
    ),
    'Alive | Conscious'
  );
$$;

create or replace function public.odyssey_get_character_token_state(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_state public.odyssey_character_combat_state%rowtype;
  v_refresh jsonb := '{}'::jsonb;
begin
  select *
  into v_state
  from public.odyssey_character_combat_state s
  where s.character_id = p_character_id;

  if not found then
    v_refresh := public.odyssey_refresh_character_combat_state(p_character_id);

    select *
    into v_state
    from public.odyssey_character_combat_state s
    where s.character_id = p_character_id;
  end if;

  return jsonb_build_object(
    'character_id', p_character_id,
    'state_version', coalesce(v_state.state_version, 0),
    'status_summary', coalesce(nullif(trim(v_state.status_summary), ''), public.odyssey_build_character_status_summary(p_character_id)),
    'overlay_text', coalesce(v_state.overlay_text, ''),
    'combat_flags', coalesce(v_state.combat_flags, '{}'::jsonb),
    'updated_at', coalesce(v_state.updated_at, timezone('utc', now()))
  );
end;
$$;

update public.odyssey_character_combat_state s
set status_summary = public.odyssey_build_character_status_summary(s.character_id)
where coalesce(trim(s.status_summary), '') = '';

create or replace function public.odyssey_refresh_character_combat_state(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character public.odyssey_characters%rowtype;
  v_existing_state public.odyssey_character_combat_state%rowtype;
  v_rule_sheet jsonb := '{}'::jsonb;
  v_body_summary jsonb := '[]'::jsonb;
  v_equipment_bundle jsonb := '{}'::jsonb;
  v_equipment_summary jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_summary jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
  v_armor_parts jsonb := '[]'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_active_penalties jsonb := '[]'::jsonb;
  v_combat_flags jsonb := '{}'::jsonb;
  v_tracker_minor integer := 0;
  v_tracker_serious integer := 0;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_next_state_version integer := 1;
  v_updated_at timestamptz := timezone('utc', now());
  v_overlay_data jsonb := '{}'::jsonb;
  v_status_summary text := 'Alive | Conscious';
begin
  select *
  into v_character
  from public.odyssey_characters c
  where c.id = p_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id
    );
  end if;

  select *
  into v_existing_state
  from public.odyssey_character_combat_state s
  where s.character_id = p_character_id;

  v_rule_sheet := public.get_character_rule_sheet(p_character_id);
  v_equipment_bundle := public.get_character_equipment(p_character_id);
  v_equipment_summary := coalesce(v_equipment_bundle->'summary', '{}'::jsonb);
  v_effective_stats := public.get_effective_character_stats(p_character_id);
  v_effect_summary := public.get_character_effect_summary(p_character_id);
  v_active_effects := coalesce(v_effect_summary->'effects', '[]'::jsonb);
  v_active_penalties := coalesce(v_effect_summary->'penalties', '[]'::jsonb);
  v_body_summary := coalesce(v_rule_sheet->'body_parts', '[]'::jsonb);
  v_armor_summary := coalesce(v_equipment_bundle->'armor_summary', '{}'::jsonb);

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'body_part_def_id', b.body_part_def_id,
          'part_key', b.part_key,
          'custom_name', b.custom_name,
          'sort_order', b.sort_order,
          'natural_armor_value', b.natural_armor_value,
          'armor_value', b.armor_value,
          'armor_minor', b.armor_minor,
          'armor_max_minor', b.armor_max_minor,
          'armor_serious', b.armor_serious,
          'armor_max_serious', b.armor_max_serious,
          'armor_critical', b.armor_critical,
          'armor_max_critical', b.armor_max_critical,
          'armor_destroyed', b.armor_destroyed
        )
        order by b.sort_order, b.part_key
      ),
      '[]'::jsonb
    ),
    coalesce(sum(b.minor), 0),
    coalesce(sum(b.serious), 0)
  into
    v_armor_parts,
    v_tracker_minor,
    v_tracker_serious
  from public.odyssey_character_body_parts b
  where b.character_id = p_character_id;

  v_is_alive := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_alive'), '')::boolean, true);
  v_is_conscious := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_conscious'), '')::boolean, true);

  v_armor_summary := jsonb_set(
    coalesce(v_armor_summary, '{}'::jsonb),
    '{parts}',
    v_armor_parts,
    true
  );

  v_combat_flags := jsonb_build_object(
    'helpless', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'helpless'), '')::boolean, false),
    'skip_main_action', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false),
    'skip_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_movement'), '')::boolean, false),
    'consumes_full_turn', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'consumes_full_turn'), '')::boolean, false),
    'suppress_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'suppress_movement'), '')::boolean, false),
    'cannot_leave_cover', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'cannot_leave_cover'), '')::boolean, false),
    'requires_concentration', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'requires_concentration'), '')::boolean, false)
  );

  v_status_summary := array_to_string(
    array_remove(
      array[
        case
          when v_is_alive then 'Alive'
          else 'Dead'
        end,
        case
          when v_is_conscious then 'Conscious'
          else 'Unconscious'
        end,
        case
          when coalesce(nullif(jsonb_extract_path_text(v_combat_flags, 'helpless'), '')::boolean, false) then 'Helpless'
          else null
        end,
        case
          when coalesce(v_tracker_serious, 0) > 0 then 'Serious: ' || v_tracker_serious::text
          else null
        end,
        case
          when coalesce(v_tracker_minor, 0) > 0 then 'Minor: ' || v_tracker_minor::text
          else null
        end
      ]::text[],
      null
    ),
    ' | '
  );
  v_status_summary := coalesce(nullif(v_status_summary, ''), 'Alive | Conscious');

  v_next_state_version := coalesce(v_existing_state.state_version, 0) + 1;
  v_overlay_data := coalesce(v_existing_state.overlay_data, '{}'::jsonb)
    || jsonb_build_object(
      'armor_summary', v_armor_summary,
      'equipment_summary', v_equipment_summary
    );

  insert into public.odyssey_character_combat_state (
    character_id,
    campaign_id,
    room_id,
    body_summary,
    armor_summary,
    equipment_summary,
    active_effects,
    active_penalties,
    effective_stats,
    combat_flags,
    overlay_text,
    overlay_data,
    status_summary,
    tracker_minor,
    tracker_serious,
    is_alive,
    is_conscious,
    state_version,
    updated_at
  )
  values (
    p_character_id,
    coalesce(v_character.campaign_id, ''),
    coalesce(v_character.room_id, ''),
    v_body_summary,
    v_armor_summary,
    v_equipment_summary,
    v_active_effects,
    v_active_penalties,
    v_effective_stats,
    v_combat_flags,
    coalesce(v_existing_state.overlay_text, ''),
    v_overlay_data,
    v_status_summary,
    v_tracker_minor,
    v_tracker_serious,
    v_is_alive,
    v_is_conscious,
    v_next_state_version,
    v_updated_at
  )
  on conflict (character_id) do update
  set
    campaign_id = excluded.campaign_id,
    room_id = excluded.room_id,
    body_summary = excluded.body_summary,
    armor_summary = excluded.armor_summary,
    equipment_summary = excluded.equipment_summary,
    active_effects = excluded.active_effects,
    active_penalties = excluded.active_penalties,
    effective_stats = excluded.effective_stats,
    combat_flags = excluded.combat_flags,
    overlay_text = excluded.overlay_text,
    overlay_data = excluded.overlay_data,
    status_summary = excluded.status_summary,
    tracker_minor = excluded.tracker_minor,
    tracker_serious = excluded.tracker_serious,
    is_alive = excluded.is_alive,
    is_conscious = excluded.is_conscious,
    state_version = excluded.state_version,
    updated_at = excluded.updated_at;

  update public.odyssey_characters
  set active_combat_state_version = v_next_state_version
  where id = p_character_id;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'state_version', v_next_state_version,
    'status_summary', v_status_summary,
    'combat_state',
      jsonb_build_object(
        'character_id', p_character_id,
        'character_key', v_character.character_key,
        'campaign_id', coalesce(v_character.campaign_id, ''),
        'room_id', coalesce(v_character.room_id, ''),
        'body_summary', v_body_summary,
        'armor_summary', v_armor_summary,
        'equipment_summary', v_equipment_summary,
        'active_effects', v_active_effects,
        'active_penalties', v_active_penalties,
        'effective_stats', v_effective_stats,
        'combat_flags', v_combat_flags,
        'overlay_text', coalesce(v_existing_state.overlay_text, ''),
        'overlay_data', v_overlay_data,
        'status_summary', v_status_summary,
        'tracker_minor', v_tracker_minor,
        'tracker_serious', v_tracker_serious,
        'is_alive', v_is_alive,
        'is_conscious', v_is_conscious,
        'state_version', v_next_state_version,
        'updated_at', v_updated_at
      )
  );
end;
$$;

create or replace function public.odyssey_spawn_npc_active_from_template(
  p_source_character_id uuid,
  p_instance_name text default null,
  p_campaign_id text default '',
  p_room_id text default '',
  p_scene_id text default ''
)
returns jsonb
language plpgsql
as $$
declare
  v_source public.odyssey_characters%rowtype;
  v_new_character_id uuid := null;
  v_new_character_key text := '';
  v_new_name text := '';
  v_resources jsonb := '{}'::jsonb;
  v_body_part_map jsonb := '{}'::jsonb;
  v_skill_map jsonb := '{}'::jsonb;
  v_equipment_map jsonb := '{}'::jsonb;
  v_item_map jsonb := '{}'::jsonb;
  v_magazine_map jsonb := '{}'::jsonb;
  v_weapon_map jsonb := '{}'::jsonb;
  v_row record;
  v_new_id uuid := null;
  v_mapped_body_part_id uuid := null;
  v_mapped_skill_id uuid := null;
  v_mapped_equipment_id uuid := null;
  v_mapped_item_id uuid := null;
  v_mapped_magazine_id uuid := null;
  v_refresh jsonb := '{}'::jsonb;
  v_template_key text := '';
  v_key_base text := '';
begin
  select *
  into v_source
  from public.odyssey_characters c
  where c.id = p_source_character_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_NOT_FOUND',
      'message', 'Source character was not found.',
      'source_character_id', p_source_character_id
    );
  end if;

  if coalesce(v_source.is_deleted, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_DELETED',
      'message', 'Source character was deleted.',
      'source_character_id', p_source_character_id
    );
  end if;

  if coalesce(v_source.enabled, true) = false then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_DISABLED',
      'message', 'Source character is disabled.',
      'source_character_id', p_source_character_id
    );
  end if;

  if v_source.character_bucket <> 'npc_template' then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_BUCKET_NOT_SUPPORTED',
      'message', 'Only NPC templates can be spawned into active NPCs.',
      'source_character_id', p_source_character_id,
      'source_bucket', v_source.character_bucket
    );
  end if;

  v_template_key := coalesce(nullif(trim(v_source.character_key), ''), 'npc_template');
  v_new_name := coalesce(
    nullif(trim(coalesce(p_instance_name, '')), ''),
    nullif(trim(coalesce(v_source.resources->>'name', '')), ''),
    v_template_key
  );

  v_resources := coalesce(v_source.resources, '{}'::jsonb) || jsonb_build_object('name', v_new_name);
  v_key_base := regexp_replace(lower(v_template_key), '[^a-z0-9]+', '_', 'g');
  v_key_base := trim(both '_' from v_key_base);
  if v_key_base = '' then
    v_key_base := 'npc';
  end if;

  loop
    v_new_character_key := format(
      'npc_%s_%s',
      v_key_base,
      substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8)
    );
    exit when not exists (
      select 1
      from public.odyssey_characters existing
      where existing.character_key = v_new_character_key
    );
  end loop;

  insert into public.odyssey_characters (
    character_key,
    character_bucket,
    source_template_key,
    source_template_id,
    enabled,
    owner_player_id,
    owner_player_name,
    resources,
    campaign_id,
    room_id,
    active_combat_state_version,
    is_deleted
  )
  values (
    v_new_character_key,
    'npc_active',
    v_template_key,
    v_source.id,
    true,
    '',
    '',
    v_resources,
    coalesce(p_campaign_id, ''),
    coalesce(p_room_id, ''),
    0,
    false
  )
  returning id into v_new_character_id;

  for v_row in
    select *
    from public.odyssey_character_attributes a
    where a.character_id = v_source.id
    order by a.created_at, a.id
  loop
    insert into public.odyssey_character_attributes (
      character_id,
      attribute_def_id,
      value
    )
    values (
      v_new_character_id,
      v_row.attribute_def_id,
      v_row.value
    );
  end loop;

  for v_row in
    select *
    from public.odyssey_character_skills s
    where s.character_id = v_source.id
    order by s.created_at, s.id
  loop
    v_new_id := gen_random_uuid();
    insert into public.odyssey_character_skills (
      id,
      character_id,
      skill_def_id,
      level,
      governing_attribute_def_id,
      custom_name,
      notes
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.skill_def_id,
      v_row.level,
      v_row.governing_attribute_def_id,
      v_row.custom_name,
      v_row.notes
    );

    v_skill_map := jsonb_set(v_skill_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select *
    from public.odyssey_character_perks p
    where p.character_id = v_source.id
    order by p.acquired_at, p.id
  loop
    insert into public.odyssey_character_perks (
      character_id,
      perk_def_id,
      acquired_at,
      notes
    )
    values (
      v_new_character_id,
      v_row.perk_def_id,
      v_row.acquired_at,
      v_row.notes
    );
  end loop;

  for v_row in
    select *
    from public.odyssey_character_body_parts b
    where b.character_id = v_source.id
    order by b.sort_order, b.id
  loop
    v_new_id := gen_random_uuid();

    insert into public.odyssey_character_body_parts (
      id,
      character_id,
      body_part_def_id,
      custom_name,
      part_key,
      max_critical,
      critical,
      serious,
      minor,
      natural_armor_value,
      armor_value,
      armor_minor,
      armor_max_minor,
      armor_serious,
      armor_max_serious,
      armor_critical,
      armor_max_critical,
      armor_destroyed,
      disabled,
      destroyed,
      sort_order,
      notes
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.body_part_def_id,
      v_row.custom_name,
      v_row.part_key,
      v_row.max_critical,
      v_row.critical,
      v_row.serious,
      v_row.minor,
      coalesce(v_row.natural_armor_value, 0),
      v_row.armor_value,
      coalesce(v_row.armor_minor, 0),
      coalesce(v_row.armor_max_minor, 0),
      coalesce(v_row.armor_serious, 0),
      coalesce(v_row.armor_max_serious, 0),
      coalesce(v_row.armor_critical, 0),
      coalesce(v_row.armor_max_critical, 0),
      coalesce(v_row.armor_destroyed, false),
      v_row.disabled,
      v_row.destroyed,
      v_row.sort_order,
      v_row.notes
    );

    v_body_part_map := jsonb_set(v_body_part_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select *
    from public.odyssey_character_equipment_items e
    where e.character_id = v_source.id
    order by e.sort_order, e.created_at, e.id
  loop
    v_new_id := gen_random_uuid();
    v_mapped_body_part_id := public.odyssey_try_parse_uuid(v_body_part_map ->> coalesce(v_row.equipped_body_part_id::text, ''));

    insert into public.odyssey_character_equipment_items (
      id,
      character_id,
      equipment_model_id,
      equipped_body_part_id,
      custom_name,
      is_equipped,
      armor_value,
      armor_minor,
      armor_max_minor,
      armor_serious,
      armor_max_serious,
      armor_critical,
      armor_max_critical,
      armor_destroyed,
      current_charges,
      max_charges,
      data,
      notes,
      sort_order
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.equipment_model_id,
      v_mapped_body_part_id,
      v_row.custom_name,
      v_row.is_equipped,
      v_row.armor_value,
      coalesce(v_row.armor_minor, 0),
      coalesce(v_row.armor_max_minor, 0),
      coalesce(v_row.armor_serious, 0),
      coalesce(v_row.armor_max_serious, 0),
      v_row.armor_critical,
      v_row.armor_max_critical,
      v_row.armor_destroyed,
      v_row.current_charges,
      v_row.max_charges,
      coalesce(v_row.data, '{}'::jsonb),
      v_row.notes,
      v_row.sort_order
    );

    v_equipment_map := jsonb_set(v_equipment_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select *
    from public.odyssey_character_items i
    where i.character_id = v_source.id
    order by i.sort_order, i.created_at, i.id
  loop
    v_new_id := gen_random_uuid();

    insert into public.odyssey_character_items (
      id,
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
      v_new_id,
      v_new_character_id,
      v_row.item_def_id,
      v_row.custom_name,
      v_row.quantity,
      v_row.current_charges,
      v_row.max_charges,
      coalesce(v_row.location_data, '{}'::jsonb),
      coalesce(v_row.data, '{}'::jsonb),
      v_row.notes,
      v_row.sort_order
    );

    v_item_map := jsonb_set(v_item_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select *
    from public.odyssey_character_ammo_stock stock
    where stock.character_id = v_source.id
    order by stock.created_at, stock.id
  loop
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
      v_new_character_id,
      v_row.display_name,
      v_row.caliber_id,
      v_row.ammo_type_id,
      v_row.quantity,
      coalesce(v_row.location_data, '{}'::jsonb),
      coalesce(v_row.data, '{}'::jsonb),
      v_row.notes
    );
  end loop;

  for v_row in
    select *
    from public.odyssey_character_magazines m
    where m.character_id = v_source.id
    order by m.created_at, m.id
  loop
    v_new_id := gen_random_uuid();

    insert into public.odyssey_character_magazines (
      id,
      character_id,
      magazine_def_id,
      ammo_type_id,
      current_rounds,
      custom_name,
      notes
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.magazine_def_id,
      v_row.ammo_type_id,
      v_row.current_rounds,
      v_row.custom_name,
      v_row.notes
    );

    v_magazine_map := jsonb_set(v_magazine_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select *
    from public.odyssey_character_weapons w
    where w.character_id = v_source.id
    order by w.sort_order, w.created_at, w.id
  loop
    v_new_id := gen_random_uuid();
    v_mapped_magazine_id := public.odyssey_try_parse_uuid(v_magazine_map ->> coalesce(v_row.loaded_magazine_id::text, ''));

    insert into public.odyssey_character_weapons (
      id,
      character_id,
      weapon_model_id,
      custom_name,
      loaded_magazine_id,
      selected_fire_mode_id,
      notes,
      sort_order,
      active_profile_id
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.weapon_model_id,
      v_row.custom_name,
      v_mapped_magazine_id,
      v_row.selected_fire_mode_id,
      v_row.notes,
      v_row.sort_order,
      v_row.active_profile_id
    );

    v_weapon_map := jsonb_set(v_weapon_map, array[v_row.id::text], to_jsonb(v_new_id::text), true);
  end loop;

  for v_row in
    select ps.*
    from public.odyssey_character_weapon_profile_states ps
    join public.odyssey_character_weapons source_weapon on source_weapon.id = ps.character_weapon_id
    where source_weapon.character_id = v_source.id
    order by ps.created_at, ps.id
  loop
    v_new_id := gen_random_uuid();
    v_mapped_magazine_id := public.odyssey_try_parse_uuid(v_magazine_map ->> coalesce(v_row.loaded_magazine_id::text, ''));

    insert into public.odyssey_character_weapon_profile_states (
      id,
      character_weapon_id,
      profile_id,
      loaded_magazine_id,
      selected_fire_mode_id,
      is_active,
      data
    )
    values (
      v_new_id,
      public.odyssey_try_parse_uuid(v_weapon_map ->> v_row.character_weapon_id::text),
      v_row.profile_id,
      v_mapped_magazine_id,
      v_row.selected_fire_mode_id,
      v_row.is_active,
      coalesce(v_row.data, '{}'::jsonb)
    );
  end loop;

  for v_row in
    select fs.*
    from public.odyssey_character_weapon_feature_states fs
    join public.odyssey_character_weapons source_weapon on source_weapon.id = fs.character_weapon_id
    where source_weapon.character_id = v_source.id
    order by fs.created_at, fs.id
  loop
    v_new_id := gen_random_uuid();

    insert into public.odyssey_character_weapon_feature_states (
      id,
      character_weapon_id,
      feature_def_id,
      profile_id,
      is_active,
      is_enabled,
      current_charges,
      max_charges,
      recharge_rounds_left,
      cooldown_rounds_left,
      active_rounds_left,
      active_uses_left,
      requires_reload,
      data
    )
    values (
      v_new_id,
      public.odyssey_try_parse_uuid(v_weapon_map ->> v_row.character_weapon_id::text),
      v_row.feature_def_id,
      v_row.profile_id,
      false,
      v_row.is_enabled,
      v_row.current_charges,
      v_row.max_charges,
      case when v_row.recharge_rounds_left is null then null else 0 end,
      case when v_row.cooldown_rounds_left is null then null else 0 end,
      case when v_row.active_rounds_left is null then null else 0 end,
      v_row.active_uses_left,
      v_row.requires_reload,
      coalesce(v_row.data, '{}'::jsonb)
    );
  end loop;

  for v_row in
    select *
    from public.odyssey_character_abilities a
    where a.character_id = v_source.id
    order by a.sort_order, a.created_at, a.id
  loop
    v_new_id := gen_random_uuid();
    v_mapped_skill_id := public.odyssey_try_parse_uuid(v_skill_map ->> coalesce(v_row.character_skill_id::text, ''));
    v_mapped_equipment_id := public.odyssey_try_parse_uuid(v_equipment_map ->> coalesce(v_row.source_equipment_item_id::text, ''));
    v_mapped_item_id := public.odyssey_try_parse_uuid(v_item_map ->> coalesce(v_row.source_character_item_id::text, ''));

    insert into public.odyssey_character_abilities (
      id,
      character_id,
      ability_def_id,
      character_skill_id,
      learned_level,
      source_equipment_item_id,
      source_character_item_id,
      is_enabled,
      is_hidden,
      current_cooldown_rounds,
      current_charges,
      max_charges,
      data,
      notes,
      sort_order
    )
    values (
      v_new_id,
      v_new_character_id,
      v_row.ability_def_id,
      v_mapped_skill_id,
      v_row.learned_level,
      v_mapped_equipment_id,
      v_mapped_item_id,
      v_row.is_enabled,
      v_row.is_hidden,
      0,
      v_row.current_charges,
      v_row.max_charges,
      coalesce(v_row.data, '{}'::jsonb),
      v_row.notes,
      v_row.sort_order
    );
  end loop;

  for v_row in
    select *
    from public.odyssey_character_resource_pools p
    where p.character_id = v_source.id
    order by p.created_at, p.id
  loop
    insert into public.odyssey_character_resource_pools (
      character_id,
      resource_pool_def_id,
      current_value,
      max_value,
      reserved_value,
      data,
      notes
    )
    values (
      v_new_character_id,
      v_row.resource_pool_def_id,
      v_row.current_value,
      v_row.max_value,
      v_row.reserved_value,
      coalesce(v_row.data, '{}'::jsonb),
      v_row.notes
    );
  end loop;

  perform public.initialize_character_rule_defaults(v_new_character_id);
  perform public.initialize_character_combat_defaults(v_new_character_id);

  for v_row in
    select w.id
    from public.odyssey_character_weapons w
    where w.character_id = v_new_character_id
    order by w.sort_order, w.created_at, w.id
  loop
    perform public.initialize_character_weapon_profile_states(v_row.id);
    perform public.initialize_character_weapon_feature_states(v_row.id);
  end loop;

  perform public.recompute_character_armor(v_new_character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_new_character_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_new_character_id,
    'character_key', v_new_character_key,
    'character_bucket', 'npc_active',
    'name', v_new_name,
    'source_template_id', v_source.id,
    'source_template_key', v_template_key,
    'state', public.odyssey_get_character_token_state(v_new_character_id),
    'refresh', v_refresh
  );
end;
$$;

create or replace function public.get_character_spawn_catalog(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language sql
stable
as $$
  with args as (
    select
      coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '') as room_id,
      coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '') as scene_id,
      coalesce(nullif(trim(coalesce(p_payload->>'search', '')), ''), '') as search_text,
      coalesce(nullif(trim(coalesce(p_payload->>'include_active_npc', '')), '')::boolean, false) as include_active_npc
  ),
  active_links as (
    select distinct on (t.character_id)
      t.character_id,
      t.token_id,
      t.token_name,
      t.room_id,
      t.scene_id
    from public.odyssey_token_links t
    cross join args
    where t.is_active = true
      and t.room_id = args.room_id
      and t.scene_id = args.scene_id
    order by t.character_id, t.updated_at desc, t.created_at desc, t.id desc
  ),
  catalog_rows as (
    select
      c.id,
      c.character_key,
      c.character_bucket,
      c.source_template_id,
      c.source_template_key,
      c.enabled,
      c.owner_player_id,
      c.owner_player_name,
      c.resources,
      coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key) as display_name,
      active_links.token_id as linked_token_id,
      active_links.token_name as linked_token_name,
      s.state_version,
      coalesce(nullif(trim(s.status_summary), ''), public.odyssey_build_character_status_summary(c.id)) as status_summary
    from public.odyssey_characters c
    cross join args
    left join active_links on active_links.character_id = c.id
    left join public.odyssey_character_combat_state s on s.character_id = c.id
    where coalesce(c.is_deleted, false) = false
      and c.enabled = true
      and (
        c.character_bucket in ('player', 'npc_template')
        or (args.include_active_npc and c.character_bucket = 'npc_active')
      )
      and (
        args.search_text = ''
        or lower(c.character_key) like '%' || lower(args.search_text) || '%'
        or lower(coalesce(c.resources->>'name', '')) like '%' || lower(args.search_text) || '%'
        or lower(coalesce(c.owner_player_name, '')) like '%' || lower(args.search_text) || '%'
      )
  )
  select jsonb_build_object(
    'ok', true,
    'characters',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', catalog_rows.id,
            'character_key', catalog_rows.character_key,
            'character_bucket', catalog_rows.character_bucket,
            'source_template_id', catalog_rows.source_template_id,
            'source_template_key', catalog_rows.source_template_key,
            'name', catalog_rows.display_name,
            'enabled', catalog_rows.enabled,
            'owner_player_id', catalog_rows.owner_player_id,
            'owner_player_name', catalog_rows.owner_player_name,
            'linked_token_id', catalog_rows.linked_token_id,
            'linked_token_name', catalog_rows.linked_token_name,
            'state_version', coalesce(catalog_rows.state_version, 0),
            'status_summary', coalesce(catalog_rows.status_summary, ''),
            'resources', coalesce(catalog_rows.resources, '{}'::jsonb)
          )
          order by
            case catalog_rows.character_bucket
              when 'player' then 1
              when 'npc_template' then 2
              when 'npc_active' then 3
              else 9
            end,
            catalog_rows.display_name,
            catalog_rows.character_key
        ),
        '[]'::jsonb
      )
  )
  from catalog_rows;
$$;

create or replace function public.get_room_token_links(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language sql
stable
as $$
  with args as (
    select
      coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '') as room_id,
      coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '') as scene_id,
      coalesce(nullif(trim(coalesce(p_payload->>'include_inactive', '')), '')::boolean, false) as include_inactive
  ),
  link_rows as (
    select
      t.id,
      t.campaign_id,
      t.room_id,
      t.scene_id,
      t.token_id,
      t.character_id,
      t.character_key,
      t.token_name,
      t.token_layer,
      t.is_active,
      t.last_seen_at,
      t.created_at,
      t.updated_at,
      c.character_bucket,
      c.source_template_id,
      c.source_template_key,
      coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key, t.character_key) as character_name,
      coalesce(s.state_version, c.active_combat_state_version, 0) as state_version,
      s.updated_at as state_updated_at,
      case
        when c.id is null then ''
        else coalesce(nullif(trim(s.status_summary), ''), public.odyssey_build_character_status_summary(c.id))
      end as status_summary
    from public.odyssey_token_links t
    cross join args
    left join public.odyssey_characters c on c.id = t.character_id
    left join public.odyssey_character_combat_state s on s.character_id = t.character_id
    where t.room_id = args.room_id
      and t.scene_id = args.scene_id
      and (args.include_inactive or t.is_active = true)
  )
  select jsonb_build_object(
    'ok', true,
    'links',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', link_rows.id,
            'campaign_id', link_rows.campaign_id,
            'room_id', link_rows.room_id,
            'scene_id', link_rows.scene_id,
            'token_id', link_rows.token_id,
            'character_id', link_rows.character_id,
            'character_key', link_rows.character_key,
            'character_bucket', link_rows.character_bucket,
            'character_name', link_rows.character_name,
            'source_template_id', link_rows.source_template_id,
            'source_template_key', link_rows.source_template_key,
            'token_name', link_rows.token_name,
            'token_layer', link_rows.token_layer,
            'is_active', link_rows.is_active,
            'state_version', link_rows.state_version,
            'state_updated_at', link_rows.state_updated_at,
            'status_summary', coalesce(link_rows.status_summary, ''),
            'last_seen_at', link_rows.last_seen_at,
            'created_at', link_rows.created_at,
            'updated_at', link_rows.updated_at
          )
          order by link_rows.updated_at desc, link_rows.created_at desc, link_rows.token_name, link_rows.token_id
        ),
        '[]'::jsonb
      )
  )
  from link_rows;
$$;

create or replace function public.deactivate_token_link(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'token_id', '')), ''), '');
  v_link public.odyssey_token_links%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_room_id = '' or v_scene_id = '' or v_token_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'room_id, scene_id and token_id are required.'
    );
  end if;

  select *
  into v_link
  from public.odyssey_token_links t
  where t.room_id = v_room_id
    and t.scene_id = v_scene_id
    and t.token_id = v_token_id
  order by t.updated_at desc, t.created_at desc, t.id desc
  limit 1
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'TOKEN_LINK_NOT_FOUND',
      'message', 'Token link was not found.',
      'room_id', v_room_id,
      'scene_id', v_scene_id,
      'token_id', v_token_id
    );
  end if;

  update public.odyssey_token_links
  set
    is_active = false,
    last_seen_at = v_now,
    updated_at = v_now
  where id = v_link.id;

  return jsonb_build_object(
    'ok', true,
    'token_link',
      jsonb_build_object(
        'id', v_link.id,
        'room_id', v_room_id,
        'scene_id', v_scene_id,
        'token_id', v_token_id,
        'character_id', v_link.character_id,
        'is_active', false
      )
  );
end;
$$;

create or replace function public.load_character_to_token(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_source_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'source_character_id');
  v_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'token_id', '')), ''), '');
  v_token_name text := coalesce(nullif(trim(coalesce(p_payload->>'token_name', '')), ''), '');
  v_token_layer text := coalesce(nullif(trim(coalesce(p_payload->>'token_layer', '')), ''), 'CHARACTER');
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_instance_name text := nullif(trim(coalesce(p_payload->>'instance_name', '')), '');
  v_replace_existing_token_link boolean := coalesce(nullif(trim(coalesce(p_payload->>'replace_existing_token_link', '')), '')::boolean, false);
  v_allow_rebind_active_npc boolean := coalesce(nullif(trim(coalesce(p_payload->>'allow_rebind_active_npc', '')), '')::boolean, false);
  v_requested_action text := lower(coalesce(nullif(trim(coalesce(p_payload->>'requested_action', '')), ''), ''));
  v_now timestamptz := timezone('utc', now());
  v_source public.odyssey_characters%rowtype;
  v_existing_token_link public.odyssey_token_links%rowtype;
  v_conflicting_context_link public.odyssey_token_links%rowtype;
  v_existing_scene_character_link public.odyssey_token_links%rowtype;
  v_target_character public.odyssey_characters%rowtype;
  v_spawn_result jsonb := '{}'::jsonb;
  v_state jsonb := '{}'::jsonb;
  v_action text := '';
  v_target_character_id uuid := null;
  v_selected_link_ids_to_deactivate uuid[] := '{}'::uuid[];
  v_existing_player_link_ids uuid[] := '{}'::uuid[];
  v_existing_active_link_ids uuid[] := '{}'::uuid[];
  v_context_changed boolean := false;
begin
  if v_source_character_id is null or v_token_id = '' or v_room_id = '' or v_scene_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'source_character_id, token_id, room_id and scene_id are required.'
    );
  end if;

  if v_requested_action not in ('', 'bind_player', 'spawn_npc', 'reattach_active_npc', 'bind_direct') then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'requested_action is invalid.'
    );
  end if;

  select *
  into v_source
  from public.odyssey_characters c
  where c.id = v_source_character_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_NOT_FOUND',
      'message', 'Source character was not found.',
      'source_character_id', v_source_character_id
    );
  end if;

  if coalesce(v_source.is_deleted, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_DELETED',
      'message', 'Source character was deleted.',
      'source_character_id', v_source_character_id
    );
  end if;

  if coalesce(v_source.enabled, true) = false then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_CHARACTER_DISABLED',
      'message', 'Source character is disabled.',
      'source_character_id', v_source_character_id
    );
  end if;

  if v_source.character_bucket not in ('player', 'npc_template', 'npc_active') then
    return jsonb_build_object(
      'ok', false,
      'error', 'SOURCE_BUCKET_NOT_SUPPORTED',
      'message', 'Source bucket is not supported.',
      'source_character_id', v_source_character_id,
      'source_bucket', v_source.character_bucket
    );
  end if;

  select *
  into v_conflicting_context_link
  from public.odyssey_token_links t
  where t.token_id = v_token_id
    and t.is_active = true
    and (t.room_id <> v_room_id or t.scene_id <> v_scene_id)
  order by t.updated_at desc, t.created_at desc, t.id desc
  limit 1
  for update;

  if found then
    if not v_replace_existing_token_link then
      return jsonb_build_object(
        'ok', false,
        'error', 'TOKEN_CONTEXT_MISMATCH',
        'message', 'This token is still linked in another room or scene context.',
        'token_id', v_token_id,
        'existing_link',
          jsonb_build_object(
            'room_id', v_conflicting_context_link.room_id,
            'scene_id', v_conflicting_context_link.scene_id,
            'character_id', v_conflicting_context_link.character_id
          )
      );
    end if;

    v_selected_link_ids_to_deactivate := array_append(v_selected_link_ids_to_deactivate, v_conflicting_context_link.id);
  end if;

  select *
  into v_existing_token_link
  from public.odyssey_token_links t
  where t.room_id = v_room_id
    and t.scene_id = v_scene_id
    and t.token_id = v_token_id
    and t.is_active = true
  order by t.updated_at desc, t.created_at desc, t.id desc
  limit 1
  for update;

  if found then
    if not v_replace_existing_token_link then
      return jsonb_build_object(
        'ok', false,
        'error', 'TOKEN_ALREADY_LINKED',
        'message', 'Selected token already has an active character link.',
        'token_link',
          jsonb_build_object(
            'token_id', v_existing_token_link.token_id,
            'character_id', v_existing_token_link.character_id,
            'room_id', v_existing_token_link.room_id,
            'scene_id', v_existing_token_link.scene_id
          )
      );
    end if;

    v_selected_link_ids_to_deactivate := array_append(v_selected_link_ids_to_deactivate, v_existing_token_link.id);
  end if;

  case v_source.character_bucket
    when 'player' then
      if v_requested_action in ('spawn_npc', 'reattach_active_npc') then
        return jsonb_build_object(
          'ok', false,
          'error', 'SOURCE_BUCKET_NOT_SUPPORTED',
          'message', 'Selected action is not valid for a Player source.',
          'source_bucket', v_source.character_bucket,
          'requested_action', v_requested_action
        );
      end if;

      perform 1
      from public.odyssey_token_links t
      where t.character_id = v_source.id
        and t.room_id = v_room_id
        and t.scene_id = v_scene_id
        and t.is_active = true
        and t.token_id <> v_token_id
      for update;

      select
        coalesce(array_agg(t.id order by t.updated_at desc, t.created_at desc, t.id desc), '{}'::uuid[])
      into v_existing_player_link_ids
      from public.odyssey_token_links t
      where t.character_id = v_source.id
        and t.room_id = v_room_id
        and t.scene_id = v_scene_id
        and t.is_active = true
        and t.token_id <> v_token_id;

      if array_length(v_existing_player_link_ids, 1) is not null and not v_replace_existing_token_link then
        select *
        into v_existing_scene_character_link
        from public.odyssey_token_links t
        where t.id = v_existing_player_link_ids[1];

        return jsonb_build_object(
          'ok', false,
          'error', 'CHARACTER_ALREADY_LINKED_IN_SCENE',
          'message', 'Player character is already linked to another token in this scene.',
          'character_id', v_source.id,
          'existing_token_id', v_existing_scene_character_link.token_id
        );
      end if;

      v_target_character_id := v_source.id;
      v_context_changed := coalesce(v_source.campaign_id, '') <> v_campaign_id
        or coalesce(v_source.room_id, '') <> v_room_id;

      if v_context_changed then
        update public.odyssey_characters
        set
          campaign_id = v_campaign_id,
          room_id = v_room_id,
          updated_at = v_now
        where id = v_source.id;

        v_state := public.odyssey_refresh_character_combat_state(v_source.id);
      else
        v_state := public.odyssey_get_character_token_state(v_source.id);
      end if;

      v_action := 'linked_player';

    when 'npc_template' then
      if v_requested_action not in ('', 'spawn_npc') then
        return jsonb_build_object(
          'ok', false,
          'error', 'NPC_TEMPLATE_CANNOT_BE_LINKED_DIRECTLY',
          'message', 'NPC templates must be spawned into a new active NPC before linking.',
          'source_character_id', v_source.id
        );
      end if;

      v_spawn_result := public.odyssey_spawn_npc_active_from_template(
        v_source.id,
        v_instance_name,
        v_campaign_id,
        v_room_id,
        v_scene_id
      );

      if coalesce(nullif(trim(coalesce(v_spawn_result->>'ok', '')), '')::boolean, false) = false then
        return v_spawn_result;
      end if;

      v_target_character_id := public.odyssey_try_parse_uuid(v_spawn_result->>'character_id');
      v_state := coalesce(v_spawn_result->'state', public.odyssey_get_character_token_state(v_target_character_id));
      v_action := 'spawned_npc';

    when 'npc_active' then
      if v_requested_action in ('bind_player', 'spawn_npc', 'bind_direct') then
        return jsonb_build_object(
          'ok', false,
          'error', 'SOURCE_BUCKET_NOT_SUPPORTED',
          'message', 'Selected action is not valid for an active NPC source.',
          'source_bucket', v_source.character_bucket,
          'requested_action', v_requested_action
        );
      end if;

      if not v_allow_rebind_active_npc then
        return jsonb_build_object(
          'ok', false,
          'error', 'NPC_ACTIVE_REBIND_NOT_ALLOWED',
          'message', 'Active NPCs may only be attached through explicit GM reattach mode.',
          'character_id', v_source.id
        );
      end if;

      perform 1
      from public.odyssey_token_links t
      where t.character_id = v_source.id
        and t.is_active = true
        and not (t.room_id = v_room_id and t.scene_id = v_scene_id and t.token_id = v_token_id)
      for update;

      select
        coalesce(array_agg(t.id order by t.updated_at desc, t.created_at desc, t.id desc), '{}'::uuid[])
      into v_existing_active_link_ids
      from public.odyssey_token_links t
      where t.character_id = v_source.id
        and t.is_active = true
        and not (t.room_id = v_room_id and t.scene_id = v_scene_id and t.token_id = v_token_id);

      v_target_character_id := v_source.id;
      v_context_changed := coalesce(v_source.campaign_id, '') <> v_campaign_id
        or coalesce(v_source.room_id, '') <> v_room_id;

      update public.odyssey_characters
      set
        campaign_id = v_campaign_id,
        room_id = v_room_id,
        updated_at = case when v_context_changed then v_now else updated_at end
      where id = v_source.id;

      if v_context_changed then
        v_state := public.odyssey_refresh_character_combat_state(v_source.id);
      else
        v_state := public.odyssey_get_character_token_state(v_source.id);
      end if;

      v_action := 'relinked_active_npc';
  end case;

  update public.odyssey_token_links
  set
    is_active = false,
    last_seen_at = v_now,
    updated_at = v_now
  where id = any(array_remove(v_selected_link_ids_to_deactivate, null));

  if array_length(v_existing_player_link_ids, 1) is not null then
    update public.odyssey_token_links
    set
      is_active = false,
      last_seen_at = v_now,
      updated_at = v_now
    where id = any(v_existing_player_link_ids);
  end if;

  if array_length(v_existing_active_link_ids, 1) is not null then
    update public.odyssey_token_links
    set
      is_active = false,
      last_seen_at = v_now,
      updated_at = v_now
    where id = any(v_existing_active_link_ids);
  end if;

  insert into public.odyssey_token_links (
    campaign_id,
    room_id,
    scene_id,
    token_id,
    character_id,
    character_key,
    token_name,
    token_layer,
    is_active,
    last_seen_at
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_token_id,
    v_target_character_id,
    coalesce(
      nullif(trim(coalesce(v_spawn_result->>'character_key', '')), ''),
      v_source.character_key
    ),
    v_token_name,
    v_token_layer,
    true,
    v_now
  )
  on conflict (room_id, scene_id, token_id) do update
  set
    campaign_id = excluded.campaign_id,
    character_id = excluded.character_id,
    character_key = excluded.character_key,
    token_name = excluded.token_name,
    token_layer = excluded.token_layer,
    is_active = true,
    last_seen_at = excluded.last_seen_at,
    updated_at = v_now;

  select *
  into v_target_character
  from public.odyssey_characters c
  where c.id = v_target_character_id;

  if v_action = 'linked_player' and v_state ? 'combat_state' then
    v_state := public.odyssey_get_character_token_state(v_target_character_id);
  elsif v_action = 'relinked_active_npc' and v_state ? 'combat_state' then
    v_state := public.odyssey_get_character_token_state(v_target_character_id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'action', v_action,
    'source',
      jsonb_build_object(
        'id', v_source.id,
        'bucket', v_source.character_bucket,
        'character_key', v_source.character_key
      ),
    'character',
      jsonb_build_object(
        'id', v_target_character.id,
        'bucket', v_target_character.character_bucket,
        'character_key', v_target_character.character_key,
        'name', coalesce(nullif(trim(v_target_character.resources->>'name'), ''), v_target_character.character_key),
        'source_template_id', v_target_character.source_template_id,
        'source_template_key', v_target_character.source_template_key
      ),
    'token_link',
      jsonb_build_object(
        'token_id', v_token_id,
        'room_id', v_room_id,
        'scene_id', v_scene_id,
        'character_id', v_target_character.id,
        'character_key', v_target_character.character_key,
        'is_active', true
      ),
    'state',
      jsonb_build_object(
        'state_version', coalesce(nullif(jsonb_extract_path_text(v_state, 'state_version'), '')::integer, 0),
        'status_summary', coalesce(nullif(jsonb_extract_path_text(v_state, 'status_summary'), ''), ''),
        'updated_at', jsonb_extract_path_text(v_state, 'updated_at')
      )
  );
end;
$$;

do $$
declare
  v_publication_exists boolean := false;
  v_table_name text;
  v_tables text[] := array[
    'public.odyssey_characters',
    'public.odyssey_token_links',
    'public.odyssey_character_combat_state',
    'public.odyssey_character_effects',
    'public.odyssey_character_body_parts',
    'public.odyssey_character_attributes',
    'public.odyssey_character_skills',
    'public.odyssey_character_perks',
    'public.odyssey_character_equipment_items',
    'public.odyssey_character_items',
    'public.odyssey_character_ammo_stock',
    'public.odyssey_character_weapons',
    'public.odyssey_character_weapon_profile_states',
    'public.odyssey_character_weapon_feature_states',
    'public.odyssey_character_magazines',
    'public.odyssey_character_abilities',
    'public.odyssey_character_resource_pools'
  ];
begin
  select exists(
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  )
  into v_publication_exists;

  if v_publication_exists then
    foreach v_table_name in array v_tables
    loop
      begin
        execute format('alter publication supabase_realtime add table %s', v_table_name);
      exception
        when duplicate_object then
          null;
        when invalid_object_definition then
          null;
        when undefined_table then
          null;
      end;
    end loop;
  end if;
end;
$$;

grant execute on function public.odyssey_build_character_status_summary(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_token_state(uuid) to anon, authenticated;
grant execute on function public.odyssey_spawn_npc_active_from_template(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.get_character_spawn_catalog(jsonb) to anon, authenticated;
grant execute on function public.get_room_token_links(jsonb) to anon, authenticated;
grant execute on function public.deactivate_token_link(jsonb) to anon, authenticated;
grant execute on function public.load_character_to_token(jsonb) to anon, authenticated;
