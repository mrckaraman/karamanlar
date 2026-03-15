-- Normalize customer pre-auth lookup RPCs for phone/email

-- Drop existing variants if they exist
DROP FUNCTION IF EXISTS public.check_customer_phone(text);
DROP FUNCTION IF EXISTS public.check_customer_email(text);

-- Recreate phone checker as returns (exists, is_active)
CREATE OR REPLACE FUNCTION public.check_customer_phone(phone_e164 text)
RETURNS TABLE (exists boolean, is_active boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.customers c WHERE c.phone = phone_e164
    ) AS exists,
    COALESCE(
      (SELECT c.is_active FROM public.customers c WHERE c.phone = phone_e164 LIMIT 1),
      TRUE
    ) AS is_active;
$$;

REVOKE ALL ON FUNCTION public.check_customer_phone(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_customer_phone(text) TO anon, authenticated;

-- Create email checker with same pattern
CREATE OR REPLACE FUNCTION public.check_customer_email(email_input text)
RETURNS TABLE (exists boolean, is_active boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.customers c WHERE lower(c.email) = lower(email_input)
    ) AS exists,
    COALESCE(
      (SELECT c.is_active FROM public.customers c WHERE lower(c.email) = lower(email_input) LIMIT 1),
      TRUE
    ) AS is_active;
$$;

REVOKE ALL ON FUNCTION public.check_customer_email(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_customer_email(text) TO anon, authenticated;
