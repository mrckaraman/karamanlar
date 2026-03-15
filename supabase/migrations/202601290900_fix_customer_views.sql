-- Fix customer price view and add customer balance view

-- 1) Customer stock prices view: v_customer_stock_prices
--    Ensure price_tier is read from customer_details (cd.price_tier)
DROP VIEW IF EXISTS public.v_customer_stock_prices;

CREATE VIEW public.v_customer_stock_prices
WITH (security_invoker = true) AS
SELECT
  -- Müşteri + stok kombinasyonundan deterministik UUID
  (md5((cd.customer_id::text || ':' || s.id::text)))::uuid AS id,
  -- Orijinal stok kimliği
  s.id AS stock_id,
  s.name,
  s.code,
  s.barcode,
  -- Şimdilik marka / görsel / vergi doğrudan stoktan veya NULL dönebilir
  s.brand,
  s.image_path,
  s.base_unit_name AS base_unit_name,
  -- price_tier mantığına göre birim fiyat
  COALESCE(
    CASE cd.price_tier
      WHEN 1 THEN s.sale_price_1
      WHEN 2 THEN COALESCE(s.sale_price_2, s.sale_price_1)
      WHEN 3 THEN COALESCE(s.sale_price_3, s.sale_price_1)
      WHEN 4 THEN COALESCE(s.sale_price_4, s.sale_price_1)
      ELSE s.sale_price_1
    END,
    s.sale_price_1
  ) AS unit_price,
  -- Şimdilik base_unit_price = unit_price
  COALESCE(
    CASE cd.price_tier
      WHEN 1 THEN s.sale_price_1
      WHEN 2 THEN COALESCE(s.sale_price_2, s.sale_price_1)
      WHEN 3 THEN COALESCE(s.sale_price_3, s.sale_price_1)
      WHEN 4 THEN COALESCE(s.sale_price_4, s.sale_price_1)
      ELSE s.sale_price_1
    END,
    s.sale_price_1
  ) AS base_unit_price,
  -- Orijinal fiyat kolonları
  s.sale_price_1,
  s.sale_price_2,
  s.sale_price_3,
  s.sale_price_4,
  s.tax_rate,
  -- Mevcut birim ve barkod alanlarını koruyoruz
  s.base_unit_name,
  s.pack_unit_name,
  s.pack_multiplier,
  s.box_unit_name,
  s.box_multiplier,
  s.pack_barcode,
  s.box_barcode,
  concat_ws(
    '|',
    NULLIF(s.barcode, ''),
    NULLIF(s.pack_barcode, ''),
    NULLIF(s.box_barcode, '')
  ) AS barcode_text,
  s.group_name,
  s.subgroup_name,
  s.subsubgroup_name,
  s.is_active
FROM public.stocks s
JOIN public.customer_details cd ON TRUE
WHERE s.is_active = true;


-- 2) Customer balance view: v_customer_balance
--    Aggregate debit/credit amounts per customer from ledger_entries
DROP VIEW IF EXISTS public.v_customer_balance;

CREATE VIEW public.v_customer_balance
WITH (security_invoker = true) AS
SELECT
  le.customer_id,
  COALESCE(SUM(le.debit), 0) AS total_debit,
  COALESCE(SUM(le.credit), 0) AS total_credit,
  COALESCE(SUM(le.debit), 0) - COALESCE(SUM(le.credit), 0) AS net
FROM public.ledger_entries le
GROUP BY le.customer_id;

-- Notify PostgREST / Supabase to reload schema
NOTIFY pgrst, 'reload schema';
