import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

const BUCKET = "farmer-identity-documents";
const FILE_SIZE_LIMIT = 8 * 1024 * 1024;
const ALLOWED_MIME_TYPES = ["image/jpeg", "image/png", "image/webp"];

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

function bucketOptions() {
  return {
    public: false,
    fileSizeLimit: FILE_SIZE_LIMIT,
    allowedMimeTypes: ALLOWED_MIME_TYPES,
  };
}

function vlmEnv() {
  const apiKey = Deno.env.get("VLM_API_KEY") ??
    Deno.env.get("QWEN_VL_API_KEY") ??
    Deno.env.get("QWEN_API_KEY");
  const baseUrl = Deno.env.get("VLM_BASE_URL") ??
    Deno.env.get("QWEN_BASE_URL") ??
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
  const model = Deno.env.get("VLM_MODEL") ??
    Deno.env.get("QWEN_VL_MODEL") ??
    "qwen-vl-max";
  if (!apiKey) throw new Error("VLM_API_KEY or QWEN_API_KEY is not configured");
  return { apiKey, baseUrl, model };
}

function safeJsonParse(value: string): Record<string, unknown> | null {
  try {
    return JSON.parse(value);
  } catch {
    const match = value.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function num(value: unknown, fallback: number): number {
  const n = typeof value === "number"
    ? value
    : Number(String(value ?? "").match(/-?\d+(\.\d+)?/)?.[0]);
  return Number.isFinite(n) ? n : fallback;
}

function textValue(value: unknown): string {
  return String(value ?? "").trim();
}

function isAlreadyExistsError(error: unknown): boolean {
  const value = String(
    (error as { message?: unknown; error?: unknown })?.message ??
      (error as { error?: unknown })?.error ??
      error ??
      "",
  ).toLowerCase();
  return value.includes("already") || value.includes("duplicate") ||
    value.includes("exists");
}

function contentType(value: unknown): string {
  const normalized = textValue(value).toLowerCase().split(";")[0]?.trim() ?? "";
  if (!ALLOWED_MIME_TYPES.includes(normalized)) {
    throw new Error("Unsupported image type. Use JPG, PNG, or WebP.");
  }
  return normalized;
}

function extensionFor(type: string): string {
  if (type === "image/png") return "png";
  if (type === "image/webp") return "webp";
  return "jpg";
}

function safeFileStem(value: unknown): string {
  const raw = textValue(value).split(/[\\/]/).pop() ?? "";
  const stem = raw.replace(/\.[^.]+$/, "");
  const safe = stem
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return safe || "agri-record";
}

function documentPathFor(
  userId: string,
  body: Record<string, unknown>,
  type: string,
): string {
  const provided = textValue(body.document_path).replaceAll("\\", "/");
  if (provided.length > 0) {
    if (
      !provided.startsWith(`${userId}/`) ||
      provided.includes("..") ||
      provided.includes("//") ||
      provided.endsWith("/")
    ) {
      throw new Error("Document does not belong to this farmer session");
    }
    return provided;
  }
  const fileName = safeFileStem(body.file_name ?? body.fileName);
  return `${userId}/${Date.now()}-${fileName}.${extensionFor(type)}`;
}

function decodeImageBase64(value: unknown): Uint8Array {
  let raw = textValue(value);
  const comma = raw.indexOf(",");
  if (raw.startsWith("data:") && comma >= 0) {
    raw = raw.slice(comma + 1);
  }
  raw = raw.replace(/\s/g, "");
  if (raw.length === 0) throw new Error("image_base64 is required");

  const binary = atob(raw);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  if (bytes.length === 0) {
    throw new Error("The selected document image is empty");
  }
  if (bytes.length > FILE_SIZE_LIMIT) {
    throw new Error("The document image is too large");
  }
  return bytes;
}

async function ensureDocumentBucket(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<void> {
  const options = bucketOptions();
  const { error: createError } = await supabase.storage.createBucket(
    BUCKET,
    options,
  );
  if (createError && !isAlreadyExistsError(createError)) {
    const { error: getError } = await supabase.storage.getBucket(BUCKET);
    if (getError) {
      throw new Error(
        `Failed to create document bucket: ${
          createError.message ?? createError
        }`,
      );
    }
  }

  const { error: updateError } = await supabase.storage.updateBucket(
    BUCKET,
    options,
  );
  if (updateError) {
    throw new Error(
      `Failed to update document bucket: ${updateError.message ?? updateError}`,
    );
  }
}

async function uploadDocumentImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  body: Record<string, unknown>,
): Promise<string> {
  const type = contentType(body.content_type ?? body.contentType);
  const bytes = decodeImageBase64(body.image_base64 ?? body.imageBase64);
  const path = documentPathFor(userId, body, type);
  await ensureDocumentBucket(supabase);
  const { error } = await supabase.storage.from(BUCKET).upload(path, bytes, {
    contentType: type,
    upsert: false,
  });
  if (error) {
    throw new Error(
      `Failed to upload document image: ${error.message ?? error}`,
    );
  }
  return path;
}

function normalizeDigits(value: unknown): string {
  const map: Record<string, string> = {
    "०": "0",
    "१": "1",
    "२": "2",
    "३": "3",
    "४": "4",
    "५": "5",
    "६": "6",
    "७": "7",
    "८": "8",
    "९": "9",
    "٠": "0",
    "١": "1",
    "٢": "2",
    "٣": "3",
    "٤": "4",
    "٥": "5",
    "٦": "6",
    "٧": "7",
    "٨": "8",
    "٩": "9",
  };
  return String(value ?? "").replace(
    /[०-९٠-٩]/g,
    (digit) => map[digit] ?? digit,
  );
}

function aadhaarDigits(value: unknown): string {
  const normalized = normalizeDigits(value);
  const grouped = normalized.match(/(?:^|\D)(\d(?:[\s.-]?\d){11})(?:\D|$)/);
  if (grouped) return grouped[1].replace(/\D/g, "");
  const digits = normalized.replace(/\D/g, "");
  return digits.length === 12 ? digits : "";
}

function firstText(parsed: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = textValue(parsed[key]);
    if (value.length > 0 && value.toLowerCase() !== "null") return value;
  }
  return "";
}

function hasAadhaarLabel(value: string): boolean {
  return /aadha?r/i.test(value) || /आधार/.test(value);
}

function firstAadhaarFromText(value: unknown): string {
  const normalized = normalizeDigits(value);
  const lines = normalized
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  for (const line of lines) {
    if (!hasAadhaarLabel(line)) continue;
    const candidate = aadhaarDigits(line);
    if (candidate) return candidate;
  }
  return aadhaarDigits(normalized);
}

function agriRecordId(value: unknown, aadhaar = ""): string {
  const cleaned = normalizeDigits(value)
    .trim()
    .toUpperCase()
    .replace(/^[\s:：#.\-–—]+|[\s:：#.\-–—]+$/g, "")
    .replace(/\s+/g, "")
    .replace(/[^A-Z0-9_./-]/g, "");
  if (cleaned.length < 4 || cleaned.length > 64) return "";
  if (aadhaar.length === 12 && cleaned === aadhaar) return "";
  if (aadhaar.length === 0 && /^\d{12}$/.test(cleaned)) return "";
  return cleaned;
}

function farmerName(value: unknown): string {
  let cleaned = textValue(value)
    .replace(/\s+/g, " ")
    .replace(/^[\s:：#.\-–—]+|[\s:：#.\-–—]+$/g, "")
    .replace(
      /^(?:farmer|applicant|holder)?\s*name\s*[:：#.\-–—]*/i,
      "",
    )
    .replace(
      /^(?:शेतकऱ्याचे|शेतकरी|अर्जदाराचे|लाभार्थी|खातेदाराचे|किसान|कृषक)?\s*(?:का|के|चे|ची|चा)?\s*(?:नाव|नांव|नाम)\s*[:：#.\-–—]*/iu,
      "",
    )
    .replace(
      /\s+(?:आधार|कृषी|कृषि|फार्म|शेत|गाव|तालुका|जिल्हा|मोबाईल|मोबाइल|aadha?r|agri|farm|village|district|mobile).*$/iu,
      "",
    )
    .replace(/[^\p{L}\p{M}.'\-\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  cleaned = cleaned.replace(/^[.'\-]+|[.'\-]+$/g, "").trim();
  if (cleaned.length < 2 || cleaned.length > 80) return "";
  if (/\d/.test(normalizeDigits(cleaned))) return "";
  if (!/[\p{L}\p{M}]/u.test(cleaned)) return "";
  const lower = cleaned.toLowerCase();
  if (
    lower === "name" || lower === "farmer" || cleaned === "नाव" ||
    cleaned === "नाम"
  ) {
    return "";
  }
  return cleaned;
}

function firstFarmerNameFromText(value: unknown): string {
  const lines = textValue(value)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const labelPatterns = [
    /(?:farmer|applicant|holder)?\s*name\s*[:：#.\-–—]*\s*([\p{L}\p{M}.'\-\s]{2,80})/iu,
    /(?:शेतकऱ्याचे|शेतकरी|अर्जदाराचे|लाभार्थी|खातेदाराचे|किसान|कृषक)?\s*(?:का|के|चे|ची|चा)?\s*(?:नाव|नांव|नाम)\s*[:：#.\-–—]*\s*([\p{L}\p{M}.'\-\s]{2,80})/iu,
  ];

  for (const line of lines) {
    if (hasAadhaarLabel(line)) continue;
    for (const pattern of labelPatterns) {
      const match = line.match(pattern);
      const candidate = farmerName(match?.[1]);
      if (candidate) return candidate;
    }
  }
  return "";
}

function firstAgriRecordIdFromText(value: unknown, aadhaar = ""): string {
  const normalized = normalizeDigits(value);
  const lines = normalized
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !hasAadhaarLabel(line));
  const labelPatterns = [
    /(?:FARMER|FARM|AGRI(?:CULTURE)?|AGRISTACK|REGISTRY|RECORD|GOVERNMENT\s+FARMER)[^\n\r]{0,40}(?:ID|NO\.?|NUMBER|CODE)[^A-Z0-9\n\r]{0,10}([A-Z0-9][A-Z0-9_./-]{3,63})/i,
    /(?:शेतकरी|किसान|कृषक|कृषी|कृषि|फार्म|शेत|जमीन)[^\n\r]{0,40}(?:आयडी|आईडी|ID|क्रमांक|क्र\.?|नंबर|नोंदणी|पंजीकरण)[^A-Z0-9\n\r]{0,10}([A-Z0-9][A-Z0-9_./-]{3,63})/iu,
    /(?:आयडी|आईडी|ID)[^A-Z0-9\n\r]{0,10}([A-Z0-9][A-Z0-9_./-]{3,63})/iu,
  ];

  for (const line of lines) {
    for (const pattern of labelPatterns) {
      const match = line.match(pattern);
      const candidate = agriRecordId(match?.[1], aadhaar);
      if (candidate) return candidate;
    }
  }
  return "";
}

async function requireUser(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  req: Request,
): Promise<{ id: string } | Response> {
  const token = bearerToken(req);
  if (token.length === 0) {
    return errorResponse(
      "Missing auth token",
      401,
      undefined,
      "missing_auth_token",
    );
  }
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user?.id) {
    return errorResponse(
      "Invalid auth token",
      401,
      error,
      "invalid_auth_token",
    );
  }
  return { id: String(data.user.id) };
}

async function signUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  path: string,
): Promise<string> {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(path, 60 * 10);
  if (error || !data?.signedUrl) {
    throw new Error(
      `Failed to sign document image: ${error?.message ?? "no url"}`,
    );
  }
  return data.signedUrl;
}

async function callVlm(imageUrl: string): Promise<Record<string, unknown>> {
  const { apiKey, baseUrl, model } = vlmEnv();
  const prompt = [
    "Read this Indian farmer government agriculture record document. The text may be in Marathi, Hindi, or English.",
    "Extract only these fields when visible:",
    "1. aadhaar_number: the 12 digit Aadhaar number. Accept Devanagari digits and grouped formats.",
    "2. farm_id: the government farm/farmer/agriculture record ID. This can appear as agri record ID, farmer registry ID, AgriStack ID, farm ID, or government farmer ID.",
    "3. farmer_name: the farmer/person name near labels like शेतकऱ्याचे नाव, शेतकरी नाव, नाव, नांव, किसान का नाम, कृषक नाम, farmer name, applicant name.",
    "Use nearby labels. Marathi labels can include आधार क्रमांक, आधार क्र., शेतकरी आयडी, शेतकरी नोंदणी क्रमांक, कृषी नोंदणी क्रमांक, कृषी आयडी, फार्म आयडी, शेत आयडी, जमीन नोंद क्रमांक, शेतकऱ्याचे नाव, शेतकरी नाव, नाव, नांव. Hindi labels can include किसान आईडी, कृषक पंजीकरण संख्या, कृषि रिकॉर्ड आईडी, आधार संख्या, किसान का नाम.",
    "If only one government farm/farmer record ID is visible, return the same value for farm_id and agri_record_id.",
    'Return only JSON: {"aadhaar_number": string|null, "farm_id": string|null, "agri_record_id": string|null, "farmer_name": string|null, "raw_text": string|null, "confidence": 0..1}.',
    "Do not guess. If a field is unclear, return null for that field.",
  ].join("\n");
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: imageUrl } },
          ],
        },
      ],
      temperature: 0.1,
      max_tokens: 500,
      response_format: { type: "json_object" },
    }),
  });
  if (!response.ok) {
    throw new Error(
      `VLM request failed: ${response.status} ${await response.text()}`,
    );
  }
  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  const text = typeof content === "string"
    ? content
    : JSON.stringify(content ?? {});
  const parsed = safeJsonParse(text);
  if (!parsed) throw new Error("VLM returned invalid JSON");
  return parsed;
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
    const body = await req.json();
    const supabase = createServiceClient();
    const user = await requireUser(supabase, req);
    if (user instanceof Response) return user;

    if (body.upload_only === true || body.uploadOnly === true) {
      const documentPath = await uploadDocumentImage(supabase, user.id, body);
      return successResponse(
        {
          bucket: BUCKET,
          document_path: documentPath,
        },
        200,
        "farmer_document_upload_complete",
      );
    }

    const documentPath = String(body.document_path ?? "").trim();
    if (documentPath.length === 0) {
      return errorResponse(
        "document_path is required",
        400,
        undefined,
        "missing_document_path",
      );
    }
    if (!documentPath.startsWith(`${user.id}/`)) {
      return errorResponse(
        "Document does not belong to this farmer session",
        403,
        undefined,
        "document_owner_mismatch",
      );
    }

    const url = await signUrl(supabase, documentPath);
    const parsed = await callVlm(url);
    const rawText = firstText(parsed, ["raw_text", "ocr_text", "text"]);
    const aadhaar = aadhaarDigits(
      firstText(parsed, [
        "aadhaar_number",
        "aadhaar",
        "aadhar_number",
        "aadhar",
      ]),
    ) || firstAadhaarFromText(rawText);
    const modelRecordId = firstText(parsed, [
      "agri_record_id",
      "farm_id",
      "farmer_id",
      "farmer_registry_id",
      "agristack_id",
      "government_farmer_id",
    ]);
    const recordId = agriRecordId(modelRecordId, aadhaar) ||
      firstAgriRecordIdFromText(rawText, aadhaar);
    const extractedName = farmerName(
      firstText(parsed, [
        "farmer_name",
        "farmerName",
        "name",
        "full_name",
        "nav",
      ]),
    ) || firstFarmerNameFromText(rawText);

    return successResponse(
      {
        document_path: documentPath,
        identity: {
          farmer_name: extractedName,
          aadhaar_number: aadhaar,
          farm_id: recordId,
          agri_record_id: recordId,
          confidence: num(parsed.confidence, aadhaar || recordId ? 0.7 : 0.2),
          source: "document_ocr",
        },
      },
      200,
      "farmer_document_ocr_complete",
    );
  } catch (error) {
    return errorResponse("farmer-document-ocr failed", 500, error);
  }
});
