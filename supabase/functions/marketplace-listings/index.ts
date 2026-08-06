import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { requireUserId, text } from "../_shared/farmer-links.ts";

type JsonRecord = Record<string, unknown>;

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function record(raw: unknown): JsonRecord {
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as JsonRecord
    : {};
}

function numberOrNull(raw: unknown): number | null {
  if (raw == null || text(raw).length === 0) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function integerOrNull(raw: unknown): number | null {
  const value = numberOrNull(raw);
  return value == null ? null : Math.round(value);
}

function listingStatus(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["draft", "active", "listed", "paused", "sold", "closed", "expired"]
      .includes(value)
    ? value
    : "listed";
}

function requestStatus(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return [
      "submitted",
      "contacted",
      "accepted",
      "declined",
      "cancelled",
      "closed",
    ]
      .includes(value)
    ? value
    : "submitted";
}

function productCategory(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["crop_lot", "byproduct", "processed_product"].includes(value)
    ? value
    : "crop_lot";
}

function marketplaceGrade(raw: unknown): string {
  const value = text(raw).toUpperCase().replace(/^GRADE\s+/, "");
  return ["A", "B", "C"].includes(value) ? value : "";
}

function listingOwner(row: JsonRecord): string {
  return text(row.farmer_user_id) || text(row.owner_id);
}

function activeListingStatus(raw: unknown): boolean {
  return ["active", "listed"].includes(text(raw).toLowerCase());
}

function lotCode(item: JsonRecord): string {
  const source = text(item.harvest_batch_id) || text(item.inventory_id) ||
    text(item.id).slice(0, 8);
  return `INV-${source}`.replace(/[^a-zA-Z0-9_-]/g, "-").slice(0, 80);
}

function listingPayload(
  item: JsonRecord,
  userId: string,
  body: JsonRecord,
  lotId: string,
): JsonRecord {
  const productName = text(item.product_name) ||
    [text(item.crop), text(item.variety)].filter(Boolean).join(" ") ||
    text(item.inventory_id);
  const price = numberOrNull(
    body.askingPricePerUnit ?? body.asking_price_per_unit ??
      body.askingPricePerKg ?? body.asking_price_per_kg,
  );
  const imageName = text(item.image_name);
  const note = text(body.listingNote ?? body.listing_note);
  const location = text(body.locationLabel ?? body.location_label) ||
    text(item.farm_name);
  const title = text(body.title) || productName;

  return {
    owner_id: userId,
    lot_id: lotId,
    inventory_item_id: text(item.id),
    farmer_user_id: userId,
    farmer_phone: text(item.farmer_phone),
    farmer_id: text(item.farmer_id),
    farm_id: text(item.farm_id) || null,
    farm_name: text(item.farm_name),
    batch_id: text(item.harvest_batch_id) || text(item.inventory_id),
    product_category: productCategory(item.product_category),
    product_name: title,
    crop: text(item.crop),
    variety: text(item.variety),
    quantity: numberOrNull(item.quantity),
    unit: text(item.unit) || "kg",
    grade: marketplaceGrade(item.grade),
    grade_score: integerOrNull(item.grade_score),
    moisture_percent: numberOrNull(item.moisture_percent),
    asking_price_per_unit: price,
    asking_price_per_kg: price,
    listing_note: note,
    title,
    description: text(body.description) || note,
    location_label: location,
    price_unit: text(body.priceUnit ?? body.price_unit) || text(item.unit) ||
      "kg",
    image_paths: imageName.length > 0 ? [imageName] : [],
    status: listingStatus(body.status),
    metadata: {
      source: "farmer_inventory",
      inventory_id: text(item.inventory_id),
      harvest_batch_id: text(item.harvest_batch_id),
      bag_count: integerOrNull(item.bag_count),
      bag_size_kg: numberOrNull(item.bag_size_kg),
      source_flow: text(item.source_flow),
    },
  };
}

async function interestState(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  listings: JsonRecord[],
) {
  const ids = listings.map((row) => text(row.id)).filter(Boolean);
  if (ids.length === 0) return listings;

  const { data, error } = await supabase
    .from("marketplace_purchase_requests")
    .select("listing_id,buyer_user_id,status")
    .in("listing_id", ids);
  if (error) throw error;

  const counts = new Map<string, number>();
  const mine = new Map<string, string>();
  for (const raw of Array.isArray(data) ? data : []) {
    const row = record(raw);
    const id = text(row.listing_id);
    if (!id) continue;
    counts.set(id, (counts.get(id) ?? 0) + 1);
    if (text(row.buyer_user_id) === userId) mine.set(id, text(row.status));
  }

  return listings.map((row) => {
    const id = text(row.id);
    return {
      ...row,
      interest_count: counts.get(id) ?? 0,
      interested_by_me: mine.has(id),
      interest_status: mine.get(id) ?? "",
    };
  });
}

async function enrichFromHarvestLots(
  supabase: ReturnType<typeof createServiceClient>,
  listings: JsonRecord[],
): Promise<JsonRecord[]> {
  const lotIds = [
    ...new Set(listings.map((row) => text(row.lot_id)).filter(Boolean)),
  ];
  if (lotIds.length === 0) return listings;

  const { data, error } = await supabase
    .from("marketplace_harvest_lots")
    .select(
      "id,lot_code,crop,variety,grade,bags,quantity_kg,moisture_percent,metadata",
    )
    .in("id", lotIds);
  if (error) throw error;

  const lots = new Map<string, JsonRecord>();
  for (const raw of Array.isArray(data) ? data : []) {
    const lot = record(raw);
    lots.set(text(lot.id), lot);
  }

  return listings.map((listing) => {
    const lot = lots.get(text(listing.lot_id));
    if (!lot) return listing;
    const metadata = record(lot.metadata);
    const farmSnapshot = record(metadata.farm_snapshot);
    const lotCodeValue = text(lot.lot_code);
    const currentTitle = text(listing.title) || text(listing.product_name);
    const titleHasLotCode = lotCodeValue.length > 0 &&
      currentTitle.includes(lotCodeValue);
    const cropValue = titleHasLotCode
      ? text(lot.crop) || text(listing.crop)
      : text(listing.crop) || text(lot.crop);
    const gradeValue = text(listing.grade) || text(lot.grade);
    const cleanTitle = titleHasLotCode
      ? [cropValue, gradeValue ? `Grade ${gradeValue}` : ""].filter(Boolean)
        .join(" • ")
      : currentTitle;
    const farmName = text(listing.farm_name) || text(farmSnapshot.name);

    return {
      ...listing,
      title: cleanTitle || cropValue,
      product_name: cleanTitle || cropValue,
      crop: cropValue,
      variety: text(listing.variety) || text(lot.variety),
      grade: gradeValue,
      quantity: numberOrNull(listing.quantity) ?? numberOrNull(lot.quantity_kg),
      moisture_percent: numberOrNull(listing.moisture_percent) ??
        numberOrNull(lot.moisture_percent),
      batch_id: text(listing.batch_id) || lotCodeValue,
      farm_name: farmName,
      location_label: text(listing.location_label) || farmName,
    };
  });
}

async function findOwnListing(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  listingId: string,
) {
  const { data, error } = await supabase
    .from("marketplace_listings")
    .select("*")
    .eq("id", listingId)
    .maybeSingle();
  if (error) throw error;
  const row = record(data);
  return listingOwner(row) === userId ? row : null;
}

async function hasFarmerAccess(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
): Promise<boolean> {
  const [profileResult, legacyResult, farmResult] = await Promise.all([
    supabase.from("farmer_phone_profiles")
      .select("user_id")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(1),
    supabase.from("farmer_ai_profiles")
      .select("user_id")
      .eq("user_id", userId)
      .limit(1),
    supabase.from("farms")
      .select("id")
      .eq("user_id", userId)
      .limit(1),
  ]);
  if (profileResult.error) throw profileResult.error;
  if (legacyResult.error) throw legacyResult.error;
  if (farmResult.error) throw farmResult.error;
  return [profileResult.data, legacyResult.data, farmResult.data]
    .some((rows) => Array.isArray(rows) && rows.length > 0);
}

type MarketplaceAccess = {
  farmer: boolean;
  fpcAdminId: string;
  fieldOfficer: boolean;
};

async function marketplaceAccess(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
): Promise<MarketplaceAccess> {
  const [farmer, membershipResult] = await Promise.all([
    hasFarmerAccess(supabase, userId),
    supabase.from("fpc_memberships")
      .select("fpc_id,role,status")
      .eq("user_id", userId)
      .eq("status", "active"),
  ]);
  if (membershipResult.error) throw membershipResult.error;
  const memberships =
    (Array.isArray(membershipResult.data) ? membershipResult.data : []).map(
      record,
    );
  return {
    farmer,
    fpcAdminId: text(
      memberships.find((row) => text(row.role) === "fpc_admin")?.fpc_id,
    ),
    fieldOfficer: memberships.some(
      (row) => text(row.role) === "field_officer",
    ),
  };
}

function actorRole(access: MarketplaceAccess, farmerOwnsListing: boolean) {
  if (farmerOwnsListing && access.farmer) return "farmer";
  if (access.fpcAdminId) return "fpc_admin";
  return "";
}

function relatedRows(
  requests: JsonRecord[],
  offers: JsonRecord[],
  listings: JsonRecord[],
) {
  const offersByRequest = new Map<string, JsonRecord[]>();
  for (const offer of offers) {
    const requestId = text(offer.request_id);
    offersByRequest.set(requestId, [
      ...(offersByRequest.get(requestId) ?? []),
      offer,
    ]);
  }
  const listingById = new Map(
    listings.map((listing) => [text(listing.id), listing]),
  );
  return requests.map((request) => ({
    ...request,
    offers: offersByRequest.get(text(request.id)) ?? [],
    listing: listingById.get(text(request.listing_id)) ?? null,
  }));
}

async function canAccessInventoryItem(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  item: JsonRecord,
): Promise<boolean> {
  if (text(item.user_id) === userId) return true;
  const itemFarmerId = text(item.farmer_id);
  const { data, error } = await supabase.from("farmer_phone_profiles")
    .select("farmer_id")
    .eq("user_id", userId)
    .eq("status", "active")
    .limit(1);
  if (error) throw error;
  const profile = record(Array.isArray(data) ? data[0] : null);
  const currentFarmerId = text(profile.farmer_id);
  return itemFarmerId.length > 0 && itemFarmerId === currentFarmerId;
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
    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const body = record(await req.json());
    const action = text(body.action).toLowerCase();
    const access = await marketplaceAccess(supabase, userId);

    if (access.fieldOfficer && !access.fpcAdminId) {
      return errorResponse(
        "Field Officer accounts cannot access the marketplace.",
        403,
        undefined,
        "field_officer_marketplace_forbidden",
      );
    }
    if (!access.farmer && !access.fpcAdminId) {
      return errorResponse(
        "Marketplace access requires a Farmer or FPC Admin account.",
        403,
        undefined,
        "marketplace_role_required",
      );
    }

    const farmerOnlyActions = new Set([
      "list_farmer",
      "my_listings",
      "list_buy",
      "create_or_update",
      "update_listing",
      "update_status",
      "confirm_final_rate",
    ]);
    const fpcOnlyActions = new Set([
      "list_fpc",
      "list_sell",
      "record_arrival",
      "propose_final_rate",
      "accept_procurement",
      "record_cost",
      "profit_summary",
    ]);
    if (farmerOnlyActions.has(action) && !access.farmer) {
      return errorResponse(
        "This marketplace action is available only to Farmers.",
        403,
        undefined,
        "farmer_marketplace_access_required",
      );
    }
    if (fpcOnlyActions.has(action) && !access.fpcAdminId) {
      return errorResponse(
        "This marketplace action requires an active FPC Admin membership.",
        403,
        undefined,
        "fpc_admin_marketplace_access_required",
      );
    }

    if (["list_farmer", "my_listings"].includes(action)) {
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select("*")
        .or(`farmer_user_id.eq.${userId},owner_id.eq.${userId}`)
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      const rows = await enrichFromHarvestLots(
        supabase,
        (Array.isArray(data) ? data : []).map(record),
      );
      return successResponse(
        {
          listings: await interestState(supabase, userId, rows),
          count: rows.length,
        },
        200,
        "marketplace_farmer_listings",
      );
    }

    if (["list_fpc", "list_sell"].includes(action)) {
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select("*")
        .in("status", ["active", "listed"])
        .or(
          `exclusive_fpc_id.is.null,exclusive_fpc_id.eq.${access.fpcAdminId}`,
        )
        .order("created_at", { ascending: false })
        .limit(300);
      if (error) throw error;
      const rows = await enrichFromHarvestLots(
        supabase,
        (Array.isArray(data) ? data : []).map(record),
      );
      return successResponse(
        {
          listings: await interestState(supabase, userId, rows),
          count: rows.length,
        },
        200,
        "marketplace_sell_listings",
      );
    }

    if (action === "list_buy") {
      const { data, error } = await supabase
        .from("marketplace_input_products")
        .select("*")
        .eq("status", "published")
        .eq("is_verified", true)
        .order("category")
        .order("name")
        .limit(300);
      if (error) throw error;
      return successResponse(
        { products: data ?? [] },
        200,
        "marketplace_buy_products",
      );
    }

    if (action === "listing_detail") {
      const listingId = text(body.listingId ?? body.listing_id);
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select("*")
        .eq("id", listingId)
        .maybeSingle();
      if (error) throw error;
      const row = record(data);
      const exclusiveFpcId = text(row.exclusive_fpc_id);
      if (
        !row.id ||
        (!activeListingStatus(row.status) && listingOwner(row) !== userId) ||
        (
          exclusiveFpcId.length > 0 &&
          listingOwner(row) !== userId &&
          access.fpcAdminId !== exclusiveFpcId
        )
      ) {
        return errorResponse(
          "Listing was not found.",
          404,
          undefined,
          "listing_not_found",
        );
      }
      await supabase.from("marketplace_listings")
        .update({ view_count: (integerOrNull(row.view_count) ?? 0) + 1 })
        .eq("id", listingId);
      const withLot = await enrichFromHarvestLots(supabase, [row]);
      const enriched = await interestState(supabase, userId, withLot);
      return successResponse(
        { listing: enriched[0] },
        200,
        "marketplace_listing_detail",
      );
    }

    if (action === "create_or_update") {
      const inventoryItemId = text(
        body.inventoryItemId ?? body.inventory_item_id,
      );
      const inventoryId = text(body.inventoryId ?? body.inventory_id);
      if (!inventoryItemId && !inventoryId) {
        return errorResponse(
          "Sync this inventory item before listing it.",
          400,
          undefined,
          "inventory_item_required",
        );
      }

      let inventoryQuery = supabase.from("farmer_inventory_items")
        .select("*")
        .limit(1);
      inventoryQuery = inventoryItemId
        ? inventoryQuery.eq("id", inventoryItemId)
        : inventoryQuery.eq("inventory_id", inventoryId);
      const { data: inventory, error: inventoryError } = await inventoryQuery
        .maybeSingle();
      if (inventoryError) throw inventoryError;
      const item = record(inventory);
      if (!item.id || !await canAccessInventoryItem(supabase, userId, item)) {
        return errorResponse(
          "Inventory item was not found for this farmer.",
          404,
          undefined,
          "inventory_item_not_found",
        );
      }
      if ((numberOrNull(item.quantity) ?? 0) <= 0) {
        return errorResponse(
          "Quantity is required before listing.",
          400,
          undefined,
          "listing_quantity_required",
        );
      }

      const { data: complianceData, error: complianceError } = await supabase
        .rpc("submit_crop_program_harvest", {
          p_inventory_item_id: text(item.id),
          p_actor_user_id: userId,
        });
      if (complianceError) throw complianceError;
      const compliance = record(complianceData);
      let cropProgramEnrollmentId = text(compliance.enrollment_id) ||
        text(item.crop_program_enrollment_id);
      let exclusiveFpcId: string | null = null;
      let protectedFloorRate: number | null = null;
      if (compliance.enrolled === true && cropProgramEnrollmentId) {
        const { data: enrollmentData, error: enrollmentError } = await supabase
          .from("fpc_program_enrollments")
          .select("id,fpc_id,status")
          .eq("id", cropProgramEnrollmentId)
          .maybeSingle();
        if (enrollmentError) throw enrollmentError;
        const enrollment = record(enrollmentData);
        const programStatus = text(enrollment.status);
        if (!["compliant", "exclusive_sale", "released"].includes(
          programStatus,
        )) {
          return errorResponse(
            "This harvest cannot be listed until the FPC crop policy is approved.",
            409,
            undefined,
            "crop_program_policy_blocked",
          );
        }
        if (programStatus !== "released") {
          exclusiveFpcId = text(enrollment.fpc_id);
          const { data: evaluationData, error: evaluationError } =
            await supabase
              .from("fpc_compliance_evaluations")
              .select("protected_floor_rate")
              .eq("enrollment_id", cropProgramEnrollmentId)
              .eq("status", "passed")
              .order("attempt_no", { ascending: false })
              .limit(1)
              .maybeSingle();
          if (evaluationError) throw evaluationError;
          protectedFloorRate = numberOrNull(
            record(evaluationData).protected_floor_rate,
          );
        }
      } else if (compliance.enrolled !== true) {
        cropProgramEnrollmentId = "";
      }

      const { data: existingLot, error: lotFindError } = await supabase
        .from("marketplace_harvest_lots")
        .select("id")
        .eq("inventory_item_id", text(item.id))
        .maybeSingle();
      if (lotFindError) throw lotFindError;
      let lotId = text(record(existingLot).id);
      const lotRow = {
        owner_id: userId,
        farm_id: text(item.farm_id) || null,
        inventory_item_id: text(item.id),
        lot_code: lotCode(item),
        crop: text(item.crop) || text(item.product_name),
        variety: text(item.variety),
        grade: marketplaceGrade(item.grade) || null,
        bags: integerOrNull(item.bag_count),
        quantity_kg: numberOrNull(item.quantity),
        moisture_percent: numberOrNull(item.moisture_percent),
        status: "listed",
        crop_program_enrollment_id: cropProgramEnrollmentId || null,
        exclusive_fpc_id: exclusiveFpcId,
        metadata: {
          inventory_id: text(item.inventory_id),
          source_flow: text(item.source_flow),
        },
      };
      if (lotId) {
        const { error } = await supabase.from("marketplace_harvest_lots")
          .update(lotRow).eq("id", lotId);
        if (error) throw error;
      } else {
        const { data, error } = await supabase.from("marketplace_harvest_lots")
          .insert(lotRow).select("id").single();
        if (error) throw error;
        lotId = text(record(data).id);
      }

      const { data: existing, error: findError } = await supabase
        .from("marketplace_listings")
        .select("id")
        .eq("inventory_item_id", text(item.id))
        .maybeSingle();
      if (findError) throw findError;
      const existingId = text(record(existing).id);
      const payload = listingPayload(item, userId, body, lotId);
      payload.crop_program_enrollment_id = cropProgramEnrollmentId || null;
      payload.exclusive_fpc_id = exclusiveFpcId;
      payload.sale_channel = exclusiveFpcId
        ? "fpc_exclusive"
        : "open_market";
      payload.protected_floor_rate = protectedFloorRate;
      const savedResult = existingId
        ? await supabase.from("marketplace_listings")
          .update(payload).eq("id", existingId).select("*").single()
        : await supabase.from("marketplace_listings")
          .insert(payload).select("*").single();
      if (savedResult.error) throw savedResult.error;
      const rows = await interestState(supabase, userId, [
        record(savedResult.data),
      ]);
      return successResponse(
        { listing: rows[0] },
        200,
        "marketplace_listing_saved",
      );
    }

    if (action === "update_listing") {
      const listingId = text(body.listingId ?? body.listing_id);
      const current = await findOwnListing(supabase, userId, listingId);
      if (!current) {
        return errorResponse(
          "Listing was not found.",
          404,
          undefined,
          "listing_not_found",
        );
      }
      const update: JsonRecord = {};
      const title = text(body.title ?? body.productName ?? body.product_name);
      if (title) {
        update.title = title;
        update.product_name = title;
      }
      if (body.description != null || body.listingNote != null) {
        const value = text(body.description ?? body.listingNote);
        update.description = value;
        update.listing_note = value;
      }
      if (
        body.askingPricePerUnit != null || body.asking_price_per_unit != null
      ) {
        const value = numberOrNull(
          body.askingPricePerUnit ?? body.asking_price_per_unit,
        );
        update.asking_price_per_unit = value;
        update.asking_price_per_kg = value;
      }
      if (body.locationLabel != null) {
        update.location_label = text(body.locationLabel);
      }
      if (body.status != null) update.status = listingStatus(body.status);
      const { data, error } = await supabase.from("marketplace_listings")
        .update(update).eq("id", listingId).select("*").single();
      if (error) throw error;
      return successResponse(
        { listing: data },
        200,
        "marketplace_listing_updated",
      );
    }

    if (action === "update_status") {
      const listingId = text(body.listingId ?? body.listing_id);
      const status = listingStatus(body.status);
      const current = await findOwnListing(supabase, userId, listingId);
      if (!current) {
        return errorResponse(
          "Listing was not found.",
          404,
          undefined,
          "listing_not_found",
        );
      }
      const update: JsonRecord = {
        status,
        paused_at: status === "paused" ? new Date().toISOString() : null,
      };
      if (["closed", "sold"].includes(status)) {
        update.closed_reason = text(body.reason) || status;
      }
      const { data, error } = await supabase.from("marketplace_listings")
        .update(update).eq("id", listingId).select("*").single();
      if (error) throw error;
      return successResponse(
        { listing: data },
        200,
        "marketplace_listing_status_updated",
      );
    }

    if (action === "list_negotiations") {
      const workspace = text(body.workspace).toLowerCase();
      const useFpcWorkspace = workspace === "fpc_admin";
      if (useFpcWorkspace && !access.fpcAdminId) {
        return errorResponse(
          "Active FPC Admin membership required.",
          403,
          undefined,
          "fpc_admin_marketplace_access_required",
        );
      }
      if (!useFpcWorkspace && !access.farmer) {
        return errorResponse(
          "Farmer marketplace access required.",
          403,
          undefined,
          "farmer_marketplace_access_required",
        );
      }

      let requests: JsonRecord[] = [];
      let listingRows: JsonRecord[] = [];
      if (useFpcWorkspace) {
        const { data, error } = await supabase
          .from("marketplace_purchase_requests")
          .select("*")
          .eq("fpc_id", access.fpcAdminId)
          .not("listing_id", "is", null)
          .order("updated_at", { ascending: false })
          .limit(300);
        if (error) throw error;
        requests = (Array.isArray(data) ? data : []).map(record);
      } else {
        const { data: ownListings, error: listingError } = await supabase
          .from("marketplace_listings")
          .select("*")
          .or(`farmer_user_id.eq.${userId},owner_id.eq.${userId}`)
          .limit(300);
        if (listingError) throw listingError;
        listingRows = (Array.isArray(ownListings) ? ownListings : [])
          .map(record);
        const listingIds = listingRows.map((row) => text(row.id))
          .filter(Boolean);
        if (listingIds.length > 0) {
          const { data, error } = await supabase
            .from("marketplace_purchase_requests")
            .select("*")
            .in("listing_id", listingIds)
            .order("updated_at", { ascending: false })
            .limit(300);
          if (error) throw error;
          requests = (Array.isArray(data) ? data : []).map(record);
        }
      }

      const listingIds = [
        ...new Set(requests.map((row) => text(row.listing_id)).filter(Boolean)),
      ];
      if (listingRows.length === 0 && listingIds.length > 0) {
        const { data, error } = await supabase.from("marketplace_listings")
          .select("*").in("id", listingIds);
        if (error) throw error;
        listingRows = (Array.isArray(data) ? data : []).map(record);
      }
      const requestIds = requests.map((row) => text(row.id)).filter(Boolean);
      let offers: JsonRecord[] = [];
      if (requestIds.length > 0) {
        const { data, error } = await supabase
          .from("marketplace_offer_events")
          .select("*")
          .in("request_id", requestIds)
          .order("created_at", { ascending: false });
        if (error) throw error;
        offers = (Array.isArray(data) ? data : []).map(record);
      }
      return successResponse(
        {
          negotiations: relatedRows(requests, offers, listingRows),
          count: requests.length,
        },
        200,
        "marketplace_negotiations",
      );
    }

    if (action === "list_orders") {
      const workspace = text(body.workspace).toLowerCase();
      const useFpcWorkspace = workspace === "fpc_admin";
      if (useFpcWorkspace && !access.fpcAdminId) {
        return errorResponse(
          "Active FPC Admin membership required.",
          403,
          undefined,
          "fpc_admin_marketplace_access_required",
        );
      }
      if (!useFpcWorkspace && !access.farmer) {
        return errorResponse(
          "Farmer marketplace access required.",
          403,
          undefined,
          "farmer_marketplace_access_required",
        );
      }
      let query = supabase.from("marketplace_orders").select("*");
      query = useFpcWorkspace
        ? query.eq("fpc_id", access.fpcAdminId)
        : query.eq("farmer_user_id", userId);
      const { data, error } = await query
        .order("updated_at", { ascending: false })
        .limit(300);
      if (error) throw error;
      const orders = (Array.isArray(data) ? data : []).map(record);
      const listingIds = [
        ...new Set(orders.map((row) => text(row.listing_id)).filter(Boolean)),
      ];
      let listings: JsonRecord[] = [];
      if (listingIds.length > 0) {
        const listingResult = await supabase.from("marketplace_listings")
          .select("*").in("id", listingIds);
        if (listingResult.error) throw listingResult.error;
        listings = (Array.isArray(listingResult.data) ? listingResult.data : [])
          .map(record);
      }
      const listingById = new Map(
        listings.map((listing) => [text(listing.id), listing]),
      );
      return successResponse(
        {
          orders: orders.map((order) => ({
            ...order,
            listing: listingById.get(text(order.listing_id)) ?? null,
          })),
          count: orders.length,
        },
        200,
        "marketplace_orders",
      );
    }

    if (["counter_offer", "accept_offer"].includes(action)) {
      const requestId = text(body.requestId ?? body.request_id);
      const { data: requestData, error: requestError } = await supabase
        .from("marketplace_purchase_requests")
        .select("*")
        .eq("id", requestId)
        .maybeSingle();
      if (requestError) throw requestError;
      const requestRow = record(requestData);
      if (!requestRow.id || !requestRow.listing_id) {
        return errorResponse(
          "Negotiation was not found.",
          404,
          undefined,
          "marketplace_negotiation_not_found",
        );
      }
      const { data: listingData, error: listingError } = await supabase
        .from("marketplace_listings")
        .select("*")
        .eq("id", text(requestRow.listing_id))
        .maybeSingle();
      if (listingError) throw listingError;
      const listing = record(listingData);
      const ownsListing = listingOwner(listing) === userId;
      const requestedRole = text(body.actorRole ?? body.actor_role)
        .toLowerCase();
      const role = requestedRole || actorRole(access, ownsListing);
      const validFarmer = role === "farmer" && access.farmer && ownsListing;
      const validFpc = role === "fpc_admin" &&
        access.fpcAdminId &&
        access.fpcAdminId === text(requestRow.fpc_id);
      if (!validFarmer && !validFpc) {
        return errorResponse(
          "You are not a party to this negotiation.",
          403,
          undefined,
          "marketplace_negotiation_forbidden",
        );
      }

      if (action === "counter_offer") {
        const price = numberOrNull(
          body.pricePerUnit ?? body.price_per_unit ?? body.proposedPrice,
        );
        if (price == null || price < 0) {
          return errorResponse(
            "A valid counteroffer rate is required.",
            400,
            undefined,
            "counteroffer_rate_required",
          );
        }
        const { data, error } = await supabase.rpc(
          "marketplace_append_offer",
          {
            p_request_id: requestId,
            p_actor_user_id: userId,
            p_actor_role: role,
            p_price_per_unit: price,
            p_message: text(body.message),
          },
        );
        if (error) throw error;
        return successResponse(
          { offer: data },
          200,
          "marketplace_counteroffer_saved",
        );
      }

      const offerId = text(body.offerId ?? body.offer_id) ||
        text(requestRow.current_offer_id);
      const { data, error } = await supabase.rpc(
        "marketplace_accept_offer",
        {
          p_request_id: requestId,
          p_offer_id: offerId,
          p_actor_user_id: userId,
          p_actor_role: role,
        },
      );
      if (error) throw error;
      return successResponse(
        { order: data },
        200,
        "marketplace_offer_accepted",
      );
    }

    if (action === "record_arrival") {
      const quantity = numberOrNull(
        body.quantityKg ?? body.quantity_kg,
      );
      const grade = text(body.grade);
      const { data, error } = await supabase.rpc(
        "marketplace_record_arrival",
        {
          p_order_id: text(body.orderId ?? body.order_id),
          p_actor_user_id: userId,
          p_quantity_kg: quantity,
          p_grade: grade,
          p_moisture_percent: numberOrNull(
            body.moisturePercent ?? body.moisture_percent,
          ),
          p_analysis_id: text(body.analysisId ?? body.analysis_id) || null,
          p_trace_payload: record(body.tracePayload ?? body.trace_payload),
        },
      );
      if (error) throw error;
      return successResponse(
        { order: data },
        200,
        "marketplace_arrival_quarantined",
      );
    }

    if (action === "propose_final_rate") {
      const orderId = text(body.orderId ?? body.order_id);
      const finalRate = numberOrNull(body.finalRate ?? body.final_rate);
      if (finalRate == null || finalRate < 0) {
        return errorResponse(
          "A valid final rate is required.",
          400,
          undefined,
          "final_rate_required",
        );
      }
      const { data: currentData, error: currentError } = await supabase
        .from("marketplace_orders")
        .select("*")
        .eq("id", orderId)
        .eq("fpc_id", access.fpcAdminId)
        .maybeSingle();
      if (currentError) throw currentError;
      const current = record(currentData);
      const arrivalQuantity = numberOrNull(current.arrival_quantity_kg);
      const protectedFloorRate = numberOrNull(current.protected_floor_rate);
      if (
        !current.id ||
        arrivalQuantity == null ||
        !["arrived_quarantine", "grading", "final_rate_pending"].includes(
          text(current.status),
        )
      ) {
        return errorResponse(
          "Record and grade the arrival before proposing the final rate.",
          409,
          undefined,
          "marketplace_arrival_required",
        );
      }
      if (
        protectedFloorRate != null &&
        finalRate != null &&
        finalRate < protectedFloorRate
      ) {
        return errorResponse(
          `Final rate cannot be below the protected floor of ₹${protectedFloorRate}/kg.`,
          409,
          undefined,
          "crop_program_floor_rate_required",
        );
      }
      const { data, error } = await supabase.from("marketplace_orders")
        .update({
          final_rate: finalRate,
          final_amount: Math.round(arrivalQuantity * finalRate * 100) / 100,
          final_rate_proposed_by: userId,
          final_rate_proposed_at: new Date().toISOString(),
          final_rate_confirmed_by: null,
          final_rate_confirmed_at: null,
          status: "final_rate_pending",
        })
        .eq("id", orderId)
        .eq("fpc_id", access.fpcAdminId)
        .select("*")
        .single();
      if (error) throw error;
      if (current.procurement_record_id) {
        const { error: receiptError } = await supabase
          .from("fpc_procurement_records")
          .update({
            price_per_kg: finalRate,
            total_value: Math.round(arrivalQuantity * finalRate * 100) / 100,
            quarantine_status: "awaiting_farmer_confirmation",
          })
          .eq("id", text(current.procurement_record_id))
          .eq("fpc_organization_id", access.fpcAdminId);
        if (receiptError) throw receiptError;
      }
      return successResponse(
        { order: data },
        200,
        "marketplace_final_rate_proposed",
      );
    }

    if (action === "confirm_final_rate") {
      const orderId = text(body.orderId ?? body.order_id);
      const { data: currentData, error: currentError } = await supabase
        .from("marketplace_orders")
        .select("*")
        .eq("id", orderId)
        .eq("farmer_user_id", userId)
        .eq("status", "final_rate_pending")
        .maybeSingle();
      if (currentError) throw currentError;
      const current = record(currentData);
      if (!current.id || current.final_rate == null) {
        return errorResponse(
          "Final rate proposal was not found.",
          409,
          undefined,
          "final_rate_proposal_not_found",
        );
      }
      const { data, error } = await supabase.from("marketplace_orders")
        .update({
          final_rate_confirmed_by: userId,
          final_rate_confirmed_at: new Date().toISOString(),
          status: "final_rate_confirmed",
        })
        .eq("id", orderId)
        .eq("farmer_user_id", userId)
        .eq("status", "final_rate_pending")
        .select("*")
        .single();
      if (error) throw error;
      if (current.procurement_record_id) {
        const { error: receiptError } = await supabase
          .from("fpc_procurement_records")
          .update({ quarantine_status: "awaiting_fpc_acceptance" })
          .eq("id", text(current.procurement_record_id))
          .eq("fpc_organization_id", text(current.fpc_id));
        if (receiptError) throw receiptError;
      }
      return successResponse(
        { order: data },
        200,
        "marketplace_final_rate_confirmed",
      );
    }

    if (action === "accept_procurement") {
      const { data, error } = await supabase.rpc(
        "marketplace_finalize_procurement",
        {
          p_order_id: text(body.orderId ?? body.order_id),
          p_actor_user_id: userId,
        },
      );
      if (error) throw error;
      return successResponse(
        { order: data },
        200,
        "marketplace_procurement_accepted",
      );
    }

    if (action === "record_cost") {
      const category = text(body.category);
      const amount = numberOrNull(body.amount);
      const allowedCategories = new Set([
        "procurement_logistics",
        "processing",
        "packaging",
        "sales_logistics",
        "adjustment",
      ]);
      if (!allowedCategories.has(category) || amount == null || amount === 0) {
        return errorResponse(
          "A valid cost category and non-zero amount are required.",
          400,
          undefined,
          "marketplace_cost_invalid",
        );
      }
      const marketplaceOrderId = text(
        body.marketplaceOrderId ?? body.marketplace_order_id,
      );
      if (!marketplaceOrderId) {
        return errorResponse(
          "Link this cost to a marketplace order.",
          400,
          undefined,
          "marketplace_cost_order_required",
        );
      }
      const { data: orderData, error: orderError } = await supabase
        .from("marketplace_orders")
        .select("id")
        .eq("id", marketplaceOrderId)
        .eq("fpc_id", access.fpcAdminId)
        .maybeSingle();
      if (orderError) throw orderError;
      if (!record(orderData).id) {
        return errorResponse(
          "Marketplace order was not found for this FPC.",
          404,
          undefined,
          "marketplace_order_not_found",
        );
      }
      const { data, error } = await supabase.from("fpc_cost_ledger")
        .insert({
          fpc_id: access.fpcAdminId,
          category,
          amount,
          description: text(body.description),
          marketplace_order_id: marketplaceOrderId,
          evidence: record(body.evidence),
          recorded_by: userId,
        })
        .select("*")
        .single();
      if (error) throw error;
      return successResponse(
        { cost: data },
        200,
        "marketplace_cost_recorded",
      );
    }

    if (action === "profit_summary") {
      const { data, error } = await supabase.from("fpc_profit_summary")
        .select("*")
        .eq("fpc_id", access.fpcAdminId)
        .maybeSingle();
      if (error) throw error;
      return successResponse(
        {
          summary: data ?? {
            fpc_id: access.fpcAdminId,
            acquisition_cost: 0,
            operating_cost: 0,
            revenue: 0,
            net_margin: 0,
          },
        },
        200,
        "fpc_profit_summary",
      );
    }

    if (["mark_interest", "create_purchase_request"].includes(action)) {
      const listingId = text(body.listingId ?? body.listing_id);
      const productId = text(body.productId ?? body.product_id);
      let listing: JsonRecord = {};
      if (listingId) {
        if (!access.fpcAdminId) {
          return errorResponse(
            "Only an FPC Admin can negotiate a farmer harvest listing.",
            403,
            undefined,
            "fpc_admin_marketplace_access_required",
          );
        }
        const { data, error } = await supabase.from("marketplace_listings")
          .select("*").eq("id", listingId).maybeSingle();
        if (error) throw error;
        listing = record(data);
        if (!listing.id || !activeListingStatus(listing.status)) {
          return errorResponse(
            "Listing is no longer active.",
            404,
            undefined,
            "listing_not_active",
          );
        }
        if (listingOwner(listing) === userId) {
          return errorResponse(
            "You cannot request your own listing.",
            400,
            undefined,
            "own_listing_request",
          );
        }
        const exclusiveFpcId = text(listing.exclusive_fpc_id);
        if (
          exclusiveFpcId.length > 0 &&
          exclusiveFpcId !== access.fpcAdminId
        ) {
          return errorResponse(
            "This harvest is exclusive to its sponsoring FPC.",
            403,
            undefined,
            "crop_program_fpc_exclusive",
          );
        }
      } else if (!access.farmer || !productId) {
        return errorResponse(
          "A verified input product is required for a Farmer enquiry.",
          400,
          undefined,
          "verified_input_product_required",
        );
      } else {
        const { data, error } = await supabase.from(
          "marketplace_input_products",
        )
          .select("id,name,status,is_verified")
          .eq("id", productId)
          .eq("status", "published")
          .eq("is_verified", true)
          .maybeSingle();
        if (error) throw error;
        const product = record(data);
        if (!product.id) {
          return errorResponse(
            "Verified input product was not found.",
            404,
            undefined,
            "verified_input_product_not_found",
          );
        }
      }

      const proposedPrice = numberOrNull(
        body.proposedPrice ?? body.proposed_price,
      ) ?? numberOrNull(listing.asking_price_per_unit) ??
        numberOrNull(listing.asking_price_per_kg);
      if (listingId && proposedPrice == null) {
        return errorResponse(
          "Offer rate is required for the whole harvest lot.",
          400,
          undefined,
          "offer_rate_required",
        );
      }
      let request: JsonRecord;
      let offer: JsonRecord | null = null;
      if (listingId) {
        const { data, error } = await supabase.rpc(
          "marketplace_start_negotiation",
          {
            p_listing_id: listingId,
            p_fpc_id: access.fpcAdminId,
            p_actor_user_id: userId,
            p_price_per_unit: proposedPrice,
            p_message: text(body.message),
          },
        );
        if (error) throw error;
        const result = record(data);
        request = record(result.request);
        offer = record(result.offer);
      } else {
        const requestRow = {
          buyer_user_id: userId,
          fpc_id: null,
          product_id: productId,
          listing_id: null,
          product_name: text(body.productName ?? body.product_name),
          quantity: numberOrNull(body.quantity),
          unit: text(body.unit) || "unit",
          proposed_price: proposedPrice,
          message: text(body.message),
          status: "submitted",
        };
        const { data, error } = await supabase.from(
          "marketplace_purchase_requests",
        )
          .insert(requestRow).select("*").single();
        if (error) throw error;
        request = record(data);
      }

      const recipient = listingOwner(listing);
      if (recipient) {
        await supabase.from("farmer_notifications").insert({
          recipient_user_id: recipient,
          farmer_id: text(listing.farmer_id) || `user:${recipient}`,
          farmer_phone: text(listing.farmer_phone) || null,
          farm_id: text(listing.farm_id) || null,
          farm_name: text(listing.farm_name) || null,
          type: "marketplace_purchase_request",
          title: "New marketplace request",
          message: `An FPC offered for ${
            text(listing.product_name) || text(listing.title)
          }.`,
          dedupe_key: `marketplace-request:${text(request.id)}`,
          action_route: `/marketplace/listing/${listingId}`,
          payload: { listing_id: listingId, request_id: text(request.id) },
        });
      }
      return successResponse(
        { request, offer },
        200,
        "marketplace_purchase_request_saved",
      );
    }

    return errorResponse(
      "Unknown marketplace action.",
      400,
      undefined,
      "unknown_marketplace_action",
    );
  } catch (error) {
    return errorResponse(
      "marketplace-listings failed",
      500,
      error,
      "marketplace_listings_failed",
    );
  }
});
