// Deterministic FAO/BIS-aligned grading rules for finger millet (ragi).
//
// Ported from grading_service/src/ai_grain_grade/rule_engine.py and
// moisture_calibration.py. The Qwen-VL model describes the grain image, but
// this module owns the final threshold decision so grades stay reproducible
// and conservative. Keep thresholds in sync with the Python reference.

export type Grade = "A" | "B" | "C";
export type MoistureRisk = "LOW" | "MODERATE" | "HIGH" | "CRITICAL";

const GRADE_ORDER: Record<Grade, number> = { C: 0, B: 1, A: 2 };

// Conservative operator-assist thresholds (RagiRuleThresholds).
export const RAGI_THRESHOLDS = {
  moistureAMax: 12.0,
  moistureBMax: 13.0,
  moistureCMax: 14.0,
  foreignAMax: 0.1,
  foreignBMax: 0.75,
  foreignCMax: 1.0,
  damagedAMax: 3.1,
  damagedBMax: 6.3,
  damagedCMax: 9.5,
  brokenCMin: 5.0,
};

export const RULE_VERSION = "ragi-bis-fao-1.0";

/** Vision-derived signals the model returns for a grain lot. */
export type GrainSignals = {
  brokenGrainPercent: number;
  foreignMatterPercent: number;
  damagedPercent: number;
  uniformityScore: number; // 0-100, higher is better
  moldVisible: boolean;
  modelGrade: Grade; // the model's own grade suggestion
};

export type RuleResult = {
  grade: Grade;
  grainGrade: Grade;
  finalScore: number;
  grainScore: number;
  moistureScore: number;
  rejectRecommended: boolean;
  rejectReasons: string[];
  appliedRules: { rule_name: string; evidence: string; rule_confidence: number }[];
  signalHighlights: string[];
};

function clamp(v: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, v));
}

/** Map a lower-is-better metric to a 0-100 score across A/B/C bands. */
function scoreMaxMetric(value: number, a: number, b: number, c: number): number {
  if (value <= a) return Math.round(clamp(90 + ((a - value) / Math.max(Math.abs(a), 0.01)) * 10));
  if (value <= b) return Math.round(clamp(75 + ((b - value) / Math.max(b - a, 0.01)) * 14));
  if (value <= c) return Math.round(clamp(60 + ((c - value) / Math.max(c - b, 0.01)) * 14));
  const span = Math.max(c - b, b - a, Math.abs(c), 1);
  return Math.round(clamp(60 - ((value - c) / span) * 35, 20));
}

function gradeFromMetric(value: number, aMax: number, bMax: number, cMax: number): Grade {
  if (value <= aMax) return "A";
  if (value <= bMax) return "B";
  if (value <= cMax) return "C";
  return "C";
}

function worse(a: Grade, b: Grade): Grade {
  return GRADE_ORDER[a] <= GRADE_ORDER[b] ? a : b;
}

/** Moisture % -> risk band. Boundaries from moisture_calibration.py. */
export function moistureRiskFromPercent(percent: number | null): MoistureRisk {
  if (percent == null || Number.isNaN(percent)) return "MODERATE";
  if (percent <= 11.5) return "LOW";
  if (percent <= 13.0) return "MODERATE";
  if (percent <= 15.0) return "HIGH";
  return "CRITICAL";
}

function moistureCapGrade(risk: MoistureRisk): Grade {
  switch (risk) {
    case "LOW":
      return "A";
    case "MODERATE":
      return "B";
    default:
      return "C"; // HIGH / CRITICAL cannot be premium
  }
}

function moistureScore(risk: MoistureRisk): number {
  switch (risk) {
    case "LOW":
      return 100;
    case "MODERATE":
      return 80;
    case "HIGH":
      return 55;
    case "CRITICAL":
      return 25;
  }
}

/**
 * Apply the deterministic grading rules to the model signals + moisture risk.
 * Final grade is the worst of: model grade, defect-derived grade, and the
 * moisture-capped grade. Critical hazards force a reject recommendation.
 */
export function applyRagiRules(
  signals: GrainSignals,
  moisturePercent: number | null,
  moistureRisk: MoistureRisk,
): RuleResult {
  const t = RAGI_THRESHOLDS;
  const rules: RuleResult["appliedRules"] = [];
  const reasons: string[] = [];
  const highlights: string[] = [];

  const foreignGrade = gradeFromMetric(
    signals.foreignMatterPercent,
    t.foreignAMax,
    t.foreignBMax,
    t.foreignCMax,
  );
  rules.push({
    rule_name: "Foreign matter limit",
    evidence: `Foreign matter ${signals.foreignMatterPercent.toFixed(2)}% (A≤${t.foreignAMax}, B≤${t.foreignBMax}, C≤${t.foreignCMax})`,
    rule_confidence: 0.9,
  });

  const damagedGrade = gradeFromMetric(
    signals.damagedPercent,
    t.damagedAMax,
    t.damagedBMax,
    t.damagedCMax,
  );
  rules.push({
    rule_name: "Damaged/defect load",
    evidence: `Damaged ${signals.damagedPercent.toFixed(1)}% (A≤${t.damagedAMax}, B≤${t.damagedBMax}, C≤${t.damagedCMax})`,
    rule_confidence: 0.85,
  });

  // Grain grade = worst of model suggestion + the defect-derived grades.
  let grainGrade = worse(worse(signals.modelGrade, foreignGrade), damagedGrade);

  // Broken grain hazard nudge.
  if (signals.brokenGrainPercent >= t.brokenCMin) {
    grainGrade = worse(grainGrade, "C");
    rules.push({
      rule_name: "Broken grain ceiling",
      evidence: `Broken ${signals.brokenGrainPercent.toFixed(1)}% ≥ ${t.brokenCMin}%`,
      rule_confidence: 0.8,
    });
  }

  // Moisture cap.
  const mCap = moistureCapGrade(moistureRisk);
  rules.push({
    rule_name: "Moisture safety cap",
    evidence: `Moisture ${moisturePercent != null ? moisturePercent.toFixed(1) + "%" : "n/a"} → ${moistureRisk}`,
    rule_confidence: 0.95,
  });

  let finalGrade = worse(grainGrade, mCap);

  // Hard rejects.
  let reject = false;
  if (signals.moldVisible) {
    reject = true;
    finalGrade = "C";
    reasons.push("Visible mold / fungal growth");
  }
  if (moistureRisk === "CRITICAL") {
    reject = true;
    reasons.push("Critical moisture — not safe to store");
  }
  if (signals.foreignMatterPercent > t.foreignCMax) {
    reject = true;
    reasons.push(`Foreign matter ${signals.foreignMatterPercent.toFixed(1)}% over limit`);
  }

  // Scores.
  const grainScore = Math.round(
    (scoreMaxMetric(signals.foreignMatterPercent, t.foreignAMax, t.foreignBMax, t.foreignCMax) +
      scoreMaxMetric(signals.damagedPercent, t.damagedAMax, t.damagedBMax, t.damagedCMax) +
      clamp(signals.uniformityScore)) /
      3,
  );
  const mScore = moistureScore(moistureRisk);
  const finalScore = reject ? Math.min(grainScore, mScore, 45) : Math.round((grainScore + mScore) / 2);

  // Highlights (short, farmer-facing positives/cautions).
  if (moistureRisk === "LOW") highlights.push("Moisture safe to store");
  if (signals.foreignMatterPercent <= t.foreignAMax) highlights.push("Very clean lot");
  if (signals.brokenGrainPercent < t.brokenCMin) highlights.push("Low broken grain");
  if (signals.moldVisible) highlights.push("Mold detected");

  return {
    grade: finalGrade,
    grainGrade,
    finalScore,
    grainScore,
    moistureScore: mScore,
    rejectRecommended: reject,
    rejectReasons: reasons,
    appliedRules: rules,
    signalHighlights: highlights,
  };
}

/** Short reference rules block injected into the vision prompt for grounding. */
export const RAGI_RULE_PROMPT = [
  "BIS/FAO finger-millet (ragi) grading anchors (operator-assist, conservative):",
  "- Grade A: foreign matter ≤0.10%, damaged ≤3.1%, moisture ≤12%.",
  "- Grade B: foreign matter ≤0.75%, damaged ≤6.3%, moisture ≤13%.",
  "- Grade C: foreign matter ≤1.0%, damaged ≤9.5%, moisture ≤14%.",
  "- Visible mold or moisture ≥15% means reject / not safe to store.",
].join("\n");
