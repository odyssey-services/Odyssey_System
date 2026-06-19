create or replace function public.odyssey_apply_equipment_critical_damage(
  p_body_part_id uuid,
  p_critical_delta integer
)
returns jsonb
language plpgsql
as $$
declare
  v_item record;
  v_body_part record;
  v_requested integer := greatest(coalesce(p_critical_delta, 0), 0);
  v_remaining integer := 0;
  v_absorbed_by_items integer := 0;
  v_total_absorbed integer := 0;
  v_body_available integer := 0;
  v_absorb integer := 0;
  v_updates jsonb := '[]'::jsonb;
  v_new_item_armor_critical integer := 0;
  v_new_item_armor_destroyed boolean := false;
  v_new_body_armor_critical integer := 0;
  v_new_body_armor_destroyed boolean := false;
begin
  if v_requested <= 0 then
    return jsonb_build_object(
      'absorbed', 0,
      'remaining', 0,
      'updated_items', '[]'::jsonb,
      'body_part', null
    );
  end if;

  select
    b.id,
    b.armor_critical,
    b.armor_max_critical,
    b.armor_destroyed
  into v_body_part
  from public.odyssey_character_body_parts b
  where b.id = p_body_part_id
  for update of b;

  if not found then
    return jsonb_build_object(
      'absorbed', 0,
      'remaining', v_requested,
      'updated_items', '[]'::jsonb,
      'body_part', null
    );
  end if;

  v_body_available := greatest(
    coalesce(v_body_part.armor_max_critical, 0) - coalesce(v_body_part.armor_critical, 0),
    0
  );

  v_total_absorbed := least(v_requested, v_body_available);
  v_remaining := v_total_absorbed;

  for v_item in
    select
      e.id,
      e.armor_critical,
      e.armor_max_critical,
      e.armor_destroyed,
      e.sort_order,
      e.created_at,
      coalesce(nullif(trim(e.custom_name), ''), m.name) as item_name
    from public.odyssey_character_equipment_items e
    join public.odyssey_equipment_model_defs m on m.id = e.equipment_model_id
    where e.equipped_body_part_id = p_body_part_id
      and e.is_equipped = true
    order by e.sort_order, e.created_at, e.id
    for update of e
  loop
    exit when v_remaining <= 0;

    if coalesce(v_item.armor_max_critical, 0) <= coalesce(v_item.armor_critical, 0) then
      continue;
    end if;

    v_absorb := least(
      v_remaining,
      greatest(coalesce(v_item.armor_max_critical, 0) - coalesce(v_item.armor_critical, 0), 0)
    );

    if v_absorb <= 0 then
      continue;
    end if;

    v_new_item_armor_critical := coalesce(v_item.armor_critical, 0) + v_absorb;
    v_new_item_armor_destroyed := case
      when coalesce(v_item.armor_max_critical, 0) > 0
        and v_new_item_armor_critical >= coalesce(v_item.armor_max_critical, 0) then true
      else coalesce(v_item.armor_destroyed, false)
    end;

    update public.odyssey_character_equipment_items
    set
      armor_critical = v_new_item_armor_critical,
      armor_destroyed = v_new_item_armor_destroyed,
      updated_at = timezone('utc', now())
    where id = v_item.id;

    v_updates := v_updates || jsonb_build_array(
      jsonb_build_object(
        'id', v_item.id,
        'name', v_item.item_name,
        'absorbed_critical', v_absorb,
        'armor_critical', v_new_item_armor_critical,
        'armor_max_critical', coalesce(v_item.armor_max_critical, 0),
        'armor_destroyed', v_new_item_armor_destroyed
      )
    );

    v_absorbed_by_items := v_absorbed_by_items + v_absorb;
    v_remaining := v_remaining - v_absorb;
  end loop;

  v_new_body_armor_critical := greatest(coalesce(v_body_part.armor_critical, 0) + v_total_absorbed, 0);
  v_new_body_armor_destroyed := case
    when coalesce(v_body_part.armor_max_critical, 0) > 0
      and v_new_body_armor_critical >= coalesce(v_body_part.armor_max_critical, 0) then true
    when coalesce(v_body_part.armor_max_critical, 0) > 0 then false
    else coalesce(v_body_part.armor_destroyed, false)
  end;

  update public.odyssey_character_body_parts
  set
    armor_critical = v_new_body_armor_critical,
    armor_destroyed = v_new_body_armor_destroyed
  where id = p_body_part_id;

  return jsonb_build_object(
    'absorbed', v_total_absorbed,
    'remaining', greatest(v_requested - v_total_absorbed, 0),
    'updated_items', v_updates,
    'body_part',
      jsonb_build_object(
        'id', v_body_part.id,
        'armor_critical', v_new_body_armor_critical,
        'armor_max_critical', coalesce(v_body_part.armor_max_critical, 0),
        'armor_destroyed', v_new_body_armor_destroyed,
        'absorbed_by_items', v_absorbed_by_items,
        'absorbed_by_body_part', greatest(v_total_absorbed - v_absorbed_by_items, 0)
      )
  );
end;
$$;

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'odyssey_perform_weapon_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_weapon_attack(jsonb) was not found.';
  end if;

  if position('v_armor_pierce := greatest(v_armor_pierce + v_feature_armor_pierce_modifier, 0);' in v_function_def) = 0 then
    raise exception 'Could not find armor pierce clamp in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  if position('perform public.recompute_character_armor(v_target_character_id);' in v_function_def) = 0 then
    raise exception 'Could not find recompute_character_armor attack-path call in public.odyssey_perform_weapon_attack(jsonb).';
  end if;

  v_function_def := replace(
    v_function_def,
    'v_armor_pierce := greatest(v_armor_pierce + v_feature_armor_pierce_modifier, 0);',
    'v_armor_pierce := coalesce(v_armor_pierce, 0) + v_feature_armor_pierce_modifier;'
  );

  v_function_def := replace(
    v_function_def,
    'perform public.recompute_character_armor(v_target_character_id);',
    ''
  );

  execute v_function_def;
end;
$$;

do $$
declare
  v_function_def text := null;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_effective_character_stats'
    and pg_get_function_identity_arguments(p.oid) = 'p_character_id uuid';

  if v_function_def is null then
    raise exception 'Function public.get_effective_character_stats(uuid) was not found.';
  end if;

  if position('v_is_alive := not v_is_alive;' in v_function_def) = 0 then
    raise exception 'Could not find is_alive inversion in public.get_effective_character_stats(uuid).';
  end if;

  v_function_def := replace(
    v_function_def,
    'v_is_alive := not v_is_alive;',
    'v_is_alive := true;'
  );

  execute v_function_def;
end;
$$;

create or replace function public.odyssey_finalize_attack_result(
  p_result jsonb,
  p_target_character_id uuid,
  p_target_body_part_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_result jsonb := coalesce(p_result, '{}'::jsonb);
  v_body_part jsonb := '{}'::jsonb;
  v_target_state jsonb := '{}'::jsonb;
  v_pending_checks jsonb := case
    when jsonb_typeof(v_result->'pending_checks') = 'array' then v_result->'pending_checks'
    else '[]'::jsonb
  end;
  v_execution jsonb := case
    when jsonb_typeof(v_result->'execution') = 'object' then v_result->'execution'
    else '{}'::jsonb
  end;
  v_auto text := null;
  v_attack_roll integer := 0;
  v_hit boolean := false;
  v_body_critical_delta integer := 0;
  v_possible_death boolean := false;
begin
  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result;
  end if;

  if p_target_character_id is not null then
    perform public.odyssey_recalculate_character_body_part_caps(p_target_character_id);
  end if;

  if p_target_body_part_id is not null then
    perform public.odyssey_normalize_body_part_damage(p_target_body_part_id);
    v_body_part := coalesce(public.odyssey_get_character_body_part_state(p_target_body_part_id), '{}'::jsonb);
  end if;

  if p_target_character_id is not null then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(p_target_character_id)->'combat_state', '{}'::jsonb);
  end if;

  v_attack_roll := coalesce(nullif(jsonb_extract_path_text(v_result, 'attack', 'roll'), '')::integer, 0);
  v_hit := coalesce((v_result->>'hit')::boolean, false);
  v_body_critical_delta := coalesce(nullif(jsonb_extract_path_text(v_result, 'damage', 'body_critical_delta'), '')::integer, 0);

  if v_hit and v_attack_roll >= 95 then
    v_auto := 'crit';
  elsif v_attack_roll > 0 and v_attack_roll <= 5 then
    v_auto := 'fail';
  end if;

  if v_body_critical_delta > 0 then
    v_pending_checks := v_pending_checks || jsonb_build_array(
      jsonb_build_object(
        'type', 'manual_check',
        'skill_code', 'endurance',
        'reason', 'critical_damage',
        'message', 'Resolve an Endurance check manually because body critical damage was applied.'
      )
    );
  end if;

  v_possible_death :=
    coalesce(nullif(jsonb_extract_path_text(v_body_part, 'destroyed'), '')::boolean, false)
    and lower(coalesce(jsonb_extract_path_text(v_body_part, 'code'), '')) in ('head', 'torso');

  if v_possible_death then
    v_execution := v_execution || jsonb_build_object(
      'fatal_triggered', true,
      'death_application_suppressed', true
    );

    v_pending_checks := v_pending_checks || jsonb_build_array(
      jsonb_build_object(
        'type', 'manual_check',
        'reason', 'possible_death',
        'message', 'Death was not applied automatically. Resolve manually.'
      )
    );
  end if;

  return v_result
    || jsonb_build_object(
      'body_part', v_body_part,
      'target_state', v_target_state,
      'auto', to_jsonb(v_auto),
      'pending_checks', v_pending_checks
    )
    || case
      when jsonb_typeof(v_execution) = 'object' and v_execution <> '{}'::jsonb
        then jsonb_build_object('execution', v_execution)
      else '{}'::jsonb
    end;
end;
$$;

grant execute on function public.odyssey_apply_equipment_critical_damage(uuid, integer) to anon, authenticated;
grant execute on function public.get_effective_character_stats(uuid) to anon, authenticated;
grant execute on function public.odyssey_finalize_attack_result(jsonb, uuid, uuid) to anon, authenticated;
grant execute on function public.odyssey_perform_weapon_attack(jsonb) to anon, authenticated;
