// supabase/functions/create-payment-intent/index.ts
//
// Deploy with:
//   supabase functions deploy create-payment-intent
//
// Set the secret key server-side ONLY (never in the app's .env):
//   supabase secrets set STRIPE_SECRET_KEY=sk_live_or_test_xxx
//
// The client calls this function and receives back only a `client_secret`,
// which is safe to use in Stripe's PaymentSheet. It never sees the secret key.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Verify the caller is an authenticated Supabase user.
    //    (Anonymous/unauthenticated requests should never be able to
    //    create arbitrary charges.)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Derive the charge from server-side records. The app must never
    // decide the amount it can charge, nor create a generic arbitrary amount.
    const { request_id, payment_ids } = await req.json();
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    let amountInCents: number;
    let metadata: Record<string, string>;
    let description: string;

    if (typeof request_id === "string" && request_id) {
      const { data: request, error: requestError } = await serviceClient
        .from("tumpang_request")
        .select("passenger_trip_id, fee, sub_start_date, sub_end_date, pickup_is_accepted, dropoff_is_accepted, pickup_time_is_accepted, fee_is_accepted, sub_start_is_accepted, sub_end_is_accepted")
        .eq("id", request_id)
        .maybeSingle();
      if (requestError || !request) throw new Error("Request not found.");
      if (![request.pickup_is_accepted, request.dropoff_is_accepted, request.pickup_time_is_accepted,
          request.fee_is_accepted, request.sub_start_is_accepted, request.sub_end_is_accepted].every(Boolean)) {
        throw new Error("All negotiation terms must be accepted before payment.");
      }

      const { data: trip, error: tripError } = await serviceClient
        .from("passenger_trips")
        .select("user_id, active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday")
        .eq("id", request.passenger_trip_id)
        .maybeSingle();
      if (tripError || !trip || trip.user_id !== userData.user.id) throw new Error("Request does not belong to the signed-in passenger.");

      const start = new Date(`${request.sub_start_date}T00:00:00Z`);
      const end = new Date(`${request.sub_end_date}T00:00:00Z`);
      if (Number.isNaN(start.valueOf()) || Number.isNaN(end.valueOf()) || end < start) throw new Error("Invalid subscription dates.");
      const depositEnd = new Date(Math.min(end.valueOf(), Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate() + 59)));
      const activeKeys = ["active_sunday", "active_monday", "active_tuesday", "active_wednesday", "active_thursday", "active_friday", "active_saturday"];
      let activeDays = 0;
      for (let day = new Date(start); day <= depositEnd; day.setUTCDate(day.getUTCDate() + 1)) {
        if (trip[activeKeys[day.getUTCDay()]]) activeDays++;
      }
      amountInCents = Math.round(Number(request.fee) * activeDays * 100);
      if (!Number.isSafeInteger(amountInCents) || amountInCents <= 0) throw new Error("Deposit amount must be greater than zero.");
      metadata = { payment_kind: "deposit", request_id };
      description = `Nak Tumpang deposit for request ${request_id}`;
    } else if (Array.isArray(payment_ids) && payment_ids.length > 0 &&
        payment_ids.every((id) => typeof id === "string" && id) && new Set(payment_ids).size === payment_ids.length) {
      const { data: payments, error: paymentsError } = await serviceClient
        .from("payments")
        .select("id, amount, tumpang_subscription_id")
        .in("id", payment_ids)
        .is("paid_at", null);
      if (paymentsError || !payments || payments.length !== payment_ids.length) throw new Error("One or more invoices are no longer payable.");
      const subscriptionIds = [...new Set(payments.map((payment) => payment.tumpang_subscription_id))];
      const { data: subscriptions, error: subscriptionsError } = await serviceClient
        .from("tumpang_subscription")
        .select("id, passenger_trip_id")
        .in("id", subscriptionIds);
      if (subscriptionsError || !subscriptions || subscriptions.length !== subscriptionIds.length) throw new Error("Subscription not found.");
      const tripIds = [...new Set(subscriptions.map((subscription) => subscription.passenger_trip_id))];
      const { data: trips, error: tripsError } = await serviceClient
        .from("passenger_trips")
        .select("id")
        .eq("user_id", userData.user.id)
        .in("id", tripIds);
      if (tripsError || !trips || trips.length !== tripIds.length) throw new Error("Invoices do not belong to the signed-in passenger.");
      amountInCents = Math.round(payments.reduce((total, payment) => total + Number(payment.amount), 0) * 100);
      if (!Number.isSafeInteger(amountInCents) || amountInCents <= 0) throw new Error("Invalid invoice amount.");
      const paymentKey = [...payment_ids].sort().join(",");
      metadata = { payment_kind: "invoice_batch", payment_ids: paymentKey };
      description = `Nak Tumpang invoice settlement (${payment_ids.length} items)`;
    } else {
      return new Response(JSON.stringify({ error: "A request or invoice list is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 3. Create the PaymentIntent with Stripe, using the secret key that
    //    only exists in this server-side environment.
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecretKey || !stripeSecretKey.startsWith("sk_")) {
      return new Response(JSON.stringify({ error: "Server misconfiguration: missing Stripe secret key" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const stripeResponse = await fetch("https://api.stripe.com/v1/payment_intents", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeSecretKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        amount: amountInCents.toString(),
        currency: "myr",
        "payment_method_types[]": "card",
        description,
        ...Object.fromEntries(Object.entries(metadata).map(([key, value]) => [`metadata[${key}]`, value])),
      }),
    });

    const stripeData = await stripeResponse.json();

    if (!stripeResponse.ok) {
      return new Response(JSON.stringify({ error: stripeData.error?.message ?? "Stripe error" }), {
        status: stripeResponse.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 4. Return ONLY the client_secret — never the secret key or full object.
    return new Response(JSON.stringify({ client_secret: stripeData.client_secret }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: `${err}` }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
