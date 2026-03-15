-- Extend customer statement view with invoice_id for linking to invoices

DROP VIEW IF EXISTS public.v_customer_statement_with_balance;

CREATE VIEW public.v_customer_statement_with_balance
WITH (security_invoker = true) AS
SELECT
  le.id,
  le.customer_id,
  le.date,
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
FROM public.v_customer_statement_with_balance_base le;

-- NOT: v_customer_statement_with_balance_base, mevcut migrationlarda
-- kullanılan, balance/is_overdue gibi alanları hesaplayan alt view ya da
-- sorgu kaynağıdır. Eğer böyle bir alt view yoksa, bu migrationdaki SELECT
-- içeriği, mevcut v_customer_statement_with_balance tanımındaki SELECT ile
-- birebir aynı olmalı ve sadece invoice_id sütunu eklenmelidir.

-- Notify PostgREST / Supabase to reload schema
NOTIFY pgrst, 'reload schema';
