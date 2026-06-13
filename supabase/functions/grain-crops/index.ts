import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

// Crop + variety catalog for the grain-grading flow. Static, derived from
// grading_service/knowledge/rag/crop_knowledge. Kept in the same shape as the
// reference FastAPI /api/crops so the Flutter client maps it unchanged.

const CROPS = [
  {
    value: "finger_millets",
    label: "Finger Millet (Ragi)",
    aliases: ["ragi", "nachni", "nachani"],
    rule_summary: ["Grade A foreign ≤0.10%, moisture ≤12%"],
    varieties: [
      { value: "local", label: "Local" },
      { value: "dapoli_nachani", label: "Dapoli Nachani" },
      { value: "gpu28", label: "GPU-28" },
      { value: "gpu45", label: "GPU-45" },
      { value: "gpu48", label: "GPU-48" },
    ],
  },
  {
    value: "rice",
    label: "Rice (Paddy)",
    aliases: ["paddy", "bhat", "tandul"],
    rule_summary: [],
    varieties: [
      { value: "local", label: "Local" },
      { value: "indrayani", label: "Indrayani" },
      { value: "basmati", label: "Basmati" },
      { value: "kolam", label: "Kolam" },
    ],
  },
  {
    value: "bajra",
    label: "Pearl Millet (Bajra)",
    aliases: ["bajari", "bajra"],
    rule_summary: [],
    varieties: [
      { value: "local", label: "Local Maharashtra Bajari" },
      { value: "ictp8203", label: "ICTP 8203" },
    ],
  },
];

Deno.serve((req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "GET" && req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }
  return successResponse({ crops: CROPS });
});
