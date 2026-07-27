import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { bearerToken, hasServerRole, text } from "../_shared/farmer-links.ts";

type Row = Record<string, unknown>;

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase service configuration missing");
  return createClient(url, key);
}

async function requireAdmin(supabase: any, req: Request): Promise<string | Response> {
  const token = bearerToken(req);
  if (!token) return errorResponse("Missing auth token", 401, undefined, "missing_auth_token");
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) {
    return errorResponse("Invalid auth token", 401, error, "invalid_auth_token");
  }
  if (!hasServerRole(data.user, ["admin"], token)) {
    return errorResponse("Platform Admin access required.", 403, undefined, "admin_role_required");
  }
  return data.user.id;
}

async function list(supabase: any) {
  const [applications, fpcs, memberships, subscriptions, procurements, jobs, farmers, stock, production, sales, notifications] = await Promise.all([
    supabase.from("fpc_registration_applications").select("*").order("submitted_at", { ascending: false }),
    supabase.from("fpcs").select("*").order("created_at", { ascending: false }),
    supabase.from("fpc_memberships").select("*").order("created_at", { ascending: false }),
    supabase.from("fpc_subscriptions").select("*").order("created_at", { ascending: false }),
    supabase.from("fpc_procurement_records").select("fpc_organization_id,quantity_kg"),
    supabase.from("analysis_jobs").select("fpc_organization_id,id"),
    supabase.from("fpc_farmer_links").select("fpc_id,id").eq("status", "active"),
    supabase.from("stock_ledger").select("fpc_id,quantity_kg"),
    supabase.from("production_runs").select("fpc_id,output_kg,status"),
    supabase.from("sales_orders").select("fpc_id,total,status"),
    supabase.from("notification_outbox").select("fpc_id,channel,status"),
  ]);
  for (const result of [applications, fpcs, memberships, subscriptions]) {
    if (result.error) throw result.error;
  }
  const procurementRows = (procurements.data ?? []) as Row[];
  const jobRows = (jobs.data ?? []) as Row[];
  const totalProcurementKg = procurementRows.reduce(
    (sum, row) => sum + (Number(row.quantity_kg) || 0),
    0,
  );
  return successResponse({
    applications: applications.data ?? [],
    fpcs: fpcs.data ?? [],
    memberships: memberships.data ?? [],
    subscriptions: subscriptions.data ?? [],
    analytics: {
      totalFpcs: (fpcs.data ?? []).length,
      activeFpcs: (fpcs.data ?? []).filter((row: Row) => row.status === "active").length,
      activeUsers: (memberships.data ?? []).filter((row: Row) => row.status === "active").length,
      linkedFarmers: (farmers.data ?? []).length,
      procurementVolumeKg: totalProcurementKg,
      stockOnHandKg: (stock.data ?? []).reduce((sum: number, row: Row) => sum + (Number(row.quantity_kg) || 0), 0),
      productionOutputKg: (production.data ?? []).filter((row: Row) => row.status === "completed").reduce((sum: number, row: Row) => sum + (Number(row.output_kg) || 0), 0),
      salesValue: (sales.data ?? []).filter((row: Row) => row.status !== "cancelled").reduce((sum: number, row: Row) => sum + (Number(row.total) || 0), 0),
      aiUsage: jobRows.length,
      notificationUsage: (notifications.data ?? []).length,
    },
  });
}

async function review(
  supabase: any,
  adminUserId: string,
  applicationId: string,
  decision: string,
  note: string,
) {
  const { data: application, error: loadError } = await supabase
    .from("fpc_registration_applications")
    .select("*")
    .eq("id", applicationId)
    .single();
  if (loadError || !application) {
    return errorResponse("FPC application not found.", 404, loadError, "application_not_found");
  }
  if (!["pending", "under_review"].includes(application.status)) {
    return errorResponse("This application was already reviewed.", 409, undefined, "already_reviewed");
  }
  if (decision === "rejected") {
    if (note.trim().length < 5) {
      return errorResponse("Add a clear rejection reason.", 400, undefined, "rejection_reason_required");
    }
    const { error } = await supabase.from("fpc_registration_applications").update({
      status: "rejected",
      admin_note: note.trim(),
      reviewed_by: adminUserId,
      reviewed_at: new Date().toISOString(),
    }).eq("id", applicationId);
    if (error) throw error;
    if (application.applicant_user_id) {
      await supabase.auth.admin.deleteUser(application.applicant_user_id).catch(() => undefined);
    }
    await supabase.from("audit_events").insert({
      actor_user_id: adminUserId,
      actor_role: "admin",
      action: "fpc_application_rejected",
      target_type: "fpc_registration_application",
      target_id: applicationId,
      after_data: { note: note.trim(), email: application.email },
    });
    return successResponse({ status: "rejected" }, 200, "fpc_application_rejected");
  }
  if (decision !== "approved") {
    return errorResponse("Invalid review decision.", 400, undefined, "invalid_decision");
  }
  if (!application.applicant_user_id) {
    return errorResponse("Applicant login is unavailable.", 409, undefined, "applicant_user_missing");
  }

  let createdFpcId = "";
  try {
    const { data: fpc, error: fpcError } = await supabase.from("fpcs").insert({
      name: application.organization_name,
      email: application.email,
      phone: application.phone,
      status: "active",
      legacy_owner_user_id: application.applicant_user_id,
    }).select("*").single();
    if (fpcError || !fpc) throw fpcError ?? new Error("FPC create failed");
    createdFpcId = fpc.id;

    const { error: membershipError } = await supabase.from("fpc_memberships").insert({
      fpc_id: fpc.id,
      user_id: application.applicant_user_id,
      role: "fpc_admin",
      status: "active",
      display_name: application.display_name,
      email: application.email,
      phone: application.phone,
      created_by: adminUserId,
    });
    if (membershipError) throw membershipError;

    const { error: profileError } = await supabase.from("role_account_profiles").upsert({
      user_id: application.applicant_user_id,
      fpc_id: fpc.id,
      role: "fpc_admin",
      email: application.email,
      display_name: application.display_name,
      organization_name: application.organization_name,
      phone: application.phone,
      status: "active",
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    if (profileError) throw profileError;

    const { error: subscriptionError } = await supabase.from("fpc_subscriptions").insert({
      fpc_id: fpc.id,
      plan_code: "managed-prototype",
      status: "active",
      amount: 0,
      limits: { fieldOfficers: 25, farmers: 5000, storageMb: 2048 },
    });
    if (subscriptionError) throw subscriptionError;

    const { error: authError } = await supabase.auth.admin.updateUserById(
      application.applicant_user_id,
      {
        email_confirm: true,
        app_metadata: {
          role: "fpc_admin",
          roles: ["fpc_admin", "fpc"],
          fpc_id: fpc.id,
        },
      },
    );
    if (authError) throw authError;

    const { error: applicationError } = await supabase
      .from("fpc_registration_applications")
      .update({
        status: "approved",
        admin_note: note.trim(),
        reviewed_by: adminUserId,
        reviewed_at: new Date().toISOString(),
        approved_fpc_id: fpc.id,
      })
      .eq("id", applicationId);
    if (applicationError) throw applicationError;

    await supabase.from("audit_events").insert({
      fpc_id: fpc.id,
      actor_user_id: adminUserId,
      actor_role: "admin",
      action: "fpc_application_approved",
      target_type: "fpc",
      target_id: fpc.id,
      after_data: { name: fpc.name, adminUserId: application.applicant_user_id },
    });
    const { data: approvalNotification } = await supabase.from("fpc_notifications").insert({
      fpc_id: fpc.id,
      recipient_user_id: application.applicant_user_id,
      event_key: "fpc_approval",
      title: "FPC application approved",
      body: `${fpc.name} is active. You can now sign in from the FPC login.`,
      data: { fpcId: fpc.id, applicationId },
    }).select("id").single();
    if (approvalNotification?.id) {
      await supabase.from("notification_outbox").insert({
        fpc_id: fpc.id,
        notification_id: approvalNotification.id,
        channel: "in_app",
        recipient: application.email,
        status: "sent",
      });
    }
    return successResponse({ fpc, status: "approved" }, 200, "fpc_application_approved");
  } catch (error) {
    if (createdFpcId) await supabase.from("fpcs").delete().eq("id", createdFpcId);
    return errorResponse("Could not approve FPC application.", 500, error, "approval_failed");
  }
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);
  try {
    const supabase = serviceClient();
    const adminUserId = await requireAdmin(supabase, req);
    if (adminUserId instanceof Response) return adminUserId;
    const body = await req.json().catch(() => ({}));
    const action = text(body.action || "list").toLowerCase();
    if (action === "list") return await list(supabase);
    if (action === "review") {
      return await review(
        supabase,
        adminUserId,
        text(body.applicationId),
        text(body.decision).toLowerCase(),
        text(body.note),
      );
    }
    if (action === "set_fpc_status") {
      const status = text(body.status).toLowerCase();
      if (!["active", "suspended", "inactive"].includes(status)) {
        return errorResponse("Invalid FPC status.", 400, undefined, "invalid_status");
      }
      const { data, error } = await supabase.from("fpcs").update({ status }).eq("id", text(body.fpcId)).select().single();
      if (error) throw error;
      await supabase.from("audit_events").insert({
        fpc_id: data.id,
        actor_user_id: adminUserId,
        actor_role: "admin",
        action: `fpc_${status}`,
        target_type: "fpc",
        target_id: data.id,
        after_data: { status },
      });
      return successResponse({ fpc: data }, 200, "fpc_status_updated");
    }
    if (action === "update_fpc") {
      const fpcId = text(body.fpcId);
      const name = text(body.name);
      const email = text(body.email).toLowerCase();
      const phone = text(body.phone).replace(/\D/g, "").slice(-10);
      const gstin = text(body.gstin).toUpperCase();
      if (!fpcId || !name || (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) {
        return errorResponse("Enter a valid organization name and email.", 400, undefined, "invalid_fpc_details");
      }
      if (gstin && !/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$/.test(gstin)) {
        return errorResponse("Enter a valid GSTIN or leave it blank.", 400, undefined, "invalid_gstin");
      }
      const before = await supabase.from("fpcs").select("*").eq("id", fpcId).single();
      if (before.error || !before.data) return errorResponse("FPC not found.", 404, before.error, "fpc_not_found");
      const { data, error } = await supabase.from("fpcs").update({
        name,
        legal_name: text(body.legalName),
        registration_number: text(body.registrationNumber),
        gstin,
        email,
        phone,
        address: typeof body.address === "object" && body.address ? body.address : {},
        limits: typeof body.limits === "object" && body.limits ? body.limits : before.data.limits,
      }).eq("id", fpcId).select().single();
      if (error) throw error;
      await supabase.from("audit_events").insert({
        fpc_id: fpcId, actor_user_id: adminUserId, actor_role: "admin",
        action: "fpc_updated", target_type: "fpc", target_id: fpcId,
        before_data: before.data, after_data: data,
      });
      return successResponse({ fpc: data }, 200, "fpc_updated");
    }
    if (action === "update_subscription") {
      const fpcId = text(body.fpcId);
      const status = text(body.status).toLowerCase();
      const planCode = text(body.planCode);
      if (!fpcId || !planCode || !["trial", "active", "past_due", "suspended", "cancelled"].includes(status)) {
        return errorResponse("Enter a valid subscription plan and status.", 400, undefined, "invalid_subscription");
      }
      const { data: existing } = await supabase.from("fpc_subscriptions").select("*").eq("fpc_id", fpcId).maybeSingle();
      const values = {
        fpc_id: fpcId,
        plan_code: planCode,
        status,
        amount: Number(body.amount) || 0,
        tax_rate: Number(body.taxRate) || 0,
        limits: typeof body.limits === "object" && body.limits ? body.limits : existing?.limits ?? {},
        starts_on: text(body.startsOn) || existing?.starts_on || new Date().toISOString().slice(0, 10),
        ends_on: text(body.endsOn) || null,
      };
      const query = existing?.id
        ? supabase.from("fpc_subscriptions").update(values).eq("id", existing.id)
        : supabase.from("fpc_subscriptions").insert(values);
      const { data, error } = await query.select().single();
      if (error) throw error;
      let invoice: Row | null = null;
      if (body.issueInvoice === true && Number(values.amount) > 0) {
        const subtotal = Number(values.amount);
        const tax = Math.round(subtotal * Number(values.tax_rate) * 100) / 10000;
        const invoiceNumber = `SUB-${new Date().getUTCFullYear()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
        const { data: createdInvoice, error: invoiceError } = await supabase
          .from("fpc_subscription_invoices")
          .insert({
            fpc_id: fpcId,
            subscription_id: data.id,
            invoice_number: invoiceNumber,
            issued_on: new Date().toISOString().slice(0, 10),
            subtotal,
            cgst: tax / 2,
            sgst: tax / 2,
            igst: 0,
            total: subtotal + tax,
            status: "issued",
            snapshot: { subscription: data, issuedBy: adminUserId },
          })
          .select()
          .single();
        if (invoiceError) throw invoiceError;
        invoice = createdInvoice;
      }
      await supabase.from("audit_events").insert({
        fpc_id: fpcId, actor_user_id: adminUserId, actor_role: "admin",
        action: "fpc_subscription_updated", target_type: "fpc_subscription",
        target_id: data.id, before_data: existing ?? {}, after_data: data,
      });
      return successResponse({ subscription: data, invoice }, 200, "subscription_updated");
    }
    return errorResponse("Unknown action.", 400, undefined, "unknown_action");
  } catch (error) {
    return errorResponse("Platform FPC workflow failed.", 500, error, "platform_fpc_failed");
  }
});
