-- RLS/policy ve RPC guvenligini sadece admin role ile sinirlar
-- Varsayim: JWT icinde role claim var: (current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin'

-- 1) rpc_apply_stock_movement fonksiyonunu admin role kontrolu ile yeniden tanimla
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
  v_role text;
begin
  -- JWT icinden uygulama rolunu oku
  begin
    v_role := (current_setting('request.jwt.claims', true)::json ->> 'role');
  exception when others then
    v_role := null;
  end;

  -- Sadece admin rolune izin ver
  if v_role is distinct from 'admin' then
    raise exception 'forbidden'
      using errcode = '42501'; -- insufficient_privilege
  end if;

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

-- 2) RLS: sadece admin role icin izin ver

-- RLS acik oldugundan emin ol
alter table if exists public.stocks
  enable row level security;

alter table if exists public.stock_movements
  enable row level security;

-- Eski gecici authenticated policy'leri temizle
DROP POLICY IF EXISTS stocks_authenticated_all_tmp ON public.stocks;
DROP POLICY IF EXISTS stock_movements_authenticated_all_tmp ON public.stock_movements;

-- Admin rol kontrolu icin tekrar kullanilacak ifade:
-- (current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin'

-- stocks: sadece admin SELECT ve UPDATE yapabilsin
create policy if not exists stocks_admin_select
  on public.stocks
  as permissive
  for select
  to authenticated
  using ((current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin');

create policy if not exists stocks_admin_update_quantity
  on public.stocks
  as permissive
  for update
  to authenticated
  using ((current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin')
  with check ((current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin');

-- stock_movements: sadece admin SELECT ve INSERT yapabilsin
create policy if not exists stock_movements_admin_select
  on public.stock_movements
  as permissive
  for select
  to authenticated
  using ((current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin');

create policy if not exists stock_movements_admin_insert
  on public.stock_movements
  as permissive
  for insert
  to authenticated
  with check ((current_setting('request.jwt.claims', true)::json ->> 'role') = 'admin');
