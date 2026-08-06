import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyHmacSha256Hex } from "../_shared/razorpay.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function record(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : {};
}

function text(raw: unknown): string {
  return typeof raw === "string" ? raw.trim() : "";
}

function integer(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isSafeInteger(value) ? value : null;
}

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function paymentEntity(body: Record<string, unknown>) {
  return record(record(record(body.payload).payment).entity);
}

function orderEntity(body: Record<string, unknown>) {
  return record(record(record(body.payload).order).entity);
}

function refundEntity(body: Record<string, unknown>) {
  return record(record(record(body.payload).refund).entity);
}

function desiredStatus(
  eventType: string,
  payment: Record<string, unknown>,
  refund: Record<string, unknown>,
  amountSubunits: number,
) {
  if (eventType === "payment.captured" || eventType === "order.paid") {
    return { attempt: "captured", application: "gateway_captured" };
  }
  if (eventType === "payment.authorized") {
    return { attempt: "authorized", application: "gateway_authorized" };
  }
  if (eventType === "payment.failed") {
    return { attempt: "failed", application: "failed" };
  }
  if (eventType === "refund.processed") {
    const amountRefunded = integer(payment.amount_refunded) ??
      integer(refund.amount) ??
      0;
    return amountRefunded >= amountSubunits
      ? { attempt: "refunded", application: "gateway_refunded" }
      : { attempt: "captured", application: "gateway_captured" };
  }
  return null;
}

function preserveTerminalStatus(
  current: string,
  desired: { attempt: string; application: string },
) {
  if (current === "refunded") {
    return { attempt: "refunded", application: "gateway_refunded" };
  }
  if (current === "captured" && desired.attempt !== "refunded") {
    return { attempt: "captured", application: "gateway_captured" };
  }
  return desired;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  const webhookMode = text(Deno.env.get("RAZORPAY_MODE"));
  const webhookSecret = text(Deno.env.get("RAZORPAY_WEBHOOK_SECRET"));
  if (webhookMode !== "test" || webhookSecret.length === 0) {
    return jsonResponse(
      {
        success: false,
        error: "Razorpay Test Mode webhook is not configured.",
      },
      503,
    );
  }

  const rawBody = await req.text();
  const signature = text(req.headers.get("x-razorpay-signature"));
  const eventId = text(req.headers.get("x-razorpay-event-id"));
  if (
    eventId.length === 0 ||
    !(await verifyHmacSha256Hex(webhookSecret, rawBody, signature))
  ) {
    return jsonResponse(
      { success: false, error: "Invalid webhook signature." },
      401,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = record(JSON.parse(rawBody));
  } catch {
    return jsonResponse(
      { success: false, error: "Invalid JSON payload." },
      400,
    );
  }
  const eventType = text(body.event);
  if (eventType.length === 0) {
    return jsonResponse({ success: false, error: "Missing event type." }, 400);
  }

  const supabase = createServiceClient();
  const { error: eventInsertError } = await supabase
    .from("razorpay_webhook_events")
    .insert({
      event_id: eventId,
      environment: "test",
      event_type: eventType,
      payload: body,
    });
  if (eventInsertError) {
    if (text(eventInsertError.code) !== "23505") throw eventInsertError;
    const { data: existingEvent, error: existingEventError } = await supabase
      .from("razorpay_webhook_events")
      .select("processed_at, processing_error")
      .eq("event_id", eventId)
      .maybeSingle();
    if (existingEventError) throw existingEventError;
    if (
      text(existingEvent?.processed_at).length > 0 ||
      text(existingEvent?.processing_error).length === 0
    ) {
      return jsonResponse({ success: true, duplicate: true });
    }
  }

  try {
    const payment = paymentEntity(body);
    const order = orderEntity(body);
    const refund = refundEntity(body);
    const paymentId = text(payment.id) || text(refund.payment_id);
    const orderId = text(payment.order_id) || text(order.id);

    const recognizedEvents = [
      "payment.authorized",
      "payment.captured",
      "payment.failed",
      "order.paid",
      "refund.processed",
    ];
    if (!recognizedEvents.includes(eventType)) {
      await supabase
        .from("razorpay_webhook_events")
        .update({
          processed_at: new Date().toISOString(),
          processing_error: "",
        })
        .eq("event_id", eventId);
      return jsonResponse({ success: true, ignored: true });
    }
    if (orderId.length === 0 && paymentId.length === 0) {
      throw new Error("Webhook is missing its payment and order IDs.");
    }

    let attemptQuery = supabase
      .from("stakeholder_payment_attempts")
      .select("*");
    attemptQuery = orderId.length > 0
      ? attemptQuery.eq("provider_order_id", orderId)
      : attemptQuery.eq("provider_payment_id", paymentId);
    const { data: attempt, error: attemptError } = await attemptQuery
      .maybeSingle();
    if (attemptError) throw attemptError;
    if (!attempt || text(attempt.environment) !== "test") {
      await supabase
        .from("razorpay_webhook_events")
        .update({
          processed_at: new Date().toISOString(),
          processing_error: "No matching Razorpay Test payment attempt.",
        })
        .eq("event_id", eventId);
      return jsonResponse({ success: true, ignored: true });
    }

    const amountSubunits = Number(attempt.amount_subunits);
    const eventAmount = integer(payment.amount) ??
      integer(order.amount_paid) ??
      integer(order.amount);
    const eventCurrency = text(payment.currency) || text(order.currency) ||
      text(refund.currency);
    if (eventType === "refund.processed") {
      const refundAmount = integer(refund.amount);
      if (
        !refundAmount ||
        refundAmount > amountSubunits ||
        eventCurrency !== text(attempt.currency)
      ) {
        throw new Error("Webhook refund does not match the order.");
      }
    } else if (
      eventAmount !== amountSubunits ||
      eventCurrency !== text(attempt.currency)
    ) {
      throw new Error("Webhook amount or currency does not match the order.");
    }
    if (
      paymentId.length > 0 &&
      text(attempt.provider_payment_id).length > 0 &&
      text(attempt.provider_payment_id) !== paymentId
    ) {
      throw new Error("Webhook payment ID does not match the order.");
    }

    const requestedStatus = desiredStatus(
      eventType,
      payment,
      refund,
      amountSubunits,
    );
    if (!requestedStatus) {
      throw new Error("Recognized event has no status mapping.");
    }
    const nextStatus = preserveTerminalStatus(
      text(attempt.status),
      requestedStatus,
    );
    const now = new Date().toISOString();
    const providerStatus = eventType === "refund.processed" &&
        nextStatus.attempt === "captured"
      ? "partially_refunded"
      : text(payment.status) || text(order.status) || eventType;

    const { error: attemptSaveError } = await supabase
      .from("stakeholder_payment_attempts")
      .update({
        provider_payment_id: paymentId || attempt.provider_payment_id,
        provider_status: providerStatus,
        status: nextStatus.attempt,
        failure_code: text(payment.error_code),
        failure_description: text(payment.error_description),
        captured_at: nextStatus.attempt === "captured"
          ? attempt.captured_at || now
          : attempt.captured_at,
        refunded_at: nextStatus.attempt === "refunded"
          ? attempt.refunded_at || now
          : attempt.refunded_at,
      })
      .eq("id", attempt.id);
    if (attemptSaveError) throw attemptSaveError;

    const { error: applicationSaveError } = await supabase
      .from("stakeholder_applications")
      .update({
        razorpay_order_id: orderId || attempt.provider_order_id,
        razorpay_payment_id: paymentId || attempt.provider_payment_id,
        payment_method: "razorpay",
        payment_status: nextStatus.application,
      })
      .eq("id", attempt.application_id);
    if (applicationSaveError) throw applicationSaveError;

    const { error: applicationEventError } = await supabase
      .from("stakeholder_application_events")
      .insert({
        application_id: attempt.application_id,
        status: "submitted",
        title: nextStatus.attempt === "captured"
          ? "Razorpay Test payment captured"
          : `Razorpay Test payment ${nextStatus.attempt}`,
        note:
          "Payment status was confirmed by a signed Razorpay Test Mode webhook.",
        actor_role: "payment_gateway",
      });
    if (applicationEventError) throw applicationEventError;

    const { error: eventSaveError } = await supabase
      .from("razorpay_webhook_events")
      .update({ processed_at: now, processing_error: "" })
      .eq("event_id", eventId);
    if (eventSaveError) throw eventSaveError;

    return jsonResponse({
      success: true,
      eventId,
      paymentStatus: nextStatus.attempt,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("razorpay_webhook_events")
      .update({ processing_error: message })
      .eq("event_id", eventId);
    return jsonResponse(
      { success: false, error: "Webhook processing failed." },
      500,
    );
  }
});
