create or replace function public.odyssey_is_excluded_virtual_part(
  p_part_code text,
  p_part_key text,
  p_custom_name text
)
returns boolean
language sql
immutable
as $$
  select
    public.odyssey_normalize_part_code(p_part_code) in ('shield', 'special')
    or public.odyssey_normalize_part_code(p_part_key) in ('shield', 'special')
    or public.odyssey_normalize_part_code(p_custom_name) in ('shield', 'special');
$$;

create or replace function public.gm_heal_character(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id_text text := trim(coalesce(p_payload->>'character_id', ''));
  v_character_id uuid := null;
  v_actor text := coalesce(nullif(trim(coalesce(p_payload->>'actor', '')), ''), 'gm');
  v_reason text := coalesce(nullif(trim(coalesce(p_payload->>'reason', '')), ''), 'manual_gm_action');
  v_character public.odyssey_characters%rowtype;
  v_healed_parts integer := 0;
  v_excluded_parts jsonb := '[]'::jsonb;
  v_excluded_part_codes jsonb := '[]'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_state_version integer := 0;
  v_encounter_id uuid := null;
  v_scene_id text := '';
  v_log_id uuid := null;
begin
  if v_character_id_text = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_ID_REQUIRED',
      'message', 'Character ID is required.'
    );
  end if;

  begin
    v_character_id := v_character_id_text::uuid;
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_CHARACTER_ID',
        'message', 'Character ID must be a valid UUID.'
      );
  end;

  select *
  into v_character
  from public.odyssey_characters c
  where c.id = v_character_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character not found.'
    );
  end if;

  update public.odyssey_characters
  set
    enabled = true,
    is_deleted = false,
    updated_at = timezone('utc', now())
  where id = v_character_id;

  with classified_parts as (
    select
      b.id,
      b.sort_order,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as display_name,
      public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      ) as is_excluded
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
  )
  select
    count(*) filter (where not is_excluded),
    coalesce(jsonb_agg(display_name order by sort_order) filter (where is_excluded), '[]'::jsonb),
    coalesce(jsonb_agg(part_code order by sort_order) filter (where is_excluded), '[]'::jsonb)
  into
    v_healed_parts,
    v_excluded_parts,
    v_excluded_part_codes
  from classified_parts;

  with target_parts as (
    select b.id
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
      and not public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      )
  )
  update public.odyssey_character_body_parts b
  set
    minor = 0,
    serious = 0,
    critical = 0,
    disabled = false,
    destroyed = false,
    updated_at = timezone('utc', now())
  from target_parts t
  where b.id = t.id;

  update public.odyssey_character_effects e
  set
    is_active = false,
    rounds_left = 0,
    updated_at = timezone('utc', now())
  where e.character_id = v_character_id
    and e.is_active = true
    and (
      lower(coalesce(e.effect_key, '')) in ('dead', 'dying', 'unconscious', 'knocked_out', 'incapacitated')
      or exists (
        select 1
        from public.odyssey_effect_defs d
        where d.id = e.effect_def_id
          and lower(coalesce(d.code, '')) in ('dead', 'dying', 'unconscious', 'knocked_out', 'incapacitated')
      )
    );

  v_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
  v_state_version := coalesce(
    nullif(jsonb_extract_path_text(v_refresh, 'state_version'), '')::integer,
    nullif(jsonb_extract_path_text(v_refresh, 'combat_state', 'state_version'), '')::integer,
    0
  );

  update public.odyssey_characters
  set
    enabled = true,
    tracker_minor = 0,
    tracker_serious = 0,
    active_combat_state_version = greatest(v_state_version, 0),
    is_deleted = false,
    updated_at = timezone('utc', now())
  where id = v_character_id;

  select
    e.id,
    coalesce(e.scene_id, '')
  into
    v_encounter_id,
    v_scene_id
  from public.odyssey_combat_encounters e
  where e.campaign_id = coalesce(v_character.campaign_id, '')
    and e.room_id = coalesce(v_character.room_id, '')
    and e.status = 'active'
  order by e.updated_at desc, e.created_at desc, e.id desc
  limit 1;

  begin
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
      coalesce(v_character.campaign_id, ''),
      coalesce(v_character.room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      null,
      v_character_id,
      'gm_heal_character',
      'GM healed all body parts.',
      jsonb_build_object(
        'action', 'gm_heal_character',
        'character_id', v_character_id,
        'actor', v_actor,
        'reason', v_reason,
        'healed_parts', v_healed_parts,
        'excluded_parts', v_excluded_part_codes
      ),
      v_actor
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, coalesce(v_character.room_id, ''));
  exception
    when others then
      v_log_id := null;
  end;

  return jsonb_build_object(
    'ok', true,
    'action', 'gm_heal_character',
    'character_id', v_character_id,
    'healed_parts', v_healed_parts,
    'excluded_parts', v_excluded_parts,
    'state_version', v_state_version,
    'log_id', v_log_id
  );
end;
$$;

create or replace function public.gm_repair_character_armor(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id_text text := trim(coalesce(p_payload->>'character_id', ''));
  v_character_id uuid := null;
  v_actor text := coalesce(nullif(trim(coalesce(p_payload->>'actor', '')), ''), 'gm');
  v_reason text := coalesce(nullif(trim(coalesce(p_payload->>'reason', '')), ''), 'manual_gm_action');
  v_character public.odyssey_characters%rowtype;
  v_repaired_parts integer := 0;
  v_excluded_parts jsonb := '[]'::jsonb;
  v_excluded_part_codes jsonb := '[]'::jsonb;
  v_recompute jsonb := '{}'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_state_version integer := 0;
  v_encounter_id uuid := null;
  v_scene_id text := '';
  v_log_id uuid := null;
begin
  if v_character_id_text = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_ID_REQUIRED',
      'message', 'Character ID is required.'
    );
  end if;

  begin
    v_character_id := v_character_id_text::uuid;
  exception
    when invalid_text_representation then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_CHARACTER_ID',
        'message', 'Character ID must be a valid UUID.'
      );
  end;

  select *
  into v_character
  from public.odyssey_characters c
  where c.id = v_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character not found.'
    );
  end if;

  with classified_parts as (
    select
      b.id,
      b.sort_order,
      coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as display_name,
      public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      ) as is_excluded
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
  )
  select
    count(*) filter (where not is_excluded),
    coalesce(jsonb_agg(display_name order by sort_order) filter (where is_excluded), '[]'::jsonb),
    coalesce(jsonb_agg(part_code order by sort_order) filter (where is_excluded), '[]'::jsonb)
  into
    v_repaired_parts,
    v_excluded_parts,
    v_excluded_part_codes
  from classified_parts;

  with target_parts as (
    select b.id
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id
      and not public.odyssey_is_excluded_virtual_part(
        coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
        b.part_key,
        b.custom_name
      )
  )
  update public.odyssey_character_equipment_items e
  set
    armor_critical = 0,
    armor_destroyed = false,
    updated_at = timezone('utc', now())
  where e.character_id = v_character_id
    and e.is_equipped = true
    and e.equipped_body_part_id in (select id from target_parts);

  v_recompute := public.recompute_character_armor(v_character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
  v_state_version := coalesce(
    nullif(jsonb_extract_path_text(v_refresh, 'state_version'), '')::integer,
    nullif(jsonb_extract_path_text(v_refresh, 'combat_state', 'state_version'), '')::integer,
    0
  );

  select
    e.id,
    coalesce(e.scene_id, '')
  into
    v_encounter_id,
    v_scene_id
  from public.odyssey_combat_encounters e
  where e.campaign_id = coalesce(v_character.campaign_id, '')
    and e.room_id = coalesce(v_character.room_id, '')
    and e.status = 'active'
  order by e.updated_at desc, e.created_at desc, e.id desc
  limit 1;

  begin
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
      coalesce(v_character.campaign_id, ''),
      coalesce(v_character.room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      null,
      v_character_id,
      'gm_repair_character_armor',
      'GM repaired all armor parts.',
      jsonb_build_object(
        'action', 'gm_repair_character_armor',
        'character_id', v_character_id,
        'actor', v_actor,
        'reason', v_reason,
        'repaired_parts', v_repaired_parts,
        'excluded_parts', v_excluded_part_codes,
        'armor_refresh', v_recompute
      ),
      v_actor
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, coalesce(v_character.room_id, ''));
  exception
    when others then
      v_log_id := null;
  end;

  return jsonb_build_object(
    'ok', true,
    'action', 'gm_repair_character_armor',
    'character_id', v_character_id,
    'repaired_parts', v_repaired_parts,
    'excluded_parts', v_excluded_parts,
    'state_version', v_state_version,
    'log_id', v_log_id
  );
end;
$$;

grant execute on function public.odyssey_is_excluded_virtual_part(text, text, text) to anon, authenticated;
grant execute on function public.gm_heal_character(jsonb) to anon, authenticated;
grant execute on function public.gm_repair_character_armor(jsonb) to anon, authenticated;
