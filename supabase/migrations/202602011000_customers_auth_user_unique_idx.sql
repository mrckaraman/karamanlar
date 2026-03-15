-- Ensure customers.auth_user_id column exists.
-- Date: 2026-02-01

set search_path to public;

alter table public.customers
  add column if not exists auth_user_id uuid;

-- Drop old idx_customers_auth_user_id index if present.
do $$
begin
  if exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'idx_customers_auth_user_id'
  ) then
    execute 'drop index if exists public.idx_customers_auth_user_id';
  end if;
end$$;

-- NOTE: As of 2026-02-01, the canonical unique constraint/index for
-- customers.auth_user_id is `customers_auth_user_id_key` which is
-- managed outside of this migration (e.g. Supabase UI or another
-- schema migration). We intentionally do NOT create an additional
-- idx_customers_auth_user_id index here to avoid redundancy.
