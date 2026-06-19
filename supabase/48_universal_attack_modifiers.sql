create or replace function public.odyssey_collect_runtime_attack_modifiers(
  p_runtime_data jsonb,
  p_attack_type text
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_data jsonb := case
    when jsonb_typeof(p_runtime_data) = 'object' then p_runtime_data
    else '{}'::jsonb
  end;
  v_attack_type text := lower(trim(coalesce(p_attack_type, '')));
  v_condition_attack_type text := lower(trim(coalesce(v_data->'conditions'->>'attack_type', '')));
  v_attack_accuracy integer := 0;
  v_damage integer := 0;
  v_armor_pierce integer := 0;
  v_aim_difficulty integer := 0;
  v_range integer := 0;
  v_skip_damage boolean := false;
  v_on_hit jsonb := '[]'::jsonb;
  v_entry jsonb;
begin
  if v_condition_attack_type <> '' and v_condition_attack_type <> v_attack_type then
    return jsonb_build_object(
      'applied', false,
      'attack_accuracy', 0,
      'damage', 0,
      'armor_pierce', 0,
      'aim_difficulty', 0,
      'range', 0,
      'skip_damage', false,
      'on_hit', '[]'::jsonb
    );
  end if;

  for v_entry in
    select value
    from jsonb_array_elements(
      case
        when jsonb_typeof(v_data->'modifiers') = 'array' then v_data->'modifiers'
        else '[]'::jsonb
      end
    )
  loop
    case lower(trim(coalesce(v_entry->>'target', '')))
      when 'attack_accuracy' then
        v_attack_accuracy := v_attack_accuracy + coalesce(nullif(trim(coalesce(v_entry->>'value', '')), '')::integer, 0);
      when 'damage' then
        v_damage := v_damage + coalesce(nullif(trim(coalesce(v_entry->>'value', '')), '')::integer, 0);
      when 'armor_pierce' then
        v_armor_pierce := v_armor_pierce + coalesce(nullif(trim(coalesce(v_entry->>'value', '')), '')::integer, 0);
      when 'aim_difficulty' then
        v_aim_difficulty := v_aim_difficulty + coalesce(nullif(trim(coalesce(v_entry->>'value', '')), '')::integer, 0);
      when 'range' then
        v_range := v_range + coalesce(nullif(trim(coalesce(v_entry->>'value', '')), '')::integer, 0);
      else
        null;
    end case;
  end loop;

  if coalesce(v_data->>'skip_damage', 'false') in ('true', '1', 'yes', 'on') then
    v_skip_damage := true;
  end if;

  if jsonb_typeof(v_data->'on_hit') = 'array' then
    v_on_hit := v_data->'on_hit';
  end if;

  return jsonb_build_object(
    'applied', true,
    'attack_accuracy', v_attack_accuracy,
    'damage', v_damage,
    'armor_pierce', v_armor_pierce,
    'aim_difficulty', v_aim_difficulty,
    'range', v_range,
    'skip_damage', v_skip_damage,
    'on_hit', v_on_hit
  );
end;
$$;

do $$
declare
  v_function_def text;
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

  if position('v_armor_pierce := greatest(v_armor_pierce + v_feature_armor_pierce_modifier, 0);' in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      'v_armor_pierce := greatest(v_armor_pierce + v_feature_armor_pierce_modifier, 0);',
      'v_armor_pierce := coalesce(v_armor_pierce, 0) + v_feature_armor_pierce_modifier;'
    );
  end if;

  if position($needle$v_effective_armor := case
      when v_attack_type = 'ranged' then greatest(v_raw_armor_value - v_armor_pierce, 0)
      else v_raw_armor_value
    end;$needle$ in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      $old$v_effective_armor := case
      when v_attack_type = 'ranged' then greatest(v_raw_armor_value - v_armor_pierce, 0)
      else v_raw_armor_value
    end;$old$,
      $new$v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);$new$
    );
  elsif position($needle$if v_attack_type = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;$needle$ in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      $old$if v_attack_type = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;$old$,
      $new$v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);$new$
    );
  end if;

  if position('case when v_attack_type = ''ranged'' then v_armor_pierce else 0 end' in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      'case when v_attack_type = ''ranged'' then v_armor_pierce else 0 end',
      'v_armor_pierce'
    );
  end if;

  execute v_function_def;
end;
$$;

do $$
declare
  v_function_def text;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'odyssey_perform_ability_attack'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is null then
    raise exception 'Function public.odyssey_perform_ability_attack(jsonb) was not found.';
  end if;

  if position('v_runtime_data jsonb := ''{}''::jsonb;' in v_function_def) = 0 then
    if position($needle$v_armor_item_updates jsonb := '[]'::jsonb;
  v_target_state jsonb := '{}'::jsonb;$needle$ in v_function_def) = 0 then
      raise exception 'Could not find declaration block in public.odyssey_perform_ability_attack(jsonb).';
    end if;

    v_function_def := replace(
      v_function_def,
      $old$v_armor_item_updates jsonb := '[]'::jsonb;
  v_target_state jsonb := '{}'::jsonb;$old$,
      $new$v_armor_item_updates jsonb := '[]'::jsonb;
  v_runtime_data jsonb := '{}'::jsonb;
  v_runtime_modifier_summary jsonb := '{}'::jsonb;
  v_runtime_attack_accuracy_modifier integer := 0;
  v_runtime_damage_modifier integer := 0;
  v_runtime_armor_pierce_modifier integer := 0;
  v_runtime_aim_difficulty_modifier integer := 0;
  v_runtime_range_modifier integer := 0;
  v_pending_saves jsonb := '[]'::jsonb;
  v_pending_effects jsonb := '[]'::jsonb;
  v_on_hit_templates jsonb := '[]'::jsonb;
  v_skip_damage boolean := false;
  v_runtime_entry jsonb;
  v_runtime_on_hit_entry jsonb;
  v_total_armor_pierce integer := 0;
  v_target_state jsonb := '{}'::jsonb;$new$
    );
  end if;

  if position('def.data as ability_definition_data' in v_function_def) = 0 then
    if position($needle$      def.resource_item_code,
      def.description as ability_description$needle$ in v_function_def) = 0 then
      raise exception 'Could not find ability definition select block in public.odyssey_perform_ability_attack(jsonb).';
    end if;

    v_function_def := replace(
      v_function_def,
      $old$      def.resource_item_code,
      def.description as ability_description$old$,
      $new$      def.resource_item_code,
      def.description as ability_description,
      def.data as ability_definition_data$new$
    );
  end if;

  if position('v_runtime_data := public.odyssey_merge_runtime_data(' in v_function_def) = 0 then
    if position($needle$if v_error_code is null then
    select
      b.id,$needle$ in v_function_def) = 0 then
      raise exception 'Could not find body part lookup entry point in public.odyssey_perform_ability_attack(jsonb).';
    end if;

    v_function_def := replace(
      v_function_def,
      $old$if v_error_code is null then
    select
      b.id,$old$,
      $new$if v_error_code is null then
    v_runtime_data := public.odyssey_merge_runtime_data(
      public.odyssey_merge_runtime_data(
        coalesce(v_ability.ability_definition_data, '{}'::jsonb),
        coalesce(v_ability.data, '{}'::jsonb)
      ),
      coalesce(v_level.data, '{}'::jsonb)
    );

    v_runtime_modifier_summary := public.odyssey_collect_runtime_attack_modifiers(
      v_runtime_data,
      coalesce(v_ability.attack_type, '')
    );

    v_runtime_attack_accuracy_modifier := coalesce(nullif(v_runtime_modifier_summary->>'attack_accuracy', '')::integer, 0);
    v_runtime_damage_modifier := coalesce(nullif(v_runtime_modifier_summary->>'damage', '')::integer, 0);
    v_runtime_armor_pierce_modifier := coalesce(nullif(v_runtime_modifier_summary->>'armor_pierce', '')::integer, 0);
    v_runtime_aim_difficulty_modifier := coalesce(nullif(v_runtime_modifier_summary->>'aim_difficulty', '')::integer, 0);
    v_runtime_range_modifier := coalesce(nullif(v_runtime_modifier_summary->>'range', '')::integer, 0);
    v_skip_damage := coalesce((v_runtime_modifier_summary->>'skip_damage')::boolean, false);
    v_on_hit_templates := coalesce(v_runtime_modifier_summary->'on_hit', '[]'::jsonb);

    select
      b.id,$new$
    );
  end if;

  if position('+ v_runtime_range_modifier' in v_function_def) = 0 then
    v_function_def := replace(
      v_function_def,
      'v_range_modifier := coalesce((v_range_json->>''modifier'')::integer, 0) + v_attacker_range_effect_modifier;',
      'v_range_modifier := coalesce((v_range_json->>''modifier'')::integer, 0) + v_attacker_range_effect_modifier + v_runtime_range_modifier;'
    );

    v_function_def := replace(
      v_function_def,
      'v_range_modifier := v_attacker_range_effect_modifier;',
      'v_range_modifier := v_attacker_range_effect_modifier + v_runtime_range_modifier;'
    );
  end if;

  if position('v_total_armor_pierce := coalesce(v_level.attack_armor_pierce, 0) + v_runtime_armor_pierce_modifier;' in v_function_def) = 0 then
    if position($needle$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    elsif coalesce(v_ability.attack_type, '') = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    elsif coalesce(v_ability.attack_type, '') = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;$old$,
        $new$v_total_armor_pierce := coalesce(v_level.attack_armor_pierce, 0) + v_runtime_armor_pierce_modifier;
    if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - v_total_armor_pierce, 0);
    end if;$new$
      );
    elsif position($needle$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    end if;$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - coalesce(v_level.attack_armor_pierce, 0), 0);
    end if;$old$,
        $new$v_total_armor_pierce := coalesce(v_level.attack_armor_pierce, 0) + v_runtime_armor_pierce_modifier;
    if coalesce(v_level.ignore_armor, false) then
      v_effective_armor := 0;
    else
      v_effective_armor := greatest(v_raw_armor_value - v_total_armor_pierce, 0);
    end if;$new$
      );
    else
      raise exception 'Could not find armor calculation in public.odyssey_perform_ability_attack(jsonb).';
    end if;
  end if;

  if position('v_runtime_aim_difficulty_modifier' in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      'v_effective_aim_difficulty := greatest(coalesce(v_target_part.aim_difficulty, 0) - v_attacker_aim_difficulty_modifier, 0);',
      'v_effective_aim_difficulty := greatest(coalesce(v_target_part.aim_difficulty, 0) - v_attacker_aim_difficulty_modifier - v_runtime_aim_difficulty_modifier, 0);'
    );
  end if;

  if position('+ v_runtime_attack_accuracy_modifier' in v_function_def) = 0 then
    v_function_def := replace(
      v_function_def,
      '+ coalesce(v_level.attack_accuracy_bonus, 0)
      + v_attacker_attack_accuracy_modifier',
      '+ coalesce(v_level.attack_accuracy_bonus, 0)
      + v_runtime_attack_accuracy_modifier
      + v_attacker_attack_accuracy_modifier'
    );
  end if;

  if position('+ v_runtime_damage_modifier;' in v_function_def) = 0 then
    v_function_def := replace(
      v_function_def,
      'v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_attacker_damage_modifier;',
      'v_damage_attack_total := v_attack_total + coalesce(v_level.attack_damage_bonus, 0) + v_runtime_damage_modifier + v_attacker_damage_modifier;'
    );
  end if;

  if position('if v_error_code is null and v_hit and not v_skip_damage then' in v_function_def) = 0 then
    v_function_def := replace(
      v_function_def,
      'if v_error_code is null and v_hit then',
      'if v_error_code is null and v_hit and not v_skip_damage then'
    );
  end if;

  if position('source'', ''ability''' in v_function_def) = 0 then
    if position($needle$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);$needle$ in v_function_def) = 0 then
      raise exception 'Could not find post-hit effects block in public.odyssey_perform_ability_attack(jsonb).';
    end if;

    v_function_def := replace(
      v_function_def,
      $old$if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);$old$,
      $new$if v_error_code is null and v_hit then
    for v_runtime_on_hit_entry in
      select value
      from jsonb_array_elements(coalesce(v_on_hit_templates, '[]'::jsonb))
    loop
      if coalesce(v_runtime_on_hit_entry->>'type', '') = 'pending_save' then
        v_pending_saves := v_pending_saves || jsonb_build_array(
          jsonb_build_object(
            'source', 'ability',
            'ability_code', v_ability.ability_code,
            'target_character_id', v_target_character_id,
            'attribute', coalesce(v_runtime_on_hit_entry->>'attribute', ''),
            'reason', coalesce(v_runtime_on_hit_entry->>'reason', v_ability.ability_code),
            'suggested_effect_code', v_runtime_on_hit_entry->>'suggested_effect_code',
            'notes', coalesce(
              nullif(v_runtime_on_hit_entry->>'notes', ''),
              'GM/player should resolve the save manually and apply the effect if needed.'
            )
          )
        );
      else
        v_pending_effects := v_pending_effects || jsonb_build_array(
          jsonb_build_object(
            'source', 'ability',
            'ability_code', v_ability.ability_code,
            'target_character_id', v_target_character_id,
            'payload', coalesce(v_runtime_on_hit_entry, '{}'::jsonb)
          )
        );
      end if;
    end loop;
  end if;

  if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);$new$
    );
  end if;

  if position($needle_pending$'pending_saves', v_pending_saves$needle_pending$ in v_function_def) = 0 then
    v_function_def := replace(
      v_function_def,
      $old_pending$'resource', v_resource_result,
    'expired_attack_effects', v_expired_attack_effects$old_pending$,
      $new_pending$'resource', v_resource_result,
    'pending_saves', v_pending_saves,
    'pending_effects', v_pending_effects,
    'expired_attack_effects', v_expired_attack_effects$new_pending$
    );
  end if;

  if position($needle_ap$'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,$needle_ap$ in v_function_def) > 0 then
    v_function_def := replace(
      v_function_def,
      $old_ap$'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            when coalesce(v_ability.attack_type, '') = 'ranged' then coalesce(v_level.attack_armor_pierce, 0)
            else 0
          end,$old_ap$,
      $new_ap$'armor_pierce_used',
          case
            when coalesce(v_level.ignore_armor, false) then 0
            else v_total_armor_pierce
          end,$new_ap$
    );
  end if;

  execute v_function_def;
end;
$$;

grant execute on function public.odyssey_collect_runtime_attack_modifiers(jsonb, text) to anon, authenticated;
