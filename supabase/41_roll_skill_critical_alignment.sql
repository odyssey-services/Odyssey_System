create or replace function public.roll_skill(
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
  v_character_id_text text := trim(coalesce(v_payload->>'character_id', ''));
  v_skill_def_id_text text := trim(coalesce(v_payload->>'skill_def_id', ''));
  v_skill_code text := lower(trim(coalesce(v_payload->>'skill_code', '')));
  v_manual_bonus_text text := trim(coalesce(v_payload->>'manual_bonus', ''));
  v_manual_penalty_text text := trim(coalesce(v_payload->>'manual_penalty', ''));
  v_reason text := nullif(trim(coalesce(v_payload->>'reason', '')), '');
  v_character_id uuid := null;
  v_skill_def_id uuid := null;
  v_skill_id_by_code uuid := null;
  v_skill_id uuid := null;
  v_manual_bonus integer := 0;
  v_manual_penalty integer := 0;
  v_actor_natural_roll integer := 0;
  v_difficulty_roll integer := 0;
  v_actor_total integer := 0;
  v_success boolean := false;
  v_is_critical_success boolean := false;
  v_is_critical_failure boolean := false;
  v_outcome text := 'failure';
  v_skill_state record;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  if v_character_id_text = '' or v_character_id_text !~* v_uuid_pattern then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id is required and must be a valid UUID.'
    );
  end if;
  v_character_id := v_character_id_text::uuid;

  if v_skill_code = '' and v_skill_def_id_text = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Provide skill_code or skill_def_id.'
    );
  end if;

  if v_skill_def_id_text <> '' then
    if v_skill_def_id_text !~* v_uuid_pattern then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'skill_def_id must be a valid UUID.'
      );
    end if;
    v_skill_def_id := v_skill_def_id_text::uuid;
  end if;

  if v_manual_bonus_text <> '' and v_manual_bonus_text !~ '^\d+$' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'manual_bonus must be a positive integer or 0.'
    );
  end if;
  if v_manual_penalty_text <> '' and v_manual_penalty_text !~ '^\d+$' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'manual_penalty must be a positive integer or 0.'
    );
  end if;

  v_manual_bonus := coalesce(nullif(v_manual_bonus_text, '')::integer, 0);
  v_manual_penalty := coalesce(nullif(v_manual_penalty_text, '')::integer, 0);

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'Character not found.'
    );
  end if;

  if v_skill_code <> '' then
    select d.id
    into v_skill_id_by_code
    from public.odyssey_skill_defs d
    where d.code = v_skill_code;

    if v_skill_id_by_code is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'SKILL_NOT_FOUND',
        'message', 'Skill code not found.'
      );
    end if;
  end if;

  if v_skill_def_id is not null then
    select d.id
    into v_skill_id
    from public.odyssey_skill_defs d
    where d.id = v_skill_def_id;

    if v_skill_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'SKILL_NOT_FOUND',
        'message', 'Skill id not found.'
      );
    end if;
  end if;

  if v_skill_id_by_code is not null and v_skill_id is not null and v_skill_id_by_code <> v_skill_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'REFERENCE_MISMATCH',
      'message', 'skill_code and skill_def_id refer to different skills.'
    );
  end if;

  v_skill_id := coalesce(v_skill_id, v_skill_id_by_code);

  select *
  into v_skill_state
  from public.odyssey_get_effective_character_skill_states(v_character_id)
  where skill_def_id = v_skill_id
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'SKILL_NOT_FOUND',
      'message', 'Skill state could not be resolved.'
    );
  end if;

  v_actor_natural_roll := floor(random() * 100)::integer + 1;
  v_difficulty_roll := floor(random() * 100)::integer + 1;
  v_actor_total := v_actor_natural_roll + v_skill_state.skill_bonus + v_skill_state.effect_skill_bonus + v_manual_bonus - v_manual_penalty;

  if v_actor_natural_roll = 100 then
    v_is_critical_success := true;
    v_success := true;
    v_outcome := 'critical_success';
  elsif v_actor_natural_roll = 1 then
    v_is_critical_failure := true;
    v_success := false;
    v_outcome := 'critical_failure';
  elsif v_actor_total >= v_difficulty_roll then
    v_success := true;
    v_outcome := 'success';
  else
    v_success := false;
    v_outcome := 'failure';
  end if;

  return jsonb_build_object(
    'ok', true,
    'check_type', 'skill',
    'character_id', v_character_id,
    'reason', v_reason,
    'skill',
      jsonb_build_object(
        'id', v_skill_state.skill_def_id,
        'character_skill_id', v_skill_state.character_skill_id,
        'code', v_skill_state.skill_code,
        'name', v_skill_state.skill_name,
        'base_level', v_skill_state.purchased_level,
        'purchased_level', v_skill_state.purchased_level,
        'base_effective_level', v_skill_state.base_effective_level,
        'effect_level_modifier', v_skill_state.effect_level_modifier,
        'effective_level', v_skill_state.effective_level,
        'skill_bonus', v_skill_state.skill_bonus,
        'effect_skill_bonus', v_skill_state.effect_skill_bonus,
        'is_trained', v_skill_state.is_trained,
        'is_passive', v_skill_state.is_passive
      ),
    'roll',
      jsonb_build_object(
        'actor_die', 'd100',
        'actor_natural_roll', v_actor_natural_roll,
        'difficulty_die', 'd100',
        'difficulty_roll', v_difficulty_roll,
        'manual_bonus', v_manual_bonus,
        'manual_penalty', v_manual_penalty,
        'actor_total', v_actor_total,
        'comparison', format('%s >= %s', v_actor_total, v_difficulty_roll)
      ),
    'result',
      jsonb_build_object(
        'success', v_success,
        'is_critical_success', v_is_critical_success,
        'is_critical_failure', v_is_critical_failure,
        'outcome', v_outcome
      )
  );
end;
$$;

grant execute on function public.roll_skill(jsonb) to anon, authenticated;
