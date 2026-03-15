-- Aging snapshot + risk scoring RPCs
-- Date: 2026-02-17

CREATE OR REPLACE FUNCTION public.rpc_admin_customer_aging_snapshot(
  p_group_name text DEFAULT NULL,
  p_sub_group text DEFAULT NULL,
  p_alt_group text DEFAULT NULL,
  p_marketer_name text DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  PERFORM set_config('search_path', 'public, auth', true);

  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN (
    WITH base_customers AS (
      SELECT
        c.id AS customer_id,
        c.customer_code,
        COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) AS display_name,
        c.phone,
        cd.group_name,
        cd.sub_group,
        cd.alt_group,
        cd.marketer_name
      FROM public.customers c
      LEFT JOIN public.customer_details cd
        ON cd.customer_id = c.id
      WHERE (p_group_name IS NULL OR p_group_name = '' OR cd.group_name = p_group_name)
        AND (p_sub_group IS NULL OR p_sub_group = '' OR cd.sub_group = p_sub_group)
        AND (p_alt_group IS NULL OR p_alt_group = '' OR cd.alt_group = p_alt_group)
        AND (p_marketer_name IS NULL OR p_marketer_name = '' OR cd.marketer_name = p_marketer_name)
        AND (
          p_search IS NULL OR p_search = ''
          OR COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) ILIKE ('%' || p_search || '%')
          OR c.customer_code ILIKE ('%' || p_search || '%')
          OR COALESCE(c.phone, '') ILIKE ('%' || p_search || '%')
        )
    ),
    sums AS (
      SELECT
        COALESCE(SUM(CASE WHEN a.bucket_order = 1 THEN a.amount ELSE 0 END), 0)::numeric AS amount_0_7,
        COALESCE(SUM(CASE WHEN a.bucket_order = 2 THEN a.amount ELSE 0 END), 0)::numeric AS amount_8_14,
        COALESCE(SUM(CASE WHEN a.bucket_order = 3 THEN a.amount ELSE 0 END), 0)::numeric AS amount_15_30,
        COALESCE(SUM(CASE WHEN a.bucket_order >= 4 THEN a.amount ELSE 0 END), 0)::numeric AS amount_over_30,
        COALESCE(SUM(CASE WHEN a.bucket_order > 0 THEN a.amount ELSE 0 END), 0)::numeric AS total_overdue,
        COALESCE(
          COUNT(DISTINCT CASE WHEN a.bucket_order > 0 AND a.amount > 0 THEN bc.customer_id END),
          0
        )::integer AS overdue_customer_count
      FROM base_customers bc
      LEFT JOIN public.v_customer_aging a
        ON a.customer_id = bc.customer_id
    )
    SELECT jsonb_build_object(
      '0_7_days_amount', amount_0_7,
      '8_14_days_amount', amount_8_14,
      '15_30_days_amount', amount_15_30,
      'over_30_days_amount', amount_over_30,
      'total_overdue_amount', total_overdue,
      'overdue_customer_count', overdue_customer_count
    )
    FROM sums
  );
END;
$$;


-- Risk scoring model
-- risk_score = (limit_usage_percent * 0.6) + (overdue_ratio * 0.3) + (payment_delay_score * 0.1)
-- overdue_ratio: overdue_amount / debt(net_balance>0) * 100 (clamped to 0..100)
-- payment_delay_score: weighted avg by overdue bucket amounts (0-7=10, 8-14=30, 15-30=60, 31+=100)
-- risk_level thresholds: <40 low, 40-70 medium, >=70 high
CREATE OR REPLACE FUNCTION public.rpc_admin_customer_risk_scored_top(
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  customer_id uuid,
  display_name text,
  net_balance numeric,
  limit_amount numeric,
  limit_usage_percent numeric,
  overdue_amount numeric,
  risk_score numeric,
  risk_level text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  PERFORM set_config('search_path', 'public, auth', true);

  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN QUERY
  WITH aging AS (
    SELECT
      a.customer_id,
      COALESCE(SUM(CASE WHEN a.bucket_order = 1 THEN a.amount ELSE 0 END), 0)::numeric AS a0_7,
      COALESCE(SUM(CASE WHEN a.bucket_order = 2 THEN a.amount ELSE 0 END), 0)::numeric AS a8_14,
      COALESCE(SUM(CASE WHEN a.bucket_order = 3 THEN a.amount ELSE 0 END), 0)::numeric AS a15_30,
      COALESCE(SUM(CASE WHEN a.bucket_order >= 4 THEN a.amount ELSE 0 END), 0)::numeric AS a31p,
      COALESCE(SUM(CASE WHEN a.bucket_order > 0 THEN a.amount ELSE 0 END), 0)::numeric AS overdue_amount
    FROM public.v_customer_aging a
    GROUP BY a.customer_id
  ),
  base AS (
    SELECT
      c.id AS customer_id,
      COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) AS display_name,
      (
        COALESCE(cb.net, 0)
        + CASE
            WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
              THEN -COALESCE(cd.opening_balance, 0)
            ELSE COALESCE(cd.opening_balance, 0)
          END
      )::numeric AS net_balance,
      COALESCE(cd.limit_amount, 0)::numeric AS limit_amount,
      COALESCE(ag.overdue_amount, 0)::numeric AS overdue_amount,
      COALESCE(ag.a0_7, 0)::numeric AS a0_7,
      COALESCE(ag.a8_14, 0)::numeric AS a8_14,
      COALESCE(ag.a15_30, 0)::numeric AS a15_30,
      COALESCE(ag.a31p, 0)::numeric AS a31p
    FROM public.customers c
    LEFT JOIN public.customer_details cd
      ON cd.customer_id = c.id
    LEFT JOIN public.v_customer_balance cb
      ON cb.customer_id = c.id
    LEFT JOIN aging ag
      ON ag.customer_id = c.id
  ),
  calc AS (
    SELECT
      b.customer_id,
      b.display_name,
      b.net_balance,
      b.limit_amount,
      CASE
        WHEN b.net_balance > 0 AND b.limit_amount > 0 THEN (b.net_balance / b.limit_amount) * 100
        ELSE 0
      END::numeric AS limit_usage_percent,
      b.overdue_amount,
      GREATEST(b.net_balance, 0)::numeric AS debt,
      CASE
        WHEN GREATEST(b.net_balance, 0) > 0 THEN LEAST((b.overdue_amount / GREATEST(b.net_balance, 0)) * 100, 100)
        ELSE 0
      END::numeric AS overdue_ratio,
      CASE
        WHEN b.overdue_amount > 0 THEN (
          (
            (b.a0_7 * 10)
            + (b.a8_14 * 30)
            + (b.a15_30 * 60)
            + (b.a31p * 100)
          ) / b.overdue_amount
        )
        ELSE 0
      END::numeric AS payment_delay_score
    FROM base b
  ),
  scored AS (
    SELECT
      c.customer_id,
      c.display_name,
      c.net_balance,
      c.limit_amount,
      c.limit_usage_percent,
      c.overdue_amount,
      (
        (LEAST(c.limit_usage_percent, 100) * 0.6)
        + (LEAST(c.overdue_ratio, 100) * 0.3)
        + (LEAST(c.payment_delay_score, 100) * 0.1)
      )::numeric AS risk_score
    FROM calc c
  )
  SELECT
    s.customer_id,
    s.display_name,
    s.net_balance,
    s.limit_amount,
    s.limit_usage_percent,
    s.overdue_amount,
    s.risk_score,
    CASE
      WHEN s.risk_score >= 70 THEN 'high'
      WHEN s.risk_score >= 40 THEN 'medium'
      ELSE 'low'
    END AS risk_level
  FROM scored s
  ORDER BY s.risk_score DESC, s.customer_id ASC
  LIMIT GREATEST(COALESCE(p_limit, 25), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

NOTIFY pgrst, 'reload schema';
