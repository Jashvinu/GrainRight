import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

type Row = Record<string, unknown>;

function object(raw: unknown): Row {
  return raw != null && typeof raw === "object" && !Array.isArray(raw)
    ? (raw as Row)
    : {};
}

function text(raw: unknown): string {
  return String(raw ?? "").trim();
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service credentials");
  return createClient(url, key);
}

async function hashToken(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function language(raw: unknown): "en" | "hi" | "mr" {
  const value = text(raw).toLowerCase();
  return value === "hi" || value === "mr" ? value : "en";
}

function whatsappReturnUrl(): string | null {
  const phone = text(Deno.env.get("WHATSAPP_BOT_PHONE")).replace(/\D/g, "");
  if (!/^\d{10,15}$/.test(phone)) return null;
  const url = new URL(`https://wa.me/${phone}`);
  url.searchParams.set("text", "CONTINUE");
  return url.toString();
}

async function loadLink(
  supabase: ReturnType<typeof serviceClient>,
  token: string,
) {
  const tokenHash = await hashToken(token);
  const { data, error } = await supabase
    .from("whatsapp_service_links")
    .select(
      "id,whatsapp_phone,user_id,farmer_id,farm_id,service,language,status,result,expires_at,completed_at",
    )
    .eq("token_hash", tokenHash)
    .in("status", ["active", "completed"])
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;
  return data as Row | null;
}

async function invokeGateway(body: Row): Promise<Row> {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const bridgeToken = Deno.env.get("GRAINRIGHT_WHATSAPP_API_TOKEN");
  if (!url || !anonKey || !bridgeToken)
    throw new Error("WhatsApp service bridge is not configured.");
  const response = await fetch(`${url}/functions/v1/whatsapp-grainright`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${anonKey}`,
      apikey: anonKey,
      "x-grainright-whatsapp-bridge": bridgeToken,
    },
    body: JSON.stringify(body),
  });
  const data = object(await response.json().catch(() => ({})));
  if (!response.ok || data.success === false)
    throw new Error(text(data.error) || "The GrainRight service failed.");
  return data;
}

async function completeService(
  supabase: ReturnType<typeof serviceClient>,
  link: Row,
  body: Row,
): Promise<Row> {
  if (text(link.status) === "completed") return object(link.result);
  const service = text(link.service);
  const common = {
    phone: text(link.whatsapp_phone),
    language: language(link.language),
    farmId: text(link.farm_id),
  };
  let result: Row;
  if (service === "ai") {
    const question = text(body.question);
    if (!question) throw new Error("Please enter your farm question.");
    result = await invokeGateway({ action: "ai_chat", ...common, question });
  } else if (service === "grading") {
    const grain = text(body.grainImageBase64).replace(
      /^data:[^;]+;base64,/,
      "",
    );
    const moisture = text(body.moistureImageBase64).replace(
      /^data:[^;]+;base64,/,
      "",
    );
    if (!grain || !moisture)
      throw new Error("Both grain and moisture photos are required.");
    const grainSaved = await invokeGateway({
      action: "grading_media",
      ...common,
      kind: "grain",
      mediaBase64: grain,
      mediaMimeType: text(body.grainImageMimeType) || "image/jpeg",
      provider: "grainright-web",
    });
    const moistureSaved = await invokeGateway({
      action: "grading_media",
      ...common,
      kind: "moisture",
      mediaBase64: moisture,
      mediaMimeType: text(body.moistureImageMimeType) || "image/jpeg",
      provider: "grainright-web",
    });
    result = await invokeGateway({
      action: "grading_submit",
      ...common,
      grainImagePath: text(grainSaved.path ?? object(grainSaved.data).path),
      moistureImagePath: text(
        moistureSaved.path ?? object(moistureSaved.data).path,
      ),
      cropType: text(body.cropType),
      cropVariety: text(body.cropVariety ?? body.crop_variety),
    });
  } else if (service === "daily_tasks") {
    const taskId = text(body.taskId ?? body.task_id);
    const rawPhotos = body.taskPhotos ?? body.task_photos;
    const photos: unknown[] = Array.isArray(rawPhotos) ? rawPhotos : [];
    if (!taskId || photos.length < 3) {
      throw new Error("Select a daily task and capture three farm-area photos.");
    }
    for (let index = 0; index < 3; index += 1) {
      const photo = object(photos[index]);
      const photoBase64 = text(photo.base64 ?? photo.mediaBase64).replace(
        /^data:[^;]+;base64,/,
        "",
      );
      if (!photoBase64) throw new Error(`Farm photo ${index + 1} is required.`);
      await invokeGateway({
        action: "daily_task_photo",
        ...common,
        taskId,
        captureIndex: index + 1,
        farmId: text(link.farm_id),
        mediaBase64: photoBase64,
        mediaMimeType: text(photo.mimeType ?? photo.mediaMimeType) || "image/jpeg",
      });
    }
    result = await invokeGateway({
      action: "daily_task_complete",
      ...common,
      taskId,
      farmId: text(link.farm_id),
    });
  } else {
    throw new Error("This web service is not available.");
  }

  const { data: updated, error } = await supabase
    .from("whatsapp_service_links")
    .update({
      status: "completed",
      result,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", link.id)
    .eq("status", "active")
    .select("result,status,completed_at")
    .maybeSingle();
  if (error) throw error;
  return object(updated?.result ?? result);
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = object(await req.json());
    const token = text(body.token);
    if (token.length < 32)
      return errorResponse("This GrainRight service link is invalid.", 400);
    const supabase = serviceClient();
    const link = await loadLink(supabase, token);
    if (!link)
      return errorResponse(
        "This service link has expired or was already used.",
        410,
      );

    const action = text(body.action).toLowerCase() || "load";
    const farm = await supabase
      .from("farms")
      .select("id,name,crop,variety,location_label")
      .eq("id", link.farm_id)
      .eq("user_id", link.user_id)
      .maybeSingle();
    if (farm.error) throw farm.error;
    if (!farm.data)
      return errorResponse("The linked farm is no longer available.", 404);

    let task: Row | null = null;
    if (text(link.service) === "daily_tasks") {
      const taskQuery = await supabase
        .from("farmer_daily_tasks")
        .select("id,title_key,description_key,priority,status,task_date,due_at,action_route")
        .eq("user_id", link.user_id)
        .eq("farm_id", link.farm_id)
        .in("status", ["pending", "snoozed"])
        .order("task_date", { ascending: false })
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(1)
        .maybeSingle();
      if (taskQuery.error) throw taskQuery.error;
      task = taskQuery.data as Row | null;
    }

    if (action === "load") {
      return successResponse(
        {
          linkId: link.id,
          service: link.service,
          language: language(link.language),
          farm: farm.data,
          status: link.status,
          result: link.status === "completed" ? link.result : null,
          task,
          expiresAt: link.expires_at,
        },
        200,
        "whatsapp_service_link_loaded",
      );
    }

    if (action !== "complete")
      return errorResponse("Unsupported service-link action.", 400);
    const result = await completeService(supabase, link, body);
    return successResponse(
      {
        linkId: link.id,
        service: link.service,
        language: language(link.language),
        result,
        returnToWhatsappUrl: whatsappReturnUrl(),
      },
      200,
      "whatsapp_service_completed",
    );
  } catch (error) {
    return errorResponse(
      error instanceof Error
        ? error.message
        : "Could not complete the GrainRight service.",
      400,
    );
  }
});
