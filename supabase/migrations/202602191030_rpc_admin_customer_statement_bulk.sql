-- Admin: Bulk customer statement (JSON) for Edge Function report generation
-- Date: 2026-02-19

set search_path = public;

create or replace function public.rpc_admin_customer_statement_bulk(
  p_customer_ids uuid[],
  p_date_from timestamptz,
  p_date_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
begin
  if p_customer_ids is null or array_length(p_customer_ids, 1) is null then
    return '[]'::jsonb;
  end if;

  -- Admin guard (uses JWT context)
  if not public.is_admin(auth.uid()) then
    raise exception 'not authorized';
  end if;

  -- For each customer: identity + summary + statement lines (ledger-based)
  select jsonb_agg(customer_block)
  into v_result
  from (
    select jsonb_build_object(
      'customer_id', c.id,
      'customer_name', coalesce(nullif(c.trade_title, ''), nullif(c.full_name, ''), c.customer_code),
      'city', nullif(cd.city, ''),
      'summary', jsonb_build_object(
        'debit', coalesce(sum(coalesce(s.debit, 0)), 0),
        'credit', coalesce(sum(coalesce(s.credit, 0)), 0),
        'balance', coalesce(sum(coalesce(s.debit, 0) - coalesce(s.credit, 0)), 0)
      ),
      'lines', coalesce(
        jsonb_agg(
          jsonb_build_object(
            'date', s.date,
            'type', s.type,
            'ref', s.ref_id,
            'description', s.description,
            'debit', coalesce(s.debit, 0),
            'credit', coalesce(s.credit, 0),
            'amount', (coalesce(s.debit, 0) - coalesce(s.credit, 0)),
            'balance', s.balance
          )
          order by s.date, s.id
        ) filter (where s.customer_id is not null),
        '[]'::jsonb
      )
    ) as customer_block
    from public.customers c
    left join public.customer_details cd
      on cd.customer_id = c.id
    left join public.v_customer_statement_with_balance s
      on s.customer_id = c.id
     and s.date >= p_date_from
     and s.date <= p_date_to
    where c.id = any(p_customer_ids)
    group by c.id, c.trade_title, c.full_name, c.customer_code, cd.city
    order by coalesce(nullif(c.trade_title, ''), nullif(c.full_name, ''), c.customer_code)
  ) t;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke all on function public.rpc_admin_customer_statement_bulk(uuid[], timestamptz, timestamptz) from public;
grant execute on function public.rpc_admin_customer_statement_bulk(uuid[], timestamptz, timestamptz) to authenticated;

-- Notify Supabase / PostgREST to reload schema
notify pgrst, 'reload schema';
