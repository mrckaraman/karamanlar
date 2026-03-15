-- Debug: list import-related functions and rpc_import_customers overloads

-- List any functions related to import
select n.nspname as schema,
       p.proname as name,
       pg_get_function_identity_arguments(p.oid) as args,
       pg_get_function_result(p.oid) as returns
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public')
  and (
    p.proname ilike '%import%'
    or p.proname ilike '%customer%'
    or p.proname ilike '%rpc%'
  )
order by 1,2,3;

-- Check rpc_import_customers specifically (all overloads)
select n.nspname as schema,
       p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       pg_get_function_result(p.oid) as returns
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and p.proname='rpc_import_customers'
order by args;
