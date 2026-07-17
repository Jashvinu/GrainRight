import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

const FORECAST_URL = "https://api.open-meteo.com/v1/forecast";
const ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive";

type WeatherSeries = Record<string, unknown[]>;
type Language = "en" | "hi" | "mr";

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function languageParam(params: URLSearchParams): Language {
  const code = text(params.get("language")).toLowerCase();
  return code === "hi" || code === "mr" ? code : "en";
}

function localized(
  language: Language,
  english: string,
  hindi: string,
  marathi: string,
): string {
  if (language === "hi") return hindi;
  if (language === "mr") return marathi;
  return english;
}

function numberParam(params: URLSearchParams, key: string): number | null {
  const value = Number(params.get(key));
  return Number.isFinite(value) ? value : null;
}

function codeLabel(code: unknown): string {
  const value = Number(code);
  if ([0].includes(value)) return "Clear";
  if ([1, 2, 3].includes(value)) return "Cloudy";
  if ([45, 48].includes(value)) return "Fog";
  if ([51, 53, 55, 56, 57].includes(value)) return "Drizzle";
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(value)) return "Rain";
  if ([95, 96, 99].includes(value)) return "Thunderstorm";
  return "Weather";
}

function pick(series: WeatherSeries | undefined, key: string, index: number) {
  const values = series?.[key];
  return Array.isArray(values) ? values[index] ?? null : null;
}

function sum(values: unknown[]): number {
  return values.reduce<number>((total, value) => {
    const n = Number(value);
    return total + (Number.isFinite(n) ? n : 0);
  }, 0);
}

function average(values: unknown[]): number | null {
  const nums = values.map(Number).filter(Number.isFinite);
  if (nums.length === 0) return null;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function rounded(value: number | null, digits = 1): number | null {
  if (value == null || !Number.isFinite(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function labelFromScore(score: number): string {
  if (score >= 0.68) return "high";
  if (score >= 0.38) return "medium";
  return "low";
}

function buildHourly(hourly: WeatherSeries): Record<string, unknown>[] {
  const times = hourly.time ?? [];
  const limit = Math.min(24, times.length);
  return Array.from({ length: limit }, (_, index) => ({
    time: times[index],
    temperature_c: pick(hourly, "temperature_2m", index),
    humidity_percent: pick(hourly, "relative_humidity_2m", index),
    rain_probability_percent: pick(hourly, "precipitation_probability", index),
    rain_mm: pick(hourly, "precipitation", index),
    wind_kmh: pick(hourly, "wind_speed_10m", index),
    cloud_percent: pick(hourly, "cloud_cover", index),
    et0_mm: pick(hourly, "et0_fao_evapotranspiration", index),
    soil_moisture: pick(hourly, "soil_moisture_0_to_1cm", index),
    soil_temperature_c: pick(hourly, "soil_temperature_0cm", index),
    weather_code: pick(hourly, "weather_code", index),
    condition: codeLabel(pick(hourly, "weather_code", index)),
  }));
}

function buildDaily(daily: WeatherSeries): Record<string, unknown>[] {
  const times = daily.time ?? [];
  const limit = Math.min(7, times.length);
  return Array.from({ length: limit }, (_, index) => ({
    date: times[index],
    temp_max_c: pick(daily, "temperature_2m_max", index),
    temp_min_c: pick(daily, "temperature_2m_min", index),
    rain_mm: pick(daily, "precipitation_sum", index),
    rain_probability_percent: pick(daily, "precipitation_probability_max", index),
    wind_max_kmh: pick(daily, "wind_speed_10m_max", index),
    et0_mm: pick(daily, "et0_fao_evapotranspiration_sum", index),
  }));
}

function buildStress(
  current: Record<string, unknown>,
  hourly: WeatherSeries,
  daily: WeatherSeries,
  satelliteMoisture: number | null,
  language: Language,
) {
  const rain24h = sum((hourly.precipitation ?? []).slice(0, 24));
  const rain7d = sum((daily.precipitation_sum ?? []).slice(0, 7));
  const et0_7d = sum((daily.et0_fao_evapotranspiration_sum ?? []).slice(0, 7));
  const temp = Number(current.temperature_c);
  const humidity = Number(current.humidity_percent);
  const heatStress = Number.isFinite(temp) ? clamp01((temp - 30) / 12) : 0.2;
  const dryness = clamp01((et0_7d - rain7d) / 35);
  const humidityStress = Number.isFinite(humidity) ? clamp01((55 - humidity) / 35) : 0.15;
  const satelliteStress = satelliteMoisture == null ? 0.3 : clamp01((0.35 - satelliteMoisture) / 0.35);
  const score = clamp01(dryness * 0.42 + heatStress * 0.22 + humidityStress * 0.16 + satelliteStress * 0.2);
  return {
    score: rounded(score, 2),
    label: labelFromScore(score),
    rain_24h_mm: rounded(rain24h),
    rain_7d_mm: rounded(rain7d),
    et0_7d_mm: rounded(et0_7d),
    satellite_moisture: satelliteMoisture,
    recommendation: score >= 0.68
      ? localized(
        language,
        "Irrigate in a cool window and inspect dry patches.",
        "ठंडे समय में सिंचाई करें और सूखे पैच देखें।",
        "थंड्या वेळेत सिंचन करा आणि कोरडे पट्टे तपासा.",
      )
      : score >= 0.38
      ? localized(
        language,
        "Monitor soil moisture and prepare irrigation if rain misses.",
        "मिट्टी की नमी देखें और बारिश न हो तो सिंचाई तैयार रखें।",
        "मातीचा ओलावा पाहा आणि पाऊस चुकल्यास सिंचन तयार ठेवा.",
      )
      : localized(
        language,
        "Water stress is currently controlled.",
        "अभी पानी तनाव नियंत्रण में है।",
        "सध्या पाण्याचा ताण नियंत्रणात आहे.",
      ),
  };
}

function buildCropHealthWeather(
  current: Record<string, unknown>,
  hourly: WeatherSeries,
  daily: WeatherSeries,
  crop: string,
  stage: string,
  language: Language,
) {
  const rain7d = sum((daily.precipitation_sum ?? []).slice(0, 7));
  const avgHumidity = average((hourly.relative_humidity_2m ?? []).slice(0, 24));
  const temp = Number(current.temperature_c);
  const heat = Number.isFinite(temp) ? clamp01((temp - 32) / 10) : 0.1;
  const excessRain = clamp01((rain7d - 70) / 80);
  const diseaseHumidity = avgHumidity == null ? 0.2 : clamp01((avgHumidity - 72) / 22);
  const floweringPenalty = stage.toLowerCase().includes("flower") ? 0.08 : 0;
  const risk = clamp01(heat * 0.32 + excessRain * 0.25 + diseaseHumidity * 0.33 + floweringPenalty);
  const score = clamp01(1 - risk);
  return {
    score: rounded(score, 2),
    label: score >= 0.72 ? "good" : score >= 0.48 ? "watch" : "stressed",
    crop,
    growth_stage: stage,
    heat_risk: rounded(heat, 2),
    rain_risk: rounded(excessRain, 2),
    humidity_risk: rounded(diseaseHumidity, 2),
    summary: score >= 0.72
      ? localized(
        language,
        "Weather is supportive for current crop growth.",
        "मौसम वर्तमान फसल बढ़वार के लिए सहायक है।",
        "हवामान सध्याच्या पीक वाढीसाठी अनुकूल आहे.",
      )
      : score >= 0.48
      ? localized(
        language,
        "Weather needs scouting attention this week.",
        "इस सप्ताह मौसम के कारण खेत जांच पर ध्यान दें।",
        "या आठवड्यात हवामानामुळे शेत तपासणीवर लक्ष द्या.",
      )
      : localized(
        language,
        "Weather stress is elevated; prioritize field inspection.",
        "मौसम तनाव अधिक है; खेत निरीक्षण को प्राथमिकता दें।",
        "हवामान ताण वाढला आहे; शेत तपासणीला प्राधान्य द्या.",
      ),
  };
}

async function fetchOpenMeteo(url: URL): Promise<Record<string, unknown>> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Open-Meteo ${response.status}: ${await response.text()}`);
  }
  return await response.json();
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "GET") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const input = new URL(req.url);
    const params = input.searchParams;
    const latitude = numberParam(params, "latitude");
    const longitude = numberParam(params, "longitude");
    if (latitude == null || longitude == null) {
      return errorResponse("latitude and longitude are required", 400, undefined, "missing_coordinates");
    }

    const startDate = text(params.get("start_date"));
    const endDate = text(params.get("end_date"));
    const mode = (text(params.get("mode")) || "").toLowerCase();
    const archiveMode = mode === "archive" || mode === "history";
    if (archiveMode && (!startDate || !endDate)) {
      return errorResponse("start_date and end_date are required", 400, undefined, "missing_date_range");
    }
    if (archiveMode && startDate && endDate) {
      const url = new URL(ARCHIVE_URL);
      url.searchParams.set("latitude", String(latitude));
      url.searchParams.set("longitude", String(longitude));
      url.searchParams.set("start_date", startDate);
      url.searchParams.set("end_date", endDate);
      url.searchParams.set("hourly", "temperature_2m,precipitation,apparent_temperature,wind_speed_10m,cloud_cover,weather_code");
      url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min,precipitation_sum");
      url.searchParams.set("timezone", "auto");
      const archive = await fetchOpenMeteo(url);
      return successResponse({
        ...archive,
        updated_at: new Date().toISOString(),
        source: "open-meteo-archive",
      });
    }

    const crop = text(params.get("crop")) || "millet";
    const growthStage = text(params.get("growth_stage")) || text(params.get("stage")) || "";
    const satelliteMoisture = numberParam(params, "satellite_moisture");
    const language = languageParam(params);
    const forecastUrl = new URL(FORECAST_URL);
    forecastUrl.searchParams.set("latitude", String(latitude));
    forecastUrl.searchParams.set("longitude", String(longitude));
    forecastUrl.searchParams.set("current", "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m");
    forecastUrl.searchParams.set("hourly", "temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,wind_speed_10m,cloud_cover,weather_code,et0_fao_evapotranspiration,soil_moisture_0_to_1cm,soil_temperature_0cm");
    forecastUrl.searchParams.set("daily", "temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,et0_fao_evapotranspiration_sum");
    forecastUrl.searchParams.set("forecast_days", "7");
    forecastUrl.searchParams.set("timezone", "auto");

    let data: Record<string, unknown>;
    try {
      data = await fetchOpenMeteo(forecastUrl);
    } catch (_error) {
      forecastUrl.searchParams.set("hourly", "temperature_2m,relative_humidity_2m,precipitation_probability,precipitation,wind_speed_10m,cloud_cover,weather_code,et0_fao_evapotranspiration");
      data = await fetchOpenMeteo(forecastUrl);
    }

    const currentRaw = data.current as Record<string, unknown> | undefined ?? {};
    const hourlyRaw = data.hourly as WeatherSeries | undefined ?? {};
    const dailyRaw = data.daily as WeatherSeries | undefined ?? {};
    const current = {
      time: currentRaw.time ?? null,
      temperature_c: currentRaw.temperature_2m ?? null,
      humidity_percent: currentRaw.relative_humidity_2m ?? null,
      apparent_temperature_c: currentRaw.apparent_temperature ?? null,
      rain_mm: currentRaw.precipitation ?? null,
      wind_kmh: currentRaw.wind_speed_10m ?? null,
      cloud_percent: currentRaw.cloud_cover ?? null,
      weather_code: currentRaw.weather_code ?? null,
      condition: codeLabel(currentRaw.weather_code),
    };
    const hourly24h = buildHourly(hourlyRaw);
    const daily7d = buildDaily(dailyRaw);
    const waterStress = buildStress(current, hourlyRaw, dailyRaw, satelliteMoisture, language);
    const cropHealthWeather = buildCropHealthWeather(current, hourlyRaw, dailyRaw, crop, growthStage, language);

    return successResponse({
      latitude: data.latitude ?? latitude,
      longitude: data.longitude ?? longitude,
      timezone: data.timezone ?? "auto",
      current,
      hourly_24h: hourly24h,
      daily_7d: daily7d,
      agro_weather: {
        crop,
        growth_stage: growthStage,
        days_after_sowing: numberParam(params, "days_after_sowing"),
        irrigation_signal: waterStress.label,
        disease_weather_signal: cropHealthWeather.label,
        next_action: waterStress.label === "high"
          ? localized(
            language,
            "Check water stress before midday and irrigate if soil is dry.",
            "दोपहर से पहले पानी तनाव देखें और मिट्टी सूखी हो तो सिंचाई करें।",
            "दुपारपूर्वी पाण्याचा ताण तपासा आणि माती कोरडी असल्यास सिंचन करा.",
          )
          : localized(
            language,
            "Scout the crop during the next field round.",
            "अगले खेत चक्कर में फसल की जांच करें।",
            "पुढील शेत फेरीत पिकाची तपासणी करा.",
          ),
      },
      water_stress: waterStress,
      crop_health_weather: cropHealthWeather,
      updated_at: new Date().toISOString(),
      source: "open-meteo-forecast",
    });
  } catch (error) {
    return errorResponse("weather lookup failed", 500, error, "weather_lookup_failed");
  }
});
