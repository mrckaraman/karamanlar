-- Up migration: Bozuk Stoklar view'i ve stock_units pack_qty/box_qty nullable + CHECK kuralı

-- 1) public.v_invalid_stocks view'i (idempotent)
create or replace view public.v_invalid_stocks as
select
  s.id,
  s.code,
  s.name,
  s.barcode,
  s.pack_barcode,
  s.box_barcode,
  u.pack_qty,
  u.box_qty,
  case
    when s.pack_barcode is not null
      and btrim(s.pack_barcode) <> ''
      and (u.pack_qty is null or u.pack_qty <= 0)
      then 'PACK_BARCODE_WITHOUT_PACK_QTY'
    when s.box_barcode is not null
      and btrim(s.box_barcode) <> ''
      and (u.box_qty is null or u.box_qty <= 0)
      then 'BOX_BARCODE_WITHOUT_BOX_QTY'
  end as invalid_reason
from public.stocks s
left join public.stock_units u on u.stock_id = s.id
where
  (
    s.pack_barcode is not null and btrim(s.pack_barcode) <> ''
    and (u.pack_qty is null or u.pack_qty <= 0)
  )
  or
  (
    s.box_barcode is not null and btrim(s.box_barcode) <> ''
    and (u.box_qty is null or u.box_qty <= 0)
  );

-- 2) Eski CHECK constraint'leri güvenli şekilde kaldır (varsa)
alter table public.stock_units
  drop constraint if exists stock_units_pack_qty_check,
  drop constraint if exists stock_units_box_qty_check;

-- 3) pack_qty / box_qty kolonlarını nullable yap
alter table public.stock_units
  alter column pack_qty drop not null,
  alter column box_qty drop not null;

-- 4) Yeni CHECK constraint'leri ekle: NULL veya >= 1
alter table public.stock_units
  add constraint stock_units_pack_qty_check
    check (pack_qty is null or pack_qty >= 1),
  add constraint stock_units_box_qty_check
    check (box_qty is null or box_qty >= 1);

-- Test sorgulari (manuel calistirmak icin):
-- select * from public.v_invalid_stocks limit 20;
-- select column_name, is_nullable from information_schema.columns
--   where table_schema = 'public'
--     and table_name = 'stock_units'
--     and column_name in ('pack_qty','box_qty');
