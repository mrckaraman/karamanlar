-- Link a customer record to the current authenticated user by phone (E.164)

DROP FUNCTION IF EXISTS public.link_customer_phone_to_user(text);

CREATE OR REPLACE FUNCTION public.link_customer_phone_to_user(phone_e164 text)
RETURNS TABLE (customer_id uuid, already_linked boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_existing_auth_user_id uuid;
BEGIN
  -- Find customer by canonical phone
  SELECT c.id, c.auth_user_id
    INTO v_customer_id, v_existing_auth_user_id
  FROM public.customers c
  WHERE c.phone = btrim(phone_e164)
  LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'customer_not_found_for_phone';
  END IF;

  -- If already linked to THIS user -> idempotent success
  IF v_existing_auth_user_id = auth.uid() THEN
    RETURN QUERY SELECT v_customer_id, TRUE;
    RETURN;
  END IF;

  -- If linked to someone else -> block
  IF v_existing_auth_user_id IS NOT NULL AND v_existing_auth_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'phone_linked_to_another_user';
  END IF;

  -- Not linked -> link now
  UPDATE public.customers
  SET auth_user_id = auth.uid()
  WHERE id = v_customer_id;

  RETURN QUERY SELECT v_customer_id, FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.link_customer_phone_to_user(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.link_customer_phone_to_user(text) TO authenticated;
