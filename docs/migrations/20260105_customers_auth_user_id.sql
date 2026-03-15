-- Customers tablosuna Supabase auth.users ile esleme icin auth_user_id kolonu ekle
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS auth_user_id uuid;

CREATE INDEX IF NOT EXISTS idx_customers_auth_user_id
  ON public.customers(auth_user_id);
