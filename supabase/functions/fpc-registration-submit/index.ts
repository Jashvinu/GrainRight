import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { text } from "../_shared/farmer-links.ts";

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase service configuration missing");
  return createClient(url, key);
}

function existingAccount(error: unknown) {
  const value = text(
    (error as { message?: unknown; code?: unknown })?.message ??
      (error as { code?: unknown })?.code ?? error,
  ).toLowerCase();
  return value.includes("already") || value.includes("registered") ||
    value.includes("exists");
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const body = await req.json().catch(() => ({}));
    const email = text(body.email).toLowerCase();
    const password = text(body.password);
    const displayName = text(body.displayName ?? body.display_name);
    const organizationName = text(body.organizationName ?? body.organization_name);
    const phone = text(body.phone).replace(/\D/g, "").slice(-10);

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return errorResponse("Enter a valid email.", 400, undefined, "invalid_email");
    }
    if (password.length < 6) {
      return errorResponse(
        "Password must be at least 6 characters.",
        400,
        undefined,
        "password_too_short",
      );
    }
    if (!displayName || !organizationName || phone.length !== 10) {
      return errorResponse(
        "Complete the contact and FPC details.",
        400,
        undefined,
        "profile_details_required",
      );
    }

    const supabase = serviceClient();
    const { data: pending } = await supabase
      .from("fpc_registration_applications")
      .select("id,status")
      .eq("email", email)
      .in("status", ["pending", "under_review"])
      .maybeSingle();
    if (pending) {
      return errorResponse(
        "This FPC application is already waiting for review.",
        409,
        undefined,
        "application_pending",
      );
    }

    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: false,
      app_metadata: { role: "fpc_applicant", roles: ["fpc_applicant"] },
      user_metadata: {
        display_name: displayName,
        organization_name: organizationName,
        phone,
      },
    });
    if (authError || !authData.user) {
      if (existingAccount(authError)) {
        return errorResponse(
          "This email is already registered. Login or contact Kalsubai Farms.",
          409,
          undefined,
          "account_already_exists",
        );
      }
      return errorResponse("Could not submit FPC application.", 500, authError, "auth_create_failed");
    }

    const { data: application, error: applicationError } = await supabase
      .from("fpc_registration_applications")
      .insert({
        applicant_user_id: authData.user.id,
        email,
        display_name: displayName,
        organization_name: organizationName,
        phone,
        status: "pending",
      })
      .select("id,status,submitted_at")
      .single();

    if (applicationError || !application) {
      await supabase.auth.admin.deleteUser(authData.user.id).catch(() => undefined);
      return errorResponse(
        "Could not save FPC application.",
        500,
        applicationError,
        "application_save_failed",
      );
    }

    return successResponse(
      { application, message: "Application submitted for Kalsubai Farms approval." },
      201,
      "fpc_application_submitted",
    );
  } catch (error) {
    return errorResponse("FPC registration failed.", 500, error, "fpc_registration_failed");
  }
});
