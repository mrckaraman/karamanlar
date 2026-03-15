-- Wrapper for rpc_import_customers to match PostgREST expected signature (mode, payload)
-- Date: 2026-02-15

-- Existing implementation has signature (payload jsonb, mode text).
-- PostgREST, given a JSON body like {"mode": "validate", "payload": {...}},
-- looks for a function rpc_import_customers(mode text, payload jsonb).
-- This wrapper delegates to the existing implementation.

create or replace function public.rpc_import_customers(mode text, payload jsonb)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.rpc_import_customers(payload::jsonb, mode::text);
$$;

revoke all on function public.rpc_import_customers(text, jsonb) from public;
grant execute on function public.rpc_import_customers(text, jsonb) to authenticated;

notify pgrst, 'reload schema';

-- NOTE:
-- 1) First deploy 202602141000_customer_import_rpc.sql (main implementation: payload jsonb, mode text)
-- 2) Then deploy this wrapper so PostgREST can call (mode text, payload jsonb)
