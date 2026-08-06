import { createClient } from "npm:@supabase/supabase-js@2";
import {
  isRazorpayTestKeyId,
  razorpayBasicAuth,
  verifyHmacSha256Hex,
} from "../_shared/razorpay.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Json = Record<string, unknown>;

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function record(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function response(body: Json, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function serviceClient() {
  const url = text(Deno.env.get("SUPABASE_URL"));
  const key = text(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  if (!url || !key) throw new Error("Supabase service configuration is missing.");
  return createClient(url, key);
}

async function requireUser(req: Request): Promise<string | Response> {
  const token = text(req.headers.get("Authorization")).replace(/^Bearer\s+/i, "");
  if (!token) return response({ success: false, error: "Login required." }, 401);
  const { data, error } = await serviceClient().auth.getUser(token);
  if (error || !data.user || data.user.is_anonymous) {
    return response(
      { success: false, error: "A permanent account is required." },
      401,
    );
  }
  return data.user.id;
}

function razorpayConfig():
  | { keyId: string; keySecret: string }
  | Response {
  const mode = text(Deno.env.get("RAZORPAY_MODE"));
  const keyId = text(Deno.env.get("RAZORPAY_KEY_ID"));
  const keySecret = text(Deno.env.get("RAZORPAY_KEY_SECRET"));
  if (
    mode !== "test" ||
    !keyId.startsWith("rzp_test_") ||
    !isRazorpayTestKeyId(keyId) ||
    !keySecret
  ) {
    return response(
      {
        success: false,
        error: "Razorpay Test Mode is not configured.",
        code: "razorpay_test_mode_required",
      },
      503,
    );
  }
  return { keyId, keySecret };
}

async function createRazorpayOrder(
  config: { keyId: string; keySecret: string },
  seedRequest: Json,
) {
  const amount = Number(seedRequest.amount_paise);
  const requestId = text(seedRequest.id);
  const providerResponse = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      "Authorization": razorpayBasicAuth(config.keyId, config.keySecret),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount,
      currency: "INR",
      receipt: `seed-${requestId.replaceAll("-", "").slice(0, 24)}`,
      notes: {
        environment: "test",
        fpc_seed_request_id: requestId,
        farm_id: text(seedRequest.farm_id),
      },
    }),
  });
  const order = record(await providerResponse.json().catch(() => ({})));
  if (!providerResponse.ok || !text(order.id)) {
    throw new Error(
      text(record(order.error).description) || "Could not create Razorpay order.",
    );
  }
  return order;
}

async function verifyRazorpayCheckoutSignature(
  config: { keyId: string; keySecret: string },
  orderId: string,
  paymentId: string,
  signature: string,
) {
  return verifyHmacSha256Hex(
    config.keySecret,
    `${orderId}|${paymentId}`,
    signature,
  );
}

async function fetchRazorpayPayment(
  config: { keyId: string; keySecret: string },
  paymentId: string,
) {
  const providerResponse = await fetch(
    `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
    {
      headers: {
        "Authorization": razorpayBasicAuth(config.keyId, config.keySecret),
      },
    },
  );
  const payment = record(await providerResponse.json().catch(() => ({})));
  if (!providerResponse.ok) {
    throw new Error(
      text(record(payment.error).description) ||
        "Could not verify Razorpay payment.",
    );
  }
  return payment;
}

async function createOrder(userId: string, body: Json): Promise<Response> {
  const seedRequestId = text(body.seedRequestId || body.seed_request_id);
  if (!seedRequestId) {
    return response(
      { success: false, error: "Seed request is required." },
      400,
    );
  }
  const config = razorpayConfig();
  if (config instanceof Response) return config;
  const supabase = serviceClient();
  const { data: seedRequest, error: requestError } = await supabase
    .from("fpc_seed_requests")
    .select("*")
    .eq("id", seedRequestId)
    .eq("farmer_user_id", userId)
    .maybeSingle();
  if (requestError) throw requestError;
  if (!seedRequest) {
    return response({ success: false, error: "Seed request not found." }, 404);
  }
  if (
    text(seedRequest.status) !== "approved" ||
    !["awaiting_payment", "order_created", "failed"].includes(
      text(seedRequest.payment_status),
    )
  ) {
    return response(
      {
        success: false,
        error: "The FPC must approve and reserve this seed before payment.",
      },
      409,
    );
  }
  const reservationExpiry = Date.parse(text(seedRequest.reservation_expires_at));
  if (!Number.isFinite(reservationExpiry) || reservationExpiry <= Date.now()) {
    return response(
      { success: false, error: "The 24-hour seed reservation has expired." },
      409,
    );
  }
  if (
    !Number.isSafeInteger(Number(seedRequest.amount_paise)) ||
    Number(seedRequest.amount_paise) <= 0
  ) {
    return response(
      { success: false, error: "The approved seed amount is invalid." },
      409,
    );
  }

  const { data: existingAttempt, error: existingAttemptError } = await supabase
    .from("fpc_seed_payment_attempts")
    .select("*")
    .eq("seed_request_id", seedRequestId)
    .in("status", ["created", "signature_verified", "authorized"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingAttemptError) throw existingAttemptError;
  if (
    existingAttempt &&
    Number(existingAttempt.amount_subunits) === Number(seedRequest.amount_paise)
  ) {
    return response({
      success: true,
      order: {
        keyId: config.keyId,
        orderId: existingAttempt.provider_order_id,
        amountSubunits: existingAttempt.amount_subunits,
        currency: existingAttempt.currency,
        environment: "test",
      },
    });
  }

  const order = await createRazorpayOrder(config, seedRequest);
  const orderId = text(order.id);
  const { error: attemptError } = await supabase
    .from("fpc_seed_payment_attempts")
    .insert({
      fpc_id: seedRequest.fpc_id,
      seed_request_id: seedRequest.id,
      farmer_user_id: userId,
      provider_order_id: orderId,
      amount_subunits: seedRequest.amount_paise,
      currency: "INR",
      provider_status: text(order.status) || "created",
      status: "created",
    });
  if (attemptError) throw attemptError;
  const { error: requestSaveError } = await supabase
    .from("fpc_seed_requests")
    .update({
      payment_status: "order_created",
      razorpay_order_id: orderId,
    })
    .eq("id", seedRequest.id)
    .eq("payment_status", seedRequest.payment_status);
  if (requestSaveError) throw requestSaveError;

  return response({
    success: true,
    order: {
      keyId: config.keyId,
      orderId,
      amountSubunits: seedRequest.amount_paise,
      currency: "INR",
      environment: "test",
    },
  });
}

async function verifyPayment(userId: string, body: Json): Promise<Response> {
  const orderId = text(body.razorpayOrderId || body.razorpay_order_id);
  const paymentId = text(body.razorpayPaymentId || body.razorpay_payment_id);
  const signature = text(body.razorpaySignature || body.razorpay_signature);
  if (!orderId || !paymentId || !signature) {
    return response(
      { success: false, error: "Razorpay payment details are incomplete." },
      400,
    );
  }
  const config = razorpayConfig();
  if (config instanceof Response) return config;
  const supabase = serviceClient();
  const { data: attempt, error: attemptError } = await supabase
    .from("fpc_seed_payment_attempts")
    .select("*")
    .eq("provider_order_id", orderId)
    .eq("farmer_user_id", userId)
    .maybeSingle();
  if (attemptError) throw attemptError;
  if (!attempt) {
    return response({ success: false, error: "Payment order not found." }, 404);
  }
  if (
    !(await verifyRazorpayCheckoutSignature(
      config,
      orderId,
      paymentId,
      signature,
    ))
  ) {
    return response(
      { success: false, error: "Payment signature is invalid." },
      400,
    );
  }
  const payment = await fetchRazorpayPayment(config, paymentId);
  if (
    text(payment.id) !== paymentId ||
    text(payment.order_id) !== orderId ||
    Number(payment.amount) !== Number(attempt.amount_subunits) ||
    text(payment.currency) !== text(attempt.currency)
  ) {
    return response(
      { success: false, error: "Payment does not match the approved order." },
      409,
    );
  }

  const providerStatus = text(payment.status);
  const attemptStatus = providerStatus === "captured"
    ? "captured"
    : providerStatus === "authorized"
    ? "authorized"
    : providerStatus === "failed"
    ? "failed"
    : "signature_verified";
  const now = new Date().toISOString();
  const { error: attemptSaveError } = await supabase
    .from("fpc_seed_payment_attempts")
    .update({
      provider_payment_id: paymentId,
      checkout_signature: signature,
      provider_status: providerStatus,
      status: attemptStatus,
      failure_code: text(payment.error_code),
      failure_description: text(payment.error_description),
      captured_at: attemptStatus === "captured" ? now : null,
    })
    .eq("id", attempt.id);
  if (attemptSaveError) throw attemptSaveError;

  const { data: seedRequest, error: requestSaveError } = await supabase
    .from("fpc_seed_requests")
    .update({
      payment_status: attemptStatus === "captured" ? "captured" : attemptStatus,
      razorpay_payment_id: paymentId,
      paid_at: attemptStatus === "captured" ? now : null,
    })
    .eq("id", attempt.seed_request_id)
    .eq("farmer_user_id", userId)
    .select("*")
    .maybeSingle();
  if (requestSaveError) throw requestSaveError;

  if (
    attemptStatus === "captured" &&
    text(attempt.status) !== "captured" &&
    seedRequest
  ) {
    const { data: recipients, error: recipientError } = await supabase
      .from("fpc_memberships")
      .select("user_id")
      .eq("fpc_id", seedRequest.fpc_id)
      .eq("role", "fpc_admin")
      .eq("status", "active");
    if (recipientError) throw recipientError;
    if (recipients?.length) {
      const { error: notificationError } = await supabase
        .from("fpc_notifications")
        .insert(
          recipients.map((recipient) => ({
            fpc_id: seedRequest.fpc_id,
            recipient_user_id: recipient.user_id,
            event_key: "farmer_seed_payment_captured",
            title: "Farmer seed payment captured",
            body:
              `Seed request ${seedRequest.id} is paid and ready for policy acceptance and issue.`,
            data: {
              seed_request_id: seedRequest.id,
              amount_paise: seedRequest.amount_paise,
            },
          })),
        );
      if (notificationError) throw notificationError;
    }
  }

  return response({
    success: true,
    paymentStatus: attemptStatus,
    captured: attemptStatus === "captured",
    seedRequest,
  });
}

async function refundSeedRequest(
  userId: string,
  body: Json,
): Promise<Response> {
  const seedRequestId = text(body.seedRequestId || body.seed_request_id);
  if (!seedRequestId) {
    return response(
      { success: false, error: "Seed request is required." },
      400,
    );
  }
  const config = razorpayConfig();
  if (config instanceof Response) return config;
  const supabase = serviceClient();
  const { data: seedRequest, error: requestError } = await supabase
    .from("fpc_seed_requests")
    .select("*")
    .eq("id", seedRequestId)
    .maybeSingle();
  if (requestError) throw requestError;
  if (!seedRequest) {
    return response({ success: false, error: "Seed request not found." }, 404);
  }
  const { data: membership, error: membershipError } = await supabase
    .from("fpc_memberships")
    .select("id")
    .eq("fpc_id", seedRequest.fpc_id)
    .eq("user_id", userId)
    .eq("role", "fpc_admin")
    .eq("status", "active")
    .maybeSingle();
  if (membershipError) throw membershipError;
  if (!membership) {
    return response(
      { success: false, error: "Active FPC Admin membership required." },
      403,
    );
  }
  if (text(seedRequest.payment_status) !== "captured") {
    return response(
      { success: false, error: "Captured seed payment not found." },
      409,
    );
  }
  const { data: issue, error: issueError } = await supabase
    .from("fpc_seed_issues")
    .select("id,status")
    .eq("enrollment_id", seedRequest.enrollment_id)
    .neq("status", "cancelled")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (issueError) throw issueError;
  if (issue && ["delivered", "acknowledged"].includes(text(issue.status))) {
    return response(
      { success: false, error: "Delivered seed cannot be refunded." },
      409,
    );
  }
  const { data: attempt, error: attemptError } = await supabase
    .from("fpc_seed_payment_attempts")
    .select("*")
    .eq("seed_request_id", seedRequest.id)
    .eq("status", "captured")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (attemptError) throw attemptError;
  if (!attempt || !text(attempt.provider_payment_id)) {
    return response(
      { success: false, error: "Captured payment attempt not found." },
      409,
    );
  }

  const now = new Date().toISOString();
  const { error: pendingAttemptError } = await supabase
    .from("fpc_seed_payment_attempts")
    .update({ status: "refund_pending", updated_at: now })
    .eq("id", attempt.id)
    .eq("status", "captured");
  if (pendingAttemptError) throw pendingAttemptError;
  const { error: pendingRequestError } = await supabase
    .from("fpc_seed_requests")
    .update({ payment_status: "refund_pending", updated_at: now })
    .eq("id", seedRequest.id)
    .eq("payment_status", "captured");
  if (pendingRequestError) throw pendingRequestError;

  const providerResponse = await fetch(
    `https://api.razorpay.com/v1/payments/${
      encodeURIComponent(text(attempt.provider_payment_id))
    }/refund`,
    {
      method: "POST",
      headers: {
        "Authorization": razorpayBasicAuth(config.keyId, config.keySecret),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: attempt.amount_subunits,
        notes: {
          environment: "test",
          fpc_seed_request_id: seedRequest.id,
        },
      }),
    },
  );
  const refund = record(await providerResponse.json().catch(() => ({})));
  if (!providerResponse.ok || !text(refund.id)) {
    await supabase
      .from("fpc_seed_payment_attempts")
      .update({ status: "captured" })
      .eq("id", attempt.id);
    await supabase
      .from("fpc_seed_requests")
      .update({ payment_status: "captured" })
      .eq("id", seedRequest.id);
    return response(
      {
        success: false,
        error: text(record(refund.error).description) ||
          "Razorpay refund failed.",
      },
      502,
    );
  }

  const { data: finalized, error: finalizeError } = await supabase.rpc(
    "finalize_fpc_seed_refund",
    {
      p_seed_request_id: seedRequest.id,
      p_provider_payment_id: attempt.provider_payment_id,
      p_provider_refund_id: refund.id,
    },
  );
  if (finalizeError) throw finalizeError;
  return response({ success: true, refunded: true, seedRequest: finalized });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return response({ success: false, error: "Method not allowed." }, 405);
  }
  try {
    const user = await requireUser(req);
    if (user instanceof Response) return user;
    const body = record(await req.json());
    const action = text(body.action);
    if (action === "create_order") return await createOrder(user, body);
    if (action === "verify_payment") return await verifyPayment(user, body);
    if (action === "refund_seed_request") {
      return await refundSeedRequest(user, body);
    }
    return response({ success: false, error: "Unknown action." }, 400);
  } catch (error) {
    return response(
      {
        success: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
