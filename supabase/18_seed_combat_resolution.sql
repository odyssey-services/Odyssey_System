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
  (
    'melee_strike',
    'Melee Strike',
    1,
    null,
    null,
    false,
    0,
    'Single melee strike used by Stage 3 minimal melee resolution.',
    '["stage3","melee","fire_mode"]'::jsonb,
    false,
    15
  )
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

update public.odyssey_range_profile_modifiers rpm
set
  scaling_mode = 'scaling',
  flat_modifier = null,
  scaling_start_modifier = -50,
  scaling_end_modifier = -100,
  notes = 'Shotgun long range scales from -50 at 51m to -100 at 100m and beyond.'
from public.odyssey_range_profile_defs rp
join public.odyssey_range_band_defs rb on rb.code = 'long'
where rpm.range_profile_id = rp.id
  and rpm.range_band_id = rb.id
  and rp.code = 'shotgun_profile';

update public.odyssey_weapon_model_defs
set base_melee_damage = case code
  when 'combat_knife' then 2
  when 'shock_baton' then 3
  else 0
end
where code in (
  'frontier_pistol',
  'compact_smg',
  'frontier_shotgun',
  'standard_rifle',
  'light_machine_gun',
  'combat_knife',
  'shock_baton'
);

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
    'unarmed',
    'Unarmed',
    (select id from public.odyssey_weapon_class_defs where code = 'melee_weapon'),
    (select id from public.odyssey_skill_defs where code = 'unarmed_combat'),
    null,
    (select id from public.odyssey_range_profile_defs where code = 'melee_profile'),
    0,
    0,
    'Stage 3 seeded baseline unarmed melee model.',
    '["stage3","starter","melee","unarmed"]'::jsonb,
    false,
    55
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
  ((select id from public.odyssey_weapon_model_defs where code = 'combat_knife'), (select id from public.odyssey_fire_mode_defs where code = 'melee_strike'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'shock_baton'), (select id from public.odyssey_fire_mode_defs where code = 'melee_strike'), true),
  ((select id from public.odyssey_weapon_model_defs where code = 'unarmed'), (select id from public.odyssey_fire_mode_defs where code = 'melee_strike'), true)
on conflict (weapon_model_id, fire_mode_id) do update
set
  is_default = excluded.is_default;

update public.odyssey_weapon_model_fire_modes
set is_default = false
where weapon_model_id in (
    select id
    from public.odyssey_weapon_model_defs
    where code in ('combat_knife', 'shock_baton', 'unarmed')
  )
  and fire_mode_id <> (select id from public.odyssey_fire_mode_defs where code = 'melee_strike');
