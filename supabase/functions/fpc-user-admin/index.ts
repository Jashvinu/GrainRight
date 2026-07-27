import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { bearerToken, hasServerRole, text } from "../_shared/farmer-links.ts";

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase service configuration missing");
  return createClient(url, key);
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);
  try {
    const supabase = serviceClient();
    const token = bearerToken(req);
    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData?.user) {
      return errorResponse("Invalid auth token", 401, authError, "invalid_auth_token");
    }
    const actor = authData.user;
    const body = await req.json().catch(() => ({}));
    const action = text(body.action || "list").toLowerCase();
    if (action === "change_password") {
      const password = text(body.password);
      if (password.length < 8) {
        return errorResponse(
          "Password must be at least 8 characters.",
          400,
          undefined,
          "password_too_short",
        );
      }
      const { error: passwordError } = await supabase.auth.admin.updateUserById(
        actor.id,
        {
          password,
          app_metadata: {
            ...actor.app_metadata,
            must_change_password: false,
          },
        },
      );
      if (passwordError) throw passwordError;
      const { error: membershipError } = await supabase
        .from("fpc_memberships")
        .update({ must_change_password: false })
        .eq("user_id", actor.id);
      if (membershipError) throw membershipError;
      return successResponse({}, 200, "password_changed");
    }
    const platformAdmin = hasServerRole(actor, ["admin"], token);
    const { data: actorMembership } = await supabase
      .from("fpc_memberships")
      .select("fpc_id,role,status")
      .eq("user_id", actor.id)
      .eq("status", "active")
      .maybeSingle();
    const actorFpcId = text(actorMembership?.fpc_id);
    const isFpcAdmin = actorMembership?.role === "fpc_admin";
    const requestedFpcId = text(body.fpcId) || actorFpcId;
    if (!platformAdmin && (!isFpcAdmin || !actorFpcId || requestedFpcId !== actorFpcId)) {
      return errorResponse("FPC Admin access required.", 403, undefined, "fpc_admin_required");
    }
    if (!requestedFpcId) return errorResponse("FPC is required.", 400, undefined, "fpc_required");

    if (action === "list") {
      const { data, error } = await supabase.from("fpc_memberships").select("*").eq("fpc_id", requestedFpcId).order("created_at");
      if (error) throw error;
      return successResponse({ memberships: data ?? [] });
    }
    if (action === "create") {
      const role = text(body.role || "field_officer").toLowerCase();
      if (!platformAdmin && role !== "field_officer") {
        return errorResponse("FPC Admins can create Field Officers only.", 403, undefined, "role_not_allowed");
      }
      if (!["field_officer", "fpc_admin"].includes(role)) {
        return errorResponse("Invalid role.", 400, undefined, "invalid_role");
      }
      const email = text(body.email).toLowerCase();
      const password = text(body.temporaryPassword);
      const displayName = text(body.displayName);
      const phone = text(body.phone).replace(/\D/g, "").slice(-10);
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || password.length < 8 || !displayName) {
        return errorResponse("Enter a name, valid email and 8-character temporary password.", 400, undefined, "invalid_user_details");
      }
      if (role === "field_officer") {
        const [{ data: subscription }, { count: officerCount, error: countError }] = await Promise.all([
          supabase.from("fpc_subscriptions").select("limits").eq("fpc_id", requestedFpcId).in("status", ["trial", "active"]).order("created_at", { ascending: false }).limit(1).maybeSingle(),
          supabase.from("fpc_memberships").select("id", { count: "exact", head: true }).eq("fpc_id", requestedFpcId).eq("role", "field_officer").eq("status", "active"),
        ]);
        if (countError) throw countError;
        const officerLimit = Number(subscription?.limits?.fieldOfficers) || 25;
        if ((officerCount ?? 0) >= officerLimit) {
          return errorResponse("This FPC has reached its Field Officer subscription limit.", 409, undefined, "field_officer_limit_reached");
        }
      }
      const { data: userData, error: createError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { role, roles: [role], fpc_id: requestedFpcId, must_change_password: true },
        user_metadata: { display_name: displayName, phone },
      });
      if (createError || !userData.user) throw createError ?? new Error("User create failed");
      const { data: fpc } = await supabase.from("fpcs").select("name").eq("id", requestedFpcId).single();
      const { error: membershipError } = await supabase.from("fpc_memberships").insert({
        fpc_id: requestedFpcId,
        user_id: userData.user.id,
        role,
        status: "active",
        must_change_password: true,
        display_name: displayName,
        email,
        phone,
        created_by: actor.id,
      });
      if (membershipError) {
        await supabase.auth.admin.deleteUser(userData.user.id).catch(() => undefined);
        throw membershipError;
      }
      await supabase.from("role_account_profiles").upsert({
        user_id: userData.user.id,
        fpc_id: requestedFpcId,
        role,
        email,
        display_name: displayName,
        organization_name: text(fpc?.name),
        phone,
        status: "active",
      }, { onConflict: "user_id" });
      await supabase.from("audit_events").insert({
        fpc_id: requestedFpcId,
        actor_user_id: actor.id,
        actor_role: platformAdmin ? "admin" : "fpc_admin",
        action: "fpc_user_created",
        target_type: "fpc_membership",
        target_id: userData.user.id,
        after_data: { role, email, displayName },
      });
      return successResponse({ userId: userData.user.id, role }, 201, "fpc_user_created");
    }
    if (action === "set_status") {
      const membershipId = text(body.membershipId);
      const status = text(body.status).toLowerCase();
      if (!["active", "disabled"].includes(status)) {
        return errorResponse("Invalid membership status.", 400, undefined, "invalid_status");
      }
      const { data, error } = await supabase.from("fpc_memberships").update({ status }).eq("id", membershipId).eq("fpc_id", requestedFpcId).select().single();
      if (error) throw error;
      await supabase.from("role_account_profiles").update({ status: status === "active" ? "active" : "inactive" }).eq("user_id", data.user_id);
      await supabase.from("audit_events").insert({
        fpc_id: requestedFpcId,
        actor_user_id: actor.id,
        actor_role: platformAdmin ? "admin" : "fpc_admin",
        action: `fpc_user_${status}`,
        target_type: "fpc_membership",
        target_id: membershipId,
        after_data: { status, userId: data.user_id },
      });
      return successResponse({ membership: data }, 200, "membership_status_updated");
    }
    if (action === "reset_password") {
      const membershipId = text(body.membershipId);
      const temporaryPassword = text(body.temporaryPassword);
      if (temporaryPassword.length < 8) {
        return errorResponse("Temporary password must be at least 8 characters.", 400, undefined, "password_too_short");
      }
      const { data: membership, error: membershipLoadError } = await supabase
        .from("fpc_memberships")
        .select("id,user_id,role")
        .eq("id", membershipId)
        .eq("fpc_id", requestedFpcId)
        .single();
      if (membershipLoadError || !membership) {
        return errorResponse("FPC membership not found.", 404, membershipLoadError, "membership_not_found");
      }
      if (!platformAdmin && membership.role !== "field_officer") {
        return errorResponse("FPC Admins can reset Field Officer passwords only.", 403, undefined, "role_not_allowed");
      }
      const { data: targetAuth, error: targetAuthError } = await supabase.auth.admin.getUserById(membership.user_id);
      if (targetAuthError || !targetAuth.user) throw targetAuthError ?? new Error("User not found");
      const { error: resetError } = await supabase.auth.admin.updateUserById(membership.user_id, {
        password: temporaryPassword,
        app_metadata: { ...targetAuth.user.app_metadata, must_change_password: true },
      });
      if (resetError) throw resetError;
      const { error: flagError } = await supabase
        .from("fpc_memberships")
        .update({ must_change_password: true })
        .eq("id", membershipId)
        .eq("fpc_id", requestedFpcId);
      if (flagError) throw flagError;
      await supabase.from("audit_events").insert({
        fpc_id: requestedFpcId,
        actor_user_id: actor.id,
        actor_role: platformAdmin ? "admin" : "fpc_admin",
        action: "fpc_user_password_reset",
        target_type: "fpc_membership",
        target_id: membershipId,
        after_data: { mustChangePassword: true, userId: membership.user_id },
      });
      return successResponse({}, 200, "temporary_password_issued");
    }
    return errorResponse("Unknown action.", 400, undefined, "unknown_action");
  } catch (error) {
    return errorResponse("FPC user workflow failed.", 500, error, "fpc_user_workflow_failed");
  }
});
