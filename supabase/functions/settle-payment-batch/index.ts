import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

async function ownedUnpaidPayments(service: ReturnType<typeof createClient>, userId: string, paymentIds: string[]) {
  const { data: payments, error: paymentError } = await service
    .from("payments")
    .select("id, amount, tumpang_subscription_id")
    .in("id", paymentIds)
    .is("paid_at", null);
  if (paymentError || !payments || payments.length !== paymentIds.length) {
    throw new Error("One or more invoices are no longer payable.");
  }

  const subscriptionIds = [...new Set(payments.map((payment) => payment.tumpang_subscription_id))];
  const { data: subscriptions, error: subscriptionError } = await service
    .from("tumpang_subscription")
    .select("id, passenger_trip_id")
    .in("id", subscriptionIds);
  if (subscriptionError || !subscriptions || subscriptions.length !== subscriptionIds.length) {
    throw new Error("Subscription not found.");
  }

  const tripIds = [...new Set(subscriptions.map((subscription) => subscription.passenger_trip_id))];
  const { data: trips, error: tripError } = await service
    .from("passenger_trips")
    .select("id")
    .eq("user_id", userId)
    .in("id", tripIds);
  if (tripError || !trips || trips.length !== tripIds.length) {
    throw new Error("Invoices do not belong to the signed-in passenger.");
  }

  const amount = payments.reduce((total, payment) => total + Number(payment.amount), 0);
  return { amount, payments };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const authClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: auth, error: authError } = await authClient.auth.getUser();
    if (authError || !auth.user) return json({ error: "Unauthorized" }, 401);

    const { payment_ids, payment_intent_id } = await req.json();
    if (!Array.isArray(payment_ids) || payment_ids.length === 0 ||
        payment_ids.some((id) => typeof id !== "string" || !id) ||
        new Set(payment_ids).size !== payment_ids.length ||
        typeof payment_intent_id !== "string" || !payment_intent_id.startsWith("pi_")) {
      return json({ error: "Invalid payment settlement request" }, 400);
    }

    const service = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { amount } = await ownedUnpaidPayments(service, auth.user.id, payment_ids);

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) return json({ error: "Server misconfiguration" }, 500);
    const stripeResponse = await fetch(`https://api.stripe.com/v1/payment_intents/${payment_intent_id}`, {
      headers: { Authorization: `Bearer ${stripeKey}` },
    });
    const paymentIntent = await stripeResponse.json();
    const paymentKey = [...payment_ids].sort().join(",");
    if (!stripeResponse.ok || paymentIntent.status !== "succeeded" ||
        paymentIntent.currency !== "myr" || paymentIntent.amount_received !== Math.round(amount * 100) ||
        paymentIntent.metadata?.payment_kind !== "invoice_batch" ||
        paymentIntent.metadata?.payment_ids !== paymentKey) {
      return json({ error: "Payment could not be verified" }, 400);
    }

    // Persist the verified intent before settlement. If settlement is retried
    // after a transient failure, it still uses this same Stripe charge.
    const { error: updateError } = await service
      .from("payments")
      .update({ payment_intent_id })
      .in("id", payment_ids);
    if (updateError) throw updateError;
    const { error: settleError } = await service.rpc("settle_payments", { p_payment_ids: payment_ids });
    if (settleError) throw settleError;

    return json({ ok: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unable to settle payment" }, 500);
  }
});
