-- Atomik stok hareketi uygulayan RPC
-- Not: RLS acikken calisabilmesi icin SECURITY DEFINER ve search_path ayari yapildi.
-- NOTE: Admin rolune gore daraltmak icin JWT claim kontrolleri ekle.

create or replace function public.rpc_apply_stock_movement(
  p_stock_id uuid,
  p_type text,
  p_qty numeric,
  p_note text default null
)
returns table (
  movement_id uuid,
  new_quantity numeric
)
language plpgsql
security definer
set search_path = public
as
$$
declare
  v_current_qty numeric;
  v_new_qty numeric;
  v_movement_id uuid;
begin
  -- Miktar pozitif olmali
  if p_qty <= 0 then
    raise exception 'Quantity must be greater than 0';
  end if;

  -- Gecerli hareket tipleri
  if p_type not in ('in','out','adjust') then
    raise exception 'Invalid movement type: %', p_type;
  end if;

  -- Ilgili stok satirini kilitle
  select quantity
    into v_current_qty
  from public.stocks
  where id = p_stock_id
  for update;

  if not found then
    raise exception 'Stock % not found', p_stock_id;
  end if;

  if v_current_qty is null then
    v_current_qty := 0;
  end if;

  -- Yeni miktari hesapla
  if p_type = 'in' then
    v_new_qty := v_current_qty + p_qty;
  elsif p_type = 'out' then
    v_new_qty := v_current_qty - p_qty;
    if v_new_qty < 0 then
      raise exception 'Insufficient stock. Current: %, requested: %', v_current_qty, p_qty
        using errcode = 'P0001';
    end if;
  else
    -- adjust
    v_new_qty := p_qty;
  end if;

  -- Hareket kaydini ekle
  insert into public.stock_movements (id, stock_id, movement_type, qty, note, created_by)
  values (gen_random_uuid(), p_stock_id, p_type, p_qty, p_note, auth.uid())
  returning id into v_movement_id;

  -- Stok miktarini guncelle
  update public.stocks
     set quantity = v_new_qty
   where id = p_stock_id;

  -- Sonucu geri dondur
  return query select v_movement_id, v_new_qty;
end;
$$;

-- Fonksiyon yetkileri: simdilik authenticated rolune izin ver
grant execute on function public.rpc_apply_stock_movement(uuid, text, numeric, text)
  to authenticated;

-- RLS aktif ise temel policy'ler
-- NOTE: Burayi sadece admin rolu icin daralt (JWT claim: role = ''admin'')

alter table if exists public.stocks
  enable row level security;

alter table if exists public.stock_movements
  enable row level security;

create policy if not exists stocks_authenticated_all_tmp
  on public.stocks
  as permissive
  for select, update
  to authenticated
  using (true)
  with check (true);

create policy if not exists stock_movements_authenticated_all_tmp
  on public.stock_movements
  as permissive
  for select, insert
  to authenticated
  using (true)
  with check (true);
