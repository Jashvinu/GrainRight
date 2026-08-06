import { createClient } from "npm:@supabase/supabase-js@2";

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

function base64Url(value: Uint8Array | string): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function privateKeyBytes(pem: string): Uint8Array {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function firebaseAccessToken(credentials: Json): Promise<string> {
  const clientEmail = text(credentials.client_email);
  const privateKey = text(credentials.private_key);
  const tokenUri = text(credentials.token_uri) ||
    "https://oauth2.googleapis.com/token";
  if (!clientEmail || !privateKey) {
    throw new Error("Firebase service account is incomplete.");
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const tokenResponse = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenBody = record(await tokenResponse.json().catch(() => ({})));
  if (!tokenResponse.ok || !text(tokenBody.access_token)) {
    throw new Error(
      text(tokenBody.error_description) ||
        "Could not obtain Firebase access token.",
    );
  }
  return text(tokenBody.access_token);
}

function stringData(value: unknown): Record<string, string> {
  const source = record(value);
  return Object.fromEntries(
    Object.entries(source).map(([key, item]) => [
      key,
      typeof item === "string" ? item : JSON.stringify(item),
    ]),
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return response({ success: false, error: "Method not allowed." }, 405);
  }
  const dispatchSecret = text(Deno.env.get("FPC_PUSH_DISPATCH_SECRET"));
  if (
    !dispatchSecret ||
    text(req.headers.get("x-fpc-push-secret")) !== dispatchSecret
  ) {
    return response({ success: false, error: "Unauthorized." }, 401);
  }
  try {
    const rawCredentials = text(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON"));
    if (!rawCredentials) {
      return response(
        {
          success: false,
          error: "Firebase service account is not configured.",
        },
        503,
      );
    }
    const credentials = record(JSON.parse(rawCredentials));
    const projectId = text(credentials.project_id);
    if (!projectId) throw new Error("Firebase project ID is missing.");
    const accessToken = await firebaseAccessToken(credentials);
    const supabase = serviceClient();
    const { data: outboxRows, error: outboxError } = await supabase
      .from("notification_outbox")
      .select("*,notification:fpc_notifications(*)")
      .eq("channel", "push")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(50);
    if (outboxError) throw outboxError;

    let sent = 0;
    let failed = 0;
    for (const outbox of outboxRows ?? []) {
      const notification = record(outbox.notification);
      const recipientUserId = text(notification.recipient_user_id) ||
        text(outbox.recipient);
      const { data: tokens, error: tokenError } = await supabase
        .from("fpc_push_tokens")
        .select("id,token")
        .eq("user_id", recipientUserId)
        .eq("active", true);
      if (tokenError) throw tokenError;
      if (!tokens?.length) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "disabled",
            last_error: "No active Android push token.",
            attempt_count: Number(outbox.attempt_count || 0) + 1,
          })
          .eq("id", outbox.id);
        continue;
      }

      let delivered = false;
      const deliveryErrors: string[] = [];
      for (const tokenRow of tokens) {
        const fcmResponse = await fetch(
          `https://fcm.googleapis.com/v1/projects/${
            encodeURIComponent(projectId)
          }/messages:send`,
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: tokenRow.token,
                notification: {
                  title: text(notification.title),
                  body: text(notification.body),
                },
                data: {
                  ...stringData(notification.data),
                  notification_id: text(notification.id),
                  event_key: text(notification.event_key),
                },
                android: {
                  priority: "high",
                  notification: {
                    channel_id: "farmer_alerts",
                    sound: "default",
                  },
                },
              },
            }),
          },
        );
        const fcmBody = record(await fcmResponse.json().catch(() => ({})));
        if (fcmResponse.ok) {
          delivered = true;
          continue;
        }
        const errorMessage = text(record(fcmBody.error).message) ||
          `FCM HTTP ${fcmResponse.status}`;
        deliveryErrors.push(errorMessage);
        if (
          fcmResponse.status === 404 ||
          errorMessage.includes("UNREGISTERED")
        ) {
          await supabase
            .from("fpc_push_tokens")
            .update({ active: false })
            .eq("id", tokenRow.id);
        }
      }

      await supabase
        .from("notification_outbox")
        .update({
          status: delivered ? "sent" : "failed",
          attempt_count: Number(outbox.attempt_count || 0) + 1,
          last_error: deliveryErrors.join(" | ").slice(0, 1000),
        })
        .eq("id", outbox.id);
      if (delivered) {
        sent += 1;
      } else {
        failed += 1;
      }
    }
    return response({ success: true, sent, failed });
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
