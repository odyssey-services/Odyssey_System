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

grant execute on function public.roll_dice(jsonb) to anon, authenticated;
