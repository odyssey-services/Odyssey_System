do $$
declare
  v_function record;
begin
  for v_function in
    select
      n.nspname as schema_name,
      p.proname as function_name,
      pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n
      on n.oid = p.pronamespace
    left join pg_depend d
      on d.classid = 'pg_proc'::regclass
     and d.objid = p.oid
     and d.deptype = 'e'
    where n.nspname = 'public'
      and p.prokind = 'f'
      and d.objid is null
  loop
    execute format(
      'alter function %I.%I(%s) set search_path = public, pg_temp',
      v_function.schema_name,
      v_function.function_name,
      v_function.identity_args
    );
  end loop;
end;
$$;
