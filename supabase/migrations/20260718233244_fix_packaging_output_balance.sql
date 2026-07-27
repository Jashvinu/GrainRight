-- Packaging must measure only production output. The production input
-- consumption uses the same reference id and must not reduce available WIP.
do $$
declare
  function_sql text;
  old_sql constant text :=
    'where s.fpc_id=target_fpc_id and s.reference_type=''production_run'' and s.reference_id=run_row.id::text;';
  new_sql constant text :=
    'where s.fpc_id=target_fpc_id and s.reference_type=''production_run'' and s.reference_id=run_row.id::text and s.item_type=''work_in_progress'';';
begin
  select pg_get_functiondef('private.execute_fpc_operation(text,jsonb,uuid)'::regprocedure)
  into function_sql;

  if position(new_sql in function_sql) > 0 then
    return;
  end if;
  if position(old_sql in function_sql) = 0 then
    raise exception 'Packaging stock balance expression was not found';
  end if;

  execute replace(function_sql, old_sql, new_sql);
end;
$$;
