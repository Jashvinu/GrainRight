import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
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

function optionalText(raw: unknown): string | null {
  const value = text(raw);
  return value.length === 0 ? null : value;
}

function finiteNumber(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function nullableNumber(raw: unknown): number | null {
  const value = finiteNumber(raw);
  return value == null ? null : value;
}

function nullableInteger(raw: unknown): number | null {
  const value = finiteNumber(raw);
  return value == null ? null : Math.round(value);
}

function normalizeCategory(raw: unknown): string {
  const value = text(raw).toLowerCase();
  return ["crop_lot", "byproduct", "processed_product"].includes(value)
    ? value
    : "crop_lot";
}

function itemText(item: Record<string, unknown>, key: string): string {
  return text(item[key] ?? item[key.replaceAll("_", "")]);
}

function itemNumber(item: Record<string, unknown>, key: string): number | null {
  return finiteNumber(item[key] ?? item[key.replaceAll("_", "")]);
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
    const item = record(body.item ?? body.inventory);
    const phone = normalizePhone(
      body.phone ?? body.farmerPhone ?? body.farmer_phone ??
        item.farmer_phone,
    );
    const farmerId = text(
      body.farmerId ?? body.farmer_id ?? item.farmer_id,
    );
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;

    const action = text(body.action).toLowerCase();
    if (action === "save") {
      const farmId = text(item.farm_id ?? item.farmId);
      if (farmId.length === 0) {
        return errorResponse(
          "Sync this farm before saving inventory.",
          400,
          undefined,
          "farm_sync_required",
        );
      }
      const farm = await assertLinkedFarm(
        supabase,
        userId,
        phone,
        farmerId,
        farmId,
      );
      if (farm instanceof Response) return farm;

      const inventoryId = text(
        item.inventory_id ?? item.inventoryId ?? item.local_id ??
          item.localId ?? item.batch_id ?? item.batchId,
      );
      const quantity = itemNumber(item, "quantity");
      if (inventoryId.length === 0) {
        return errorResponse(
          "Inventory id is required",
          400,
          undefined,
          "inventory_id_required",
        );
      }
      if (quantity == null || quantity <= 0) {
        return errorResponse(
          "Quantity is required",
          400,
          undefined,
          "inventory_quantity_required",
        );
      }

      const ownerUserId = text(farm.user_id);
      const row = {
        user_id: ownerUserId,
        farmer_phone: phone,
        farmer_id: farmerId.length > 0 ? farmerId : optionalText(
          item.farmer_id,
        ),
        farm_id: farmId,
        farm_name: itemText(item, "farm_name"),
        inventory_id: inventoryId,
        harvest_batch_id: optionalText(
          item.harvest_batch_id ?? item.harvestBatchId,
        ),
        product_category: normalizeCategory(item.product_category),
        product_name: itemText(item, "product_name"),
        crop: itemText(item, "crop"),
        variety: itemText(item, "variety"),
        quantity,
        unit: text(item.unit) || "kg",
        bag_count: nullableInteger(item.bag_count ?? item.bagCount),
        bag_size_kg: nullableNumber(item.bag_size_kg ?? item.bagSizeKg),
        moisture_percent: nullableNumber(
          item.moisture_percent ?? item.moisturePercent,
        ),
        grade: itemText(item, "grade"),
        grade_score: nullableInteger(item.grade_score ?? item.gradeScore),
        grade_basis: itemText(item, "grade_basis"),
        estimated_yield_kg: nullableNumber(
          item.estimated_yield_kg ?? item.estimatedYieldKg,
        ),
        harvested_at: optionalText(item.harvested_at ?? item.harvestedAt) ??
          new Date().toISOString(),
        latitude: nullableNumber(item.latitude),
        longitude: nullableNumber(item.longitude),
        image_name: itemText(item, "image_name"),
        source_flow: text(item.source_flow ?? item.sourceFlow) || "inventory",
        notes: itemText(item, "notes"),
      };

      const { data: saved, error: saveError } = await supabase
        .from("farmer_inventory_items")
        .upsert(row, { onConflict: "user_id,inventory_id" })
        .select("*")
        .maybeSingle();
      if (saveError) throw saveError;
      return successResponse({ item: saved }, 200, "inventory_saved");
    }

    const linkedUserIds = await loadLinkedUserIds(
      supabase,
      userId,
      phone,
      farmerId,
    );
    if (linkedUserIds instanceof Response) return linkedUserIds;
    if (linkedUserIds.length === 0) {
      return successResponse(
        { items: [], count: 0 },
        200,
        "inventory_empty",
      );
    }

    const { data: items, error: itemsError } = await supabase
      .from("farmer_inventory_items")
      .select("*")
      .eq("farmer_phone", phone)
      .in("user_id", linkedUserIds)
      .order("created_at", { ascending: false })
      .limit(300);
    if (itemsError) throw itemsError;

    const rows = Array.isArray(items) ? items : [];
    return successResponse(
      { items: rows, count: rows.length },
      200,
      "inventory_synced",
    );
  } catch (error) {
    return errorResponse(
      "farmer-inventory-sync failed",
      500,
      error,
      "farmer_inventory_sync_failed",
    );
  }
});
