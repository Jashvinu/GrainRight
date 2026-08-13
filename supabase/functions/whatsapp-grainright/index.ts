import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { normalizePhone, text } from "../_shared/farmer-links.ts";

type Row = Record<string, unknown>;
type Identity = {
  whatsapp_phone: string;
  user_id: string;
  role: "farmer" | "fpc";
  farmer_id: string | null;
  fpc_id: string | null;
  language: "en" | "hi" | "mr";
};

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service credentials");
  return createClient(url, key);
}

function object(raw: unknown): Row {
  return raw != null && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Row
    : {};
}

function language(raw: unknown): "en" | "hi" | "mr" {
  const value = text(raw).toLowerCase();
  return value === "hi" || value === "mr" ? value : "en";
}

function bridgeAuthorized(req: Request): boolean {
  const expected = Deno.env.get("GRAINRIGHT_WHATSAPP_API_TOKEN")?.trim() ?? "";
  const received = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  return expected.length >= 24 && received.length === expected.length &&
    received === expected;
}

async function farmerIdentity(supabase: ReturnType<typeof serviceClient>, phone: string, preferredLanguage: "en" | "hi" | "mr") {
  const values = [phone, `91${phone}`, `+91${phone}`];
  const { data, error } = await supabase
    .from("farmer_phone_profiles")
    .select("user_id,farmer_id,phone,status")
    .in("phone", values)
    .eq("status", "active")
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  if (!data?.user_id || !data?.farmer_id) return null;
  const identity = {
    whatsapp_phone: phone,
    user_id: String(data.user_id),
    role: "farmer",
    farmer_id: String(data.farmer_id),
    fpc_id: null,
    language: preferredLanguage,
    last_seen_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  const { error: upsertError } = await supabase.from("whatsapp_identities")
    .upsert(identity, { onConflict: "whatsapp_phone,role" });
  if (upsertError) throw upsertError;
  return identity as unknown as Identity;
}

async function activeIdentity(supabase: ReturnType<typeof serviceClient>, phone: string): Promise<Identity | null> {
  const { data, error } = await supabase.from("whatsapp_identities")
    .select("whatsapp_phone,user_id,role,farmer_id,fpc_id,language")
    .eq("whatsapp_phone", phone)
    .order("last_seen_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data ? data as Identity : null;
}

async function requireFarmer(supabase: ReturnType<typeof serviceClient>, phone: string, preferredLanguage: "en" | "hi" | "mr") {
  const existing = await activeIdentity(supabase, phone);
  if (existing?.role === "farmer") return existing;
  const linked = await farmerIdentity(supabase, phone, preferredLanguage);
  if (!linked) throw new HttpError("This WhatsApp number is not linked to an active GrainRight farmer account.", 403);
  return linked;
}

class HttpError extends Error {
  constructor(message: string, readonly status: number, readonly details: Row = {}) { super(message); }
}

async function farmsFor(supabase: ReturnType<typeof serviceClient>, identity: Identity) {
  const { data, error } = await supabase.from("farms")
    .select("id,name,crop,variety,location_label,area_hectares,area_acres,current_status,current_status_stage,current_status_updated_at,sowing_date")
    .eq("user_id", identity.user_id)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

async function resolveFarm(supabase: ReturnType<typeof serviceClient>, identity: Identity, rawFarm: unknown) {
  const farms = await farmsFor(supabase, identity);
  const requested = text(rawFarm);
  const farm = requested.length === 0
    ? farms[0]
    : farms.find((item) => String(item.id) === requested || String(item.name).toLowerCase() === requested.toLowerCase());
  if (!farm) {
    throw new HttpError("Choose one of your linked farms first.", 404, {
      farms: farms.slice(0, 8).map((item) => ({
        id: item.id,
        name: item.name,
        crop: item.crop,
        location_label: item.location_label,
      })),
    });
  }
  return farm as Row;
}

async function saveSession(supabase: ReturnType<typeof serviceClient>, phone: string, body: Row, identity: Identity | null) {
  const row = {
    whatsapp_phone: phone,
    language: language(body.language ?? identity?.language),
    role: identity?.role ?? null,
    selected_farm_id: text(body.selectedFarmId ?? body.selected_farm_id) || null,
    flow: text(body.flow),
    draft: object(body.draft),
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase.from("whatsapp_chat_sessions").upsert(row);
  if (error) throw error;
  return row;
}

async function importWhatsAppMedia(supabase: ReturnType<typeof serviceClient>, identity: Identity, body: Row) {
  const mediaId = text(body.mediaId ?? body.media_id);
  const kind = text(body.kind) === "moisture" ? "moisture" : "grain";
  const inlineBase64 = text(body.mediaBase64 ?? body.media_base64).replace(/^data:[^;]+;base64,/, "");
  let bytes: Uint8Array;
  let mimeType = text(body.mediaMimeType ?? body.media_mime_type) || "image/jpeg";
  if (inlineBase64) {
    try {
      bytes = Uint8Array.from(atob(inlineBase64), (character) => character.charCodeAt(0));
    } catch {
      throw new HttpError("The WhatsApp image payload is invalid.", 400);
    }
  } else {
    if (!mediaId) throw new HttpError("A WhatsApp image is required.", 400);
    const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
    const graphVersion = Deno.env.get("GRAPH_API_VERSION") || "v25.0";
    if (!accessToken) throw new HttpError("WhatsApp media access is not configured.", 503);
    const metadataResponse = await fetch(`https://graph.facebook.com/${graphVersion}/${mediaId}`, {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    if (!metadataResponse.ok) throw new HttpError("Could not load the WhatsApp image.", 422);
    const metadata = object(await metadataResponse.json());
    const downloadUrl = text(metadata.url);
    if (!downloadUrl) throw new HttpError("WhatsApp image URL was missing.", 422);
    const imageResponse = await fetch(downloadUrl, { headers: { authorization: `Bearer ${accessToken}` } });
    if (!imageResponse.ok) throw new HttpError("Could not download the WhatsApp image.", 422);
    mimeType = imageResponse.headers.get("content-type") || "image/jpeg";
    bytes = new Uint8Array(await imageResponse.arrayBuffer());
  }
  if (!mimeType.startsWith("image/")) throw new HttpError("Only image attachments are supported.", 415);
  const extension = mimeType.includes("png") ? "png" : "jpg";
  const bucket = kind === "moisture" ? "moisture-images" : "grain-images";
  const path = `${identity.user_id}/whatsapp/${crypto.randomUUID()}.${extension}`;
  if (bytes.byteLength > 12 * 1024 * 1024) throw new HttpError("The image is too large. Send an image under 12 MB.", 413);
  const { error } = await supabase.storage.from(bucket).upload(path, bytes, { contentType: mimeType, upsert: false });
  if (error) throw error;
  return { path, bucket, mimeType };
}

async function invokeInternal(name: string, body: Row) {
  const url = Deno.env.get("SUPABASE_URL");
  const token = Deno.env.get("GRAINRIGHT_WHATSAPP_INTERNAL_TOKEN");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !token || !anonKey) {
    throw new HttpError("WhatsApp internal service bridge is not configured.", 503);
  }
  const response = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${anonKey}`,
      apikey: anonKey,
      "x-grainright-whatsapp-internal": token,
    },
    body: JSON.stringify({ ...body, whatsapp_internal: true }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new HttpError(text((data as Row).message) || `${name} failed`, response.status);
  return data;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);
  if (!bridgeAuthorized(req)) return errorResponse("Unauthorized WhatsApp bridge request", 401);

  try {
    const body = object(await req.json());
    const action = text(body.action).toLowerCase();
    const phone = normalizePhone(body.phone);
    const phoneOptional = ["webhook_prepare", "webhook_complete", "webhook_fail", "delivery_status"].includes(action);
    if (!phoneOptional && phone.length !== 10) return errorResponse("A valid WhatsApp phone number is required", 400);
    const preferredLanguage = language(body.language);
    const supabase = serviceClient();

    if (action === "health") {
      return successResponse({ service: "whatsapp-grainright" }, 200, "whatsapp_gateway_healthy");
    }

    if (action === "session_load") {
      const { data, error } = await supabase.from("whatsapp_chat_sessions")
        .select("language,role,flow,draft,bot_state,verified,updated_at")
        .eq("whatsapp_phone", phone)
        .maybeSingle();
      if (error) throw error;
      const identity = await activeIdentity(supabase, phone);
      const fallback = data ? { language: data.language, role: data.role, flow: data.flow, draft: data.draft, verified: data.verified } : null;
      const persisted = object(data?.bot_state);
      const session = data ? {
        ...(Object.keys(persisted).length > 0 ? persisted : fallback),
        verified: Boolean(identity) || Boolean(data.verified),
        role: identity?.role ?? data.role,
      } : null;
      return successResponse({ session }, 200, "whatsapp_session_loaded");
    }

    if (action === "session_save") {
      const identity = await activeIdentity(supabase, phone);
      const snapshot = object(body.session);
      const row = {
        whatsapp_phone: phone,
        language: language(snapshot.language ?? identity?.language),
        role: identity?.role ?? (text(snapshot.role) || null),
        verified: Boolean(identity) || snapshot.verified === true,
        bot_state: snapshot,
        updated_at: new Date().toISOString(),
      };
      const { error } = await supabase.from("whatsapp_chat_sessions").upsert(row);
      if (error) throw error;
      return successResponse({ session: snapshot }, 200, "whatsapp_session_saved");
    }

    if (action === "webhook_claim") {
      const eventKey = text(body.eventKey ?? body.event_key);
      if (!eventKey) return errorResponse("A webhook event key is required.", 400);
      const { data, error } = await supabase.rpc("claim_whatsapp_webhook_event", {
        p_event_key: eventKey,
        p_provider: text(body.provider) || "openwa",
        p_event_type: text(body.event),
        p_message_id: text(body.messageId ?? body.message_id) || null,
        p_whatsapp_phone: phone,
      });
      if (error) throw error;
      return successResponse(object(data), 200, "whatsapp_webhook_claimed");
    }

    if (action === "webhook_prepare") {
      const eventKey = text(body.eventKey ?? body.event_key);
      const reply = text(body.reply);
      if (!eventKey || !reply) return errorResponse("An event key and reply are required.", 400);
      const { error } = await supabase.from("whatsapp_webhook_events").update({
        status: "reply_pending",
        reply_text: reply,
        updated_at: new Date().toISOString(),
      }).eq("event_key", eventKey).eq("status", "processing");
      if (error) throw error;
      return successResponse({ eventKey, status: "reply_pending" }, 200, "whatsapp_webhook_reply_prepared");
    }

    if (action === "webhook_complete" || action === "webhook_fail") {
      const eventKey = text(body.eventKey ?? body.event_key);
      let status = action === "webhook_complete" ? "completed" : "failed";
      if (action === "webhook_fail") {
        const { data: existing, error: existingError } = await supabase.from("whatsapp_webhook_events")
          .select("reply_text")
          .eq("event_key", eventKey)
          .maybeSingle();
        if (existingError) throw existingError;
        if (text(existing?.reply_text)) status = "reply_pending";
      }
      const { error } = await supabase.from("whatsapp_webhook_events").update({
        status,
        provider_message_id: text(body.providerMessageId ?? body.provider_message_id) || null,
        last_error: action === "webhook_fail" ? text(body.error).slice(0, 1000) : "",
        processed_at: action === "webhook_complete" ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      }).eq("event_key", eventKey);
      if (error) throw error;
      return successResponse({ eventKey, status }, 200, "whatsapp_webhook_updated");
    }

    if (action === "notification_preference") {
      const enabled = body.enabled === true;
      const identity = await activeIdentity(supabase, phone);
      if (!identity) return errorResponse("Verify this WhatsApp number before changing alerts.", 403);
      const { error } = await supabase.from("whatsapp_identities").update({
        notifications_enabled: enabled,
        notifications_updated_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("whatsapp_phone", phone);
      if (error) throw error;
      return successResponse({ enabled }, 200, "whatsapp_notification_preference_saved");
    }

    if (action === "delivery_status") {
      const providerMessageId = text(body.providerMessageId ?? body.provider_message_id);
      if (!providerMessageId) return successResponse({ updated: false }, 200, "whatsapp_delivery_ignored");
      const deliveryStatus = text(body.deliveryStatus ?? body.delivery_status);
      const status = deliveryStatus === "failed" ? "failed" : deliveryStatus === "read" ? "read" : deliveryStatus === "delivered" ? "delivered" : "sent";
      const patch: Row = {
        status,
        last_error: status === "failed" ? text(body.error).slice(0, 1000) : "",
        updated_at: new Date().toISOString(),
      };
      if (status === "delivered" || status === "read") patch.delivered_at = new Date().toISOString();
      if (status === "read") patch.read_at = new Date().toISOString();
      const { data, error } = await supabase.from("whatsapp_notification_outbox")
        .update(patch)
        .eq("provider_message_id", providerMessageId)
        .select("id");
      if (error) throw error;
      return successResponse({ updated: (data ?? []).length > 0, status }, 200, "whatsapp_delivery_updated");
    }

    if (action === "set_language") {
      const identity = await activeIdentity(supabase, phone);
      const session = await saveSession(supabase, phone, body, identity);
      if (identity) await supabase.from("whatsapp_identities").update({ language: preferredLanguage, last_seen_at: new Date().toISOString() }).eq("whatsapp_phone", phone).eq("role", identity.role);
      return successResponse({ session }, 200, "whatsapp_language_saved");
    }

    if (action === "request_otp" || action === "verify_otp") {
      const identity = await farmerIdentity(supabase, phone, preferredLanguage);
      if (!identity) return errorResponse("This WhatsApp number is not registered as an active farmer number.", 403);
      await saveSession(supabase, phone, body, identity);
      return successResponse({ verified: true, role: "farmer", farmerId: identity.farmer_id }, 200, "whatsapp_farmer_verified");
    }

    if (action === "fpc_request_otp") {
      const email = text(body.email).toLowerCase();
      const { data, error } = await supabase.from("fpc_memberships").select("user_id,fpc_id,email,status,role").eq("email", email).eq("status", "active").maybeSingle();
      if (error) throw error;
      if (!data?.user_id) return errorResponse("No active FPC account was found for this email.", 404);
      // Delivery is delegated to the configured mail provider so credentials never reach WhatsApp.
      const sender = Deno.env.get("WHATSAPP_FPC_OTP_SENDER_URL")?.trim();
      if (!sender) return errorResponse("FPC email verification is not configured.", 503);
      const code = String(Math.floor(100000 + Math.random() * 900000));
      await supabase.from("whatsapp_chat_sessions").upsert({ whatsapp_phone: phone, language: preferredLanguage, role: "fpc", flow: "fpc_email_otp", draft: { email, code_hash: await hash(code), user_id: data.user_id, fpc_id: data.fpc_id }, updated_at: new Date().toISOString() });
      const sent = await fetch(sender, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, code }) });
      if (!sent.ok) throw new HttpError("Could not send the FPC verification email.", 502);
      return successResponse({ sent: true }, 200, "whatsapp_fpc_otp_sent");
    }

    if (action === "fpc_verify_otp") {
      const { data: session, error } = await supabase.from("whatsapp_chat_sessions")
        .select("draft,language")
        .eq("whatsapp_phone", phone)
        .eq("flow", "fpc_email_otp")
        .maybeSingle();
      if (error) throw error;
      const draft = object(session?.draft);
      if (!session || text(draft.code_hash) !== await hash(text(body.otp))) {
        return errorResponse("The FPC verification code is not valid.", 403);
      }
      const identity = {
        whatsapp_phone: phone,
        user_id: text(draft.user_id),
        role: "fpc",
        farmer_id: null,
        fpc_id: text(draft.fpc_id),
        email: text(draft.email),
        language: language(session.language),
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      const { error: upsertError } = await supabase.from("whatsapp_identities")
        .upsert(identity, { onConflict: "whatsapp_phone,role" });
      if (upsertError) throw upsertError;
      await saveSession(supabase, phone, { language: identity.language, flow: "", draft: {} }, identity as unknown as Identity);
      return successResponse({ verified: true, role: "fpc", fpcId: identity.fpc_id }, 200, "whatsapp_fpc_verified");
    }

    if (action === "farm_list") {
      const identity = await requireFarmer(supabase, phone, preferredLanguage);
      return successResponse({ farms: await farmsFor(supabase, identity) }, 200, "whatsapp_farms_listed");
    }

    if (action === "market_rates") {
      const query = text(body.query);
      let officialRequest = supabase.from("apmc_market_rate_history")
        .select("commodity,market_name:market,modal_price,min_price,max_price,arrival_date,state,district,variety,grade")
        .order("arrival_date", { ascending: false })
        .order("market", { ascending: true })
        .limit(10);
      const officialFilter = query.replace(/[,()%]/g, " ").trim();
      if (officialFilter.length > 0) {
        officialRequest = officialRequest.or([
          `commodity.ilike.%${officialFilter}%`,
          `market.ilike.%${officialFilter}%`,
          `district.ilike.%${officialFilter}%`,
          `state.ilike.%${officialFilter}%`,
        ].join(","));
      }
      const { data: officialRates, error: officialError } = await officialRequest;
      if (officialError) throw officialError;
      if ((officialRates ?? []).length > 0) {
        return successResponse({
          rates: officialRates ?? [],
          source: "Government of India AGMARKNET via data.gov.in",
          unit: "INR/quintal",
        }, 200, "whatsapp_official_market_rates");
      }

      let request = supabase.from("apmc_market_rates")
        .select("commodity:crop,market_name,modal_price:modal_rate,min_price:min_rate,max_price:max_rate,arrival_date:rate_date,demand,trend,note")
        .eq("active", true)
        .order("rate_date", { ascending: false })
        .limit(10);
      if (query.length > 0) request = request.ilike("crop", `%${query}%`);
      const { data, error } = await request;
      if (error) throw error;
      return successResponse({ rates: data ?? [], source: "GrainRight curated rates", unit: "INR/quintal" }, 200, "whatsapp_market_rates");
    }

    const existingIdentity = await activeIdentity(supabase, phone);
    if (existingIdentity?.role === "fpc") {
      const { data: membership, error: membershipError } = await supabase
        .from("fpc_memberships")
        .select("fpc_id,role,status,display_name,email")
        .eq("user_id", existingIdentity.user_id)
        .eq("fpc_id", existingIdentity.fpc_id)
        .eq("status", "active")
        .maybeSingle();
      if (membershipError) throw membershipError;
      if (!membership) return errorResponse("Your FPC membership is no longer active.", 403);
      if (action === "fpc_dashboard") {
        const { data: fpc, error } = await supabase.from("fpcs")
          .select("id,name,status")
          .eq("id", existingIdentity.fpc_id)
          .maybeSingle();
        if (error) throw error;
        const { count, error: countError } = await supabase.from("fpc_memberships")
          .select("id", { count: "exact", head: true })
          .eq("fpc_id", existingIdentity.fpc_id)
          .eq("status", "active");
        if (countError) throw countError;
        return successResponse({ fpc, membership, activeMembers: count ?? 0 }, 200, "whatsapp_fpc_dashboard");
      }
      if (action === "fpc_members") {
        const { data, error } = await supabase.from("fpc_memberships")
          .select("id,display_name,email,phone,role,status,created_at")
          .eq("fpc_id", existingIdentity.fpc_id)
          .order("created_at", { ascending: false })
          .limit(50);
        if (error) throw error;
        return successResponse({ memberships: data ?? [] }, 200, "whatsapp_fpc_members");
      }
      if (action === "fpc_alerts") {
        const { data, error } = await supabase.from("fpc_notifications")
          .select("id,title,message,type,created_at,read_at")
          .eq("fpc_id", existingIdentity.fpc_id)
          .order("created_at", { ascending: false })
          .limit(20);
        if (error) throw error;
        return successResponse({ alerts: data ?? [] }, 200, "whatsapp_fpc_alerts");
      }
      return errorResponse("This FPC WhatsApp service is not available yet.", 400);
    }

    const identity = await requireFarmer(supabase, phone, preferredLanguage);
    await supabase.from("whatsapp_identities").update({ last_seen_at: new Date().toISOString(), language: preferredLanguage }).eq("whatsapp_phone", phone).eq("role", "farmer");

    if (action === "farm_alerts") {
      const { data, error } = await supabase.from("farmer_notifications").select("id,title,message,type,severity,created_at,farm_id,read_at").eq("farmer_id", identity.farmer_id).order("created_at", { ascending: false }).limit(20);
      if (error) throw error;
      return successResponse({ alerts: data ?? [] }, 200, "whatsapp_farm_alerts");
    }

    if (action === "farm_summary") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const [snapshots, status] = await Promise.all([
        supabase.from("farm_data_snapshots").select("created_at,recommendation,disease_risk,weather,crop_cycle").eq("farm_id", farm.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
        supabase.from("farm_status_updates").select("status_text,growth_stage,created_at").eq("farm_id", farm.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (snapshots.error) throw snapshots.error;
      if (status.error) throw status.error;
      return successResponse({ farm, snapshot: snapshots.data ?? null, latestStatus: status.data ?? null }, 200, "whatsapp_farm_summary");
    }

    if (action === "status_update") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const statusText = text(body.statusText);
      if (!statusText) return errorResponse("Status text is required.", 400);
      const response = await invokeInternal("farm-status-update", {
        phone, farmerId: identity.farmer_id, farmId: farm.id, farmName: farm.name,
        crop: farm.crop, variety: farm.variety, stage: text(body.stage) || text(farm.current_status_stage) || "field_update",
        statusText, language: preferredLanguage, source: "whatsapp_chat",
        whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_status_updated");
    }

    if (action === "ai_chat") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const question = text(body.question);
      if (!question) return errorResponse("A question is required.", 400);
      const response = await invokeInternal("farm-assistant-chat", {
        phone, farmerId: identity.farmer_id, farmId: farm.id, question, language: preferredLanguage,
        source: "ai_chat", whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_ai_chat");
    }

    if (action === "grading_media") {
      return successResponse(await importWhatsAppMedia(supabase, identity, body), 201, "whatsapp_grading_media_saved");
    }

    if (action === "grading_submit") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const response = await invokeInternal("grain-grade", {
        farmer_phone: phone, farmer_id: identity.farmer_id, farm_id: farm.id, actor_role: "farmer",
        grain_image_path: text(body.grainImagePath), moisture_image_path: text(body.moistureImagePath) || null,
        manual_moisture_percent: body.manualMoisturePercent ?? null, crop_type: text(body.cropType) || text(farm.crop) || "finger_millets",
        source: "whatsapp", whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_grading_complete");
    }

    if (action === "farm_setup_link") {
      const appUrl = Deno.env.get("GRAINRIGHT_APP_URL")?.trim();
      if (appUrl) {
        return successResponse({
          url: `${appUrl.replace(/\/$/, "")}/farmer/farm-setup?whatsapp=${encodeURIComponent(phone)}`,
          route: "/farmer/farm-setup",
        }, 200, "whatsapp_farm_setup_link");
      }
      return successResponse({
        route: "/farmer/farm-setup",
        instruction: "Open GrainRight, choose Farms, then Add farm to draw the field boundary.",
      }, 200, "whatsapp_farm_setup_route");
    }

    if (action === "daily_tasks") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const { data, error } = await supabase.from("farmer_daily_tasks")
        .select("id,title:title_key,description:description_key,priority,status,task_date,due_at,action_route")
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("task_date", { ascending: false })
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(20);
      if (error) throw error;
      return successResponse({ tasks: data ?? [] }, 200, "whatsapp_daily_tasks");
    }

    if (action === "inventory") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const { data, error } = await supabase.from("farmer_inventory_items")
        .select("inventory_id,product_name,crop,variety,quantity,unit,grade,moisture_percent,harvested_at")
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse({ farm, items: data ?? [] }, 200, "whatsapp_inventory_listed");
    }

    if (action === "economics") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const { data, error } = await supabase.from("farm_economic_plans")
        .select("plan_type,crop,variety,growth_stage,area_acres,ai_summary,created_at")
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse({ farm, plans: data ?? [] }, 200, "whatsapp_economics_listed");
    }

    if (action === "harvest") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const { data, error } = await supabase.from("farm_harvest_zone_plans")
        .select("id,growth_stage,readiness,confidence,coverage_percent,status,summary,generated_at")
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("generated_at", { ascending: false })
        .limit(5);
      if (error) throw error;
      return successResponse({ farm, plans: data ?? [] }, 200, "whatsapp_harvest_listed");
    }

    if (action === "marketplace") {
      const farm = await resolveFarm(supabase, identity, body.farm ?? body.farmId);
      const { data, error } = await supabase.from("marketplace_listings")
        .select("id,product_name,crop,quantity,unit,grade,asking_price_per_unit,status,created_at")
        .eq("farmer_user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse({ farm, listings: data ?? [] }, 200, "whatsapp_marketplace_listed");
    }

    return errorResponse("Unsupported WhatsApp action.", 400);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    if (error instanceof HttpError && Object.keys(error.details).length > 0) {
      return new Response(JSON.stringify({
        success: false,
        error: error.message,
        ...error.details,
      }), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return errorResponse(error instanceof Error ? error.message : "WhatsApp gateway failed", status, error);
  }
});

async function hash(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
