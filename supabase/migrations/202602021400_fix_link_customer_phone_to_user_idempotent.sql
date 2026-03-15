-- Make link_customer_phone_to_user idempotent and return a result row
-- so "already linked to same user" is not an error.

CREATE OR REPLACE FUNCTION public.link_customer_phone_to_user(phone_e164 text)
RETURNS TABLE (customer_id uuid, already_linked boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid;
  v_customer_id uuid;
  v_existing_uid uuid;
  v_phone text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  v_phone := btrim(phone_e164);

  SELECT c.id, c.auth_user_id
    INTO v_customer_id, v_existing_uid
  FROM public.customers c
  WHERE c.phone = v_phone
  LIMIT 1;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'customer_not_found_for_phone';
  END IF;

  -- If already linked to SAME user => success (already_linked = true)
  IF v_existing_uid IS NOT NULL AND v_existing_uid = v_uid THEN
    RETURN QUERY SELECT v_customer_id, TRUE;
    RETURN;
  END IF;

  -- If linked to ANOTHER user => error
  IF v_existing_uid IS NOT NULL AND v_existing_uid <> v_uid THEN
    RAISE EXCEPTION 'phone_linked_to_another_user';
  END IF;

  -- Not linked yet => link it
  UPDATE public.customers
  SET auth_user_id = v_uid
  WHERE id = v_customer_id;

  RETURN QUERY SELECT v_customer_id, FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.link_customer_phone_to_user(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.link_customer_phone_to_user(text) TO authenticated;
