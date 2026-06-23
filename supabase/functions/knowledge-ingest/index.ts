// One-off admin function: embed the curated agronomy knowledge files and
// upsert them into agronomy_knowledge. Idempotent per doc_source
// (delete-then-insert), so it is safe to re-run after editing a knowledge file.
//
// Invoke once after deploying the migration. Optionally protect with an
// INGEST_SECRET env var, supplied by the caller as the x-ingest-secret header.

import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { embedText } from "../_shared/knowledge-retrieval.ts";
import fingerMillet from "../_shared/knowledge/finger_millet.json" with {
  type: "json",
};
import riceLifecycle from "../_shared/knowledge/rice_lifecycle.json" with {
  type: "json",
};
import pearlMilletLifecycle from "../_shared/knowledge/pearl_millet_lifecycle.json" with {
  type: "json",
};
import fingerMilletLifecycle from "../_shared/knowledge/finger_millet_lifecycle.json" with {
  type: "json",
};
import assetFingerMillet from "../_shared/knowledge/asset_finger_millet_deep_2026.json" with {
  type: "json",
};
import assetPearlMillet from "../_shared/knowledge/asset_pearl_millet_deep_2026.json" with {
  type: "json",
};
import assetRice from "../_shared/knowledge/asset_rice_deep_2026.json" with {
  type: "json",
};

type KnowledgeRecord = {
  chunk_type: string;
  disease?: string | null;
  growth_stage?: string | null;
  district?: string | null;
  content: string;
  metadata?: Record<string, unknown>;
};

type KnowledgeDoc = {
  doc_source: string;
  crop: string;
  source_title?: string;
  source_asset?: string;
  records: KnowledgeRecord[];
};

const DOCS: KnowledgeDoc[] = [
  fingerMillet as KnowledgeDoc,
  riceLifecycle as KnowledgeDoc,
  pearlMilletLifecycle as KnowledgeDoc,
  fingerMilletLifecycle as KnowledgeDoc,
  assetFingerMillet as KnowledgeDoc,
  assetPearlMillet as KnowledgeDoc,
  assetRice as KnowledgeDoc,
];

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

async function ingestDoc(
  supabase: ReturnType<typeof createServiceClient>,
  doc: KnowledgeDoc,
): Promise<number> {
  const records = Array.isArray(doc.records) ? doc.records : [];
  if (records.length === 0) return 0;

  const rows = [];
  let index = 0;
  const workerCount = Math.min(3, records.length);
  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (index < records.length) {
      const record = records[index++];
      const content = String(record.content ?? "").trim();
      if (content.length === 0) continue;
      const embedding = await embedText(content);
      rows.push({
        crop: doc.crop,
        doc_source: doc.doc_source,
        chunk_type: record.chunk_type,
        disease: record.disease ?? null,
        growth_stage: record.growth_stage ?? null,
        district: record.district ?? null,
        content,
        metadata: record.metadata ?? {},
        embedding: JSON.stringify(embedding),
      });
    }
  }));

  const { error: deleteError } = await supabase
    .from("agronomy_knowledge")
    .delete()
    .eq("doc_source", doc.doc_source);
  if (deleteError) {
    throw new Error(
      `Failed to clear ${doc.doc_source}: ${deleteError.message}`,
    );
  }

  const { error: insertError } = await supabase
    .from("agronomy_knowledge")
    .insert(rows);
  if (insertError) {
    throw new Error(
      `Failed to insert ${doc.doc_source}: ${insertError.message}`,
    );
  }

  return rows.length;
}

function requestedSources(body: Record<string, unknown>): Set<string> | null {
  const raw = body.doc_sources ?? body.sources ?? body.doc_source ?? body.source;
  if (raw == null) return null;

  const values = Array.isArray(raw) ? raw : [raw];
  const normalized = values
    .map((item) => String(item).trim())
    .filter(Boolean);
  if (normalized.length === 0) return null;
  if (normalized.some((item) => item === "assets" || item === "asset_docs")) {
    return new Set(
      DOCS
        .filter((doc) => doc.doc_source.startsWith("asset_"))
        .map((doc) => doc.doc_source),
    );
  }
  return new Set(normalized);
}

function selectDocs(body: Record<string, unknown>): KnowledgeDoc[] {
  const requested = requestedSources(body);
  if (requested == null) return DOCS;
  return DOCS.filter((doc) => requested.has(doc.doc_source));
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const secret = Deno.env.get("INGEST_SECRET");
  if (secret && req.headers.get("x-ingest-secret") !== secret) {
    return errorResponse("Unauthorized", 401);
  }

  try {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }
    const docs = selectDocs(body);
    if (docs.length === 0) {
      return errorResponse(
        "No matching knowledge sources",
        400,
        { available_sources: DOCS.map((doc) => doc.doc_source) },
        "no_matching_knowledge_sources",
      );
    }

    const supabase = createServiceClient();
    const ingested: Record<string, number> = {};
    for (const doc of docs) {
      ingested[doc.doc_source] = await ingestDoc(supabase, doc);
    }
    const total = Object.values(ingested).reduce((sum, n) => sum + n, 0);
    return successResponse({
      ingested,
      total,
      selected_sources: docs.map((doc) => doc.doc_source),
    });
  } catch (error) {
    return errorResponse("knowledge-ingest failed", 500, error);
  }
});
