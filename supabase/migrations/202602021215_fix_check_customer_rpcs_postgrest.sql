-- Fix customer pre-auth lookup RPCs for PostgREST compatibility

-- Drop existing variants if they exist (single text argument signature)
DROP FUNCTION IF EXISTS public.check_customer_phone(text);
DROP FUNCTION IF EXISTS public.check_customer_email(text);

-- Recreate phone checker with explicit argument name and PostgREST-friendly signature
CREATE FUNCTION public.check_customer_phone(phone_e164 text)
RETURNS TABLE ("exists" boolean, is_active boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.customers c
      WHERE c.phone = trim(phone_e164)
    ) AS "exists",
    COALESCE(
      (
        SELECT c.is_active
        FROM public.customers c
        WHERE c.phone = trim(phone_e164)
        LIMIT 1
      ),
      TRUE
    ) AS is_active;
$$;

REVOKE ALL ON FUNCTION public.check_customer_phone(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_customer_phone(text) TO anon, authenticated;

-- Recreate email checker with explicit argument name and PostgREST-friendly signature
CREATE FUNCTION public.check_customer_email(email_input text)
RETURNS TABLE ("exists" boolean, is_active boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1
      FROM public.customers c
      WHERE lower(trim(c.email)) = lower(trim(email_input))
    ) AS "exists",
    COALESCE(
      (
        SELECT c.is_active
        FROM public.customers c
        WHERE lower(trim(c.email)) = lower(trim(email_input))
        LIMIT 1
      ),
      TRUE
    ) AS is_active;
$$;

REVOKE ALL ON FUNCTION public.check_customer_email(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_customer_email(text) TO anon, authenticated;
