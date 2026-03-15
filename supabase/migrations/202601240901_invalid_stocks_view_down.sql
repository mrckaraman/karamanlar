-- Down migration: v_invalid_stocks ve yeni CHECK kurallarini geri al

-- 1) View'i kaldir
drop view if exists public.v_invalid_stocks;

-- 2) Yeni CHECK constraint'leri kaldir
alter table public.stock_units
  drop constraint if exists stock_units_pack_qty_check,
  drop constraint if exists stock_units_box_qty_check;

-- 3) pack_qty / box_qty kolonlarini tekrar NOT NULL yap
--    Not: Bu adim, tabloda NULL degerler varsa hata verebilir.
alter table public.stock_units
  alter column pack_qty set not null,
  alter column box_qty set not null;

-- 4) (Opsiyonel) Eski CHECK kurallarini geri ekle: >= 1
alter table public.stock_units
  add constraint stock_units_pack_qty_check
    check (pack_qty >= 1),
  add constraint stock_units_box_qty_check
    check (box_qty >= 1);

-- Geri alma sonrasi manuel kontrol icin ornek sorgular:
-- select column_name, is_nullable from information_schema.columns
--   where table_schema = 'public'
--     and table_name = 'stock_units'
--     and column_name in ('pack_qty','box_qty');
