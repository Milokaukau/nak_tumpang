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

    const { request_id, payment_intent_id } = await req.json();
    if (typeof request_id !== "string" || !request_id ||
        typeof payment_intent_id !== "string" || !payment_intent_id.startsWith("pi_")) {
      return json({ error: "Invalid deposit finalization request" }, 400);
    }

    const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: request, error: requestError } = await service
      .from("tumpang_request")
      .select("passenger_trip_id")
      .eq("id", request_id)
      .maybeSingle();
    if (requestError || !request) return json({ error: "Request not found" }, 404);
    const { data: trip, error: tripError } = await service
      .from("passenger_trips")
      .select("user_id")
      .eq("id", request.passenger_trip_id)
      .maybeSingle();
    if (tripError || !trip || trip.user_id !== auth.user.id) return json({ error: "Request does not belong to the signed-in passenger" }, 403);

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) return json({ error: "Server misconfiguration" }, 500);
    const stripeResponse = await fetch(`https://api.stripe.com/v1/payment_intents/${payment_intent_id}`, {
      headers: { Authorization: `Bearer ${stripeKey}` },
    });
    const paymentIntent = await stripeResponse.json();
    if (!stripeResponse.ok || paymentIntent.status !== "succeeded" || paymentIntent.currency !== "myr" ||
        paymentIntent.metadata?.payment_kind !== "deposit" || paymentIntent.metadata?.request_id !== request_id ||
        !Number.isSafeInteger(paymentIntent.amount_received) || paymentIntent.amount_received <= 0) {
      return json({ error: "Deposit payment could not be verified" }, 400);
    }

    const { data: subscriptionId, error: finalizeError } = await service.rpc("finalize_tumpang_payment", {
      p_request_id: request_id,
      p_payment_intent_id: payment_intent_id,
      p_deposit: paymentIntent.amount_received / 100,
    });
    if (finalizeError || !subscriptionId) throw finalizeError ?? new Error("Finalization did not return a subscription id");
    return json({ subscription_id: subscriptionId.toString() });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unable to finalize deposit" }, 500);
  }
});
