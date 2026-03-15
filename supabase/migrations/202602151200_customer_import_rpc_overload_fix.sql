-- Fix overload ambiguity for rpc_import_customers (PGRST203)
-- Date: 2026-02-15

begin;

set search_path = public;

-- Rename existing implementation (payload jsonb, mode text) to an internal name
alter function public.rpc_import_customers(jsonb, text)
  rename to rpc_import_customers_impl;

-- Expose a single public signature matching PostgREST expectations
create or replace function public.rpc_import_customers(mode text, payload jsonb)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.rpc_import_customers_impl(payload::jsonb, mode::text);
$$;

revoke all on function public.rpc_import_customers(text, jsonb) from public;
grant execute on function public.rpc_import_customers(text, jsonb) to authenticated;

-- Reload PostgREST schema cache
notify pgrst, 'reload schema';

commit;
