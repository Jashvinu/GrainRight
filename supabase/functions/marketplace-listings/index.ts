import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { requireUserId, text } from "../_shared/farmer-links.ts";

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

function nullableText(raw: unknown): string | null {
  const value = text(raw);
  return value.length === 0 ? null : value;
}

function finiteNumber(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function nullableInteger(raw: unknown): number | null {
  const value = finiteNumber(raw);
  return value == null ? null : Math.round(value);
}

function normalizeStatus(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["active", "paused", "closed"].includes(value) ? value : "active";
}

function normalizeInterestStatus(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["interested", "contacted", "closed"].includes(value)
    ? value
    : "interested";
}

function normalizeCategory(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["crop_lot", "byproduct", "processed_product"].includes(value)
    ? value
    : "crop_lot";
}

function rowText(row: Record<string, unknown>, key: string): string {
  return text(row[key]);
}

async function listingsWithInterestState(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  listings: Record<string, unknown>[],
) {
  const listingIds = listings.map((listing) => text(listing.id)).filter(Boolean);
  if (listingIds.length === 0) return listings;

  const { data: interests, error } = await supabase
    .from("marketplace_listing_interests")
    .select("listing_id, fpc_user_id, status")
    .in("listing_id", listingIds);
  if (error) throw error;

  const countByListing = new Map<string, number>();
  const myInterestByListing = new Map<string, string>();
  for (const interest of Array.isArray(interests) ? interests : []) {
    const interestRow = record(interest);
    const listingId = text(interestRow.listing_id);
    if (listingId.length === 0) continue;
    countByListing.set(listingId, (countByListing.get(listingId) ?? 0) + 1);
    if (text(interestRow.fpc_user_id) === userId) {
      myInterestByListing.set(listingId, text(interestRow.status));
    }
  }

  return listings.map((listing) => {
    const listingId = text(listing.id);
    return {
      ...listing,
      interest_count: countByListing.get(listingId) ?? 0,
      interested_by_me: myInterestByListing.has(listingId),
      interest_status: myInterestByListing.get(listingId) ?? "",
    };
  });
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

    if (action === "list_farmer") {
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select("*")
        .eq("farmer_user_id", userId)
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      const rows = Array.isArray(data)
        ? data.map((row) => record(row))
        : [];
      return successResponse(
        {
          listings: await listingsWithInterestState(supabase, userId, rows),
          count: rows.length,
        },
        200,
        "marketplace_farmer_listings",
      );
    }

    if (action === "list_fpc") {
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select("*")
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(300);
      if (error) throw error;
      const rows = Array.isArray(data)
        ? data.map((row) => record(row))
        : [];
      return successResponse(
        {
          listings: await listingsWithInterestState(supabase, userId, rows),
          count: rows.length,
        },
        200,
        "marketplace_fpc_listings",
      );
    }

    if (action === "create_or_update") {
      const inventoryItemId = text(
        body.inventoryItemId ?? body.inventory_item_id,
      );
      const inventoryId = text(body.inventoryId ?? body.inventory_id);
      if (inventoryItemId.length === 0 && inventoryId.length === 0) {
        return errorResponse(
          "Sync this inventory item before listing it.",
          400,
          undefined,
          "inventory_item_required",
        );
      }

      let query = supabase
        .from("farmer_inventory_items")
        .select("*")
        .eq("user_id", userId)
        .limit(1);
      query = inventoryItemId.length > 0
        ? query.eq("id", inventoryItemId)
        : query.eq("inventory_id", inventoryId);

      const { data: inventory, error: inventoryError } = await query
        .maybeSingle();
      if (inventoryError) throw inventoryError;
      const item = record(inventory);
      if (!inventory || text(item.id).length === 0) {
        return errorResponse(
          "Inventory item was not found for this farmer.",
          404,
          undefined,
          "inventory_item_not_found",
        );
      }

      const listingRow = {
        inventory_item_id: text(item.id),
        farmer_user_id: userId,
        farmer_phone: rowText(item, "farmer_phone"),
        farmer_id: rowText(item, "farmer_id"),
        farm_id: nullableText(item.farm_id),
        farm_name: rowText(item, "farm_name"),
        batch_id: rowText(item, "harvest_batch_id") ||
          rowText(item, "inventory_id"),
        product_category: normalizeCategory(item.product_category),
        product_name: rowText(item, "product_name"),
        crop: rowText(item, "crop"),
        variety: rowText(item, "variety"),
        quantity: finiteNumber(item.quantity) ?? 0,
        unit: rowText(item, "unit") || "kg",
        grade: rowText(item, "grade"),
        grade_score: nullableInteger(item.grade_score),
        moisture_percent: finiteNumber(item.moisture_percent),
        asking_price_per_unit: finiteNumber(
          body.askingPricePerUnit ?? body.asking_price_per_unit,
        ),
        listing_note: text(body.listingNote ?? body.listing_note),
        status: normalizeStatus(body.status),
      };

      if (listingRow.quantity <= 0) {
        return errorResponse(
          "Quantity is required before listing.",
          400,
          undefined,
          "listing_quantity_required",
        );
      }

      const { data: saved, error: saveError } = await supabase
        .from("marketplace_listings")
        .upsert(listingRow, { onConflict: "inventory_item_id" })
        .select("*")
        .maybeSingle();
      if (saveError) throw saveError;
      const savedRows = await listingsWithInterestState(
        supabase,
        userId,
        [record(saved)],
      );
      return successResponse(
        { listing: savedRows[0] ?? saved },
        200,
        "marketplace_listing_saved",
      );
    }

    if (action === "mark_interest") {
      const listingId = text(body.listingId ?? body.listing_id);
      if (listingId.length === 0) {
        return errorResponse(
          "Listing is required.",
          400,
          undefined,
          "listing_required",
        );
      }

      const { data: listing, error: listingError } = await supabase
        .from("marketplace_listings")
        .select("id, farmer_user_id, status")
        .eq("id", listingId)
        .eq("status", "active")
        .maybeSingle();
      if (listingError) throw listingError;
      const listingRow = record(listing);
      if (!listing || text(listingRow.id).length === 0) {
        return errorResponse(
          "Listing is no longer active.",
          404,
          undefined,
          "listing_not_active",
        );
      }
      if (text(listingRow.farmer_user_id) === userId) {
        return errorResponse(
          "You cannot mark interest in your own listing.",
          400,
          undefined,
          "own_listing_interest",
        );
      }

      const interestRow = {
        listing_id: listingId,
        fpc_user_id: userId,
        status: normalizeInterestStatus(body.status),
        message: text(body.message),
      };
      const { data: saved, error: saveError } = await supabase
        .from("marketplace_listing_interests")
        .upsert(interestRow, { onConflict: "listing_id,fpc_user_id" })
        .select("*")
        .maybeSingle();
      if (saveError) throw saveError;
      return successResponse(
        { interest: saved },
        200,
        "marketplace_interest_saved",
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
