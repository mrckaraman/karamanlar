-- Risk report RPCs (enterprise)
-- Date: 2026-02-17

-- Ensure we also support is_admin(uid) signature (keep arg name stable: p_uid)
CREATE OR REPLACE FUNCTION public.is_admin(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users au
    WHERE au.user_id = p_uid
  );
$$;

-- Keep existing is_admin() overload
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT public.is_admin(auth.uid());
$$;


CREATE OR REPLACE FUNCTION public.rpc_admin_customer_risk_snapshot(
  p_alt_group text DEFAULT NULL,
  p_group_name text DEFAULT NULL,
  p_marketer_name text DEFAULT NULL,
  p_min_abs_net numeric DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_sub_group text DEFAULT NULL
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
    WITH base AS (
      SELECT
        c.id AS customer_id,
        c.customer_code,
        COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) AS display_name,
        c.phone,
        cd.group_name,
        cd.sub_group,
        cd.alt_group,
        cd.marketer_name,
        c.is_active,
        (
          COALESCE(cb.net, 0)
          + CASE
              WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                THEN -COALESCE(cd.opening_balance, 0)
              ELSE COALESCE(cd.opening_balance, 0)
            END
        )::numeric AS net_balance,
        COALESCE(cd.limit_amount, 0)::numeric AS limit_amount
      FROM public.customers c
      LEFT JOIN public.customer_details cd
        ON cd.customer_id = c.id
      LEFT JOIN public.v_customer_balance cb
        ON cb.customer_id = c.id
      WHERE
        (
          p_min_abs_net IS NULL
          OR ABS(
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) >= p_min_abs_net
        )
        AND (
          p_status IS NULL
          OR BTRIM(p_status) = ''
          OR LOWER(p_status) = 'all'
          OR (
            LOWER(p_status) = 'debt'
            AND (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) > 0
          )
          OR (
            LOWER(p_status) = 'credit'
            AND (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) < 0
          )
        )
        AND (p_group_name IS NULL OR p_group_name = '' OR cd.group_name = p_group_name)
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
    calc AS (
      SELECT
        net_balance,
        GREATEST(net_balance, 0)::numeric AS debt,
        GREATEST(-net_balance, 0)::numeric AS credit,
        limit_amount,
        CASE
          WHEN net_balance > 0 AND limit_amount > 0 THEN (net_balance / limit_amount) * 100
          ELSE 0
        END::numeric AS limit_usage_percent,
        (limit_amount > 0 AND net_balance > limit_amount) AS is_limit_exceeded,
        (
          limit_amount > 0
          AND net_balance > 0
          AND (net_balance / limit_amount) >= 0.80
        ) AS is_risky_80
      FROM base
    )
    SELECT jsonb_build_object(
      'total_debt', COALESCE(SUM(debt), 0)::numeric,
      'total_credit', COALESCE(SUM(credit), 0)::numeric,
      'net_total', COALESCE(SUM(debt) - SUM(credit), 0)::numeric,
      'row_count', COALESCE(COUNT(*), 0)::integer,
      'limit_exceeded_count', COALESCE(SUM(CASE WHEN is_limit_exceeded THEN 1 ELSE 0 END), 0)::integer,
      'risky_count', COALESCE(SUM(CASE WHEN is_risky_80 THEN 1 ELSE 0 END), 0)::integer,
      'avg_limit_usage', COALESCE(AVG(CASE WHEN limit_amount > 0 AND net_balance > 0 THEN limit_usage_percent END), 0)::numeric
    )
    FROM calc
  );
END;
$$;


CREATE OR REPLACE FUNCTION public.rpc_admin_customer_risk_top(
  p_alt_group text DEFAULT NULL,
  p_group_name text DEFAULT NULL,
  p_marketer_name text DEFAULT NULL,
  p_min_abs_net numeric DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_sub_group text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0,
  p_sort_field text DEFAULT 'limit_usage_percent',
  p_sort_desc boolean DEFAULT true
)
RETURNS TABLE (
  customer_id uuid,
  customer_code text,
  display_name text,
  group_name text,
  sub_group text,
  alt_group text,
  marketer_name text,
  is_active boolean,
  net_balance numeric,
  debt numeric,
  credit numeric,
  limit_amount numeric,
  limit_usage_percent numeric,
  is_limit_exceeded boolean,
  last_invoice_date date,
  last_payment_date date
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_sort_col text;
  v_dir text;
  v_sql text;
BEGIN
  PERFORM set_config('search_path', 'public, auth', true);

  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  v_sort_col := CASE p_sort_field
    WHEN 'display_name' THEN 'display_name'
    WHEN 'customer_code' THEN 'customer_code'
    WHEN 'group_name' THEN 'group_name'
    WHEN 'sub_group' THEN 'sub_group'
    WHEN 'alt_group' THEN 'alt_group'
    WHEN 'marketer_name' THEN 'marketer_name'
    WHEN 'net_balance' THEN 'net_balance'
    WHEN 'limit_amount' THEN 'limit_amount'
    WHEN 'limit_usage_percent' THEN 'limit_usage_percent'
    WHEN 'last_invoice_date' THEN 'last_invoice_date'
    WHEN 'last_payment_date' THEN 'last_payment_date'
    ELSE 'limit_usage_percent'
  END;

  v_dir := CASE WHEN COALESCE(p_sort_desc, true) THEN 'DESC' ELSE 'ASC' END;

  v_sql := format($f$
    WITH base AS (
      SELECT
        c.id AS customer_id,
        c.customer_code,
        COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) AS display_name,
        cd.group_name,
        cd.sub_group,
        cd.alt_group,
        cd.marketer_name,
        c.is_active,
        (
          COALESCE(cb.net, 0)
          + CASE
              WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                THEN -COALESCE(cd.opening_balance, 0)
              ELSE COALESCE(cd.opening_balance, 0)
            END
        )::numeric AS net_balance,
        COALESCE(cd.limit_amount, 0)::numeric AS limit_amount,
        CASE
          WHEN (
            (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) > 0
            AND COALESCE(cd.limit_amount, 0) > 0
          ) THEN (
            (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) / cd.limit_amount
          ) * 100
          ELSE 0
        END::numeric AS limit_usage_percent,
        (
          COALESCE(cd.limit_amount, 0) > 0
          AND (
            COALESCE(cb.net, 0)
            + CASE
                WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                  THEN -COALESCE(cd.opening_balance, 0)
                ELSE COALESCE(cd.opening_balance, 0)
              END
          ) > cd.limit_amount
        ) AS is_limit_exceeded,
        li.last_invoice_date,
        lp.last_payment_date
      FROM public.customers c
      LEFT JOIN public.customer_details cd
        ON cd.customer_id = c.id
      LEFT JOIN public.v_customer_balance cb
        ON cb.customer_id = c.id
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
      WHERE
        (
          $1 IS NULL
          OR ABS(
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) >= $1
        )
        AND (
          $2 IS NULL
          OR BTRIM($2) = ''
          OR LOWER($2) = 'all'
          OR (
            LOWER($2) = 'debt'
            AND (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) > 0
          )
          OR (
            LOWER($2) = 'credit'
            AND (
              COALESCE(cb.net, 0)
              + CASE
                  WHEN LOWER(COALESCE(cd.opening_balance_type, '')) = 'credit'
                    THEN -COALESCE(cd.opening_balance, 0)
                  ELSE COALESCE(cd.opening_balance, 0)
                END
            ) < 0
          )
        )
        AND ($3 IS NULL OR $3 = '' OR cd.group_name = $3)
        AND ($4 IS NULL OR $4 = '' OR cd.sub_group = $4)
        AND ($5 IS NULL OR $5 = '' OR cd.alt_group = $5)
        AND ($6 IS NULL OR $6 = '' OR cd.marketer_name = $6)
        AND (
          $7 IS NULL OR $7 = ''
          OR COALESCE(NULLIF(c.trade_title, ''), NULLIF(c.full_name, ''), c.customer_code) ILIKE ('%%' || $7 || '%%')
          OR c.customer_code ILIKE ('%%' || $7 || '%%')
          OR COALESCE(c.phone, '') ILIKE ('%%' || $7 || '%%')
        )
    ),
    calc AS (
      SELECT
        customer_id,
        customer_code,
        display_name,
        group_name,
        sub_group,
        alt_group,
        marketer_name,
        is_active,
        net_balance,
        GREATEST(net_balance, 0)::numeric AS debt,
        GREATEST(-net_balance, 0)::numeric AS credit,
        limit_amount,
        limit_usage_percent,
        is_limit_exceeded,
        last_invoice_date,
        last_payment_date
      FROM base
    )
    SELECT
      customer_id,
      customer_code,
      display_name,
      group_name,
      sub_group,
      alt_group,
      marketer_name,
      is_active,
      net_balance,
      debt,
      credit,
      limit_amount,
      limit_usage_percent,
      is_limit_exceeded,
      last_invoice_date,
      last_payment_date
    FROM calc
    ORDER BY %I %s, customer_id ASC
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
      GREATEST(COALESCE(p_limit, 25), 1),
      GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

-- PostgREST schema reload
NOTIFY pgrst, 'reload schema';
