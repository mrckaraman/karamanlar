-- Customer statement: use created_at timestamptz for ordering + filtering
-- Date: 2026-03-06

set search_path = public;

-- Recreate view to expose created_at (timestamptz) and keep backward-compatible date field
DROP VIEW IF EXISTS public.v_customer_statement_with_balance;

CREATE VIEW public.v_customer_statement_with_balance
WITH (security_invoker = true) AS
SELECT
  le.id,
  le.customer_id,

  -- Authoritative timestamp (timestamptz)
  e.created_at,

  -- Backward compatibility: keep "date" column but now include time.
  -- (Older clients may still read/order by date)
  e.created_at AS date,

  le.type,
  le.ref_id,
  le.description,
  le.debit,
  le.credit,
  le.balance,
  le.is_overdue,

  -- invoice_id: varsa doğrudan ledger_entries.ref_type/ref_id'den, yoksa invoice_no eşleşmesi ile
  COALESCE(
    CASE
      WHEN le.ref_type = 'invoice' AND le.ref_id IS NOT NULL THEN le.ref_id::uuid
      ELSE NULL
    END,
    (
      SELECT i.id
      FROM public.invoices i
      WHERE le.ref_type = 'invoice_no'
        AND i.invoice_no = le.ref_id
      LIMIT 1
    )
  ) AS invoice_id
FROM public.v_customer_statement_with_balance_base le
JOIN public.ledger_entries e
  ON e.id = le.id;


-- Update bulk statement RPC to filter/sort by created_at
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
            'created_at', s.created_at,
            'date', s.created_at,
            'type', s.type,
            'ref', s.ref_id,
            'description', s.description,
            'debit', coalesce(s.debit, 0),
            'credit', coalesce(s.credit, 0),
            'amount', (coalesce(s.debit, 0) - coalesce(s.credit, 0)),
            'balance', s.balance
          )
          order by s.created_at desc, s.id
        ) filter (where s.customer_id is not null),
        '[]'::jsonb
      )
    ) as customer_block
    from public.customers c
    left join public.customer_details cd
      on cd.customer_id = c.id
    left join public.v_customer_statement_with_balance s
      on s.customer_id = c.id
     and s.created_at >= p_date_from
     and s.created_at <= p_date_to
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
