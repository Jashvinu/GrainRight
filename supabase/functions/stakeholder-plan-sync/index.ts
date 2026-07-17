import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  loadLinkedUserIds,
  normalizePhone,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

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

function numberValue(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function boolValue(raw: unknown): boolean {
  return raw === true || raw === "true" || raw === 1 || raw === "1";
}

async function loadActivePlan(supabase: any, planId = "", planCode = "") {
  let query = supabase
    .from("stakeholder_plans")
    .select("*")
    .eq("status", "active");

  if (planId.length > 0) {
    query = query.eq("id", planId);
  } else if (planCode.length > 0) {
    query = query.eq("plan_code", planCode);
  }

  const { data: plan, error } = await query
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return plan as Record<string, unknown> | null;
}

async function loadApplicationBundle(
  supabase: any,
  userId: string,
  plan: Record<string, unknown>,
  farmer: { phone: string; farmerId: string },
) {
  const planId = text(plan.id);
  const application = await loadExistingApplication(
    supabase,
    userId,
    planId,
    farmer,
  );
  if (!application) {
    return { plan, application: null, events: [] };
  }

  const { data: eventRows, error: eventError } = await supabase
    .from("stakeholder_application_events")
    .select("*")
    .eq("application_id", application.id)
    .order("created_at", { ascending: true });
  if (eventError) throw eventError;

  return {
    plan,
    application,
    events: Array.isArray(eventRows) ? eventRows : [],
  };
}

async function loadExistingApplication(
  supabase: any,
  userId: string,
  planId: string,
  farmer: { phone: string; farmerId: string },
) {
  const { data: application, error: appError } = await supabase
    .from("stakeholder_applications")
    .select("*")
    .eq("user_id", userId)
    .eq("plan_id", planId)
    .maybeSingle();
  if (appError) throw appError;
  if (application) return application as Record<string, unknown>;

  let identityQuery = supabase
    .from("stakeholder_applications")
    .select("*")
    .eq("plan_id", planId)
    .eq("farmer_phone", farmer.phone);
  if (farmer.farmerId.length > 0) {
    identityQuery = identityQuery.eq("farmer_id", farmer.farmerId);
  }

  const { data: identityRows, error: identityError } = await identityQuery
    .order("updated_at", { ascending: false })
    .limit(1);
  if (identityError) throw identityError;
  return Array.isArray(identityRows) && identityRows.length > 0
    ? identityRows[0] as Record<string, unknown>
    : null;
}

async function assertFarmerSession(
  supabase: any,
  userId: string,
  farmer: Record<string, unknown>,
): Promise<{ phone: string; farmerId: string; farmerName: string } | Response> {
  const phone = normalizePhone(farmer.phone ?? farmer.farmerPhone);
  const farmerId = text(farmer.farmerId ?? farmer.farmer_id);
  const farmerName = text(farmer.farmerName ?? farmer.farmer_name);
  if (phone.length !== 10) {
    return errorResponse(
      "Enter a valid 10 digit mobile number",
      400,
      undefined,
      "invalid_phone",
    );
  }

  const linkedUserIds = await loadLinkedUserIds(
    supabase,
    userId,
    phone,
    farmerId,
  );
  if (linkedUserIds instanceof Response) return linkedUserIds;
  if (linkedUserIds.length === 0) {
    return errorResponse(
      "This session is not linked to that farmer number.",
      403,
      undefined,
      "farmer_session_not_linked",
    );
  }
  return { phone, farmerId, farmerName };
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
    const body = record(await req.json());
    const action = text(body.action).toLowerCase();
    const farmer = record(body.farmer);
    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;

    const linkedFarmer = await assertFarmerSession(supabase, userId, farmer);
    if (linkedFarmer instanceof Response) return linkedFarmer;

    const plan = await loadActivePlan(
      supabase,
      text(body.planId ?? body.plan_id),
      text(body.planCode ?? body.plan_code),
    );
    if (!plan) {
      return errorResponse(
        "Stakeholder plan is not available.",
        404,
        undefined,
        "stakeholder_plan_not_found",
      );
    }

    if (action === "submit_interest") {
      const selectedAmount = numberValue(
        body.selectedAmount ?? body.selected_amount,
      );
      const shareUnitValue = numberValue(plan.share_unit_value) ?? 0;
      const minAmount = numberValue(plan.min_amount) ?? 0;
      const maxAmount = numberValue(plan.max_amount) ?? 0;
      const estimatedShares = selectedAmount == null || shareUnitValue <= 0
        ? 0
        : Math.floor(selectedAmount / shareUnitValue);

      if (selectedAmount == null || selectedAmount < minAmount) {
        return errorResponse(
          "Select an amount within the allowed plan range.",
          400,
          undefined,
          "stakeholder_amount_too_low",
        );
      }
      if (maxAmount > 0 && selectedAmount > maxAmount) {
        return errorResponse(
          "Select an amount within the allowed plan range.",
          400,
          undefined,
          "stakeholder_amount_too_high",
        );
      }
      if (estimatedShares < 1) {
        return errorResponse(
          "Selected amount must create at least one estimated share.",
          400,
          undefined,
          "stakeholder_share_estimate_invalid",
        );
      }
      if (
        !boolValue(body.consentInterestOnly) ||
        !boolValue(body.consentNoGuaranteedReturn) ||
        !boolValue(body.consentDataUse)
      ) {
        return errorResponse(
          "Accept all stakeholder consent points before submitting.",
          400,
          undefined,
          "stakeholder_consent_required",
        );
      }

      const planId = text(plan.id);
      const existing = await loadExistingApplication(
        supabase,
        userId,
        planId,
        linkedFarmer,
      );
      const existingStatus = text(existing?.status);
      if (
        existingStatus.length > 0 &&
        existingStatus !== "submitted"
      ) {
        return errorResponse(
          "This stakeholder application is already under review.",
          409,
          undefined,
          "stakeholder_application_locked",
        );
      }

      const row = {
        plan_id: planId,
        user_id: userId,
        farmer_phone: linkedFarmer.phone,
        farmer_id: linkedFarmer.farmerId,
        farmer_name: linkedFarmer.farmerName,
        agri_record_id: text(farmer.agriRecordId ?? farmer.agri_record_id),
        aadhaar_last4: text(farmer.aadhaarLast4 ?? farmer.aadhaar_last4),
        selected_amount: selectedAmount,
        estimated_shares: estimatedShares,
        status: "submitted",
        consent_interest_only: true,
        consent_no_guaranteed_return: true,
        consent_data_use: true,
        farmer_note: text(body.farmerNote ?? body.farmer_note),
        submitted_at: new Date().toISOString(),
      };

      const saveResult = existing?.id
        ? await supabase
          .from("stakeholder_applications")
          .update(row)
          .eq("id", existing.id)
          .select("*")
          .maybeSingle()
        : await supabase
          .from("stakeholder_applications")
          .insert(row)
          .select("*")
          .maybeSingle();
      const { data: saved, error: saveError } = saveResult;
      if (saveError) throw saveError;

      if (saved?.id) {
        const { error: eventError } = await supabase
          .from("stakeholder_application_events")
          .insert({
            application_id: saved.id,
            status: "submitted",
            title: existing?.id ? "Interest updated" : "Interest submitted",
            note: existing?.id
              ? "Farmer updated selected amount or note for Kalsubai Farms review."
              : "Farmer selected amount and consent were saved for Kalsubai Farms review.",
            actor_role: "farmer",
          });
        if (eventError) throw eventError;
      }
    }

    const bundle = await loadApplicationBundle(
      supabase,
      userId,
      plan,
      linkedFarmer,
    );
    return successResponse(bundle, 200, "stakeholder_plan_synced");
  } catch (error) {
    return errorResponse(
      "stakeholder-plan-sync failed",
      500,
      error,
      "stakeholder_plan_sync_failed",
    );
  }
});
