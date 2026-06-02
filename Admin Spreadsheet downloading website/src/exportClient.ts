import type { ExportPayload, ExportSummary } from "./types";

const functionUrl = import.meta.env.VITE_ADMIN_EXPORT_FUNCTION_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export function hasExportConfig() {
  return Boolean(functionUrl);
}

export async function fetchSummary(signal?: AbortSignal): Promise<ExportSummary> {
  return fetchJson<ExportSummary>(`${requiredFunctionUrl()}?summary=1`, signal);
}

export async function fetchExportPayload(): Promise<ExportPayload> {
  return fetchJson<ExportPayload>(requiredFunctionUrl());
}

async function fetchJson<T>(url: string, signal?: AbortSignal): Promise<T> {
  const headers: HeadersInit = {};
  if (anonKey) headers.Authorization = `Bearer ${anonKey}`;

  const response = await fetch(url, {
    method: "GET",
    headers,
    signal,
  });

  const body = await response.text();
  let data: unknown = null;
  if (body) {
    try {
      data = JSON.parse(body);
    } catch {
      throw new Error(body);
    }
  }

  if (!response.ok) {
    const message =
      typeof data === "object" && data && "error" in data
        ? String((data as { error: unknown }).error)
        : `Request failed with ${response.status}`;
    throw new Error(message);
  }

  return data as T;
}

function requiredFunctionUrl() {
  if (!functionUrl) {
    throw new Error("Missing VITE_ADMIN_EXPORT_FUNCTION_URL");
  }
  return functionUrl;
}
