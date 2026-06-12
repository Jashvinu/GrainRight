// RAG retrieval over the agronomy_knowledge base.
// Grounds the Qwen advisory layer (disease-image-diagnose, farm-alert-advisor)
// with ICAR crop knowledge. Retrieval is best-effort: any failure returns no
// chunks so the calling LLM request still proceeds ungrounded.

import { createClient } from "npm:@supabase/supabase-js@2";

const DEFAULT_EMBED_MODEL = "text-embedding-v3";

export type KnowledgeChunk = {
  chunk_type: string;
  disease: string | null;
  growth_stage: string | null;
  district: string | null;
  content: string;
  similarity: number;
};

export type RetrieveOptions = {
  crop: string;
  growthStage?: string;
  diseaseCandidates?: string[];
  queryText?: string;
  k?: number;
};

// Maps free-form crop labels to the knowledge-base crop key.
// Matches the rice/millet split used in the Flutter farm tab.
export function normalizeCrop(crop: string): string {
  const c = (crop ?? "").toLowerCase();
  if (c.includes("rice") || c.includes("paddy") || c.includes("dhan")) {
    return "rice";
  }
  return "millet";
}

export async function embedText(text: string): Promise<number[]> {
  const apiKey = Deno.env.get("QWEN_EMBED_API_KEY") ??
    Deno.env.get("QWEN_API_KEY") ??
    Deno.env.get("QWEN3_API_KEY");
  const baseUrl = Deno.env.get("QWEN_EMBED_BASE_URL") ??
    Deno.env.get("QWEN_BASE_URL") ??
    Deno.env.get("QWEN3_BASE_URL") ??
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
  const model = Deno.env.get("QWEN_EMBED_MODEL") ?? DEFAULT_EMBED_MODEL;

  if (!apiKey) throw new Error("QWEN_API_KEY is not configured for embeddings");

  const response = await fetch(`${baseUrl}/embeddings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model, input: text, encoding_format: "float" }),
  });

  if (!response.ok) {
    throw new Error(
      `Embedding request failed: ${response.status} ${await response.text()}`,
    );
  }

  const data = await response.json();
  const vector = data?.data?.[0]?.embedding;
  if (!Array.isArray(vector)) {
    throw new Error("Embedding response missing vector");
  }
  return vector as number[];
}

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

export async function retrieveKnowledge(
  opts: RetrieveOptions,
): Promise<KnowledgeChunk[]> {
  const crop = normalizeCrop(opts.crop);
  const queryParts = [
    crop,
    opts.growthStage ?? "",
    ...(opts.diseaseCandidates ?? []),
    opts.queryText ?? "",
  ].filter((part) => part && part.length > 0);
  const query = queryParts.join(" ").trim();
  if (query.length === 0) return [];

  try {
    const embedding = await embedText(query);
    const supabase = createServiceClient();
    const { data, error } = await supabase.rpc("match_agronomy_knowledge", {
      query_embedding: embedding,
      filter_crop: crop,
      match_count: opts.k ?? 6,
    });
    if (error || !Array.isArray(data)) return [];
    return data as KnowledgeChunk[];
  } catch (_error) {
    return [];
  }
}

export function formatKnowledge(chunks: KnowledgeChunk[]): string {
  if (chunks.length === 0) return "";
  return chunks
    .map((chunk, index) => {
      const tag = [chunk.disease, chunk.chunk_type].filter(Boolean).join("/");
      return `[${index + 1}] (${tag}) ${chunk.content}`;
    })
    .join("\n");
}
