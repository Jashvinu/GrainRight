from __future__ import annotations

import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import HTTPException

from .services import AppServices
from .supabase_store import SupabaseStore


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _number(value: Any) -> Optional[float]:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def _result_update_from_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    quality = payload.get("quality") or {}
    moisture = payload.get("moisture") or {}
    confidence = payload.get("confidence") or {}
    audit = payload.get("audit") or {}
    routing = payload.get("routing") or {}
    score_breakdown = quality.get("score_breakdown") or {}
    meter_reading = moisture.get("meter_reading") or {}

    moisture_percent = (
        _number(moisture.get("machine_percent"))
        or _number(moisture.get("percent_estimate"))
        or _number(meter_reading.get("percent"))
    )
    return {
        "status": "completed",
        "final_grade": quality.get("grade"),
        "grain_grade": quality.get("grain_grade") or score_breakdown.get("grain_grade"),
        "final_score": _number(quality.get("score")) or _number(score_breakdown.get("final_score")),
        "grain_score": _number(quality.get("grain_score")) or _number(score_breakdown.get("grain_score")),
        "moisture_percent": moisture_percent,
        "moisture_risk": moisture.get("risk_level") or moisture.get("risk"),
        "moisture_source": moisture.get("source") or meter_reading.get("source"),
        "moisture_confidence": _number(moisture.get("ocr_confidence")) or _number(meter_reading.get("confidence")),
        "reject_recommended": bool(quality.get("reject_recommended")),
        "reject_reasons": quality.get("reject_reasons") or [],
        "applied_rules": payload.get("applied_rules") or [],
        "quality_metrics": {
            "broken_grain_percent": quality.get("broken_grain_percent"),
            "foreign_matter_percent": quality.get("foreign_matter_percent"),
            "uniformity_score": quality.get("uniformity_score"),
            "mold_visible": quality.get("mold_visible"),
            "proxy_summary": payload.get("proxy_summary") or {},
        },
        "score_breakdown": score_breakdown,
        "model_version": audit.get("model_version"),
        "rule_version": audit.get("rule_version"),
        "route_version": routing.get("route_label"),
        "completed_at": _now(),
        "result_payload": payload,
    }


def run_analysis_job(analysis_id: str, store: SupabaseStore, services: AppServices) -> Dict[str, Any]:
    started = time.perf_counter()
    job = store.get_analysis_job(analysis_id)
    try:
        store.update_analysis_job(analysis_id, {"status": "processing", "error_message": None})
        store.insert_analysis_log(
            analysis_id,
            "processing",
            {"message": "Grading worker started.", "job": job},
        )

        grain_path_value = job.get("grain_image_path")
        moisture_path_value = job.get("moisture_image_path")
        if not grain_path_value:
            raise HTTPException(status_code=422, detail="grain_image_path is required.")
        if not moisture_path_value and job.get("manual_moisture_percent") is None:
            raise HTTPException(status_code=422, detail="moisture_image_path or manual_moisture_percent is required.")

        grain_path = store.materialize_storage_path(str(grain_path_value), purpose="grain")
        moisture_path = (
            store.materialize_storage_path(str(moisture_path_value), purpose="moisture_meter")
            if moisture_path_value
            else None
        )
        store.insert_analysis_log(
            analysis_id,
            "download",
            {
                "grain_image_path": grain_path_value,
                "moisture_image_path": moisture_path_value,
            },
        )

        moisture_started = time.perf_counter()
        moisture_reading = services.extract_moisture_reading(
            moisture_path,
            manual_moisture_percent=job.get("manual_moisture_percent"),
        )
        store.insert_analysis_log(
            analysis_id,
            "moisture_ocr",
            moisture_reading,
            latency_ms=int((time.perf_counter() - moisture_started) * 1000),
        )

        model_started = time.perf_counter()
        payload = services.analyze(
            image_path=grain_path,
            image_name=Path(str(grain_path_value)).name,
            crop_type=job.get("crop_type"),
            crop_variety=job.get("variety") or job.get("crop_variety"),
            moisture_image_path=moisture_path,
            moisture_image_name=Path(str(moisture_path_value)).name if moisture_path_value else None,
            moisture_reading=moisture_reading,
            confidence_threshold=int(job.get("confidence_threshold") or 60),
            analysis_id=analysis_id,
        )
        store.insert_analysis_log(
            analysis_id,
            "model_result",
            payload,
            latency_ms=int((time.perf_counter() - model_started) * 1000),
        )

        update = _result_update_from_payload(payload)
        completed = store.update_analysis_job(analysis_id, update)
        store.insert_analysis_log(
            analysis_id,
            "completed",
            {"status": "completed"},
            latency_ms=int((time.perf_counter() - started) * 1000),
        )
        return completed
    except Exception as exc:
        status_code = getattr(exc, "status_code", 500)
        detail = getattr(exc, "detail", str(exc))
        store.update_analysis_job(
            analysis_id,
            {
                "status": "failed",
                "error_message": str(detail),
                "completed_at": _now(),
            },
        )
        store.insert_analysis_log(
            analysis_id,
            "error",
            {
                "status_code": status_code,
                "error": str(detail),
            },
            latency_ms=int((time.perf_counter() - started) * 1000),
        )
        raise
