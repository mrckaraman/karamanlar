-- Enterprise: Customer statement summary + audit log + due_date + reporting RPCs

-- 0) Invoice due_date column (for overdue calculations + index)
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS due_date date;

-- Backfill due_date (best effort) using customer_details.due_days
UPDATE public.invoices i
SET due_date = (
  COALESCE(
    i.invoice_date,
    i.issued_at::date,
    i.created_at::date,
    current_date
  ) + (COALESCE(cd.due_days, 30) || ' days')::interval
)::date
FROM public.customer_details cd
WHERE cd.customer_id = i.customer_id
  AND i.due_date IS NULL;

CREATE INDEX IF NOT EXISTS idx_invoice_due_date
  ON public.invoices (due_date);


-- 1) Audit log table (no hard delete policy support)
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL,
  user_id uuid,
  entity_type text NOT NULL,
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_entity
  ON public.audit_log (entity_type, entity_id, created_at DESC);


-- 2) Summary view: customer_statement (requested fields)
-- Notes:
-- - net_balance / totals come from v_customer_balance (ledger-based)
-- - overdue/not_due based on invoices.due_date and remaining amount
DROP MATERIALIZED VIEW IF EXISTS public.customer_statement;

CREATE MATERIALIZED VIEW public.customer_statement AS
SELECT
  c.id AS customer_id,
  COALESCE(b.net, 0)::numeric AS net_balance,
  COALESCE(b.total_debit, 0)::numeric AS total_debit,
  COALESCE(b.total_credit, 0)::numeric AS total_credit,

  COALESCE(inv.overdue_amount, 0)::numeric AS overdue_amount,
  COALESCE(inv.not_due_amount, 0)::numeric AS not_due_amount,

  COALESCE(cd.limit_amount, 0)::numeric AS limit_amount,
  CASE
    WHEN COALESCE(cd.limit_amount, 0) = 0 THEN 0
    ELSE (COALESCE(b.net, 0) / cd.limit_amount) * 100
  END::numeric AS limit_usage_percent,

  li.last_invoice_date,
  lp.last_payment_date,

  (
    COALESCE(cd.limit_amount, 0) > 0
    AND COALESCE(b.net, 0) >= cd.limit_amount
  ) AS is_limit_exceeded
FROM public.customers c
LEFT JOIN public.customer_details cd
  ON cd.customer_id = c.id
LEFT JOIN public.v_customer_balance b
  ON b.customer_id = c.id
LEFT JOIN LATERAL (
  SELECT
    COALESCE(i.invoice_date, i.issued_at::date, i.created_at::date) AS last_invoice_date
  FROM public.invoices i
  WHERE i.customer_id = c.id
  ORDER BY COALESCE(i.invoice_date, i.issued_at::date, i.created_at::date) DESC
  LIMIT 1
) li ON TRUE
LEFT JOIN LATERAL (
  SELECT
    cp.payment_date AS last_payment_date
  FROM public.customer_payments cp
  WHERE cp.customer_id = c.id
    AND COALESCE(cp.is_cancelled, false) = false
  ORDER BY cp.payment_date DESC
  LIMIT 1
) lp ON TRUE
LEFT JOIN LATERAL (
  SELECT
    SUM(
      CASE
        WHEN i.due_date < current_date AND i.status <> 'paid'
          THEN GREATEST(i.total_amount - COALESCE(i.paid_amount, 0), 0)
        ELSE 0
      END
    ) AS overdue_amount,
    SUM(
      CASE
        WHEN i.due_date >= current_date AND i.status <> 'paid'
          THEN GREATEST(i.total_amount - COALESCE(i.paid_amount, 0), 0)
        ELSE 0
      END
    ) AS not_due_amount
  FROM public.invoices i
  WHERE i.customer_id = c.id
) inv ON TRUE
WHERE c.is_active = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_statement_customer_id
  ON public.customer_statement (customer_id);

CREATE INDEX IF NOT EXISTS idx_customer_net_balance
  ON public.customer_statement (net_balance);

CREATE INDEX IF NOT EXISTS idx_customer_limit_usage
  ON public.customer_statement (limit_usage_percent);


-- 3) Admin report view (joins summary with customer identity + groups)
DROP VIEW IF EXISTS public.v_admin_customer_financial_report;

CREATE VIEW public.v_admin_customer_financial_report
WITH (security_invoker = true) AS
SELECT
  cs.customer_id,
  c.customer_code,
  COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) AS title,
  c.phone,
  cd.group_name,
  cd.sub_group,
  cd.alt_group,
  cd.marketer_name,

  cs.net_balance,
  cs.total_debit,
  cs.total_credit,
  cs.overdue_amount,
  cs.not_due_amount,
  cs.limit_amount,
  cs.limit_usage_percent,
  cs.last_invoice_date,
  cs.last_payment_date,
  cs.is_limit_exceeded,

  lo.last_shipment_at
FROM public.customer_statement cs
JOIN public.customers c
  ON c.id = cs.customer_id
LEFT JOIN public.customer_details cd
  ON cd.customer_id = c.id
LEFT JOIN LATERAL (
  SELECT MAX(o.created_at) AS last_shipment_at
  FROM public.orders o
  WHERE o.customer_id = c.id
) lo ON TRUE
WHERE c.is_active = TRUE;


-- 4) Reporting RPCs (server-side pagination + sorting)
-- Snapshot: totals for current filters
CREATE OR REPLACE FUNCTION public.rpc_admin_customer_balance_snapshot(
  p_min_abs_net numeric DEFAULT 0,
  p_status text DEFAULT 'all',
  p_group_name text DEFAULT NULL,
  p_sub_group text DEFAULT NULL,
  p_alt_group text DEFAULT NULL,
  p_marketer_name text DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS TABLE (
  total_debit numeric,
  total_credit numeric,
  net_risk numeric,
  limit_exceeded_count integer,
  row_count integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      r.total_debit,
      r.total_credit,
      r.net_balance,
      r.is_limit_exceeded
    FROM public.v_admin_customer_financial_report r
    WHERE ABS(COALESCE(r.net_balance, 0)) >= COALESCE(p_min_abs_net, 0)
      AND (
        p_status = 'all'
        OR (p_status = 'debitOnly' AND COALESCE(r.net_balance, 0) > 0)
        OR (p_status = 'creditOnly' AND COALESCE(r.net_balance, 0) < 0)
      )
      AND (p_group_name IS NULL OR p_group_name = '' OR r.group_name = p_group_name)
      AND (p_sub_group IS NULL OR p_sub_group = '' OR r.sub_group = p_sub_group)
      AND (p_alt_group IS NULL OR p_alt_group = '' OR r.alt_group = p_alt_group)
      AND (p_marketer_name IS NULL OR p_marketer_name = '' OR r.marketer_name = p_marketer_name)
      AND (
        p_search IS NULL OR p_search = ''
        OR r.title ILIKE ('%' || p_search || '%')
        OR r.customer_code ILIKE ('%' || p_search || '%')
        OR COALESCE(r.phone, '') ILIKE ('%' || p_search || '%')
      )
  )
  SELECT
    COALESCE(SUM(total_debit), 0)::numeric AS total_debit,
    COALESCE(SUM(total_credit), 0)::numeric AS total_credit,
    COALESCE(SUM(total_debit) - SUM(total_credit), 0)::numeric AS net_risk,
    COALESCE(SUM(CASE WHEN is_limit_exceeded THEN 1 ELSE 0 END), 0)::integer AS limit_exceeded_count,
    COALESCE(COUNT(*), 0)::integer AS row_count
  FROM base;
$$;


-- Page: rows with pagination and safe sorting
CREATE OR REPLACE FUNCTION public.rpc_admin_customer_balance_page(
  p_min_abs_net numeric DEFAULT 0,
  p_status text DEFAULT 'all',
  p_group_name text DEFAULT NULL,
  p_sub_group text DEFAULT NULL,
  p_alt_group text DEFAULT NULL,
  p_marketer_name text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_sort_field text DEFAULT 'net_balance',
  p_sort_desc boolean DEFAULT true,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  customer_id uuid,
  customer_code text,
  title text,
  group_name text,
  net_balance numeric,
  total_debit numeric,
  total_credit numeric,
  limit_amount numeric,
  limit_usage_percent numeric,
  last_shipment_at timestamptz,
  last_payment_date date,
  status_badge text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sort_col text;
  v_dir text;
  v_sql text;
BEGIN
  v_sort_col := CASE p_sort_field
    WHEN 'customer_code' THEN 'customer_code'
    WHEN 'title' THEN 'title'
    WHEN 'group_name' THEN 'group_name'
    WHEN 'total_debit' THEN 'total_debit'
    WHEN 'total_credit' THEN 'total_credit'
    WHEN 'limit_amount' THEN 'limit_amount'
    WHEN 'limit_usage_percent' THEN 'limit_usage_percent'
    WHEN 'last_shipment_at' THEN 'last_shipment_at'
    WHEN 'last_payment_date' THEN 'last_payment_date'
    WHEN 'net_balance' THEN 'net_balance'
    ELSE 'net_balance'
  END;

  v_dir := CASE WHEN COALESCE(p_sort_desc, true) THEN 'DESC' ELSE 'ASC' END;

  v_sql := format($f$
    SELECT
      r.customer_id,
      r.customer_code,
      r.title,
      r.group_name,
      r.net_balance,
      r.total_debit,
      r.total_credit,
      r.limit_amount,
      r.limit_usage_percent,
      r.last_shipment_at,
      r.last_payment_date,
      CASE
        WHEN COALESCE(r.limit_usage_percent, 0) >= 100 THEN 'limit_exceeded'
        WHEN COALESCE(r.limit_usage_percent, 0) >= 80 THEN 'risky'
        ELSE 'normal'
      END AS status_badge
    FROM public.v_admin_customer_financial_report r
    WHERE ABS(COALESCE(r.net_balance, 0)) >= $1
      AND (
        $2 = 'all'
        OR ($2 = 'debitOnly' AND COALESCE(r.net_balance, 0) > 0)
        OR ($2 = 'creditOnly' AND COALESCE(r.net_balance, 0) < 0)
      )
      AND ($3 IS NULL OR $3 = '' OR r.group_name = $3)
      AND ($4 IS NULL OR $4 = '' OR r.sub_group = $4)
      AND ($5 IS NULL OR $5 = '' OR r.alt_group = $5)
      AND ($6 IS NULL OR $6 = '' OR r.marketer_name = $6)
      AND (
        $7 IS NULL OR $7 = ''
        OR r.title ILIKE ('%%' || $7 || '%%')
        OR r.customer_code ILIKE ('%%' || $7 || '%%')
        OR COALESCE(r.phone, '') ILIKE ('%%' || $7 || '%%')
      )
    ORDER BY %I %s, r.customer_id ASC
    LIMIT $8 OFFSET $9
  $f$, v_sort_col, v_dir);

  RETURN QUERY EXECUTE v_sql
    USING
      COALESCE(p_min_abs_net, 0),
      COALESCE(p_status, 'all'),
      p_group_name,
      p_sub_group,
      p_alt_group,
      p_marketer_name,
      p_search,
      GREATEST(COALESCE(p_limit, 50), 1),
      GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;


-- Refresh helper for materialized view
CREATE OR REPLACE FUNCTION public.refresh_customer_statement()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  REFRESH MATERIALIZED VIEW public.customer_statement;
$$;


-- PostgREST schema reload
NOTIFY pgrst, 'reload schema';
