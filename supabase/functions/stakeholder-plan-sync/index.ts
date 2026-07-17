import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  bearerToken,
  hasServerRole,
  loadLinkedUserIds,
  normalizePhone,
  optionalSchemaError,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

const documentBucket = "stakeholder-documents";
const amountStep = 100;

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

async function requireAdminUserId(
  supabase: any,
  req: Request,
): Promise<string | Response> {
  const token = bearerToken(req);
  if (token.length === 0) {
    return errorResponse(
      "Missing auth token",
      401,
      undefined,
      "missing_auth_token",
    );
  }

  const { data: userData, error: userError } = await supabase.auth.getUser(
    token,
  );
  const user = userData?.user;
  if (userError || !user) {
    return errorResponse(
      "Invalid auth token",
      401,
      userError,
      "invalid_auth_token",
    );
  }
  if (!hasServerRole(user, ["admin"], token)) {
    return errorResponse(
      "This account is not enabled for admin review.",
      403,
      undefined,
      "admin_role_required",
    );
  }
  return user.id;
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

function optionalText(body: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = text(body[key]);
    if (value.length > 0) return value;
  }
  return "";
}

function missingFullAadhaarColumn(error: unknown): boolean {
  const raw = String(
    (error as { code?: unknown; message?: unknown; details?: unknown })?.code ??
      (error as { message?: unknown })?.message ??
      (error as { details?: unknown })?.details ??
      error ??
      "",
  ).toLowerCase();
  return optionalSchemaError(error) &&
    (raw.includes("aadhaar_number") ||
      raw.includes("farmer_aadhaar_number"));
}

function optionalDocumentUploadRecordError(error: unknown): boolean {
  const raw = String(
    (error as { code?: unknown; message?: unknown; details?: unknown })?.code ??
      (error as { message?: unknown })?.message ??
      (error as { details?: unknown })?.details ??
      error ??
      "",
  ).toLowerCase();
  return optionalSchemaError(error) ||
    raw.includes("42p01") ||
    raw.includes("stakeholder_document_uploads");
}

function withoutFullAadhaarColumns(row: Record<string, unknown>) {
  const copy = { ...row };
  delete copy.aadhaar_number;
  delete copy.farmer_aadhaar_number;
  return copy;
}

async function recordDocumentUpload(
  supabase: any,
  row: {
    userId: string;
    farmerPhone: string;
    documentKind: string;
    documentPath: string;
    contentType: string;
  },
) {
  const { error } = await supabase
    .from("stakeholder_document_uploads")
    .upsert(
      {
        user_id: row.userId,
        farmer_phone: row.farmerPhone,
        document_kind: row.documentKind,
        document_path: row.documentPath,
        content_type: row.contentType,
      },
      { onConflict: "user_id,document_path" },
    );
  if (error && !optionalDocumentUploadRecordError(error)) throw error;
}

function normalizePan(value: string) {
  return value.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
}

function last4Digits(value: string) {
  const digits = value.replace(/\D/g, "");
  if (digits.length <= 4) return digits;
  return digits.length === 12 ? digits.slice(-4) : "";
}

function aadhaarNumber(value: string) {
  const digits = value.replace(/\D/g, "");
  return digits.length === 12 ? digits : "";
}

function isUploadedDocumentPath(value: string, kind: string) {
  return value.includes(`/${kind}/`) && value.split("/").length >= 3;
}

function landRecordFieldKey(label: string) {
  switch (label.toLowerCase().replace(/[^a-z0-9]/g, "")) {
    case "surveygatnumber":
    case "surveygat":
    case "surveynumber":
    case "gatnumber":
    case "gatno":
    case "surveyno":
      return "surveyGatNumber";
    case "subdivisionnumber":
    case "subdivision":
    case "hissanumber":
    case "hissano":
    case "subdivisionno":
      return "subDivisionNumber";
    case "village":
      return "village";
    case "taluka":
    case "tehsil":
      return "taluka";
    case "district":
      return "district";
    case "ownernameon712":
    case "ownername":
    case "landowner":
      return "ownerName";
    case "landarea":
    case "area":
    case "totalarea":
    case "totalholding":
      return "landArea";
    case "cultivablearea":
    case "cultivatedarea":
    case "potkharabarea":
    case "noncultivablearea":
      return "cultivableArea";
    case "khatanumber":
    case "khatano":
    case "accountnumber":
    case "accountno":
      return "khataNumber";
    case "croplanduse":
    case "crop":
    case "landuse":
      return "cropOrUse";
    case "irrigationsource":
    case "irrigation":
    case "watersource":
      return "irrigationSource";
    case "mutationentrynumber":
    case "mutationentry":
    case "mutationnumber":
    case "ferfarnumber":
    case "ferfarno":
      return "mutationEntryNumber";
    case "landrevenue":
    case "revenue":
    case "assessment":
      return "landRevenue";
    case "otherrightsencumbrance":
    case "otherrights":
    case "encumbrance":
    case "loancharge":
    case "boja":
      return "otherRights";
  }
  return "";
}

function hasCompleteLandRecordDetails(value: string) {
  const fields = new Set<string>();
  for (const rawLine of value.split(/\r?\n/)) {
    const separatorIndex = rawLine.indexOf(":");
    if (separatorIndex <= 0) continue;
    const key = landRecordFieldKey(rawLine.slice(0, separatorIndex));
    const fieldValue = rawLine.slice(separatorIndex + 1).trim();
    if (key.length > 0 && fieldValue.length > 0) fields.add(key);
  }
  return [
    "surveyGatNumber",
    "village",
    "taluka",
    "district",
    "ownerName",
    "landArea",
  ].every((field) => fields.has(field));
}

const defaultPlan = {
  plan_code: "kalsubai-farmer-stakeholder-v1",
  title: "Kalsubai Farms Farmer Stakeholder Plan",
  summary:
    "Apply to buy farmer stakeholder shares. Final allocation is confirmed only after Kalsubai Farms review.",
  currency: "INR",
  share_unit_value: 100,
  min_amount: 100,
  max_amount: 25000,
  status: "active",
  purpose: [
    "Let registered farmers apply to buy Kalsubai Farms stakeholder shares.",
    "Keep farmer identity, PAN, 7/12 land record, bank, selected amount and payment details in one review-ready record.",
    "Prepare an auditable application before final approval and allocation.",
  ],
  use_of_funds: [
    "Farm aggregation and procurement readiness",
    "Millet quality, grading and packaging operations",
    "Traceability, farmer services and working capital planning",
  ],
  stages: [
    "Submit farmer account, KYC, 7/12 land record, bank and payment details",
    "Kalsubai Farms reviews farmer record, payment and plan capacity",
    "Approved allocation and documents are updated after admin review",
  ],
  risk_notes: [
    "Payment confirmation is not a confirmed share issue.",
    "Returns are not guaranteed and depend on final approval and business performance.",
    "Final terms must be reviewed before any allocation.",
  ],
  terms: [
    "The selected amount starts an application for review.",
    "Estimated shares are calculated from the current plan share value.",
    "Kalsubai Farms may approve, revise or reject the application after review.",
  ],
};

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

async function ensureActivePlan(supabase: any, planId = "", planCode = "") {
  const existing = await loadActivePlan(supabase, planId, planCode);
  if (existing) return existing;

  const row = {
    ...defaultPlan,
    plan_code: planCode.length > 0 ? planCode : defaultPlan.plan_code,
  };
  const { data: plan, error } = await supabase
    .from("stakeholder_plans")
    .upsert(row, { onConflict: "plan_code" })
    .select("*")
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

function validateApplicationInput(
  body: Record<string, unknown>,
  plan: Record<string, unknown>,
  rawFarmer: Record<string, unknown>,
) {
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
  const steppedAmount = Math.round(selectedAmount / amountStep) * amountStep;
  if (Math.abs(selectedAmount - steppedAmount) > 0.001) {
    return errorResponse(
      "Amount must increase in Rs 100 steps.",
      400,
      undefined,
      "stakeholder_amount_step_invalid",
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

  const farmerFullName = optionalText(
    body,
    "farmerFullName",
    "farmer_full_name",
  );
  const farmerFatherName = optionalText(
    body,
    "farmerFatherName",
    "farmer_father_name",
  );
  const farmerMobileNumber = normalizePhone(optionalText(
    body,
    "farmerMobileNumber",
    "farmer_mobile_number",
  ));
  const savedAadhaarLast4 = last4Digits(text(
    rawFarmer.aadhaarLast4 ?? rawFarmer.aadhaar_last4,
  ));
  const savedAadhaarNumber = aadhaarNumber(text(
    rawFarmer.aadhaarNumber ?? rawFarmer.aadhaar_number,
  ));
  const inputAadhaarNumber = aadhaarNumber(optionalText(
    body,
    "farmerAadhaarNumber",
    "farmer_aadhaar_number",
    "aadhaarNumber",
    "aadhaar_number",
  ));
  const farmerAadhaarNumber = inputAadhaarNumber.length > 0
    ? inputAadhaarNumber
    : savedAadhaarNumber;
  const inputAadhaarLast4 = last4Digits(optionalText(
    body,
    "farmerAadhaarLast4",
    "farmer_aadhaar_last4",
  ));
  const farmerAadhaarLast4 = inputAadhaarLast4.length > 0
    ? inputAadhaarLast4
    : farmerAadhaarNumber.length === 12
    ? last4Digits(farmerAadhaarNumber)
    : savedAadhaarLast4;
  const farmerAgriRecordId = optionalText(
    body,
    "farmerAgriRecordId",
    "farmer_agri_record_id",
    "agriRecordId",
    "agri_record_id",
  ) || text(rawFarmer.agriRecordId ?? rawFarmer.agri_record_id);
  const farmerAddress = optionalText(body, "farmerAddress", "farmer_address");
  const farmerVillage = optionalText(body, "farmerVillage", "farmer_village");
  const farmerTaluka = optionalText(body, "farmerTaluka", "farmer_taluka");
  const farmerDistrict = optionalText(
    body,
    "farmerDistrict",
    "farmer_district",
  );
  const farmerPincode = optionalText(
    body,
    "farmerPincode",
    "farmer_pincode",
  ).replace(/\D/g, "");
  const farmerTotalLandAcres = optionalText(
    body,
    "farmerTotalLandAcres",
    "farmer_total_land_acres",
  );
  const nomineeName = optionalText(body, "nomineeName", "nominee_name");
  const nomineeAddress = optionalText(
    body,
    "nomineeAddress",
    "nominee_address",
  );
  const nomineeMobileNumber = normalizePhone(optionalText(
    body,
    "nomineeMobileNumber",
    "nominee_mobile_number",
  ));
  const nomineeSignature = optionalText(
    body,
    "nomineeSignature",
    "nominee_signature",
  );
  const nomineeCount =
    (numberValue(body.nomineeCount ?? body.nominee_count) ?? 1) >= 2 ? 2 : 1;
  const nominee2Name = nomineeCount === 2
    ? optionalText(body, "nominee2Name", "nominee2_name")
    : "";
  const nominee2Address = nomineeCount === 2
    ? optionalText(body, "nominee2Address", "nominee2_address")
    : "";
  const nominee2MobileNumber = nomineeCount === 2
    ? normalizePhone(optionalText(
      body,
      "nominee2MobileNumber",
      "nominee2_mobile_number",
    ))
    : "";
  const nominee2Signature = nomineeCount === 2
    ? optionalText(body, "nominee2Signature", "nominee2_signature")
    : "";
  const farmerSignature = optionalText(
    body,
    "farmerSignature",
    "farmer_signature",
  );
  const contractReadAccepted = boolValue(
    body.contractReadAccepted ?? body.contract_read_accepted,
  );
  const totalLandAcres = Number(farmerTotalLandAcres);
  if (
    farmerFullName.length < 2 ||
    farmerFatherName.length < 2 ||
    !/^[6-9][0-9]{9}$/.test(farmerMobileNumber) ||
    (farmerAadhaarNumber.length !== 12 && farmerAadhaarLast4.length !== 4) ||
    farmerAgriRecordId.length === 0 ||
    farmerAddress.length < 5 ||
    farmerVillage.length < 2 ||
    farmerTaluka.length < 2 ||
    farmerDistrict.length < 2 ||
    !/^[1-9][0-9]{5}$/.test(farmerPincode) ||
    !Number.isFinite(totalLandAcres) ||
    totalLandAcres <= 0 ||
    nomineeName.length < 2 ||
    nomineeAddress.length < 5 ||
    !/^[6-9][0-9]{9}$/.test(nomineeMobileNumber) ||
    !isUploadedDocumentPath(nomineeSignature, "nominee_signature") ||
    (nomineeCount === 2 &&
      (nominee2Name.length < 2 ||
        nominee2Address.length < 5 ||
        !/^[6-9][0-9]{9}$/.test(nominee2MobileNumber) ||
        !isUploadedDocumentPath(nominee2Signature, "nominee2_signature")))
  ) {
    return errorResponse(
      "Complete farmer and nominee details before selecting the amount.",
      400,
      undefined,
      "stakeholder_farmer_details_required",
    );
  }
  if (
    !contractReadAccepted ||
    !isUploadedDocumentPath(farmerSignature, "farmer_signature")
  ) {
    return errorResponse(
      "Read the contract and draw farmer signature before submitting interest.",
      400,
      undefined,
      "stakeholder_contract_signature_required",
    );
  }

  const panNumber = normalizePan(optionalText(body, "panNumber", "pan_number"));
  const panHolderName = optionalText(
    body,
    "panHolderName",
    "pan_holder_name",
  );
  const panDocumentPath = optionalText(
    body,
    "panDocumentPath",
    "pan_document_path",
  );
  const landRecordDocumentPath = optionalText(
    body,
    "landRecordDocumentPath",
    "land_record_document_path",
  );
  const landRecordDetails = optionalText(
    body,
    "landRecordDetails",
    "land_record_details",
  );
  const hasPanManualDetails = /^[A-Z]{5}[0-9]{4}[A-Z]$/.test(panNumber);
  if (!hasPanManualDetails && panDocumentPath.length === 0) {
    return errorResponse(
      "Enter a valid PAN number or upload a clear PAN document.",
      400,
      undefined,
      "stakeholder_pan_proof_required",
    );
  }
  if (
    !hasCompleteLandRecordDetails(landRecordDetails) &&
    landRecordDocumentPath.length === 0
  ) {
    return errorResponse(
      "Enter 7/12 land details or upload the 7/12 land record image.",
      400,
      undefined,
      "stakeholder_land_record_required",
    );
  }

  const accountHolderName = optionalText(
    body,
    "accountHolderName",
    "account_holder_name",
  );
  const bankName = optionalText(body, "bankName", "bank_name");
  const bankAccountNumber = optionalText(
    body,
    "bankAccountNumber",
    "bank_account_number",
  ).replace(/\s/g, "");
  const ifscCode = optionalText(body, "ifscCode", "ifsc_code").toUpperCase();
  const upiId = optionalText(body, "upiId", "upi_id");
  const passbookDocumentPath = optionalText(
    body,
    "passbookDocumentPath",
    "passbook_document_path",
  );
  const hasBankManualDetails = accountHolderName.length >= 2 &&
    bankName.length >= 2 &&
    /^[0-9]{6,20}$/.test(bankAccountNumber) &&
    /^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifscCode);
  if (!hasBankManualDetails && passbookDocumentPath.length === 0) {
    return errorResponse(
      "Enter valid bank account details or upload passbook/cancelled cheque image.",
      400,
      undefined,
      "stakeholder_bank_proof_required",
    );
  }

  return {
    selectedAmount,
    estimatedShares,
    farmerFullName,
    farmerFatherName,
    farmerMobileNumber,
    farmerAadhaarNumber,
    farmerAadhaarLast4,
    farmerAddress,
    farmerVillage,
    farmerTaluka,
    farmerDistrict,
    farmerPincode,
    farmerTotalLandAcres,
    farmerAgriRecordId,
    nomineeName,
    nomineeAddress,
    nomineeMobileNumber,
    nomineeSignature,
    nomineeCount,
    nominee2Name,
    nominee2Address,
    nominee2MobileNumber,
    nominee2Signature,
    farmerSignature,
    contractReadAccepted,
    panNumber,
    panHolderName,
    panDocumentPath,
    landRecordDetails,
    landRecordDocumentPath,
    accountHolderName,
    bankName,
    bankAccountNumber,
    ifscCode,
    upiId,
    passbookDocumentPath,
    farmerNote: optionalText(body, "farmerNote", "farmer_note"),
  };
}

async function saveApplication(
  supabase: any,
  options: {
    existing: Record<string, unknown> | null;
    plan: Record<string, unknown>;
    userId: string;
    farmer: { phone: string; farmerId: string; farmerName: string };
    rawFarmer: Record<string, unknown>;
    input: Record<string, unknown>;
    paymentMethod: string;
    paymentStatus: string;
    status?: string;
    extra?: Record<string, unknown>;
  },
) {
  const rawAadhaarLast4 = last4Digits(text(
    options.rawFarmer.aadhaarLast4 ?? options.rawFarmer.aadhaar_last4,
  ));
  const rawAadhaarNumber = aadhaarNumber(text(
    options.rawFarmer.aadhaarNumber ?? options.rawFarmer.aadhaar_number,
  ));
  const inputAadhaarNumber = aadhaarNumber(text(
    options.input.farmerAadhaarNumber ??
      options.input.farmer_aadhaar_number ??
      options.input.aadhaarNumber ??
      options.input.aadhaar_number,
  ));
  const farmerAadhaarNumber = inputAadhaarNumber.length > 0
    ? inputAadhaarNumber
    : rawAadhaarNumber;
  const inputAadhaarLast4 = last4Digits(text(
    options.input.farmerAadhaarLast4 ?? options.input.farmer_aadhaar_last4,
  ));
  const farmerAadhaarLast4 = inputAadhaarLast4.length > 0
    ? inputAadhaarLast4
    : farmerAadhaarNumber.length === 12
    ? last4Digits(farmerAadhaarNumber)
    : rawAadhaarLast4;
  const farmerAgriRecordId = text(
    options.input.farmerAgriRecordId ??
      options.input.farmer_agri_record_id ??
      options.rawFarmer.agriRecordId ??
      options.rawFarmer.agri_record_id,
  );
  const row = {
    plan_id: text(options.plan.id),
    user_id: options.userId,
    farmer_phone: options.farmer.phone,
    farmer_id: options.farmer.farmerId,
    farmer_name: options.farmer.farmerName,
    agri_record_id: farmerAgriRecordId,
    aadhaar_number: farmerAadhaarNumber,
    aadhaar_last4: farmerAadhaarLast4,
    farmer_full_name: options.input.farmerFullName,
    farmer_father_name: options.input.farmerFatherName,
    farmer_mobile_number: options.input.farmerMobileNumber,
    farmer_aadhaar_number: farmerAadhaarNumber,
    farmer_aadhaar_last4: farmerAadhaarLast4,
    farmer_address: options.input.farmerAddress,
    farmer_village: options.input.farmerVillage,
    farmer_taluka: options.input.farmerTaluka,
    farmer_district: options.input.farmerDistrict,
    farmer_pincode: options.input.farmerPincode,
    farmer_total_land_acres: options.input.farmerTotalLandAcres,
    farmer_photo_path: "",
    nominee_name: options.input.nomineeName,
    nominee_address: options.input.nomineeAddress,
    nominee_mobile_number: options.input.nomineeMobileNumber,
    nominee_signature: options.input.nomineeSignature,
    nominee_count: options.input.nomineeCount,
    nominee2_name: options.input.nominee2Name,
    nominee2_address: options.input.nominee2Address,
    nominee2_mobile_number: options.input.nominee2MobileNumber,
    nominee2_signature: options.input.nominee2Signature,
    farmer_signature: options.input.farmerSignature,
    contract_read_accepted: options.input.contractReadAccepted,
    selected_amount: options.input.selectedAmount,
    estimated_shares: options.input.estimatedShares,
    status: options.status ?? "submitted",
    consent_interest_only: true,
    consent_no_guaranteed_return: true,
    consent_data_use: true,
    farmer_note: optionalText(options.input, "farmerNote", "farmer_note"),
    pan_number: options.input.panNumber,
    pan_holder_name: options.input.panHolderName,
    pan_document_path: options.input.panDocumentPath,
    land_record_details: options.input.landRecordDetails,
    land_record_document_path: options.input.landRecordDocumentPath,
    account_holder_name: options.input.accountHolderName,
    bank_name: options.input.bankName,
    bank_account_number: options.input.bankAccountNumber,
    ifsc_code: options.input.ifscCode,
    upi_id: options.input.upiId,
    passbook_document_path: options.input.passbookDocumentPath,
    payment_method: options.paymentMethod,
    payment_status: options.paymentStatus,
    submitted_at: new Date().toISOString(),
    ...(options.extra ?? {}),
  };

  const existingId = text(options.existing?.id);
  async function saveRow(candidate: Record<string, unknown>) {
    return existingId.length > 0
      ? await supabase
        .from("stakeholder_applications")
        .update(candidate)
        .eq("id", existingId)
        .select("*")
        .maybeSingle()
      : await supabase
        .from("stakeholder_applications")
        .insert(candidate)
        .select("*")
        .maybeSingle();
  }

  let saveResult = await saveRow(row);
  if (saveResult.error && missingFullAadhaarColumn(saveResult.error)) {
    saveResult = await saveRow(withoutFullAadhaarColumns(row));
  }
  const { data: saved, error } = saveResult;
  if (error) throw error;
  return saved as Record<string, unknown>;
}

async function addEvent(
  supabase: any,
  applicationId: unknown,
  status: string,
  title: string,
  note: string,
) {
  if (text(applicationId).length === 0) return;
  const { error } = await supabase
    .from("stakeholder_application_events")
    .insert({
      application_id: applicationId,
      status,
      title,
      note,
      actor_role: "farmer",
    });
  if (error) throw error;
}

async function addAdminEvent(
  supabase: any,
  applicationId: unknown,
  status: string,
  title: string,
  note: string,
) {
  if (text(applicationId).length === 0) return;
  const { error } = await supabase
    .from("stakeholder_application_events")
    .insert({
      application_id: applicationId,
      status,
      title,
      note,
      actor_role: "admin",
    });
  if (error) throw error;
}

async function loadEventsForApplications(
  supabase: any,
  applicationIds: string[],
) {
  if (applicationIds.length === 0) return [];
  const { data, error } = await supabase
    .from("stakeholder_application_events")
    .select("*")
    .in("application_id", applicationIds)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

async function adminListApplications(supabase: any) {
  const { data: applications, error } = await supabase
    .from("stakeholder_applications")
    .select("*")
    .order("updated_at", { ascending: false })
    .limit(200);
  if (error) throw error;

  const rows = Array.isArray(applications) ? applications : [];
  const applicationIds = rows
    .map((row) => text(row.id))
    .filter((value) => value.length > 0);
  const events = await loadEventsForApplications(supabase, applicationIds);
  return { applications: rows, events };
}

async function adminReviewApplication(
  supabase: any,
  adminUserId: string,
  body: Record<string, unknown>,
) {
  const applicationId = optionalText(body, "applicationId", "application_id");
  const status = optionalText(body, "status").toLowerCase();
  const adminNote = optionalText(body, "adminNote", "admin_note");
  if (applicationId.length === 0) {
    return errorResponse(
      "Select a stakeholder application.",
      400,
      undefined,
      "stakeholder_application_required",
    );
  }
  if (!["under_review", "approved", "rejected"].includes(status)) {
    return errorResponse(
      "Select a valid review status.",
      400,
      undefined,
      "stakeholder_review_status_invalid",
    );
  }
  if (status === "rejected" && adminNote.length < 5) {
    return errorResponse(
      "Add a clear rejection reason before rejecting.",
      400,
      undefined,
      "stakeholder_rejection_reason_required",
    );
  }

  const now = new Date().toISOString();
  const { data: saved, error } = await supabase
    .from("stakeholder_applications")
    .update({
      status,
      admin_note: adminNote,
      reviewed_by: adminUserId,
      reviewed_at: now,
      kyc_reviewed_at: now,
    })
    .eq("id", applicationId)
    .select("*")
    .maybeSingle();
  if (error) throw error;
  if (!saved) {
    return errorResponse(
      "Stakeholder application was not found.",
      404,
      undefined,
      "stakeholder_application_not_found",
    );
  }

  const title = status === "approved"
    ? "Application approved"
    : status === "rejected"
    ? "Application rejected"
    : "Application under review";
  const defaultNote = status === "approved"
    ? "Kalsubai Farms admin approved this stakeholder request for payment."
    : "Kalsubai Farms admin started review of this stakeholder request.";
  await addAdminEvent(
    supabase,
    applicationId,
    status,
    title,
    adminNote.length > 0 ? adminNote : defaultNote,
  );
  const events = await loadEventsForApplications(supabase, [applicationId]);
  return { application: saved, events };
}

async function adminSignedDocumentUrl(
  supabase: any,
  body: Record<string, unknown>,
) {
  const documentPath = optionalText(body, "documentPath", "document_path");
  const expiresInRaw = numberValue(body.expiresIn ?? body.expires_in);
  const expiresIn = Math.min(Math.max(expiresInRaw ?? 300, 60), 900);
  if (documentPath.length === 0) {
    return errorResponse(
      "Select a stakeholder document.",
      400,
      undefined,
      "stakeholder_document_required",
    );
  }
  const { data, error } = await supabase.storage
    .from(documentBucket)
    .createSignedUrl(documentPath, expiresIn);
  if (error) throw error;
  return {
    documentPath,
    signedUrl: text(data?.signedUrl),
    expiresIn,
  };
}

async function createRazorpayOrder(amountSubunits: number, receipt: string) {
  const keyId = text(Deno.env.get("RAZORPAY_KEY_ID"));
  const keySecret = text(Deno.env.get("RAZORPAY_KEY_SECRET"));
  if (keyId.length === 0 || keySecret.length === 0) {
    return {
      error: errorResponse(
        "Razorpay is not configured yet.",
        503,
        undefined,
        "razorpay_not_configured",
      ),
    };
  }

  const response = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      "Authorization": `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: amountSubunits,
      currency: "INR",
      receipt,
      payment_capture: 1,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    return {
      error: errorResponse(
        "Could not create Razorpay order.",
        502,
        data,
        "razorpay_order_failed",
      ),
    };
  }
  return {
    order: data as Record<string, unknown>,
    keyId,
  };
}

async function hmacSha256Hex(secret: string, message: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function ensureDocumentBucket(supabase: any) {
  const bucketOptions = {
    public: false,
    fileSizeLimit: 8388608,
    allowedMimeTypes: ["image/jpeg", "image/png", "image/webp"],
  };
  const { error } = await supabase.storage.createBucket(
    documentBucket,
    bucketOptions,
  );
  const message = String(error?.message ?? error ?? "").toLowerCase();
  if (
    error &&
    !message.includes("already") &&
    !message.includes("exists") &&
    !message.includes("duplicate")
  ) {
    throw error;
  }
  const { error: updateError } = await supabase.storage.updateBucket(
    documentBucket,
    bucketOptions,
  );
  if (updateError) throw updateError;
}

function bytesFromBase64(raw: string) {
  const binary = atob(raw);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function safeFileName(raw: string, fallback: string) {
  const name = raw.split(/[\\/]/).pop() || fallback;
  const cleaned = name
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return cleaned.length > 0 ? cleaned : fallback;
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

    if (action.startsWith("admin_")) {
      const adminUserId = await requireAdminUserId(supabase, req);
      if (adminUserId instanceof Response) return adminUserId;

      if (action === "admin_list_applications") {
        const payload = await adminListApplications(supabase);
        return successResponse(
          payload,
          200,
          "stakeholder_admin_applications_synced",
        );
      }
      if (action === "admin_review_application") {
        const payload = await adminReviewApplication(
          supabase,
          adminUserId,
          body,
        );
        if (payload instanceof Response) return payload;
        return successResponse(
          payload,
          200,
          "stakeholder_admin_application_reviewed",
        );
      }
      if (action === "admin_signed_document_url") {
        await ensureDocumentBucket(supabase);
        const payload = await adminSignedDocumentUrl(supabase, body);
        if (payload instanceof Response) return payload;
        return successResponse(
          payload,
          200,
          "stakeholder_admin_document_url_created",
        );
      }
      return errorResponse(
        "Unknown stakeholder admin action.",
        400,
        undefined,
        "stakeholder_admin_action_unknown",
      );
    }

    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;

    const linkedFarmer = await assertFarmerSession(supabase, userId, farmer);
    if (linkedFarmer instanceof Response) return linkedFarmer;

    if (action === "upload_document") {
      await ensureDocumentBucket(supabase);
      const kind = optionalText(body, "documentKind", "document_kind");
      if (
        kind !== "pan" &&
        kind !== "land_record" &&
        kind !== "passbook" &&
        kind !== "bank_transfer" &&
        kind !== "farmer_signature" &&
        kind !== "nominee_signature" &&
        kind !== "nominee2_signature"
      ) {
        return errorResponse(
          "Select a valid document type.",
          400,
          undefined,
          "stakeholder_document_kind_invalid",
        );
      }
      const imageBase64 = optionalText(body, "imageBase64", "image_base64");
      const contentType = optionalText(body, "contentType", "content_type");
      if (
        imageBase64.length === 0 ||
        !["image/jpeg", "image/png", "image/webp"].includes(contentType)
      ) {
        return errorResponse(
          "Upload a JPG, PNG or WebP document image.",
          400,
          undefined,
          "stakeholder_document_invalid",
        );
      }
      const fileName = safeFileName(
        optionalText(body, "fileName", "file_name"),
        `${kind}.jpg`,
      );
      const path = `${userId}/${kind}/${Date.now()}-${fileName}`;
      const { error: uploadError } = await supabase.storage
        .from(documentBucket)
        .upload(
          path,
          new Blob([bytesFromBase64(imageBase64)], {
            type: contentType,
          }),
          {
            contentType,
            upsert: false,
          },
        );
      if (uploadError) throw uploadError;
      await recordDocumentUpload(supabase, {
        userId,
        farmerPhone: linkedFarmer.phone,
        documentKind: kind,
        documentPath: path,
        contentType,
      });
      return successResponse(
        { documentPath: path, documentKind: kind },
        200,
        "stakeholder_document_uploaded",
      );
    }

    const plan = await ensureActivePlan(
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

    if (action === "load" || action.length === 0) {
      await ensureDocumentBucket(supabase);
      const bundle = await loadApplicationBundle(
        supabase,
        userId,
        plan,
        linkedFarmer,
      );
      return successResponse(bundle, 200, "stakeholder_plan_synced");
    }

    const planId = text(plan.id);
    const existing = await loadExistingApplication(
      supabase,
      userId,
      planId,
      linkedFarmer,
    );
    const existingStatus = text(existing?.status);
    const existingPaymentStatus = text(existing?.payment_status);
    const paymentComplete = existingPaymentStatus === "gateway_verified" ||
      existingPaymentStatus === "bank_transfer_submitted";
    if (action === "submit_interest" && existingStatus.length > 0) {
      const bundle = await loadApplicationBundle(
        supabase,
        userId,
        plan,
        linkedFarmer,
      );
      return successResponse(
        bundle,
        200,
        "stakeholder_application_already_submitted",
      );
    }
    if (action === "create_razorpay_order") {
      if (existingStatus !== "approved" || paymentComplete) {
        return errorResponse(
          paymentComplete
            ? "Payment is already verified for this application."
            : "Payment starts after Kalsubai Farms approves the application.",
          409,
          undefined,
          paymentComplete
            ? "stakeholder_payment_already_verified"
            : "stakeholder_payment_requires_approval",
        );
      }
    } else if (action === "verify_razorpay_payment") {
      if (
        existingStatus !== "approved" ||
        existingPaymentStatus !== "gateway_order_created"
      ) {
        return errorResponse(
          "Start payment only after the application is approved.",
          409,
          undefined,
          "stakeholder_payment_not_ready",
        );
      }
    } else if (
      action === "submit_bank_transfer" &&
      (existingStatus !== "approved" || paymentComplete)
    ) {
      return errorResponse(
        "Bank transfer starts after Kalsubai Farms approves the application.",
        409,
        undefined,
        "stakeholder_payment_requires_approval",
      );
    }

    if (action === "submit_interest" || action === "submit_bank_transfer") {
      const input = validateApplicationInput(body, plan, farmer);
      if (input instanceof Response) return input;

      const bankTransferReference = optionalText(
        body,
        "bankTransferReference",
        "bank_transfer_reference",
      );
      const bankTransferProofPath = optionalText(
        body,
        "bankTransferProofPath",
        "bank_transfer_proof_path",
      );
      if (
        action === "submit_bank_transfer" &&
        (bankTransferReference.length === 0 ||
          bankTransferProofPath.length === 0)
      ) {
        return errorResponse(
          "Add bank transfer reference and proof before submitting.",
          400,
          undefined,
          "stakeholder_bank_transfer_required",
        );
      }

      const saved = await saveApplication(supabase, {
        existing,
        plan,
        userId,
        farmer: linkedFarmer,
        rawFarmer: farmer,
        input,
        paymentMethod: action === "submit_bank_transfer"
          ? "bank_transfer"
          : "none",
        paymentStatus: action === "submit_bank_transfer"
          ? "bank_transfer_submitted"
          : "pending",
        status: action === "submit_bank_transfer" ? "approved" : "submitted",
        extra: {
          bank_transfer_reference: bankTransferReference,
          bank_transfer_proof_path: bankTransferProofPath,
        },
      });
      await addEvent(
        supabase,
        saved.id,
        "submitted",
        action === "submit_bank_transfer"
          ? "Bank transfer submitted"
          : "Application submitted",
        "Farmer account, KYC and selected amount were saved for review.",
      );
    } else if (action === "create_razorpay_order") {
      const input = validateApplicationInput(body, plan, farmer);
      if (input instanceof Response) return input;

      const amountSubunits = Math.round(Number(input.selectedAmount) * 100);
      const receipt = `stake-${Date.now()}`.slice(0, 40);
      const created = await createRazorpayOrder(amountSubunits, receipt);
      if (created.error) return created.error;
      const order = created.order!;
      const razorpayOrderId = text(order.id);
      const saved = await saveApplication(supabase, {
        existing,
        plan,
        userId,
        farmer: linkedFarmer,
        rawFarmer: farmer,
        input,
        paymentMethod: "razorpay",
        paymentStatus: "gateway_order_created",
        status: "approved",
        extra: {
          razorpay_order_id: razorpayOrderId,
        },
      });
      await addEvent(
        supabase,
        saved.id,
        "submitted",
        "Razorpay payment started",
        "Farmer created a payment order for stakeholder review.",
      );
      const bundle = await loadApplicationBundle(
        supabase,
        userId,
        plan,
        linkedFarmer,
      );
      return successResponse(
        {
          ...bundle,
          order: {
            keyId: created.keyId,
            orderId: razorpayOrderId,
            amountSubunits,
            currency: text(order.currency) || "INR",
            receipt,
          },
        },
        200,
        "stakeholder_razorpay_order_created",
      );
    } else if (action === "verify_razorpay_payment") {
      const razorpayOrderId = optionalText(
        body,
        "razorpayOrderId",
        "razorpay_order_id",
      );
      const razorpayPaymentId = optionalText(
        body,
        "razorpayPaymentId",
        "razorpay_payment_id",
      );
      const razorpaySignature = optionalText(
        body,
        "razorpaySignature",
        "razorpay_signature",
      );
      const keySecret = text(Deno.env.get("RAZORPAY_KEY_SECRET"));
      if (keySecret.length === 0) {
        return errorResponse(
          "Razorpay is not configured yet.",
          503,
          undefined,
          "razorpay_not_configured",
        );
      }
      const expected = await hmacSha256Hex(
        keySecret,
        `${razorpayOrderId}|${razorpayPaymentId}`,
      );
      if (
        razorpayOrderId.length === 0 ||
        razorpayPaymentId.length === 0 ||
        razorpaySignature.length === 0 ||
        expected !== razorpaySignature
      ) {
        return errorResponse(
          "Payment verification failed.",
          400,
          undefined,
          "razorpay_signature_invalid",
        );
      }
      if (
        !existing?.id || text(existing.razorpay_order_id) !== razorpayOrderId
      ) {
        return errorResponse(
          "Payment order was not found for this farmer.",
          404,
          undefined,
          "razorpay_order_not_found",
        );
      }
      const { data: saved, error: saveError } = await supabase
        .from("stakeholder_applications")
        .update({
          razorpay_order_id: razorpayOrderId,
          razorpay_payment_id: razorpayPaymentId,
          razorpay_signature: razorpaySignature,
          payment_method: "razorpay",
          payment_status: "gateway_verified",
          status: "approved",
          submitted_at: new Date().toISOString(),
        })
        .eq("id", existing.id)
        .select("*")
        .maybeSingle();
      if (saveError) throw saveError;
      await addEvent(
        supabase,
        saved?.id,
        "submitted",
        "Razorpay payment verified",
        "Payment details were verified and saved for admin review.",
      );
    } else {
      return errorResponse(
        "Unknown stakeholder action.",
        400,
        undefined,
        "stakeholder_action_unknown",
      );
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
