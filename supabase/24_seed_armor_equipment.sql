insert into public.odyssey_skill_defs (
  code,
  name,
  category,
  max_level,
  main_attribute_id,
  secondary_attribute_id,
  description,
  tags,
  is_custom,
  sort_order
)
values
  (
    'light_armor',
    'Light Armor Training',
    'passive',
    1,
    null,
    null,
    'Passive training for wearing light armor without untrained penalties.',
    '["stage4b","armor","training","passive"]'::jsonb,
    false,
    610
  ),
  (
    'medium_armor',
    'Medium Armor Training',
    'passive',
    1,
    null,
    null,
    'Passive training for wearing medium armor without untrained penalties.',
    '["stage4b","armor","training","passive"]'::jsonb,
    false,
    620
  ),
  (
    'heavy_armor',
    'Heavy Armor Training',
    'passive',
    1,
    null,
    null,
    'Passive training for wearing heavy armor without untrained penalties.',
    '["stage4b","armor","training","passive"]'::jsonb,
    false,
    630
  ),
  (
    'superheavy_armor',
    'Superheavy Armor Training',
    'passive',
    1,
    null,
    null,
    'Passive training for wearing superheavy armor without untrained penalties.',
    '["stage4b","armor","training","passive"]'::jsonb,
    false,
    640
  )
on conflict (code) do update
set
  name = excluded.name,
  category = excluded.category,
  max_level = excluded.max_level,
  main_attribute_id = excluded.main_attribute_id,
  secondary_attribute_id = excluded.secondary_attribute_id,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_armor_class_defs (
  code,
  name,
  min_total_armor,
  max_total_armor,
  required_skill_code,
  trained_penalties,
  untrained_penalties,
  description,
  tags,
  is_custom,
  sort_order
)
values
  (
    'none',
    'None',
    0,
    0,
    null,
    '{}'::jsonb,
    '{}'::jsonb,
    'No equipped armor items contribute to armor class.',
    '["stage4b","armor-class"]'::jsonb,
    false,
    10
  ),
  (
    'light',
    'Light',
    1,
    70,
    'light_armor',
    '{}'::jsonb,
    jsonb_build_object(
      'attribute_modifiers', jsonb_build_object(
        'agility', -1,
        'endurance', -1
      )
    ),
    'Light armor class. Untrained wearers suffer mild agility and endurance penalties.',
    '["stage4b","armor-class","light"]'::jsonb,
    false,
    20
  ),
  (
    'medium',
    'Medium',
    71,
    140,
    'medium_armor',
    jsonb_build_object(
      'skill_modifiers', jsonb_build_object(
        'stealth', -30
      ),
      'movement_m', -3,
      'parry_skill_level_modifier', -1
    ),
    jsonb_build_object(
      'attribute_modifiers', jsonb_build_object(
        'agility', -2,
        'endurance', -2,
        'strength', -2
      )
    ),
    'Medium armor class. Trained wearers take movement, stealth, and parry penalties. Untrained wearers also lose core physical attributes.',
    '["stage4b","armor-class","medium"]'::jsonb,
    false,
    30
  ),
  (
    'heavy',
    'Heavy',
    141,
    260,
    'heavy_armor',
    jsonb_build_object(
      'movement_m', -6,
      'parry_skill_level_modifier', -3,
      'flags', jsonb_build_object(
        'stealth_auto_fail', true
      ),
      'standing_up_costs_action_and_movement', true
    ),
    jsonb_build_object(
      'attribute_modifiers', jsonb_build_object(
        'agility', -4,
        'endurance', -5,
        'strength', -4
      )
    ),
    'Heavy armor class. Trained wearers still lose mobility and stealth. Untrained wearers also suffer large physical penalties.',
    '["stage4b","armor-class","heavy"]'::jsonb,
    false,
    40
  ),
  (
    'superheavy',
    'Superheavy',
    261,
    null,
    'superheavy_armor',
    jsonb_build_object(
      'movement_m', -6,
      'parry_skill_level_modifier', -3,
      'flags', jsonb_build_object(
        'stealth_auto_fail', true
      ),
      'standing_up_costs_action_and_movement', true
    ),
    jsonb_build_object(
      'attribute_modifiers', jsonb_build_object(
        'agility', -4,
        'endurance', -5,
        'strength', -4
      )
    ),
    'Superheavy armor class. Uses the same starting penalty profile as heavy armor in Stage 4B.',
    '["stage4b","armor-class","superheavy"]'::jsonb,
    false,
    50
  )
on conflict (code) do update
set
  name = excluded.name,
  min_total_armor = excluded.min_total_armor,
  max_total_armor = excluded.max_total_armor,
  required_skill_code = excluded.required_skill_code,
  trained_penalties = excluded.trained_penalties,
  untrained_penalties = excluded.untrained_penalties,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_equipment_model_defs (
  code,
  name,
  item_type,
  description,
  armor_value,
  armor_max_critical,
  default_body_part_code,
  can_equip,
  can_equip_to_body_part,
  effect_data,
  flags,
  tags,
  is_custom,
  sort_order
)
values
  (
    'light_helmet',
    'Light Helmet',
    'armor',
    'Starter light head protection.',
    10,
    2,
    'head',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('head')),
    '["stage4b","armor","starter","light"]'::jsonb,
    false,
    110
  ),
  (
    'light_torso_armor',
    'Light Torso Armor',
    'armor',
    'Starter light torso protection.',
    20,
    2,
    'torso',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('torso')),
    '["stage4b","armor","starter","light"]'::jsonb,
    false,
    120
  ),
  (
    'light_arm_guard',
    'Light Arm Guard',
    'armor',
    'Starter light arm protection.',
    10,
    2,
    'l_arm',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_arm', 'r_arm', 'extra_l_arm', 'extra_r_arm')
    ),
    '["stage4b","armor","starter","light"]'::jsonb,
    false,
    130
  ),
  (
    'light_leg_guard',
    'Light Leg Guard',
    'armor',
    'Starter light leg protection.',
    10,
    2,
    'l_leg',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_leg', 'r_leg')
    ),
    '["stage4b","armor","starter","light"]'::jsonb,
    false,
    140
  ),
  (
    'medium_helmet',
    'Medium Helmet',
    'armor',
    'Starter medium head protection.',
    20,
    3,
    'head',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('head')),
    '["stage4b","armor","starter","medium"]'::jsonb,
    false,
    210
  ),
  (
    'medium_torso_armor',
    'Medium Torso Armor',
    'armor',
    'Starter medium torso protection.',
    40,
    3,
    'torso',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('torso')),
    '["stage4b","armor","starter","medium"]'::jsonb,
    false,
    220
  ),
  (
    'medium_arm_guard',
    'Medium Arm Guard',
    'armor',
    'Starter medium arm protection.',
    20,
    3,
    'l_arm',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_arm', 'r_arm', 'extra_l_arm', 'extra_r_arm')
    ),
    '["stage4b","armor","starter","medium"]'::jsonb,
    false,
    230
  ),
  (
    'medium_leg_guard',
    'Medium Leg Guard',
    'armor',
    'Starter medium leg protection.',
    20,
    3,
    'l_leg',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_leg', 'r_leg')
    ),
    '["stage4b","armor","starter","medium"]'::jsonb,
    false,
    240
  ),
  (
    'heavy_helmet',
    'Heavy Helmet',
    'armor',
    'Starter heavy head protection.',
    40,
    5,
    'head',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('head')),
    '["stage4b","armor","starter","heavy"]'::jsonb,
    false,
    310
  ),
  (
    'heavy_torso_armor',
    'Heavy Torso Armor',
    'armor',
    'Starter heavy torso protection.',
    60,
    5,
    'torso',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('torso')),
    '["stage4b","armor","starter","heavy"]'::jsonb,
    false,
    320
  ),
  (
    'heavy_arm_guard',
    'Heavy Arm Guard',
    'armor',
    'Starter heavy arm protection.',
    40,
    5,
    'l_arm',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_arm', 'r_arm', 'extra_l_arm', 'extra_r_arm')
    ),
    '["stage4b","armor","starter","heavy"]'::jsonb,
    false,
    330
  ),
  (
    'heavy_leg_guard',
    'Heavy Leg Guard',
    'armor',
    'Starter heavy leg protection.',
    40,
    5,
    'l_leg',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_leg', 'r_leg')
    ),
    '["stage4b","armor","starter","heavy"]'::jsonb,
    false,
    340
  ),
  (
    'superheavy_helmet',
    'Superheavy Helmet',
    'armor',
    'Starter superheavy head protection.',
    60,
    8,
    'head',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('head')),
    '["stage4b","armor","starter","superheavy"]'::jsonb,
    false,
    410
  ),
  (
    'superheavy_torso_armor',
    'Superheavy Torso Armor',
    'armor',
    'Starter superheavy torso protection.',
    100,
    8,
    'torso',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object('allowed_body_part_codes', jsonb_build_array('torso')),
    '["stage4b","armor","starter","superheavy"]'::jsonb,
    false,
    420
  ),
  (
    'superheavy_arm_guard',
    'Superheavy Arm Guard',
    'armor',
    'Starter superheavy arm protection.',
    60,
    8,
    'l_arm',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_arm', 'r_arm', 'extra_l_arm', 'extra_r_arm')
    ),
    '["stage4b","armor","starter","superheavy"]'::jsonb,
    false,
    430
  ),
  (
    'superheavy_leg_guard',
    'Superheavy Leg Guard',
    'armor',
    'Starter superheavy leg protection.',
    60,
    8,
    'l_leg',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'allowed_body_part_codes',
      jsonb_build_array('l_leg', 'r_leg')
    ),
    '["stage4b","armor","starter","superheavy"]'::jsonb,
    false,
    440
  ),
  (
    'basic_psionic_shield',
    'Basic Psionic Shield',
    'special_protection',
    'Special protection slot item that can prevent helpless execution checks while it still has critical capacity.',
    0,
    1,
    'special',
    true,
    true,
    '{}'::jsonb,
    jsonb_build_object(
      'protects_helpless_execution', true,
      'allowed_body_part_codes', jsonb_build_array('special')
    ),
    '["stage4b","equipment","special-protection"]'::jsonb,
    false,
    510
  ),
  (
    'basic_exoskeleton_frame',
    'Basic Exoskeleton Frame',
    'exoskeleton',
    'Reserved Stage 4B equipment model for future exoskeleton automation.',
    0,
    0,
    'torso',
    true,
    true,
    jsonb_build_object(
      'reserved_for_future', true,
      'notes', 'Stage 4B stores the model and equips it, but does not automatically apply exoskeleton effects yet.'
    ),
    jsonb_build_object(
      'allowed_body_part_codes', jsonb_build_array('torso')
    ),
    '["stage4b","equipment","exoskeleton"]'::jsonb,
    false,
    520
  ),
  (
    'basic_closed_suit',
    'Basic Closed Suit',
    'closed_suit',
    'Reserved Stage 4B equipment model for future closed-suit automation.',
    0,
    0,
    'torso',
    true,
    true,
    jsonb_build_object(
      'reserved_for_future', true,
      'notes', 'Stage 4B stores the model and equips it, but does not automatically apply closed-suit effects yet.'
    ),
    jsonb_build_object(
      'allowed_body_part_codes', jsonb_build_array('torso')
    ),
    '["stage4b","equipment","closed-suit"]'::jsonb,
    false,
    530
  )
on conflict (code) do update
set
  name = excluded.name,
  item_type = excluded.item_type,
  description = excluded.description,
  armor_value = excluded.armor_value,
  armor_max_critical = excluded.armor_max_critical,
  default_body_part_code = excluded.default_body_part_code,
  can_equip = excluded.can_equip,
  can_equip_to_body_part = excluded.can_equip_to_body_part,
  effect_data = excluded.effect_data,
  flags = excluded.flags,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;
