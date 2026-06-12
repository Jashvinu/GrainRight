-- Agronomy knowledge base for RAG grounding of the Qwen advisory layer.
-- Grounds disease-image-diagnose and farm-alert-advisor with ICAR crop knowledge.
-- Embeddings: DashScope text-embedding-v3 (1024 dims).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS agronomy_knowledge (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  crop          TEXT NOT NULL,            -- 'millet' | 'rice'
  doc_source    TEXT NOT NULL,            -- source doc id, used for idempotent re-ingest
  chunk_type    TEXT NOT NULL,
    -- symptom | mitigation | idm | variety | crop_cycle | grading | climate | district
  disease       TEXT,                     -- nullable; disease this chunk concerns
  growth_stage  TEXT,                     -- nullable
  district      TEXT,                     -- nullable
  content       TEXT NOT NULL,
  metadata      JSONB DEFAULT '{}'::jsonb,
  embedding     vector(1024),
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agronomy_knowledge_embedding
  ON agronomy_knowledge USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS agronomy_knowledge_crop_type
  ON agronomy_knowledge (crop, chunk_type);
CREATE INDEX IF NOT EXISTS agronomy_knowledge_source
  ON agronomy_knowledge (doc_source);

-- Top-k cosine match with crop pre-filter and optional disease filter.
CREATE OR REPLACE FUNCTION match_agronomy_knowledge(
  query_embedding vector(1024),
  filter_crop     TEXT,
  match_count     INT DEFAULT 6,
  filter_disease  TEXT DEFAULT NULL
)
RETURNS TABLE (
  id          UUID,
  crop        TEXT,
  chunk_type  TEXT,
  disease     TEXT,
  growth_stage TEXT,
  district    TEXT,
  content     TEXT,
  metadata    JSONB,
  similarity  FLOAT
)
LANGUAGE sql STABLE
AS $$
  SELECT
    ak.id,
    ak.crop,
    ak.chunk_type,
    ak.disease,
    ak.growth_stage,
    ak.district,
    ak.content,
    ak.metadata,
    1 - (ak.embedding <=> query_embedding) AS similarity
  FROM agronomy_knowledge ak
  WHERE ak.embedding IS NOT NULL
    AND ak.crop = filter_crop
    AND (filter_disease IS NULL OR ak.disease = filter_disease)
  ORDER BY ak.embedding <=> query_embedding
  LIMIT match_count;
$$;

-- Knowledge base is shared reference content, readable by authenticated users.
ALTER TABLE agronomy_knowledge ENABLE ROW LEVEL SECURITY;
CREATE POLICY "agronomy_knowledge_read"
  ON agronomy_knowledge FOR SELECT
  USING (auth.role() = 'authenticated');

-- Data loop: let an agronomist/scout confirm the true disease on a photo,
-- accumulating (image, label) pairs for future model fine-tuning.
ALTER TABLE farmer_photo_submissions
  ADD COLUMN IF NOT EXISTS confirmed_label TEXT,
  ADD COLUMN IF NOT EXISTS label_source    TEXT,   -- 'agronomist' | 'scout' | 'lab'
  ADD COLUMN IF NOT EXISTS labeled_at      TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS farmer_photos_labeled
  ON farmer_photo_submissions (crop, confirmed_label)
  WHERE confirmed_label IS NOT NULL;
