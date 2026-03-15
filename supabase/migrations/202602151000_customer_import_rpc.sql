-- Wrapper for rpc_import_customers to match PostgREST expected signature (mode, payload)
-- Date: 2026-02-15

set search_path to public;

-- Existing implementation has signature (payload jsonb, mode text).
-- PostgREST, given a JSON body like {"mode": "validate", "payload": {...}},
-- looks for a function rpc_import_customers(mode text, payload jsonb).
-- This wrapper delegates to the existing implementation.

create or replace function public.rpc_import_customers(mode text, payload jsonb)
returns jsonb
language sql
security definer
as
$$
  select public.rpc_import_customers(payload, mode);
$$;

revoke all on function public.rpc_import_customers(text, jsonb) from public;
grant execute on function public.rpc_import_customers(text, jsonb) to authenticated;

-- Ask PostgREST / Supabase to reload schema so the new overload is visible
notify pgrst, 'reload schema';
