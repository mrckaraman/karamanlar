-- Ensure public.is_admin() uses search_path = public and checks admin_users
-- Date: 2026-02-15

set search_path = public;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  );
$$;

-- No grants here; function will be callable in SQL security context as usual.
-- If needed you can explicitly grant execute, e.g.:
-- grant execute on function public.is_admin() to authenticated;
