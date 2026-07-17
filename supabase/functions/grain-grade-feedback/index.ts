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

class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

async function authenticatedUserId(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<string> {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError("Authentication required", 401);

  const { data, error } = await supabase.auth.getUser(token);
  const userId = data?.user?.id ? String(data.user.id) : "";
  if (error || !userId) throw new HttpError("Invalid or expired session", 401);
  return userId;
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

    if (!analysisId) return errorResponse("analysis_id is required", 400);
    if (!GRADES.has(trueGrade)) return errorResponse("true_grade must be A, B or C", 400);
    if (!RISKS.has(trueMoistureRisk)) {
      return errorResponse("true_moisture_risk is invalid", 400);
    }

    const supabase = createServiceClient();
    const operatorId = await authenticatedUserId(req, supabase);
    const requestedOperatorId = body.operator_id ? String(body.operator_id) : "";
    if (requestedOperatorId && requestedOperatorId !== operatorId) {
      throw new HttpError("operator_id does not match the signed-in user", 403);
    }

    const { data: job, error: jobError } = await supabase
      .from("analysis_jobs")
      .select("operator_id, final_grade, grain_grade, moisture_percent, moisture_risk")
      .eq("id", analysisId)
      .maybeSingle();
    if (jobError) throw new Error(`Could not load analysis job: ${jobError.message}`);
    if (!job) throw new HttpError("Analysis job not found", 404);
    if (String(job.operator_id ?? "") !== operatorId) {
      throw new HttpError("This analysis belongs to another user", 403);
    }

    const { data: correction, error: insertError } = await supabase
      .from("operator_corrections")
      .insert({
        analysis_id: analysisId,
        operator_id: operatorId,
        predicted_final_grade: job.final_grade ?? null,
        corrected_final_grade: trueGrade,
        predicted_grain_grade: job.grain_grade ?? null,
        corrected_grain_grade: body.true_grain_grade
          ? String(body.true_grain_grade).toUpperCase()
          : trueGrade,
        predicted_moisture_percent: job.moisture_percent ?? null,
        corrected_moisture_percent: body.corrected_moisture_percent ?? null,
        predicted_moisture_risk: job.moisture_risk ?? null,
        corrected_moisture_risk: trueMoistureRisk,
        notes,
      })
      .select("id")
      .single();
    if (insertError || !correction?.id) {
      throw new Error(`Could not save correction: ${insertError?.message ?? "no id returned"}`);
    }

    return successResponse({
      saved: true,
      analysis_id: analysisId,
      correction_id: correction.id,
    });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    return errorResponse("grain-grade-feedback failed", status, error);
  }
});
