alter table public.odyssey_characters
  drop column if exists display_name;

alter table public.odyssey_character_combat_state
  drop column if exists display_name;

create or replace function public.recompute_odyssey_character_combat_state(p_character_id uuid)
returns jsonb
language plpgsql
as $body$
declare
  v_character record;
  v_body_summary jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
  v_active_penalties jsonb := '[]'::jsonb;
  v_overlay_lines text[] := array[]::text[];
  v_overlay_text text := '';
  v_overlay_data jsonb := '{}'::jsonb;
  v_armor_total integer := 0;
  v_state_version integer := 1;
  v_tracker_minor integer := 0;
  v_tracker_serious integer := 0;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_head jsonb := '{}'::jsonb;
  v_l_arm jsonb := '{}'::jsonb;
  v_r_arm jsonb := '{}'::jsonb;
  v_torso jsonb := '{}'::jsonb;
  v_l_leg jsonb := '{}'::jsonb;
  v_r_leg jsonb := '{}'::jsonb;
  v_shield jsonb := '{}'::jsonb;
  v_special jsonb := '{}'::jsonb;
begin
  select *
  into v_character
  from public.odyssey_characters
  where id = p_character_id;

  if not found then
    raise exception 'Character % was not found', p_character_id;
  end if;

  select
    coalesce(
      jsonb_object_agg(
        b.part_key,
        jsonb_build_object(
          'current_hp', b.current_hp,
          'max_hp', b.max_hp,
          'armor', b.armor,
          'minor', b.minor,
          'serious', b.serious,
          'critical', greatest(0, coalesce(b.critical, greatest(0, b.max_hp - b.current_hp))),
          'max_critical', coalesce(nullif(b.max_critical, 0), b.max_hp),
          'destroyed', b.destroyed,
          'disabled', b.disabled,
          'notes', b.notes
        )
      ),
      '{}'::jsonb
    ),
    coalesce(sum(b.armor), 0)
  into v_body_summary, v_armor_total
  from public.odyssey_character_body_parts b
  where b.character_id = p_character_id;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'effect_key', e.effect_key,
          'name', e.name,
          'description', e.description,
          'source', e.source,
          'source_character_id', e.source_character_id,
          'duration_type', e.duration_type,
          'rounds_left', e.rounds_left,
          'data', e.data,
          'created_by', e.created_by,
          'created_at', e.created_at
        )
        order by e.created_at desc
      ),
      '[]'::jsonb
    )
  into v_active_effects
  from public.odyssey_character_effects e
  where e.character_id = p_character_id
    and e.is_active = true;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'effect_id', e.id,
          'effect_key', e.effect_key,
          'effect_name', e.name,
          'kind', penalty->>'kind',
          'skill', penalty->>'skill',
          'part_key', penalty->>'part_key',
          'value', coalesce((penalty->>'value')::integer, 0)
        )
        order by e.created_at desc
      ),
      '[]'::jsonb
    )
  into v_active_penalties
  from public.odyssey_character_effects e
  join lateral jsonb_array_elements(
    case
      when jsonb_typeof(e.data->'penalties') = 'array' then e.data->'penalties'
      else '[]'::jsonb
    end
  ) as penalty on true
  where e.character_id = p_character_id
    and e.is_active = true;

  v_head := coalesce(v_body_summary->'Head', '{}'::jsonb);
  v_l_arm := coalesce(v_body_summary->'L.Arm', '{}'::jsonb);
  v_r_arm := coalesce(v_body_summary->'R.Arm', '{}'::jsonb);
  v_torso := coalesce(v_body_summary->'Torso', '{}'::jsonb);
  v_l_leg := coalesce(v_body_summary->'L.Leg', '{}'::jsonb);
  v_r_leg := coalesce(v_body_summary->'R.Leg', '{}'::jsonb);
  v_shield := coalesce(v_body_summary->'Shield', '{}'::jsonb);
  v_special := coalesce(v_body_summary->'Special', '{}'::jsonb);

  if coalesce((v_shield->>'max_hp')::integer, 0) > 0
     or coalesce((v_shield->>'current_hp')::integer, 0) > 0
     or coalesce((v_shield->>'armor')::integer, 0) > 0 then
    v_overlay_lines := array_append(
      v_overlay_lines,
      format(
        'Shield %s/%s(%s)',
        coalesce(v_shield->>'current_hp', '0'),
        coalesce(v_shield->>'max_hp', '0'),
        coalesce(v_shield->>'armor', '0')
      )
    );
  end if;

  if coalesce((v_special->>'max_hp')::integer, 0) > 0
     or coalesce((v_special->>'current_hp')::integer, 0) > 0
     or coalesce((v_special->>'armor')::integer, 0) > 0 then
    v_overlay_lines := array_append(
      v_overlay_lines,
      format(
        'Special %s/%s(%s)',
        coalesce(v_special->>'current_hp', '0'),
        coalesce(v_special->>'max_hp', '0'),
        coalesce(v_special->>'armor', '0')
      )
    );
  end if;

  v_overlay_lines := array_append(
    v_overlay_lines,
    format(
      'Head %s/%s(%s) | L.Arm %s/%s(%s) | R.Arm %s/%s(%s)',
      coalesce(v_head->>'current_hp', '0'),
      coalesce(v_head->>'max_hp', '0'),
      coalesce(v_head->>'armor', '0'),
      coalesce(v_l_arm->>'current_hp', '0'),
      coalesce(v_l_arm->>'max_hp', '0'),
      coalesce(v_l_arm->>'armor', '0'),
      coalesce(v_r_arm->>'current_hp', '0'),
      coalesce(v_r_arm->>'max_hp', '0'),
      coalesce(v_r_arm->>'armor', '0')
    )
  );

  v_overlay_lines := array_append(
    v_overlay_lines,
    format(
      'Torso %s/%s(%s) | L.Leg %s/%s(%s) | R.Leg %s/%s(%s)',
      coalesce(v_torso->>'current_hp', '0'),
      coalesce(v_torso->>'max_hp', '0'),
      coalesce(v_torso->>'armor', '0'),
      coalesce(v_l_leg->>'current_hp', '0'),
      coalesce(v_l_leg->>'max_hp', '0'),
      coalesce(v_l_leg->>'armor', '0'),
      coalesce(v_r_leg->>'current_hp', '0'),
      coalesce(v_r_leg->>'max_hp', '0'),
      coalesce(v_r_leg->>'armor', '0')
    )
  );

  v_overlay_text := array_to_string(v_overlay_lines, E'\n');
  v_tracker_minor := greatest(0, least(4, coalesce(v_character.tracker_minor, 0)));
  v_tracker_serious := greatest(0, least(2, coalesce(v_character.tracker_serious, 0)));

  v_is_alive :=
    greatest(
      coalesce((v_head->>'current_hp')::integer, 0) +
      coalesce((v_l_arm->>'current_hp')::integer, 0) +
      coalesce((v_r_arm->>'current_hp')::integer, 0) +
      coalesce((v_torso->>'current_hp')::integer, 0) +
      coalesce((v_l_leg->>'current_hp')::integer, 0) +
      coalesce((v_r_leg->>'current_hp')::integer, 0),
      0
    ) > 0;

  v_is_conscious :=
    coalesce((v_head->>'current_hp')::integer, 0) > 0
    and coalesce((v_torso->>'current_hp')::integer, 0) > 0;

  select coalesce(state_version, 0) + 1
  into v_state_version
  from public.odyssey_character_combat_state
  where character_id = p_character_id;

  v_state_version := greatest(1, coalesce(v_state_version, 1));
  v_overlay_data := jsonb_build_object(
    'lines', to_jsonb(v_overlay_lines),
    'armorTotal', v_armor_total,
    'stateVersion', v_state_version
  );

  insert into public.odyssey_character_combat_state (
    character_id,
    campaign_id,
    room_id,
    body_summary,
    armor_summary,
    active_effects,
    active_penalties,
    overlay_text,
    overlay_data,
    tracker_minor,
    tracker_serious,
    is_alive,
    is_conscious,
    state_version
  )
  values (
    p_character_id,
    coalesce(v_character.campaign_id, ''),
    coalesce(v_character.room_id, ''),
    v_body_summary,
    jsonb_build_object(
      'total', v_armor_total,
      'parts', v_body_summary
    ),
    v_active_effects,
    v_active_penalties,
    v_overlay_text,
    v_overlay_data,
    v_tracker_minor,
    v_tracker_serious,
    v_is_alive,
    v_is_conscious,
    v_state_version
  )
  on conflict (character_id) do update
  set
    campaign_id = excluded.campaign_id,
    room_id = excluded.room_id,
    body_summary = excluded.body_summary,
    armor_summary = excluded.armor_summary,
    active_effects = excluded.active_effects,
    active_penalties = excluded.active_penalties,
    overlay_text = excluded.overlay_text,
    overlay_data = excluded.overlay_data,
    tracker_minor = excluded.tracker_minor,
    tracker_serious = excluded.tracker_serious,
    is_alive = excluded.is_alive,
    is_conscious = excluded.is_conscious,
    state_version = excluded.state_version
  returning state_version into v_state_version;

  update public.odyssey_characters
  set
    active_combat_state_version = v_state_version,
    updated_at = timezone('utc', now())
  where id = p_character_id;

  return jsonb_build_object(
    'character_id', v_character.id,
    'character_key', v_character.character_key,
    'campaign_id', v_character.campaign_id,
    'room_id', v_character.room_id,
    'state_version', v_state_version,
    'tracker_minor', v_tracker_minor,
    'tracker_serious', v_tracker_serious,
    'combat_state', jsonb_build_object(
      'body_summary', v_body_summary,
      'armor_summary', jsonb_build_object(
        'total', v_armor_total,
        'parts', v_body_summary
      ),
      'active_effects', v_active_effects,
      'active_penalties', v_active_penalties,
      'overlay_text', v_overlay_text,
      'overlay_data', v_overlay_data,
      'is_alive', v_is_alive,
      'is_conscious', v_is_conscious,
      'tracker_minor', v_tracker_minor,
      'tracker_serious', v_tracker_serious,
      'state_version', v_state_version
    )
  );
end;
$body$;

create or replace function public.get_odyssey_character_sheet(p_character_key text)
returns jsonb
language sql
stable
as $body$
  select
    jsonb_build_object(
      'character_id', c.id,
      'character_key', c.character_key,
      'character_bucket', c.character_bucket,
      'source_template_key', c.source_template_key,
      'campaign_id', c.campaign_id,
      'room_id', c.room_id,
      'enabled', c.enabled,
      'tracker_minor', c.tracker_minor,
      'tracker_serious', c.tracker_serious,
      'owner_player_id', c.owner_player_id,
      'owner_player_name', c.owner_player_name,
      'resources', c.resources,
      'characteristics',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'key', a.key,
                'label', a.label,
                'value', a.value,
                'sort_order', a.sort_order
              )
              order by a.sort_order, a.key
            )
            from public.odyssey_character_characteristics a
            where a.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'skills',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'name', s.name,
                'value', s.value,
                'category', s.category,
                'strength_bonus', s.strength_bonus,
                'sort_order', s.sort_order
              )
              order by s.sort_order, s.name
            )
            from public.odyssey_character_skills s
            where s.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'weapons',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'weapon_kind', w.weapon_kind,
                'name', w.name,
                'damage', w.damage,
                'accuracy', w.accuracy,
                'ammoCurrent', w.ammo_current,
                'ammoMax', w.ammo_max,
                'sort_order', w.sort_order
              )
              order by w.weapon_kind, w.sort_order, w.name
            )
            from public.odyssey_character_weapons w
            where w.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'body_parts',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'part_key', b.part_key,
                'current_hp', b.current_hp,
                'max_hp', b.max_hp,
                'armor', b.armor,
                'minor', b.minor,
                'serious', b.serious,
                'critical', b.critical,
                'max_critical', b.max_critical,
                'destroyed', b.destroyed,
                'disabled', b.disabled,
                'notes', b.notes,
                'sort_order', b.sort_order
              )
              order by b.sort_order, b.part_key
            )
            from public.odyssey_character_body_parts b
            where b.character_id = c.id
          ),
          '[]'::jsonb
        )
    )
  from public.odyssey_characters c
  where c.character_key = trim(p_character_key)
    and c.is_deleted = false;
$body$;

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
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
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
    campaign_id,
    room_id,
    resources,
    is_deleted
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
    v_campaign_id,
    v_room_id,
    v_resources,
    false
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
    campaign_id = excluded.campaign_id,
    room_id = excluded.room_id,
    resources = excluded.resources,
    is_deleted = false
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
    critical,
    max_critical,
    destroyed,
    disabled,
    notes,
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
    greatest(0, coalesce((entry.value->>'critical')::integer, 0)),
    greatest(0, coalesce((entry.value->>'max_critical')::integer, (entry.value->>'max_hp')::integer, 0)),
    coalesce((entry.value->>'destroyed')::boolean, false),
    coalesce((entry.value->>'disabled')::boolean, false),
    coalesce(entry.value->>'notes', ''),
    coalesce((entry.value->>'sort_order')::integer, entry.ordinality - 1)
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_payload->'body_parts') = 'array' then p_payload->'body_parts'
      else '[]'::jsonb
    end
  ) with ordinality as entry(value, ordinality)
  where trim(coalesce(entry.value->>'part_key', '')) in ('Head', 'L.Arm', 'R.Arm', 'Torso', 'L.Leg', 'R.Leg', 'Shield', 'Special');

  perform public.recompute_odyssey_character_combat_state(v_character_id);

  return public.get_odyssey_character_sheet(v_character_key);
end;
$body$;

grant execute on function public.get_odyssey_character_sheet(text) to anon, authenticated;
grant execute on function public.upsert_odyssey_character_sheet(jsonb) to anon, authenticated;
