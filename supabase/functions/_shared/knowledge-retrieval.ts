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
export function normalizeCrop(crop: string): string {
  const c = (crop ?? "").toLowerCase();
  if (c.includes("rice") || c.includes("paddy") || c.includes("dhan")) {
    return "rice";
  }
  if (
    c.includes("finger") ||
    c.includes("ragi") ||
    c.includes("nachani") ||
    c.includes("nachni") ||
    c.includes("mandua")
  ) {
    return "finger_millet";
  }
  if (
    c.includes("pearl") ||
    c.includes("bajra") ||
    c.includes("bajara") ||
    c.includes("bajari")
  ) {
    return "pearl_millet";
  }
  return "millet";
}

function includesAny(value: string, hints: string[]): boolean {
  return hints.some((hint) => value.includes(hint));
}

export function resolveKnowledgeCrop(crop: string, context = ""): string {
  const explicit = normalizeCrop(crop);
  if (explicit !== "millet") return explicit;

  const c = `${crop} ${context}`.toLowerCase();
  if (includesAny(c, ["indrayani", "basmati", "kolam", "paddy", "dhan"])) {
    return "rice";
  }
  if (
    includesAny(c, [
      "bajra",
      "bajara",
      "bajari",
      "dhanshakti",
      "ictp",
      "hhb",
      "ghb",
      "mbbh",
    ])
  ) {
    return "pearl_millet";
  }
  if (
    includesAny(c, [
      "finger",
      "ragi",
      "nachani",
      "nachni",
      "mandua",
      "gpu-28",
      "gpu 28",
      "gpu-67",
      "gpu 67",
      "gpu-48",
      "gpu 48",
      "kmr-204",
      "kmr 204",
      "indaf",
      "vl mandua",
      "vl-149",
      "vl 149",
    ])
  ) {
    return "finger_millet";
  }
  return explicit;
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

async function matchKnowledge(
  supabase: ReturnType<typeof createServiceClient>,
  embedding: number[],
  crop: string,
  matchCount: number,
): Promise<KnowledgeChunk[]> {
  const { data, error } = await supabase.rpc("match_agronomy_knowledge", {
    query_embedding: embedding,
    filter_crop: crop,
    match_count: matchCount,
  });
  return error || !Array.isArray(data) ? [] : data as KnowledgeChunk[];
}

function uniqueChunks(chunks: KnowledgeChunk[]): KnowledgeChunk[] {
  const seen = new Set<string>();
  const unique: KnowledgeChunk[] = [];
  for (const chunk of chunks) {
    const key = [
      chunk.chunk_type,
      chunk.disease ?? "",
      chunk.growth_stage ?? "",
      chunk.district ?? "",
      chunk.content,
    ].join("|");
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(chunk);
  }
  return unique;
}

export async function retrieveKnowledge(
  opts: RetrieveOptions,
): Promise<KnowledgeChunk[]> {
  const crop = resolveKnowledgeCrop(
    opts.crop,
    [
      opts.growthStage ?? "",
      ...(opts.diseaseCandidates ?? []),
      opts.queryText ?? "",
    ].join(" "),
  );
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
    const requested = opts.k ?? 6;
    const primary = await matchKnowledge(supabase, embedding, crop, requested);
    if (crop === "millet") {
      const [finger, pearl] = await Promise.all([
        matchKnowledge(supabase, embedding, "finger_millet", requested),
        matchKnowledge(supabase, embedding, "pearl_millet", requested),
      ]);
      return uniqueChunks([...primary, ...finger, ...pearl])
        .sort((a, b) => b.similarity - a.similarity)
        .slice(0, requested);
    }

    if (primary.length >= Math.min(3, requested) || crop === "rice") {
      return primary;
    }

    const fallback = await matchKnowledge(
      supabase,
      embedding,
      "millet",
      Math.max(1, requested - primary.length),
    );
    return uniqueChunks([...primary, ...fallback]).slice(0, requested);
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
