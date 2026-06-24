create or replace function public.odyssey_creator_build_perk_bundle(
  p_perk_def_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_perk jsonb := null;
begin
  select jsonb_build_object(
    'id', p.id,
    'code', p.code,
    'name', p.name,
    'description', coalesce(p.description, ''),
    'linked_skill_id', coalesce(p.linked_skill_id, p.skill_def_id),
    'skill_def_id', coalesce(p.linked_skill_id, p.skill_def_id),
    'linked_skill_code', skill.code,
    'linked_skill_name', skill.name,
    'skill_code', skill.code,
    'skill_name', skill.name,
    'required_skill_level', greatest(coalesce(p.required_skill_level, 1), 1),
    'perk_type', coalesce(p.perk_type, 'passive'),
    'activation_type', coalesce(p.activation_type, 'passive'),
    'resolution_mode', coalesce(p.resolution_mode, 'backend'),
    'effect_data', coalesce(p.effect_data, '{}'::jsonb),
    'tags', coalesce(p.tags, '[]'::jsonb),
    'is_enabled', coalesce(p.is_enabled, true),
    'is_custom', p.is_custom,
    'sort_order', p.sort_order,
    'created_at', p.created_at,
    'updated_at', p.updated_at
  )
  into v_perk
  from public.odyssey_perk_defs p
  left join public.odyssey_skill_defs skill on skill.id = coalesce(p.linked_skill_id, p.skill_def_id)
  where p.id = p_perk_def_id;

  if v_perk is null then
    return public.odyssey_creator_error(
      'PERK_NOT_FOUND',
      'Perk definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown perk definition id.'))
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'perk', v_perk
  );
end;
$$;

drop function if exists public.creator_list_perks(text);

create or replace function public.creator_list_perks(
  p_search text default null,
  p_linked_skill_id uuid default null,
  p_perk_type text default null,
  p_resolution_mode text default null
)
returns jsonb
language sql
stable
as $$
  with filter_input as (
    select
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      p_linked_skill_id as linked_skill_id,
      nullif(lower(trim(coalesce(p_perk_type, ''))), '') as perk_type,
      nullif(lower(trim(coalesce(p_resolution_mode, ''))), '') as resolution_mode
  ),
  filtered as (
    select
      perk.id,
      perk.code,
      perk.name,
      perk.sort_order,
      greatest(coalesce(perk.required_skill_level, 1), 1) as required_skill_level,
      coalesce(perk.linked_skill_id, perk.skill_def_id) as linked_skill_id,
      skill.code as linked_skill_code,
      skill.name as linked_skill_name,
      coalesce(perk.perk_type, 'passive') as perk_type,
      coalesce(perk.activation_type, 'passive') as activation_type,
      coalesce(perk.resolution_mode, 'backend') as resolution_mode,
      coalesce(perk.is_enabled, true) as is_enabled,
      coalesce(perk.tags, '[]'::jsonb) as tags
    from public.odyssey_perk_defs perk
    left join public.odyssey_skill_defs skill on skill.id = coalesce(perk.linked_skill_id, perk.skill_def_id)
    cross join filter_input
    where (
      filter_input.search_text is null
      or perk.code ilike '%' || filter_input.search_text || '%'
      or perk.name ilike '%' || filter_input.search_text || '%'
      or coalesce(skill.name, '') ilike '%' || filter_input.search_text || '%'
      or perk.tags::text ilike '%' || filter_input.search_text || '%'
    )
      and (
        filter_input.linked_skill_id is null
        or coalesce(perk.linked_skill_id, perk.skill_def_id) = filter_input.linked_skill_id
      )
      and (
        filter_input.perk_type is null
        or coalesce(perk.perk_type, 'passive') = filter_input.perk_type
      )
      and (
        filter_input.resolution_mode is null
        or coalesce(perk.resolution_mode, 'backend') = filter_input.resolution_mode
      )
  )
  select jsonb_build_object(
    'ok', true,
    'items',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'linked_skill_id', linked_skill_id,
            'linked_skill_code', linked_skill_code,
            'linked_skill_name', linked_skill_name,
            'skill_code', linked_skill_code,
            'skill_name', linked_skill_name,
            'required_skill_level', required_skill_level,
            'perk_type', perk_type,
            'activation_type', activation_type,
            'resolution_mode', resolution_mode,
            'is_enabled', is_enabled,
            'tags', tags
          )
          order by sort_order, name, code
        ),
        '[]'::jsonb
      )
  )
  from filtered;
$$;

create or replace function public.creator_get_perk(
  p_perk_def_id uuid
)
returns jsonb
language sql
stable
as $$
  select public.odyssey_creator_build_perk_bundle(p_perk_def_id);
$$;

create or replace function public.creator_upsert_perk(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := public.odyssey_creator_normalize_json_object(p_payload);
  v_id uuid := nullif(trim(coalesce(v_payload->>'id', '')), '')::uuid;
  v_code text := public.odyssey_creator_normalize_code(v_payload->>'code');
  v_name text := trim(coalesce(v_payload->>'name', ''));
  v_linked_skill_id uuid := nullif(trim(coalesce(v_payload->>'linked_skill_id', '')), '')::uuid;
  v_required_skill_level integer := greatest(coalesce(nullif(trim(coalesce(v_payload->>'required_skill_level', '')), '')::integer, 1), 1);
  v_perk_type text := lower(trim(coalesce(v_payload->>'perk_type', 'passive')));
  v_activation_type text := lower(trim(coalesce(v_payload->>'activation_type', 'passive')));
  v_resolution_mode text := lower(trim(coalesce(v_payload->>'resolution_mode', 'backend')));
  v_is_enabled boolean := coalesce(nullif(trim(coalesce(v_payload->>'is_enabled', '')), '')::boolean, true);
  v_description text := coalesce(v_payload->>'description', '');
  v_effect_data jsonb := public.odyssey_creator_normalize_json_object(v_payload->'effect_data');
  v_tags jsonb := public.odyssey_creator_normalize_text_array(v_payload->'tags');
  v_sort_order integer := coalesce(nullif(trim(coalesce(v_payload->>'sort_order', '')), '')::integer, 0);
  v_entity_id uuid := null;
  v_result jsonb := '{}'::jsonb;
begin
  if v_code = '' or not public.odyssey_creator_is_valid_code(v_code) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'code must match ^[a-z][a-z0-9_]*$.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Use lowercase snake_case starting with a letter.'))
    );
  end if;

  if v_name = '' then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'name is required.',
      jsonb_build_array(jsonb_build_object('field', 'name', 'message', 'Name cannot be empty.'))
    );
  end if;

  if v_linked_skill_id is null or not exists (
    select 1
    from public.odyssey_skill_defs skill
    where skill.id = v_linked_skill_id
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'linked_skill_id is required and must exist.',
      jsonb_build_array(jsonb_build_object('field', 'linked_skill_id', 'message', 'Unknown linked skill id.'))
    );
  end if;

  if v_perk_type not in ('passive', 'active', 'narrative') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'perk_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'perk_type', 'message', 'Unsupported perk_type value.'))
    );
  end if;

  if v_activation_type not in ('passive', 'manual', 'reaction', 'scene_start') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'activation_type is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'activation_type', 'message', 'Unsupported activation_type value.'))
    );
  end if;

  if v_resolution_mode not in ('backend', 'gm_resolved', 'hybrid') then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'resolution_mode is invalid.',
      jsonb_build_array(jsonb_build_object('field', 'resolution_mode', 'message', 'Unsupported resolution_mode value.'))
    );
  end if;

  if v_id is not null then
    select perk.id
    into v_entity_id
    from public.odyssey_perk_defs perk
    where perk.id = v_id;

    if v_entity_id is null then
      return public.odyssey_creator_error(
        'PERK_NOT_FOUND',
        'Perk definition was not found for update.',
        jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown perk definition id.'))
      );
    end if;
  else
    select perk.id
    into v_entity_id
    from public.odyssey_perk_defs perk
    where perk.code = v_code
    limit 1;
  end if;

  if exists (
    select 1
    from public.odyssey_perk_defs perk
    where perk.code = v_code
      and perk.id <> coalesce(v_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    return public.odyssey_creator_error(
      'VALIDATION_ERROR',
      'Perk code must be unique.',
      jsonb_build_array(jsonb_build_object('field', 'code', 'message', 'Duplicate perk code.'))
    );
  end if;

  if v_entity_id is null then
    insert into public.odyssey_perk_defs (
      linked_skill_id,
      skill_def_id,
      code,
      name,
      required_skill_level,
      description,
      perk_type,
      activation_type,
      resolution_mode,
      effect_data,
      tags,
      is_enabled,
      is_custom,
      sort_order
    )
    values (
      v_linked_skill_id,
      v_linked_skill_id,
      v_code,
      v_name,
      v_required_skill_level,
      v_description,
      v_perk_type,
      v_activation_type,
      v_resolution_mode,
      v_effect_data,
      v_tags,
      v_is_enabled,
      true,
      v_sort_order
    )
    returning id into v_entity_id;
  else
    update public.odyssey_perk_defs
    set
      linked_skill_id = v_linked_skill_id,
      skill_def_id = v_linked_skill_id,
      code = v_code,
      name = v_name,
      required_skill_level = v_required_skill_level,
      description = v_description,
      perk_type = v_perk_type,
      activation_type = v_activation_type,
      resolution_mode = v_resolution_mode,
      effect_data = v_effect_data,
      tags = v_tags,
      is_enabled = v_is_enabled,
      sort_order = v_sort_order
    where id = v_entity_id;
  end if;

  v_result := public.creator_get_perk(v_entity_id);

  return jsonb_build_object(
    'ok', true,
    'entity_id', v_entity_id,
    'entity', v_result,
    'warnings', '[]'::jsonb
  );
end;
$$;

create or replace function public.creator_delete_perk(
  p_perk_def_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_perk public.odyssey_perk_defs%rowtype;
  v_character_perk_count integer := 0;
  v_details jsonb := '[]'::jsonb;
begin
  select *
  into v_perk
  from public.odyssey_perk_defs perk
  where perk.id = p_perk_def_id;

  if not found then
    return public.odyssey_creator_error(
      'PERK_NOT_FOUND',
      'Perk definition was not found.',
      jsonb_build_array(jsonb_build_object('field', 'id', 'message', 'Unknown perk definition id.'))
    );
  end if;

  select count(*)::integer
  into v_character_perk_count
  from public.odyssey_character_perks character_perk
  where character_perk.perk_def_id = p_perk_def_id;

  select coalesce(jsonb_agg(item), '[]'::jsonb)
  into v_details
  from (
    select jsonb_build_object(
      'field', 'character_perks',
      'count', v_character_perk_count,
      'message', 'Perk is assigned to one or more characters.'
    ) as item
    where v_character_perk_count > 0
  ) dependency_rows;

  if v_details <> '[]'::jsonb then
    return public.odyssey_creator_error(
      'PERK_DEF_IN_USE',
      'Perk definition is still referenced and cannot be deleted.',
      v_details
    );
  end if;

  delete from public.odyssey_perk_defs perk
  where perk.id = p_perk_def_id;

  return jsonb_build_object(
    'ok', true,
    'deleted_id', p_perk_def_id,
    'deleted_code', v_perk.code
  );
end;
$$;

grant execute on function public.odyssey_creator_build_perk_bundle(uuid) to anon, authenticated;
grant execute on function public.creator_list_perks(text, uuid, text, text) to anon, authenticated;
grant execute on function public.creator_get_perk(uuid) to anon, authenticated;
grant execute on function public.creator_upsert_perk(jsonb) to anon, authenticated;
grant execute on function public.creator_delete_perk(uuid) to anon, authenticated;
