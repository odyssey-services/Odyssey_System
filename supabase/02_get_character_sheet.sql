create or replace function public.get_odyssey_character_sheet(p_character_key text)
returns jsonb
language sql
stable
as $body$
  select
    jsonb_build_object(
      'character_key', c.character_key,
      'character_bucket', c.character_bucket,
      'source_template_key', c.source_template_key,
      'enabled', c.enabled,
      'tracker_minor', c.tracker_minor,
      'tracker_serious', c.tracker_serious,
      'owner_player_id', c.owner_player_id,
      'owner_player_name', c.owner_player_name,
      'resources', c.resources,
      'characteristics',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'key', a.key,
                'label', a.label,
                'value', a.value,
                'sort_order', a.sort_order
              )
              order by a.sort_order, a.key
            )
            from public.odyssey_character_characteristics a
            where a.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'skills',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'name', s.name,
                'value', s.value,
                'category', s.category,
                'strength_bonus', s.strength_bonus,
                'sort_order', s.sort_order
              )
              order by s.sort_order, s.name
            )
            from public.odyssey_character_skills s
            where s.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'weapons',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'weapon_kind', w.weapon_kind,
                'name', w.name,
                'damage', w.damage,
                'accuracy', w.accuracy,
                'ammoCurrent', w.ammo_current,
                'ammoMax', w.ammo_max,
                'sort_order', w.sort_order
              )
              order by w.weapon_kind, w.sort_order, w.name
            )
            from public.odyssey_character_weapons w
            where w.character_id = c.id
          ),
          '[]'::jsonb
        ),
      'body_parts',
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'part_key', b.part_key,
                'current_hp', b.current_hp,
                'max_hp', b.max_hp,
                'armor', b.armor,
                'minor', b.minor,
                'serious', b.serious,
                'sort_order', b.sort_order
              )
              order by b.sort_order, b.part_key
            )
            from public.odyssey_character_body_parts b
            where b.character_id = c.id
          ),
          '[]'::jsonb
        )
    )
  from public.odyssey_characters c
  where c.character_key = trim(p_character_key);
$body$;
