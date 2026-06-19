create or replace function public.odyssey_overlay_mix_hex_color(
  p_start_hex text,
  p_end_hex text,
  p_ratio numeric
)
returns text
language plpgsql
immutable
as $body$
declare
  v_start text := upper(regexp_replace(coalesce(p_start_hex, ''), '[^0-9A-Fa-f]', '', 'g'));
  v_end text := upper(regexp_replace(coalesce(p_end_hex, ''), '[^0-9A-Fa-f]', '', 'g'));
  v_ratio numeric := greatest(0, least(1, coalesce(p_ratio, 0)));
  v_start_r integer;
  v_start_g integer;
  v_start_b integer;
  v_end_r integer;
  v_end_g integer;
  v_end_b integer;
  v_result_r integer;
  v_result_g integer;
  v_result_b integer;
begin
  if length(v_start) <> 6 then
    v_start := '000000';
  end if;
  if length(v_end) <> 6 then
    v_end := '000000';
  end if;

  v_start_r := get_byte(decode(substr(v_start, 1, 2), 'hex'), 0);
  v_start_g := get_byte(decode(substr(v_start, 3, 2), 'hex'), 0);
  v_start_b := get_byte(decode(substr(v_start, 5, 2), 'hex'), 0);
  v_end_r := get_byte(decode(substr(v_end, 1, 2), 'hex'), 0);
  v_end_g := get_byte(decode(substr(v_end, 3, 2), 'hex'), 0);
  v_end_b := get_byte(decode(substr(v_end, 5, 2), 'hex'), 0);

  v_result_r := greatest(0, least(255, round(v_start_r + ((v_end_r - v_start_r) * v_ratio))::integer));
  v_result_g := greatest(0, least(255, round(v_start_g + ((v_end_g - v_start_g) * v_ratio))::integer));
  v_result_b := greatest(0, least(255, round(v_start_b + ((v_end_b - v_start_b) * v_ratio))::integer));

  return
    '#' ||
    upper(lpad(to_hex(v_result_r), 2, '0')) ||
    upper(lpad(to_hex(v_result_g), 2, '0')) ||
    upper(lpad(to_hex(v_result_b), 2, '0'));
end;
$body$;

create or replace function public.odyssey_overlay_hp_color(
  p_current_hp integer,
  p_max_hp integer,
  p_armor integer default 0
)
returns text
language plpgsql
immutable
as $body$
declare
  v_current_hp integer := greatest(0, coalesce(p_current_hp, 0));
  v_max_hp integer := greatest(0, coalesce(p_max_hp, 0));
  v_armor integer := greatest(0, coalesce(p_armor, 0));
  v_ratio numeric;
begin
  if v_max_hp <= 0 then
    v_ratio := case when v_armor > 0 then 1 else 0 end;
  else
    v_ratio := greatest(0, least(1, v_current_hp::numeric / v_max_hp::numeric));
  end if;

  if v_ratio >= 0.75 then
    return public.odyssey_overlay_mix_hex_color('#FFF243', '#73FF5A', (v_ratio - 0.75) / 0.25);
  end if;
  if v_ratio >= 0.5 then
    return public.odyssey_overlay_mix_hex_color('#FFAF22', '#FFF243', (v_ratio - 0.5) / 0.25);
  end if;
  if v_ratio >= 0.25 then
    return public.odyssey_overlay_mix_hex_color('#AC0004', '#FFAF22', (v_ratio - 0.25) / 0.25);
  end if;
  return public.odyssey_overlay_mix_hex_color('#000000', '#AC0004', v_ratio / 0.25);
end;
$body$;

create or replace function public.odyssey_overlay_special_color(
  p_current_hp integer,
  p_max_hp integer,
  p_armor integer default 0
)
returns text
language plpgsql
immutable
as $body$
declare
  v_current_hp integer := greatest(0, coalesce(p_current_hp, 0));
  v_max_hp integer := greatest(0, coalesce(p_max_hp, 0));
  v_armor integer := greatest(0, coalesce(p_armor, 0));
  v_ratio numeric;
begin
  if v_max_hp > 0 then
    v_ratio := greatest(0, least(1, v_current_hp::numeric / v_max_hp::numeric));
  else
    v_ratio := case when v_current_hp > 0 or v_armor > 0 then 1 else 0 end;
  end if;

  return public.odyssey_overlay_mix_hex_color('#000000', '#57D8FF', v_ratio);
end;
$body$;

create or replace function public.odyssey_overlay_signature(
  p_body_summary jsonb,
  p_visual_version integer default 12
)
returns text
language plpgsql
immutable
as $body$
declare
  v_body_summary jsonb := case
    when jsonb_typeof(p_body_summary) = 'object' then p_body_summary
    else '{}'::jsonb
  end;
  v_visual_version integer := greatest(1, coalesce(p_visual_version, 12));
  v_parts text[] := array[]::text[];
  v_part_name text;
  v_part jsonb;
begin
  foreach v_part_name in array array['Head', 'L.Arm', 'R.Arm', 'Torso', 'L.Leg', 'R.Leg', 'Shield', 'Special']
  loop
    v_part := coalesce(v_body_summary->v_part_name, '{}'::jsonb);
    v_parts := array_append(
      v_parts,
      format(
        '%s:%s:%s:%s:%s:%s',
        v_part_name,
        greatest(0, coalesce((v_part->>'current_hp')::integer, (v_part->>'current')::integer, 0)),
        greatest(0, coalesce((v_part->>'max_hp')::integer, (v_part->>'max')::integer, 0)),
        greatest(0, coalesce((v_part->>'armor')::integer, 0)),
        greatest(0, coalesce((v_part->>'minor')::integer, 0)),
        greatest(0, coalesce((v_part->>'serious')::integer, 0))
      )
    );
  end loop;

  return format('semantic-v%s;%s', v_visual_version, array_to_string(v_parts, ';'));
end;
$body$;

create or replace function public.odyssey_build_overlay_manifest(
  p_body_summary jsonb,
  p_armor_total integer default 0,
  p_state_version integer default 0,
  p_visual_version integer default 12
)
returns jsonb
language plpgsql
immutable
as $body$
declare
  v_body_summary jsonb := case
    when jsonb_typeof(p_body_summary) = 'object' then p_body_summary
    else '{}'::jsonb
  end;
  v_visual_version integer := greatest(1, coalesce(p_visual_version, 12));
  v_state_version integer := greatest(0, coalesce(p_state_version, 0));
  v_armor_total integer := greatest(0, coalesce(p_armor_total, 0));
  v_head jsonb := coalesce(v_body_summary->'Head', '{}'::jsonb);
  v_l_arm jsonb := coalesce(v_body_summary->'L.Arm', '{}'::jsonb);
  v_r_arm jsonb := coalesce(v_body_summary->'R.Arm', '{}'::jsonb);
  v_torso jsonb := coalesce(v_body_summary->'Torso', '{}'::jsonb);
  v_l_leg jsonb := coalesce(v_body_summary->'L.Leg', '{}'::jsonb);
  v_r_leg jsonb := coalesce(v_body_summary->'R.Leg', '{}'::jsonb);
  v_shield jsonb := coalesce(v_body_summary->'Shield', '{}'::jsonb);
  v_special jsonb := coalesce(v_body_summary->'Special', '{}'::jsonb);
  v_signature text := public.odyssey_overlay_signature(v_body_summary, v_visual_version);
  v_special_visible boolean := false;
  v_shield_visible boolean := false;
begin
  v_special_visible :=
    greatest(0, coalesce((v_special->>'max_hp')::integer, (v_special->>'max')::integer, 0)) > 0
    or greatest(0, coalesce((v_special->>'current_hp')::integer, (v_special->>'current')::integer, 0)) > 0
    or greatest(0, coalesce((v_special->>'armor')::integer, 0)) > 0;

  v_shield_visible :=
    greatest(0, coalesce((v_shield->>'max_hp')::integer, (v_shield->>'max')::integer, 0)) > 0
    or greatest(0, coalesce((v_shield->>'current_hp')::integer, (v_shield->>'current')::integer, 0)) > 0
    or greatest(0, coalesce((v_shield->>'armor')::integer, 0)) > 0;

  return jsonb_build_object(
    'armorTotal', v_armor_total,
    'stateVersion', v_state_version,
    'visualVersion', v_visual_version,
    'signature', v_signature,
    'items', jsonb_build_array(
      jsonb_build_object(
        'kind', 'outer-base',
        'fillColor', '#000000',
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'segment-Head',
        'part', 'Head',
        'fillColor', public.odyssey_overlay_hp_color((v_head->>'current_hp')::integer, (v_head->>'max_hp')::integer, (v_head->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'segment-R.Arm',
        'part', 'R.Arm',
        'fillColor', public.odyssey_overlay_hp_color((v_r_arm->>'current_hp')::integer, (v_r_arm->>'max_hp')::integer, (v_r_arm->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'segment-R.Leg',
        'part', 'R.Leg',
        'fillColor', public.odyssey_overlay_hp_color((v_r_leg->>'current_hp')::integer, (v_r_leg->>'max_hp')::integer, (v_r_leg->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'segment-L.Leg',
        'part', 'L.Leg',
        'fillColor', public.odyssey_overlay_hp_color((v_l_leg->>'current_hp')::integer, (v_l_leg->>'max_hp')::integer, (v_l_leg->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'segment-L.Arm',
        'part', 'L.Arm',
        'fillColor', public.odyssey_overlay_hp_color((v_l_arm->>'current_hp')::integer, (v_l_arm->>'max_hp')::integer, (v_l_arm->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'torso-ring',
        'part', 'Torso',
        'fillColor', public.odyssey_overlay_hp_color((v_torso->>'current_hp')::integer, (v_torso->>'max_hp')::integer, (v_torso->>'armor')::integer),
        'visible', true
      ),
      jsonb_build_object(
        'kind', 'special-ring',
        'part', 'Special',
        'fillColor', public.odyssey_overlay_special_color((v_special->>'current_hp')::integer, (v_special->>'max_hp')::integer, (v_special->>'armor')::integer),
        'visible', v_special_visible
      ),
      jsonb_build_object(
        'kind', 'shield-ring',
        'part', 'Shield',
        'fillColor', public.odyssey_overlay_hp_color((v_shield->>'current_hp')::integer, (v_shield->>'max_hp')::integer, (v_shield->>'armor')::integer),
        'visible', v_shield_visible
      )
    )
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
  v_overlay_manifest jsonb := '{}'::jsonb;
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
  v_overlay_manifest := public.odyssey_build_overlay_manifest(
    v_body_summary,
    v_armor_total,
    v_state_version,
    12
  );
  v_overlay_data := jsonb_build_object(
    'lines', to_jsonb(v_overlay_lines)
  ) || v_overlay_manifest;

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
