do $$
declare
  v_function_def text := null;
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

  v_function_def := replace(
    v_function_def,
    '''level'', v_effective_level',
    '''level'', v_attack_skill_level'
  );

  execute v_function_def;
end;
$$;

grant execute on function public.odyssey_perform_ability_attack(jsonb) to anon, authenticated;
