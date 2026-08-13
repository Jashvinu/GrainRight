import { createClient } from "npm:@supabase/supabase-js@2";
import { errorResponse, successResponse } from "../_shared/response.ts";

type Row = Record<string, unknown>;

function client() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service credentials");
  return createClient(url, key);
}

function text(value: unknown) {
  return String(value ?? "").trim();
}

async function cronAuthorized(supabase: ReturnType<typeof client>, req: Request) {
  const token = req.headers.get("x-whatsapp-dispatch-token") ?? "";
  const { data, error } = await supabase.from("whatsapp_dispatch_control")
    .select("cron_token")
    .eq("id", true)
    .maybeSingle();
  if (error) throw error;
  return token.length > 0 && token === text(data?.cron_token);
}

async function send(to: string, language: string, title: string, message: string) {
  const relayUrl = Deno.env.get("WHATSAPP_NOTIFICATION_RELAY_URL")?.trim();
  const relayToken = Deno.env.get("WHATSAPP_NOTIFICATION_RELAY_TOKEN")?.trim();
  if (!relayUrl || !relayToken) throw new Error("WhatsApp notification relay is not configured");
  const response = await fetch(relayUrl, {
    method: "POST",
    headers: { authorization: "Bearer " + relayToken, "content-type": "application/json" },
    body: JSON.stringify({ to, language, title, message }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error("WhatsApp relay failed: " + response.status + " " + JSON.stringify(body));
  return text((body as Row).providerMessageId);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);
  try {
    const supabase = client();
    if (!await cronAuthorized(supabase, req)) return errorResponse("Unauthorized dispatcher request", 401);
    const { data: control, error: controlError } = await supabase.from("whatsapp_dispatch_control")
      .select("rollout_started_at,proactive_alerts_enabled,last_dispatch_at")
      .eq("id", true)
      .maybeSingle();
    if (controlError) throw controlError;
    if (control?.proactive_alerts_enabled === false) {
      return successResponse({ sent: 0, processed: 0, paused: "disabled" }, 200, "whatsapp_notifications_paused");
    }
    const rolloutStarted = Date.parse(text(control?.rollout_started_at));
    const rolloutDays = Number.isFinite(rolloutStarted) ? Math.floor((Date.now() - rolloutStarted) / 86400000) : 0;
    const dailyCap = rolloutDays < 7 ? 0 : rolloutDays < 14 ? 20 : rolloutDays < 21 ? 50 : 100;
    if (dailyCap === 0) {
      return successResponse({ sent: 0, processed: 0, paused: "warmup", rolloutDays }, 200, "whatsapp_notifications_warming_up");
    }
    const lastDispatch = Date.parse(text(control?.last_dispatch_at));
    if (Number.isFinite(lastDispatch) && Date.now() - lastDispatch < 110000) {
      return successResponse({ sent: 0, processed: 0, paused: "rate_limit" }, 200, "whatsapp_notifications_rate_limited");
    }
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const { data: sentToday, error: sentTodayError } = await supabase.from("whatsapp_notification_outbox")
      .select("whatsapp_phone")
      .in("status", ["accepted", "sent", "delivered", "read"])
      .gte("accepted_at", today.toISOString());
    if (sentTodayError) throw sentTodayError;
    const recipientsToday = new Set((sentToday ?? []).map((row) => text(row.whatsapp_phone)));
    const reservedRecipients = new Set(recipientsToday);
    const remainingRecipients = Math.max(0, dailyCap - recipientsToday.size);
    if (remainingRecipients === 0) {
      return successResponse({ sent: 0, processed: 0, paused: "daily_cap", dailyCap }, 200, "whatsapp_notifications_daily_cap_reached");
    }
    await supabase.from("whatsapp_dispatch_control").update({ last_dispatch_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", true);
    const { data: queue, error } = await supabase.from("whatsapp_notification_outbox")
      .select("id,notification_id,whatsapp_phone,language,attempt_count,created_at")
      .in("status", ["pending", "failed"])
      .lt("attempt_count", 5)
      .order("created_at", { ascending: true })
      .limit(Math.min(6, remainingRecipients));
    if (error) throw error;
    let sent = 0;
    for (const entry of (queue ?? []) as Row[]) {
      try {
        const recipient = text(entry.whatsapp_phone);
        if (reservedRecipients.has(recipient)) continue;
        const { data: notification, error: notificationError } = await supabase
          .from("farmer_notifications")
          .select("title,message")
          .eq("id", text(entry.notification_id))
          .maybeSingle();
        if (notificationError) throw notificationError;
        if (!notification) throw new Error("Notification was not found");
        const { data: identity, error: identityError } = await supabase
          .from("whatsapp_identities")
          .select("last_seen_at,notifications_enabled")
          .eq("whatsapp_phone", text(entry.whatsapp_phone))
          .eq("role", "farmer")
          .maybeSingle();
        if (identityError) throw identityError;
        if (identity?.notifications_enabled === false) {
          await supabase.from("whatsapp_notification_outbox").update({
            status: "disabled",
            last_error: "WhatsApp alerts are disabled by the farmer",
            updated_at: new Date().toISOString(),
          }).eq("id", entry.id);
          continue;
        }
        const providerMessageId = await send(
          text(entry.whatsapp_phone),
          text(entry.language),
          text(notification.title),
          text(notification.message),
        );
        const { error: updateError } = await supabase.from("whatsapp_notification_outbox").update({
          status: "accepted",
          attempt_count: Number(entry.attempt_count ?? 0) + 1,
          provider_message_id: providerMessageId || null,
          accepted_at: new Date().toISOString(),
          last_error: "",
          updated_at: new Date().toISOString(),
        }).eq("id", entry.id);
        if (updateError) throw updateError;
        reservedRecipients.add(recipient);
        sent += 1;
      } catch (sendError) {
        const pacingLimited = String(sendError).includes(" 429 ");
        await supabase.from("whatsapp_notification_outbox").update({
          status: pacingLimited ? "pending" : "failed",
          attempt_count: Number(entry.attempt_count ?? 0) + (pacingLimited ? 0 : 1),
          last_error: String(sendError).slice(0, 1000),
          updated_at: new Date().toISOString(),
        }).eq("id", entry.id);
      }
    }
    return successResponse({ sent, processed: queue?.length ?? 0 }, 200, "whatsapp_notifications_dispatched");
  } catch (error) {
    return errorResponse("WhatsApp notification dispatch failed", 500, error);
  }
});
