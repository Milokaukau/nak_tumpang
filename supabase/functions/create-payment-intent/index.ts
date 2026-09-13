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

    // 2. Parse and validate the request body.
    const { amount, currency, description } = await req.json();
    if (typeof amount !== "number" || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid amount" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountInCents = Math.round(amount * 100);

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
        currency: currency ?? "myr",
        "payment_method_types[]": "card",
        description: description ?? `Nak Tumpang payment (user ${userData.user.id})`,
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