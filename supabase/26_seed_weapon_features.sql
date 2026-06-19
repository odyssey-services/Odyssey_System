insert into public.odyssey_weapon_feature_defs (
  code,
  name,
  feature_type,
  activation_type,
  description,
  default_max_charges,
  default_current_charges,
  default_recharge_rounds,
  default_cooldown_rounds,
  default_active_rounds,
  default_active_uses,
  requires_reload_item_code,
  data,
  effect_data,
  tags,
  is_custom,
  sort_order
)
values
  (
    'plasma_edge',
    'Plasma Edge',
    'duration',
    'manual',
    'Temporarily overcharges a melee edge, adding damage and armor pierce for the next two attack attempts.',
    1,
    1,
    null,
    null,
    null,
    2,
    'small_energy_cell',
    '{
      "modifiers": [
        {
          "target": "damage",
          "value": 10
        },
        {
          "target": "armor_pierce",
          "value": 20
        }
      ],
      "conditions": {
        "attack_type": "melee"
      },
      "notes": "Works for the next 2 attack attempts with this weapon. After that it requires replacing a small energy cell. Inventory consumption is narrative/manual for now."
    }'::jsonb,
    '{}'::jsonb,
    '["stage4c","weapon_feature","melee","energy"]'::jsonb,
    false,
    10
  ),
  (
    'stun_blast',
    'Stun Blast',
    'on_hit',
    'on_attack',
    'Generic non-lethal shock discharge that checks only hit accuracy and, on hit, asks for an Endurance save.',
    1,
    1,
    2,
    null,
    null,
    null,
    null,
    '{
      "skip_damage": true,
      "on_hit": [
        {
          "type": "pending_save",
          "attribute": "endurance",
          "reason": "stun_blast",
          "suggested_effect_code": "stunned",
          "application": "manual",
          "notes": "GM/player should roll Endurance. If failed, GM applies stunned manually and chooses duration."
        }
      ],
      "notes": "Uses normal hit accuracy but does not deal direct damage. On hit it returns a pending Endurance save."
    }'::jsonb,
    '{}'::jsonb,
    '["stage4c","weapon_feature","control","nonlethal","generic"]'::jsonb,
    false,
    20
  ),
  (
    'change_caliber',
    'Change Caliber / Switch Weapon Profile',
    'profile_switch',
    'profile_switch',
    'Marker feature for weapons that switch between functional profiles.',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '{
      "notes": "This feature is implemented by weapon profiles. Switching profile changes caliber, range profile, fire mode compatibility, and magazine slot/state."
    }'::jsonb,
    '{}'::jsonb,
    '["stage4c","weapon_feature","profile_switch"]'::jsonb,
    false,
    30
  )
on conflict (code) do update
set
  name = excluded.name,
  feature_type = excluded.feature_type,
  activation_type = excluded.activation_type,
  description = excluded.description,
  default_max_charges = excluded.default_max_charges,
  default_current_charges = excluded.default_current_charges,
  default_recharge_rounds = excluded.default_recharge_rounds,
  default_cooldown_rounds = excluded.default_cooldown_rounds,
  default_active_rounds = excluded.default_active_rounds,
  default_active_uses = excluded.default_active_uses,
  requires_reload_item_code = excluded.requires_reload_item_code,
  data = excluded.data,
  effect_data = excluded.effect_data,
  tags = excluded.tags,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

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
    'burning',
    'Burning',
    'condition',
    'Burning foundation effect for future weapon and environmental interactions.',
    'rounds',
    2,
    'replace',
    true,
    false,
    '{"modifiers":[],"flags":{},"notes":"Burning foundation effect. Automatic damage-over-time can be implemented later."}'::jsonb,
    '["stage4c","condition","fire"]'::jsonb,
    false,
    210
  ),
  (
    'poisoned',
    'Poisoned',
    'condition',
    'Generic poison or toxin foundation effect.',
    'manual',
    null,
    'replace',
    true,
    false,
    '{"modifiers":[],"flags":{},"notes":"Generic poison/toxin foundation. GM may add attribute modifiers in custom payload."}'::jsonb,
    '["stage4c","condition","toxin"]'::jsonb,
    false,
    220
  ),
  (
    'corroded',
    'Corroded',
    'condition',
    'Acid or corrosion foundation effect.',
    'manual',
    null,
    'replace',
    true,
    false,
    '{"modifiers":[],"flags":{},"notes":"Acid/corrosion foundation. Armor/equipment degradation may be implemented later."}'::jsonb,
    '["stage4c","condition","acid"]'::jsonb,
    false,
    230
  ),
  (
    'shocked',
    'Shocked',
    'condition',
    'Shock or electric foundation effect.',
    'rounds',
    1,
    'replace',
    true,
    false,
    '{"modifiers":[],"flags":{},"notes":"Shock/electric foundation. Can be used with pending saves or stun-like effects later."}'::jsonb,
    '["stage4c","condition","electric"]'::jsonb,
    false,
    240
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

insert into public.odyssey_weapon_model_defs (
  code,
  name,
  weapon_class_id,
  linked_skill_id,
  caliber_id,
  range_profile_id,
  base_accuracy_bonus,
  base_melee_damage,
  description,
  tags,
  is_custom,
  sort_order
)
values
  (
    'hybrid_rifle_shotgun',
    'Hybrid Rifle / Shotgun',
    (select id from public.odyssey_weapon_class_defs where code = 'rifle'),
    (select id from public.odyssey_skill_defs where code = 'rifles'),
    (select id from public.odyssey_caliber_defs where code = 'medium_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'rifle_profile'),
    0,
    0,
    'Stage 4C seeded dual-profile test weapon.',
    '["stage4c","hybrid","profile-switch"]'::jsonb,
    false,
    200
  )
on conflict (code) do update
set
  name = excluded.name,
  weapon_class_id = excluded.weapon_class_id,
  linked_skill_id = excluded.linked_skill_id,
  caliber_id = excluded.caliber_id,
  range_profile_id = excluded.range_profile_id,
  base_accuracy_bonus = excluded.base_accuracy_bonus,
  base_melee_damage = excluded.base_melee_damage,
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
  ((select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'), (select id from public.odyssey_fire_mode_defs where code = 'burst_3'), false),
  ((select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'), (select id from public.odyssey_fire_mode_defs where code = 'double'), false)
on conflict (weapon_model_id, fire_mode_id) do update
set
  is_default = excluded.is_default;

insert into public.odyssey_weapon_model_magazines (
  weapon_model_id,
  magazine_def_id,
  is_default
)
values
  ((select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'), (select id from public.odyssey_magazine_defs where code = 'medium_rifle_magazine'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'), (select id from public.odyssey_magazine_defs where code = 'shotgun_tube'), false)
on conflict (weapon_model_id, magazine_def_id) do update
set
  is_default = excluded.is_default;

insert into public.odyssey_weapon_model_profiles (
  weapon_model_id,
  code,
  name,
  description,
  weapon_class_id,
  linked_skill_id,
  caliber_id,
  range_profile_id,
  accuracy_modifier,
  base_melee_damage,
  attack_type,
  is_default,
  data,
  tags,
  sort_order
)
values
  (
    (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'),
    'rifle_mode',
    'Rifle Mode',
    'Primary rifle configuration.',
    (select id from public.odyssey_weapon_class_defs where code = 'rifle'),
    (select id from public.odyssey_skill_defs where code = 'rifles'),
    (select id from public.odyssey_caliber_defs where code = 'medium_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'rifle_profile'),
    0,
    0,
    'ranged',
    true,
    '{}'::jsonb,
    '["stage4c","rifle_mode"]'::jsonb,
    10
  ),
  (
    (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun'),
    'shotgun_mode',
    'Shotgun Mode',
    'Secondary close-range shotgun configuration.',
    (select id from public.odyssey_weapon_class_defs where code = 'shotgun'),
    (select id from public.odyssey_skill_defs where code = 'shotguns'),
    (select id from public.odyssey_caliber_defs where code = 'shotgun_caliber'),
    (select id from public.odyssey_range_profile_defs where code = 'shotgun_profile'),
    0,
    0,
    'ranged',
    false,
    '{}'::jsonb,
    '["stage4c","shotgun_mode"]'::jsonb,
    20
  )
on conflict (weapon_model_id, code) do update
set
  name = excluded.name,
  description = excluded.description,
  weapon_class_id = excluded.weapon_class_id,
  linked_skill_id = excluded.linked_skill_id,
  caliber_id = excluded.caliber_id,
  range_profile_id = excluded.range_profile_id,
  accuracy_modifier = excluded.accuracy_modifier,
  base_melee_damage = excluded.base_melee_damage,
  attack_type = excluded.attack_type,
  is_default = excluded.is_default,
  data = excluded.data,
  tags = excluded.tags,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_profile_fire_modes (
  profile_id,
  fire_mode_id,
  is_default,
  sort_order
)
values
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'rifle_mode'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true, 10),
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'rifle_mode'), (select id from public.odyssey_fire_mode_defs where code = 'burst_3'), false, 20),
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'shotgun_mode'), (select id from public.odyssey_fire_mode_defs where code = 'single'), true, 10),
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'shotgun_mode'), (select id from public.odyssey_fire_mode_defs where code = 'double'), false, 20)
on conflict (profile_id, fire_mode_id) do update
set
  is_default = excluded.is_default,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_profile_magazines (
  profile_id,
  magazine_def_id,
  is_default,
  sort_order
)
values
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'rifle_mode'), (select id from public.odyssey_magazine_defs where code = 'medium_rifle_magazine'), true, 10),
  ((select id from public.odyssey_weapon_model_profiles where weapon_model_id = (select id from public.odyssey_weapon_model_defs where code = 'hybrid_rifle_shotgun') and code = 'shotgun_mode'), (select id from public.odyssey_magazine_defs where code = 'shotgun_tube'), true, 10)
on conflict (profile_id, magazine_def_id) do update
set
  is_default = excluded.is_default,
  sort_order = excluded.sort_order;

insert into public.odyssey_weapon_model_features (
  weapon_model_id,
  feature_def_id,
  profile_id,
  is_enabled_by_default,
  data,
  sort_order
)
select
  wm.id,
  def.id,
  profile.id,
  true,
  '{}'::jsonb,
  sort_order_value
from (
  values
    ('combat_knife', 'plasma_edge', 'default', 10),
    ('shock_baton', 'stun_blast', 'default', 20),
    ('hybrid_rifle_shotgun', 'change_caliber', null, 30)
) seed(model_code, feature_code, profile_code, sort_order_value)
join public.odyssey_weapon_model_defs wm on wm.code = seed.model_code
join public.odyssey_weapon_feature_defs def on def.code = seed.feature_code
left join public.odyssey_weapon_model_profiles profile
  on profile.weapon_model_id = wm.id
 and profile.code = seed.profile_code
where not exists (
  select 1
  from public.odyssey_weapon_model_features existing
  where existing.weapon_model_id = wm.id
    and existing.feature_def_id = def.id
    and coalesce(existing.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(profile.id, '00000000-0000-0000-0000-000000000000'::uuid)
);

select public.initialize_character_weapon_profile_states(w.id)
from public.odyssey_character_weapons w;

select public.initialize_character_weapon_feature_states(w.id)
from public.odyssey_character_weapons w;
