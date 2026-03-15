-- Fix: admin customer report RPCs
-- - Accept p_status NULL and treat as "all"
-- - Support new status values: debt / credit
-- - Keep backward compatibility for debitOnly / creditOnly
-- - Allow p_min_abs_net NULL (no minimum)

CREATE OR REPLACE FUNCTION public.rpc_admin_customer_balance_snapshot(
  p_min_abs_net numeric DEFAULT NULL,
  p_status text DEFAULT NULL,
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
    WHERE (
        p_min_abs_net IS NULL
        OR ABS(COALESCE(r.net_balance, 0)) >= p_min_abs_net
      )
      AND (
        p_status IS NULL
        OR LOWER(p_status) = 'all'
        OR (LOWER(p_status) IN ('debt', 'debitonly') AND COALESCE(r.net_balance, 0) > 0)
        OR (LOWER(p_status) IN ('credit', 'creditonly') AND COALESCE(r.net_balance, 0) < 0)
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


CREATE OR REPLACE FUNCTION public.rpc_admin_customer_balance_page(
  p_min_abs_net numeric DEFAULT NULL,
  p_status text DEFAULT NULL,
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
    WHERE (
        $1 IS NULL
        OR ABS(COALESCE(r.net_balance, 0)) >= $1
      )
      AND (
        $2 IS NULL
        OR LOWER($2) = 'all'
        OR (LOWER($2) IN ('debt', 'debitonly') AND COALESCE(r.net_balance, 0) > 0)
        OR (LOWER($2) IN ('credit', 'creditonly') AND COALESCE(r.net_balance, 0) < 0)
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
      p_min_abs_net,
      p_status,
      p_group_name,
      p_sub_group,
      p_alt_group,
      p_marketer_name,
      p_search,
      GREATEST(COALESCE(p_limit, 50), 1),
      GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

-- PostgREST schema reload
NOTIFY pgrst, 'reload schema';
