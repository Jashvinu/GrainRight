-- Farmer risk-cell action tracking.
-- Stores visits and photo checks opened from the farm map risk detail screen.

CREATE TABLE IF NOT EXISTS farm_issue_actions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  farm_id                 UUID REFERENCES farms(id) ON DELETE CASCADE,
  farmer_id               TEXT,
  farmer_phone            TEXT,
  action                  TEXT NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'visited',
  issue_lat               NUMERIC,
  issue_lng               NUMERIC,
  risk_score              NUMERIC,
  crop                    TEXT,
  growth_stage            TEXT,
  issue_snapshot          JSONB NOT NULL DEFAULT '{}'::jsonb,
  photo_diagnosis_result  JSONB,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS farm_issue_actions_farm_created
  ON farm_issue_actions (farm_id, created_at DESC);

CREATE INDEX IF NOT EXISTS farm_issue_actions_farmer
  ON farm_issue_actions (farmer_id, farmer_phone, created_at DESC);

CREATE INDEX IF NOT EXISTS farm_issue_actions_status
  ON farm_issue_actions (farm_id, status);

ALTER TABLE farm_issue_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner_only_farm_issue_actions" ON farm_issue_actions;
CREATE POLICY "owner_only_farm_issue_actions"
  ON farm_issue_actions FOR ALL
  USING (farm_id IN (SELECT id FROM farms WHERE user_id = auth.uid()))
  WITH CHECK (farm_id IN (SELECT id FROM farms WHERE user_id = auth.uid()));
