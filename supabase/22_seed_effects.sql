insert into public.odyssey_effect_defs (
  code,
  name,
  category,
  description,
  default_duration_type,
  default_rounds,
  stacking_mode,
  is_negative,
  is_narrative,
  data,
  tags,
  is_custom,
  sort_order
)
values
  (
    'stunned',
    'Stunned',
    'condition',
    'Target loses action economy for the turn and becomes helpless.',
    'rounds',
    1,
    'replace',
    true,
    false,
    '{
      "modifiers": [],
      "flags": {
        "skip_main_action": true,
        "skip_movement": true,
        "consumes_full_turn": true,
        "helpless": true
      }
    }'::jsonb,
    '["stage4a","condition","control"]'::jsonb,
    false,
    10
  ),
  (
    'unconscious',
    'Unconscious',
    'condition',
    'Target is unconscious and cannot act until the effect is removed.',
    'manual',
    null,
    'replace',
    true,
    false,
    '{
      "modifiers": [],
      "flags": {
        "skip_main_action": true,
        "skip_movement": true,
        "consumes_full_turn": true,
        "helpless": true
      }
    }'::jsonb,
    '["stage4a","condition","helpless"]'::jsonb,
    false,
    20
  ),
  (
    'suppressed',
    'Suppressed',
    'condition',
    'Suppression reduces offensive output and constrains movement choices.',
    'rounds',
    2,
    'replace',
    true,
    false,
    '{
      "modifiers": [
        {
          "target": "attack_accuracy",
          "value": -25
        }
      ],
      "flags": {
        "suppress_movement": true,
        "cannot_leave_cover": true
      }
    }'::jsonb,
    '["stage4a","condition","suppression"]'::jsonb,
    false,
    30
  ),
  (
    'prepared_aim',
    'Prepared Aim',
    'combat',
    'Prepared action that grants accuracy to the next attack and expires after the attempt.',
    'until_used',
    null,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attack_accuracy",
          "value": 20
        }
      ],
      "flags": {
        "expires_after_attack": true
      }
    }'::jsonb,
    '["stage4a","combat","aim"]'::jsonb,
    false,
    40
  ),
  (
    'myostimulation_1',
    'Myostimulation I',
    'psionic',
    'Minor psionic myostimulation boost.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "strength",
          "value": 5
        },
        {
          "target": "attribute",
          "attribute": "agility",
          "value": 5
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    50
  ),
  (
    'myostimulation_2',
    'Myostimulation II',
    'psionic',
    'Moderate psionic myostimulation boost.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "strength",
          "value": 10
        },
        {
          "target": "attribute",
          "attribute": "agility",
          "value": 10
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    60
  ),
  (
    'myostimulation_3',
    'Myostimulation III',
    'psionic',
    'Major psionic myostimulation boost.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "strength",
          "value": 15
        },
        {
          "target": "attribute",
          "attribute": "agility",
          "value": 15
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    70
  ),
  (
    'sense_focus_1',
    'Sense Focus I',
    'psionic',
    'Minor focus boost for sensory and reaction processing.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "perception",
          "value": 5
        },
        {
          "target": "attribute",
          "attribute": "reaction",
          "value": 5
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    80
  ),
  (
    'sense_focus_2',
    'Sense Focus II',
    'psionic',
    'Moderate focus boost for sensory and reaction processing.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "perception",
          "value": 10
        },
        {
          "target": "attribute",
          "attribute": "reaction",
          "value": 10
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    90
  ),
  (
    'sense_focus_3',
    'Sense Focus III',
    'psionic',
    'Major focus boost for sensory and reaction processing.',
    'rounds',
    2,
    'replace',
    false,
    false,
    '{
      "modifiers": [
        {
          "target": "attribute",
          "attribute": "perception",
          "value": 15
        },
        {
          "target": "attribute",
          "attribute": "reaction",
          "value": 15
        }
      ],
      "flags": {}
    }'::jsonb,
    '["stage4a","psionic","buff"]'::jsonb,
    false,
    100
  ),
  (
    'custom_narrative',
    'Custom Narrative Effect',
    'narrative',
    'Narrative-only effect placeholder for the GM.',
    'manual',
    null,
    'stack',
    false,
    true,
    '{
      "modifiers": [],
      "flags": {},
      "notes": "Narrative-only effect. It is stored and displayed but does not affect calculations by default."
    }'::jsonb,
    '["stage4a","narrative","custom"]'::jsonb,
    false,
    110
  )
on conflict (code) do update
set
  name = excluded.name,
  category = excluded.category,
  description = excluded.description,
  default_duration_type = excluded.default_duration_type,
  default_rounds = excluded.default_rounds,
  stacking_mode = excluded.stacking_mode,
  is_negative = excluded.is_negative,
  is_narrative = excluded.is_narrative,
  data = excluded.data,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;
