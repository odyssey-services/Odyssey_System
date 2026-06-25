-- Stage 71: expose separate attribute bonuses and penalties in the rule sheet.
-- UI can now show +N and -N at the same time while still using effective_value as the net result.

create or replace function public.get_character_rule_sheet(
  p_character_id uuid
)
returns jsonb
language sql
stable
as $$
  with selected_character as (
    select
      c.id,
      c.character_key,
      c.character_bucket,
      c.enabled,
      c.owner_player_id,
      c.owner_player_name,
      c.resources,
      coalesce(nullif(trim(c.resources->>'name'), ''), c.character_key) as character_name
    from public.odyssey_characters c
    where c.id = p_character_id
      and coalesce(c.is_deleted, false) = false
  ),
  effect_summary as (
    select public.get_character_effect_summary(p_character_id) as effect_summary
    from selected_character
  ),
  progression as (
    select
      coalesce(p.development_points, 0) as development_points,
      coalesce(p.lifetime_points_granted, 0) as lifetime_points_granted,
      coalesce(p.lifetime_points_spent, 0) as lifetime_points_spent
    from selected_character c
    left join public.odyssey_character_progression p on p.character_id = c.id
  )
  select jsonb_build_object(
    'character',
      jsonb_build_object(
        'id', c.id,
        'character_key', c.character_key,
        'character_bucket', c.character_bucket,
        'name', c.character_name,
        'enabled', c.enabled,
        'owner_player_id', c.owner_player_id,
        'owner_player_name', c.owner_player_name,
        'resources', c.resources
      ),
    'progression',
      jsonb_build_object(
        'development_points', coalesce((select development_points from progression), 0),
        'lifetime_points_granted', coalesce((select lifetime_points_granted from progression), 0),
        'lifetime_points_spent', coalesce((select lifetime_points_spent from progression), 0)
      ),
    'attributes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', d.id,
              'attribute_def_id', d.id,
              'code', d.code,
              'name', d.name,
              'value', coalesce(a.value, d.default_value, 0),
              'base_value', coalesce(a.value, d.default_value, 0),
              'effect_modifier',
                case
                  when d.code is null then 0
                  else coalesce(
                    nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', d.code), '')::integer,
                    0
                  )
                end,
              'effect_bonus',
                case
                  when d.code is null then 0
                  else coalesce(
                    (
                      select sum(greatest(coalesce(nullif(trim(coalesce(modifier->>'value', '')), '')::integer, 0), 0))::integer
                      from jsonb_array_elements(coalesce(effect_summary.effect_summary->'modifier_rows', '[]'::jsonb)) modifier
                      where lower(coalesce(modifier->>'target', '')) = 'attribute'
                        and lower(coalesce(modifier->>'attribute', '')) = lower(d.code)
                    ),
                    0
                  )
                end,
              'effect_penalty',
                case
                  when d.code is null then 0
                  else coalesce(
                    (
                      select sum(abs(least(coalesce(nullif(trim(coalesce(modifier->>'value', '')), '')::integer, 0), 0)))::integer
                      from jsonb_array_elements(coalesce(effect_summary.effect_summary->'modifier_rows', '[]'::jsonb)) modifier
                      where lower(coalesce(modifier->>'target', '')) = 'attribute'
                        and lower(coalesce(modifier->>'attribute', '')) = lower(d.code)
                    ),
                    0
                  )
                end,
              'effective_value',
                coalesce(a.value, d.default_value, 0)
                + case
                    when d.code is null then 0
                    else coalesce(
                      nullif(jsonb_extract_path_text(effect_summary.effect_summary, 'modifiers', 'attributes', d.code), '')::integer,
                      0
                    )
                  end,
              'default_value', d.default_value,
              'max_value', d.max_value,
              'cost_per_level', d.cost_per_level,
              'description', d.description,
              'sort_order', d.sort_order,
              'is_custom', d.is_custom
            )
            order by d.sort_order, d.name
          )
          from public.odyssey_attribute_defs d
          left join public.odyssey_character_attributes a
            on a.attribute_def_id = d.id
           and a.character_id = c.id
          cross join effect_summary
        ),
        '[]'::jsonb
      ),
    'skills',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', skill_state.skill_def_id,
              'character_skill_id', skill_state.character_skill_id,
              'skill_def_id', skill_state.skill_def_id,
              'code', skill_state.skill_code,
              'name', skill_state.skill_name,
              'custom_name', skill_state.custom_name,
              'category', skill_state.skill_category,
              'level', skill_state.purchased_level,
              'purchased_level', skill_state.purchased_level,
              'base_effective_level', skill_state.base_effective_level,
              'effect_level_modifier', skill_state.effect_level_modifier,
              'effective_level', skill_state.effective_level,
              'skill_bonus', skill_state.skill_bonus,
              'effect_skill_bonus', skill_state.effect_skill_bonus,
              'max_level', skill_state.max_level,
              'is_passive', skill_state.is_passive,
              'is_trained', skill_state.is_trained,
              'requirements_met', skill_state.current_level_requirements_met,
              'main_attribute',
                case
                  when skill_state.main_attribute_def_id is null then 'null'::jsonb
                  else jsonb_build_object(
                    'id', skill_state.main_attribute_def_id,
                    'code', skill_state.main_attribute_code,
                    'name', skill_state.main_attribute_name,
                    'base_value', skill_state.main_base_value,
                    'effect_modifier', skill_state.main_effect_modifier,
                    'effective_value', skill_state.main_effective_value
                  )
                end,
              'secondary_attribute',
                case
                  when skill_state.secondary_attribute_def_id is null then 'null'::jsonb
                  else jsonb_build_object(
                    'id', skill_state.secondary_attribute_def_id,
                    'code', skill_state.secondary_attribute_code,
                    'name', skill_state.secondary_attribute_name,
                    'base_value', skill_state.secondary_base_value,
                    'effect_modifier', skill_state.secondary_effect_modifier,
                    'effective_value', skill_state.secondary_effective_value
                  )
                end,
              'governing_attribute', governing_attr.code,
              'tags', skill_state.skill_tags,
              'description', skill_state.description,
              'notes', skill_state.notes,
              'next_level',
                case
                  when skill_state.purchased_level >= skill_state.max_level then 'null'::jsonb
                  else jsonb_build_object(
                    'target_level', skill_state.purchased_level + 1,
                    'cost', next_purchase_req.development_point_cost,
                    'advancement_mode', next_purchase_req.advancement_mode,
                    'main_attribute_required', next_purchase_req.main_attribute_required,
                    'secondary_attribute_required', next_purchase_req.secondary_attribute_required
                  )
                end
            )
            order by skill_state.skill_category, skill_state.sort_order, skill_state.skill_name
          )
          from public.odyssey_get_effective_character_skill_states(c.id) skill_state
          left join public.odyssey_attribute_defs governing_attr on governing_attr.id = skill_state.governing_attribute_def_id
          left join public.odyssey_skill_level_requirements next_purchase_req
            on next_purchase_req.skill_def_id = skill_state.skill_def_id
           and next_purchase_req.level = case
             when skill_state.purchased_level >= skill_state.max_level then null
             else skill_state.purchased_level + 1
           end
        ),
        '[]'::jsonb
      ),
    'perks',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', owned.id,
              'perk_def_id', perk.id,
              'code', perk.code,
              'name', perk.name,
              'skill_code', skill.code,
              'required_skill_level', perk.required_skill_level,
              'effect_type', perk.effect_type,
              'effect_data', perk.effect_data,
              'tags', perk.tags,
              'notes', owned.notes,
              'acquired_at', owned.acquired_at
            )
            order by perk.name
          )
          from public.odyssey_character_perks owned
          join public.odyssey_perk_defs perk on perk.id = owned.perk_def_id
          left join public.odyssey_skill_defs skill on skill.id = perk.skill_def_id
          where owned.character_id = c.id
        ),
        '[]'::jsonb
      ),
    'body_parts',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', b.id,
              'body_part_def_id', d.id,
              'code', d.code,
              'name', coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key),
              'custom_name', b.custom_name,
              'part_key', b.part_key,
              'minor', b.minor,
              'serious', b.serious,
              'critical', b.critical,
              'max_critical', b.max_critical,
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
              'aim_difficulty', coalesce(d.aim_difficulty, 0),
              'serious_counts_as_critical', coalesce(d.serious_counts_as_critical, false),
              'category', d.category,
              'tags', coalesce(d.tags, '[]'::jsonb),
              'sort_order', b.sort_order
            )
            order by b.sort_order, b.part_key
          )
          from public.odyssey_character_body_parts b
          left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
          where b.character_id = c.id
        ),
        '[]'::jsonb
      )
  )
  from selected_character c;
$$;
