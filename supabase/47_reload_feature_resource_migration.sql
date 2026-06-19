create or replace function public.odyssey_merge_runtime_data(
  p_base jsonb,
  p_override jsonb
)
returns jsonb
language sql
immutable
as $$
  with normalized as (
    select
      coalesce(case when jsonb_typeof(p_base) = 'object' then p_base else '{}'::jsonb end, '{}'::jsonb) as base_data,
      coalesce(case when jsonb_typeof(p_override) = 'object' then p_override else '{}'::jsonb end, '{}'::jsonb) as override_data
  )
  select jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          ((base_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions') || (override_data - 'modifiers' - 'flags' - 'on_hit' - 'conditions')),
          '{modifiers}',
          case
            when jsonb_typeof(base_data->'modifiers') = 'array'
              and jsonb_typeof(override_data->'modifiers') = 'array'
              then (base_data->'modifiers') || (override_data->'modifiers')
            when jsonb_typeof(override_data->'modifiers') = 'array'
              then override_data->'modifiers'
            when jsonb_typeof(base_data->'modifiers') = 'array'
              then base_data->'modifiers'
            else '[]'::jsonb
          end,
          true
        ),
        '{on_hit}',
        case
          when jsonb_typeof(base_data->'on_hit') = 'array'
            and jsonb_typeof(override_data->'on_hit') = 'array'
            then (base_data->'on_hit') || (override_data->'on_hit')
          when jsonb_typeof(override_data->'on_hit') = 'array'
            then override_data->'on_hit'
          when jsonb_typeof(base_data->'on_hit') = 'array'
            then base_data->'on_hit'
          else '[]'::jsonb
        end,
        true
      ),
      '{flags}',
      case
        when jsonb_typeof(base_data->'flags') = 'object'
          or jsonb_typeof(override_data->'flags') = 'object'
          then coalesce(base_data->'flags', '{}'::jsonb) || coalesce(override_data->'flags', '{}'::jsonb)
        else '{}'::jsonb
      end,
      true
    ),
    '{conditions}',
    case
      when jsonb_typeof(base_data->'conditions') = 'object'
        or jsonb_typeof(override_data->'conditions') = 'object'
        then coalesce(base_data->'conditions', '{}'::jsonb) || coalesce(override_data->'conditions', '{}'::jsonb)
      else '{}'::jsonb
    end,
    true
  )
  from normalized;
$$;

alter table public.odyssey_item_defs
  drop constraint if exists odyssey_item_defs_use_action_type_check;

alter table public.odyssey_item_defs
  add constraint odyssey_item_defs_use_action_type_check
  check (use_action_type in ('none', 'consume', 'heal', 'reload_feature_resource', 'manual', 'custom'));

create or replace function public.odyssey_consume_character_ability_cost(
  p_character_ability_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_ability record;
  v_effective_level integer := 0;
  v_level record;
  v_pool record;
  v_sync jsonb := '{}'::jsonb;
  v_item_result jsonb := '{}'::jsonb;
  v_runtime_data jsonb := '{}'::jsonb;
  v_reload_config jsonb := '{}'::jsonb;
  v_reload_mode text := '';
  v_reload_item_code text := null;
  v_item_cost_per_reload integer := 1;
  v_charges_before integer := 0;
  v_charges_after integer := 0;
begin
  select
    ability.id,
    ability.character_id,
    ability.ability_def_id,
    ability.current_cooldown_rounds,
    ability.current_charges,
    ability.max_charges,
    ability.data as state_data,
    def.code as ability_code,
    def.name as ability_name,
    def.resource_mode,
    def.resource_pool_code,
    def.resource_item_code,
    def.data as definition_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = p_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', p_character_ability_id
    );
  end if;

  if coalesce(v_ability.current_cooldown_rounds, 0) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_ON_COOLDOWN',
      'character_ability_id', p_character_ability_id,
      'cooldown_rounds_left', v_ability.current_cooldown_rounds
    );
  end if;

  v_effective_level := public.odyssey_get_character_ability_effective_level(p_character_ability_id);

  select *
  into v_level
  from public.odyssey_ability_level_defs level_data
  where level_data.ability_def_id = v_ability.ability_def_id
    and level_data.ability_level <= v_effective_level
  order by level_data.ability_level desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_LEVEL_NOT_AVAILABLE',
      'character_ability_id', p_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  v_runtime_data := public.odyssey_merge_runtime_data(
    public.odyssey_merge_runtime_data(
      coalesce(v_ability.definition_data, '{}'::jsonb),
      coalesce(v_ability.state_data, '{}'::jsonb)
    ),
    coalesce(v_level.data, '{}'::jsonb)
  );

  if jsonb_typeof(v_runtime_data->'reload') = 'object' then
    v_reload_config := v_runtime_data->'reload';
    v_reload_mode := lower(trim(coalesce(v_reload_config->>'mode', '')));
    v_reload_item_code := lower(trim(coalesce(
      nullif(v_reload_config->>'item_code', ''),
      nullif(v_ability.resource_item_code, ''),
      ''
    )));

    if coalesce(v_reload_config->>'item_cost_per_reload', '') ~ '^-?[0-9]+$' then
      v_item_cost_per_reload := greatest((v_reload_config->>'item_cost_per_reload')::integer, 1);
    else
      v_item_cost_per_reload := 1;
    end if;
  end if;

  if v_reload_mode in ('reset', 'per_charge') then
    if v_ability.current_charges is null or v_ability.max_charges is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_CHARGE_STATE_NOT_CONFIGURED',
        'character_ability_id', p_character_ability_id
      );
    end if;

    if coalesce(v_ability.current_charges, 0) <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_LOADED',
        'character_ability_id', p_character_ability_id,
        'reload_mode', v_reload_mode,
        'charges',
          jsonb_build_object(
            'before', coalesce(v_ability.current_charges, 0),
            'after', coalesce(v_ability.current_charges, 0),
            'max', coalesce(v_ability.max_charges, 0)
          )
      );
    end if;

    v_charges_before := coalesce(v_ability.current_charges, 0);
    v_charges_after := greatest(v_charges_before - 1, 0);

    update public.odyssey_character_abilities
    set current_charges = v_charges_after
    where id = p_character_ability_id;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', 'internal_charge',
      'resource_consumed', true,
      'resource_cost', 1,
      'charges',
        jsonb_build_object(
          'before', v_charges_before,
          'after', v_charges_after,
          'max', coalesce(v_ability.max_charges, 0),
          'consumed', 1
        ),
      'resource',
        jsonb_build_object(
          'type', 'internal_charge',
          'reload_mode', v_reload_mode,
          'item_code', nullif(v_reload_item_code, ''),
          'item_cost_per_reload', v_item_cost_per_reload
        )
    );
  end if;

  if coalesce(v_level.resource_cost, 0) <= 0 or v_ability.resource_mode in ('none', 'cooldown', 'custom') then
    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'resource_consumed', false
    );
  end if;

  if v_ability.resource_mode = 'pool' then
    v_sync := public.odyssey_sync_character_resource_pools(v_ability.character_id);

    select
      p.id,
      p.current_value,
      p.max_value,
      d.code,
      d.name
    into v_pool
    from public.odyssey_character_resource_pools p
    join public.odyssey_resource_pool_defs d on d.id = p.resource_pool_def_id
    where p.character_id = v_ability.character_id
      and d.code = v_ability.resource_pool_code
    for update of p;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_POOL_NOT_FOUND',
        'character_ability_id', p_character_ability_id,
        'resource_pool_code', v_ability.resource_pool_code,
        'sync', v_sync
      );
    end if;

    if coalesce(v_pool.current_value, 0) < coalesce(v_level.resource_cost, 0) then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_ENERGY',
        'character_ability_id', p_character_ability_id,
        'resource_pool_code', v_pool.code,
        'required', v_level.resource_cost,
        'available', coalesce(v_pool.current_value, 0)
      );
    end if;

    update public.odyssey_character_resource_pools
    set current_value = greatest(current_value - coalesce(v_level.resource_cost, 0), 0)
    where id = v_pool.id;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_consumed', true,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'resource_pool',
        jsonb_build_object(
          'id', v_pool.id,
          'code', v_pool.code,
          'name', v_pool.name,
          'before', coalesce(v_pool.current_value, 0),
          'after', greatest(coalesce(v_pool.current_value, 0) - coalesce(v_level.resource_cost, 0), 0),
          'max', coalesce(v_pool.max_value, 0)
        )
    );
  end if;

  if v_ability.resource_mode = 'item' then
    if nullif(trim(coalesce(v_ability.resource_item_code, '')), '') is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_ITEM_CODE_REQUIRED',
        'character_ability_id', p_character_ability_id
      );
    end if;

    v_item_result := public.remove_character_item_quantity(
      v_ability.character_id,
      v_ability.resource_item_code,
      coalesce(v_level.resource_cost, 0)
    );

    if coalesce((v_item_result->>'ok')::boolean, false) = false then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_ITEM_NOT_AVAILABLE',
        'character_ability_id', p_character_ability_id,
        'resource_item_code', v_ability.resource_item_code,
        'details', v_item_result
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_consumed', true,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'item', v_item_result
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', p_character_ability_id,
    'resource_mode', v_ability.resource_mode,
    'resource_cost', coalesce(v_level.resource_cost, 0),
    'resource_consumed', false
  );
end;
$$;

create or replace function public.reload_feature_resource(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_feature_instance_type text := lower(trim(coalesce(p_payload->>'feature_instance_type', '')));
  v_feature_instance_id uuid := public.odyssey_try_parse_uuid(p_payload->>'feature_instance_id');
  v_quantity_text text := nullif(trim(coalesce(p_payload->>'quantity', '')), '');
  v_requested_quantity integer := 1;
  v_reload_mode text := '';
  v_reload_config jsonb := '{}'::jsonb;
  v_item_code text := '';
  v_item_cost_per_reload integer := 1;
  v_inventory_before integer := 0;
  v_inventory_after integer := 0;
  v_quantity_spent integer := 0;
  v_loaded_quantity integer := 0;
  v_item_result jsonb := '{}'::jsonb;
  v_feature record;
  v_ability record;
  v_runtime_data jsonb := '{}'::jsonb;
  v_free_slots integer := 0;
  v_charges_before integer := 0;
  v_charges_after integer := 0;
begin
  if v_feature_instance_type not in ('weapon_feature', 'character_ability') then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_INSTANCE_TYPE_NOT_SUPPORTED',
      'message', 'feature_instance_type must be weapon_feature or character_ability.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  if v_feature_instance_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'feature_instance_id is required and must be a valid UUID.',
      'feature_instance_type', v_feature_instance_type
    );
  end if;

  if v_quantity_text is not null then
    if v_quantity_text !~ '^[0-9]+$' then
      return jsonb_build_object(
        'ok', false,
        'error', 'INVALID_RELOAD_QUANTITY',
        'message', 'quantity must be a positive integer.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    v_requested_quantity := v_quantity_text::integer;
  end if;

  if v_requested_quantity <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_RELOAD_QUANTITY',
      'message', 'quantity must be a positive integer.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  if v_feature_instance_type = 'weapon_feature' then
    select
      s.id,
      s.character_weapon_id,
      s.is_active,
      s.is_enabled,
      s.current_charges,
      s.max_charges,
      s.recharge_rounds_left,
      s.cooldown_rounds_left,
      s.active_rounds_left,
      s.active_uses_left,
      s.requires_reload,
      s.data as state_data,
      w.character_id,
      def.code as feature_code,
      def.name as feature_name,
      def.requires_reload_item_code,
      public.odyssey_merge_runtime_data(
        public.odyssey_merge_runtime_data(def.data, coalesce(link.data, '{}'::jsonb)),
        s.data
      ) as merged_data
    into v_feature
    from public.odyssey_character_weapon_feature_states s
    join public.odyssey_character_weapons w on w.id = s.character_weapon_id
    join public.odyssey_weapon_feature_defs def on def.id = s.feature_def_id
    left join public.odyssey_weapon_model_features link
      on link.weapon_model_id = w.weapon_model_id
     and link.feature_def_id = s.feature_def_id
     and coalesce(link.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = coalesce(s.profile_id, '00000000-0000-0000-0000-000000000000'::uuid)
    where s.id = v_feature_instance_id
    for update of s;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_INSTANCE_NOT_FOUND',
        'message', 'Weapon feature instance was not found.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    if not coalesce(v_feature.is_enabled, true) then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_DISABLED',
        'message', 'Feature instance is disabled.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    if jsonb_typeof(v_feature.merged_data->'reload') = 'object' then
      v_reload_config := v_feature.merged_data->'reload';
      v_reload_mode := lower(trim(coalesce(v_reload_config->>'mode', '')));
      v_item_code := lower(trim(coalesce(
        nullif(v_reload_config->>'item_code', ''),
        nullif(v_feature.requires_reload_item_code, ''),
        ''
      )));
      if coalesce(v_reload_config->>'item_cost_per_reload', '') ~ '^-?[0-9]+$' then
        v_item_cost_per_reload := greatest((v_reload_config->>'item_cost_per_reload')::integer, 1);
      end if;
    else
      v_reload_mode := case
        when nullif(trim(coalesce(v_feature.requires_reload_item_code, '')), '') is not null then 'reset'
        else ''
      end;
      v_item_code := lower(trim(coalesce(v_feature.requires_reload_item_code, '')));
    end if;

    if v_reload_mode = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_NOT_RELOADABLE',
        'message', 'Feature does not define reload configuration.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    if v_reload_mode not in ('reset', 'per_charge') then
      return jsonb_build_object(
        'ok', false,
        'error', 'RELOAD_MODE_NOT_SUPPORTED',
        'message', 'reload.mode must be reset or per_charge.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id,
        'reload_mode', v_reload_mode
      );
    end if;

    if v_item_code = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_NOT_RELOADABLE',
        'message', 'Reloadable feature is missing reload item_code.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id,
        'reload_mode', v_reload_mode
      );
    end if;

    v_charges_before := coalesce(v_feature.current_charges, 0);

    if v_reload_mode = 'reset' then
      if not coalesce(v_feature.requires_reload, false) then
        return jsonb_build_object(
          'ok', false,
          'error', 'FEATURE_DOES_NOT_REQUIRE_RELOAD',
          'message', 'Feature does not currently require reload.',
          'feature_instance_type', v_feature_instance_type,
          'feature_instance_id', v_feature_instance_id
        );
      end if;

      if v_feature.max_charges is null then
        return jsonb_build_object(
          'ok', false,
          'error', 'NO_CHARGE_CAPACITY',
          'message', 'Feature does not expose max_charges for reset reload.',
          'feature_instance_type', v_feature_instance_type,
          'feature_instance_id', v_feature_instance_id
        );
      end if;

      v_quantity_spent := v_item_cost_per_reload;
      v_loaded_quantity := 1;
      v_charges_after := coalesce(v_feature.max_charges, 0);
    else
      if v_feature.current_charges is null or v_feature.max_charges is null then
        return jsonb_build_object(
          'ok', false,
          'error', 'NO_CHARGE_CAPACITY',
          'message', 'Feature does not expose current_charges/max_charges for per_charge reload.',
          'feature_instance_type', v_feature_instance_type,
          'feature_instance_id', v_feature_instance_id
        );
      end if;

      v_free_slots := greatest(coalesce(v_feature.max_charges, 0) - coalesce(v_feature.current_charges, 0), 0);
      if v_free_slots <= 0 then
        return jsonb_build_object(
          'ok', false,
          'error', 'NO_CHARGE_CAPACITY',
          'message', 'Feature charges are already full.',
          'feature_instance_type', v_feature_instance_type,
          'feature_instance_id', v_feature_instance_id
        );
      end if;

      v_loaded_quantity := least(v_requested_quantity, v_free_slots);
      v_quantity_spent := v_loaded_quantity * v_item_cost_per_reload;
      v_charges_after := coalesce(v_feature.current_charges, 0) + v_loaded_quantity;
    end if;

    v_inventory_before := public.get_character_item_quantity(v_feature.character_id, v_item_code);
    if v_inventory_before <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_RESOURCE_ITEM',
        'message', 'Character does not have the required reload item.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    if v_inventory_before < v_quantity_spent then
      return jsonb_build_object(
        'ok', false,
        'error', 'INSUFFICIENT_RESOURCE_ITEM',
        'message', 'Character does not have enough reload items.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    v_item_result := public.remove_character_item_quantity(
      v_feature.character_id,
      v_item_code,
      v_quantity_spent
    );

    if coalesce((v_item_result->>'ok')::boolean, false) = false then
      return jsonb_build_object(
        'ok', false,
        'error',
          case
            when coalesce(v_item_result->>'error', '') = 'NOT_ENOUGH_ITEMS' then 'INSUFFICIENT_RESOURCE_ITEM'
            else 'NO_RESOURCE_ITEM'
          end,
        'message', 'Character does not have the required reload item.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    v_inventory_after := coalesce((v_item_result->>'remaining_quantity')::integer, greatest(v_inventory_before - v_quantity_spent, 0));

    if v_reload_mode = 'reset' then
      update public.odyssey_character_weapon_feature_states
      set
        is_active = false,
        current_charges = max_charges,
        recharge_rounds_left = null,
        cooldown_rounds_left = null,
        active_rounds_left = null,
        active_uses_left = null,
        requires_reload = false
      where id = v_feature.id;
    else
      update public.odyssey_character_weapon_feature_states
      set
        current_charges = least(coalesce(max_charges, current_charges), coalesce(current_charges, 0) + v_loaded_quantity),
        requires_reload = false
      where id = v_feature.id;
    end if;

    return jsonb_build_object(
      'ok', true,
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id,
      'character_id', v_feature.character_id,
      'reload_mode', v_reload_mode,
      'feature_code', v_feature.feature_code,
      'resource',
        jsonb_build_object(
          'item_code', v_item_code,
          'quantity_spent', v_quantity_spent,
          'inventory_before', v_inventory_before,
          'inventory_after', v_inventory_after
        ),
      'charges',
        jsonb_build_object(
          'before', v_charges_before,
          'after', v_charges_after,
          'max', coalesce(v_feature.max_charges, v_charges_after),
          'loaded', v_loaded_quantity
        ),
      'feature_state',
        jsonb_build_object(
          'requires_reload', false,
          'is_active', case when v_reload_mode = 'reset' then false else coalesce(v_feature.is_active, false) end,
          'active_uses_left', case when v_reload_mode = 'reset' then null else v_feature.active_uses_left end,
          'cooldown_rounds_left', case when v_reload_mode = 'reset' then null else v_feature.cooldown_rounds_left end,
          'recharge_rounds_left', case when v_reload_mode = 'reset' then null else v_feature.recharge_rounds_left end
        )
    );
  end if;

  select
    ability.id,
    ability.character_id,
    ability.ability_def_id,
    ability.is_enabled,
    ability.current_cooldown_rounds,
    ability.current_charges,
    ability.max_charges,
    ability.data as state_data,
    def.code as ability_code,
    def.name as ability_name,
    def.resource_item_code,
    def.data as definition_data,
    level.data as level_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  left join lateral (
    select level_entry.*
    from public.odyssey_ability_level_defs level_entry
    where level_entry.ability_def_id = def.id
      and level_entry.ability_level <= public.odyssey_get_character_ability_effective_level(ability.id)
    order by level_entry.ability_level desc
    limit 1
  ) level on true
  where ability.id = v_feature_instance_id
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_INSTANCE_NOT_FOUND',
      'message', 'Character ability instance was not found.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  if not coalesce(v_ability.is_enabled, true) then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_DISABLED',
      'message', 'Feature instance is disabled.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  v_runtime_data := public.odyssey_merge_runtime_data(
    public.odyssey_merge_runtime_data(
      coalesce(v_ability.definition_data, '{}'::jsonb),
      coalesce(v_ability.state_data, '{}'::jsonb)
    ),
    coalesce(v_ability.level_data, '{}'::jsonb)
  );

  if jsonb_typeof(v_runtime_data->'reload') = 'object' then
    v_reload_config := v_runtime_data->'reload';
    v_reload_mode := lower(trim(coalesce(v_reload_config->>'mode', '')));
    v_item_code := lower(trim(coalesce(
      nullif(v_reload_config->>'item_code', ''),
      nullif(v_ability.resource_item_code, ''),
      ''
    )));
    if coalesce(v_reload_config->>'item_cost_per_reload', '') ~ '^-?[0-9]+$' then
      v_item_cost_per_reload := greatest((v_reload_config->>'item_cost_per_reload')::integer, 1);
    else
      v_item_cost_per_reload := 1;
    end if;
  end if;

  if v_reload_mode = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_NOT_RELOADABLE',
      'message', 'Ability does not define reload configuration.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  if v_reload_mode not in ('reset', 'per_charge') then
    return jsonb_build_object(
      'ok', false,
      'error', 'RELOAD_MODE_NOT_SUPPORTED',
      'message', 'reload.mode must be reset or per_charge.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id,
      'reload_mode', v_reload_mode
    );
  end if;

  if v_item_code = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'FEATURE_NOT_RELOADABLE',
      'message', 'Reloadable ability is missing reload item_code.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id,
      'reload_mode', v_reload_mode
    );
  end if;

  if v_ability.current_charges is null or v_ability.max_charges is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_CHARGE_CAPACITY',
      'message', 'Ability does not expose current_charges/max_charges.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  v_charges_before := coalesce(v_ability.current_charges, 0);

  if v_reload_mode = 'reset' then
    if v_charges_before >= coalesce(v_ability.max_charges, 0) then
      return jsonb_build_object(
        'ok', false,
        'error', 'FEATURE_DOES_NOT_REQUIRE_RELOAD',
        'message', 'Ability charges are already full.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    v_loaded_quantity := greatest(coalesce(v_ability.max_charges, 0) - v_charges_before, 0);
    v_quantity_spent := v_item_cost_per_reload;
    v_charges_after := coalesce(v_ability.max_charges, v_charges_before);
  else
    v_free_slots := greatest(coalesce(v_ability.max_charges, 0) - v_charges_before, 0);
    if v_free_slots <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_CHARGE_CAPACITY',
        'message', 'Ability charges are already full.',
        'feature_instance_type', v_feature_instance_type,
        'feature_instance_id', v_feature_instance_id
      );
    end if;

    v_loaded_quantity := least(v_requested_quantity, v_free_slots);
    v_quantity_spent := v_loaded_quantity * v_item_cost_per_reload;
    v_charges_after := v_charges_before + v_loaded_quantity;
  end if;

  v_inventory_before := public.get_character_item_quantity(v_ability.character_id, v_item_code);
  if v_inventory_before <= 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'NO_RESOURCE_ITEM',
      'message', 'Character does not have the required reload item.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  if v_inventory_before < v_quantity_spent then
    return jsonb_build_object(
      'ok', false,
      'error', 'INSUFFICIENT_RESOURCE_ITEM',
      'message', 'Character does not have enough reload items.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  v_item_result := public.remove_character_item_quantity(
    v_ability.character_id,
    v_item_code,
    v_quantity_spent
  );

  if coalesce((v_item_result->>'ok')::boolean, false) = false then
    return jsonb_build_object(
      'ok', false,
      'error',
        case
          when coalesce(v_item_result->>'error', '') = 'NOT_ENOUGH_ITEMS' then 'INSUFFICIENT_RESOURCE_ITEM'
          else 'NO_RESOURCE_ITEM'
        end,
      'message', 'Character does not have the required reload item.',
      'feature_instance_type', v_feature_instance_type,
      'feature_instance_id', v_feature_instance_id
    );
  end if;

  v_inventory_after := coalesce((v_item_result->>'remaining_quantity')::integer, greatest(v_inventory_before - v_quantity_spent, 0));

  update public.odyssey_character_abilities
  set
    current_charges = v_charges_after,
    current_cooldown_rounds = case when v_reload_mode = 'reset' then 0 else current_cooldown_rounds end
  where id = v_ability.id;

  return jsonb_build_object(
    'ok', true,
    'feature_instance_type', v_feature_instance_type,
    'feature_instance_id', v_feature_instance_id,
    'character_id', v_ability.character_id,
    'reload_mode', v_reload_mode,
    'ability_code', v_ability.ability_code,
    'resource',
      jsonb_build_object(
        'item_code', v_item_code,
        'quantity_spent', v_quantity_spent,
        'inventory_before', v_inventory_before,
        'inventory_after', v_inventory_after
      ),
    'charges',
      jsonb_build_object(
        'before', v_charges_before,
        'after', v_charges_after,
        'max', coalesce(v_ability.max_charges, v_charges_after),
        'loaded', v_loaded_quantity
      ),
    'feature_state',
      jsonb_build_object(
        'requires_reload', false,
        'is_active', false,
        'active_uses_left', null,
        'cooldown_rounds_left', case when v_reload_mode = 'reset' then 0 else coalesce(v_ability.current_cooldown_rounds, 0) end,
        'recharge_rounds_left', null
      )
  );
end;
$$;

drop function if exists public.reload_feature_resource(uuid);

grant execute on function public.odyssey_merge_runtime_data(jsonb, jsonb) to anon, authenticated;
grant execute on function public.odyssey_consume_character_ability_cost(uuid) to anon, authenticated;
grant execute on function public.reload_feature_resource(jsonb) to anon, authenticated;
