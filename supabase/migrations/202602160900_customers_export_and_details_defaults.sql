-- Create v_customers_export view with COALESCE defaults for admin exports
-- and ensure every customer has a corresponding customer_details row.

-- 1) Export view: v_customers_export

DROP VIEW IF EXISTS public.v_customers_export;

CREATE VIEW public.v_customers_export
WITH (security_invoker = true) AS
SELECT
  c.id,
  c.customer_code,
  COALESCE(c.trade_title, '') AS trade_title,
  COALESCE(c.full_name, '') AS full_name,
  COALESCE(c.phone, '') AS phone,
  COALESCE(c.email, '') AS email,
  COALESCE(c.address, '') AS address,
  COALESCE(cd.tax_office, '') AS tax_office,
  COALESCE(cd.tax_no, '') AS tax_no,
  COALESCE(cd.city, '') AS city,
  COALESCE(cd.district, '') AS district,
  COALESCE(cd.risk_note, '') AS risk_note,
  COALESCE(cd.limit_amount, 0)::numeric AS limit_amount,
  COALESCE(cd.due_days, 30) AS due_days,
  COALESCE(cd.price_tier, 4) AS price_tier,
  COALESCE(cd.warn_on_limit_exceeded, false) AS warn_on_limit_exceeded
FROM public.customers c
LEFT JOIN public.customer_details cd
  ON cd.customer_id = c.id;


-- 2) Trigger to guarantee customer_details row per customer

CREATE OR REPLACE FUNCTION public.trg_customers_ensure_details()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.customer_details (customer_id)
  VALUES (NEW.id)
  ON CONFLICT (customer_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customers_ensure_details
  ON public.customers;

CREATE TRIGGER trg_customers_ensure_details
AFTER INSERT ON public.customers
FOR EACH ROW
EXECUTE FUNCTION public.trg_customers_ensure_details();


-- Notify Supabase / PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
