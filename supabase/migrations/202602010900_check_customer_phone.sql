-- Create RPC function for checking customer phone in a RLS-safe way
-- Date: 2026-02-01

set search_path to public;

create or replace function public.check_customer_phone(phone_e164 text)
returns table (
  exists boolean,
  is_active boolean
) as
$$
declare
  v_is_active boolean;
begin
  select c.is_active
    into v_is_active
  from public.customers c
  where c.phone = phone_e164
  limit 1;

  if not found then
    exists := false;
    is_active := false;
    return;
  end if;

  exists := true;
  is_active := coalesce(v_is_active, true);
  return;
end;
$$ language plpgsql
security definer;

-- Lock down and grant execute only to required roles
revoke all on function public.check_customer_phone(text) from public;
grant execute on function public.check_customer_phone(text) to anon, authenticated;
