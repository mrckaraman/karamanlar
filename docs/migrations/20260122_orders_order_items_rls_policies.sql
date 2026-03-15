-- RLS enable ve policy tanımları
-- Bu script Supabase Postgres üzerinde calismak uzere yazilmistir.
-- public.is_admin() fonksiyonunun boolean dondugu varsayilir.

-- RLS'yi ac
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- Var olan (ayni isimli) policy'leri temizle

-- orders icin
DROP POLICY IF EXISTS "orders_admin_all" ON public.orders;
DROP POLICY IF EXISTS "orders_customer_all" ON public.orders;

-- Supabase otomatik olusturulmus olabilecek bazi generic policy isimleri
DROP POLICY IF EXISTS "Enable read access for all users" ON public.orders;
DROP POLICY IF EXISTS "Enable insert access for authenticated users only" ON public.orders;
DROP POLICY IF EXISTS "Enable update access for authenticated users only" ON public.orders;
DROP POLICY IF EXISTS "Enable delete access for authenticated users only" ON public.orders;

-- order_items icin
DROP POLICY IF EXISTS "order_items_admin_all" ON public.order_items;
DROP POLICY IF EXISTS "order_items_customer_all" ON public.order_items;

DROP POLICY IF EXISTS "Enable read access for all users" ON public.order_items;
DROP POLICY IF EXISTS "Enable insert access for authenticated users only" ON public.order_items;
DROP POLICY IF EXISTS "Enable update access for authenticated users only" ON public.order_items;
DROP POLICY IF EXISTS "Enable delete access for authenticated users only" ON public.order_items;


-- 1) ADMIN POLICY'LERI

-- Admin: public.is_admin() true ise tum orders satirlarina full access
CREATE POLICY "orders_admin_all"
ON public.orders
AS PERMISSIVE
FOR ALL
TO authenticated
USING ( public.is_admin() )
WITH CHECK ( public.is_admin() );

-- Admin: tum order_items satirlarina full access
CREATE POLICY "order_items_admin_all"
ON public.order_items
AS PERMISSIVE
FOR ALL
TO authenticated
USING ( public.is_admin() )
WITH CHECK ( public.is_admin() );


-- 2) CUSTOMER POLICY'LERI

-- Yardimci ifade (aciklama):
-- Bir kullanici icin gecerli customer kaydi:
--   customers.auth_user_id = auth.uid()
--
-- orders.customer_id -> customers.id iliskisi varsayilmistir.

-- Customer: sadece kendi carisine ait orders kayitlari
CREATE POLICY "orders_customer_all"
ON public.orders
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = orders.customer_id
      AND c.auth_user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = orders.customer_id
      AND c.auth_user_id = auth.uid()
  )
);

-- Customer: sadece kendi order'larina ait order_items satirlari
-- order_items.order_id -> orders.id -> customers.id -> customers.auth_user_id = auth.uid()
CREATE POLICY "order_items_customer_all"
ON public.order_items
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.customers c ON c.id = o.customer_id
    WHERE o.id = order_items.order_id
      AND c.auth_user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.orders o
    JOIN public.customers c ON c.id = o.customer_id
    WHERE o.id = order_items.order_id
      AND c.auth_user_id = auth.uid()
  )
);
