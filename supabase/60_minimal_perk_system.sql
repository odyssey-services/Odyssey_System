alter table public.odyssey_perk_defs
  alter column description set default '';

alter table public.odyssey_perk_defs
  alter column required_skill_level set default 1;

alter table public.odyssey_perk_defs
  add column if not exists linked_skill_id uuid references public.odyssey_skill_defs(id) on delete set null,
  add column if not exists perk_type text not null default 'passive',
  add column if not exists activation_type text not null default 'passive',
  add column if not exists resolution_mode text not null default 'backend',
  add column if not exists is_enabled boolean not null default true;

update public.odyssey_perk_defs
set
  description = coalesce(description, ''),
  required_skill_level = greatest(coalesce(required_skill_level, 1), 1),
  linked_skill_id = coalesce(linked_skill_id, skill_def_id),
  perk_type = case
    when coalesce(lower(trim(perk_type)), '') in ('passive', 'active', 'narrative') then lower(trim(perk_type))
    when coalesce(lower(trim(effect_type)), '') in ('special_action', 'grant_reaction') then 'narrative'
    else 'passive'
  end,
  activation_type = case
    when coalesce(lower(trim(activation_type)), '') in ('passive', 'manual', 'reaction', 'scene_start') then lower(trim(activation_type))
    else case
      when coalesce(lower(trim(effect_type)), '') = 'grant_reaction' then 'reaction'
      else 'passive'
    end
  end,
  resolution_mode = case
    when coalesce(lower(trim(resolution_mode)), '') in ('backend', 'gm_resolved', 'hybrid') then lower(trim(resolution_mode))
    else 'backend'
  end,
  is_enabled = coalesce(is_enabled, true);

create or replace function public.odyssey_sync_perk_def_legacy_fields()
returns trigger
language plpgsql
as $$
begin
  if new.linked_skill_id is null and new.skill_def_id is not null then
    new.linked_skill_id := new.skill_def_id;
  elsif new.skill_def_id is null and new.linked_skill_id is not null then
    new.skill_def_id := new.linked_skill_id;
  elsif tg_op = 'INSERT' and new.linked_skill_id is not null then
    new.skill_def_id := new.linked_skill_id;
  elsif tg_op = 'UPDATE' and new.linked_skill_id is distinct from old.linked_skill_id then
    new.skill_def_id := new.linked_skill_id;
  elsif tg_op = 'UPDATE' and new.skill_def_id is distinct from old.skill_def_id then
    new.linked_skill_id := new.skill_def_id;
  end if;

  new.description := coalesce(new.description, '');
  new.required_skill_level := greatest(coalesce(new.required_skill_level, 1), 1);
  new.perk_type := case
    when coalesce(lower(trim(new.perk_type)), '') in ('passive', 'active', 'narrative') then lower(trim(new.perk_type))
    else 'passive'
  end;
  new.activation_type := case
    when coalesce(lower(trim(new.activation_type)), '') in ('passive', 'manual', 'reaction', 'scene_start') then lower(trim(new.activation_type))
    else 'passive'
  end;
  new.resolution_mode := case
    when coalesce(lower(trim(new.resolution_mode)), '') in ('backend', 'gm_resolved', 'hybrid') then lower(trim(new.resolution_mode))
    else 'backend'
  end;
  new.is_enabled := coalesce(new.is_enabled, true);

  return new;
end;
$$;

drop trigger if exists odyssey_sync_perk_def_legacy_fields on public.odyssey_perk_defs;
create trigger odyssey_sync_perk_def_legacy_fields
before insert or update on public.odyssey_perk_defs
for each row
execute function public.odyssey_sync_perk_def_legacy_fields();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_perk_defs'::regclass
      and conname = 'odyssey_perk_defs_perk_type_check'
  ) then
    alter table public.odyssey_perk_defs
      add constraint odyssey_perk_defs_perk_type_check
      check (perk_type in ('passive', 'active', 'narrative'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_perk_defs'::regclass
      and conname = 'odyssey_perk_defs_activation_type_check'
  ) then
    alter table public.odyssey_perk_defs
      add constraint odyssey_perk_defs_activation_type_check
      check (activation_type in ('passive', 'manual', 'reaction', 'scene_start'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_perk_defs'::regclass
      and conname = 'odyssey_perk_defs_resolution_mode_check'
  ) then
    alter table public.odyssey_perk_defs
      add constraint odyssey_perk_defs_resolution_mode_check
      check (resolution_mode in ('backend', 'gm_resolved', 'hybrid'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_perk_defs'::regclass
      and conname = 'odyssey_perk_defs_required_skill_level_check'
  ) then
    alter table public.odyssey_perk_defs
      add constraint odyssey_perk_defs_required_skill_level_check
      check (required_skill_level >= 1);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.odyssey_character_perks'::regclass
      and conname = 'odyssey_character_perks_character_perk_key'
  ) then
    alter table public.odyssey_character_perks
      add constraint odyssey_character_perks_character_perk_key unique (character_id, perk_def_id);
  end if;
end;
$$;

create index if not exists odyssey_perk_defs_linked_skill_idx
  on public.odyssey_perk_defs (linked_skill_id, sort_order, code);

create or replace function public.odyssey_build_perk_weapon_effect_key(
  p_effect_code text,
  p_character_weapon_id uuid
)
returns text
language sql
immutable
as $$
  select case
    when p_character_weapon_id is null
      then lower(trim(coalesce(p_effect_code, 'custom_perk_effect')))
    else lower(trim(coalesce(p_effect_code, 'custom_perk_effect'))) || ':' || p_character_weapon_id::text
  end
$$;

create or replace function public.odyssey_get_character_weapon_perk_context(
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
      w.active_profile_id,
      coalesce(nullif(trim(w.custom_name), ''), wm.name) as weapon_name,
      wm.code as weapon_model_code,
      coalesce(p.code, '') as profile_code,
      coalesce(p.attack_type, 'ranged') as attack_type,
      coalesce(pwc.code, mwc.code) as weapon_class_code,
      coalesce(pcal.code, mcal.code) as caliber_code,
      coalesce(wm.tags, '[]'::jsonb) as model_tags,
      coalesce(p.tags, '[]'::jsonb) as profile_tags,
      exists (
        select 1
        from public.odyssey_weapon_profile_fire_modes pfm
        join public.odyssey_fire_mode_defs fm on fm.id = pfm.fire_mode_id
        where pfm.profile_id = coalesce(p.id, w.active_profile_id)
          and fm.code in ('burst_3', 'burst_5', 'full_auto_random', 'double')
      ) as has_multi_shot_mode
    from public.odyssey_character_weapons w
    join public.odyssey_weapon_model_defs wm on wm.id = w.weapon_model_id
    left join public.odyssey_weapon_model_profiles p on p.id = w.active_profile_id
    left join public.odyssey_weapon_class_defs mwc on mwc.id = wm.weapon_class_id
    left join public.odyssey_weapon_class_defs pwc on pwc.id = p.weapon_class_id
    left join public.odyssey_caliber_defs mcal on mcal.id = wm.caliber_id
    left join public.odyssey_caliber_defs pcal on pcal.id = p.caliber_id
    where w.id = p_character_weapon_id
  )
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'character_weapon_id', wr.character_weapon_id,
        'character_id', wr.character_id,
        'weapon_name', wr.weapon_name,
        'weapon_model_code', wr.weapon_model_code,
        'profile_code', wr.profile_code,
        'weapon_class_code', wr.weapon_class_code,
        'caliber_code', wr.caliber_code,
        'compatible',
          (
            wr.weapon_model_code in ('assault_rifle', 'standard_rifle')
            or wr.profile_code in ('assault_rifle', 'standard_rifle')
            or wr.model_tags ? 'assault_rifle'
            or wr.profile_tags ? 'assault_rifle'
            or (
              wr.weapon_class_code = 'rifle'
              and wr.attack_type = 'ranged'
              and wr.caliber_code = 'medium_caliber'
              and not (
                wr.model_tags ? 'sniper'
                or wr.model_tags ? 'precision'
                or wr.profile_tags ? 'sniper'
                or wr.profile_tags ? 'precision'
              )
            )
            or wr.has_multi_shot_mode
          )
      )
      from weapon_row wr
    ),
    jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_FOUND',
      'message', 'Weapon was not found.'
    )
  );
$$;

create or replace function public.odyssey_apply_effect_after_expire(
  p_character_id uuid,
  p_expired_effect_id uuid,
  p_expired_effect_key text,
  p_expired_effect_name text,
  p_expired_effect_data jsonb,
  p_created_by text default ''
)
returns jsonb
language plpgsql
as $$
declare
  v_after jsonb := case
    when jsonb_typeof(p_expired_effect_data->'after_expire') = 'object' then p_expired_effect_data->'after_expire'
    else '{}'::jsonb
  end;
  v_effect_code text := lower(trim(coalesce(v_after->>'apply_effect_code', '')));
  v_duration_rounds integer := greatest(coalesce(nullif(trim(coalesce(v_after->>'duration_rounds', '')), '')::integer, 1), 1);
  v_character_weapon_id uuid := public.odyssey_try_parse_uuid(v_after->>'character_weapon_id');
  v_effect_key text := '';
  v_effect_name text := '';
  v_effect_description text := '';
  v_effect_data jsonb := '{}'::jsonb;
  v_inserted_id uuid := null;
begin
  if p_character_id is null or v_effect_code = '' then
    return '{}'::jsonb;
  end if;

  v_effect_key := public.odyssey_build_perk_weapon_effect_key(v_effect_code, v_character_weapon_id);
  v_effect_name := initcap(replace(v_effect_code, '_', ' '));
  v_effect_description := coalesce(
    nullif(trim(coalesce(v_after->>'reason', '')), ''),
    format('Follow-up effect from %s.', coalesce(nullif(trim(p_expired_effect_name), ''), nullif(trim(p_expired_effect_key), ''), 'perk effect'))
  );

  v_effect_data := public.odyssey_merge_effect_data(
    jsonb_build_object(
      'perk_code', coalesce(nullif(trim(coalesce(p_expired_effect_data->>'perk_code', '')), ''), null),
      'character_weapon_id', case when v_character_weapon_id is not null then v_character_weapon_id::text else null end,
      'category', coalesce(nullif(trim(coalesce(v_after->>'category', '')), ''), 'combat')
    ),
    v_after - 'apply_effect_code' - 'duration_rounds'
  );

  update public.odyssey_character_effects
  set
    is_active = false,
    updated_at = timezone('utc', now())
  where character_id = p_character_id
    and is_active = true
    and effect_key = v_effect_key;

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
    v_effect_name,
    v_effect_description,
    'perk_after_expire',
    'perk',
    p_expired_effect_id,
    p_character_id,
    'rounds',
    v_duration_rounds,
    v_effect_data,
    true,
    coalesce(p_created_by, '')
  )
  returning id into v_inserted_id;

  return jsonb_build_object(
    'id', v_inserted_id,
    'effect_key', v_effect_key,
    'name', v_effect_name,
    'rounds_left', v_duration_rounds,
    'data', v_effect_data
  );
end;
$$;

create or replace function public.get_character_perks(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_perks jsonb := '[]'::jsonb;
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id must be a valid UUID.'
    );
  end if;

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_character_id
    );
  end if;

  select coalesce(
    jsonb_agg(perk_json order by sort_order, name, code),
    '[]'::jsonb
  )
  into v_perks
  from (
    select
      jsonb_build_object(
        'id', cp.id,
        'perk_def_id', p.id,
        'code', p.code,
        'name', p.name,
        'description', coalesce(p.description, ''),
        'linked_skill_id', coalesce(p.linked_skill_id, p.skill_def_id),
        'linked_skill_code', skill.code,
        'linked_skill_name', skill.name,
        'required_skill_level', greatest(coalesce(p.required_skill_level, 1), 1),
        'perk_type', coalesce(p.perk_type, 'passive'),
        'activation_type', coalesce(p.activation_type, 'passive'),
        'resolution_mode', coalesce(p.resolution_mode, 'backend'),
        'effect_data', coalesce(p.effect_data, '{}'::jsonb),
        'tags', coalesce(p.tags, '[]'::jsonb),
        'is_enabled', coalesce(p.is_enabled, true),
        'owned', true,
        'is_passive', coalesce(p.perk_type, 'passive') = 'passive' or coalesce(p.activation_type, 'passive') = 'passive',
        'can_use', case
          when not coalesce(p.is_enabled, true) then false
          when coalesce(p.perk_type, 'passive') = 'passive' or coalesce(p.activation_type, 'passive') = 'passive' then false
          else true
        end,
        'ui_hint', coalesce(nullif(trim(coalesce(p.effect_data->>'ui_hint', '')), ''), coalesce(p.description, '')),
        'acquired_at', cp.acquired_at,
        'notes', coalesce(cp.notes, '')
      ) as perk_json,
      p.sort_order,
      p.name,
      p.code
    from public.odyssey_character_perks cp
    join public.odyssey_perk_defs p on p.id = cp.perk_def_id
    left join public.odyssey_skill_defs skill on skill.id = coalesce(p.linked_skill_id, p.skill_def_id)
    where cp.character_id = v_character_id
  ) owned_perks;

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'perks', v_perks
  );
end;
$$;

create or replace function public.get_character_available_perks(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_id');
  v_items jsonb := '[]'::jsonb;
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'INVALID_PAYLOAD',
      'message', 'character_id must be a valid UUID.'
    );
  end if;

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_character_id
    );
  end if;

  with skill_levels as (
    select
      s.skill_def_id,
      coalesce(s.level, 0) as skill_level
    from public.odyssey_character_skills s
    where s.character_id = v_character_id
  ),
  availability as (
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
      p.sort_order,
      owned.id as character_perk_id,
      owned.acquired_at,
      owned.notes,
      coalesce(levels.skill_level, 0) as skill_level,
      case
        when owned.id is not null then 'owned'
        when not coalesce(p.is_enabled, true) then 'locked'
        when coalesce(p.linked_skill_id, p.skill_def_id) is not null and levels.skill_def_id is null then 'locked'
        when coalesce(levels.skill_level, 0) < greatest(coalesce(p.required_skill_level, 1), 1) then 'locked'
        else 'available'
      end as status,
      case
        when owned.id is not null then 'ALREADY_OWNED'
        when not coalesce(p.is_enabled, true) then 'PERK_DISABLED'
        when coalesce(p.linked_skill_id, p.skill_def_id) is not null and levels.skill_def_id is null then 'SKILL_NOT_FOUND'
        when coalesce(levels.skill_level, 0) < greatest(coalesce(p.required_skill_level, 1), 1) then 'SKILL_LEVEL_TOO_LOW'
        else null
      end as lock_reason
    from public.odyssey_perk_defs p
    left join public.odyssey_skill_defs skill on skill.id = coalesce(p.linked_skill_id, p.skill_def_id)
    left join skill_levels levels on levels.skill_def_id = coalesce(p.linked_skill_id, p.skill_def_id)
    left join public.odyssey_character_perks owned
      on owned.character_id = v_character_id
     and owned.perk_def_id = p.id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'perk_def_id', perk_def_id,
        'character_perk_id', character_perk_id,
        'code', code,
        'name', name,
        'description', description,
        'linked_skill_id', linked_skill_id,
        'linked_skill_code', linked_skill_code,
        'linked_skill_name', linked_skill_name,
        'required_skill_level', required_skill_level,
        'current_skill_level', skill_level,
        'perk_type', perk_type,
        'activation_type', activation_type,
        'resolution_mode', resolution_mode,
        'effect_data', effect_data,
        'tags', tags,
        'is_enabled', is_enabled,
        'ui_hint', coalesce(nullif(trim(coalesce(effect_data->>'ui_hint', '')), ''), description),
        'owned', status = 'owned',
        'available', status = 'available',
        'locked', status = 'locked',
        'status', status,
        'lock_reason', lock_reason,
        'acquired_at', acquired_at,
        'notes', coalesce(notes, '')
      )
      order by sort_order, name, code
    ),
    '[]'::jsonb
  )
  into v_items
  from availability;

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'perks', v_items,
    'owned', coalesce((select jsonb_agg(value) from jsonb_array_elements(v_items) as item(value) where value->>'status' = 'owned'), '[]'::jsonb),
    'available', coalesce((select jsonb_agg(value) from jsonb_array_elements(v_items) as item(value) where value->>'status' = 'available'), '[]'::jsonb),
    'locked', coalesce((select jsonb_agg(value) from jsonb_array_elements(v_items) as item(value) where value->>'status' = 'locked'), '[]'::jsonb)
  );
end;
$$;

create or replace function public.grant_character_perk(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_character_id uuid := public.odyssey_try_parse_uuid(v_payload->>'character_id');
  v_perk_code text := lower(trim(coalesce(v_payload->>'perk_code', '')));
  v_spend_development_point boolean := coalesce(nullif(trim(coalesce(v_payload->>'spend_development_point', '')), '')::boolean, false);
  v_created_by text := coalesce(nullif(trim(coalesce(v_payload->>'created_by', '')), ''), '');
  v_perk record;
  v_skill_level integer := 0;
  v_progression_result jsonb := '{}'::jsonb;
  v_perks_result jsonb := '{}'::jsonb;
  v_perk_json jsonb := '{}'::jsonb;
  v_state_version integer := 0;
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

  if not exists (
    select 1
    from public.odyssey_characters c
    where c.id = v_character_id
      and coalesce(c.is_deleted, false) = false
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', v_character_id
    );
  end if;

  select
    p.id,
    p.code,
    p.name,
    coalesce(p.linked_skill_id, p.skill_def_id) as linked_skill_id,
    greatest(coalesce(p.required_skill_level, 1), 1) as required_skill_level,
    coalesce(p.is_enabled, true) as is_enabled
  into v_perk
  from public.odyssey_perk_defs p
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

  if exists (
    select 1
    from public.odyssey_character_perks cp
    where cp.character_id = v_character_id
      and cp.perk_def_id = v_perk.id
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'PERK_ALREADY_OWNED',
      'message', 'Character already owns this perk.',
      'perk_code', v_perk_code
    );
  end if;

  if v_perk.linked_skill_id is not null then
    select coalesce(s.level, 0)
    into v_skill_level
    from public.odyssey_character_skills s
    where s.character_id = v_character_id
      and s.skill_def_id = v_perk.linked_skill_id;

    if v_skill_level < v_perk.required_skill_level then
      return jsonb_build_object(
        'ok', false,
        'error', 'SKILL_LEVEL_TOO_LOW',
        'message', 'Linked skill level is too low for this perk.',
        'perk_code', v_perk_code,
        'required_skill_level', v_perk.required_skill_level,
        'current_skill_level', v_skill_level
      );
    end if;
  end if;

  if v_spend_development_point then
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'purchase_character_perk'
        and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb'
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'PROGRESSION_SPEND_NOT_AVAILABLE',
        'message', 'Progression spend helper is not available.'
      );
    end if;

    v_progression_result := public.purchase_character_perk(
      jsonb_build_object(
        'character_id', v_character_id,
        'perk_code', v_perk_code,
        'reason', nullif(v_created_by, '')
      )
    );

    if coalesce((v_progression_result->>'ok')::boolean, false) = false then
      if v_progression_result->>'error' = 'PERK_SKILL_REQUIREMENT_NOT_MET' then
        return jsonb_build_object(
          'ok', false,
          'error', 'SKILL_LEVEL_TOO_LOW',
          'message', coalesce(v_progression_result->>'message', 'Linked skill level is too low.')
        );
      end if;
      return v_progression_result;
    end if;
  else
    insert into public.odyssey_character_perks (
      character_id,
      perk_def_id
    )
    values (
      v_character_id,
      v_perk.id
    );

    v_state_version := public.odyssey_bump_character_state_version(v_character_id);
    v_progression_result := jsonb_build_object(
      'ok', true,
      'state_version', v_state_version,
      'development_points_spent', false
    );
  end if;

  v_perks_result := public.get_character_perks(jsonb_build_object('character_id', v_character_id));

  select value
  into v_perk_json
  from jsonb_array_elements(coalesce(v_perks_result->'perks', '[]'::jsonb)) value
  where value->>'code' = v_perk_code
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'character_id', v_character_id,
    'perk', coalesce(v_perk_json, '{}'::jsonb),
    'progression', v_progression_result
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
  v_multiplier integer := 1;
  v_cooling_active boolean := false;
begin
  if v_attacker_character_id is null or v_weapon_id is null then
    return jsonb_build_object(
      'ok', true,
      'perk_context', '{}'::jsonb
    );
  end if;

  select exists (
    select 1
    from public.odyssey_character_effects e
    where e.character_id = v_attacker_character_id
      and e.is_active = true
      and coalesce(e.data->>'character_weapon_id', '') = v_weapon_id::text
      and coalesce(nullif(e.data#>>'{flags,weapon_locked}', ''), 'false') in ('true', '1', 'yes', 'on')
  )
  into v_cooling_active;

  if v_cooling_active then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_COOLING',
      'message', 'Weapon is cooling down and cannot attack this round.',
      'character_weapon_id', v_weapon_id
    );
  end if;

  select greatest(coalesce(nullif(trim(coalesce(modifier->>'value', '')), '')::integer, 1), 1)
  into v_multiplier
  from public.odyssey_character_effects e
  cross join lateral jsonb_array_elements(coalesce(e.data->'modifiers', '[]'::jsonb)) modifier
  where e.character_id = v_attacker_character_id
    and e.is_active = true
    and coalesce(e.data->>'perk_code', '') = 'not_full_auto'
    and coalesce(e.data->>'character_weapon_id', '') = v_weapon_id::text
    and coalesce(modifier->>'target', '') = 'ammo_base_damage'
    and coalesce(modifier->>'operation', '') = 'multiply'
  order by e.updated_at desc, e.created_at desc, e.id desc
  limit 1;

  if coalesce(v_multiplier, 1) <= 1 then
    return jsonb_build_object(
      'ok', true,
      'perk_context', '{}'::jsonb
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'perk_context',
      jsonb_build_object(
        'ammo_base_damage_multiplier', v_multiplier,
        'perk_modifiers',
          jsonb_build_array(
            jsonb_build_object(
              'perk_code', 'not_full_auto',
              'modifier', 'ammo_base_damage_multiplier',
              'value', v_multiplier
            )
          )
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
  v_log_id uuid := null;
  v_message text := '';
  v_gm_hint text := '';
  v_effect_key text := '';
  v_cooling_effect_key text := '';
  v_effect_id uuid := null;
  v_duration_rounds integer := 2;
  v_cooling_rounds integer := 1;
  v_damage_multiplier integer := 2;
  v_effect_data jsonb := '{}'::jsonb;
  v_combat_state jsonb := '{}'::jsonb;
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

  if v_perk.code <> 'not_full_auto' then
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

  v_weapon_context := public.odyssey_get_character_weapon_perk_context(v_character_weapon_id);

  if coalesce((v_weapon_context->>'ok')::boolean, false) = false then
    return v_weapon_context;
  end if;

  if not coalesce((v_weapon_context->>'compatible')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_NOT_COMPATIBLE',
      'message', 'Weapon is not compatible with this perk.',
      'character_weapon_id', v_character_weapon_id,
      'weapon_context', v_weapon_context
    );
  end if;

  v_cooling_effect_key := public.odyssey_build_perk_weapon_effect_key('coil_cooling', v_character_weapon_id);
  v_effect_key := public.odyssey_build_perk_weapon_effect_key(v_perk.code, v_character_weapon_id);

  if exists (
    select 1
    from public.odyssey_character_effects e
    where e.character_id = v_character_id
      and e.is_active = true
      and e.effect_key = v_cooling_effect_key
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'WEAPON_COOLING',
      'message', 'Weapon is cooling down and cannot use this perk yet.',
      'character_weapon_id', v_character_weapon_id
    );
  end if;

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

  v_message := format(
    '%s activates perk "%s" on %s.',
    coalesce(nullif(trim(v_character.resources->>'name'), ''), v_character.character_key),
    v_perk.name,
    coalesce(v_weapon_context->>'weapon_name', 'weapon')
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
      'character_weapon_id', v_character_weapon_id,
      'effect_id', v_effect_id,
      'duration_rounds', v_duration_rounds,
      'cooling_rounds', v_cooling_rounds
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
      jsonb_build_array(
        jsonb_build_object(
          'perk_code', v_perk.code,
          'modifier', 'ammo_base_damage_multiplier',
          'value', v_damage_multiplier
        )
      )
  );
end;
$$;

create or replace function public.advance_character_effects(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_changed_effects jsonb := '[]'::jsonb;
  v_expired_effects jsonb := '[]'::jsonb;
  v_followup_effects jsonb := '[]'::jsonb;
  v_refresh jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_ability_states jsonb := '{}'::jsonb;
  v_weapon_feature_states jsonb := '{}'::jsonb;
  v_expired_row record;
  v_followup_result jsonb := '{}'::jsonb;
begin
  with updated_effects as (
    update public.odyssey_character_effects e
    set
      rounds_left = case
        when e.duration_type = 'rounds' and e.rounds_left is not null
          then greatest(e.rounds_left - 1, 0)
        else e.rounds_left
      end,
      is_active = case
        when coalesce(nullif(e.data#>>'{flags,expires_after_turn}', '')::boolean, false) then false
        when e.duration_type = 'rounds' and e.rounds_left is not null and e.rounds_left - 1 <= 0 then false
        else e.is_active
      end,
      updated_at = timezone('utc', now())
    where e.character_id = p_character_id
      and e.is_active = true
      and (
        (e.duration_type = 'rounds' and e.rounds_left is not null)
        or coalesce(nullif(e.data#>>'{flags,expires_after_turn}', '')::boolean, false)
      )
    returning e.*
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', u.id,
          'effect_key', u.effect_key,
          'name', u.name,
          'duration_type', u.duration_type,
          'rounds_left', u.rounds_left,
          'is_active', u.is_active
        )
        order by u.updated_at desc, u.id
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', u.id,
          'effect_key', u.effect_key,
          'name', u.name,
          'duration_type', u.duration_type,
          'rounds_left', u.rounds_left,
          'data', u.data
        )
        order by u.updated_at desc, u.id
      ) filter (where u.is_active = false),
      '[]'::jsonb
    )
  into
    v_changed_effects,
    v_expired_effects
  from updated_effects u;

  for v_expired_row in
    select u.id, u.effect_key, u.name, u.data, u.created_by
    from public.odyssey_character_effects u
    where u.character_id = p_character_id
      and u.id in (
        select public.odyssey_try_parse_uuid(item->>'id')
        from jsonb_array_elements(coalesce(v_expired_effects, '[]'::jsonb)) item
      )
  loop
    v_followup_result := public.odyssey_apply_effect_after_expire(
      p_character_id,
      v_expired_row.id,
      v_expired_row.effect_key,
      v_expired_row.name,
      coalesce(v_expired_row.data, '{}'::jsonb),
      coalesce(v_expired_row.created_by, '')
    );
    if v_followup_result <> '{}'::jsonb then
      v_followup_effects := v_followup_effects || jsonb_build_array(v_followup_result);
    end if;
  end loop;

  v_ability_states := public.advance_character_ability_states(p_character_id);
  v_weapon_feature_states := public.advance_weapon_feature_states(p_character_id);
  v_refresh := public.odyssey_refresh_character_combat_state(p_character_id);
  v_effective_stats := public.get_effective_character_stats(p_character_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'changed_effects', v_changed_effects,
    'expired_effects', v_expired_effects,
    'followup_effects', v_followup_effects,
    'ability_states', coalesce(v_ability_states->'changed_abilities', '[]'::jsonb),
    'weapon_feature_states', coalesce(v_weapon_feature_states->'states', '[]'::jsonb),
    'effective_stats', v_effective_stats,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
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
  v_character_ability_id uuid := public.odyssey_try_parse_uuid(p_payload->>'character_ability_id');
  v_ability_code text := lower(trim(coalesce(p_payload->>'ability_code', '')));
  v_target_character_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_character_id');
  v_target_body_part_id uuid := public.odyssey_try_parse_uuid(p_payload->>'target_body_part_id');
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_perk_context_result jsonb := jsonb_build_object('ok', true, 'perk_context', '{}'::jsonb);
  v_result jsonb := '{}'::jsonb;
begin
  if v_character_ability_id is not null or v_ability_code <> '' then
    return public.odyssey_perform_ability_attack(v_payload);
  end if;

  v_perk_context_result := public.odyssey_get_weapon_perk_attack_context(v_payload);
  if coalesce((v_perk_context_result->>'ok')::boolean, false) = false then
    return v_perk_context_result;
  end if;

  if jsonb_typeof(v_perk_context_result->'perk_context') = 'object' then
    v_payload := v_payload || jsonb_build_object('perk_context', v_perk_context_result->'perk_context');
  end if;

  v_result := public.odyssey_perform_weapon_attack(v_payload);

  if coalesce((v_result->>'ok')::boolean, false) = true then
    return public.odyssey_finalize_attack_result(v_result, v_target_character_id, v_target_body_part_id);
  end if;

  return v_result;
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

  if v_function_def is not null then
    if position($needle$v_next_feature_requires_reload boolean;$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$v_next_feature_requires_reload boolean;$old$,
        $new$v_next_feature_requires_reload boolean;
  v_perk_context jsonb := coalesce(
    case
      when jsonb_typeof(p_payload->'perk_context') = 'object' then p_payload->'perk_context'
      else '{}'::jsonb
    end,
    '{}'::jsonb
  );
  v_perk_base_damage_multiplier integer := greatest(coalesce(nullif(trim(coalesce(p_payload#>>'{perk_context,ammo_base_damage_multiplier}', '')), '')::integer, 1), 1);
  v_perk_modifiers jsonb := coalesce(
    case
      when jsonb_typeof(p_payload->'perk_context'->'perk_modifiers') = 'array' then p_payload->'perk_context'->'perk_modifiers'
      else '[]'::jsonb
    end,
    '[]'::jsonb
  );$new$
      );
    end if;

    if position($needle$v_bullet_damage := greatest(coalesce(v_weapon_profile.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$v_bullet_damage := greatest(coalesce(v_weapon_profile.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;$old$,
        $new$v_bullet_damage := greatest(coalesce(v_weapon_profile.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            if v_perk_base_damage_multiplier > 1 then
              v_bullet_damage := v_bullet_damage * v_perk_base_damage_multiplier;
            end if;
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;$new$
      );
    end if;

    if position($needle$'remaining_magazine_rounds', v_remaining_rounds,
    'weapon_features',$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$'remaining_magazine_rounds', v_remaining_rounds,
    'weapon_features',$old$,
        $new$'remaining_magazine_rounds', v_remaining_rounds,
    'perk_modifiers', v_perk_modifiers,
    'weapon_features',$new$
      );
    end if;

    if position($needle$'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'weapon_features',$needle$ in v_function_def) > 0 then
      v_function_def := replace(
        v_function_def,
        $old$'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'weapon_features',$old$,
        $new$'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'perk_modifiers', v_perk_modifiers,
    'weapon_features',$new$
      );
    end if;

    execute v_function_def;
  end if;
end;
$$;

do $$
declare
  v_function_def text := null;
  v_old_block text := $old$
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
  end if;$old$;
  v_new_block text := $new$
  if v_all_sections or 'perks' = any(v_requested) then
    v_perks := coalesce(
      public.get_character_perks(jsonb_build_object('character_id', v_character_id))->'perks',
      '[]'::jsonb
    );
  end if;$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_function_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_character_runtime_bundle'
    and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb';

  if v_function_def is not null then
    if position(v_old_block in v_function_def) > 0 then
      v_function_def := replace(v_function_def, v_old_block, v_new_block);
      execute v_function_def;
    end if;
  end if;
end;
$$;

insert into public.odyssey_perk_defs (
  code,
  name,
  description,
  linked_skill_id,
  required_skill_level,
  perk_type,
  activation_type,
  resolution_mode,
  effect_data,
  tags,
  is_enabled,
  is_custom,
  sort_order
)
select
  seed.code,
  seed.name,
  seed.description,
  skill.id,
  seed.required_skill_level,
  seed.perk_type,
  seed.activation_type,
  seed.resolution_mode,
  seed.effect_data,
  seed.tags,
  true,
  false,
  seed.sort_order
from (
  values
    (
      'cards_money',
      'Карты, деньги',
      'При двух пистолетах разрешает две атаки за одно действие.',
      array['pistols']::text[],
      2,
      'passive',
      'passive',
      'backend',
      jsonb_build_object(
        'type', 'passive_rule',
        'conditions', jsonb_build_object('requires_dual_wield', true, 'weapon_tags', jsonb_build_array('pistol')),
        'effects', jsonb_build_object('extra_attacks_per_action', 1, 'max_attacks_per_action', 2),
        'ui_hint', 'При двух пистолетах разрешает две атаки за одно действие.'
      ),
      jsonb_build_array('perk', 'pistols', 'dual_wield'),
      10
    ),
    (
      'for_the_brotherhood_and_yard_pistols',
      'За братву и двор',
      'Игнорирует штраф пистолетов в клинче.',
      array['pistols']::text[],
      2,
      'passive',
      'passive',
      'backend',
      jsonb_build_object(
        'type', 'passive_rule',
        'conditions', jsonb_build_object('weapon_tags', jsonb_build_array('pistol'), 'range_bands', jsonb_build_array('clinch')),
        'effects', jsonb_build_object('ignore_penalty', 'pistol_clinch'),
        'ui_hint', 'Игнорирует штраф пистолетов в клинче.'
      ),
      jsonb_build_array('perk', 'pistols', 'clinch'),
      20
    ),
    (
      'not_han_solo',
      'Не Хан Соло',
      'Объявляет бесплатный quickdraw-выстрел в начале сцены; сам выстрел пока ведет GM.',
      array['pistols']::text[],
      2,
      'active',
      'scene_start',
      'gm_resolved',
      jsonb_build_object(
        'type', 'scene_start_announcement',
        'ui_hint', 'Бесплатный quickdraw-выстрел в начале сцены. Сам выстрел пока разрешает GM.'
      ),
      jsonb_build_array('perk', 'pistols', 'scene_start'),
      30
    ),
    (
      'flutter_like_butterfly',
      'Порхай как бабочка',
      '+15 к точности burst-очередей на короткой дистанции.',
      array['smg']::text[],
      2,
      'passive',
      'passive',
      'backend',
      jsonb_build_object(
        'type', 'passive_rule',
        'conditions', jsonb_build_object('weapon_tags', jsonb_build_array('smg'), 'range_bands', jsonb_build_array('short'), 'fire_modes', jsonb_build_array('burst_3', 'burst_5')),
        'effects', jsonb_build_object('attack_accuracy_bonus', 15),
        'ui_hint', '+15 к точности burst-очередей на короткой дистанции.'
      ),
      jsonb_build_array('perk', 'smg', 'burst'),
      40
    ),
    (
      'no_brains_smg',
      'Нет ума',
      'Объявляет мульти-таргет burst на короткой дистанции; дополнительные цели и сложность решает GM.',
      array['smg']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_burst',
        'ui_hint', 'Мульти-таргет burst на короткой дистанции. Дополнительные цели и сложность решает GM.'
      ),
      jsonb_build_array('perk', 'smg', 'burst', 'gm_resolved'),
      50
    ),
    (
      'overwatch_sector',
      'Овердроч',
      'Объявляет 30-градусный сектор overwatch; сектор пока вручную ведет GM.',
      array['rifles']::text[],
      2,
      'narrative',
      'reaction',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_overwatch',
        'ui_hint', '30-градусный сектор overwatch. Сектор и триггеры пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'rifles', 'overwatch'),
      60
    ),
    (
      'no_brains_assault_rifle',
      'Нет ума',
      'Объявляет мульти-таргет burst на короткой/средней дистанции; цели и сложность решает GM.',
      array['rifles']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_burst',
        'ui_hint', 'Мульти-таргет burst на короткой/средней дистанции. Цели и сложность решает GM.'
      ),
      jsonb_build_array('perk', 'rifles', 'assault_rifle', 'gm_resolved'),
      70
    ),
    (
      'not_full_auto',
      'Not full-auto',
      'Форсирует катушку: стандартный урон пули x2 на 2 хода, затем оружие охлаждается 1 ход.',
      array['rifles']::text[],
      2,
      'active',
      'manual',
      'hybrid',
      jsonb_build_object(
        'type', 'active_weapon_effect',
        'requires_weapon_tags', jsonb_build_array('assault_rifle'),
        'duration_rounds', 2,
        'effects', jsonb_build_object('ammo_base_damage_multiplier', 2),
        'after_expire', jsonb_build_object('weapon_locked_rounds', 1, 'reason', 'coil_cooling'),
        'ui_hint', 'Форсирует катушку: стандартный урон пули x2 на 2 хода, затем оружие охлаждается 1 ход.'
      ),
      jsonb_build_array('perk', 'rifles', 'assault_rifle', 'hybrid'),
      80
    ),
    (
      'patient_hunter',
      'Терпеливый охотник',
      'Объявляет подготовку выстрела с накоплением +20 за ход до +100; пока решается GM.',
      array['rifles']::text[],
      2,
      'active',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_preparation',
        'ui_hint', 'Подготовка выстрела: +20 за ход до +100. Пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'rifles', 'sniper', 'gm_resolved'),
      90
    ),
    (
      'calibrating',
      'Калибрую',
      'После убийства из той же винтовки дает +1 к точности; автоматизация убийств пока не включена.',
      array['rifles']::text[],
      2,
      'passive',
      'passive',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_stack',
        'ui_hint', 'После убийства из той же винтовки дает +1 к точности. Пока GM отслеживает вручную.'
      ),
      jsonb_build_array('perk', 'rifles', 'sniper', 'gm_resolved'),
      100
    ),
    (
      'first_time_no',
      'Первый раз не',
      'После промаха по неподвижной цели следующий выстрел по ней получает +25; трекинг цели пока ведет GM.',
      array['rifles']::text[],
      2,
      'passive',
      'passive',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_retry_bonus',
        'ui_hint', 'После промаха по неподвижной цели следующий выстрел получает +25. Пока GM отслеживает вручную.'
      ),
      jsonb_build_array('perk', 'rifles', 'sniper', 'gm_resolved'),
      110
    ),
    (
      'head_taker',
      'Снос башки',
      'Двойной урон дробовика в клинче/на короткой дистанции после попадания. Пока решается GM.',
      array['shotguns']::text[],
      2,
      'active',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_shotgun_finisher',
        'ui_hint', 'Двойной урон дробовика в клинче/на короткой дистанции после попадания. Пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'shotguns', 'close_range', 'gm_resolved'),
      120
    ),
    (
      'captain_price',
      'Капитан Прайс',
      'Позволяет проверкой вскрывать бронированные двери из дробовика.',
      array['shotguns']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_breach',
        'ui_hint', 'Проверка для вскрытия бронированных дверей из дробовика. Пока решает GM.'
      ),
      jsonb_build_array('perk', 'shotguns', 'breach', 'gm_resolved'),
      130
    ),
    (
      'for_the_brotherhood_and_yard_shotguns',
      'За братву и двор',
      'Снижает штраф дробовика в клинче на 15. Нокбэк пока решает GM.',
      array['shotguns']::text[],
      2,
      'passive',
      'passive',
      'hybrid',
      jsonb_build_object(
        'type', 'passive_rule',
        'conditions', jsonb_build_object('weapon_tags', jsonb_build_array('shotgun'), 'range_bands', jsonb_build_array('clinch')),
        'effects', jsonb_build_object('range_penalty_reduction', 15),
        'ui_hint', 'Снижает штраф дробовика в клинче на 15. Нокбэк пока решает GM.'
      ),
      jsonb_build_array('perk', 'shotguns', 'clinch'),
      140
    ),
    (
      'ratatatata',
      'Ра-та-та-та',
      'Объявляет подавляющий огонь в секторе 45 градусов; волю, ограничения движения и расход ленты пока ведет GM.',
      array['machine_guns']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_suppression',
        'ui_hint', 'Подавляющий огонь в секторе 45 градусов. Пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'machine_guns', 'suppression', 'gm_resolved'),
      150
    ),
    (
      'whist',
      'Вист',
      'Объявляет 5-градусный конус и цели за первой целью; дальнейшее разрешение пока ведет GM.',
      array['machine_guns']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_cone',
        'ui_hint', '5-градусный конус и цели за первой целью. Пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'machine_guns', 'cone', 'gm_resolved'),
      160
    ),
    (
      'demolition',
      'Демонтаж',
      'Объявляет попытку разрушения укрытия; укрытие как броню и добивание пока вручную ведет GM.',
      array['machine_guns']::text[],
      2,
      'narrative',
      'manual',
      'gm_resolved',
      jsonb_build_object(
        'type', 'gm_resolved_cover_break',
        'ui_hint', 'Попытка разрушения укрытия. Пока вручную ведет GM.'
      ),
      jsonb_build_array('perk', 'machine_guns', 'cover', 'gm_resolved'),
      170
    )
) as seed(code, name, description, skill_codes, required_skill_level, perk_type, activation_type, resolution_mode, effect_data, tags, sort_order)
left join lateral (
  select s.id
  from public.odyssey_skill_defs s
  where s.code = any(seed.skill_codes)
  order by array_position(seed.skill_codes, s.code), s.sort_order, s.code
  limit 1
) skill on true
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  linked_skill_id = excluded.linked_skill_id,
  skill_def_id = excluded.linked_skill_id,
  required_skill_level = excluded.required_skill_level,
  perk_type = excluded.perk_type,
  activation_type = excluded.activation_type,
  resolution_mode = excluded.resolution_mode,
  effect_data = excluded.effect_data,
  tags = excluded.tags,
  is_enabled = excluded.is_enabled,
  is_custom = excluded.is_custom,
  sort_order = excluded.sort_order;

grant execute on function public.odyssey_sync_perk_def_legacy_fields() to anon, authenticated;
grant execute on function public.odyssey_build_perk_weapon_effect_key(text, uuid) to anon, authenticated;
grant execute on function public.odyssey_get_character_weapon_perk_context(uuid) to anon, authenticated;
grant execute on function public.odyssey_apply_effect_after_expire(uuid, uuid, text, text, jsonb, text) to anon, authenticated;
grant execute on function public.get_character_perks(jsonb) to anon, authenticated;
grant execute on function public.get_character_available_perks(jsonb) to anon, authenticated;
grant execute on function public.grant_character_perk(jsonb) to anon, authenticated;
grant execute on function public.odyssey_get_weapon_perk_attack_context(jsonb) to anon, authenticated;
grant execute on function public.use_character_perk(jsonb) to anon, authenticated;
