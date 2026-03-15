-- View: public.v_admin_customers_with_last_invoice
-- Amaç: Admin fatura oluşturma akışında cari + son fatura bilgisini tek sorguda vermek

DROP VIEW IF EXISTS public.v_admin_customers_with_last_invoice;

CREATE VIEW public.v_admin_customers_with_last_invoice
WITH (security_invoker = true) AS
SELECT
  c.id AS customer_id,
  c.id AS id,
  c.trade_title,
  c.full_name,
  c.phone,
  c.customer_code,
  li.last_invoice_no,
  li.last_invoice_issued_at
FROM public.customers c
LEFT JOIN LATERAL (
  SELECT
    i.invoice_no AS last_invoice_no,
    COALESCE(i.invoice_date, i.issued_at, i.created_at) AS last_invoice_issued_at
  FROM public.invoices i
  WHERE i.customer_id = c.id
  ORDER BY COALESCE(i.invoice_date, i.issued_at, i.created_at) DESC
  LIMIT 1
) li ON TRUE
WHERE c.is_active = TRUE;

-- PostgREST / Supabase icin şema yenileme bildirimi
NOTIFY pgrst, 'reload schema';
