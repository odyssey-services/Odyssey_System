create or replace function public.roll_characteristic(
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
  v_attribute_def_id_text text := trim(coalesce(v_payload->>'attribute_def_id', ''));
  v_attribute_code text := lower(trim(coalesce(v_payload->>'attribute_code', '')));
  v_manual_bonus_text text := trim(coalesce(v_payload->>'manual_bonus', ''));
  v_manual_penalty_text text := trim(coalesce(v_payload->>'manual_penalty', ''));
  v_reason text := nullif(trim(coalesce(v_payload->>'reason', '')), '');
  v_character_id uuid := null;
  v_attribute_def_id uuid := null;
  v_attribute_id_by_code uuid := null;
  v_attribute_id uuid := null;
  v_attribute_name text := '';
  v_base_value integer := 0;
  v_effect_modifier integer := 0;
  v_effective_value integer := 0;
  v_manual_bonus integer := 0;
  v_manual_penalty integer := 0;
  v_target_value integer := 0;
  v_natural_roll integer := 0;
  v_success boolean := false;
  v_is_critical_success boolean := false;
  v_is_critical_failure boolean := false;
  v_outcome text := 'failure';
  v_effect_summary jsonb := '{}'::jsonb;
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

  if v_attribute_code = '' and v_attribute_def_id_text = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Provide attribute_code or attribute_def_id.'
    );
  end if;

  if v_attribute_def_id_text <> '' then
    if v_attribute_def_id_text !~* v_uuid_pattern then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_PAYLOAD',
        'message', 'attribute_def_id must be a valid UUID.'
      );
    end if;
    v_attribute_def_id := v_attribute_def_id_text::uuid;
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

  if v_attribute_code <> '' then
    select d.id
    into v_attribute_id_by_code
    from public.odyssey_attribute_defs d
    where d.code = v_attribute_code;

    if v_attribute_id_by_code is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'ATTRIBUTE_NOT_FOUND',
        'message', 'Attribute code not found.'
      );
    end if;
  end if;

  if v_attribute_def_id is not null then
    select d.id
    into v_attribute_id
    from public.odyssey_attribute_defs d
    where d.id = v_attribute_def_id;

    if v_attribute_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'ATTRIBUTE_NOT_FOUND',
        'message', 'Attribute id not found.'
      );
    end if;
  end if;

  if v_attribute_id_by_code is not null and v_attribute_id is not null and v_attribute_id_by_code <> v_attribute_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'REFERENCE_MISMATCH',
      'message', 'attribute_code and attribute_def_id refer to different attributes.'
    );
  end if;

  v_attribute_id := coalesce(v_attribute_id, v_attribute_id_by_code);

  select
    d.code,
    d.name,
    a.value
  into
    v_attribute_code,
    v_attribute_name,
    v_base_value
  from public.odyssey_character_attributes a
  join public.odyssey_attribute_defs d on d.id = a.attribute_def_id
  where a.character_id = v_character_id
    and a.attribute_def_id = v_attribute_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ATTRIBUTE_NOT_ASSIGNED',
      'message', 'The character does not have this attribute assigned.'
    );
  end if;

  v_effect_summary := public.get_character_effect_summary(v_character_id);
  v_effect_modifier := coalesce(
    nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'attributes', v_attribute_code), '')::integer,
    0
  );
  v_effective_value := v_base_value + v_effect_modifier;
  v_target_value := v_effective_value + v_manual_bonus - v_manual_penalty;

  v_natural_roll := floor(random() * 20)::integer + 1;

  if v_natural_roll = 1 then
    v_is_critical_success := true;
    v_success := true;
    v_outcome := 'critical_success';
  elsif v_natural_roll = 20 then
    v_is_critical_failure := true;
    v_success := false;
    v_outcome := 'critical_failure';
  elsif v_natural_roll <= v_target_value then
    v_success := true;
    v_outcome := 'success';
  else
    v_success := false;
    v_outcome := 'failure';
  end if;

  return jsonb_build_object(
    'ok', true,
    'check_type', 'characteristic',
    'character_id', v_character_id,
    'reason', v_reason,
    'attribute',
      jsonb_build_object(
        'id', v_attribute_id,
        'code', v_attribute_code,
        'name', v_attribute_name,
        'base_value', v_base_value,
        'effect_modifier', v_effect_modifier,
        'effective_value', v_effective_value
      ),
    'roll',
      jsonb_build_object(
        'die', 'd20',
        'natural_roll', v_natural_roll,
        'manual_bonus', v_manual_bonus,
        'manual_penalty', v_manual_penalty,
        'target_value', v_target_value,
        'comparison', format('%s <= %s', v_natural_roll, v_target_value)
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
  v_skill_name text := '';
  v_base_level integer := 0;
  v_effect_level_modifier integer := 0;
  v_effective_level integer := 0;
  v_skill_bonus integer := 0;
  v_effect_skill_bonus integer := 0;
  v_manual_bonus integer := 0;
  v_manual_penalty integer := 0;
  v_actor_natural_roll integer := 0;
  v_difficulty_roll integer := 0;
  v_actor_total integer := 0;
  v_success boolean := false;
  v_is_critical_success boolean := false;
  v_is_critical_failure boolean := false;
  v_outcome text := 'failure';
  v_is_trained boolean := false;
  v_effect_summary jsonb := '{}'::jsonb;
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

  select
    d.code,
    d.name
  into
    v_skill_code,
    v_skill_name
  from public.odyssey_skill_defs d
  where d.id = v_skill_id;

  select
    s.level
  into v_base_level
  from public.odyssey_character_skills s
  where s.character_id = v_character_id
    and s.skill_def_id = v_skill_id;

  v_is_trained := found;
  if not v_is_trained then
    v_base_level := 0;
  end if;

  v_effect_summary := public.get_character_effect_summary(v_character_id);
  v_effect_level_modifier := coalesce(
    nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'skills', v_skill_code), '')::integer,
    0
  );
  v_effective_level := greatest(v_base_level + v_effect_level_modifier, 0);
  v_skill_bonus := v_effective_level * 10;
  v_effect_skill_bonus := 0;

  v_actor_natural_roll := floor(random() * 100)::integer + 1;
  v_difficulty_roll := floor(random() * 100)::integer + 1;
  v_actor_total := v_actor_natural_roll + v_skill_bonus + v_effect_skill_bonus + v_manual_bonus - v_manual_penalty;

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
        'id', v_skill_id,
        'code', v_skill_code,
        'name', v_skill_name,
        'base_level', v_base_level,
        'effect_level_modifier', v_effect_level_modifier,
        'effective_level', v_effective_level,
        'skill_bonus', v_skill_bonus,
        'effect_skill_bonus', v_effect_skill_bonus,
        'is_trained', v_is_trained
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

create or replace function public.roll_dice(
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_expression text := trim(coalesce(v_payload->>'expression', ''));
  v_reason text := nullif(trim(coalesce(v_payload->>'reason', '')), '');
  v_normalized_expression text := '';
  v_matches text[];
  v_dice_count integer := 1;
  v_sides integer := 0;
  v_roll integer := 0;
  v_rolls integer[] := '{}'::integer[];
  v_total integer := 0;
  v_index integer := 0;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  v_normalized_expression := lower(
    replace(
      replace(v_expression, chr(1044), 'D'),
      chr(1076), 'd'
    )
  );

  if v_normalized_expression = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_DICE_EXPRESSION',
      'message', 'Supported formats: d20, 2d6, 3d10.'
    );
  end if;

  v_matches := regexp_match(v_normalized_expression, '^([0-9]+)?d([0-9]+)$');
  if v_matches is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_DICE_EXPRESSION',
      'message', 'Supported formats: d20, 2d6, 3d10.'
    );
  end if;

  v_dice_count := coalesce(nullif(v_matches[1], '')::integer, 1);
  v_sides := v_matches[2]::integer;

  if v_dice_count < 1 or v_dice_count > 100 or v_sides < 2 or v_sides > 1000 then
    return jsonb_build_object(
      'ok', false,
      'error', 'DICE_LIMIT_EXCEEDED',
      'message', 'Dice count must be between 1 and 100, and die sides must be between 2 and 1000.'
    );
  end if;

  for v_index in 1..v_dice_count loop
    v_roll := floor(random() * v_sides)::integer + 1;
    v_rolls := array_append(v_rolls, v_roll);
    v_total := v_total + v_roll;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'check_type', 'dice',
    'reason', v_reason,
    'expression', v_expression,
    'normalized_expression', format('%sd%s', v_dice_count, v_sides),
    'dice_count', v_dice_count,
    'sides', v_sides,
    'rolls', to_jsonb(v_rolls),
    'total', v_total,
    'minimum_total', v_dice_count,
    'maximum_total', v_dice_count * v_sides
  );
end;
$$;

grant execute on function public.roll_characteristic(jsonb) to anon, authenticated;
grant execute on function public.roll_skill(jsonb) to anon, authenticated;
grant execute on function public.roll_dice(jsonb) to anon, authenticated;
