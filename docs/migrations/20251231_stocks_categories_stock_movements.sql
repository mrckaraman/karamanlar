-- 1) Stocks tablosu: miktar ve barkod alanlari
ALTER TABLE public.stocks
  ADD COLUMN IF NOT EXISTS quantity numeric DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS barcode text,
  ADD COLUMN IF NOT EXISTS pack_barcode text,
  ADD COLUMN IF NOT EXISTS box_barcode text;

-- 2) Categories tablosu: is_active kolonu
ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true;

-- 3) Stock movements: stok hareketleri icin tablo
CREATE TABLE IF NOT EXISTS public.stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stock_id uuid NOT NULL REFERENCES public.stocks(id) ON DELETE CASCADE,
  movement_type text NOT NULL CHECK (movement_type IN ('in','out','adjust')),
  qty numeric NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_stock_id
  ON public.stock_movements(stock_id);

-- 4) Stocks tablosuna kategori baglantisi
ALTER TABLE public.stocks
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.categories(id);
