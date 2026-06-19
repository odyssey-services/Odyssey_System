create or replace function public.odyssey_apply_part_damage(
  p_part jsonb,
  p_damage_kind text,
  p_amount integer default 1
)
returns jsonb
language plpgsql
immutable
as $body$
declare
  v_current_hp integer := greatest(0, coalesce((p_part->>'current_hp')::integer, (p_part->>'current')::integer, 0));
  v_max_hp integer := greatest(0, coalesce((p_part->>'max_hp')::integer, (p_part->>'max')::integer, 0));
  v_armor integer := greatest(0, coalesce((p_part->>'armor')::integer, 0));
  v_minor integer := greatest(0, coalesce((p_part->>'minor')::integer, 0));
  v_serious integer := greatest(0, coalesce((p_part->>'serious')::integer, 0));
  v_max_critical integer := greatest(0, coalesce((p_part->>'max_critical')::integer, v_max_hp));
  v_amount integer := greatest(0, coalesce(p_amount, 1));
  v_promoted_serious integer := 0;
  v_converted_crit integer := 0;
  v_direct_crit integer := 0;
  v_total_crit integer := 0;
begin
  case lower(coalesce(p_damage_kind, 'minor'))
    when 'minor' then
      v_minor := v_minor + v_amount;
    when 'serious' then
      v_serious := v_serious + v_amount;
    when 'critical' then
      v_direct_crit := v_amount;
    when 'hp_delta' then
      v_direct_crit := v_amount;
    else
      v_minor := v_minor + v_amount;
  end case;

  v_promoted_serious := floor(v_minor / 4.0);
  v_minor := v_minor % 4;
  v_serious := v_serious + v_promoted_serious;

  v_converted_crit := floor(v_serious / 2.0);
  v_serious := v_serious % 2;

  v_total_crit := greatest(0, v_direct_crit + v_converted_crit);
  v_current_hp := greatest(0, least(v_max_hp, v_current_hp - v_total_crit));

  return jsonb_build_object(
    'current_hp', v_current_hp,
    'max_hp', v_max_hp,
    'armor', v_armor,
    'minor', v_minor,
    'serious', v_serious,
    'critical', least(v_max_critical, greatest(0, v_max_hp - v_current_hp)),
    'max_critical', v_max_critical,
    'destroyed', v_current_hp <= 0 and v_max_hp > 0,
    'disabled', v_current_hp <= 0 and v_max_hp > 0,
    'crit_applied', v_total_crit,
    'notes', coalesce(p_part->>'notes', '')
  );
end;
$body$;

create or replace function public.odyssey_apply_part_heal(
  p_part jsonb,
  p_heal_kind text,
  p_amount integer default 1
)
returns jsonb
language plpgsql
immutable
as $body$
declare
  v_current_hp integer := greatest(0, coalesce((p_part->>'current_hp')::integer, (p_part->>'current')::integer, 0));
  v_max_hp integer := greatest(0, coalesce((p_part->>'max_hp')::integer, (p_part->>'max')::integer, 0));
  v_armor integer := greatest(0, coalesce((p_part->>'armor')::integer, 0));
  v_minor integer := greatest(0, coalesce((p_part->>'minor')::integer, 0));
  v_serious integer := greatest(0, coalesce((p_part->>'serious')::integer, 0));
  v_max_critical integer := greatest(0, coalesce((p_part->>'max_critical')::integer, v_max_hp));
  v_amount integer := greatest(0, coalesce(p_amount, 1));
begin
  case lower(coalesce(p_heal_kind, 'minor'))
    when 'full_part' then
      v_current_hp := v_max_hp;
      v_minor := 0;
      v_serious := 0;
    when 'critical' then
      v_current_hp := least(v_max_hp, v_current_hp + v_amount);
    when 'hp_delta' then
      v_current_hp := least(v_max_hp, v_current_hp + v_amount);
    when 'serious' then
      v_serious := greatest(0, v_serious - v_amount);
    else
      v_minor := greatest(0, v_minor - v_amount);
  end case;

  return jsonb_build_object(
    'current_hp', v_current_hp,
    'max_hp', v_max_hp,
    'armor', v_armor,
    'minor', v_minor,
    'serious', v_serious,
    'critical', least(v_max_critical, greatest(0, v_max_hp - v_current_hp)),
    'max_critical', v_max_critical,
    'destroyed', v_current_hp <= 0 and v_max_hp > 0,
    'disabled', v_current_hp <= 0 and v_max_hp > 0,
    'crit_applied', 0,
    'notes', coalesce(p_part->>'notes', '')
  );
end;
$body$;

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

create or replace function public.apply_damage(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_actor_character_id uuid := nullif(trim(coalesce(p_payload->>'actor_character_id', '')), '')::uuid;
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_target_part text := coalesce(nullif(trim(coalesce(p_payload->>'target_part', '')), ''), 'Torso');
  v_damage_kind text := lower(coalesce(p_payload->>'damage_kind', 'minor'));
  v_amount integer := greatest(0, coalesce((p_payload->>'amount')::integer, 1));
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_target_row public.odyssey_character_body_parts%rowtype;
  v_special_row public.odyssey_character_body_parts%rowtype;
  v_target_result jsonb := '{}'::jsonb;
  v_special_result jsonb := '{}'::jsonb;
  v_overflow_crit integer := 0;
  v_special_hp_loss integer := 0;
  v_special_crit_applied integer := 0;
  v_recomputed jsonb := '{}'::jsonb;
  v_message text := '';
  v_log_entry jsonb := '{}'::jsonb;
begin
  if v_target_character_id is null then
    raise exception 'target_character_id is required';
  end if;

  if v_target_part not in ('Head', 'L.Arm', 'R.Arm', 'Torso', 'L.Leg', 'R.Leg', 'Shield', 'Special') then
    raise exception 'target_part % is invalid', v_target_part;
  end if;

  select *
  into v_target_row
  from public.odyssey_character_body_parts
  where character_id = v_target_character_id
    and part_key = v_target_part;

  if not found then
    raise exception 'Target part % was not found for character %', v_target_part, v_target_character_id;
  end if;

  select *
  into v_special_row
  from public.odyssey_character_body_parts
  where character_id = v_target_character_id
    and part_key = 'Special';

  if v_target_part <> 'Special'
     and found
     and v_special_row.max_hp > 0
     and v_special_row.current_hp > 0 then
    v_special_result := public.odyssey_apply_part_damage(to_jsonb(v_special_row), v_damage_kind, v_amount);
    v_special_hp_loss := greatest(0, v_special_row.current_hp - coalesce((v_special_result->>'current_hp')::integer, 0));
    v_special_crit_applied := greatest(0, coalesce((v_special_result->>'crit_applied')::integer, 0));
    v_overflow_crit := greatest(0, v_special_crit_applied - v_special_hp_loss);

    update public.odyssey_character_body_parts
    set
      current_hp = coalesce((v_special_result->>'current_hp')::integer, current_hp),
      minor = coalesce((v_special_result->>'minor')::integer, minor),
      serious = coalesce((v_special_result->>'serious')::integer, serious),
      critical = coalesce((v_special_result->>'critical')::integer, critical),
      max_critical = coalesce((v_special_result->>'max_critical')::integer, max_critical),
      destroyed = coalesce((v_special_result->>'destroyed')::boolean, destroyed),
      disabled = coalesce((v_special_result->>'disabled')::boolean, disabled),
      updated_at = timezone('utc', now())
    where character_id = v_target_character_id
      and part_key = 'Special';

    if v_overflow_crit > 0 then
      v_target_result := public.odyssey_apply_part_damage(to_jsonb(v_target_row), 'critical', v_overflow_crit);
    else
      v_target_result := to_jsonb(v_target_row) || jsonb_build_object('crit_applied', 0);
    end if;
  else
    v_target_result := public.odyssey_apply_part_damage(to_jsonb(v_target_row), v_damage_kind, v_amount);
  end if;

  update public.odyssey_character_body_parts
  set
    current_hp = coalesce((v_target_result->>'current_hp')::integer, current_hp),
    minor = coalesce((v_target_result->>'minor')::integer, minor),
    serious = coalesce((v_target_result->>'serious')::integer, serious),
    critical = coalesce((v_target_result->>'critical')::integer, critical),
    max_critical = coalesce((v_target_result->>'max_critical')::integer, max_critical),
    destroyed = coalesce((v_target_result->>'destroyed')::boolean, destroyed),
    disabled = coalesce((v_target_result->>'disabled')::boolean, disabled),
    updated_at = timezone('utc', now())
  where character_id = v_target_character_id
    and part_key = v_target_part;

  v_recomputed := public.recompute_odyssey_character_combat_state(v_target_character_id);
  v_message := format(
    'Damage applied to %s (%s x%s).',
    v_target_part,
    v_damage_kind,
    v_amount
  );

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    actor_character_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_encounter_id,
    v_actor_character_id,
    v_target_character_id,
    'damage',
    v_message,
    jsonb_build_object(
      'target_part', v_target_part,
      'damage_kind', v_damage_kind,
      'amount', v_amount,
      'attack_result', coalesce(p_payload->'attack_result', '{}'::jsonb)
    ),
    v_created_by
  )
  returning jsonb_build_object(
    'event_type', event_type,
    'message', message,
    'created_at', created_at,
    'target_character_id', target_character_id,
    'actor_character_id', actor_character_id
  ) into v_log_entry;

  return jsonb_build_object(
    'ok', true,
    'changed_character_ids', jsonb_build_array(v_target_character_id),
    'target_character_id', v_target_character_id,
    'combat_state', v_recomputed->'combat_state',
    'log_entry', v_log_entry
  );
end;
$body$;

create or replace function public.heal_damage(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_target_part text := coalesce(nullif(trim(coalesce(p_payload->>'target_part', '')), ''), 'Torso');
  v_heal_kind text := lower(coalesce(p_payload->>'heal_kind', 'minor'));
  v_amount integer := greatest(0, coalesce((p_payload->>'amount')::integer, 1));
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_row record;
  v_result jsonb := '{}'::jsonb;
  v_recomputed jsonb := '{}'::jsonb;
  v_log_entry jsonb := '{}'::jsonb;
  v_message text := '';
begin
  if v_target_character_id is null then
    raise exception 'target_character_id is required';
  end if;

  if v_heal_kind = 'full_character' then
    for v_row in
      select *
      from public.odyssey_character_body_parts
      where character_id = v_target_character_id
    loop
      v_result := public.odyssey_apply_part_heal(to_jsonb(v_row), 'full_part', v_amount);
      update public.odyssey_character_body_parts
      set
        current_hp = coalesce((v_result->>'current_hp')::integer, current_hp),
        minor = coalesce((v_result->>'minor')::integer, minor),
        serious = coalesce((v_result->>'serious')::integer, serious),
        critical = coalesce((v_result->>'critical')::integer, critical),
        max_critical = coalesce((v_result->>'max_critical')::integer, max_critical),
        destroyed = coalesce((v_result->>'destroyed')::boolean, destroyed),
        disabled = coalesce((v_result->>'disabled')::boolean, disabled),
        updated_at = timezone('utc', now())
      where character_id = v_target_character_id
        and part_key = v_row.part_key;
    end loop;
    v_message := 'Character fully healed.';
  else
    select *
    into v_row
    from public.odyssey_character_body_parts
    where character_id = v_target_character_id
      and part_key = v_target_part;

    if not found then
      raise exception 'Target part % was not found for character %', v_target_part, v_target_character_id;
    end if;

    if v_heal_kind = 'full_part' then
      v_result := public.odyssey_apply_part_heal(to_jsonb(v_row), 'full_part', v_amount);
    else
      v_result := public.odyssey_apply_part_heal(to_jsonb(v_row), v_heal_kind, v_amount);
    end if;

    update public.odyssey_character_body_parts
    set
      current_hp = coalesce((v_result->>'current_hp')::integer, current_hp),
      minor = coalesce((v_result->>'minor')::integer, minor),
      serious = coalesce((v_result->>'serious')::integer, serious),
      critical = coalesce((v_result->>'critical')::integer, critical),
      max_critical = coalesce((v_result->>'max_critical')::integer, max_critical),
      destroyed = coalesce((v_result->>'destroyed')::boolean, destroyed),
      disabled = coalesce((v_result->>'disabled')::boolean, disabled),
      updated_at = timezone('utc', now())
    where character_id = v_target_character_id
      and part_key = v_target_part;

    v_message := format('Heal applied to %s (%s x%s).', v_target_part, v_heal_kind, v_amount);
  end if;

  v_recomputed := public.recompute_odyssey_character_combat_state(v_target_character_id);

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_encounter_id,
    v_target_character_id,
    'heal',
    v_message,
    jsonb_build_object(
      'target_part', v_target_part,
      'heal_kind', v_heal_kind,
      'amount', v_amount
    ),
    v_created_by
  )
  returning jsonb_build_object(
    'event_type', event_type,
    'message', message,
    'created_at', created_at,
    'target_character_id', target_character_id
  ) into v_log_entry;

  return jsonb_build_object(
    'ok', true,
    'changed_character_ids', jsonb_build_array(v_target_character_id),
    'target_character_id', v_target_character_id,
    'combat_state', v_recomputed->'combat_state',
    'log_entry', v_log_entry
  );
end;
$body$;

create or replace function public.add_effect(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_source_character_id uuid := nullif(trim(coalesce(p_payload->>'source_character_id', '')), '')::uuid;
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_effect_id uuid;
  v_recomputed jsonb := '{}'::jsonb;
  v_log_entry jsonb := '{}'::jsonb;
begin
  if v_target_character_id is null then
    raise exception 'target_character_id is required';
  end if;

  insert into public.odyssey_character_effects (
    character_id,
    effect_key,
    name,
    description,
    source,
    source_character_id,
    duration_type,
    rounds_left,
    data,
    is_active,
    created_by
  )
  values (
    v_target_character_id,
    trim(coalesce(p_payload->>'effect_key', '')),
    coalesce(nullif(trim(coalesce(p_payload->>'name', '')), ''), 'Effect'),
    coalesce(p_payload->>'description', ''),
    coalesce(p_payload->>'source', ''),
    v_source_character_id,
    case lower(coalesce(p_payload->>'duration_type', 'manual'))
      when 'rounds' then 'rounds'
      when 'until_turn_start' then 'until_turn_start'
      when 'until_turn_end' then 'until_turn_end'
      when 'scene' then 'scene'
      else 'manual'
    end,
    nullif(trim(coalesce(p_payload->>'rounds_left', '')), '')::integer,
    case
      when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data'
      else '{}'::jsonb
    end,
    true,
    v_created_by
  )
  returning id into v_effect_id;

  v_recomputed := public.recompute_odyssey_character_combat_state(v_target_character_id);

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    actor_character_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_encounter_id,
    v_source_character_id,
    v_target_character_id,
    'effect_added',
    format('Effect added: %s', coalesce(nullif(trim(coalesce(p_payload->>'name', '')), ''), 'Effect')),
    jsonb_build_object('effect_id', v_effect_id),
    v_created_by
  )
  returning jsonb_build_object(
    'event_type', event_type,
    'message', message,
    'created_at', created_at,
    'target_character_id', target_character_id,
    'actor_character_id', actor_character_id
  ) into v_log_entry;

  return jsonb_build_object(
    'ok', true,
    'changed_character_ids', jsonb_build_array(v_target_character_id),
    'target_character_id', v_target_character_id,
    'combat_state', v_recomputed->'combat_state',
    'log_entry', v_log_entry
  );
end;
$body$;

create or replace function public.remove_effect(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_effect_id uuid := nullif(trim(coalesce(p_payload->>'effect_id', '')), '')::uuid;
  v_effect_key text := trim(coalesce(p_payload->>'effect_key', ''));
  v_remove_all boolean := coalesce((p_payload->>'remove_all_matching')::boolean, false);
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_recomputed jsonb := '{}'::jsonb;
  v_log_entry jsonb := '{}'::jsonb;
begin
  if v_target_character_id is null then
    raise exception 'target_character_id is required';
  end if;

  if v_effect_id is null and v_effect_key = '' then
    raise exception 'effect_id or effect_key is required';
  end if;

  update public.odyssey_character_effects
  set
    is_active = false,
    updated_at = timezone('utc', now())
  where character_id = v_target_character_id
    and (
      (v_effect_id is not null and id = v_effect_id)
      or (
        v_effect_key <> ''
        and effect_key = v_effect_key
        and (v_remove_all or id = (
          select id
          from public.odyssey_character_effects
          where character_id = v_target_character_id
            and effect_key = v_effect_key
            and is_active = true
          order by created_at desc
          limit 1
        ))
      )
    );

  v_recomputed := public.recompute_odyssey_character_combat_state(v_target_character_id);

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_target_character_id,
    'effect_removed',
    'Effect removed.',
    jsonb_build_object(
      'effect_id', v_effect_id,
      'effect_key', v_effect_key,
      'remove_all_matching', v_remove_all
    ),
    v_created_by
  )
  returning jsonb_build_object(
    'event_type', event_type,
    'message', message,
    'created_at', created_at,
    'target_character_id', target_character_id
  ) into v_log_entry;

  return jsonb_build_object(
    'ok', true,
    'changed_character_ids', jsonb_build_array(v_target_character_id),
    'target_character_id', v_target_character_id,
    'combat_state', v_recomputed->'combat_state',
    'log_entry', v_log_entry
  );
end;
$body$;

create or replace function public.roll_initiative(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_entry jsonb;
  v_character_id uuid;
  v_roll_value integer;
  v_bonus_value integer;
  v_reaction_value integer;
  v_active_entry_id uuid;
  v_active_character_id uuid;
  v_entries jsonb := '[]'::jsonb;
begin
  if v_encounter_id is null then
    select id
    into v_encounter_id
    from public.odyssey_combat_encounters
    where campaign_id = v_campaign_id
      and room_id = v_room_id
      and scene_id = v_scene_id
      and status = 'active'
    order by created_at desc
    limit 1;

    if v_encounter_id is null then
      insert into public.odyssey_combat_encounters (
        campaign_id,
        room_id,
        scene_id,
        name,
        status,
        current_round,
        created_by
      )
      values (
        v_campaign_id,
        v_room_id,
        v_scene_id,
        'Combat',
        'active',
        1,
        v_created_by
      )
      returning id into v_encounter_id;
    end if;
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(
      case
        when jsonb_typeof(p_payload->'characters') = 'array' then p_payload->'characters'
        else '[]'::jsonb
      end
    )
  loop
    v_character_id := nullif(trim(coalesce(v_entry->>'character_id', '')), '')::uuid;
    if v_character_id is null then
      continue;
    end if;

    v_roll_value := coalesce((v_entry->>'roll_value')::integer, 0);
    v_bonus_value := coalesce((v_entry->>'bonus_value')::integer, 0);

    select coalesce(value, 0)
    into v_reaction_value
    from public.odyssey_character_characteristics
    where character_id = v_character_id
      and key = 'Reaction'
    limit 1;

    insert into public.odyssey_initiative_entries (
      encounter_id,
      character_id,
      initiative_value,
      reaction_value,
      roll_value,
      bonus_value,
      order_index,
      has_acted,
      is_active
    )
    values (
      v_encounter_id,
      v_character_id,
      v_roll_value + v_reaction_value + v_bonus_value,
      v_reaction_value,
      v_roll_value,
      v_bonus_value,
      0,
      false,
      true
    )
    on conflict (encounter_id, character_id) do update
    set
      initiative_value = excluded.initiative_value,
      reaction_value = excluded.reaction_value,
      roll_value = excluded.roll_value,
      bonus_value = excluded.bonus_value,
      is_active = true,
      has_acted = false;
  end loop;

  with ranked as (
    select
      e.id,
      row_number() over (
        order by e.initiative_value desc, e.reaction_value desc, c.character_key asc, e.id asc
      ) - 1 as next_order_index
    from public.odyssey_initiative_entries e
    join public.odyssey_characters c on c.id = e.character_id
    where e.encounter_id = v_encounter_id
      and e.is_active = true
  )
  update public.odyssey_initiative_entries e
  set order_index = ranked.next_order_index
  from ranked
  where e.id = ranked.id;

  select id, character_id
  into v_active_entry_id, v_active_character_id
  from public.odyssey_initiative_entries
  where encounter_id = v_encounter_id
    and is_active = true
  order by order_index asc
  limit 1;

  update public.odyssey_combat_encounters
  set
    active_entry_id = v_active_entry_id,
    active_character_id = v_active_character_id,
    updated_at = timezone('utc', now())
  where id = v_encounter_id;

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    v_campaign_id,
    v_room_id,
    v_scene_id,
    v_encounter_id,
    'initiative',
    'Initiative rolled.',
    jsonb_build_object('characters', coalesce(p_payload->'characters', '[]'::jsonb)),
    v_created_by
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'character_id', e.character_id,
        'initiative_value', e.initiative_value,
        'reaction_value', e.reaction_value,
        'roll_value', e.roll_value,
        'bonus_value', e.bonus_value,
        'order_index', e.order_index,
        'has_acted', e.has_acted,
        'is_active', e.is_active
      )
      order by e.order_index asc
    ),
    '[]'::jsonb
  )
  into v_entries
  from public.odyssey_initiative_entries e
  join public.odyssey_characters c on c.id = e.character_id
  where e.encounter_id = v_encounter_id;

  return jsonb_build_object(
    'ok', true,
    'encounter', (
      select jsonb_build_object(
        'id', ce.id,
        'campaign_id', ce.campaign_id,
        'room_id', ce.room_id,
        'scene_id', ce.scene_id,
        'name', ce.name,
        'status', ce.status,
        'current_round', ce.current_round,
        'active_character_id', ce.active_character_id,
        'active_entry_id', ce.active_entry_id
      )
      from public.odyssey_combat_encounters ce
      where ce.id = v_encounter_id
    ),
    'entries', v_entries
  );
end;
$body$;

create or replace function public.advance_turn(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_direction text := lower(coalesce(p_payload->>'direction', 'next'));
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_encounter public.odyssey_combat_encounters%rowtype;
  v_total_entries integer := 0;
  v_current_index integer := 0;
  v_next_index integer := 0;
  v_wrapped boolean := false;
  v_active_entry public.odyssey_initiative_entries%rowtype;
  v_changed_character_ids uuid[] := '{}';
  v_changed_states jsonb := '[]'::jsonb;
  v_changed_state jsonb;
begin
  if v_encounter_id is null then
    raise exception 'encounter_id is required';
  end if;

  select *
  into v_encounter
  from public.odyssey_combat_encounters
  where id = v_encounter_id;

  if not found then
    raise exception 'Encounter % was not found', v_encounter_id;
  end if;

  select count(*)
  into v_total_entries
  from public.odyssey_initiative_entries
  where encounter_id = v_encounter_id
    and is_active = true;

  if v_total_entries = 0 then
    raise exception 'No active initiative entries found';
  end if;

  select order_index
  into v_current_index
  from public.odyssey_initiative_entries
  where id = v_encounter.active_entry_id;

  v_current_index := coalesce(v_current_index, 0);

  if v_direction = 'previous' then
    v_next_index := v_current_index - 1;
    if v_next_index < 0 then
      v_next_index := v_total_entries - 1;
    end if;
  else
    update public.odyssey_initiative_entries
    set has_acted = true
    where id = v_encounter.active_entry_id;

    v_next_index := v_current_index + 1;
    if v_next_index >= v_total_entries then
      v_next_index := 0;
      v_wrapped := true;
    end if;
  end if;

  if v_wrapped then
    update public.odyssey_combat_encounters
    set current_round = current_round + 1
    where id = v_encounter_id;

    update public.odyssey_initiative_entries
    set has_acted = false
    where encounter_id = v_encounter_id;

    update public.odyssey_character_effects
    set
      rounds_left = rounds_left - 1,
      is_active = case when rounds_left - 1 <= 0 then false else is_active end,
      updated_at = timezone('utc', now())
    where character_id in (
      select character_id
      from public.odyssey_initiative_entries
      where encounter_id = v_encounter_id
    )
      and is_active = true
      and duration_type = 'rounds'
      and rounds_left is not null;

    select array_agg(distinct character_id)
    into v_changed_character_ids
    from public.odyssey_character_effects
    where updated_at >= timezone('utc', now()) - interval '5 seconds'
      and character_id in (
        select character_id
        from public.odyssey_initiative_entries
        where encounter_id = v_encounter_id
      );
  end if;

  select *
  into v_active_entry
  from public.odyssey_initiative_entries
  where encounter_id = v_encounter_id
    and is_active = true
    and order_index = v_next_index
  limit 1;

  update public.odyssey_combat_encounters
  set
    active_entry_id = v_active_entry.id,
    active_character_id = v_active_entry.character_id,
    updated_at = timezone('utc', now())
  where id = v_encounter_id;

  if coalesce(array_length(v_changed_character_ids, 1), 0) > 0 then
    for v_active_entry in
      select character_id as id
      from unnest(v_changed_character_ids) as character_id
    loop
      v_changed_state := public.recompute_odyssey_character_combat_state(v_active_entry.id);
      v_changed_states := v_changed_states || jsonb_build_array(v_changed_state);
    end loop;
  end if;

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by,
    round_number
  )
  values (
    v_encounter.campaign_id,
    v_encounter.room_id,
    v_encounter.scene_id,
    v_encounter_id,
    v_active_entry.character_id,
    'turn_advanced',
    case when v_direction = 'previous' then 'Turn moved back.' else 'Turn advanced.' end,
    jsonb_build_object(
      'direction', v_direction,
      'wrapped', v_wrapped,
      'active_entry_id', v_active_entry.id
    ),
    v_created_by,
    (select current_round from public.odyssey_combat_encounters where id = v_encounter_id)
  );

  return jsonb_build_object(
    'ok', true,
    'encounter', (
      select jsonb_build_object(
        'id', ce.id,
        'campaign_id', ce.campaign_id,
        'room_id', ce.room_id,
        'scene_id', ce.scene_id,
        'name', ce.name,
        'status', ce.status,
        'current_round', ce.current_round,
        'active_character_id', ce.active_character_id,
        'active_entry_id', ce.active_entry_id
      )
      from public.odyssey_combat_encounters ce
      where ce.id = v_encounter_id
    ),
    'active_entry', jsonb_build_object(
      'id', v_active_entry.id,
      'character_id', v_active_entry.character_id,
      'initiative_value', v_active_entry.initiative_value,
      'reaction_value', v_active_entry.reaction_value,
      'roll_value', v_active_entry.roll_value,
      'bonus_value', v_active_entry.bonus_value,
      'order_index', v_active_entry.order_index,
      'has_acted', v_active_entry.has_acted,
      'is_active', v_active_entry.is_active
    ),
    'changed_character_ids', to_jsonb(coalesce(v_changed_character_ids, '{}'::uuid[])),
    'changed_combat_states', v_changed_states
  );
end;
$body$;
