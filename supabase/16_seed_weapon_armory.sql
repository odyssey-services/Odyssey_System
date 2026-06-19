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
    'pistols',
    'Pistols',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    null,
    'Training with handguns and other compact sidearms.',
    '["stage2","combat","ranged","firearm","attack_skill"]'::jsonb,
    false,
    30
  ),
  (
    'smg',
    'SMG',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'perception'),
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    'Short automatic firearms that reward close-range control and target tracking.',
    '["stage2","combat","ranged","firearm","attack_skill"]'::jsonb,
    false,
    40
  ),
  (
    'shotguns',
    'Shotguns',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    (select id from public.odyssey_attribute_defs where code = 'perception'),
    'Large spread weapons that favor power at close and short range.',
    '["stage2","combat","ranged","firearm","attack_skill"]'::jsonb,
    false,
    50
  ),
  (
    'rifles',
    'Rifles',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'perception'),
    null,
    'Precision long guns and standard line-rifle handling.',
    '["stage2","combat","ranged","firearm","attack_skill"]'::jsonb,
    false,
    60
  ),
  (
    'machine_guns',
    'Machine Guns',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    (select id from public.odyssey_attribute_defs where code = 'perception'),
    'Sustained-fire heavy ranged weapons that rely on handling and target control.',
    '["stage2","combat","ranged","firearm","attack_skill"]'::jsonb,
    false,
    70
  ),
  (
    'unarmed_combat',
    'Unarmed Combat',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    'Hand-to-hand combat. Characters can govern it through Strength or Agility per character via governing_attribute_def_id; the remaining attribute is treated as the secondary learning dependency.',
    '["stage2","combat","melee","attack_skill","governing-attribute-choice"]'::jsonb,
    false,
    80
  ),
  (
    'cutting_weapons',
    'Cutting Weapons',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    'Blades, knives, swords, and other cutting melee weapons.',
    '["stage2","combat","melee","attack_skill"]'::jsonb,
    false,
    90
  ),
  (
    'impact_weapons',
    'Impact Weapons',
    'combat',
    5,
    (select id from public.odyssey_attribute_defs where code = 'strength'),
    (select id from public.odyssey_attribute_defs where code = 'agility'),
    'Maces, clubs, hammers, and other blunt-force melee weapons.',
    '["stage2","combat","melee","attack_skill"]'::jsonb,
    false,
    100
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
where skill_def.code in (
  'melee',
  'parry',
  'pistols',
  'smg',
  'shotguns',
  'rifles',
  'machine_guns',
  'unarmed_combat',
  'cutting_weapons',
  'impact_weapons'
)
on conflict (skill_def_id, level) do update
set
  main_attribute_required = excluded.main_attribute_required,
  secondary_attribute_required = excluded.secondary_attribute_required,
  requires_critical_successes = excluded.requires_critical_successes,
  notes = excluded.notes;

insert into public.odyssey_caliber_defs (
  code,
  name,
  base_damage_per_round,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('small_caliber', 'Small Caliber', 1, 'Light ballistic rounds for compact firearms.', '["stage2","ballistic"]'::jsonb, false, 10),
  ('medium_caliber', 'Medium Caliber', 2, 'Standard rifle-class ballistic rounds.', '["stage2","ballistic"]'::jsonb, false, 20),
  ('heavy_caliber', 'Heavy Caliber', 4, 'Large machine-gun or anti-materiel ballistic rounds.', '["stage2","ballistic"]'::jsonb, false, 30),
  ('shotgun_caliber', 'Shotgun Caliber', 10, 'Scattergun shells and heavy close-range payloads.', '["stage2","ballistic","spread"]'::jsonb, false, 40),
  ('sniper_caliber', 'Sniper Caliber', 10, 'High-power precision rifle rounds.', '["stage2","ballistic","precision"]'::jsonb, false, 50),
  ('plasma_small_cell', 'Small Plasma Cell', 30, 'Compact energy cell used by experimental plasma platforms.', '["stage2","energy"]'::jsonb, false, 60)
on conflict (code) do update
set
  name = excluded.name,
  base_damage_per_round = excluded.base_damage_per_round,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_ammo_type_defs (
  caliber_id,
  code,
  name,
  damage_modifier,
  accuracy_modifier,
  armor_pierce,
  description,
  tags,
  is_custom,
  sort_order
)
select
  caliber.id,
  'standard',
  case caliber.code
    when 'small_caliber' then 'Standard Small Caliber Ammo'
    when 'medium_caliber' then 'Standard Medium Caliber Ammo'
    when 'heavy_caliber' then 'Standard Heavy Caliber Ammo'
    when 'shotgun_caliber' then 'Standard Shotgun Shells'
    when 'sniper_caliber' then 'Standard Sniper Ammo'
    when 'plasma_small_cell' then 'Standard Small Plasma Cell'
    else 'Standard Ammo'
  end,
  0,
  0,
  0,
  'Stage 2 seeded default ammunition for this caliber.',
  '["stage2","standard"]'::jsonb,
  false,
  caliber.sort_order
from public.odyssey_caliber_defs caliber
where caliber.code in (
  'small_caliber',
  'medium_caliber',
  'heavy_caliber',
  'shotgun_caliber',
  'sniper_caliber',
  'plasma_small_cell'
)
on conflict (caliber_id, code) do update
set
  name = excluded.name,
  damage_modifier = excluded.damage_modifier,
  accuracy_modifier = excluded.accuracy_modifier,
  armor_pierce = excluded.armor_pierce,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_class_defs (
  code,
  name,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('pistol', 'Pistol', 'Compact sidearms and similar one-handed firearms.', '["stage2","firearm","sidearm"]'::jsonb, false, 10),
  ('smg', 'SMG', 'Short automatic firearms for mobile close-quarters fire.', '["stage2","firearm","automatic"]'::jsonb, false, 20),
  ('shotgun', 'Shotgun', 'Spread weapons optimized for clinch and short range.', '["stage2","firearm","spread"]'::jsonb, false, 30),
  ('rifle', 'Rifle', 'Standard or precision long-gun platforms.', '["stage2","firearm","long-gun"]'::jsonb, false, 40),
  ('machine_gun', 'Machine Gun', 'Sustained-fire heavy firearms.', '["stage2","firearm","heavy"]'::jsonb, false, 50),
  ('melee_weapon', 'Melee Weapon', 'Hand-held non-firearm weapons.', '["stage2","melee"]'::jsonb, false, 60)
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_range_band_defs (
  code,
  name,
  min_distance_m,
  max_distance_m,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('clinch', 'Clinch', 0, 1, 'Adjacent or same-space combat distance.', '["stage2","range"]'::jsonb, false, 10),
  ('short', 'Short', 2, 15, 'Short-range engagement band.', '["stage2","range"]'::jsonb, false, 20),
  ('medium', 'Medium', 16, 50, 'Mid-range engagement band.', '["stage2","range"]'::jsonb, false, 30),
  ('long', 'Long', 51, null, 'Long-range engagement band.', '["stage2","range"]'::jsonb, false, 40)
on conflict (code) do update
set
  name = excluded.name,
  min_distance_m = excluded.min_distance_m,
  max_distance_m = excluded.max_distance_m,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_range_profile_defs (
  code,
  name,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('pistol_profile', 'Pistol Profile', 'Default distance profile for pistols.', '["stage2","range","firearm"]'::jsonb, false, 10),
  ('smg_profile', 'SMG Profile', 'Default distance profile for SMGs.', '["stage2","range","firearm"]'::jsonb, false, 20),
  ('shotgun_profile', 'Shotgun Profile', 'Default distance profile for shotguns.', '["stage2","range","firearm"]'::jsonb, false, 30),
  ('rifle_profile', 'Rifle Profile', 'Default distance profile for rifles.', '["stage2","range","firearm"]'::jsonb, false, 40),
  ('machine_gun_profile', 'Machine Gun Profile', 'Default distance profile for machine guns.', '["stage2","range","firearm"]'::jsonb, false, 50),
  ('sniper_profile', 'Sniper Profile', 'Default distance profile for sniper weapons.', '["stage2","range","firearm"]'::jsonb, false, 60),
  ('melee_profile', 'Melee Profile', 'Default distance profile for melee weapons.', '["stage2","range","melee"]'::jsonb, false, 70)
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_range_profile_modifiers (
  range_profile_id,
  range_band_id,
  scaling_mode,
  flat_modifier,
  scaling_start_modifier,
  scaling_end_modifier,
  notes
)
values
  ((select id from public.odyssey_range_profile_defs where code = 'pistol_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -15, null, null, 'Pistols are awkward in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'pistol_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', 0, null, null, 'Pistol baseline short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'pistol_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', -5, null, null, 'Pistol medium range penalty.'),
  ((select id from public.odyssey_range_profile_defs where code = 'pistol_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'scaling', null, -10, -50, 'Pistol long range scales from -10 toward -50.'),
  ((select id from public.odyssey_range_profile_defs where code = 'smg_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -25, null, null, 'SMGs are difficult to use in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'smg_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', 5, null, null, 'SMGs are favored at short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'smg_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', 0, null, null, 'SMG baseline medium range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'smg_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'scaling', null, -10, -50, 'SMG long range scales from -10 toward -50.'),
  ((select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -25, null, null, 'Shotguns are unwieldy in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', 15, null, null, 'Shotguns excel at short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', -15, null, null, 'Shotgun effectiveness drops at medium range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'flat', -50, null, null, 'Shotguns are nearly ineffective at long range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'rifle_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -30, null, null, 'Rifles are poor in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'rifle_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', 0, null, null, 'Rifle baseline short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'rifle_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', 0, null, null, 'Rifle baseline medium range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'rifle_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'flat', 0, null, null, 'Rifle baseline long range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'machine_gun_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -30, null, null, 'Machine guns are poor in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'machine_gun_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', 0, null, null, 'Machine-gun baseline short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'machine_gun_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', 0, null, null, 'Machine-gun baseline medium range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'machine_gun_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'flat', 0, null, null, 'Machine-gun baseline long range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'sniper_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', -50, null, null, 'Sniper systems are extremely poor in clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'sniper_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', -30, null, null, 'Sniper systems are awkward at short range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'sniper_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', 0, null, null, 'Sniper baseline medium range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'sniper_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'flat', 10, null, null, 'Sniper systems gain advantage at long range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'melee_profile'), (select id from public.odyssey_range_band_defs where code = 'clinch'), 'flat', 0, null, null, 'Melee baseline clinch range.'),
  ((select id from public.odyssey_range_profile_defs where code = 'melee_profile'), (select id from public.odyssey_range_band_defs where code = 'short'), 'flat', -999, null, null, 'Melee attacks are unavailable beyond clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'melee_profile'), (select id from public.odyssey_range_band_defs where code = 'medium'), 'flat', -999, null, null, 'Melee attacks are unavailable beyond clinch.'),
  ((select id from public.odyssey_range_profile_defs where code = 'melee_profile'), (select id from public.odyssey_range_band_defs where code = 'long'), 'flat', -999, null, null, 'Melee attacks are unavailable beyond clinch.')
on conflict (range_profile_id, range_band_id) do update
set
  scaling_mode = excluded.scaling_mode,
  flat_modifier = excluded.flat_modifier,
  scaling_start_modifier = excluded.scaling_start_modifier,
  scaling_end_modifier = excluded.scaling_end_modifier,
  notes = excluded.notes;

insert into public.odyssey_fire_mode_defs (
  code,
  name,
  fixed_rounds,
  min_rounds,
  max_rounds,
  is_random,
  accuracy_modifier,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('single', 'Single', 1, null, null, false, 0, 'Fire a single round.', '["stage2","fire_mode"]'::jsonb, false, 10),
  ('double', 'Double', 2, null, null, false, 0, 'Fire a fixed two-round burst.', '["stage2","fire_mode"]'::jsonb, false, 20),
  ('burst_3', 'Burst 3', 3, null, null, false, 0, 'Fire a fixed three-round burst.', '["stage2","fire_mode"]'::jsonb, false, 30),
  ('burst_5', 'Burst 5', 5, null, null, false, 0, 'Fire a fixed five-round burst.', '["stage2","fire_mode"]'::jsonb, false, 40),
  ('full_auto_random', 'Full Auto Random', null, 6, null, true, 0, 'Randomly fires from 6 rounds up to the current magazine if enough rounds remain.', '["stage2","fire_mode","auto","random"]'::jsonb, false, 50)
on conflict (code) do update
set
  name = excluded.name,
  fixed_rounds = excluded.fixed_rounds,
  min_rounds = excluded.min_rounds,
  max_rounds = excluded.max_rounds,
  is_random = excluded.is_random,
  accuracy_modifier = excluded.accuracy_modifier,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_magazine_defs (
  code,
  name,
  caliber_id,
  capacity,
  description,
  tags,
  is_custom,
  sort_order
)
values
  ('small_pistol_magazine', 'Small Pistol Magazine', (select id from public.odyssey_caliber_defs where code = 'small_caliber'), 12, 'Standard 12-round pistol magazine.', '["stage2","magazine"]'::jsonb, false, 10),
  ('small_smg_magazine', 'Small SMG Magazine', (select id from public.odyssey_caliber_defs where code = 'small_caliber'), 30, 'Standard 30-round SMG magazine.', '["stage2","magazine"]'::jsonb, false, 20),
  ('medium_rifle_magazine', 'Medium Rifle Magazine', (select id from public.odyssey_caliber_defs where code = 'medium_caliber'), 30, 'Standard 30-round rifle magazine.', '["stage2","magazine"]'::jsonb, false, 30),
  ('shotgun_tube', 'Shotgun Tube', (select id from public.odyssey_caliber_defs where code = 'shotgun_caliber'), 6, 'Six-shell shotgun tube or internal loading track.', '["stage2","magazine","tube"]'::jsonb, false, 40),
  ('heavy_machine_gun_box', 'Heavy Machine Gun Box', (select id from public.odyssey_caliber_defs where code = 'heavy_caliber'), 60, 'Sixty-round box feed for machine guns.', '["stage2","magazine","box"]'::jsonb, false, 50),
  ('sniper_magazine', 'Sniper Magazine', (select id from public.odyssey_caliber_defs where code = 'sniper_caliber'), 5, 'Five-round precision rifle magazine.', '["stage2","magazine"]'::jsonb, false, 60),
  ('plasma_small_cell_pack', 'Small Plasma Cell Pack', (select id from public.odyssey_caliber_defs where code = 'plasma_small_cell'), 10, 'Ten-shot compact plasma energy pack.', '["stage2","magazine","energy"]'::jsonb, false, 70)
on conflict (code) do update
set
  name = excluded.name,
  caliber_id = excluded.caliber_id,
  capacity = excluded.capacity,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_model_defs (
  code,
  name,
  weapon_class_id,
  linked_skill_id,
  caliber_id,
  range_profile_id,
  base_accuracy_bonus,
  description,
  tags,
  is_custom,
  sort_order
)
values
  (
    'frontier_pistol',
    'Frontier Pistol',
    (select id from public.odyssey_weapon_class_defs where code = 'pistol'),
    (select id from public.odyssey_skill_defs where code = 'pistols'),
    (select id from public.odyssey_caliber_defs where code = 'small_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'pistol_profile'),
    0,
    'Stage 2 seeded baseline pistol.',
    '["stage2","starter","sidearm"]'::jsonb,
    false,
    10
  ),
  (
    'compact_smg',
    'Compact SMG',
    (select id from public.odyssey_weapon_class_defs where code = 'smg'),
    (select id from public.odyssey_skill_defs where code = 'smg'),
    (select id from public.odyssey_caliber_defs where code = 'small_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'smg_profile'),
    2,
    'Stage 2 seeded baseline SMG.',
    '["stage2","starter","automatic"]'::jsonb,
    false,
    20
  ),
  (
    'frontier_shotgun',
    'Frontier Shotgun',
    (select id from public.odyssey_weapon_class_defs where code = 'shotgun'),
    (select id from public.odyssey_skill_defs where code = 'shotguns'),
    (select id from public.odyssey_caliber_defs where code = 'shotgun_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'),
    0,
    'Stage 2 seeded baseline shotgun.',
    '["stage2","starter","spread"]'::jsonb,
    false,
    30
  ),
  (
    'standard_rifle',
    'Standard Rifle',
    (select id from public.odyssey_weapon_class_defs where code = 'rifle'),
    (select id from public.odyssey_skill_defs where code = 'rifles'),
    (select id from public.odyssey_caliber_defs where code = 'medium_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'rifle_profile'),
    0,
    'Stage 2 seeded baseline rifle.',
    '["stage2","starter","long-gun"]'::jsonb,
    false,
    40
  ),
  (
    'light_machine_gun',
    'Light Machine Gun',
    (select id from public.odyssey_weapon_class_defs where code = 'machine_gun'),
    (select id from public.odyssey_skill_defs where code = 'machine_guns'),
    (select id from public.odyssey_caliber_defs where code = 'heavy_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'machine_gun_profile'),
    0,
    'Stage 2 seeded baseline machine gun.',
    '["stage2","starter","heavy"]'::jsonb,
    false,
    50
  ),
  (
    'combat_knife',
    'Combat Knife',
    (select id from public.odyssey_weapon_class_defs where code = 'melee_weapon'),
    (select id from public.odyssey_skill_defs where code = 'cutting_weapons'),
    null,
    (select id from public.odyssey_range_profile_defs where code = 'melee_profile'),
    0,
    'Stage 2 seeded baseline blade weapon.',
    '["stage2","starter","melee","blade"]'::jsonb,
    false,
    60
  ),
  (
    'shock_baton',
    'Shock Baton',
    (select id from public.odyssey_weapon_class_defs where code = 'melee_weapon'),
    (select id from public.odyssey_skill_defs where code = 'impact_weapons'),
    null,
    (select id from public.odyssey_range_profile_defs where code = 'melee_profile'),
    0,
    'Stage 2 seeded baseline blunt weapon.',
    '["stage2","starter","melee","impact"]'::jsonb,
    false,
    70
  )
on conflict (code) do update
set
  name = excluded.name,
  weapon_class_id = excluded.weapon_class_id,
  linked_skill_id = excluded.linked_skill_id,
  caliber_id = excluded.caliber_id,
  range_profile_id = excluded.range_profile_id,
  base_accuracy_bonus = excluded.base_accuracy_bonus,
  description = excluded.description,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_model_fire_modes (
  weapon_model_id,
  fire_mode_id,
  is_default
)
values
  ((select id from public.odyssey_weapon_model_defs where code = 'frontier_pistol'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'frontier_pistol'), (select id from public.odyssey_fire_mode_defs where code = 'double'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'compact_smg'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'compact_smg'), (select id from public.odyssey_fire_mode_defs where code = 'burst_3'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'compact_smg'), (select id from public.odyssey_fire_mode_defs where code = 'full_auto_random'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'frontier_shotgun'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'standard_rifle'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'standard_rifle'), (select id from public.odyssey_fire_mode_defs where code = 'double'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'light_machine_gun'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'light_machine_gun'), (select id from public.odyssey_fire_mode_defs where code = 'burst_5'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'light_machine_gun'), (select id from public.odyssey_fire_mode_defs where code = 'full_auto_random'), false)
on conflict (weapon_model_id, fire_mode_id) do update
set
  is_default = excluded.is_default;

insert into public.odyssey_weapon_model_magazines (
  weapon_model_id,
  magazine_def_id,
  is_default
)
values
  ((select id from public.odyssey_weapon_model_defs where code = 'frontier_pistol'), (select id from public.odyssey_magazine_defs where code = 'small_pistol_magazine'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'compact_smg'), (select id from public.odyssey_magazine_defs where code = 'small_smg_magazine'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'frontier_shotgun'), (select id from public.odyssey_magazine_defs where code = 'shotgun_tube'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'standard_rifle'), (select id from public.odyssey_magazine_defs where code = 'medium_rifle_magazine'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'light_machine_gun'), (select id from public.odyssey_magazine_defs where code = 'heavy_machine_gun_box'), true)
on conflict (weapon_model_id, magazine_def_id) do update
set
  is_default = excluded.is_default;
