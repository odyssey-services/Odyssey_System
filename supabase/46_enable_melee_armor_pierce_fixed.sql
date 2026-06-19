-- 46_enable_melee_armor_pierce_fixed.sql
--
-- Enables armor_pierce for melee attacks in odyssey_perform_weapon_attack.
-- Negative armor_pierce is intentionally preserved: it increases effective armor.
--
-- Idempotent: can be safely run more than once.

DO $$
DECLARE
  v_source text;
  v_updated text;

  -- Existing, ranged-only armor calculation. [[:space:]] also matches CRLF/LF.
  v_old_armor_pattern text :=
    'v_effective_armor[[:space:]]*:=[[:space:]]*case[[:space:]]+'
    || 'when[[:space:]]+v_attack_type[[:space:]]*=[[:space:]]*''ranged''[[:space:]]+'
    || 'then[[:space:]]+greatest[[:space:]]*\([[:space:]]*v_raw_armor_value[[:space:]]*'
    || '-[[:space:]]*v_armor_pierce[[:space:]]*,[[:space:]]*0[[:space:]]*\)'
    || '[[:space:]]+else[[:space:]]+v_raw_armor_value[[:space:]]+end[[:space:]]*;';

  -- Desired calculation after migration.
  v_new_armor_pattern text :=
    'v_effective_armor[[:space:]]*:=[[:space:]]*greatest[[:space:]]*'
    || '\([[:space:]]*v_raw_armor_value[[:space:]]*-[[:space:]]*v_armor_pierce'
    || '[[:space:]]*,[[:space:]]*0[[:space:]]*\)[[:space:]]*;';

  -- Existing combat-result field that suppresses melee armor pierce in output.
  v_old_log_pattern text :=
    '''armor_pierce_used''[[:space:]]*,[[:space:]]*case[[:space:]]+'
    || 'when[[:space:]]+v_attack_type[[:space:]]*=[[:space:]]*''ranged''[[:space:]]+'
    || 'then[[:space:]]+v_armor_pierce[[:space:]]+else[[:space:]]+0[[:space:]]+end';

  v_new_log_pattern text :=
    '''armor_pierce_used''[[:space:]]*,[[:space:]]*v_armor_pierce';
BEGIN
  SELECT pg_get_functiondef(
    'public.odyssey_perform_weapon_attack(jsonb)'::regprocedure
  )
  INTO v_source;

  IF v_source IS NULL THEN
    RAISE EXCEPTION 'odyssey_perform_weapon_attack(jsonb) was not found';
  END IF;

  v_updated := v_source;

  IF v_updated ~ v_old_armor_pattern THEN
    v_updated := regexp_replace(
      v_updated,
      v_old_armor_pattern,
      'v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);',
      'g'
    );
  ELSIF v_updated !~ v_new_armor_pattern THEN
    RAISE EXCEPTION
      'Armor calculation could not be recognized. No changes were applied.';
  END IF;

  IF v_updated ~ v_old_log_pattern THEN
    v_updated := regexp_replace(
      v_updated,
      v_old_log_pattern,
      '''armor_pierce_used'', v_armor_pierce',
      'g'
    );
  ELSIF v_updated !~ v_new_log_pattern THEN
    RAISE EXCEPTION
      'Armor-pierce log calculation could not be recognized. No changes were applied.';
  END IF;

  EXECUTE v_updated;
END;
$$;
