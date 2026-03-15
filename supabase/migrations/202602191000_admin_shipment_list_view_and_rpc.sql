-- Admin shipment list view + RPC (pagination + filters)
-- Date: 2026-02-19

set search_path = public;

create or replace view public.v_admin_shipment_list
with (security_invoker = true) as
select
  o.id,
  o.order_no,
  o.created_at,
  o.status,
  o.total_amount,
  o.customer_id,
  COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) as customer_name,
  NULLIF(cd.city, '') as city,
  o.invoiced
from public.orders o
join public.customers c on c.id = o.customer_id
left join public.customer_details cd on cd.customer_id = c.id
where o.status in ('approved','preparing')
  and o.invoiced = false;

create or replace function public.rpc_admin_shipment_list(
  p_search text default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_limit int default 20,
  p_offset int default 0
)
returns setof public.v_admin_shipment_list
language sql
stable
security definer
set search_path = public, auth
as $$
  select *
  from public.v_admin_shipment_list
  where
    public.is_admin()
    and (p_search is null or customer_name ilike '%' || p_search || '%')
    and (p_date_from is null or created_at >= p_date_from)
    and (p_date_to is null or created_at <= p_date_to)
  order by created_at desc
  limit p_limit
  offset p_offset;
$$;

create or replace function public.rpc_admin_shipment_list_count(
  p_search text default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null
)
returns bigint
language sql
stable
security definer
set search_path = public, auth
as $$
  select count(*)
  from public.v_admin_shipment_list
  where
    public.is_admin()
    and (p_search is null or customer_name ilike '%' || p_search || '%')
    and (p_date_from is null or created_at >= p_date_from)
    and (p_date_to is null or created_at <= p_date_to);
$$;

revoke all on function public.rpc_admin_shipment_list(text, timestamptz, timestamptz, int, int) from public;
grant execute on function public.rpc_admin_shipment_list(text, timestamptz, timestamptz, int, int) to authenticated;

revoke all on function public.rpc_admin_shipment_list_count(text, timestamptz, timestamptz) from public;
grant execute on function public.rpc_admin_shipment_list_count(text, timestamptz, timestamptz) to authenticated;

-- Notify Supabase / PostgREST to reload schema
notify pgrst, 'reload schema';
