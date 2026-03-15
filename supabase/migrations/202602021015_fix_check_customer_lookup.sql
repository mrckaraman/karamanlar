-- Fix customer lookup functions for pre-auth checks via RPC

-- 1) DROP existing functions (signature exact!)
drop function if exists public.check_customer_phone(text);
drop function if exists public.check_customer_email(text);

-- 2) Recreate as security definer RPCs
create or replace function public.check_customer_phone(phone_e164 text)
returns table (customer_id uuid, is_active boolean)
language sql
security definer
set search_path = public
as $$
  select c.id, c.is_active
  from public.customers c
  where c.phone = phone_e164
  limit 1;
$$;

revoke all on function public.check_customer_phone(text) from public;
grant execute on function public.check_customer_phone(text) to anon, authenticated;

create or replace function public.check_customer_email(email_input text)
returns table (customer_id uuid, is_active boolean)
language sql
security definer
set search_path = public
as $$
  select c.id, c.is_active
  from public.customers c
  where lower(c.email) = lower(email_input)
  limit 1;
$$;

revoke all on function public.check_customer_email(text) from public;
grant execute on function public.check_customer_email(text) to anon, authenticated;
