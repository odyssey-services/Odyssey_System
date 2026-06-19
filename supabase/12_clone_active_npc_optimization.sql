create or replace function public.clone_odyssey_npc_active(p_payload jsonb)
returns jsonb
language plpgsql
as $body$
declare
  v_trace_id text := trim(coalesce(p_payload->>'trace_id', ''));
  v_function_name constant text := 'clone_odyssey_npc_active';
  v_total_started_at timestamptz := clock_timestamp();
  v_phase_started_at timestamptz := clock_timestamp();
  v_duration_ms numeric(12,2) := 0;
  v_source_character_id uuid := nullif(trim(coalesce(p_payload->>'source_character_id', '')), '')::uuid;
  v_source record;
  v_new_character_id uuid;
  v_new_character_key text := trim(coalesce(p_payload->>'new_character_key', ''));
  v_new_character_bucket text := case lower(coalesce(p_payload->>'new_character_bucket', 'npc_active'))
    when 'npc_active' then 'npc_active'
    else 'npc_active'
  end;
  v_source_template_key text := trim(coalesce(p_payload->>'source_template_key', ''));
  v_campaign_id text := trim(coalesce(p_payload->>'campaign_id', ''));
  v_room_id text := trim(coalesce(p_payload->>'room_id', ''));
  v_scene_id text := trim(coalesce(p_payload->>'scene_id', ''));
  v_token_id text := trim(coalesce(p_payload->>'token_id', ''));
  v_token_name text := trim(coalesce(p_payload->>'token_name', ''));
  v_token_layer text := trim(coalesce(p_payload->>'token_layer', 'CHARACTER'));
  v_owner_player_id text := trim(coalesce(p_payload->>'owner_player_id', ''));
  v_owner_player_name text := trim(coalesce(p_payload->>'owner_player_name', ''));
  v_recomputed jsonb := '{}'::jsonb;
  v_state_version integer := 0;
  v_token_link jsonb := '{}'::jsonb;
begin
  v_phase_started_at := clock_timestamp();
  if v_source_character_id is null then
    raise exception 'source_character_id is required';
  end if;
  if v_new_character_key = '' then
    raise exception 'new_character_key is required';
  end if;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.start',
    p_phase_name => 'clone_active_npc.start',
    p_trace_id => v_trace_id,
    p_character_id => v_source_character_id,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms,
    p_metadata => jsonb_build_object(
      'new_character_key', v_new_character_key,
      'token_id', v_token_id
    )
  );

  v_phase_started_at := clock_timestamp();
  select *
  into v_source
  from public.odyssey_characters
  where id = v_source_character_id
    and is_deleted = false;

  if not found then
    raise exception 'Source character % was not found', v_source_character_id;
  end if;

  if v_source_template_key = '' then
    v_source_template_key := coalesce(nullif(v_source.source_template_key, ''), v_source.character_key, '');
  end if;
  if v_campaign_id = '' then
    v_campaign_id := coalesce(v_source.campaign_id, '');
  end if;
  if v_room_id = '' then
    v_room_id := coalesce(v_source.room_id, '');
  end if;
  if v_owner_player_id = '' then
    v_owner_player_id := coalesce(v_source.owner_player_id, '');
  end if;
  if v_owner_player_name = '' then
    v_owner_player_name := coalesce(v_source.owner_player_name, '');
  end if;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.load_source',
    p_phase_name => 'clone_active_npc.load_source',
    p_trace_id => v_trace_id,
    p_character_id => v_source_character_id,
    p_character_key => v_source.character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms,
    p_metadata => jsonb_build_object(
      'source_character_bucket', v_source.character_bucket,
      'source_template_key', v_source_template_key
    )
  );

  v_phase_started_at := clock_timestamp();
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
    active_combat_state_version,
    is_deleted
  )
  values (
    v_new_character_key,
    v_new_character_bucket,
    v_source_template_key,
    v_source.enabled,
    v_source.tracker_minor,
    v_source.tracker_serious,
    v_owner_player_id,
    v_owner_player_name,
    v_campaign_id,
    v_room_id,
    coalesce(v_source.resources, '{}'::jsonb),
    0,
    false
  )
  returning id into v_new_character_id;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.insert_character',
    p_phase_name => 'clone_active_npc.insert_character',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms,
    p_metadata => jsonb_build_object(
      'source_character_id', v_source_character_id,
      'source_character_key', v_source.character_key
    )
  );

  v_phase_started_at := clock_timestamp();
  insert into public.odyssey_character_characteristics (
    character_id,
    key,
    label,
    value,
    sort_order
  )
  select
    v_new_character_id,
    c.key,
    c.label,
    c.value,
    c.sort_order
  from public.odyssey_character_characteristics c
  where c.character_id = v_source_character_id;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.copy_characteristics',
    p_phase_name => 'clone_active_npc.copy_characteristics',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms
  );

  v_phase_started_at := clock_timestamp();
  insert into public.odyssey_character_skills (
    character_id,
    name,
    value,
    category,
    strength_bonus,
    sort_order
  )
  select
    v_new_character_id,
    s.name,
    s.value,
    s.category,
    s.strength_bonus,
    s.sort_order
  from public.odyssey_character_skills s
  where s.character_id = v_source_character_id;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.copy_skills',
    p_phase_name => 'clone_active_npc.copy_skills',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms
  );

  v_phase_started_at := clock_timestamp();
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
    v_new_character_id,
    w.weapon_kind,
    w.name,
    w.damage,
    w.accuracy,
    w.ammo_current,
    w.ammo_max,
    w.sort_order
  from public.odyssey_character_weapons w
  where w.character_id = v_source_character_id;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.copy_weapons',
    p_phase_name => 'clone_active_npc.copy_weapons',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms
  );

  v_phase_started_at := clock_timestamp();
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
    v_new_character_id,
    b.part_key,
    b.current_hp,
    b.max_hp,
    b.armor,
    b.minor,
    b.serious,
    coalesce(b.critical, greatest(0, b.max_hp - b.current_hp)),
    coalesce(nullif(b.max_critical, 0), b.max_hp),
    b.destroyed,
    b.disabled,
    b.notes,
    b.sort_order
  from public.odyssey_character_body_parts b
  where b.character_id = v_source_character_id;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.copy_body_parts',
    p_phase_name => 'clone_active_npc.copy_body_parts',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms
  );

  v_phase_started_at := clock_timestamp();
  v_recomputed := public.recompute_odyssey_character_combat_state(v_new_character_id);
  v_state_version := greatest(0, coalesce((v_recomputed->>'state_version')::integer, 0));
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.recompute_combat_state',
    p_phase_name => 'clone_active_npc.recompute_combat_state',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms
  );

  v_phase_started_at := clock_timestamp();
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
    v_new_character_id,
    v_new_character_key,
    v_token_name,
    v_token_layer,
    true,
    timezone('utc', now())
  )
  on conflict (room_id, scene_id, token_id) do update
  set
    campaign_id = excluded.campaign_id,
    character_id = excluded.character_id,
    character_key = excluded.character_key,
    token_name = excluded.token_name,
    token_layer = excluded.token_layer,
    is_active = excluded.is_active,
    last_seen_at = excluded.last_seen_at;
  v_duration_ms := (extract(epoch from clock_timestamp() - v_phase_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.upsert_token_link',
    p_phase_name => 'clone_active_npc.upsert_token_link',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms,
    p_metadata => jsonb_build_object(
      'token_id', v_token_id,
      'token_name', v_token_name
    )
  );

  v_token_link := jsonb_build_object(
    'linked', true,
    'character_id', v_new_character_id,
    'character_key', v_new_character_key,
    'character_bucket', v_new_character_bucket,
    'source_template_key', v_source_template_key,
    'campaign_id', v_campaign_id,
    'room_id', v_room_id,
    'scene_id', v_scene_id,
    'state_version', v_state_version,
    'owner_player_id', v_owner_player_id,
    'owner_player_name', v_owner_player_name
  );

  v_duration_ms := (extract(epoch from clock_timestamp() - v_total_started_at) * 1000)::numeric(12,2);
  perform public.odyssey_debug_perf(
    p_function_name => v_function_name,
    p_span_name => 'clone_active_npc.done',
    p_phase_name => 'clone_active_npc.done',
    p_trace_id => v_trace_id,
    p_character_id => v_new_character_id,
    p_character_key => v_new_character_key,
    p_room_id => v_room_id,
    p_scene_id => v_scene_id,
    p_duration_ms => v_duration_ms,
    p_metadata => jsonb_build_object(
      'source_character_id', v_source_character_id,
      'source_character_key', v_source.character_key,
      'token_id', v_token_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'source_character_id', v_source_character_id,
    'source_character_key', v_source.character_key,
    'character_id', v_new_character_id,
    'character_key', v_new_character_key,
    'campaign_id', v_campaign_id,
    'room_id', v_room_id,
    'combat_state', coalesce(v_recomputed->'combat_state', '{}'::jsonb),
    'token_link', v_token_link
  );
exception
  when others then
    perform public.odyssey_debug_perf(
      p_function_name => v_function_name,
      p_span_name => 'clone_active_npc.error',
      p_phase_name => 'clone_active_npc.error',
      p_trace_id => v_trace_id,
      p_character_id => v_new_character_id,
      p_character_key => v_new_character_key,
      p_room_id => v_room_id,
      p_scene_id => v_scene_id,
      p_level => 'error',
      p_duration_ms => (extract(epoch from clock_timestamp() - v_total_started_at) * 1000)::numeric(12,2),
      p_metadata => jsonb_build_object(
        'message', sqlerrm,
        'source_character_id', coalesce(v_source_character_id::text, ''),
        'token_id', v_token_id
      ),
      p_error_code => sqlstate
    );
    raise;
end;
$body$;

grant execute on function public.clone_odyssey_npc_active(jsonb) to anon, authenticated;
