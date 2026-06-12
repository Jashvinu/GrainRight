import { corsHeaders } from "../_shared/cors.ts";

function errorResponse(message: string, status = 400): Response {
  return new Response(JSON.stringify({ success: false, error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function successResponse(data: unknown): Response {
  return new Response(JSON.stringify({ success: true, data }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requireParam(url: URL, name: string): string {
  const value = url.searchParams.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") return errorResponse("Method not allowed", 405);

  try {
    const url = new URL(req.url);
    const latitude = Number(requireParam(url, "latitude"));
    const longitude = Number(requireParam(url, "longitude"));
    const startDate = requireParam(url, "start_date");
    const endDate = requireParam(url, "end_date");

    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
      return errorResponse("latitude must be a valid coordinate");
    }
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      return errorResponse("longitude must be a valid coordinate");
    }

    const params = new URLSearchParams({
      latitude: String(latitude),
      longitude: String(longitude),
      start_date: startDate,
      end_date: endDate,
      hourly:
        "temperature_2m,precipitation,apparent_temperature,wind_speed_10m,cloud_cover,weather_code",
      timezone: "auto",
    });

    const response = await fetch(
      `https://archive-api.open-meteo.com/v1/archive?${params}`,
    );
    if (!response.ok) {
      return errorResponse(
        `Open-Meteo request failed: ${response.status}`,
        502,
      );
    }

    const data = await response.json();
    const hourly = data?.hourly;
    const required = [
      "time",
      "temperature_2m",
      "precipitation",
      "apparent_temperature",
      "wind_speed_10m",
      "cloud_cover",
      "weather_code",
    ];

    for (const key of required) {
      if (!Array.isArray(hourly?.[key])) {
        return errorResponse(`Open-Meteo response missing hourly.${key}`, 502);
      }
    }

    const expectedLength = hourly.time.length;
    for (const key of required.slice(1)) {
      if (hourly[key].length !== expectedLength) {
        return errorResponse(`Open-Meteo hourly.${key} length mismatch`, 502);
      }
    }

    return successResponse({
      latitude,
      longitude,
      start_date: startDate,
      end_date: endDate,
      timezone: data.timezone,
      hourly,
    });
  } catch (error) {
    return errorResponse(
      error instanceof Error ? error.message : String(error),
    );
  }
});
