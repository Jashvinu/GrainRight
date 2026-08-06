import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyHmacSha256Hex } from "../_shared/razorpay.ts";

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
    headers: { "Content-Type": "application/json" },
  });
}

function serviceClient() {
  const url = text(Deno.env.get("SUPABASE_URL"));
  const key = text(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  if (!url || !key) throw new Error("Supabase service configuration is missing.");
  return createClient(url, key);
}

async function verifyRazorpayWebhookSignature(
  secret: string,
  rawBody: string,
  signature: string,
) {
  return verifyHmacSha256Hex(secret, rawBody, signature);
}

function paymentEntity(body: Json): Json {
  return record(record(record(body.payload).payment).entity);
}

function orderEntity(body: Json): Json {
  return record(record(record(body.payload).order).entity);
}

function refundEntity(body: Json): Json {
  return record(record(record(body.payload).refund).entity);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return response({ success: false, error: "Method not allowed." }, 405);
  }
  const mode = text(Deno.env.get("RAZORPAY_MODE"));
  const secret = text(Deno.env.get("RAZORPAY_SEED_WEBHOOK_SECRET")) ||
    text(Deno.env.get("RAZORPAY_WEBHOOK_SECRET"));
  if (mode !== "test" || !secret) {
    return response(
      { success: false, error: "Razorpay Test Mode webhook is not configured." },
      503,
    );
  }
  const rawBody = await req.text();
  const signature = text(req.headers.get("x-razorpay-signature"));
  const eventId = text(req.headers.get("x-razorpay-event-id"));
  if (
    !eventId ||
    !(await verifyRazorpayWebhookSignature(secret, rawBody, signature))
  ) {
    return response({ success: false, error: "Invalid signature." }, 401);
  }

  let body: Json;
  try {
    body = record(JSON.parse(rawBody));
  } catch {
    return response({ success: false, error: "Invalid JSON." }, 400);
  }
  const eventType = text(body.event);
  const supabase = serviceClient();
  const { error: insertError } = await supabase
    .from("fpc_seed_webhook_events")
    .insert({
      event_id: eventId,
      event_type: eventType,
      environment: "test",
      payload: body,
    });
  if (insertError) {
    if (text(insertError.code) === "23505") {
      return response({ success: true, duplicate: true });
    }
    throw insertError;
  }

  try {
    const payment = paymentEntity(body);
    const order = orderEntity(body);
    const refund = refundEntity(body);
    const paymentId = text(payment.id) || text(refund.payment_id);
    const orderId = text(payment.order_id) || text(order.id);
    let query = supabase.from("fpc_seed_payment_attempts").select("*");
    query = orderId
      ? query.eq("provider_order_id", orderId)
      : query.eq("provider_payment_id", paymentId);
    const { data: attempt, error: attemptError } = await query.maybeSingle();
    if (attemptError) throw attemptError;
    if (!attempt) {
      await supabase
        .from("fpc_seed_webhook_events")
        .update({
          processed_at: new Date().toISOString(),
          processing_error: "No matching seed payment attempt.",
        })
        .eq("event_id", eventId);
      return response({ success: true, ignored: true });
    }

    const amount = Number(payment.amount || order.amount_paid || order.amount);
    const currency = text(payment.currency) || text(order.currency) ||
      text(refund.currency);
    if (
      eventType !== "refund.processed" &&
      (amount !== Number(attempt.amount_subunits) ||
        currency !== text(attempt.currency))
    ) {
      throw new Error("Webhook amount or currency does not match seed order.");
    }

    const now = new Date().toISOString();
    if (eventType === "payment.captured" || eventType === "order.paid") {
      const { error: attemptSaveError } = await supabase
        .from("fpc_seed_payment_attempts")
        .update({
          provider_payment_id: paymentId || attempt.provider_payment_id,
          provider_status: text(payment.status) || "captured",
          status: "captured",
          captured_at: attempt.captured_at || now,
        })
        .eq("id", attempt.id);
      if (attemptSaveError) throw attemptSaveError;
      const { data: seedRequest, error: requestSaveError } = await supabase
        .from("fpc_seed_requests")
        .update({
          payment_status: "captured",
          razorpay_payment_id: paymentId || attempt.provider_payment_id,
          paid_at: now,
        })
        .eq("id", attempt.seed_request_id)
        .select("id, fpc_id, amount_paise")
        .maybeSingle();
      if (requestSaveError) throw requestSaveError;
      if (text(attempt.status) !== "captured" && seedRequest) {
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
    } else if (eventType === "payment.failed") {
      await supabase
        .from("fpc_seed_payment_attempts")
        .update({
          provider_payment_id: paymentId || attempt.provider_payment_id,
          provider_status: text(payment.status) || "failed",
          status: "failed",
          failure_code: text(payment.error_code),
          failure_description: text(payment.error_description),
        })
        .eq("id", attempt.id);
      await supabase
        .from("fpc_seed_requests")
        .update({ payment_status: "failed" })
        .eq("id", attempt.seed_request_id)
        .neq("payment_status", "captured");
    } else if (eventType === "refund.processed") {
      if (Number(refund.amount) !== Number(attempt.amount_subunits)) {
        throw new Error("Only a full seed payment refund is supported.");
      }
      const { error: refundError } = await supabase.rpc(
        "finalize_fpc_seed_refund",
        {
          p_seed_request_id: attempt.seed_request_id,
          p_provider_payment_id: paymentId || attempt.provider_payment_id,
          p_provider_refund_id: text(refund.id),
        },
      );
      if (refundError) throw refundError;
    }

    await supabase
      .from("fpc_seed_webhook_events")
      .update({ processed_at: now, processing_error: "" })
      .eq("event_id", eventId);
    return response({ success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("fpc_seed_webhook_events")
      .update({ processing_error: message })
      .eq("event_id", eventId);
    return response({ success: false, error: message }, 500);
  }
});
