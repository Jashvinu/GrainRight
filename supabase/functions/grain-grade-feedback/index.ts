import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

// Stores an operator correction for a prior grain-grade analysis.
// Service role so guest sessions can record corrections (owner-only RLS).

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, key);
}

const GRADES = new Set(["A", "B", "C"]);
const RISKS = new Set(["LOW", "MODERATE", "HIGH", "CRITICAL"]);

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json();
    const analysisId = String(body.analysis_id ?? "");
    const trueGrade = String(body.true_grade ?? "").toUpperCase();
    const trueMoistureRisk = String(body.true_moisture_risk ?? "").toUpperCase();
    const notes = String(body.notes ?? "");
    const operatorId = body.operator_id ? String(body.operator_id) : null;

    if (!analysisId) return errorResponse("analysis_id is required", 400);
    if (!GRADES.has(trueGrade)) return errorResponse("true_grade must be A, B or C", 400);

    const supabase = createServiceClient();

    const { data: job } = await supabase
      .from("analysis_jobs")
      .select("final_grade, grain_grade, moisture_percent, moisture_risk")
      .eq("id", analysisId)
      .maybeSingle();

    const { error: insertError } = await supabase.from("operator_corrections").insert({
      analysis_id: analysisId,
      operator_id: operatorId,
      predicted_final_grade: job?.final_grade ?? null,
      corrected_final_grade: trueGrade,
      predicted_grain_grade: job?.grain_grade ?? null,
      corrected_grain_grade: body.true_grain_grade
        ? String(body.true_grain_grade).toUpperCase()
        : trueGrade,
      predicted_moisture_percent: job?.moisture_percent ?? null,
      corrected_moisture_percent: body.corrected_moisture_percent ?? null,
      notes: RISKS.has(trueMoistureRisk) ? `${notes} [moisture:${trueMoistureRisk}]`.trim() : notes,
    });
    if (insertError) throw new Error(insertError.message);

    return successResponse({ saved: true, analysis_id: analysisId });
  } catch (error) {
    return errorResponse("grain-grade-feedback failed", 500, error);
  }
});
