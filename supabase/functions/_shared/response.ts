// Shared response utilities for Supabase Edge Functions

import { corsHeaders } from "./cors.ts";

export function successResponse(
  data: any,
  status: number = 200,
  code?: string,
): Response {
  const response: any = {
    success: true,
  };

  if (data && typeof data === "object") {
    Object.assign(response, data);
  } else if (data !== undefined) {
    response.data = data;
  }

  if (code && code.trim().length > 0) {
    response.code = code.trim();
  }

  return new Response(
    JSON.stringify(response),
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    },
  );
}

export function errorResponse(
  message: string,
  status: number = 500,
  error?: any,
  code?: string,
): Response {
  const response: any = {
    success: false,
    error: message,
  };

  if (error) {
    response.details = error instanceof Error ? error.message : String(error);
  }

  if (code && code.trim().length > 0) {
    response.code = code.trim();
  }

  return new Response(JSON.stringify(response), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
