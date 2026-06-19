drop function if exists public.initialize_character_combat_defaults(uuid);

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

create or replace function public.initialize_character_combat_defaults(p_character_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_character_exists boolean := false;
  v_rule_defaults jsonb := '{}'::jsonb;
  v_unarmed_model_id uuid := null;
  v_melee_strike_id uuid := null;
  v_unarmed_weapon_id uuid := null;
  v_unarmed_created boolean := false;
begin
  select exists(
    select 1
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  )
  into v_character_exists;

  if not v_character_exists then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id
    );
  end if;

  v_rule_defaults := public.initialize_character_rule_defaults(p_character_id);

  select wm.id
  into v_unarmed_model_id
  from public.odyssey_weapon_model_defs wm
  where wm.code = 'unarmed';

  if v_unarmed_model_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'UNARMED_MODEL_NOT_FOUND',
      'character_id', p_character_id,
      'rule_defaults', v_rule_defaults
    );
  end if;

  select fm.id
  into v_melee_strike_id
  from public.odyssey_fire_mode_defs fm
  where fm.code = 'melee_strike';

  if v_melee_strike_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'MELEE_STRIKE_NOT_FOUND',
      'character_id', p_character_id,
      'rule_defaults', v_rule_defaults
    );
  end if;

  select w.id
  into v_unarmed_weapon_id
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  where w.character_id = p_character_id
    and wm.code = 'unarmed'
  order by w.sort_order, w.created_at, w.id
  limit 1;

  if v_unarmed_weapon_id is null then
    insert into public.odyssey_character_weapons (
      character_id,
      weapon_model_id,
      custom_name,
      loaded_magazine_id,
      selected_fire_mode_id,
      notes,
      sort_order
    )
    values (
      p_character_id,
      v_unarmed_model_id,
      null,
      null,
      v_melee_strike_id,
      '',
      5
    )
    returning id into v_unarmed_weapon_id;

    v_unarmed_created := true;
  else
    update public.odyssey_character_weapons
    set
      loaded_magazine_id = null,
      selected_fire_mode_id = v_melee_strike_id
    where id = v_unarmed_weapon_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'rule_defaults', v_rule_defaults,
    'unarmed_weapon_id', v_unarmed_weapon_id,
    'unarmed_created', v_unarmed_created,
    'rule_sheet', public.get_character_rule_sheet(p_character_id),
    'armory', public.get_character_armory(p_character_id)
  );
end;
$$;

grant execute on function public.initialize_character_combat_defaults(uuid) to anon, authenticated;
