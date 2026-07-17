import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { text } from "../_shared/farmer-links.ts";

type RoleAccount = "admin" | "fpc";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function normalizeRole(raw: unknown): RoleAccount | null {
  const role = text(raw).toLowerCase();
  if (role === "admin") return "admin";
  if (["fpc", "fpo", "fpo_fpc", "fpo/fpc"].includes(role)) return "fpc";
  return null;
}

function normalizeEmail(raw: unknown): string {
  return text(raw).toLowerCase();
}

function normalizePhone(raw: unknown): string {
  return text(raw).replace(/\D/g, "").slice(-10);
}

function looksLikeExistingAccount(error: unknown): boolean {
  const raw = text(
    (error as { message?: unknown; code?: unknown })?.message ??
      (error as { code?: unknown })?.code ??
      error,
  ).toLowerCase();
  return raw.includes("already") ||
    raw.includes("registered") ||
    raw.includes("exists");
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse(
      "Method not allowed",
      405,
      undefined,
      "method_not_allowed",
    );
  }

  try {
    const body = await req.json().catch(() => ({}));
    const role = normalizeRole(body.role);
    if (!role) {
      return errorResponse(
        "This signup link is not valid.",
        400,
        undefined,
        "invalid_role",
      );
    }

    const email = normalizeEmail(body.email);
    const password = text(body.password);
    const displayName = text(body.displayName ?? body.display_name);
    const organizationName = text(
      body.organizationName ?? body.organization_name,
    );
    const phone = normalizePhone(body.phone);

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return errorResponse(
        "Enter a valid email.",
        400,
        undefined,
        "invalid_email",
      );
    }
    if (password.length < 6) {
      return errorResponse(
        "Password must be at least 6 characters.",
        400,
        undefined,
        "password_too_short",
      );
    }
    if (displayName.length === 0 || organizationName.length === 0) {
      return errorResponse(
        "Name and organization details are required.",
        400,
        undefined,
        "profile_details_required",
      );
    }
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid mobile number.",
        400,
        undefined,
        "invalid_phone",
      );
    }

    const supabase = createServiceClient();
    const serverRoles = role === "admin" ? ["admin"] : ["fpc"];
    const { data: userData, error: createError } =
      await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: {
          role,
          roles: serverRoles,
        },
        user_metadata: {
          role,
          display_name: displayName,
          organization_name: organizationName,
          phone,
        },
      });

    if (createError || !userData?.user) {
      if (looksLikeExistingAccount(createError)) {
        return errorResponse(
          "This email is already registered. Login instead.",
          409,
          undefined,
          "account_already_exists",
        );
      }
      return errorResponse(
        "Could not create account.",
        500,
        createError,
        "account_create_failed",
      );
    }

    const user = userData.user;
    const { error: profileError } = await supabase
      .from("role_account_profiles")
      .upsert(
        {
          user_id: user.id,
          role,
          email,
          display_name: displayName,
          organization_name: organizationName,
          phone,
          status: "active",
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" },
      );

    if (profileError) {
      await supabase.auth.admin.deleteUser(user.id).catch((deleteError) => {
        console.error("[role-account-signup] rollback failed", deleteError);
      });
      return errorResponse(
        "Could not sync account profile.",
        500,
        profileError,
        "profile_sync_failed",
      );
    }

    return successResponse(
      {
        userId: user.id,
        email,
        role,
      },
      201,
      "role_account_created",
    );
  } catch (error) {
    return errorResponse(
      "role-account-signup failed",
      500,
      error,
      "role_account_signup_failed",
    );
  }
});
