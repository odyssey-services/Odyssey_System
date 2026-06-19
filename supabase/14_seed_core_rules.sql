insert into public.odyssey_attribute_defs (
  code,
  name,
  default_value,
  max_value,
  cost_per_level,
  description,
  sort_order,
  is_custom
)
values
  ('strength', 'Strength', 8, 15, 2, 'Physical power and brute-force actions.', 10, false),
  ('agility', 'Agility', 8, 15, 2, 'Precision, dexterity, and fine motor control.', 20, false),
  ('reaction', 'Reaction', 8, 15, 2, 'Speed of response, reflexes, and defense timing.', 30, false),
  ('endurance', 'Endurance', 8, 15, 2, 'Stamina, resilience, and physical staying power.', 40, false),
  ('perception', 'Perception', 8, 15, 2, 'Awareness, senses, and noticing details.', 50, false),
  ('intelligence', 'Intelligence', 8, 15, 2, 'Knowledge, analysis, and complex reasoning.', 60, false),
  ('charisma', 'Charisma', 8, 15, 2, 'Presence, leadership, and social influence.', 70, false),
  ('willpower', 'Willpower', 8, 15, 2, 'Mental discipline, focus, and resolve.', 80, false),
  ('psionics', 'Psionics', 0, 15, 3, 'Innate or learned psionic potential.', 90, false)
on conflict (code) do update
set
  name = excluded.name,
  default_value = excluded.default_value,
  max_value = excluded.max_value,
  cost_per_level = excluded.cost_per_level,
  description = excluded.description,
  sort_order = excluded.sort_order,
  is_custom = excluded.is_custom;

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
    'melee',
    'Melee',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    'Close combat skill. Each character may bind its governing attribute to Strength or Agility.',
    '["core","attack_skill","governing-attribute-choice"]'::jsonb,
    false,
    10
  ),
  (
    'parry',
    'Parry',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'reaction'),
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    'Default defense skill for melee defense and timing-based reactions.',
    '["core","defense_skill","default-defense-skill"]'::jsonb,
    false,
    20
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

insert into public.odyssey_skill_level_requirements (
  skill_def_id,
  level,
  main_attribute_required,
  secondary_attribute_required,
  requires_critical_successes,
  notes
)
select
  skill_def.id,
  requirement.level,
  requirement.main_attribute_required,
  requirement.secondary_attribute_required,
  requirement.requires_critical_successes,
  requirement.notes
from public.odyssey_skill_defs skill_def
join (
  values
    (1, 8, null::integer, false, 'Level 1 requires main attribute 8+.'),
    (2, 10, null::integer, false, 'Level 2 requires main attribute 10+.'),
    (3, 12, 10, false, 'Level 3 requires main attribute 12+ and secondary attribute 10+ if the skill uses one.'),
    (4, 14, 11, false, 'Level 4 requires main attribute 14+ and secondary attribute 11+ if the skill uses one.'),
    (5, null::integer, null::integer, true, 'Level 5 requires critical successes and GM approval.')
) as requirement(level, main_attribute_required, secondary_attribute_required, requires_critical_successes, notes)
  on skill_def.max_level = 5
where skill_def.code in ('melee', 'parry')
on conflict (skill_def_id, level) do update
set
  main_attribute_required = excluded.main_attribute_required,
  secondary_attribute_required = excluded.secondary_attribute_required,
  requires_critical_successes = excluded.requires_critical_successes,
  notes = excluded.notes;

insert into public.odyssey_body_part_defs (
  code,
  name,
  category,
  default_max_critical,
  default_armor_slot,
  is_vital,
  can_hold_weapon,
  can_use_item,
  can_be_targeted,
  aim_difficulty,
  serious_counts_as_critical,
  sort_order,
  tags,
  is_custom
)
values
  ('head', 'Head', 'head', 1, 'head', true, false, false, true, 30, true, 10, '["core","vital"]'::jsonb, false),
  ('l_arm', 'L.Arm', 'arm', 2, 'arm', false, true, true, true, 15, false, 20, '["core","limb","left"]'::jsonb, false),
  ('r_arm', 'R.Arm', 'arm', 2, 'arm', false, true, true, true, 15, false, 30, '["core","limb","right"]'::jsonb, false),
  ('torso', 'Torso', 'torso', 3, 'torso', true, false, false, true, 0, false, 40, '["core","vital"]'::jsonb, false),
  ('l_leg', 'L.Leg', 'leg', 2, 'leg', false, false, false, true, 15, false, 50, '["core","limb","left"]'::jsonb, false),
  ('r_leg', 'R.Leg', 'leg', 2, 'leg', false, false, false, true, 15, false, 60, '["core","limb","right"]'::jsonb, false),
  ('shield', 'Shield', 'shield', 1, 'shield', false, false, false, true, 0, false, 70, '["core","defense"]'::jsonb, false),
  ('special', 'Special', 'special', 1, 'special', false, false, false, false, 0, false, 80, '["core","special"]'::jsonb, false)
on conflict (code) do update
set
  name = excluded.name,
  category = excluded.category,
  default_max_critical = excluded.default_max_critical,
  default_armor_slot = excluded.default_armor_slot,
  is_vital = excluded.is_vital,
  can_hold_weapon = excluded.can_hold_weapon,
  can_use_item = excluded.can_use_item,
  can_be_targeted = excluded.can_be_targeted,
  aim_difficulty = excluded.aim_difficulty,
  serious_counts_as_critical = excluded.serious_counts_as_critical,
  sort_order = excluded.sort_order,
  tags = excluded.tags,
  is_custom = excluded.is_custom;
