update public.odyssey_perk_defs
set
  perk_type = 'passive',
  activation_type = 'passive',
  resolution_mode = 'backend',
  effect_data = jsonb_build_object(
    'type', 'passive_rule',
    'conditions', jsonb_build_object(
      'weapon_tags', jsonb_build_array('shotgun'),
      'range_bands', jsonb_build_array('clinch', 'short'),
      'attack_types', jsonb_build_array('ranged'),
      'target_armor_value_max', 0
    ),
    'effects', jsonb_build_object(
      'ammo_base_damage_multiplier', 2
    ),
    'ui_hint', coalesce(nullif(trim(coalesce(effect_data->>'ui_hint', '')), ''), coalesce(description, ''))
  )
where code = 'head_taker';

update public.odyssey_perk_defs
set
  perk_type = 'active',
  activation_type = 'manual',
  resolution_mode = 'hybrid',
  effect_data = jsonb_build_object(
    'type', 'active_weapon_effect',
    'conditions', jsonb_build_object(
      'weapon_tags', jsonb_build_array('machine_gun')
    ),
    'effects', jsonb_build_object(
      'weapon_locked', true,
      'spend_full_magazine', true,
      'min_magazine_fill_ratio', 0.5
    ),
    'duration_rounds', 2,
    'after_expire', jsonb_build_object(
      'weapon_locked_rounds', 1,
      'reason', 'coil_cooling'
    ),
    'ui_hint', coalesce(nullif(trim(coalesce(effect_data->>'ui_hint', '')), ''), coalesce(description, ''))
  )
where code = 'ratatatata';

update public.odyssey_perk_defs
set
  perk_type = 'passive',
  activation_type = 'passive',
  resolution_mode = 'backend',
  effect_data = jsonb_build_object(
    'type', 'passive_rule',
    'conditions', jsonb_build_object(
      'weapon_tags', jsonb_build_array('sniper', 'precision')
    ),
    'effects', jsonb_build_object(
      'attack_accuracy_bonus', 25,
      'create_retry_effect_on_miss', true
    ),
    'ui_hint', coalesce(nullif(trim(coalesce(effect_data->>'ui_hint', '')), ''), coalesce(description, ''))
  )
where code = 'first_time_no';

update public.odyssey_perk_defs
set
  perk_type = 'passive',
  activation_type = 'passive',
  resolution_mode = 'backend',
  effect_data = jsonb_build_object(
    'type', 'passive_rule',
    'conditions', jsonb_build_object(
      'weapon_tags', jsonb_build_array('sniper', 'precision')
    ),
    'effects', jsonb_build_object(
      'attack_accuracy_from_weapon_data_key', 'calibrating_accuracy_bonus'
    ),
    'ui_hint', coalesce(nullif(trim(coalesce(effect_data->>'ui_hint', '')), ''), coalesce(description, ''))
  )
where code = 'calibrating';

create or replace function public.odyssey_get_weapon_runtime_context(
  p_character_weapon_id uuid
)
returns jsonb
language sql
stable
as $$
  with weapon_row as (
    select
      w.id as character_weapon_id,
      w.character_id,
      w.weapon_model_id,
      w.active_profile_id,
      w.loaded_magazine_id,
      w.selected_fire_mode_id,
      coalesce(nullif(trim(w.custom_name), ''), wm.name) as weapon_name,
      wm.code as weapon_model_code,
      wm.tags as model_tags,
      '{}'::jsonb as weapon_data,
      wc.code as weapon_class_code,
      wc.name as weapon_class_name,
      p.id as profile_id,
      coalesce(p.code, '') as profile_code,
      coalesce(p.tags, '[]'::jsonb) as profile_tags,
      coalesce(p.attack_type, 'ranged') as attack_type,
      coalesce(p.range_profile_id, wm.range_profile_id) as range_profile_id,
      coalesce(rp.code, mrp.code) as range_profile_code,
      coalesce(p.caliber_id, wm.caliber_id) as caliber_id,
      coalesce(cal.code, mcal.code) as caliber_code,
      coalesce(fm.code, default_fm.code, '') as fire_mode_code,
      coalesce(fm.id, default_fm.id) as fire_mode_id,
      cm.current_rounds as loaded_magazine_current_rounds,
      md.capacity as loaded_magazine_capacity,
      ammo.code as loaded_ammo_code
    from public.odyssey_character_weapons w
    join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
    join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
    left join public.odyssey_weapon_model_profiles p on p.id = w.active_profile_id
    left join public.odyssey_range_profile_defs rp on rp.id = p.range_profile_id
    left join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
    left join public.odyssey_caliber_defs cal on cal.id = p.caliber_id
    left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
    left join public.odyssey_fire_mode_defs fm on fm.id = w.selected_fire_mode_id
    left join lateral (
      select fm2.id, fm2.code
      from public.odyssey_weapon_profile_fire_modes pfm2
      join public.odyssey_fire_mode_defs fm2 on fm2.id = pfm2.fire_mode_id
      where pfm2.profile_id = w.active_profile_id
        and pfm2.is_default = true
      order by pfm2.sort_order, pfm2.created_at, pfm2.id
      limit 1
    ) default_fm on true
    left join public.odyssey_character_magazines cm on cm.id = w.loaded_magazine_id
    left join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
    left join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
    where w.id = p_character_weapon_id
  ),
  weapon_tags as (
    select
      wr.character_weapon_id,
      coalesce(
        jsonb_agg(distinct tag_rows.tag) filter (where tag_rows.tag <> ''),
        '[]'::jsonb
      ) as tags
    from weapon_row wr
    left join lateral (
      select lower(trim(value)) as tag
      from jsonb_array_elements_text(coalesce(wr.model_tags, '[]'::jsonb)) value
      union
      select lower(trim(value)) as tag
      from jsonb_array_elements_text(coalesce(wr.profile_tags, '[]'::jsonb)) value
      union
      select lower(trim(coalesce(wr.weapon_class_code, '')))
      union
      select lower(trim(coalesce(wr.weapon_model_code, '')))
      union
      select lower(trim(coalesce(wr.profile_code, '')))
    ) tag_rows on true
    group by wr.character_weapon_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'character_weapon_id', wr.character_weapon_id,
        'character_id', wr.character_id,
        'weapon_model_id', wr.weapon_model_id,
        'active_profile_id', wr.active_profile_id,
        'profile_id', wr.profile_id,
        'weapon_name', wr.weapon_name,
        'weapon_model_code', wr.weapon_model_code,
        'weapon_class_code', wr.weapon_class_code,
        'weapon_class_name', wr.weapon_class_name,
        'profile_code', wr.profile_code,
        'attack_type', wr.attack_type,
        'range_profile_id', wr.range_profile_id,
        'range_profile_code', wr.range_profile_code,
        'caliber_id', wr.caliber_id,
        'caliber_code', wr.caliber_code,
        'fire_mode_id', wr.fire_mode_id,
        'fire_mode_code', wr.fire_mode_code,
        'loaded_magazine_id', wr.loaded_magazine_id,
        'loaded_magazine_current_rounds', wr.loaded_magazine_current_rounds,
        'loaded_magazine_capacity', wr.loaded_magazine_capacity,
        'loaded_ammo_code', wr.loaded_ammo_code,
        'weapon_tags', coalesce(tags.tags, '[]'::jsonb),
        'weapon_data', coalesce(wr.weapon_data, '{}'::jsonb)
      )
      from weapon_row wr
      left join weapon_tags tags on tags.character_weapon_id = wr.character_weapon_id
    ),
    jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', 'Weapon was not found.'
    )
  );
$$;

create or replace function public.odyssey_get_weapon_lock_state(
  p_character_id uuid,
  p_character_weapon_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_weapon_context jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
  v_locked boolean := false;
  v_reason text := '';
  v_error_code text := null;
  v_message text := null;
begin
  if p_character_id is null or p_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id and character_weapon_id are required.'
    );
  end if;

  v_weapon_context := public.odyssey_get_weapon_runtime_context(p_character_weapon_id);
  if coalesce((v_weapon_context->>'ok')::boolean, false) = false then
    return v_weapon_context;
  end if;

  if public.odyssey_try_parse_uuid(v_weapon_context->>'character_id') is distinct from p_character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_OWNED',
      'message', 'Weapon does not belong to this character.',
      'character_weapon_id', p_character_weapon_id
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'effect_key', e.effect_key,
        'perk_code', coalesce(e.data->>'perk_code', ''),
        'reason', coalesce(e.data#>>'{flags,reason}', e.data->>'reason', ''),
        'name', e.name,
        'data', coalesce(e.data, '{}'::jsonb)
      )
      order by e.updated_at desc, e.created_at desc, e.id desc
    ),
    '[]'::jsonb
  )
  into v_active_effects
  from public.odyssey_character_effects e
  where e.character_id = p_character_id
    and e.is_active = true
    and coalesce(e.data->>'character_weapon_id', '') = p_character_weapon_id::text
    and (
      coalesce(lower(e.data#>>'{flags,weapon_locked}'), 'false') in ('true', '1', 'yes', 'on')
      or coalesce(e.data->>'perk_code', '') in ('ratatatata')
      or split_part(coalesce(e.effect_key, ''), ':', 1) in ('coil_cooling', 'suppression_fire_active', 'ratatatata')
    );

  v_locked := jsonb_array_length(coalesce(v_active_effects, '[]'::jsonb)) > 0;

  if v_locked then
    select
      coalesce(
        nullif(trim(coalesce(effect->>'reason', '')), ''),
        nullif(trim(coalesce(effect->>'perk_code', '')), ''),
        split_part(coalesce(effect->>'effect_key', ''), ':', 1),
        'weapon_locked'
      )
    into v_reason
    from jsonb_array_elements(coalesce(v_active_effects, '[]'::jsonb)) effect
    limit 1;

    if exists (
      select 1
      from jsonb_array_elements(coalesce(v_active_effects, '[]'::jsonb)) effect
      where coalesce(effect->>'perk_code', '') = 'coil_cooling'
         or split_part(coalesce(effect->>'effect_key', ''), ':', 1) = 'coil_cooling'
         or coalesce(effect->>'reason', '') = 'coil_cooling'
    ) then
      v_error_code := 'WEAPON_COOLING';
      v_message := 'Weapon is cooling down and cannot be used right now.';
    else
      v_error_code := 'WEAPON_LOCKED';
      v_message := 'Weapon is currently locked by an active perk or effect.';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'character_weapon_id', p_character_weapon_id,
    'locked', v_locked,
    'reason', v_reason,
    'error', v_error_code,
    'message', v_message,
    'active_effects', coalesce(v_active_effects, '[]'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_get_character_attack_perk_context(
  p_character_id uuid,
  p_character_weapon_id uuid,
  p_target_character_id uuid default null,
  p_target_body_part_id uuid default null,
  p_distance_m numeric default 0,
  p_fire_mode_code text default null,
  p_attack_type text default null
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_weapon_context jsonb := '{}'::jsonb;
  v_weapon_tags jsonb := '[]'::jsonb;
  v_range_json jsonb := '{}'::jsonb;
  v_range_band text := null;
  v_range_modifier integer := 0;
  v_effective_fire_mode_code text := '';
  v_effective_attack_type text := '';
  v_attack_accuracy_bonus integer := 0;
  v_ammo_base_damage_multiplier integer := 1;
  v_flags jsonb := '{}'::jsonb;
  v_perk_modifiers jsonb := '[]'::jsonb;
  v_consume_effect_ids jsonb := '[]'::jsonb;
  v_target_armor_value integer := 0;
  v_dual_pistol_count integer := 0;
  v_calibrating_bonus integer := 0;
  v_bonus integer := 0;
  v_multiplier integer := 1;
  v_effect record;
  v_perk record;
begin
  if p_character_id is null or p_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id and character_weapon_id are required.'
    );
  end if;

  v_weapon_context := public.odyssey_get_weapon_runtime_context(p_character_weapon_id);
  if coalesce((v_weapon_context->>'ok')::boolean, false) = false then
    return v_weapon_context;
  end if;

  if public.odyssey_try_parse_uuid(v_weapon_context->>'character_id') is distinct from p_character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_OWNED',
      'message', 'Weapon does not belong to this character.',
      'character_weapon_id', p_character_weapon_id
    );
  end if;

  v_weapon_tags := coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb);
  v_effective_fire_mode_code := lower(trim(coalesce(nullif(p_fire_mode_code, ''), v_weapon_context->>'fire_mode_code', '')));
  v_effective_attack_type := lower(trim(coalesce(nullif(p_attack_type, ''), v_weapon_context->>'attack_type', '')));

  if public.odyssey_try_parse_uuid(v_weapon_context->>'range_profile_id') is not null then
    v_range_json := public.odyssey_get_range_profile_modifier(
      public.odyssey_try_parse_uuid(v_weapon_context->>'range_profile_id'),
      greatest(coalesce(p_distance_m, 0), 0)
    );
    v_range_band := nullif(coalesce(v_range_json->>'range_band', ''), '');
    v_range_modifier := coalesce((v_range_json->>'modifier')::integer, 0);
  end if;

  if p_target_body_part_id is not null then
    select greatest(coalesce(b.armor_value, 0), 0)
    into v_target_armor_value
    from public.odyssey_character_body_parts b
    where b.id = p_target_body_part_id
      and (p_target_character_id is null or b.character_id = p_target_character_id)
    limit 1;
  end if;

  select count(*)
  into v_dual_pistol_count
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  left join public.odyssey_weapon_model_profiles p on p.id = w.active_profile_id
  left join public.odyssey_weapon_class_defs wc on wc.id = coalesce(p.weapon_class_id, wm.weapon_class_id)
  where w.character_id = p_character_id
    and (
      coalesce(wm.tags, '[]'::jsonb) ? 'pistol'
      or coalesce(p.tags, '[]'::jsonb) ? 'pistol'
      or lower(coalesce(wc.code, '')) = 'pistol'
      or lower(coalesce(wm.code, '')) = 'pistol'
      or lower(coalesce(p.code, '')) = 'pistol'
    );

  for v_perk in
    select
      perk_def.id as perk_def_id,
      perk_def.code,
      coalesce(perk_def.effect_data, '{}'::jsonb) as effect_data
    from public.odyssey_character_perks owned
    join public.odyssey_perk_defs perk_def on perk_def.id = owned.perk_def_id
    where owned.character_id = p_character_id
      and coalesce(perk_def.is_enabled, true) = true
  loop
    case v_perk.code
      when 'cards_money' then
        if v_weapon_tags ? 'pistol' and v_dual_pistol_count >= 2 then
          v_flags := v_flags || jsonb_build_object(
            'offhand_attack_available', true,
            'extra_attacks_per_action',
              coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,extra_attacks_per_action}', '')), '')::integer, 1),
            'max_attacks_per_action',
              coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,max_attacks_per_action}', '')), '')::integer, 2)
          );
          v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'offhand_attack_available',
              'value', true
            )
          );
        end if;
      when 'for_the_brotherhood_and_yard_pistols' then
        if v_weapon_tags ? 'pistol' and v_range_band = 'clinch' and v_range_modifier < 0 then
          v_bonus := abs(v_range_modifier);
          if v_bonus > 0 then
            v_attack_accuracy_bonus := v_attack_accuracy_bonus + v_bonus;
            v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
              jsonb_build_object(
                'perk_code', v_perk.code,
                'modifier', 'attack_accuracy_bonus',
                'value', v_bonus,
                'reason', 'ignore_pistol_clinch_penalty'
              )
            );
          end if;
        end if;
      when 'flutter_like_butterfly' then
        if v_weapon_tags ? 'smg'
           and v_range_band = 'short'
           and v_effective_fire_mode_code in ('burst_3', 'burst_5') then
          v_bonus := coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,attack_accuracy_bonus}', '')), '')::integer, 15);
          v_attack_accuracy_bonus := v_attack_accuracy_bonus + v_bonus;
          v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'attack_accuracy_bonus',
              'value', v_bonus
            )
          );
        end if;
      when 'for_the_brotherhood_and_yard_shotguns' then
        if (v_weapon_tags ? 'shotgun' or v_weapon_tags ? 'shotguns') and v_range_band = 'clinch' then
          v_bonus := coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,range_penalty_reduction}', '')), '')::integer, 15);
          v_attack_accuracy_bonus := v_attack_accuracy_bonus + v_bonus;
          v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'attack_accuracy_bonus',
              'value', v_bonus,
              'reason', 'reduce_shotgun_clinch_penalty'
            )
          );
        end if;
      when 'head_taker' then
        if v_effective_attack_type = 'ranged'
           and (v_weapon_tags ? 'shotgun' or v_weapon_tags ? 'shotguns')
           and v_range_band in ('clinch', 'short')
           and v_target_armor_value <= coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{conditions,target_armor_value_max}', '')), '')::integer, 0) then
          v_multiplier := coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,ammo_base_damage_multiplier}', '')), '')::integer, 2);
          v_ammo_base_damage_multiplier := greatest(v_ammo_base_damage_multiplier, v_multiplier);
          v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'ammo_base_damage_multiplier',
              'value', v_multiplier
            )
          );
        end if;
      when 'calibrating' then
        if v_weapon_tags ? 'sniper' or v_weapon_tags ? 'precision' then
          v_calibrating_bonus := coalesce(
            nullif(trim(coalesce(v_weapon_context#>>'{weapon_data,perks,calibrating_accuracy_bonus}', '')), '')::integer,
            nullif(trim(coalesce(v_weapon_context#>>'{weapon_data,perks,calibrating,accuracy_bonus}', '')), '')::integer,
            nullif(trim(coalesce(v_weapon_context#>>'{weapon_data,calibrating_accuracy_bonus}', '')), '')::integer,
            0
          );
          if v_calibrating_bonus > 0 then
            v_attack_accuracy_bonus := v_attack_accuracy_bonus + v_calibrating_bonus;
            v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
              jsonb_build_object(
                'perk_code', v_perk.code,
                'modifier', 'attack_accuracy_bonus',
                'value', v_calibrating_bonus,
                'source', 'weapon_data'
              )
            );
          end if;
        end if;
      else
        null;
    end case;
  end loop;

  for v_effect in
    select
      e.id,
      e.effect_key,
      coalesce(e.data, '{}'::jsonb) as data
    from public.odyssey_character_effects e
    where e.character_id = p_character_id
      and e.is_active = true
      and coalesce(e.data->>'character_weapon_id', '') = p_character_weapon_id::text
      and coalesce(e.data->>'perk_code', '') in ('not_full_auto', 'first_time_no')
    order by e.updated_at desc, e.created_at desc, e.id desc
  loop
    if coalesce(v_effect.data->>'perk_code', '') = 'not_full_auto' then
      select greatest(
        coalesce(nullif(trim(coalesce(modifier->>'value', '')), '')::integer, 1),
        1
      )
      into v_multiplier
      from jsonb_array_elements(coalesce(v_effect.data->'modifiers', '[]'::jsonb)) modifier
      where coalesce(modifier->>'target', '') = 'ammo_base_damage'
        and coalesce(modifier->>'operation', '') = 'multiply'
      limit 1;

      if coalesce(v_multiplier, 1) > 1 then
        v_ammo_base_damage_multiplier := greatest(v_ammo_base_damage_multiplier, v_multiplier);
        v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
          jsonb_build_object(
            'perk_code', 'not_full_auto',
            'modifier', 'ammo_base_damage_multiplier',
            'value', v_multiplier,
            'effect_id', v_effect.id
          )
        );
      end if;
    elsif coalesce(v_effect.data->>'perk_code', '') = 'first_time_no'
      and coalesce(v_effect.data->>'target_character_id', '') = coalesce(p_target_character_id::text, '') then
      select coalesce(
        sum(
          coalesce(nullif(trim(coalesce(modifier->>'value', '')), '')::integer, 0)
        ),
        0
      )
      into v_bonus
      from jsonb_array_elements(coalesce(v_effect.data->'modifiers', '[]'::jsonb)) modifier
      where coalesce(modifier->>'target', '') = 'attack_accuracy'
        and coalesce(modifier->>'operation', '') = 'add';

      if coalesce(v_bonus, 0) > 0 then
        v_attack_accuracy_bonus := v_attack_accuracy_bonus + v_bonus;
        v_consume_effect_ids := v_consume_effect_ids || jsonb_build_array(v_effect.id::text);
        v_perk_modifiers := v_perk_modifiers || jsonb_build_array(
          jsonb_build_object(
            'perk_code', 'first_time_no',
            'modifier', 'attack_accuracy_bonus',
            'value', v_bonus,
            'effect_id', v_effect.id
          )
        );
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'character_weapon_id', p_character_weapon_id,
    'target_character_id', p_target_character_id,
    'target_body_part_id', p_target_body_part_id,
    'range_band', v_range_band,
    'range_modifier', v_range_modifier,
    'attack_accuracy_bonus', v_attack_accuracy_bonus,
    'ammo_base_damage_multiplier', v_ammo_base_damage_multiplier,
    'flags', coalesce(v_flags, '{}'::jsonb),
    'perk_modifiers', coalesce(v_perk_modifiers, '[]'::jsonb),
    'consume_effect_ids', coalesce(v_consume_effect_ids, '[]'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_grant_first_time_no_retry_effect(
  p_character_id uuid,
  p_character_weapon_id uuid,
  p_target_character_id uuid,
  p_created_by text default ''
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_context jsonb := '{}'::jsonb;
  v_perk record;
  v_effect_key text := '';
  v_effect_id uuid := null;
  v_effect_data jsonb := '{}'::jsonb;
  v_accuracy_bonus integer := 25;
begin
  if p_character_id is null or p_character_weapon_id is null or p_target_character_id is null then
    return jsonb_build_object(
      'ok', true,
      'applied', false
    );
  end if;

  select
    perk_def.id as perk_def_id,
    perk_def.code,
    perk_def.name,
    coalesce(perk_def.description, '') as description,
    coalesce(perk_def.effect_data, '{}'::jsonb) as effect_data
  into v_perk
  from public.odyssey_character_perks owned
  join public.odyssey_perk_defs perk_def on perk_def.id = owned.perk_def_id
  where owned.character_id = p_character_id
    and perk_def.code = 'first_time_no'
    and coalesce(perk_def.is_enabled, true) = true
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'applied', false
    );
  end if;

  v_weapon_context := public.odyssey_get_weapon_runtime_context(p_character_weapon_id);
  if coalesce((v_weapon_context->>'ok')::boolean, false) = false then
    return jsonb_build_object(
      'ok', true,
      'applied', false
    );
  end if;

  if not (
    coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'sniper'
    or coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'precision'
  ) then
    return jsonb_build_object(
      'ok', true,
      'applied', false
    );
  end if;

  v_effect_key := public.odyssey_build_perk_weapon_effect_key('first_time_no', p_character_weapon_id);
  v_accuracy_bonus := coalesce(
    nullif(trim(coalesce(v_perk.effect_data#>>'{effects,attack_accuracy_bonus}', '')), '')::integer,
    25
  );

  v_effect_data := jsonb_build_object(
    'perk_code', 'first_time_no',
    'character_weapon_id', p_character_weapon_id::text,
    'target_character_id', p_target_character_id::text,
    'duration_rounds', 2,
    'category', 'combat',
    'flags', jsonb_build_object(
      'consume_on_attack', true
    ),
    'modifiers',
      jsonb_build_array(
        jsonb_build_object(
          'target', 'attack_accuracy',
          'operation', 'add',
          'value', v_accuracy_bonus
        )
      )
  );

  update public.odyssey_character_effects
  set
    is_active = false,
    rounds_left = 0,
    updated_at = timezone('utc', now())
  where character_id = p_character_id
    and effect_key = v_effect_key
    and is_active = true;

  insert into public.odyssey_character_effects (
    character_id,
    effect_key,
    name,
    description,
    source,
    source_type,
    source_id,
    source_character_id,
    duration_type,
    rounds_left,
    data,
    is_active,
    created_by
  )
  values (
    p_character_id,
    v_effect_key,
    v_perk.name,
    v_perk.description,
    'perk',
    'perk',
    v_perk.perk_def_id,
    p_character_id,
    'rounds',
    2,
    v_effect_data,
    true,
    p_created_by
  )
  returning id into v_effect_id;

  return jsonb_build_object(
    'ok', true,
    'applied', true,
    'effect_id', v_effect_id,
    'perk_code', 'first_time_no'
  );
end;
$$;

create or replace function public.odyssey_get_weapon_perk_attack_context(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_attacker_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'attacker_character_id');
  v_weapon_id uuid := public.odyssey_try_parse_uuid(p_payload->>'weapon_id');
  v_target_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_body_part_id');
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(p_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_lock_state jsonb := '{}'::jsonb;
  v_context jsonb := '{}'::jsonb;
begin
  if v_attacker_character_id is null or v_weapon_id is null then
    return jsonb_build_object(
      'ok', true,
      'perk_context', '{}'::jsonb
    );
  end if;

  v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_weapon_id);
  if coalesce((v_lock_state->>'locked')::boolean, false) = true then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
      'message', coalesce(v_lock_state->>'message', 'Weapon is locked.'),
      'character_weapon_id', v_weapon_id
    );
  end if;

  v_context := public.odyssey_get_character_attack_perk_context(
    v_attacker_character_id,
    v_weapon_id,
    v_target_character_id,
    v_target_body_part_id,
    v_distance_m,
    nullif(trim(coalesce(p_payload->>'fire_mode_code', '')), ''),
    nullif(trim(coalesce(p_payload->>'attack_type', '')), '')
  );

  if coalesce((v_context->>'ok')::boolean, false) = false then
    return v_context;
  end if;

  return jsonb_build_object(
    'ok', true,
    'perk_context', v_context - 'ok'
  );
end;
$$;

create or replace function public.get_character_armory(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_weapon_id uuid;
  v_weapons jsonb := '[]'::jsonb;
  v_magazines jsonb := '[]'::jsonb;
begin
  for v_weapon_id in
    select w.id
    from public.odyssey_character_weapons w
    where w.character_id = p_character_id
  loop
    perform public.initialize_character_weapon_profile_states(v_weapon_id);
    perform public.initialize_character_weapon_feature_states(v_weapon_id);
  end loop;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', w.id,
          'character_id', w.character_id,
          'custom_name', w.custom_name,
          'name', coalesce(nullif(trim(w.custom_name), ''), wm.name),
          'notes', w.notes,
          'sort_order', w.sort_order,
          'active_profile_id', w.active_profile_id,
          'model',
            jsonb_build_object(
              'id', wm.id,
              'code', wm.code,
              'name', wm.name,
              'weapon_class', mwc.code,
              'weapon_class_name', mwc.name,
              'linked_skill', mskill.code,
              'linked_skill_name', mskill.name,
              'caliber', mcal.code,
              'caliber_name', mcal.name,
              'base_accuracy_bonus', wm.base_accuracy_bonus,
              'base_melee_damage', wm.base_melee_damage,
              'range_profile', mrp.code,
              'range_profile_name', mrp.name,
              'tags', wm.tags
            ),
          'active_profile', public.odyssey_get_active_character_weapon_profile(w.id),
          'profiles', public.odyssey_get_character_weapon_profiles(w.id),
          'features', coalesce(public.get_character_weapon_features(w.id)->'features', '[]'::jsonb),
          'loaded_magazine', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'loaded_magazine', 'null'::jsonb),
          'selected_fire_mode', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'selected_fire_mode', 'null'::jsonb),
          'available_fire_modes', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'available_fire_modes', '[]'::jsonb),
          'compatible_magazines', coalesce(public.odyssey_get_active_character_weapon_profile(w.id)->'compatible_magazines', '[]'::jsonb),
          'lock_state', public.odyssey_get_weapon_lock_state(w.character_id, w.id)
        )
        order by w.sort_order, coalesce(nullif(trim(w.custom_name), ''), wm.name), w.id
      ),
      '[]'::jsonb
    )
  into v_weapons
  from public.odyssey_character_weapons w
  join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
  join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
  join public.odyssey_skill_defs mskill on mskill.id = wm.linked_skill_id
  left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
  join public.odyssey_range_profile_defs mrp on mrp.id = wm.range_profile_id
  where w.character_id = p_character_id;

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', cm.id,
          'character_id', cm.character_id,
          'custom_name', cm.custom_name,
          'name', coalesce(nullif(trim(cm.custom_name), ''), md.name),
          'notes', cm.notes,
          'current_rounds', cm.current_rounds,
          'magazine_def',
            jsonb_build_object(
              'id', md.id,
              'code', md.code,
              'name', md.name,
              'capacity', md.capacity,
              'caliber', caliber.code,
              'caliber_name', caliber.name
            ),
          'ammo_type',
            jsonb_build_object(
              'id', ammo.id,
              'code', ammo.code,
              'name', ammo.name,
              'caliber', ammo_caliber.code,
              'caliber_name', ammo_caliber.name
            )
        )
        order by md.sort_order, md.name, cm.created_at, cm.id
      ),
      '[]'::jsonb
    )
  into v_magazines
  from public.odyssey_character_magazines cm
  join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
  join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
  join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
  join public.odyssey_caliber_defs ammo_caliber on ammo_caliber.id = ammo.caliber_id
  where cm.character_id = p_character_id;

  return jsonb_build_object(
    'character_id', p_character_id,
    'weapons', coalesce(v_weapons, '[]'::jsonb),
    'magazines', coalesce(v_magazines, '[]'::jsonb)
  );
end;
$$;

create or replace function public.activate_weapon_feature(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_weapon_id uuid := nullif(trim(coalesce(p_payload->>'character_weapon_id', '')), '')::uuid;
  v_feature_code text := coalesce(nullif(trim(coalesce(p_payload->>'feature_code', '')), ''), '');
  v_weapon public.odyssey_character_weapons%rowtype;
  v_state record;
  v_active_uses integer := null;
  v_active_rounds integer := null;
  v_lock_state jsonb := '{}'::jsonb;
begin
  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', format('Weapon %s was not found.', v_character_weapon_id)
    );
  end if;

  v_lock_state := public.odyssey_get_weapon_lock_state(v_weapon.character_id, v_character_weapon_id);
  if coalesce((v_lock_state->>'locked')::boolean, false) = true then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
      'message', coalesce(v_lock_state->>'message', 'Weapon is locked right now.'),
      'character_weapon_id', v_character_weapon_id
    );
  end if;

  perform public.initialize_character_weapon_profile_states(v_weapon.id);
  perform public.initialize_character_weapon_feature_states(v_weapon.id);

  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id;

  select
    s.id,
    s.character_weapon_id,
    s.feature_def_id,
    s.profile_id,
    s.is_active,
    s.is_enabled,
    s.current_charges,
    s.max_charges,
    s.recharge_rounds_left,
    s.cooldown_rounds_left,
    s.active_rounds_left,
    s.active_uses_left,
    s.requires_reload,
    s.data,
    def.code,
    def.name,
    def.feature_type,
    def.activation_type,
    def.default_active_rounds,
    def.default_active_uses,
    def.requires_reload_item_code
  into v_state
  from public.odyssey_character_weapon_feature_states s
  join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
  where s.character_weapon_id = v_weapon.id
    and def.code = v_feature_code
    and (s.profile_id = v_weapon.active_profile_id or s.profile_id is null)
  order by case when s.profile_id = v_weapon.active_profile_id then 0 else 1 end
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_NOT_AVAILABLE',
      'message', format('Feature %s is not available for weapon %s.', v_feature_code, v_character_weapon_id)
    );
  end if;

  if not coalesce(v_state.is_enabled, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_DISABLED',
      'message', format('Feature %s is disabled for weapon %s.', v_feature_code, v_character_weapon_id)
    );
  end if;

  if v_state.activation_type <> 'manual' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_ACTIVATION_MODE',
      'message', format('Feature %s must be used through %s activation, not manual activation.', v_feature_code, v_state.activation_type)
    );
  end if;

  if coalesce(v_state.requires_reload, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_RELOAD_REQUIRED',
      'message', format('Feature %s requires manual reload before activation.', v_feature_code)
    );
  end if;

  if coalesce(v_state.recharge_rounds_left, 0) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_RECHARGING',
      'message', format('Feature %s is still recharging.', v_feature_code)
    );
  end if;

  if coalesce(v_state.cooldown_rounds_left, 0) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_COOLDOWN',
      'message', format('Feature %s is still cooling down.', v_feature_code)
    );
  end if;

  if v_state.current_charges is not null and v_state.current_charges <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_NO_CHARGES',
      'message', format('Feature %s has no charges left.', v_feature_code)
    );
  end if;

  v_active_uses := coalesce(v_state.default_active_uses, v_state.active_uses_left);
  v_active_rounds := coalesce(v_state.default_active_rounds, v_state.active_rounds_left);

  update public.odyssey_character_weapon_feature_states
  set
    is_active = true,
    current_charges =
      case
        when current_charges is null then null
        else greatest(current_charges - 1, 0)
      end,
    active_uses_left = v_active_uses,
    active_rounds_left = v_active_rounds,
    recharge_rounds_left = null,
    cooldown_rounds_left = null,
    requires_reload = false
  where id = v_state.id;

  return jsonb_build_object(
    'ok', true,
    'weapon_id', v_weapon.id,
    'feature', (
      select feature
      from jsonb_array_elements(public.get_character_weapon_features(v_weapon.id)->'features') feature
      where nullif(feature->>'state_id', '')::uuid = v_state.id
      limit 1
    )
  );
end;
$$;

create or replace function public.use_character_perk(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_perk_code text := lower(trim(coalesce(v_payload->>'perk_code', '')));
  v_scene_id text := coalesce(nullif(trim(coalesce(v_payload->>'scene_id', '')), ''), '');
  v_encounter_id uuid := public.odyssey_try_parse_uuid(v_payload->>'encounter_id');
  v_target_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_body_part_id');
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_weapon_id');
  v_note text := coalesce(v_payload->>'note', '');
  v_created_by text := coalesce(nullif(trim(coalesce(v_payload->>'created_by', '')), ''), '');
  v_character public.odyssey_characters%rowtype;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_perk record;
  v_weapon_context jsonb := '{}'::jsonb;
  v_lock_state jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_message text := '';
  v_gm_hint text := '';
  v_effect_key text := '';
  v_effect_id uuid := null;
  v_duration_rounds integer := 2;
  v_cooling_rounds integer := 1;
  v_damage_multiplier integer := 2;
  v_effect_data jsonb := '{}'::jsonb;
  v_combat_state jsonb := '{}'::jsonb;
  v_magazine_id uuid := null;
  v_magazine_rounds integer := 0;
  v_magazine_capacity integer := 0;
  v_spent_rounds integer := 0;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'Payload must be a JSON object.'
    );
  end if;

  if v_character_id is null or v_perk_code = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id and perk_code are required.'
    );
  end if;

  select *
  into v_character
  from public.odyssey_characters c
  where c.id = v_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_character_id
    );
  end if;

  select
    p.id as perk_def_id,
    p.code,
    p.name,
    coalesce(p.description, '') as description,
    coalesce(p.linked_skill_id, p.skill_def_id) as linked_skill_id,
    skill.code as linked_skill_code,
    skill.name as linked_skill_name,
    greatest(coalesce(p.required_skill_level, 1), 1) as required_skill_level,
    coalesce(p.perk_type, 'passive') as perk_type,
    coalesce(p.activation_type, 'passive') as activation_type,
    coalesce(p.resolution_mode, 'backend') as resolution_mode,
    coalesce(p.effect_data, '{}'::jsonb) as effect_data,
    coalesce(p.tags, '[]'::jsonb) as tags,
    coalesce(p.is_enabled, true) as is_enabled,
    owned.id as character_perk_id
  into v_perk
  from public.odyssey_perk_defs p
  left join public.odyssey_skill_defs skill on skill.id = coalesce(p.linked_skill_id, p.skill_def_id)
  left join public.odyssey_character_perks owned
    on owned.perk_def_id = p.id
   and owned.character_id = v_character_id
  where p.code = v_perk_code;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'PERK_NOT_FOUND',
      'message', 'Perk definition was not found.'
    );
  end if;

  if not v_perk.is_enabled then
    return jsonb_build_object(
      'ok', false,
      'error', 'PERK_DISABLED',
      'message', 'Perk is disabled.',
      'perk_code', v_perk_code
    );
  end if;

  if v_perk.character_perk_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'PERK_NOT_OWNED',
      'message', 'Character does not own this perk.',
      'perk_code', v_perk_code
    );
  end if;

  if v_perk.perk_type = 'passive' or v_perk.activation_type = 'passive' then
    return jsonb_build_object(
      'ok', false,
      'error', 'PERK_IS_PASSIVE',
      'message', 'Passive perks cannot be used manually.',
      'perk_code', v_perk_code
    );
  end if;

  v_gm_hint := coalesce(
    nullif(trim(coalesce(v_perk.effect_data->>'ui_hint', '')), ''),
    nullif(trim(v_perk.description), ''),
    'GM resolves this perk.'
  );

  if v_perk.resolution_mode = 'gm_resolved' then
    v_message := format(
      '%s uses perk "%s".',
      coalesce(nullif(trim(v_character.resources->>'name'), ''), v_character.character_key),
      v_perk.name
    );

    insert into public.odyssey_combat_log (
      campaign_id,
      room_id,
      scene_id,
      encounter_id,
      actor_character_id,
      target_character_id,
      event_type,
      message,
      data,
      created_by
    )
    values (
      coalesce(v_character.campaign_id, ''),
      coalesce(v_character.room_id, ''),
      v_scene_id,
      v_encounter_id,
      v_character_id,
      v_target_character_id,
      'perk_use',
      v_message,
      jsonb_build_object(
        'type', 'perk_use',
        'character_id', v_character_id,
        'perk_code', v_perk.code,
        'perk_name', v_perk.name,
        'perk_type', v_perk.perk_type,
        'activation_type', v_perk.activation_type,
        'resolution_mode', v_perk.resolution_mode,
        'gm_hint', v_gm_hint,
        'note', v_note,
        'target_character_id', v_target_character_id,
        'target_body_part_id', v_target_body_part_id,
        'character_weapon_id', v_character_weapon_id
      ),
      v_created_by
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, v_character.room_id);

    return jsonb_build_object(
      'ok', true,
      'character_id', v_character_id,
      'perk_code', v_perk.code,
      'message', v_message,
      'gm_hint', v_gm_hint,
      'log_id', v_log_id
    );
  end if;

  if v_perk.code not in ('not_full_auto', 'ratatatata') then
    return jsonb_build_object(
      'ok', false,
      'error', 'UNSUPPORTED_BACKEND_PERK',
      'message', 'This perk has no backend automation in the current stage.',
      'perk_code', v_perk.code
    );
  end if;

  if v_character_weapon_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_REQUIRED',
      'message', 'character_weapon_id is required for this perk.'
    );
  end if;

  select *
  into v_weapon
  from public.odyssey_character_weapons w
  where w.id = v_character_weapon_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', 'Weapon was not found.',
      'character_weapon_id', v_character_weapon_id
    );
  end if;

  if v_weapon.character_id is distinct from v_character_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_OWNED',
      'message', 'Weapon does not belong to this character.',
      'character_weapon_id', v_character_weapon_id
    );
  end if;

  v_lock_state := public.odyssey_get_weapon_lock_state(v_character_id, v_character_weapon_id);
  if coalesce((v_lock_state->>'locked')::boolean, false) = true then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
      'message', coalesce(v_lock_state->>'message', 'Weapon is currently locked.'),
      'character_weapon_id', v_character_weapon_id
    );
  end if;

  v_weapon_context := public.odyssey_get_weapon_runtime_context(v_character_weapon_id);
  if coalesce((v_weapon_context->>'ok')::boolean, false) = false then
    return v_weapon_context;
  end if;

  if v_perk.code = 'not_full_auto' then
    if not (
      coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'assault_rifle'
      or coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'standard_rifle'
      or (
        coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'rifle'
        and not (coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'sniper')
        and not (coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'precision')
      )
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'WEAPON_NOT_COMPATIBLE',
        'message', 'Weapon is not compatible with this perk.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_effect_key := public.odyssey_build_perk_weapon_effect_key(v_perk.code, v_character_weapon_id);
    if exists (
      select 1
      from public.odyssey_character_effects e
      where e.character_id = v_character_id
        and e.is_active = true
        and e.effect_key = v_effect_key
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'PERK_ALREADY_ACTIVE',
        'message', 'This perk is already active on the selected weapon.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_duration_rounds := greatest(coalesce(nullif(trim(coalesce(v_perk.effect_data->>'duration_rounds', '')), '')::integer, 2), 1);
    v_damage_multiplier := greatest(
      coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{effects,ammo_base_damage_multiplier}', '')), '')::integer, 2),
      1
    );
    v_cooling_rounds := greatest(
      coalesce(
        nullif(trim(coalesce(v_perk.effect_data#>>'{after_expire,duration_rounds}', '')), '')::integer,
        nullif(trim(coalesce(v_perk.effect_data#>>'{after_expire,weapon_locked_rounds}', '')), '')::integer,
        1
      ),
      1
    );

    v_effect_data := jsonb_build_object(
      'perk_code', v_perk.code,
      'character_weapon_id', v_character_weapon_id::text,
      'duration_rounds', v_duration_rounds,
      'category', 'combat',
      'modifiers',
        jsonb_build_array(
          jsonb_build_object(
            'target', 'ammo_base_damage',
            'operation', 'multiply',
            'value', v_damage_multiplier,
            'conditions', jsonb_build_object('character_weapon_id', v_character_weapon_id::text)
          )
        ),
      'after_expire',
        jsonb_build_object(
          'apply_effect_code', 'coil_cooling',
          'duration_rounds', v_cooling_rounds,
          'character_weapon_id', v_character_weapon_id::text,
          'reason', coalesce(nullif(trim(coalesce(v_perk.effect_data#>>'{after_expire,reason}', '')), ''), 'coil_cooling'),
          'flags', jsonb_build_object('weapon_locked', true, 'reason', 'coil_cooling'),
          'category', 'combat'
        ),
      'ui_hint', v_gm_hint
    );
  else
    if not (
      coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'machine_gun'
      or coalesce(v_weapon_context->'weapon_tags', '[]'::jsonb) ? 'machine_guns'
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'WEAPON_NOT_COMPATIBLE',
        'message', 'Weapon is not compatible with this perk.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_effect_key := public.odyssey_build_perk_weapon_effect_key('suppression_fire_active', v_character_weapon_id);
    if exists (
      select 1
      from public.odyssey_character_effects e
      where e.character_id = v_character_id
        and e.is_active = true
        and e.effect_key = v_effect_key
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'PERK_ALREADY_ACTIVE',
        'message', 'This perk is already active on the selected weapon.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    v_magazine_id := public.odyssey_try_parse_uuid(v_weapon_context->>'loaded_magazine_id');
    v_magazine_rounds := coalesce(nullif(trim(coalesce(v_weapon_context->>'loaded_magazine_current_rounds', '')), '')::integer, 0);
    v_magazine_capacity := coalesce(nullif(trim(coalesce(v_weapon_context->>'loaded_magazine_capacity', '')), '')::integer, 0);

    if v_magazine_id is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'MAGAZINE_REQUIRED',
        'message', 'A loaded magazine is required for this perk.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    if v_magazine_rounds <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_AMMO',
        'message', 'Loaded magazine is empty.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    if v_magazine_capacity <= 0
       or v_magazine_rounds < ceil(v_magazine_capacity::numeric / 2.0)::integer then
      return jsonb_build_object(
        'ok', false,
        'error', 'MAGAZINE_TOO_EMPTY',
        'message', 'Magazine must be at least half full to use this perk.',
        'character_weapon_id', v_character_weapon_id
      );
    end if;

    update public.odyssey_character_magazines
    set current_rounds = 0
    where id = v_magazine_id;

    v_spent_rounds := v_magazine_rounds;
    v_duration_rounds := greatest(coalesce(nullif(trim(coalesce(v_perk.effect_data->>'duration_rounds', '')), '')::integer, 2), 1);
    v_cooling_rounds := greatest(
      coalesce(
        nullif(trim(coalesce(v_perk.effect_data#>>'{after_expire,duration_rounds}', '')), '')::integer,
        nullif(trim(coalesce(v_perk.effect_data#>>'{after_expire,weapon_locked_rounds}', '')), '')::integer,
        1
      ),
      1
    );

    v_effect_data := jsonb_build_object(
      'perk_code', v_perk.code,
      'character_weapon_id', v_character_weapon_id::text,
      'duration_rounds', v_duration_rounds,
      'category', 'combat',
      'spent_rounds', v_spent_rounds,
      'flags', jsonb_build_object('weapon_locked', true, 'reason', 'suppression_fire_active'),
      'after_expire',
        jsonb_build_object(
          'apply_effect_code', 'coil_cooling',
          'duration_rounds', v_cooling_rounds,
          'character_weapon_id', v_character_weapon_id::text,
          'reason', 'coil_cooling',
          'flags', jsonb_build_object('weapon_locked', true, 'reason', 'coil_cooling'),
          'category', 'combat'
        ),
      'ui_hint', v_gm_hint
    );
  end if;

  insert into public.odyssey_character_effects (
    character_id,
    effect_key,
    name,
    description,
    source,
    source_type,
    source_id,
    source_character_id,
    duration_type,
    rounds_left,
    data,
    is_active,
    created_by
  )
  values (
    v_character_id,
    v_effect_key,
    v_perk.name,
    v_perk.description,
    'perk',
    'perk',
    v_perk.perk_def_id,
    v_character_id,
    'rounds',
    v_duration_rounds,
    v_effect_data,
    true,
    v_created_by
  )
  returning id into v_effect_id;

  v_combat_state := coalesce(public.odyssey_refresh_character_combat_state(v_character_id)->'combat_state', '{}'::jsonb);
  perform public.odyssey_sync_character_weapon_profile_cache(v_character_weapon_id);

  if v_perk.code = 'ratatatata' then
    v_message := format(
      '%s activates perk "%s" on %s and spends %s rounds to begin suppressive fire.',
      coalesce(nullif(trim(v_character.resources->>'name'), ''), v_character.character_key),
      v_perk.name,
      coalesce(v_weapon_context->>'weapon_name', 'weapon'),
      v_spent_rounds
    );
  else
    v_message := format(
      '%s activates perk "%s" on %s.',
      coalesce(nullif(trim(v_character.resources->>'name'), ''), v_character.character_key),
      v_perk.name,
      coalesce(v_weapon_context->>'weapon_name', 'weapon')
    );
  end if;

  insert into public.odyssey_combat_log (
    campaign_id,
    room_id,
    scene_id,
    encounter_id,
    actor_character_id,
    target_character_id,
    event_type,
    message,
    data,
    created_by
  )
  values (
    coalesce(v_character.campaign_id, ''),
    coalesce(v_character.room_id, ''),
    v_scene_id,
    v_encounter_id,
    v_character_id,
    v_target_character_id,
    'perk_use',
    v_message,
    jsonb_build_object(
      'type', 'perk_use',
      'character_id', v_character_id,
      'perk_code', v_perk.code,
      'perk_name', v_perk.name,
      'perk_type', v_perk.perk_type,
      'activation_type', v_perk.activation_type,
      'resolution_mode', v_perk.resolution_mode,
      'gm_hint', v_gm_hint,
      'note', v_note,
      'target_character_id', v_target_character_id,
      'target_body_part_id', v_target_body_part_id,
      'character_weapon_id', v_character_weapon_id,
      'effect_id', v_effect_id,
      'duration_rounds', v_duration_rounds,
      'cooling_rounds', v_cooling_rounds,
      'spent_rounds', v_spent_rounds
    ),
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, v_character.room_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'perk_code', v_perk.code,
    'message', v_message,
    'gm_hint', v_gm_hint,
    'effect_id', v_effect_id,
    'log_id', v_log_id,
    'combat_state', v_combat_state,
    'perk_modifiers',
      case
        when v_perk.code = 'not_full_auto' then
          jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'ammo_base_damage_multiplier',
              'value', v_damage_multiplier
            )
          )
        else
          jsonb_build_array(
            jsonb_build_object(
              'perk_code', v_perk.code,
              'modifier', 'weapon_locked',
              'value', true
            )
          )
      end
  );
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_ability_id');
  v_ability_code text := lower(trim(coalesce(v_payload->>'ability_code', '')));
  v_attacker_character_id uuid := public.odyssey_try_parse_uuid(coalesce(v_payload->>'attacker_character_id', v_payload->>'character_id'));
  v_target_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(v_payload->>'target_body_part_id');
  v_weapon_id uuid := public.odyssey_try_parse_uuid(v_payload->>'weapon_id');
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_weapon_id');
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(v_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_lock_state jsonb := '{}'::jsonb;
  v_perk_context_result jsonb := jsonb_build_object(
    'ok', true,
    'attack_accuracy_bonus', 0,
    'ammo_base_damage_multiplier', 1,
    'flags', '{}'::jsonb,
    'perk_modifiers', '[]'::jsonb,
    'consume_effect_ids', '[]'::jsonb
  );
  v_attack_context jsonb := '{}'::jsonb;
  v_existing_bonus integer := 0;
  v_perk_bonus integer := 0;
  v_result jsonb := '{}'::jsonb;
  v_retry_effect jsonb := jsonb_build_object('ok', true, 'applied', false);
  v_refresh_attacker boolean := false;
begin
  if v_character_ability_id is not null or v_ability_code <> '' then
    if v_attacker_character_id is not null and coalesce(v_character_weapon_id, v_weapon_id) is not null then
      v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, coalesce(v_character_weapon_id, v_weapon_id));
      if coalesce((v_lock_state->>'locked')::boolean, false) = true then
        return jsonb_build_object(
          'ok', false,
          'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
          'message', coalesce(v_lock_state->>'message', 'Weapon is currently locked.'),
          'character_weapon_id', coalesce(v_character_weapon_id, v_weapon_id)
        );
      end if;
    end if;

    return public.odyssey_perform_ability_attack(v_payload);
  end if;

  if v_attacker_character_id is not null and v_weapon_id is not null then
    v_lock_state := public.odyssey_get_weapon_lock_state(v_attacker_character_id, v_weapon_id);
    if coalesce((v_lock_state->>'locked')::boolean, false) = true then
      return jsonb_build_object(
        'ok', false,
        'error', coalesce(v_lock_state->>'error', 'WEAPON_LOCKED'),
        'message', coalesce(v_lock_state->>'message', 'Weapon is currently locked.'),
        'character_weapon_id', v_weapon_id
      );
    end if;

    v_perk_context_result := public.odyssey_get_character_attack_perk_context(
      v_attacker_character_id,
      v_weapon_id,
      v_target_character_id,
      v_target_body_part_id,
      v_distance_m,
      nullif(trim(coalesce(v_payload->>'fire_mode_code', '')), ''),
      nullif(trim(coalesce(v_payload->>'attack_type', '')), '')
    );

    if coalesce((v_perk_context_result->>'ok')::boolean, false) = false then
      return v_perk_context_result;
    end if;
  end if;

  v_attack_context := case
    when jsonb_typeof(v_payload->'attack_context') = 'object' then v_payload->'attack_context'
    else '{}'::jsonb
  end;
  v_existing_bonus := coalesce(nullif(trim(coalesce(v_attack_context->>'manual_attack_bonus', '')), '')::integer, 0);
  v_perk_bonus := coalesce(nullif(trim(coalesce(v_perk_context_result->>'attack_accuracy_bonus', '')), '')::integer, 0);

  if v_perk_bonus <> 0 then
    v_attack_context := v_attack_context || jsonb_build_object('manual_attack_bonus', v_existing_bonus + v_perk_bonus);
    v_payload := v_payload || jsonb_build_object('attack_context', v_attack_context);
  end if;

  v_payload := v_payload || jsonb_build_object('perk_context', v_perk_context_result - 'ok');
  v_result := public.odyssey_perform_weapon_attack(v_payload);

  if coalesce((v_result->>'ok')::boolean, false) = true then
    if jsonb_array_length(coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb)) > 0 then
      update public.odyssey_character_effects e
      set
        is_active = false,
        rounds_left = 0,
        updated_at = timezone('utc', now())
      where e.character_id = v_attacker_character_id
        and e.id in (
          select public.odyssey_try_parse_uuid(value)
          from jsonb_array_elements_text(coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb)) value
        );
      v_refresh_attacker := true;
    end if;

    if not coalesce((v_result->>'hit')::boolean, false) then
      v_retry_effect := public.odyssey_grant_first_time_no_retry_effect(
        v_attacker_character_id,
        v_weapon_id,
        v_target_character_id,
        coalesce(v_payload->>'actor_token_id', '')
      );
      if coalesce((v_retry_effect->>'applied')::boolean, false) = true then
        v_refresh_attacker := true;
      end if;
    end if;

    if v_refresh_attacker and v_attacker_character_id is not null then
      v_result := v_result || jsonb_build_object(
        'attacker_state',
        coalesce(public.odyssey_refresh_character_combat_state(v_attacker_character_id)->'combat_state', '{}'::jsonb),
        'post_attack_perks',
          jsonb_build_object(
            'consumed_effect_ids', coalesce(v_perk_context_result->'consume_effect_ids', '[]'::jsonb),
            'retry_effect', v_retry_effect
          )
      );
    end if;

    return public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
  end if;

  return v_result;
end;
$$;

grant execute on function public.odyssey_get_weapon_runtime_context(uuid) to anon, authenticated;
grant execute on function public.odyssey_get_weapon_lock_state(uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_attack_perk_context(uuid, uuid, uuid, uuid, numeric, text, text) to anon, authenticated;
grant execute on function public.odyssey_grant_first_time_no_retry_effect(uuid, uuid, uuid, text) to anon, authenticated;
