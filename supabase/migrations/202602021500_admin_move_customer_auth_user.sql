-- Admin tool: move a customer's auth_user_id to a specific auth user.
-- Used by admin_app screen to fix phone-linked accounts.

CREATE OR REPLACE FUNCTION public.admin_move_customer_auth_user(
  customer_id uuid,
  target_auth_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_uid uuid;
BEGIN
  v_caller_uid := auth.uid();
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Only admin users are allowed to move customer auth links.
  IF NOT EXISTS (
    SELECT 1
    FROM public.admin_users au
    WHERE au.user_id = v_caller_uid
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.customers
  SET auth_user_id = target_auth_user_id
  WHERE id = customer_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_move_customer_auth_user(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_move_customer_auth_user(uuid, uuid) TO authenticated;
