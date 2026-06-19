create extension if not exists pgcrypto;

create table if not exists public.odyssey_effect_defs (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  category text not null check (category in ('buff', 'debuff', 'condition', 'combat', 'psionic', 'equipment', 'weapon', 'armor', 'narrative', 'custom')),
  description text not null default '',
  default_duration_type text not null default 'manual' check (default_duration_type in ('manual', 'rounds', 'until_turn_start', 'until_turn_end', 'scene', 'until_used')),
  default_rounds integer null,
  stacking_mode text not null default 'replace' check (stacking_mode in ('replace', 'stack', 'highest', 'lowest', 'unique')),
  is_negative boolean not null default false,
  is_narrative boolean not null default false,
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  tags jsonb not null default '[]'::jsonb check (jsonb_typeof(tags) = 'array'),
  is_custom boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.odyssey_effect_defs enable row level security;

drop policy if exists "odyssey_effect_defs_full_access" on public.odyssey_effect_defs;
create policy "odyssey_effect_defs_full_access"
on public.odyssey_effect_defs
for all
using (true)
with check (true);

grant select, insert, update, delete on public.odyssey_effect_defs to anon, authenticated;

drop trigger if exists odyssey_touch_updated_at_effect_defs on public.odyssey_effect_defs;
create trigger odyssey_touch_updated_at_effect_defs
before update on public.odyssey_effect_defs
for each row
execute function public.odyssey_touch_updated_at();

alter table public.odyssey_character_effects
  add column if not exists effect_def_id uuid references public.odyssey_effect_defs(id) on delete set null,
  add column if not exists source_type text not null default '',
  add column if not exists source_id uuid null,
  add column if not exists stacks integer not null default 1;

do $$
declare
  v_constraint_name text;
begin
  select conname
  into v_constraint_name
  from pg_constraint
  where conrelid = 'public.odyssey_character_effects'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%duration_type%';

  if v_constraint_name is not null then
    execute format(
      'alter table public.odyssey_character_effects drop constraint %I',
      v_constraint_name
    );
  end if;
end;
$$;

alter table public.odyssey_character_effects
  drop constraint if exists odyssey_character_effects_duration_type_check;

alter table public.odyssey_character_effects
  add constraint odyssey_character_effects_duration_type_check
  check (duration_type in ('manual', 'rounds', 'until_turn_start', 'until_turn_end', 'scene', 'until_used'));

alter table public.odyssey_character_effects
  drop constraint if exists odyssey_character_effects_stacks_check;

alter table public.odyssey_character_effects
  add constraint odyssey_character_effects_stacks_check
  check (stacks >= 1);

create index if not exists odyssey_character_effects_effect_def_idx
  on public.odyssey_character_effects (effect_def_id);

create index if not exists odyssey_character_effects_effect_key_active_idx
  on public.odyssey_character_effects (character_id, effect_key, is_active);

alter table public.odyssey_character_combat_state
  add column if not exists effective_stats jsonb not null default '{}'::jsonb,
  add column if not exists combat_flags jsonb not null default '{}'::jsonb;

create or replace function public.odyssey_get_armor_class(
  p_total_armor_value integer
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_total_armor_value, 0) <= 0 then 'none'
    when p_total_armor_value <= 70 then 'light'
    when p_total_armor_value <= 140 then 'medium'
    when p_total_armor_value <= 260 then 'heavy'
    else 'superheavy'
  end;
$$;

create or replace function public.odyssey_get_main_actions_from_agility(
  p_effective_agility integer
)
returns integer
language sql
immutable
as $$
  select 1 + floor(greatest(coalesce(p_effective_agility, 0) - 10, 0)::numeric / 5)::integer;
$$;

create or replace function public.odyssey_get_movement_bonus_from_agility(
  p_effective_agility integer
)
returns integer
language sql
immutable
as $$
  select greatest(coalesce(p_effective_agility, 0) - 10, 0);
$$;

create or replace function public.odyssey_get_concentration_slots_from_intelligence(
  p_effective_intelligence integer
)
returns integer
language sql
immutable
as $$
  select 1 + floor(greatest(coalesce(p_effective_intelligence, 0) - 10, 0)::numeric / 5)::integer;
$$;

create or replace function public.odyssey_merge_effect_data(
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
      ((base_data - 'modifiers' - 'flags') || (override_data - 'modifiers' - 'flags')),
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
    '{flags}',
    case
      when jsonb_typeof(base_data->'flags') = 'object'
        or jsonb_typeof(override_data->'flags') = 'object'
        then coalesce(base_data->'flags', '{}'::jsonb) || coalesce(override_data->'flags', '{}'::jsonb)
      else '{}'::jsonb
    end,
    true
  )
  from normalized;
$$;

create or replace function public.get_character_effect_summary(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_active_effects jsonb := '[]'::jsonb;
  v_modifier_rows jsonb := '[]'::jsonb;
  v_attribute_modifiers jsonb := '{}'::jsonb;
  v_skill_modifiers jsonb := '{}'::jsonb;
  v_attack_accuracy integer := 0;
  v_defense integer := 0;
  v_damage integer := 0;
  v_armor integer := 0;
  v_movement_m integer := 0;
  v_action_count integer := 0;
  v_concentration_slots integer := 0;
  v_aim_difficulty integer := 0;
  v_range integer := 0;
  v_skip_main_action boolean := false;
  v_skip_movement boolean := false;
  v_consumes_full_turn boolean := false;
  v_helpless boolean := false;
  v_fatal_on_any_damage_if_unprotected boolean := false;
  v_suppress_movement boolean := false;
  v_cannot_leave_cover boolean := false;
  v_expires_after_attack boolean := false;
  v_expires_after_turn boolean := false;
  v_requires_concentration boolean := false;
begin
  with active_effect_rows as (
    select
      e.id,
      e.character_id,
      e.effect_def_id,
      coalesce(d.code, nullif(e.effect_key, ''), 'custom') as code,
      e.effect_key,
      e.name,
      coalesce(d.category, nullif(e.data->>'category', ''), 'custom') as category,
      e.description,
      e.source,
      coalesce(e.source_type, '') as source_type,
      e.source_id,
      e.source_character_id,
      e.duration_type,
      e.rounds_left,
      e.stacks,
      e.data,
      coalesce(d.stacking_mode, 'stack') as stacking_mode,
      coalesce(d.is_negative, false) as is_negative,
      coalesce(d.is_narrative, false) as is_narrative,
      e.created_by,
      e.created_at,
      e.updated_at
    from public.odyssey_character_effects e
    left join public.odyssey_effect_defs d on d.id = e.effect_def_id
    where e.character_id = p_character_id
      and e.is_active = true
  ),
  modifier_raw as (
    select
      aer.effect_key,
      aer.code,
      aer.category,
      aer.stacking_mode,
      lower(coalesce(modifier.value->>'target', '')) as target,
      nullif(trim(coalesce(modifier.value->>'attribute', '')), '') as attribute_code,
      nullif(trim(coalesce(modifier.value->>'skill_code', modifier.value->>'skill', '')), '') as skill_code,
      coalesce(nullif(trim(coalesce(modifier.value->>'value', '')), '')::integer, 0) as value
    from active_effect_rows aer
    join lateral jsonb_array_elements(
      case
        when jsonb_typeof(aer.data->'modifiers') = 'array' then aer.data->'modifiers'
        else '[]'::jsonb
      end
    ) modifier(value) on true
  ),
  modifier_summary as (
    select
      target,
      attribute_code,
      skill_code,
      array_remove(array_agg(distinct effect_key), null) as effect_keys,
      array_remove(array_agg(distinct code), null) as effect_codes,
      case
        when bool_or(stacking_mode = 'lowest') then min(value)
        when bool_or(stacking_mode = 'highest') then max(value)
        else sum(value)
      end as resolved_value,
      case
        when bool_or(stacking_mode = 'lowest') then 'lowest'
        when bool_or(stacking_mode = 'highest') then 'highest'
        when bool_or(stacking_mode = 'replace') then 'replace'
        when bool_or(stacking_mode = 'unique') then 'unique'
        else 'stack'
      end as aggregation
    from modifier_raw
    where target <> ''
    group by target, attribute_code, skill_code
  ),
  flag_raw as (
    select
      lower(flags.key) as flag_key,
      case
        when jsonb_typeof(flags.value) = 'boolean' then (flags.value #>> '{}')::boolean
        when lower(coalesce(flags.value #>> '{}', 'false')) in ('true', '1', 'yes', 'on') then true
        else false
      end as flag_value
    from active_effect_rows aer
    join lateral jsonb_each(
      case
        when jsonb_typeof(aer.data->'flags') = 'object' then aer.data->'flags'
        else '{}'::jsonb
      end
    ) flags(key, value) on true
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'effect_def_id', effect_def_id,
            'code', code,
            'effect_key', effect_key,
            'name', name,
            'category', category,
            'description', description,
            'source', source,
            'source_type', source_type,
            'source_id', source_id,
            'source_character_id', source_character_id,
            'duration_type', duration_type,
            'rounds_left', rounds_left,
            'stacks', stacks,
            'data', data,
            'is_negative', is_negative,
            'is_narrative', is_narrative,
            'created_by', created_by,
            'created_at', created_at,
            'updated_at', updated_at
          )
          order by created_at desc, id
        )
        from active_effect_rows
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'effect_keys', to_jsonb(effect_keys),
            'effect_codes', to_jsonb(effect_codes),
            'target', target,
            'attribute', attribute_code,
            'skill_code', skill_code,
            'value', resolved_value,
            'aggregation', aggregation
          )
          order by target, attribute_code, skill_code
        )
        from modifier_summary
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_object_agg(attribute_code, resolved_value)
        from modifier_summary
        where target = 'attribute'
          and attribute_code is not null
      ),
      '{}'::jsonb
    ),
    coalesce(
      (
        select jsonb_object_agg(skill_code, resolved_value)
        from modifier_summary
        where target = 'skill'
          and skill_code is not null
      ),
      '{}'::jsonb
    ),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'attack_accuracy'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'defense'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'damage'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'armor'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'movement_m'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'action_count'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'concentration_slots'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'aim_difficulty'), 0),
    coalesce((select sum(resolved_value) from modifier_summary where target = 'range'), 0),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'skip_main_action'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'skip_movement'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'consumes_full_turn'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'helpless'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'fatal_on_any_damage_if_unprotected'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'suppress_movement'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'cannot_leave_cover'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'expires_after_attack'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'expires_after_turn'), false),
    coalesce((select bool_or(flag_value) from flag_raw where flag_key = 'requires_concentration'), false)
  into
    v_active_effects,
    v_modifier_rows,
    v_attribute_modifiers,
    v_skill_modifiers,
    v_attack_accuracy,
    v_defense,
    v_damage,
    v_armor,
    v_movement_m,
    v_action_count,
    v_concentration_slots,
    v_aim_difficulty,
    v_range,
    v_skip_main_action,
    v_skip_movement,
    v_consumes_full_turn,
    v_helpless,
    v_fatal_on_any_damage_if_unprotected,
    v_suppress_movement,
    v_cannot_leave_cover,
    v_expires_after_attack,
    v_expires_after_turn,
    v_requires_concentration;

  return jsonb_build_object(
    'character_id', p_character_id,
    'active_effects', v_active_effects,
    'modifier_rows', v_modifier_rows,
    'modifiers',
      jsonb_build_object(
        'attributes', v_attribute_modifiers,
        'skills', v_skill_modifiers,
        'attack_accuracy', v_attack_accuracy,
        'defense', v_defense,
        'damage', v_damage,
        'armor', v_armor,
        'movement_m', v_movement_m,
        'action_count', v_action_count,
        'concentration_slots', v_concentration_slots,
        'aim_difficulty', v_aim_difficulty,
        'range', v_range
      ),
    'flags',
      jsonb_build_object(
        'helpless', v_helpless,
        'skip_main_action', v_skip_main_action,
        'skip_movement', v_skip_movement,
        'consumes_full_turn', v_consumes_full_turn,
        'fatal_on_any_damage_if_unprotected', v_fatal_on_any_damage_if_unprotected,
        'suppress_movement', v_suppress_movement,
        'cannot_leave_cover', v_cannot_leave_cover,
        'expires_after_attack', v_expires_after_attack,
        'expires_after_turn', v_expires_after_turn,
        'requires_concentration', v_requires_concentration
      )
  );
end;
$$;

create or replace function public.get_effective_character_stats(
  p_character_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_character_exists boolean := false;
  v_effect_summary jsonb := '{}'::jsonb;
  v_attributes jsonb := '[]'::jsonb;
  v_attribute_values jsonb := '{}'::jsonb;
  v_armor_total integer := 0;
  v_armor_class text := 'none';
  v_action_count_modifier integer := 0;
  v_movement_modifier integer := 0;
  v_concentration_modifier integer := 0;
  v_attack_accuracy_modifier integer := 0;
  v_defense_modifier integer := 0;
  v_damage_modifier integer := 0;
  v_armor_modifier integer := 0;
  v_aim_difficulty_modifier integer := 0;
  v_range_modifier integer := 0;
  v_effective_strength integer := 0;
  v_effective_agility integer := 0;
  v_effective_intelligence integer := 0;
  v_main_actions integer := 0;
  v_movement_bonus integer := 0;
  v_movement_available integer := 0;
  v_concentration_slots integer := 0;
  v_helpless boolean := false;
  v_skip_main_action boolean := false;
  v_skip_movement boolean := false;
  v_consumes_full_turn boolean := false;
  v_suppress_movement boolean := false;
  v_cannot_leave_cover boolean := false;
  v_requires_concentration boolean := false;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_has_unconscious_effect boolean := false;
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

  v_effect_summary := public.get_character_effect_summary(p_character_id);

  with attribute_rows as (
    select
      d.code,
      d.name,
      coalesce(a.value, d.default_value, 0) as base_value,
      coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'attributes', d.code), '')::integer, 0) as modifier_value,
      d.max_value,
      d.sort_order
    from public.odyssey_attribute_defs d
    left join public.odyssey_character_attributes a
      on a.attribute_def_id = d.id
     and a.character_id = p_character_id
    order by d.sort_order, d.name
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'code', code,
          'name', name,
          'base_value', base_value,
          'modifier', modifier_value,
          'effective_value', base_value + modifier_value,
          'max_value', max_value,
          'sort_order', sort_order
        )
        order by sort_order, name
      ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_object_agg(code, base_value + modifier_value),
      '{}'::jsonb
    )
  into
    v_attributes,
    v_attribute_values
  from attribute_rows;

  select
    coalesce(sum(case when coalesce(b.armor_destroyed, false) then 0 else coalesce(b.armor_value, 0) end), 0),
    coalesce(bool_or(lower(coalesce(d.code, b.part_key)) in ('head', 'torso') and coalesce(b.destroyed, false)), false)
  into
    v_armor_total,
    v_is_alive
  from public.odyssey_character_body_parts b
  left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
  where b.character_id = p_character_id;

  v_is_alive := not v_is_alive;

  select exists(
    select 1
    from public.odyssey_character_effects e
    left join public.odyssey_effect_defs d on d.id = e.effect_def_id
    where e.character_id = p_character_id
      and e.is_active = true
      and lower(coalesce(d.code, e.effect_key, '')) = 'unconscious'
  )
  into v_has_unconscious_effect;

  v_is_conscious := v_is_alive and not v_has_unconscious_effect;
  v_armor_class := public.odyssey_get_armor_class(v_armor_total);

  v_action_count_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'action_count'), '')::integer, 0);
  v_movement_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'movement_m'), '')::integer, 0);
  v_concentration_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'concentration_slots'), '')::integer, 0);
  v_attack_accuracy_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'attack_accuracy'), '')::integer, 0);
  v_defense_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'defense'), '')::integer, 0);
  v_damage_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'damage'), '')::integer, 0);
  v_armor_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'armor'), '')::integer, 0);
  v_aim_difficulty_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'aim_difficulty'), '')::integer, 0);
  v_range_modifier := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'modifiers', 'range'), '')::integer, 0);

  v_helpless := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'helpless'), '')::boolean, false);
  v_skip_main_action := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'skip_main_action'), '')::boolean, false);
  v_skip_movement := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'skip_movement'), '')::boolean, false);
  v_consumes_full_turn := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'consumes_full_turn'), '')::boolean, false);
  v_suppress_movement := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'suppress_movement'), '')::boolean, false);
  v_cannot_leave_cover := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'cannot_leave_cover'), '')::boolean, false);
  v_requires_concentration := coalesce(nullif(jsonb_extract_path_text(v_effect_summary, 'flags', 'requires_concentration'), '')::boolean, false);

  v_effective_strength := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'strength'), '')::integer, 0);
  v_effective_agility := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'agility'), '')::integer, 0);
  v_effective_intelligence := coalesce(nullif(jsonb_extract_path_text(v_attribute_values, 'intelligence'), '')::integer, 0);

  v_main_actions := greatest(
    public.odyssey_get_main_actions_from_agility(v_effective_agility) + v_action_count_modifier,
    0
  );
  if not v_is_alive or not v_is_conscious or v_skip_main_action or v_consumes_full_turn then
    v_main_actions := 0;
  end if;

  v_movement_bonus := public.odyssey_get_movement_bonus_from_agility(v_effective_agility);
  v_movement_available := greatest(v_movement_bonus + v_movement_modifier, 0);
  if not v_is_alive or not v_is_conscious or v_skip_movement or v_consumes_full_turn then
    v_movement_available := 0;
  end if;

  v_concentration_slots := greatest(
    public.odyssey_get_concentration_slots_from_intelligence(v_effective_intelligence) + v_concentration_modifier,
    0
  );

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'attributes', v_attributes,
    'attribute_values', v_attribute_values,
    'derived',
      jsonb_build_object(
        'base_main_actions', 1,
        'main_actions_per_turn', v_main_actions,
        'action_count_modifier', v_action_count_modifier,
        'movement_bonus_m', v_movement_bonus,
        'movement_modifier_m', v_movement_modifier,
        'movement_available_m', v_movement_available,
        'concentration_slots', v_concentration_slots,
        'concentration_slots_modifier', v_concentration_modifier,
        'armor_total', v_armor_total,
        'armor_class', v_armor_class,
        'attack_accuracy_modifier', v_attack_accuracy_modifier,
        'defense_modifier', v_defense_modifier,
        'damage_modifier', v_damage_modifier,
        'armor_modifier', v_armor_modifier,
        'aim_difficulty_modifier', v_aim_difficulty_modifier,
        'range_modifier', v_range_modifier,
        'helpless', v_helpless,
        'skip_main_action', v_skip_main_action,
        'skip_movement', v_skip_movement,
        'consumes_full_turn', v_consumes_full_turn,
        'suppress_movement', v_suppress_movement,
        'cannot_leave_cover', v_cannot_leave_cover,
        'requires_concentration', v_requires_concentration,
        'is_alive', v_is_alive,
        'is_conscious', v_is_conscious
      ),
    'active_effects', coalesce(v_effect_summary->'active_effects', '[]'::jsonb),
    'effect_summary', v_effect_summary
  );
end;
$$;

create or replace function public.odyssey_refresh_character_combat_state(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_character public.odyssey_characters%rowtype;
  v_existing_state public.odyssey_character_combat_state%rowtype;
  v_rule_sheet jsonb := '{}'::jsonb;
  v_body_summary jsonb := '[]'::jsonb;
  v_armor_parts jsonb := '[]'::jsonb;
  v_armor_summary jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_summary jsonb := '{}'::jsonb;
  v_active_effects jsonb := '[]'::jsonb;
  v_active_penalties jsonb := '[]'::jsonb;
  v_combat_flags jsonb := '{}'::jsonb;
  v_tracker_minor integer := 0;
  v_tracker_serious integer := 0;
  v_is_alive boolean := true;
  v_is_conscious boolean := true;
  v_next_state_version integer := 1;
  v_updated_at timestamptz := timezone('utc', now());
begin
  select *
  into v_character
  from public.odyssey_characters c
  where c.id = p_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'character_id', p_character_id
    );
  end if;

  select *
  into v_existing_state
  from public.odyssey_character_combat_state s
  where s.character_id = p_character_id;

  v_rule_sheet := public.get_character_rule_sheet(p_character_id);
  v_body_summary := coalesce(v_rule_sheet->'body_parts', '[]'::jsonb);
  v_effective_stats := public.get_effective_character_stats(p_character_id);
  v_effect_summary := coalesce(v_effective_stats->'effect_summary', '{}'::jsonb);
  v_active_effects := coalesce(v_effective_stats->'active_effects', '[]'::jsonb);
  v_active_penalties := coalesce(v_effect_summary->'modifier_rows', '[]'::jsonb);

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'part_key', b.part_key,
          'armor_value', b.armor_value,
          'armor_critical', b.armor_critical,
          'armor_max_critical', b.armor_max_critical,
          'armor_destroyed', b.armor_destroyed
        )
        order by b.sort_order, b.part_key
      ),
      '[]'::jsonb
    ),
    coalesce(sum(b.minor), 0),
    coalesce(sum(b.serious), 0)
  into
    v_armor_parts,
    v_tracker_minor,
    v_tracker_serious
  from public.odyssey_character_body_parts b
  where b.character_id = p_character_id;

  v_is_alive := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_alive'), '')::boolean, true);
  v_is_conscious := coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'is_conscious'), '')::boolean, true);

  v_armor_summary := jsonb_build_object(
    'parts', v_armor_parts,
    'total_armor_value', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'armor_total'), '')::integer, 0),
    'armor_class', coalesce(jsonb_extract_path_text(v_effective_stats, 'derived', 'armor_class'), 'none')
  );

  v_combat_flags := jsonb_build_object(
    'helpless', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'helpless'), '')::boolean, false),
    'skip_main_action', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false),
    'skip_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'skip_movement'), '')::boolean, false),
    'consumes_full_turn', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'consumes_full_turn'), '')::boolean, false),
    'suppress_movement', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'suppress_movement'), '')::boolean, false),
    'cannot_leave_cover', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'cannot_leave_cover'), '')::boolean, false),
    'requires_concentration', coalesce(nullif(jsonb_extract_path_text(v_effective_stats, 'derived', 'requires_concentration'), '')::boolean, false)
  );

  v_next_state_version := coalesce(v_existing_state.state_version, 0) + 1;

  insert into public.odyssey_character_combat_state (
    character_id,
    campaign_id,
    room_id,
    body_summary,
    armor_summary,
    active_effects,
    active_penalties,
    effective_stats,
    combat_flags,
    overlay_text,
    overlay_data,
    tracker_minor,
    tracker_serious,
    is_alive,
    is_conscious,
    state_version,
    updated_at
  )
  values (
    p_character_id,
    coalesce(v_character.campaign_id, ''),
    coalesce(v_character.room_id, ''),
    v_body_summary,
    v_armor_summary,
    v_active_effects,
    v_active_penalties,
    v_effective_stats,
    v_combat_flags,
    coalesce(v_existing_state.overlay_text, ''),
    coalesce(v_existing_state.overlay_data, '{}'::jsonb),
    v_tracker_minor,
    v_tracker_serious,
    v_is_alive,
    v_is_conscious,
    v_next_state_version,
    v_updated_at
  )
  on conflict (character_id) do update
  set
    campaign_id = excluded.campaign_id,
    room_id = excluded.room_id,
    body_summary = excluded.body_summary,
    armor_summary = excluded.armor_summary,
    active_effects = excluded.active_effects,
    active_penalties = excluded.active_penalties,
    effective_stats = excluded.effective_stats,
    combat_flags = excluded.combat_flags,
    overlay_text = excluded.overlay_text,
    overlay_data = excluded.overlay_data,
    tracker_minor = excluded.tracker_minor,
    tracker_serious = excluded.tracker_serious,
    is_alive = excluded.is_alive,
    is_conscious = excluded.is_conscious,
    state_version = excluded.state_version,
    updated_at = excluded.updated_at;

  update public.odyssey_characters
  set active_combat_state_version = v_next_state_version
  where id = p_character_id;

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'state_version', v_next_state_version,
    'is_alive', v_is_alive,
    'is_conscious', v_is_conscious,
    'tracker_minor', v_tracker_minor,
    'tracker_serious', v_tracker_serious,
    'combat_state',
      jsonb_build_object(
        'character_id', p_character_id,
        'character_key', v_character.character_key,
        'campaign_id', coalesce(v_character.campaign_id, ''),
        'room_id', coalesce(v_character.room_id, ''),
        'body_summary', v_body_summary,
        'armor_summary', v_armor_summary,
        'active_effects', v_active_effects,
        'active_penalties', v_active_penalties,
        'effective_stats', v_effective_stats,
        'combat_flags', v_combat_flags,
        'overlay_text', coalesce(v_existing_state.overlay_text, ''),
        'overlay_data', coalesce(v_existing_state.overlay_data, '{}'::jsonb),
        'tracker_minor', v_tracker_minor,
        'tracker_serious', v_tracker_serious,
        'is_alive', v_is_alive,
        'is_conscious', v_is_conscious,
        'state_version', v_next_state_version,
        'updated_at', v_updated_at
      )
  );
end;
$$;

create or replace function public.add_character_effect(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_character_id uuid := nullif(trim(coalesce(p_payload->>'character_id', '')), '')::uuid;
  v_effect_code text := lower(trim(coalesce(p_payload->>'effect_code', '')));
  v_effect_key text := trim(coalesce(p_payload->>'effect_key', ''));
  v_name text := trim(coalesce(p_payload->>'name', ''));
  v_description text := coalesce(p_payload->>'description', '');
  v_duration_type text := lower(trim(coalesce(p_payload->>'duration_type', '')));
  v_rounds_left integer := nullif(trim(coalesce(p_payload->>'rounds_left', '')), '')::integer;
  v_source text := coalesce(p_payload->>'source', '');
  v_source_type text := coalesce(p_payload->>'source_type', '');
  v_source_id uuid := nullif(trim(coalesce(p_payload->>'source_id', '')), '')::uuid;
  v_source_character_id uuid := nullif(trim(coalesce(p_payload->>'source_character_id', '')), '')::uuid;
  v_created_by text := trim(coalesce(p_payload->>'created_by', ''));
  v_payload_data jsonb := case when jsonb_typeof(p_payload->'data') = 'object' then p_payload->'data' else '{}'::jsonb end;
  v_payload_category text := lower(trim(coalesce(p_payload->>'category', '')));
  v_stacks integer := greatest(coalesce(nullif(trim(coalesce(p_payload->>'stacks', '')), '')::integer, 1), 1);
  v_effect_def public.odyssey_effect_defs%rowtype;
  v_stacking_mode text := 'stack';
  v_merged_data jsonb := '{}'::jsonb;
  v_existing_effect_id uuid := null;
  v_inserted_id uuid := null;
  v_refresh jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
  v_effect_json jsonb := '{}'::jsonb;
begin
  if v_character_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'CHARACTER_NOT_FOUND',
      'message', 'character_id is required.'
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

  if v_effect_code <> '' then
    select *
    into v_effect_def
    from public.odyssey_effect_defs d
    where d.code = v_effect_code;

    if not found then
      return jsonb_build_object(
        'ok', false,
        'error', 'EFFECT_DEF_NOT_FOUND',
        'effect_code', v_effect_code
      );
    end if;
  end if;

  if v_payload_category <> '' and v_payload_category not in ('buff', 'debuff', 'condition', 'combat', 'psionic', 'equipment', 'weapon', 'armor', 'narrative', 'custom') then
    v_payload_category := 'custom';
  end if;

  if v_effect_def.id is not null then
    v_effect_key := coalesce(nullif(v_effect_key, ''), v_effect_def.code);
    v_name := coalesce(nullif(v_name, ''), v_effect_def.name);
    v_description := coalesce(nullif(v_description, ''), v_effect_def.description);
    v_duration_type := coalesce(nullif(v_duration_type, ''), v_effect_def.default_duration_type);
    if v_rounds_left is null then
      v_rounds_left := v_effect_def.default_rounds;
    end if;
    v_stacking_mode := v_effect_def.stacking_mode;
    v_merged_data := public.odyssey_merge_effect_data(v_effect_def.data, v_payload_data);
  else
    v_stacking_mode := 'stack';
    if v_payload_category = '' then
      v_payload_category := 'custom';
    end if;
    v_merged_data := public.odyssey_merge_effect_data('{}'::jsonb, v_payload_data);
  end if;

  if v_payload_category <> '' then
    v_merged_data := jsonb_set(v_merged_data, '{category}', to_jsonb(v_payload_category), true);
  end if;

  v_duration_type := case v_duration_type
    when 'rounds' then 'rounds'
    when 'until_turn_start' then 'until_turn_start'
    when 'until_turn_end' then 'until_turn_end'
    when 'scene' then 'scene'
    when 'until_used' then 'until_used'
    else 'manual'
  end;

  if v_effect_key = '' then
    v_effect_key := regexp_replace(
      regexp_replace(lower(coalesce(nullif(v_name, ''), 'custom_effect')), '[^a-z0-9]+', '_', 'g'),
      '(^_+|_+$)',
      '',
      'g'
    );
  end if;

  if v_effect_key = '' then
    v_effect_key := 'custom_effect';
  end if;

  if v_name = '' then
    v_name := initcap(replace(v_effect_key, '_', ' '));
  end if;

  if v_stacking_mode in ('replace', 'highest', 'lowest') then
    update public.odyssey_character_effects
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where character_id = v_character_id
      and is_active = true
      and effect_key = v_effect_key;
  elsif v_stacking_mode = 'unique' then
    select e.id
    into v_existing_effect_id
    from public.odyssey_character_effects e
    where e.character_id = v_character_id
      and e.is_active = true
      and e.effect_key = v_effect_key
    order by e.created_at desc, e.id desc
    limit 1;

    if v_existing_effect_id is not null then
      v_effective_stats := public.get_effective_character_stats(v_character_id);
      select jsonb_build_object(
        'id', e.id,
        'effect_def_id', e.effect_def_id,
        'code', coalesce(d.code, e.effect_key),
        'effect_key', e.effect_key,
        'name', e.name,
        'category', coalesce(d.category, nullif(e.data->>'category', ''), 'custom'),
        'description', e.description,
        'source', e.source,
        'source_type', e.source_type,
        'source_id', e.source_id,
        'source_character_id', e.source_character_id,
        'duration_type', e.duration_type,
        'rounds_left', e.rounds_left,
        'stacks', e.stacks,
        'data', e.data,
        'created_by', e.created_by,
        'created_at', e.created_at,
        'updated_at', e.updated_at
      )
      into v_effect_json
      from public.odyssey_character_effects e
      left join public.odyssey_effect_defs d on d.id = e.effect_def_id
      where e.id = v_existing_effect_id;

      return jsonb_build_object(
        'ok', true,
        'created', false,
        'character_id', v_character_id,
        'effect', v_effect_json,
        'effective_stats', v_effective_stats,
        'combat_state',
          coalesce(
            (
              select jsonb_build_object(
                'character_id', s.character_id,
                'campaign_id', s.campaign_id,
                'room_id', s.room_id,
                'body_summary', s.body_summary,
                'armor_summary', s.armor_summary,
                'active_effects', s.active_effects,
                'active_penalties', s.active_penalties,
                'effective_stats', s.effective_stats,
                'combat_flags', s.combat_flags,
                'overlay_text', s.overlay_text,
                'overlay_data', s.overlay_data,
                'tracker_minor', s.tracker_minor,
                'tracker_serious', s.tracker_serious,
                'is_alive', s.is_alive,
                'is_conscious', s.is_conscious,
                'state_version', s.state_version,
                'updated_at', s.updated_at
              )
              from public.odyssey_character_combat_state s
              where s.character_id = v_character_id
            ),
            '{}'::jsonb
          )
      );
    end if;
  end if;

  insert into public.odyssey_character_effects (
    character_id,
    effect_def_id,
    effect_key,
    name,
    description,
    source,
    source_type,
    source_id,
    source_character_id,
    duration_type,
    rounds_left,
    stacks,
    data,
    is_active,
    created_by
  )
  values (
    v_character_id,
    v_effect_def.id,
    v_effect_key,
    v_name,
    v_description,
    v_source,
    v_source_type,
    v_source_id,
    v_source_character_id,
    v_duration_type,
    v_rounds_left,
    v_stacks,
    v_merged_data,
    true,
    v_created_by
  )
  returning id into v_inserted_id;

  v_refresh := public.odyssey_refresh_character_combat_state(v_character_id);
  v_effective_stats := public.get_effective_character_stats(v_character_id);

  select jsonb_build_object(
    'id', e.id,
    'effect_def_id', e.effect_def_id,
    'code', coalesce(d.code, e.effect_key),
    'effect_key', e.effect_key,
    'name', e.name,
    'category', coalesce(d.category, nullif(e.data->>'category', ''), 'custom'),
    'description', e.description,
    'source', e.source,
    'source_type', e.source_type,
    'source_id', e.source_id,
    'source_character_id', e.source_character_id,
    'duration_type', e.duration_type,
    'rounds_left', e.rounds_left,
    'stacks', e.stacks,
    'data', e.data,
    'created_by', e.created_by,
    'created_at', e.created_at,
    'updated_at', e.updated_at
  )
  into v_effect_json
  from public.odyssey_character_effects e
  left join public.odyssey_effect_defs d on d.id = e.effect_def_id
  where e.id = v_inserted_id;

  return jsonb_build_object(
    'ok', true,
    'created', true,
    'character_id', v_character_id,
    'effect', v_effect_json,
    'effective_stats', v_effective_stats,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.remove_character_effect(
  p_effect_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_effect public.odyssey_character_effects%rowtype;
  v_refresh jsonb := '{}'::jsonb;
begin
  select *
  into v_effect
  from public.odyssey_character_effects e
  where e.id = p_effect_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'EFFECT_NOT_FOUND',
      'effect_id', p_effect_id
    );
  end if;

  update public.odyssey_character_effects
  set
    is_active = false,
    updated_at = timezone('utc', now())
  where id = p_effect_id;

  v_refresh := public.odyssey_refresh_character_combat_state(v_effect.character_id);

  return jsonb_build_object(
    'ok', true,
    'effect_id', p_effect_id,
    'character_id', v_effect.character_id,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
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
  v_refresh jsonb := '{}'::jsonb;
  v_effective_stats jsonb := '{}'::jsonb;
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
          'rounds_left', u.rounds_left
        )
        order by u.updated_at desc, u.id
      ) filter (where u.is_active = false),
      '[]'::jsonb
    )
  into
    v_changed_effects,
    v_expired_effects
  from updated_effects u;

  v_refresh := public.odyssey_refresh_character_combat_state(p_character_id);
  v_effective_stats := public.get_effective_character_stats(p_character_id);

  return jsonb_build_object(
    'ok', true,
    'character_id', p_character_id,
    'changed_effects', v_changed_effects,
    'expired_effects', v_expired_effects,
    'effective_stats', v_effective_stats,
    'combat_state', coalesce(v_refresh->'combat_state', '{}'::jsonb)
  );
end;
$$;

create or replace function public.odyssey_expire_attack_effects_after_attack(
  p_character_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_expired jsonb := '[]'::jsonb;
begin
  with expired_rows as (
    update public.odyssey_character_effects e
    set
      is_active = false,
      updated_at = timezone('utc', now())
    where e.character_id = p_character_id
      and e.is_active = true
      and coalesce(nullif(e.data#>>'{flags,expires_after_attack}', '')::boolean, false)
    returning e.*
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'effect_key', e.effect_key,
          'name', e.name,
          'code', coalesce(d.code, e.effect_key)
        )
        order by e.updated_at desc, e.id
      ),
      '[]'::jsonb
    )
  into v_expired
  from expired_rows e
  left join public.odyssey_effect_defs d on d.id = e.effect_def_id;

  return v_expired;
end;
$$;

create or replace function public.perform_attack(
  p_payload jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_attacker_character_id uuid := nullif(trim(coalesce(p_payload->>'attacker_character_id', '')), '')::uuid;
  v_target_character_id uuid := nullif(trim(coalesce(p_payload->>'target_character_id', '')), '')::uuid;
  v_weapon_id uuid := nullif(trim(coalesce(p_payload->>'weapon_id', '')), '')::uuid;
  v_target_body_part_id uuid := nullif(trim(coalesce(p_payload->>'target_body_part_id', '')), '')::uuid;
  v_defense_skill_id uuid := nullif(trim(coalesce(p_payload->>'defense_skill_id', '')), '')::uuid;
  v_encounter_id uuid := nullif(trim(coalesce(p_payload->>'encounter_id', '')), '')::uuid;
  v_distance_m numeric := greatest(coalesce(nullif(trim(coalesce(p_payload->>'distance_m', '')), '')::numeric, 0), 0);
  v_room_id text := coalesce(nullif(trim(coalesce(p_payload->>'room_id', '')), ''), '');
  v_campaign_id text := coalesce(nullif(trim(coalesce(p_payload->>'campaign_id', '')), ''), '');
  v_scene_id text := coalesce(nullif(trim(coalesce(p_payload->>'scene_id', '')), ''), '');
  v_actor_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'actor_token_id', '')), ''), '');
  v_target_token_id text := coalesce(nullif(trim(coalesce(p_payload->>'target_token_id', '')), ''), '');
  v_manual_attack_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_bonus}', '')), '')::integer, 0);
  v_manual_attack_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{attack_context,manual_attack_penalty}', '')), '')::integer, 0);
  v_manual_defense_bonus integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_bonus}', '')), '')::integer, 0);
  v_manual_defense_penalty integer := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,manual_defense_penalty}', '')), '')::integer, 0);
  v_hostile_adjacent_count integer := greatest(coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,hostile_adjacent_count}', '')), '')::integer, 1), 1);
  v_ignore_defense_skill boolean := coalesce(nullif(trim(coalesce(p_payload#>>'{defense_context,ignore_defense_skill}', '')), '')::boolean, false);
  v_override_ignore_action_restrictions boolean := coalesce(nullif(trim(coalesce(p_payload#>>'{override,ignore_action_restrictions}', '')), '')::boolean, false);
  v_attacker public.odyssey_characters%rowtype;
  v_target public.odyssey_characters%rowtype;
  v_weapon public.odyssey_character_weapons%rowtype;
  v_weapon_model record;
  v_fire_mode record;
  v_target_part record;
  v_attacker_effective_stats jsonb := '{}'::jsonb;
  v_target_effective_stats jsonb := '{}'::jsonb;
  v_attacker_effect_summary jsonb := '{}'::jsonb;
  v_target_effect_summary jsonb := '{}'::jsonb;
  v_attacker_is_alive boolean := true;
  v_attacker_is_conscious boolean := true;
  v_attacker_helpless boolean := false;
  v_attacker_skip_main_action boolean := false;
  v_target_helpless boolean := false;
  v_target_armor_total integer := 0;
  v_target_armor_class text := 'none';
  v_target_helpless_source jsonb := '[]'::jsonb;
  v_attack_skill_level integer := 0;
  v_attack_skill_modifier integer := 0;
  v_attack_skill_bonus integer := 0;
  v_attack_roll integer := 0;
  v_defense_roll integer := 0;
  v_attack_total integer := 0;
  v_defense_total integer := 0;
  v_defense_skill_level integer := 0;
  v_defense_skill_modifier integer := 0;
  v_effective_defense_skill_level integer := 0;
  v_defense_skill_source text := 'none_for_ranged';
  v_defense_skill_code text := '';
  v_range_json jsonb := '{}'::jsonb;
  v_range_band text := null;
  v_range_modifier integer := 0;
  v_attack_type text := null;
  v_magazine record;
  v_magazine_id uuid := null;
  v_ammo_code text := null;
  v_bullets_spent integer := 0;
  v_remaining_rounds integer := null;
  v_bullet_damage integer := 0;
  v_total_weapon_damage integer := 0;
  v_melee_strength_bonus integer := 0;
  v_strength_value integer := 0;
  v_ammo_accuracy_modifier integer := 0;
  v_ammo_damage_modifier integer := 0;
  v_armor_pierce integer := 0;
  v_attacker_attack_accuracy_modifier integer := 0;
  v_attacker_damage_modifier integer := 0;
  v_attacker_aim_difficulty_modifier integer := 0;
  v_attacker_range_effect_modifier integer := 0;
  v_target_defense_modifier integer := 0;
  v_target_armor_modifier integer := 0;
  v_helpless_defense_penalty integer := 0;
  v_effective_aim_difficulty integer := 0;
  v_raw_armor_value integer := 0;
  v_effective_armor integer := 0;
  v_hit boolean := false;
  v_hit_source text := 'normal';
  v_damage_attack_total integer := null;
  v_damage_defense_total integer := null;
  v_damage_diff integer := null;
  v_minor_delta integer := 0;
  v_serious_delta integer := 0;
  v_critical_delta integer := 0;
  v_armor_critical_delta integer := 0;
  v_body_critical_delta integer := 0;
  v_damage_level text := 'no_damage';
  v_new_minor integer := 0;
  v_new_serious integer := 0;
  v_new_critical integer := 0;
  v_new_armor_critical integer := 0;
  v_new_armor_value integer := 0;
  v_new_disabled boolean := false;
  v_new_destroyed boolean := false;
  v_new_armor_destroyed boolean := false;
  v_body_changed boolean := false;
  v_target_state jsonb := '{}'::jsonb;
  v_attacker_state jsonb := '{}'::jsonb;
  v_expired_attack_effects jsonb := '[]'::jsonb;
  v_message text := '';
  v_error_code text := null;
  v_error_message text := null;
  v_result jsonb := '{}'::jsonb;
  v_log_data jsonb := '{}'::jsonb;
  v_log_id uuid := null;
  v_created_by text := '';
  v_execution_info jsonb := '{}'::jsonb;
begin
  v_created_by := coalesce(v_actor_token_id, '');

  select *
  into v_attacker
  from public.odyssey_characters c
  where c.id = v_attacker_character_id
    and coalesce(c.is_deleted, false) = false;

  if not found then
    v_error_code := 'CHARACTER_NOT_FOUND';
    v_error_message := 'Attacker character was not found.';
  end if;

  if v_error_code is null then
    select *
    into v_target
    from public.odyssey_characters c
    where c.id = v_target_character_id
      and coalesce(c.is_deleted, false) = false;

    if not found then
      v_error_code := 'TARGET_NOT_FOUND';
      v_error_message := 'Target character was not found.';
    end if;
  end if;

  if v_error_code is null then
    select *
    into v_weapon
    from public.odyssey_character_weapons w
    where w.id = v_weapon_id
      and w.character_id = v_attacker_character_id;

    if not found then
      v_error_code := 'WEAPON_NOT_FOUND';
      v_error_message := 'Weapon was not found for the attacker.';
    end if;
  end if;

  if v_error_code is null then
    select
      wm.id,
      wm.code,
      wm.name,
      wm.weapon_class_id,
      wc.code as weapon_class_code,
      wc.name as weapon_class_name,
      wm.linked_skill_id,
      skill.code as linked_skill_code,
      skill.name as linked_skill_name,
      wm.caliber_id,
      caliber.code as caliber_code,
      caliber.name as caliber_name,
      caliber.base_damage_per_round,
      wm.range_profile_id,
      rp.code as range_profile_code,
      rp.name as range_profile_name,
      wm.base_accuracy_bonus,
      wm.base_melee_damage
    into v_weapon_model
    from public.odyssey_weapon_model_defs wm
    join public.odyssey_weapon_class_defs wc on wc.id = wm.weapon_class_id
    join public.odyssey_skill_defs skill on skill.id = wm.linked_skill_id
    left join public.odyssey_caliber_defs caliber on caliber.id = wm.caliber_id
    join public.odyssey_range_profile_defs rp on rp.id = wm.range_profile_id
    where wm.id = v_weapon.weapon_model_id;

    if not found then
      v_error_code := 'INVALID_WEAPON_MODEL';
      v_error_message := 'Weapon model linked to the weapon was not found.';
    end if;
  end if;

  if v_error_code is null then
    if v_weapon.selected_fire_mode_id is not null then
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.fire_mode_id = v_weapon.selected_fire_mode_id
      limit 1;
    else
      select
        fm.id,
        fm.code,
        fm.name,
        fm.fixed_rounds,
        fm.min_rounds,
        fm.max_rounds,
        fm.is_random,
        fm.accuracy_modifier
      into v_fire_mode
      from public.odyssey_weapon_model_fire_modes wmfm
      join public.odyssey_fire_mode_defs fm on fm.id = wmfm.fire_mode_id
      where wmfm.weapon_model_id = v_weapon.weapon_model_id
        and wmfm.is_default = true
      order by wmfm.created_at
      limit 1;
    end if;

    if not found then
      v_error_code := 'INVALID_FIRE_MODE';
      v_error_message := 'Weapon fire mode is missing or not allowed for this model.';
    end if;
  end if;

  if v_error_code is null then
    select
      b.id,
      b.character_id,
      b.body_part_def_id,
      b.custom_name,
      b.part_key,
      b.minor,
      b.serious,
      b.critical,
      b.max_critical,
      b.armor_value,
      b.armor_critical,
      b.armor_max_critical,
      b.armor_destroyed,
      b.disabled,
      b.destroyed,
      coalesce(d.code, b.part_key) as part_code,
      coalesce(nullif(trim(b.custom_name), ''), d.name, b.part_key) as part_name,
      coalesce(d.can_be_targeted, true) as can_be_targeted,
      coalesce(d.aim_difficulty, 0) as aim_difficulty
    into v_target_part
    from public.odyssey_character_body_parts b
    left join public.odyssey_body_part_defs d on d.id = b.body_part_def_id
    where b.id = v_target_body_part_id
      and b.character_id = v_target_character_id;

    if not found or not coalesce(v_target_part.can_be_targeted, true) then
      v_error_code := 'BODY_PART_NOT_FOUND';
      v_error_message := 'Target body part was not found or cannot be targeted.';
    end if;
  end if;

  if coalesce(v_campaign_id, '') = '' then
    v_campaign_id := coalesce(v_attacker.campaign_id, '');
  end if;

  if coalesce(v_room_id, '') = '' then
    v_room_id := coalesce(v_attacker.room_id, '');
  end if;

  if v_error_code is null then
    v_attacker_effective_stats := public.get_effective_character_stats(v_attacker_character_id);
    v_target_effective_stats := public.get_effective_character_stats(v_target_character_id);
    v_attacker_effect_summary := coalesce(v_attacker_effective_stats->'effect_summary', '{}'::jsonb);
    v_target_effect_summary := coalesce(v_target_effective_stats->'effect_summary', '{}'::jsonb);

    v_attacker_is_alive := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_alive'), '')::boolean, true);
    v_attacker_is_conscious := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'is_conscious'), '')::boolean, true);
    v_attacker_helpless := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'helpless'), '')::boolean, false);
    v_attacker_skip_main_action := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'skip_main_action'), '')::boolean, false);

    if not v_override_ignore_action_restrictions
      and (
        not v_attacker_is_alive
        or not v_attacker_is_conscious
        or v_attacker_helpless
        or v_attacker_skip_main_action
      ) then
      v_error_code := 'ATTACKER_CANNOT_ACT';
      v_error_message := 'Attacker cannot act because of current effects or combat state.';
    end if;
  end if;

  if v_error_code is null then
    v_target_helpless := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'helpless'), '')::boolean, false);
    v_target_armor_total := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'armor_total'), '')::integer, 0);
    v_target_armor_class := coalesce(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'armor_class'), 'none');

    select
      coalesce(
        jsonb_agg(coalesce(entry->>'code', entry->>'effect_key'))
          filter (
            where lower(coalesce(entry->'data'->'flags'->>'helpless', 'false')) in ('true', '1', 'yes', 'on')
          ),
        '[]'::jsonb
      )
    into v_target_helpless_source
    from jsonb_array_elements(coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb)) entry;
  end if;

  if v_error_code is null then
    v_attack_type := case when v_weapon_model.caliber_id is null then 'melee' else 'ranged' end;

    select coalesce(s.level, 0)
    into v_attack_skill_level
    from public.odyssey_skill_defs d
    left join public.odyssey_character_skills s
      on s.skill_def_id = d.id
     and s.character_id = v_attacker_character_id
    where d.id = v_weapon_model.linked_skill_id;

    v_attack_skill_modifier := coalesce(
      nullif(jsonb_extract_path_text(v_attacker_effect_summary, 'modifiers', 'skills', v_weapon_model.linked_skill_code), '')::integer,
      0
    );
    v_attack_skill_level := coalesce(v_attack_skill_level, 0) + v_attack_skill_modifier;
    if v_attack_skill_level < 0 then
      v_attack_skill_level := 0;
    end if;
    v_attack_skill_bonus := v_attack_skill_level * 10;

    v_attacker_attack_accuracy_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'attack_accuracy_modifier'), '')::integer, 0);
    v_attacker_damage_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'damage_modifier'), '')::integer, 0);
    v_attacker_aim_difficulty_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'aim_difficulty_modifier'), '')::integer, 0);
    v_attacker_range_effect_modifier := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'derived', 'range_modifier'), '')::integer, 0);
    v_target_defense_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'defense_modifier'), '')::integer, 0);
    v_target_armor_modifier := coalesce(nullif(jsonb_extract_path_text(v_target_effective_stats, 'derived', 'armor_modifier'), '')::integer, 0);
  end if;

  if v_error_code is null then
    v_range_json := public.get_weapon_range_modifier(v_weapon_model.id, v_distance_m);
    v_range_band := nullif(coalesce(v_range_json->>'range_band', ''), '');
    v_range_modifier := coalesce((v_range_json->>'modifier')::integer, 0) + v_attacker_range_effect_modifier;
  end if;

  if v_error_code is null and v_attack_type = 'ranged' then
    if v_weapon.loaded_magazine_id is null then
      v_error_code := 'NO_MAGAZINE';
      v_error_message := 'Weapon requires a loaded magazine.';
    else
      select
        cm.id,
        cm.character_id,
        cm.magazine_def_id,
        cm.ammo_type_id,
        cm.current_rounds,
        md.code as magazine_def_code,
        md.name as magazine_def_name,
        md.capacity,
        md.caliber_id as magazine_caliber_id,
        caliber.code as magazine_caliber_code,
        ammo.code as ammo_code,
        ammo.name as ammo_name,
        ammo.caliber_id as ammo_caliber_id,
        ammo.damage_modifier,
        ammo.accuracy_modifier,
        ammo.armor_pierce
      into v_magazine
      from public.odyssey_character_magazines cm
      join public.odyssey_magazine_defs md on md.id = cm.magazine_def_id
      join public.odyssey_caliber_defs caliber on caliber.id = md.caliber_id
      join public.odyssey_ammo_type_defs ammo on ammo.id = cm.ammo_type_id
      where cm.id = v_weapon.loaded_magazine_id
        and cm.character_id = v_attacker_character_id;

      if not found then
        v_error_code := 'INVALID_MAGAZINE';
        v_error_message := 'Loaded magazine was not found or does not belong to the attacker.';
      else
        v_magazine_id := v_magazine.id;
        v_ammo_code := v_magazine.ammo_code;
      end if;

      if v_error_code is null then
        if v_magazine.magazine_caliber_id <> v_weapon_model.caliber_id
          or v_magazine.ammo_caliber_id <> v_magazine.magazine_caliber_id
          or not exists (
            select 1
            from public.odyssey_weapon_model_magazines wmm
            where wmm.weapon_model_id = v_weapon.weapon_model_id
              and wmm.magazine_def_id = v_magazine.magazine_def_id
          ) then
          v_error_code := 'INVALID_MAGAZINE';
          v_error_message := 'Loaded magazine is incompatible with the weapon model.';
        elsif coalesce(v_magazine.current_rounds, 0) <= 0 then
          v_error_code := 'NO_AMMO';
          v_error_message := 'Loaded magazine is empty.';
        else
          if coalesce(v_fire_mode.is_random, false) then
            if v_magazine.current_rounds >= coalesce(v_fire_mode.min_rounds, 1) then
              v_bullets_spent :=
                floor(
                  random()
                  * (
                      least(
                        coalesce(v_fire_mode.max_rounds, v_magazine.current_rounds),
                        v_magazine.current_rounds
                      )
                      - coalesce(v_fire_mode.min_rounds, 1)
                      + 1
                    )
                )::integer + coalesce(v_fire_mode.min_rounds, 1);
            else
              v_bullets_spent := v_magazine.current_rounds;
            end if;
          else
            v_bullets_spent := least(coalesce(v_fire_mode.fixed_rounds, 0), v_magazine.current_rounds);
          end if;

          if v_bullets_spent <= 0 then
            v_error_code := 'NO_AMMO';
            v_error_message := 'Attack cannot be made because there is no ammunition to spend.';
          else
            v_ammo_accuracy_modifier := coalesce(v_magazine.accuracy_modifier, 0);
            v_ammo_damage_modifier := coalesce(v_magazine.damage_modifier, 0);
            v_armor_pierce := coalesce(v_magazine.armor_pierce, 0);
            v_bullet_damage := greatest(coalesce(v_weapon_model.base_damage_per_round, 0) + v_ammo_damage_modifier, 0);
            v_total_weapon_damage := v_bullet_damage * v_bullets_spent;
            v_remaining_rounds := v_magazine.current_rounds - v_bullets_spent;
          end if;
        end if;
      end if;
    end if;
  elsif v_error_code is null then
    v_strength_value := coalesce(nullif(jsonb_extract_path_text(v_attacker_effective_stats, 'attribute_values', 'strength'), '')::integer, 0);
    v_melee_strength_bonus := greatest(v_strength_value - 10, 0);
    v_total_weapon_damage := coalesce(v_weapon_model.base_melee_damage, 0) + v_melee_strength_bonus;
    v_bullet_damage := 0;
    v_ammo_accuracy_modifier := 0;
    v_ammo_damage_modifier := 0;
    v_armor_pierce := 0;
    v_magazine_id := null;
    v_ammo_code := null;
    v_remaining_rounds := null;
  end if;

  if v_error_code is null then
    v_total_weapon_damage := greatest(v_total_weapon_damage + v_attacker_damage_modifier, 0);
  end if;

  if v_error_code is null then
    if v_target_helpless then
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'helpless';
      v_defense_skill_code := '';
    elsif v_ignore_defense_skill then
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'ignored';
      v_defense_skill_code := '';
    elsif v_defense_skill_id is not null then
      select
        d.code,
        coalesce(s.level, 0)
      into
        v_defense_skill_code,
        v_defense_skill_level
      from public.odyssey_skill_defs d
      left join public.odyssey_character_skills s
        on s.skill_def_id = d.id
       and s.character_id = v_target_character_id
      where d.id = v_defense_skill_id;

      v_defense_skill_modifier := coalesce(
        nullif(jsonb_extract_path_text(v_target_effect_summary, 'modifiers', 'skills', coalesce(v_defense_skill_code, '')), '')::integer,
        0
      );
      v_defense_skill_level := greatest(coalesce(v_defense_skill_level, 0) + v_defense_skill_modifier, 0);
      v_effective_defense_skill_level := v_defense_skill_level;
      v_defense_skill_source := 'payload';
    elsif v_attack_type = 'melee' then
      v_defense_skill_code := 'parry';
      select coalesce(s.level, 0)
      into v_defense_skill_level
      from public.odyssey_skill_defs d
      left join public.odyssey_character_skills s
        on s.skill_def_id = d.id
       and s.character_id = v_target_character_id
      where d.code = 'parry';

      v_defense_skill_modifier := coalesce(
        nullif(jsonb_extract_path_text(v_target_effect_summary, 'modifiers', 'skills', 'parry'), '')::integer,
        0
      );
      v_defense_skill_level := greatest(coalesce(v_defense_skill_level, 0) + v_defense_skill_modifier, 0);
      v_effective_defense_skill_level := floor(v_defense_skill_level::numeric / v_hostile_adjacent_count)::integer;
      if v_defense_skill_level > 0 and v_effective_defense_skill_level < 1 then
        v_effective_defense_skill_level := 1;
      end if;
      v_defense_skill_source := 'fallback_parry';
    else
      v_defense_skill_level := 0;
      v_effective_defense_skill_level := 0;
      v_defense_skill_source := 'none_for_ranged';
      v_defense_skill_code := '';
    end if;
  end if;

  if v_error_code is null then
    v_raw_armor_value := greatest(
      case
        when coalesce(v_target_part.armor_destroyed, false) then 0
        else coalesce(v_target_part.armor_value, 0)
      end
      + v_target_armor_modifier,
      0
    );

    if v_attack_type = 'ranged' then
      v_effective_armor := greatest(v_raw_armor_value - v_armor_pierce, 0);
    else
      v_effective_armor := v_raw_armor_value;
    end if;

    v_attack_roll := floor(random() * 100)::integer + 1;
    if v_target_helpless and v_target_armor_class in ('none', 'light') then
      v_defense_roll := 1;
      v_hit_source := 'helpless_defense_roll_1';
    else
      v_defense_roll := floor(random() * 100)::integer + 1;
      if v_target_helpless and v_target_armor_class in ('medium', 'heavy', 'superheavy') then
        v_helpless_defense_penalty := -60;
        v_hit_source := 'helpless_defense_penalty_60';
      end if;
    end if;

    v_effective_aim_difficulty := greatest(coalesce(v_target_part.aim_difficulty, 0) - v_attacker_aim_difficulty_modifier, 0);

    v_attack_total :=
      v_attack_roll
      + v_attack_skill_bonus
      + coalesce(v_weapon_model.base_accuracy_bonus, 0)
      + v_ammo_accuracy_modifier
      + coalesce(v_fire_mode.accuracy_modifier, 0)
      + coalesce(v_range_modifier, 0)
      + v_attacker_attack_accuracy_modifier
      - v_effective_aim_difficulty
      + v_manual_attack_bonus
      - v_manual_attack_penalty;

    v_defense_total :=
      v_defense_roll
      + (v_effective_defense_skill_level * 10)
      + v_target_defense_modifier
      + v_helpless_defense_penalty
      + v_manual_defense_bonus
      - v_manual_defense_penalty;

    if v_attack_type = 'ranged' then
      update public.odyssey_character_magazines
      set current_rounds = v_remaining_rounds
      where id = v_magazine_id;
    end if;

    v_hit := v_attack_total > v_defense_total;
  end if;

  if v_error_code is null and v_hit then
    v_damage_attack_total := v_attack_total + v_total_weapon_damage;
    v_damage_defense_total := v_defense_total + v_effective_armor;
    v_damage_diff := v_damage_attack_total - v_damage_defense_total;

    if v_damage_diff > 90 then
      v_critical_delta := 3;
      v_damage_level := 'critical';
    elsif v_damage_diff > 60 then
      v_critical_delta := 2;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 31 then
      v_critical_delta := 1;
      v_damage_level := 'critical';
    elsif v_damage_diff >= 6 then
      v_serious_delta := 1;
      v_damage_level := 'serious';
    elsif v_damage_diff > 0 then
      v_minor_delta := 1;
      v_damage_level := 'minor';
    else
      v_damage_level := 'no_damage';
    end if;

    v_new_minor := coalesce(v_target_part.minor, 0) + v_minor_delta;
    v_new_serious := coalesce(v_target_part.serious, 0) + v_serious_delta;
    v_new_critical := coalesce(v_target_part.critical, 0);
    v_new_armor_critical := coalesce(v_target_part.armor_critical, 0);
    v_new_armor_value := coalesce(v_target_part.armor_value, 0);
    v_new_disabled := coalesce(v_target_part.disabled, false);
    v_new_destroyed := coalesce(v_target_part.destroyed, false);
    v_new_armor_destroyed := coalesce(v_target_part.armor_destroyed, false);

    if v_critical_delta > 0 then
      if coalesce(v_target_part.armor_value, 0) > 0
        and not coalesce(v_target_part.armor_destroyed, false)
        and coalesce(v_target_part.armor_max_critical, 0) > 0 then
        v_armor_critical_delta := least(
          v_critical_delta,
          greatest(coalesce(v_target_part.armor_max_critical, 0) - coalesce(v_target_part.armor_critical, 0), 0)
        );
        v_new_armor_critical := coalesce(v_target_part.armor_critical, 0) + v_armor_critical_delta;
        v_body_critical_delta := v_critical_delta - v_armor_critical_delta;

        if v_new_armor_critical >= coalesce(v_target_part.armor_max_critical, 0)
          and coalesce(v_target_part.armor_max_critical, 0) > 0 then
          v_new_armor_destroyed := true;
          v_new_armor_value := 0;
        end if;
      else
        v_body_critical_delta := v_critical_delta;
      end if;

      if v_body_critical_delta > 0 then
        v_new_critical := coalesce(v_target_part.critical, 0) + v_body_critical_delta;
        v_new_disabled := true;
        if v_new_critical >= coalesce(v_target_part.max_critical, 0) then
          v_new_destroyed := true;
          v_new_disabled := true;
        end if;
      end if;
    end if;

    if v_minor_delta > 0
      or v_serious_delta > 0
      or v_critical_delta > 0 then
      update public.odyssey_character_body_parts
      set
        minor = v_new_minor,
        serious = v_new_serious,
        critical = v_new_critical,
        armor_critical = v_new_armor_critical,
        armor_value = v_new_armor_value,
        armor_destroyed = v_new_armor_destroyed,
        disabled = v_new_disabled,
        destroyed = v_new_destroyed
      where id = v_target_part.id;

      v_body_changed := true;
    end if;
  end if;

  if v_body_changed then
    v_target_state := coalesce(public.odyssey_refresh_character_combat_state(v_target_character_id)->'combat_state', '{}'::jsonb);
  end if;

  if v_error_code is null then
    v_expired_attack_effects := public.odyssey_expire_attack_effects_after_attack(v_attacker_character_id);
    if jsonb_array_length(coalesce(v_expired_attack_effects, '[]'::jsonb)) > 0 then
      v_attacker_state := coalesce(public.odyssey_refresh_character_combat_state(v_attacker_character_id)->'combat_state', '{}'::jsonb);
    end if;
  end if;

  if v_error_code is not null then
    v_log_data := jsonb_build_object(
      'type', 'attack',
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'attacker_character_id', v_attacker_character_id,
      'target_character_id', v_target_character_id,
      'weapon_id', v_weapon_id,
      'target_body_part_id', v_target_body_part_id,
      'distance_m', v_distance_m,
      'actor_token_id', v_actor_token_id,
      'target_token_id', v_target_token_id
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
      coalesce(v_campaign_id, ''),
      coalesce(v_room_id, ''),
      coalesce(v_scene_id, ''),
      v_encounter_id,
      v_attacker_character_id,
      v_target_character_id,
      'attack',
      v_error_message,
      v_log_data,
      v_created_by
    )
    returning id into v_log_id;

    perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

    return jsonb_build_object(
      'ok', false,
      'error', v_error_code,
      'message', v_error_message,
      'log_id', v_log_id
    );
  end if;

  if not v_hit then
    v_message := format(
      '%s attacks %s with %s and misses.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  elsif v_damage_level = 'no_damage' then
    v_message := format(
      '%s hits %s in %s with %s but deals no damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name)
    );
  else
    v_message := format(
      '%s hits %s in %s with %s for %s damage.',
      coalesce(nullif(trim(v_attacker.resources->>'name'), ''), v_attacker.character_key),
      coalesce(nullif(trim(v_target.resources->>'name'), ''), v_target.character_key),
      v_target_part.part_name,
      coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
      v_damage_level
    );
  end if;

  v_execution_info := jsonb_build_object(
    'auto_hit', false,
    'hit_source', v_hit_source,
    'fatal_on_any_damage', false,
    'fatal_triggered', false,
    'special_rule',
      case
        when v_hit_source = 'helpless_defense_roll_1' then 'helpless_defense_roll_1'
        when v_hit_source = 'helpless_defense_penalty_60' then 'helpless_defense_penalty_60'
        else 'normal'
      end,
    'expired_effects_after_attack', v_expired_attack_effects
  );

  v_log_data := jsonb_build_object(
    'type', 'attack',
    'ok', true,
    'hit', v_hit,
    'hit_source', v_hit_source,
    'attack_type', v_attack_type,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon_id', v_weapon_id,
    'weapon_model_id', v_weapon_model.id,
    'weapon_name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
    'target_body_part_id', v_target_body_part_id,
    'target_body_part_name', v_target_part.part_name,
    'distance_m', v_distance_m,
    'range_band', v_range_band,
    'range_modifier', v_range_modifier,
    'attack_roll', v_attack_roll,
    'attack_skill_level', v_attack_skill_level,
    'attack_total', v_attack_total,
    'defense_roll', v_defense_roll,
    'defense_skill_level', v_defense_skill_level,
    'effective_defense_skill_level', v_effective_defense_skill_level,
    'defense_skill_source', v_defense_skill_source,
    'defense_total', v_defense_total,
    'fire_mode', v_fire_mode.code,
    'bullets_spent', v_bullets_spent,
    'melee_strength_bonus', v_melee_strength_bonus,
    'damage_level', v_damage_level,
    'damage_diff', v_damage_diff,
    'minor_delta', v_minor_delta,
    'serious_delta', v_serious_delta,
    'critical_delta', v_critical_delta,
    'armor_critical_delta', v_armor_critical_delta,
    'remaining_magazine_rounds', v_remaining_rounds,
    'effects',
      jsonb_build_object(
        'attacker',
          jsonb_build_object(
            'active_effects', coalesce(v_attacker_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_attacker_effect_summary->'modifiers', '{}'::jsonb)
          ),
        'target',
          jsonb_build_object(
            'active_effects', coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_target_effect_summary->'modifiers', '{}'::jsonb),
            'flags', coalesce(v_target_effect_summary->'flags', '{}'::jsonb),
            'helpless_source', v_target_helpless_source
          )
      ),
    'armor_summary',
      jsonb_build_object(
        'total_armor_value', v_target_armor_total,
        'armor_class', v_target_armor_class,
        'helpless_execution_protected', v_target_armor_class not in ('none', 'light')
      ),
    'execution', v_execution_info
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
    coalesce(v_campaign_id, ''),
    coalesce(v_room_id, ''),
    coalesce(v_scene_id, ''),
    v_encounter_id,
    v_attacker_character_id,
    v_target_character_id,
    'attack',
    v_message,
    v_log_data,
    v_created_by
  )
  returning id into v_log_id;

  perform public.odyssey_trim_combat_log(v_encounter_id, v_room_id);

  select jsonb_build_object(
    'ok', true,
    'hit', v_hit,
    'attack_type', v_attack_type,
    'attacker_character_id', v_attacker_character_id,
    'target_character_id', v_target_character_id,
    'weapon',
      jsonb_build_object(
        'id', v_weapon_id,
        'model_id', v_weapon_model.id,
        'name', coalesce(nullif(trim(v_weapon.custom_name), ''), v_weapon_model.name),
        'base_accuracy_bonus', v_weapon_model.base_accuracy_bonus,
        'base_melee_damage', v_weapon_model.base_melee_damage
      ),
    'fire_mode',
      jsonb_build_object(
        'id', v_fire_mode.id,
        'code', v_fire_mode.code,
        'accuracy_modifier', v_fire_mode.accuracy_modifier
      ),
    'ammo',
      jsonb_build_object(
        'caliber', v_weapon_model.caliber_code,
        'ammo_type', case when v_attack_type = 'ranged' then v_ammo_code else null end,
        'bullet_damage', v_bullet_damage,
        'damage_modifier', v_ammo_damage_modifier,
        'accuracy_modifier', v_ammo_accuracy_modifier,
        'armor_pierce', v_armor_pierce
      ),
    'range',
      jsonb_build_object(
        'distance_m', v_distance_m,
        'band', v_range_band,
        'modifier', v_range_modifier
      ),
    'attack',
      jsonb_build_object(
        'roll', v_attack_roll,
        'skill_level', v_attack_skill_level,
        'skill_bonus', v_attack_skill_bonus,
        'manual_bonus', v_manual_attack_bonus,
        'manual_penalty', v_manual_attack_penalty,
        'total', v_attack_total
      ),
    'defense',
      jsonb_build_object(
        'roll', v_defense_roll,
        'skill_level', v_defense_skill_level,
        'effective_skill_level', v_effective_defense_skill_level,
        'skill_source', v_defense_skill_source,
        'hostile_adjacent_count', v_hostile_adjacent_count,
        'manual_bonus', v_manual_defense_bonus,
        'manual_penalty', v_manual_defense_penalty,
        'total', v_defense_total
      ),
    'damage',
      jsonb_build_object(
        'damage_attack_total', v_damage_attack_total,
        'damage_defense_total', v_damage_defense_total,
        'diff', v_damage_diff,
        'level', v_damage_level,
        'minor_delta', v_minor_delta,
        'serious_delta', v_serious_delta,
        'critical_delta', v_critical_delta,
        'armor_critical_delta', v_armor_critical_delta,
        'body_critical_delta', v_body_critical_delta,
        'melee_strength_bonus', v_melee_strength_bonus
      ),
    'body_part',
      jsonb_build_object(
        'id', v_target_part.id,
        'name', v_target_part.part_name,
        'armor_value', v_new_armor_value,
        'effective_armor', v_effective_armor,
        'armor_critical', v_new_armor_critical,
        'armor_max_critical', coalesce(v_target_part.armor_max_critical, 0),
        'armor_destroyed', v_new_armor_destroyed,
        'minor', v_new_minor,
        'serious', v_new_serious,
        'critical', v_new_critical,
        'max_critical', coalesce(v_target_part.max_critical, 0),
        'disabled', v_new_disabled,
        'destroyed', v_new_destroyed
      ),
    'magazine',
      jsonb_build_object(
        'id', case when v_attack_type = 'ranged' then v_magazine_id else null end,
        'bullets_spent', v_bullets_spent,
        'remaining_rounds', v_remaining_rounds
      ),
    'effects',
      jsonb_build_object(
        'attacker',
          jsonb_build_object(
            'active_effects', coalesce(v_attacker_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_attacker_effect_summary->'modifiers', '{}'::jsonb)
          ),
        'target',
          jsonb_build_object(
            'active_effects', coalesce(v_target_effect_summary->'active_effects', '[]'::jsonb),
            'applied_modifiers', coalesce(v_target_effect_summary->'modifiers', '{}'::jsonb),
            'flags', coalesce(v_target_effect_summary->'flags', '{}'::jsonb),
            'helpless_source', v_target_helpless_source
          )
      ),
    'armor_summary',
      jsonb_build_object(
        'total_armor_value', v_target_armor_total,
        'armor_class', v_target_armor_class,
        'helpless_execution_protected', v_target_armor_class not in ('none', 'light')
      ),
    'execution', v_execution_info,
    'attacker_state', v_attacker_state,
    'target_state', v_target_state,
    'log_id', v_log_id
  )
  into v_result;

  return v_result;
end;
$$;

grant execute on function public.odyssey_get_armor_class(integer) to anon, authenticated;
grant execute on function public.odyssey_get_main_actions_from_agility(integer) to anon, authenticated;
grant execute on function public.odyssey_get_movement_bonus_from_agility(integer) to anon, authenticated;
grant execute on function public.odyssey_get_concentration_slots_from_intelligence(integer) to anon, authenticated;
grant execute on function public.odyssey_merge_effect_data(jsonb, jsonb) to anon, authenticated;
grant execute on function public.get_character_effect_summary(uuid) to anon, authenticated;
grant execute on function public.get_effective_character_stats(uuid) to anon, authenticated;
grant execute on function public.add_character_effect(jsonb) to anon, authenticated;
grant execute on function public.remove_character_effect(uuid) to anon, authenticated;
grant execute on function public.advance_character_effects(uuid) to anon, authenticated;
grant execute on function public.odyssey_refresh_character_combat_state(uuid) to anon, authenticated;
grant execute on function public.perform_attack(jsonb) to anon, authenticated;
