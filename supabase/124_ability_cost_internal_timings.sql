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
  v_started_at timestamptz := clock_timestamp();
  v_stage_started_at timestamptz := clock_timestamp();
  v_timings_ms jsonb := '{}'::jsonb;
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
      'character_ability_id', p_character_ability_id,
      'timings_ms', jsonb_build_object(
        'lock_character_ability',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
    );
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'lock_character_ability',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  if coalesce(v_ability.current_cooldown_rounds, 0) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_ON_COOLDOWN',
      'character_ability_id', p_character_ability_id,
      'cooldown_rounds_left', v_ability.current_cooldown_rounds,
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'cooldown_check',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  v_effective_level := public.odyssey_get_character_ability_effective_level(p_character_ability_id);
  v_timings_ms := v_timings_ms || jsonb_build_object(
    'effective_level_lookup',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

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
      'effective_level', v_effective_level,
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'load_ability_level',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'load_ability_level',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  v_runtime_data := public.odyssey_merge_runtime_data(
    public.odyssey_merge_runtime_data(
      coalesce(v_ability.definition_data, '{}'::jsonb),
      coalesce(v_ability.state_data, '{}'::jsonb)
    ),
    coalesce(v_level.data, '{}'::jsonb)
  );
  v_timings_ms := v_timings_ms || jsonb_build_object(
    'merge_runtime_data',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

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
        'character_ability_id', p_character_ability_id,
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'internal_charge_validation',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
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
          ),
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'internal_charge_validation',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
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
        ),
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'consume_internal_charge',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  if coalesce(v_level.resource_cost, 0) <= 0 or v_ability.resource_mode in ('none', 'cooldown', 'custom') then
    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'resource_consumed', false,
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'resource_mode_short_circuit',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  if v_ability.resource_mode = 'pool' then
    v_sync := public.odyssey_sync_character_resource_pools(v_ability.character_id);
    v_timings_ms := v_timings_ms || jsonb_build_object(
      'sync_resource_pools',
      greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
    );
    v_stage_started_at := clock_timestamp();

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
        'sync', v_sync,
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'lock_resource_pool',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
      );
    end if;

    v_timings_ms := v_timings_ms || jsonb_build_object(
      'lock_resource_pool',
      greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
    );
    v_stage_started_at := clock_timestamp();

    if coalesce(v_pool.current_value, 0) < coalesce(v_level.resource_cost, 0) then
      return jsonb_build_object(
        'ok', false,
        'error', 'NO_ENERGY',
        'character_ability_id', p_character_ability_id,
        'resource_pool_code', v_pool.code,
        'required', v_level.resource_cost,
        'available', coalesce(v_pool.current_value, 0),
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'validate_pool_balance',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
      );
    end if;

    v_timings_ms := v_timings_ms || jsonb_build_object(
      'validate_pool_balance',
      greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
    );
    v_stage_started_at := clock_timestamp();

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
        ),
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'update_resource_pool',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  if v_ability.resource_mode = 'item' then
    if nullif(trim(coalesce(v_ability.resource_item_code, '')), '') is null then
      return jsonb_build_object(
        'ok', false,
        'error', 'RESOURCE_ITEM_CODE_REQUIRED',
        'character_ability_id', p_character_ability_id,
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'item_resource_validation',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
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
        'details', v_item_result,
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            'consume_resource_item',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'character_ability_id', p_character_ability_id,
      'resource_mode', v_ability.resource_mode,
      'resource_consumed', true,
      'resource_cost', coalesce(v_level.resource_cost, 0),
      'item', v_item_result,
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          'consume_resource_item',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', p_character_ability_id,
    'resource_mode', v_ability.resource_mode,
    'resource_cost', coalesce(v_level.resource_cost, 0),
    'resource_consumed', false,
    'timings_ms',
      v_timings_ms || jsonb_build_object(
        'resource_mode_fallback',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
  );
end;
$$;

create or replace function public.odyssey_use_ability_with_weapon_support(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_ability_id');
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_ability_code text := lower(trim(coalesce(v_payload->>'ability_code', '')));
  v_selected_character_weapon_id uuid := public.odyssey_try_parse_uuid(v_payload->>'selected_character_weapon_id');
  v_source_validation jsonb := '{}'::jsonb;
  v_ability record;
  v_level record;
  v_effective_level integer := 0;
  v_merged_ability_data jsonb := '{}'::jsonb;
  v_resource_result jsonb := '{}'::jsonb;
  v_activation_result jsonb := '{}'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_feature_code text := '';
  v_stage text := 'resolve_character_ability';
  v_include_combat_state boolean := coalesce(nullif(trim(coalesce(v_payload->>'include_combat_state', '')), '')::boolean, true);
  v_started_at timestamptz := clock_timestamp();
  v_stage_started_at timestamptz := clock_timestamp();
  v_timings_ms jsonb := '{}'::jsonb;
begin
  perform set_config('lock_timeout', '1500ms', true);

  if v_character_ability_id is null then
    if v_character_id is null or v_ability_code = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ABILITY_NOT_FOUND',
        'message', 'character_ability_id or character_id + ability_code is required.'
      );
    end if;

    select ability.id
    into v_character_ability_id
    from public.odyssey_character_abilities ability
    join public.odyssey_ability_defs def on def.id = ability.ability_def_id
    where ability.character_id = v_character_id
      and def.code = v_ability_code
      and ability.is_enabled = true
    order by ability.sort_order, ability.created_at, ability.id
    limit 1;
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'resolve_character_ability',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  v_source_validation := public.odyssey_validate_character_ability_source(
    v_character_ability_id,
    v_selected_character_weapon_id
  );
  v_timings_ms := v_timings_ms || jsonb_build_object(
    'validate_ability_source',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();
  if coalesce((v_source_validation->>'ok')::boolean, false) = false then
    return v_source_validation || jsonb_build_object(
      'timings_ms',
      v_timings_ms || jsonb_build_object(
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
    );
  end if;

  v_stage := 'lock_character_ability';
  select
    ability.*,
    def.code as ability_code,
    def.name as ability_name,
    def.ability_kind,
    def.source_type,
    def.activation_type,
    def.target_type,
    def.effect_mode,
    def.attack_type,
    def.resource_item_code,
    def.data as def_data
  into v_ability
  from public.odyssey_character_abilities ability
  join public.odyssey_ability_defs def on def.id = ability.ability_def_id
  where ability.id = v_character_ability_id
    and ability.is_enabled = true
  for update of ability;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'ABILITY_NOT_FOUND',
      'character_ability_id', v_character_ability_id
    );
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'lock_character_ability',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  if v_ability.effect_mode <> 'activate_weapon_feature' then
    v_stage := 'delegate_legacy';
    return public.odyssey_use_ability_with_weapon_support_legacy(v_payload);
  end if;

  v_stage := 'load_ability_level';
  v_effective_level := public.odyssey_get_character_ability_effective_level(v_character_ability_id);
  v_timings_ms := v_timings_ms || jsonb_build_object(
    'effective_level_lookup',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

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
      'character_ability_id', v_character_ability_id,
      'effective_level', v_effective_level
    );
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'load_ability_level',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  v_merged_ability_data := public.odyssey_merge_runtime_data(
    public.odyssey_merge_runtime_data(
      coalesce(v_ability.def_data, '{}'::jsonb),
      coalesce(v_ability.data, '{}'::jsonb)
    ),
    coalesce(v_level.data, '{}'::jsonb)
  );

  v_feature_code := lower(trim(coalesce(
    nullif(v_merged_ability_data->>'weapon_feature_code', ''),
    nullif(v_merged_ability_data->>'feature_code', ''),
    v_ability.ability_code
  )));

  if v_ability.source_character_weapon_id is null or v_feature_code = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_FEATURE_NOT_CONFIGURED',
      'message', 'The bridge ability does not define a weapon_feature_code.'
    );
  end if;

  v_stage := 'consume_ability_cost';
  v_resource_result := public.odyssey_consume_character_ability_cost(v_character_ability_id);
  v_timings_ms := v_timings_ms || jsonb_build_object(
    'consume_ability_cost',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();
  if coalesce((v_resource_result->>'ok')::boolean, false) = false then
    return v_resource_result || jsonb_build_object(
      'timings_ms',
      v_timings_ms || jsonb_build_object(
        'resource', coalesce(v_resource_result->'timings_ms', '{}'::jsonb),
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
    );
  end if;

  if coalesce(v_level.cooldown_rounds, 0) > 0 then
    v_stage := 'set_cooldown';
    update public.odyssey_character_abilities
    set current_cooldown_rounds = v_level.cooldown_rounds
    where id = v_character_ability_id;
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'set_cooldown',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  v_stage := 'activate_weapon_feature';
  v_activation_result := public.activate_weapon_feature(
    jsonb_build_object(
      'character_weapon_id', v_ability.source_character_weapon_id::text,
      'feature_code', v_feature_code
    )
  );

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'activate_weapon_feature',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );
  v_stage_started_at := clock_timestamp();

  if coalesce((v_activation_result->>'ok')::boolean, false) = false then
    return v_activation_result || jsonb_build_object(
      'timings_ms',
      v_timings_ms || jsonb_build_object(
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
    );
  end if;

  if v_include_combat_state then
    v_stage := 'refresh_character_combat_state';
    v_refresh := coalesce(public.odyssey_refresh_character_combat_state(v_ability.character_id)->'combat_state', '{}'::jsonb);
  end if;

  v_timings_ms := v_timings_ms || jsonb_build_object(
    'refresh_character_combat_state',
    greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer)
  );

  return jsonb_build_object(
    'ok', true,
    'character_ability_id', v_character_ability_id,
    'character_id', v_ability.character_id,
    'source_character_weapon_id', v_ability.source_character_weapon_id,
    'ability',
      jsonb_build_object(
        'code', v_ability.ability_code,
        'name', v_ability.ability_name,
        'ability_kind', v_ability.ability_kind,
        'source_type', v_ability.source_type,
        'effect_mode', v_ability.effect_mode,
        'effective_level', v_effective_level
      ),
    'resource', v_resource_result,
    'result', jsonb_build_object('weapon_feature', v_activation_result),
    'combat_state', v_refresh,
    'message', format('%s activated.', v_ability.ability_name),
    'timings_ms',
      v_timings_ms || jsonb_build_object(
        'resource', coalesce(v_resource_result->'timings_ms', '{}'::jsonb),
        'total',
        greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
      )
  );
exception
  when lock_not_available then
    return jsonb_build_object(
      'ok', false,
      'error', 'ACTION_BUSY_RETRY',
      'message', 'Character state is busy. Please retry.',
      'stage', v_stage,
      'timings_ms',
        v_timings_ms || jsonb_build_object(
          v_stage,
          greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
          'total',
          greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
        )
    );
  when query_canceled then
    if SQLERRM ilike '%statement timeout%' or SQLERRM ilike '%lock timeout%' then
      return jsonb_build_object(
        'ok', false,
        'error', 'ACTION_BUSY_RETRY',
        'message', 'Character state is busy. Please retry.',
        'stage', v_stage,
        'timings_ms',
          v_timings_ms || jsonb_build_object(
            v_stage,
            greatest(0, floor(extract(epoch from clock_timestamp() - v_stage_started_at) * 1000)::integer),
            'total',
            greatest(0, floor(extract(epoch from clock_timestamp() - v_started_at) * 1000)::integer)
          )
      );
    end if;
    raise;
end;
$$;
