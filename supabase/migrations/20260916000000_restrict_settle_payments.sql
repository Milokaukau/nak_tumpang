-- Settlement now occurs only through the settle-payment-batch Edge Function,
-- which verifies the Stripe PaymentIntent and invoice ownership first.
DO $$
DECLARE
  target_function regprocedure;
BEGIN
  FOR target_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('settle_payments', 'finalize_tumpang_payment')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', target_function);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', target_function);
  END LOOP;
END;
$$;
