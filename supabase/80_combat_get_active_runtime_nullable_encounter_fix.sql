create or replace function public.combat_get_active_runtime(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_actor_player_id text := coalesce(nullif(trim(coalesce(p_payload->>'actor_player_id', '')), ''), '');
  v_actor_is_gm boolean := coalesce(nullif(trim(coalesce(p_payload->>'actor_is_gm', '')), '')::boolean, false);
  v_include_hidden boolean := coalesce(nullif(trim(coalesce(p_payload->>'include_hidden', '')), '')::boolean, false);
  v_log_limit integer := greatest(1, least(coalesce(nullif(trim(coalesce(p_payload->>'log_limit', '')), '')::integer, 5), 100));
  v_encounter public.odyssey_combat_encounters;
begin
  if v_room_id = '' or v_scene_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'campaign_id, room_id and scene_id are required.'
    );
  end if;

  select *
  into v_encounter
  from public.odyssey_get_active_encounter(v_campaign_id, v_room_id, v_scene_id);

  if v_encounter.id is null then
    return jsonb_build_object(
      'ok', true,
      'encounter', null,
      'current_turn', null,
      'visible_participants', '[]'::jsonb,
      'viewer_controlled_character_ids', '[]'::jsonb,
      'log', '[]'::jsonb,
      'state_version', 0
    );
  end if;

  return public.odyssey_build_combat_runtime(
    v_encounter.id,
    v_actor_player_id,
    v_actor_is_gm,
    v_include_hidden,
    v_log_limit
  );
end;
$$;
