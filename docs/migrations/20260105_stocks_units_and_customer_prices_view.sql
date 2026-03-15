-- 1) Stocks tablosuna birim alanlarini ekle
ALTER TABLE public.stocks
  ADD COLUMN IF NOT EXISTS base_unit_name text,
  ADD COLUMN IF NOT EXISTS pack_unit_name text,
  ADD COLUMN IF NOT EXISTS pack_multiplier numeric(14,3),
  ADD COLUMN IF NOT EXISTS box_unit_name text,
  ADD COLUMN IF NOT EXISTS box_multiplier numeric(14,3);

-- 2) Null veya bos kalanlari default degerlerle doldur
-- Not: yalnizca NULL veya bos string olan kayitlara dokunulur.
UPDATE public.stocks
SET base_unit_name = 'Adet'
WHERE base_unit_name IS NULL OR trim(base_unit_name) = '';

UPDATE public.stocks
SET pack_unit_name = 'Paket'
WHERE pack_unit_name IS NULL OR trim(pack_unit_name) = '';

UPDATE public.stocks
SET box_unit_name = 'Koli'
WHERE box_unit_name IS NULL OR trim(box_unit_name) = '';

UPDATE public.stocks
SET pack_multiplier = 5
WHERE pack_multiplier IS NULL;

UPDATE public.stocks
SET box_multiplier = 15
WHERE box_multiplier IS NULL;

-- 3) Musteri stok fiyat view'i: v_customer_stock_prices
-- Mevcut isim degisikligi sorunu icin once view'i tamamen dusurup sonra yeniden olusturuyoruz.
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
  s.base_unit_name AS unit,
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

-- Şema değişikliğini PostgREST'e bildir
NOTIFY pgrst, 'reload schema';
