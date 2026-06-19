-- Odyssey: UI read RPCs, authoritative scene links, safe unbind and NPC-active cleanup.
-- This migration is additive and keeps older RPC names for backward compatibility.

create or replace function public.get_character_runtime_bundle(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_sections_raw jsonb := p_payload->'sections';
  v_requested text[] := array[]::text[];
  v_allowed text[] := array[
    'summary', 'combat', 'attributes', 'skills', 'perks',
    'equipment', 'inventory', 'armory', 'abilities', 'effects', 'token_link'
  ];
  v_all_sections boolean := true;
  v_invalid_section text;
  v_character public.odyssey_characters%rowtype;
  v_summary jsonb := '{}'::jsonb;
  v_state jsonb := '{}'::jsonb;
  v_combat jsonb := '{}'::jsonb;
  v_attributes jsonb := '[]'::jsonb;
  v_skills jsonb := '[]'::jsonb;
  v_perks jsonb := '[]'::jsonb;
  v_equipment jsonb := '[]'::jsonb;
  v_inventory jsonb := '{}'::jsonb;
  v_armory jsonb := '{}'::jsonb;
  v_abilities jsonb := '{}'::jsonb;
  v_effects jsonb := '[]'::jsonb;
  v_token_links jsonb := '[]'::jsonb;
  v_sections jsonb := '{}'::jsonb;
  v_body_parts jsonb := '[]'::jsonb;
  v_status_summary text := '';
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id must be a valid UUID.'
    );
  end if;

  if v_sections_raw is not null and jsonb_typeof(v_sections_raw) <> 'array' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_SECTION',
      'message', 'sections must be a JSON array when provided.'
    );
  end if;

  if v_sections_raw is not null then
    select coalesce(array_agg(value), array[]::text[])
    into v_requested
    from jsonb_array_elements_text(v_sections_raw) as value;

    v_all_sections := cardinality(v_requested) = 0;

    select section_name
    into v_invalid_section
    from unnest(v_requested) as section_name
    where not (section_name = any(v_allowed))
    limit 1;

    if v_invalid_section is not null then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_SECTION',
        'message', format('Unknown requested section: %s.', v_invalid_section),
        'section', v_invalid_section
      );
    end if;
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
      'message', 'Character was not found or has been deleted.',
      'character_id', v_character_id
    );
  end if;

  select coalesce(nullif(trim(s.status_summary), ''), public.odyssey_build_character_status_summary(v_character_id))
  into v_status_summary
  from public.odyssey_character_combat_state s
  where s.character_id = v_character_id;

  v_status_summary := coalesce(nullif(v_status_summary, ''), 'Alive | Conscious');

  v_summary := jsonb_build_object(
    'id', v_character.id,
    'character_key', v_character.character_key,
    'display_name', coalesce(nullif(trim(v_character.resources->>'name'), ''), nullif(trim(v_character.owner_player_name), ''), v_character.character_key),
    'character_bucket', v_character.character_bucket,
    'source_template_id', v_character.source_template_id,
    'source_template_key', v_character.source_template_key,
    'campaign_id', v_character.campaign_id,
    'room_id', v_character.room_id,
    'enabled', v_character.enabled,
    'is_deleted', v_character.is_deleted,
    'owner_player_id', v_character.owner_player_id,
    'owner_player_name', v_character.owner_player_name,
    'resources', coalesce(v_character.resources, '{}'::jsonb)
  );

  select jsonb_build_object(
    'state_version', coalesce(s.state_version, v_character.active_combat_state_version, 0),
    'status_summary', v_status_summary,
    'overlay_text', coalesce(s.overlay_text, ''),
    'overlay_data', coalesce(s.overlay_data, '{}'::jsonb),
    'is_alive', coalesce(s.is_alive, true),
    'is_conscious', coalesce(s.is_conscious, true),
    'tracker_minor', coalesce(s.tracker_minor, 0),
    'tracker_serious', coalesce(s.tracker_serious, 0),
    'armor_summary', coalesce(s.armor_summary, '{}'::jsonb),
    'equipment_summary', coalesce(s.equipment_summary, '{}'::jsonb),
    'effective_stats', coalesce(s.effective_stats, '{}'::jsonb),
    'combat_flags', coalesce(s.combat_flags, '{}'::jsonb),
    'updated_at', s.updated_at
  )
  into v_state
  from public.odyssey_character_combat_state s
  where s.character_id = v_character_id;

  v_state := coalesce(
    v_state,
    jsonb_build_object(
      'state_version', coalesce(v_character.active_combat_state_version, 0),
      'status_summary', v_status_summary,
      'overlay_text', '',
      'overlay_data', '{}'::jsonb,
      'is_alive', true,
      'is_conscious', true,
      'tracker_minor', 0,
      'tracker_serious', 0,
      'armor_summary', '{}'::jsonb,
      'equipment_summary', '{}'::jsonb,
      'effective_stats', '{}'::jsonb,
      'combat_flags', '{}'::jsonb,
      'updated_at', null
    )
  );

  if v_all_sections or 'combat' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'body_part_def_id', b.body_part_def_id,
          'code', coalesce(d.code, public.odyssey_normalize_part_code(b.part_key)),
          'name', coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key),
          'part_key', b.part_key,
          'sort_order', b.sort_order,
          'minor', b.minor,
          'serious', b.serious,
          'critical', b.critical,
          'max_critical', b.max_critical,
          'natural_armor_value', b.natural_armor_value,
          'armor_value', b.armor_value,
          'armor_minor', b.armor_minor,
          'armor_max_minor', b.armor_max_minor,
          'armor_serious', b.armor_serious,
          'armor_max_serious', b.armor_max_serious,
          'armor_critical', b.armor_critical,
          'armor_max_critical', b.armor_max_critical,
          'armor_destroyed', b.armor_destroyed,
          'disabled', b.disabled,
          'destroyed', b.destroyed,
          'can_be_targeted', coalesce(d.can_be_targeted, true),
          'aim_difficulty', coalesce(d.aim_difficulty, 0)
        )
        order by b.sort_order, b.part_key, b.id
      ),
      '[]'::jsonb
    )
    into v_body_parts
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.character_id = v_character_id;

    v_combat := jsonb_build_object(
      'state', v_state,
      'body_parts', v_body_parts,
      'body_summary', coalesce((v_state->'body_summary'), '[]'::jsonb),
      'armor_summary', coalesce((v_state->'armor_summary'), '{}'::jsonb),
      'combat_flags', coalesce((v_state->'combat_flags'), '{}'::jsonb)
    );
  end if;

  if v_all_sections or 'attributes' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'attribute_def_id', a.attribute_def_id,
          'code', d.code,
          'name', d.name,
          'value', a.value,
          'default_value', d.default_value,
          'max_value', d.max_value,
          'sort_order', d.sort_order
        )
        order by d.sort_order, d.code, a.id
      ),
      '[]'::jsonb
    )
    into v_attributes
    from public.odyssey_character_attributes a
    join public.odyssey_attribute_defs d on d.id = a.attribute_def_id
    where a.character_id = v_character_id;
  end if;

  if v_all_sections or 'skills' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'skill_def_id', s.skill_def_id,
          'code', d.code,
          'name', coalesce(nullif(trim(s.custom_name), ''), d.name),
          'category', d.category,
          'level', s.level,
          'max_level', d.max_level,
          'governing_attribute_def_id', s.governing_attribute_def_id,
          'notes', coalesce(s.notes, ''),
          'sort_order', d.sort_order
        )
        order by d.sort_order, d.code, s.id
      ),
      '[]'::jsonb
    )
    into v_skills
    from public.odyssey_character_skills s
    join public.odyssey_skill_defs d on d.id = s.skill_def_id
    where s.character_id = v_character_id;
  end if;

  if v_all_sections or 'perks' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'perk_def_id', p.perk_def_id,
          'code', d.code,
          'name', d.name,
          'description', coalesce(d.description, ''),
          'effect_type', d.effect_type,
          'effect_data', coalesce(d.effect_data, '{}'::jsonb),
          'acquired_at', p.acquired_at,
          'notes', coalesce(p.notes, '')
        )
        order by d.sort_order, d.name, p.id
      ),
      '[]'::jsonb
    )
    into v_perks
    from public.odyssey_character_perks p
    join public.odyssey_perk_defs d on d.id = p.perk_def_id
    where p.character_id = v_character_id;
  end if;

  if v_all_sections or 'equipment' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'equipment_model_id', e.equipment_model_id,
          'code', d.code,
          'name', coalesce(nullif(trim(e.custom_name), ''), d.name, d.code),
          'item_type', d.item_type,
          'is_equipped', e.is_equipped,
          'equipped_body_part_id', e.equipped_body_part_id,
          'equipped_body_part_code', coalesce(bp.code, public.odyssey_normalize_part_code(b.part_key)),
          'equipped_body_part_name', coalesce(nullif(trim(b.custom_name), ''), bp.name, b.part_key),
          'armor_value', e.armor_value,
          'armor_minor', e.armor_minor,
          'armor_max_minor', e.armor_max_minor,
          'armor_serious', e.armor_serious,
          'armor_max_serious', e.armor_max_serious,
          'armor_critical', e.armor_critical,
          'armor_max_critical', e.armor_max_critical,
          'armor_destroyed', e.armor_destroyed,
          'current_charges', e.current_charges,
          'max_charges', e.max_charges,
          'data', coalesce(e.data, '{}'::jsonb),
          'notes', coalesce(e.notes, ''),
          'sort_order', e.sort_order
        )
        order by e.sort_order, d.sort_order, d.name, e.id
      ),
      '[]'::jsonb
    )
    into v_equipment
    from public.odyssey_character_equipment_items e
    left join public.odyssey_equipment_model_defs d on d.id = e.equipment_model_id
    left join public.odyssey_character_body_parts b on b.id = e.equipped_body_part_id
    left join public.odyssey_body_part_defs bp on bp.id = b.body_part_def_id
    where e.character_id = v_character_id;
  end if;

  if v_all_sections or 'inventory' = any(v_requested) then
    select jsonb_build_object(
      'items', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', i.id,
              'item_def_id', i.item_def_id,
              'code', d.code,
              'name', coalesce(nullif(trim(i.custom_name), ''), d.name, d.code),
              'item_type', d.item_type,
              'use_action_type', d.use_action_type,
              'quantity', i.quantity,
              'current_charges', i.current_charges,
              'max_charges', i.max_charges,
              'location_data', coalesce(i.location_data, '{}'::jsonb),
              'data', coalesce(i.data, '{}'::jsonb),
              'notes', coalesce(i.notes, ''),
              'sort_order', i.sort_order
            )
            order by i.sort_order, d.sort_order, d.name, i.id
          )
          from public.odyssey_character_items i
          left join public.odyssey_item_defs d on d.id = i.item_def_id
          where i.character_id = v_character_id
        ),
        '[]'::jsonb
      ),
      'ammo_stock', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'display_name', a.display_name,
              'caliber_id', a.caliber_id,
              'ammo_type_id', a.ammo_type_id,
              'ammo_code', at.code,
              'ammo_name', at.name,
              'quantity', a.quantity,
              'location_data', coalesce(a.location_data, '{}'::jsonb),
              'data', coalesce(a.data, '{}'::jsonb),
              'notes', coalesce(a.notes, '')
            )
            order by a.display_name, at.name, a.id
          )
          from public.odyssey_character_ammo_stock a
          left join public.odyssey_ammo_type_defs at on at.id = a.ammo_type_id
          where a.character_id = v_character_id
        ),
        '[]'::jsonb
      ),
      'magazines', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', m.id,
              'magazine_def_id', m.magazine_def_id,
              'code', md.code,
              'name', coalesce(nullif(trim(m.custom_name), ''), md.name, md.code),
              'ammo_type_id', m.ammo_type_id,
              'ammo_code', at.code,
              'ammo_name', at.name,
              'current_rounds', m.current_rounds,
              'capacity', md.capacity,
              'notes', coalesce(m.notes, '')
            )
            order by md.sort_order, md.name, m.id
          )
          from public.odyssey_character_magazines m
          left join public.odyssey_magazine_defs md on md.id = m.magazine_def_id
          left join public.odyssey_ammo_type_defs at on at.id = m.ammo_type_id
          where m.character_id = v_character_id
        ),
        '[]'::jsonb
      )
    )
    into v_inventory;
  end if;

  if v_all_sections or 'armory' = any(v_requested) then
    select jsonb_build_object(
      'weapons', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', w.id,
              'weapon_model_id', w.weapon_model_id,
              'code', wd.code,
              'name', coalesce(nullif(trim(w.custom_name), ''), wd.name, wd.code),
              'base_accuracy_bonus', wd.base_accuracy_bonus,
              'base_melee_damage', wd.base_melee_damage,
              'loaded_magazine_id', w.loaded_magazine_id,
              'selected_fire_mode_id', w.selected_fire_mode_id,
              'active_profile_id', w.active_profile_id,
              'notes', coalesce(w.notes, ''),
              'sort_order', w.sort_order,
              'profiles', coalesce(
                (
                  select jsonb_agg(
                    jsonb_build_object(
                      'state_id', ps.id,
                      'profile_id', p.id,
                      'code', p.code,
                      'name', p.name,
                      'attack_type', p.attack_type,
                      'base_melee_damage', p.base_melee_damage,
                      'accuracy_modifier', p.accuracy_modifier,
                      'is_active', ps.is_active,
                      'loaded_magazine_id', ps.loaded_magazine_id,
                      'selected_fire_mode_id', ps.selected_fire_mode_id,
                      'loaded_magazine', case when m.id is null then null else jsonb_build_object(
                        'id', m.id,
                        'name', coalesce(nullif(trim(m.custom_name), ''), md.name, md.code),
                        'current_rounds', m.current_rounds,
                        'capacity', md.capacity,
                        'ammo_code', at.code,
                        'ammo_name', at.name
                      ) end,
                      'selected_fire_mode', case when fm.id is null then null else jsonb_build_object(
                        'id', fm.id,
                        'code', fm.code,
                        'name', fm.name,
                        'accuracy_modifier', fm.accuracy_modifier,
                        'fixed_rounds', fm.fixed_rounds,
                        'min_rounds', fm.min_rounds,
                        'max_rounds', fm.max_rounds,
                        'is_random', fm.is_random
                      ) end,
                      'data', coalesce(ps.data, '{}'::jsonb)
                    )
                    order by p.sort_order, p.code, ps.id
                  )
                  from public.odyssey_character_weapon_profile_states ps
                  join public.odyssey_weapon_model_profiles p on p.id = ps.profile_id
                  left join public.odyssey_character_magazines m on m.id = ps.loaded_magazine_id
                  left join public.odyssey_magazine_defs md on md.id = m.magazine_def_id
                  left join public.odyssey_ammo_type_defs at on at.id = m.ammo_type_id
                  left join public.odyssey_fire_mode_defs fm on fm.id = ps.selected_fire_mode_id
                  where ps.character_weapon_id = w.id
                ),
                '[]'::jsonb
              ),
              'features', coalesce(
                (
                  select jsonb_agg(
                    jsonb_build_object(
                      'state_id', fs.id,
                      'feature_def_id', fd.id,
                      'code', fd.code,
                      'name', fd.name,
                      'feature_type', fd.feature_type,
                      'activation_type', fd.activation_type,
                      'is_active', fs.is_active,
                      'is_enabled', fs.is_enabled,
                      'current_charges', fs.current_charges,
                      'max_charges', fs.max_charges,
                      'recharge_rounds_left', fs.recharge_rounds_left,
                      'cooldown_rounds_left', fs.cooldown_rounds_left,
                      'active_rounds_left', fs.active_rounds_left,
                      'active_uses_left', fs.active_uses_left,
                      'requires_reload', fs.requires_reload,
                      'requires_reload_item_code', fd.requires_reload_item_code,
                      'profile_id', fs.profile_id,
                      'data', coalesce(fs.data, '{}'::jsonb),
                      'definition_data', coalesce(fd.data, '{}'::jsonb),
                      'effect_data', coalesce(fd.effect_data, '{}'::jsonb)
                    )
                    order by fd.sort_order, fd.code, fs.id
                  )
                  from public.odyssey_character_weapon_feature_states fs
                  join public.odyssey_weapon_feature_defs fd on fd.id = fs.feature_def_id
                  where fs.character_weapon_id = w.id
                ),
                '[]'::jsonb
              )
            )
            order by w.sort_order, wd.sort_order, wd.name, w.id
          )
          from public.odyssey_character_weapons w
          left join public.odyssey_weapon_model_defs wd on wd.id = w.weapon_model_id
          where w.character_id = v_character_id
        ),
        '[]'::jsonb
      )
    )
    into v_armory;
  end if;

  if v_all_sections or 'abilities' = any(v_requested) then
    select jsonb_build_object(
      'abilities', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', a.id,
              'ability_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'ability_kind', d.ability_kind,
              'source_type', d.source_type,
              'activation_type', d.activation_type,
              'target_type', d.target_type,
              'effect_mode', d.effect_mode,
              'attack_type', d.attack_type,
              'resource_mode', d.resource_mode,
              'resource_pool_code', d.resource_pool_code,
              'resource_item_code', d.resource_item_code,
              'character_skill_id', a.character_skill_id,
              'learned_level', a.learned_level,
              'source_equipment_item_id', a.source_equipment_item_id,
              'source_character_item_id', a.source_character_item_id,
              'is_enabled', a.is_enabled,
              'is_hidden', a.is_hidden,
              'current_cooldown_rounds', a.current_cooldown_rounds,
              'current_charges', a.current_charges,
              'max_charges', a.max_charges,
              'description', coalesce(d.description, ''),
              'data', coalesce(a.data, '{}'::jsonb),
              'definition_data', coalesce(d.data, '{}'::jsonb),
              'effect_data', coalesce(d.effect_data, '{}'::jsonb),
              'notes', coalesce(a.notes, ''),
              'sort_order', a.sort_order
            )
            order by a.sort_order, d.sort_order, d.name, a.id
          )
          from public.odyssey_character_abilities a
          join public.odyssey_ability_defs d on d.id = a.ability_def_id
          where a.character_id = v_character_id
        ),
        '[]'::jsonb
      ),
      'resource_pools', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', p.id,
              'resource_pool_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'source_type', d.source_type,
              'recovery_mode', d.recovery_mode,
              'current_value', p.current_value,
              'max_value', p.max_value,
              'reserved_value', p.reserved_value,
              'data', coalesce(p.data, '{}'::jsonb),
              'notes', coalesce(p.notes, '')
            )
            order by d.sort_order, d.name, p.id
          )
          from public.odyssey_character_resource_pools p
          join public.odyssey_resource_pool_defs d on d.id = p.resource_pool_def_id
          where p.character_id = v_character_id
        ),
        '[]'::jsonb
      )
    )
    into v_abilities;
  end if;

  if v_all_sections or 'effects' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'effect_def_id', e.effect_def_id,
          'effect_key', e.effect_key,
          'name', e.name,
          'description', e.description,
          'source', e.source,
          'source_type', e.source_type,
          'source_id', e.source_id,
          'source_character_id', e.source_character_id,
          'duration_type', e.duration_type,
          'rounds_left', e.rounds_left,
          'stacks', e.stacks,
          'is_active', e.is_active,
          'data', coalesce(e.data, '{}'::jsonb),
          'created_at', e.created_at,
          'updated_at', e.updated_at
        )
        order by e.created_at, e.id
      ),
      '[]'::jsonb
    )
    into v_effects
    from public.odyssey_character_effects e
    where e.character_id = v_character_id
      and e.is_active = true;
  end if;

  if v_all_sections or 'token_link' = any(v_requested) then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'campaign_id', t.campaign_id,
          'room_id', t.room_id,
          'scene_id', t.scene_id,
          'token_id', t.token_id,
          'token_name', t.token_name,
          'token_layer', t.token_layer,
          'is_active', t.is_active,
          'last_seen_at', t.last_seen_at,
          'updated_at', t.updated_at
        )
        order by t.is_active desc, t.updated_at desc, t.created_at desc, t.id
      ),
      '[]'::jsonb
    )
    into v_token_links
    from public.odyssey_token_links t
    where t.character_id = v_character_id
      and t.is_active = true
      and (v_room_id = '' or t.room_id = v_room_id)
      and (v_scene_id = '' or t.scene_id = v_scene_id);
  end if;

  if v_all_sections or 'summary' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('summary', v_summary);
  end if;
  if v_all_sections or 'combat' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('combat', v_combat);
  end if;
  if v_all_sections or 'attributes' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('attributes', v_attributes);
  end if;
  if v_all_sections or 'skills' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('skills', v_skills);
  end if;
  if v_all_sections or 'perks' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('perks', v_perks);
  end if;
  if v_all_sections or 'equipment' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('equipment', v_equipment);
  end if;
  if v_all_sections or 'inventory' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('inventory', v_inventory);
  end if;
  if v_all_sections or 'armory' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('armory', v_armory);
  end if;
  if v_all_sections or 'abilities' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('abilities', v_abilities);
  end if;
  if v_all_sections or 'effects' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('effects', v_effects);
  end if;
  if v_all_sections or 'token_link' = any(v_requested) then
    v_sections := v_sections || jsonb_build_object('token_link', v_token_links);
  end if;

  return jsonb_build_object(
    'ok', true,
    'character', v_summary,
    'state', v_state,
    'sections', v_sections,
    'section_errors', '{}'::jsonb
  );
end;
$$;

create or replace function public.get_scene_token_links(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'token_id', '')), ''), '');
  v_include_inactive boolean := coalesce(nullif(trim(coalesce(p_payload->>'include_inactive', '')), '')::boolean, false);
  v_links jsonb := '[]'::jsonb;
begin
  if v_room_id = '' or v_scene_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'room_id and scene_id are required.'
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'campaign_id', t.campaign_id,
        'room_id', t.room_id,
        'scene_id', t.scene_id,
        'token_id', t.token_id,
        'token_name', t.token_name,
        'token_layer', t.token_layer,
        'is_active', t.is_active,
        'last_seen_at', t.last_seen_at,
        'updated_at', t.updated_at,
        'character', case when c.id is null then null else jsonb_build_object(
          'id', c.id,
          'character_key', c.character_key,
          'display_name', coalesce(nullif(trim(c.resources->>'name'), ''), nullif(trim(c.owner_player_name), ''), c.character_key),
          'character_bucket', c.character_bucket,
          'source_template_id', c.source_template_id,
          'source_template_key', c.source_template_key,
          'enabled', c.enabled,
          'is_deleted', c.is_deleted
        ) end,
        'state', case when c.id is null then null else jsonb_build_object(
          'state_version', coalesce(s.state_version, c.active_combat_state_version, 0),
          'status_summary', coalesce(nullif(trim(s.status_summary), ''), public.odyssey_build_character_status_summary(c.id)),
          'overlay_text', coalesce(s.overlay_text, ''),
          'is_alive', coalesce(s.is_alive, true),
          'is_conscious', coalesce(s.is_conscious, true),
          'updated_at', s.updated_at
        ) end
      )
      order by t.is_active desc, t.updated_at desc, t.created_at desc, t.token_name, t.token_id
    ),
    '[]'::jsonb
  )
  into v_links
  from public.odyssey_token_links t
  left join public.odyssey_characters c on c.id = t.character_id
  left join public.odyssey_character_combat_state s on s.character_id = t.character_id
  where t.room_id = v_room_id
    and t.scene_id = v_scene_id
    and (v_campaign_id = '' or t.campaign_id = v_campaign_id)
    and (v_token_id = '' or t.token_id = v_token_id)
    and (v_include_inactive or t.is_active = true);

  return jsonb_build_object(
    'ok', true,
    'room_id', v_room_id,
    'scene_id', v_scene_id,
    'links', v_links
  );
end;
$$;

create or replace function public.unbind_token_character(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'token_id', '')), ''), '');
  v_link public.odyssey_token_links%rowtype;
  v_character public.odyssey_characters%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_room_id = '' or v_scene_id = '' or v_token_id = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'room_id, scene_id and token_id are required.'
    );
  end if;

  select *
  into v_link
  from public.odyssey_token_links t
  where t.room_id = v_room_id
    and t.scene_id = v_scene_id
    and t.token_id = v_token_id
    and t.is_active = true
  order by t.updated_at desc, t.created_at desc, t.id desc
  limit 1
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'TOKEN_LINK_NOT_FOUND',
      'message', 'Selected token does not have an active character link.',
      'room_id', v_room_id,
      'scene_id', v_scene_id,
      'token_id', v_token_id
    );
  end if;

  select *
  into v_character
  from public.odyssey_characters c
  where c.id = v_link.character_id;

  update public.odyssey_token_links
  set is_active = false,
      last_seen_at = v_now,
      updated_at = v_now
  where id = v_link.id;

  return jsonb_build_object(
    'ok', true,
    'unbound', true,
    'token_link', jsonb_build_object(
      'id', v_link.id,
      'room_id', v_link.room_id,
      'scene_id', v_link.scene_id,
      'token_id', v_link.token_id,
      'is_active', false
    ),
    'character', case when v_character.id is null then null else jsonb_build_object(
      'id', v_character.id,
      'character_key', v_character.character_key,
      'display_name', coalesce(nullif(trim(v_character.resources->>'name'), ''), nullif(trim(v_character.owner_player_name), ''), v_character.character_key),
      'character_bucket', v_character.character_bucket
    ) end
  );
end;
$$;

-- Purges active NPCs. "archive" is reversible through direct DB maintenance;
-- "hard_delete" physically removes selected NPC_Active rows and related combat history.
create or replace function public.purge_active_npcs(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_scope text := lower(coalesce(nullif(trim(coalesce(p_payload->>'scope', '')), ''), 'all'));
  v_mode text := lower(coalesce(nullif(trim(coalesce(p_payload->>'mode', '')), ''), 'hard_delete'));
  v_confirm text := trim(coalesce(p_payload->>'confirm', ''));
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_target_ids uuid[] := array[]::uuid[];
  v_target_count integer := 0;
  v_link_count integer := 0;
  v_log_count integer := 0;
  v_initiative_count integer := 0;
  v_now timestamptz := timezone('utc', now());
begin
  if v_scope not in ('all', 'campaign', 'room', 'scene') then
    return jsonb_build_object('ok', false, 'error', 'INVALID_SCOPE', 'message', 'scope must be all, campaign, room or scene.');
  end if;

  if v_mode not in ('archive', 'hard_delete') then
    return jsonb_build_object('ok', false, 'error', 'INVALID_PURGE_MODE', 'message', 'mode must be archive or hard_delete.');
  end if;

  if v_scope = 'campaign' and v_campaign_id = '' then
    return jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'message', 'campaign_id is required for campaign scope.');
  end if;

  if v_scope = 'room' and v_room_id = '' then
    return jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'message', 'room_id is required for room scope.');
  end if;

  if v_scope = 'scene' and (v_room_id = '' or v_scene_id = '') then
    return jsonb_build_object('ok', false, 'error', 'INVALID_PAYLOAD', 'message', 'room_id and scene_id are required for scene scope.');
  end if;

  if v_mode = 'archive' and v_confirm <> 'ARCHIVE_ACTIVE_NPCS' then
    return jsonb_build_object('ok', false, 'error', 'CONFIRMATION_REQUIRED', 'message', 'confirm must equal ARCHIVE_ACTIVE_NPCS.');
  end if;

  if v_mode = 'hard_delete' and v_confirm <> 'PURGE_ACTIVE_NPCS' then
    return jsonb_build_object('ok', false, 'error', 'CONFIRMATION_REQUIRED', 'message', 'confirm must equal PURGE_ACTIVE_NPCS.');
  end if;

  select coalesce(array_agg(target_rows.id), array[]::uuid[])
  into v_target_ids
  from (
    select c.id
    from public.odyssey_characters c
    where c.character_bucket = 'npc_active'
      and (
        v_scope = 'all'
        or (v_scope = 'campaign' and c.campaign_id = v_campaign_id)
        or (v_scope = 'room' and c.room_id = v_room_id)
        or (
          v_scope = 'scene'
          and exists (
            select 1
            from public.odyssey_token_links t
            where t.character_id = c.id
              and t.room_id = v_room_id
              and t.scene_id = v_scene_id
          )
        )
      )
    for update
  ) as target_rows;

  v_target_count := cardinality(v_target_ids);

  if v_target_count = 0 then
    return jsonb_build_object(
      'ok', true,
      'mode', v_mode,
      'scope', v_scope,
      'purged_count', 0,
      'message', 'No NPC_Active records matched the requested scope.'
    );
  end if;

  if v_mode = 'archive' then
    update public.odyssey_token_links
    set is_active = false,
        last_seen_at = v_now,
        updated_at = v_now
    where character_id = any(v_target_ids)
      and is_active = true;
    get diagnostics v_link_count = row_count;

    update public.odyssey_characters
    set is_deleted = true,
        enabled = false,
        updated_at = v_now
    where id = any(v_target_ids)
      and character_bucket = 'npc_active';

    return jsonb_build_object(
      'ok', true,
      'mode', 'archive',
      'scope', v_scope,
      'archived_count', v_target_count,
      'deactivated_token_links', v_link_count,
      'message', 'Selected NPC_Active records were archived and hidden from normal UI queries.'
    );
  end if;

  -- Hard deletion deliberately removes only logs involving the NPCs being purged.
  delete from public.odyssey_combat_log l
  where l.actor_character_id = any(v_target_ids)
     or l.target_character_id = any(v_target_ids);
  get diagnostics v_log_count = row_count;

  update public.odyssey_combat_encounters e
  set active_character_id = null,
      active_entry_id = null,
      updated_at = v_now
  where e.active_character_id = any(v_target_ids)
     or e.active_entry_id in (
       select ie.id
       from public.odyssey_initiative_entries ie
       where ie.character_id = any(v_target_ids)
     );

  delete from public.odyssey_initiative_entries ie
  where ie.character_id = any(v_target_ids);
  get diagnostics v_initiative_count = row_count;

  update public.odyssey_character_effects e
  set source_character_id = null,
      updated_at = v_now
  where e.source_character_id = any(v_target_ids);

  delete from public.odyssey_token_links t
  where t.character_id = any(v_target_ids);
  get diagnostics v_link_count = row_count;

  delete from public.odyssey_characters c
  where c.id = any(v_target_ids)
    and c.character_bucket = 'npc_active';

  return jsonb_build_object(
    'ok', true,
    'mode', 'hard_delete',
    'scope', v_scope,
    'deleted_count', v_target_count,
    'deleted_token_links', v_link_count,
    'deleted_initiative_entries', v_initiative_count,
    'deleted_combat_logs', v_log_count,
    'message', 'Selected NPC_Active records and their dependent gameplay data were permanently deleted.'
  );
end;
$$;

-- Realtime publication entries needed by the UI. Safe if already present.
do $$
declare
  v_table text;
  v_tables text[] := array[
    'odyssey_characters',
    'odyssey_token_links',
    'odyssey_character_combat_state',
    'odyssey_character_effects',
    'odyssey_character_body_parts',
    'odyssey_character_attributes',
    'odyssey_character_skills',
    'odyssey_character_perks',
    'odyssey_character_equipment_items',
    'odyssey_character_items',
    'odyssey_character_ammo_stock',
    'odyssey_character_weapons',
    'odyssey_character_weapon_profile_states',
    'odyssey_character_weapon_feature_states',
    'odyssey_character_magazines',
    'odyssey_character_abilities',
    'odyssey_character_resource_pools'
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  foreach v_table in array v_tables loop
    if not exists (
      select 1
      from pg_publication_tables ppt
      where ppt.pubname = 'supabase_realtime'
        and ppt.schemaname = 'public'
        and ppt.tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

grant execute on function public.get_character_runtime_bundle(jsonb) to anon, authenticated;
grant execute on function public.get_scene_token_links(jsonb) to anon, authenticated;
grant execute on function public.unbind_token_character(jsonb) to anon, authenticated;
grant execute on function public.purge_active_npcs(jsonb) to anon, authenticated;
