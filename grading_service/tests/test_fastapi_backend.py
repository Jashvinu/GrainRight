from __future__ import annotations

import json
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

import backend.app.services as services_module
from backend.app.main import app
from backend.app.services import AppServices, _extract_percent_from_text, _normalize_moisture_candidate, get_services


def _image_bytes() -> bytes:
    buffer = BytesIO()
    Image.new("RGB", (24, 24), color=(130, 90, 50)).save(buffer, format="JPEG")
    return buffer.getvalue()


@dataclass
class FakeServices:
    saved_feedback: bool = False

    def health(self) -> dict:
        return {
            "status": "ok",
            "runtime": {
                "runtime_online": True,
                "model_ready": True,
                "runtime_label": "Cloud Ready",
                "runtime_detail": "dashscope is configured for qwen3-vl-plus.",
                "chunk_count": 12,
                "crop_route_count": 0,
                "provider": "dashscope",
                "model": "qwen3-vl-plus",
                "provider_label": "dashscope/qwen3-vl-plus",
            },
            "pending_feedback": 2,
        }

    async def save_upload(self, upload, purpose: str = "api"):
        if upload.content_type not in {"image/jpeg", "image/png", "image/jpg"}:
            raise HTTPException(status_code=415, detail="Upload must be a JPG or PNG image.")
        return "saved/sample.jpg"

    def crop_catalog(self) -> dict:
        return {
            "crops": [
                {
                    "value": "finger_millets",
                    "label": "Finger Millets",
                    "aliases": ["Ragi"],
                    "varieties": [
                        {"value": "gpu_48", "label": "GPU 48", "source_file": "knowledge/rag/crop_knowledge/FingerMillets/Variety/GPU48.MD"}
                    ],
                    "rule_summary": ["moisture: A <= 12, B <= 13, C <= 14"],
                }
            ]
        }

    def extract_moisture_reading(self, moisture_image_path: str | None, manual_moisture_percent: float | None = None) -> dict:
        return {
            "percent": 12.4,
            "source": "moisture_meter_ocr",
            "confidence": 0.92,
            "raw_text": "12.4%",
            "display_text": "12.4%",
        }

    def analyze(
        self,
        image_path: str,
        image_name: str,
        crop_type: str,
        crop_variety: str,
        moisture_image_path: str | None,
        moisture_image_name: str | None,
        moisture_reading: dict,
        confidence_threshold: int,
    ) -> dict:
        return {
            "analysis_id": "analysis-1",
            "image_name": image_name,
            "grain_image_name": image_name,
            "moisture_image_name": moisture_image_name,
            "quality": {
                "grade": "B",
                "grain_grade": "A",
                "score": 78,
                "grain_score": 91,
                "moisture_score": 82,
                "score_breakdown": {
                    "grain_grade": "A",
                    "grain_score": 91,
                    "moisture_score": 82,
                    "final_score": 78,
                    "metrics": {
                        "moisture": {"value": 12.4, "grade": "B", "score": 82}
                    },
                    "penalties": [
                        {"name": "penalty_1", "points": 12, "reason": "Moisture blocks Grade A"}
                    ],
                    "rule_source": "test_rules",
                },
                "reject_recommended": False,
                "reject_reasons": [],
                "broken_grain_percent": 1.2,
                "foreign_matter_percent": 0.3,
                "uniformity_score": 82,
                "mold_visible": False,
            },
            "moisture": {
                "risk_level": "MODERATE",
                "percent_estimate": moisture_reading["percent"],
                "machine_percent": moisture_reading["percent"],
                "source": moisture_reading["source"],
                "ocr_confidence": moisture_reading["confidence"],
                "calibrated": True,
                "meter_reading": moisture_reading,
            },
            "confidence": {
                "overall": 76,
                "pass1_safety_gate": 90,
                "pass2_grading": 76,
            },
            "selection": {
                "selected_crop": crop_type.lower() if crop_type else "ragi",
                "selected_variety": crop_variety,
                "requested_crop": crop_type,
                "requested_variety": crop_variety,
                "selected_crop_confidence": 1.0,
                "selection_source": "manual",
            },
            "routing": {
                "route_label": "default",
                "route_provider": "dashscope",
                "route_model": "qwen3-vl-plus",
                "route_base_url": "https://example.test/v1",
                "route_fallback_used": False,
                "route_attempts": ["default:dashscope/qwen3-vl-plus@https://example.test/v1"],
                "route_error": None,
            },
            "applied_rules": [{"rule_id": "test_rule", "rule_name": "Test Rule"}],
            "audit": {
                "timestamp": "2026-06-12T00:00:00+00:00",
                "model_version": "dashscope/qwen3-vl-plus",
                "rag_chunks_used": 3,
                "session_log_id": "analysis-1",
                "session_log_path": "data/logs/sessions/2026-06-12/analysis-1.json",
            },
            "proxy_summary": {
                "texture_entropy": 1.4,
                "roughness_score": 22.0,
                "grain_mask_coverage": 0.42,
                "uniformity_score": 82,
                "darkness_index": 48,
                "clumping_density": 0.05,
                "capture_distance_estimate_cm": None,
                "calibration_source": "none",
            },
            "manual_review_required": False,
            "operator_summary": "Usable lot.",
            "signal_highlights": ["Good uniformity"],
        }

    def submit_feedback(
        self,
        analysis_id: str,
        true_grade: str,
        true_moisture_risk: str,
        notes: str = "",
        true_grain_grade: str | None = None,
    ) -> dict:
        self.saved_feedback = True
        return {
            "saved": True,
            "pending_count": 3,
            "analysis_id": analysis_id,
            "feedback_path": "data/feedback/feedback_data/analysis-1.json",
            "training_export_saved": True,
            "session_log_path": "data/logs/sessions/2026-06-12/analysis-1.json",
        }


@pytest.fixture()
def client():
    fake_services = FakeServices()
    app.dependency_overrides[get_services] = lambda: fake_services
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()


def test_health_returns_runtime_without_secret(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["runtime"]["model_ready"] is True
    assert "api_key" not in str(payload).lower()


def test_crops_returns_catalog(client):
    response = client.get("/api/crops")

    assert response.status_code == 200
    payload = response.json()
    assert payload["crops"][0]["value"] == "finger_millets"
    assert payload["crops"][0]["varieties"][0]["label"] == "GPU 48"


def test_meter_text_parser_handles_real_display_formats():
    assert _extract_percent_from_text("MEMORY FULL MILLET % 08.8") == 8.8
    assert _extract_percent_from_text("MEMORY FULL RICE-5Grn % 09.8") == 9.8
    assert _normalize_moisture_candidate(88.0) == 8.8
    assert _normalize_moisture_candidate(98.0) == 9.8


def test_analyze_accepts_grain_and_meter_uploads(client):
    response = client.post(
        "/api/analyze",
        files={
            "grain_image": ("sample.jpg", _image_bytes(), "image/jpeg"),
            "moisture_image": ("meter.jpg", _image_bytes(), "image/jpeg"),
        },
        data={"crop_type": "finger_millets", "crop_variety": "GPU 48", "confidence_threshold": "60"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["analysis_id"] == "analysis-1"
    assert payload["quality"]["grade"] == "B"
    assert payload["quality"]["grain_grade"] == "A"
    assert payload["quality"]["score_breakdown"]["rule_source"] == "test_rules"
    assert payload["moisture"]["risk_level"] == "MODERATE"
    assert payload["moisture"]["machine_percent"] == 12.4
    assert payload["selection"]["selected_variety"] == "GPU 48"


def test_analyze_rejects_non_image_upload(client):
    response = client.post(
        "/api/analyze",
        files={
            "grain_image": ("notes.txt", b"not image", "text/plain"),
            "moisture_image": ("meter.jpg", _image_bytes(), "image/jpeg"),
        },
    )

    assert response.status_code == 415


def test_analyze_requires_moisture_meter_image_or_manual_value(client):
    response = client.post(
        "/api/analyze",
        files={"grain_image": ("sample.jpg", _image_bytes(), "image/jpeg")},
        data={"crop_type": "rice", "crop_variety": "Basmati"},
    )

    assert response.status_code == 422


def test_feedback_submits_for_analysis(client):
    response = client.post(
        "/api/feedback",
        json={
            "analysis_id": "analysis-1",
            "true_grade": "A",
            "true_grain_grade": "A",
            "true_moisture_risk": "LOW",
            "notes": "operator correction",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["saved"] is True
    assert payload["pending_count"] == 3
    assert payload["training_export_saved"] is True


def test_session_log_writer_redacts_secrets(tmp_path, monkeypatch):
    monkeypatch.setattr(services_module, "SESSION_LOGS_DIR", tmp_path)
    services = object.__new__(AppServices)
    services.pipeline = type(
        "Pipeline",
        (),
        {
            "last_grading_audit": {
                "route_meta": {
                    "model": "qwen3-vl-plus",
                    "api_key": "secret-token",
                }
            }
        },
    )()

    log_ref = services._write_session_log(
        analysis_id="analysis-log",
        image_path="grain.jpg",
        image_name="grain.jpg",
        moisture_image_path="meter.jpg",
        moisture_image_name="meter.jpg",
        crop_type="rice",
        crop_variety="Basmati",
        moisture_reading={"percent": 9.8, "raw_text": "RICE % 09.8"},
        proxies={"uniformity_score": 95.0},
        payload={
            "audit": {"timestamp": "2026-06-12T00:00:00+00:00"},
            "quality": {"grade": "A", "score": 94},
        },
    )

    assert log_ref is not None
    log_path = Path(log_ref)
    if not log_path.is_absolute():
        log_path = services_module.PROJECT_ROOT / log_path
    payload = json.loads(log_path.read_text(encoding="utf-8"))
    assert payload["analysis_id"] == "analysis-log"
    assert payload["pipeline_audit"]["route_meta"]["api_key"] == "[redacted]"
    assert payload["moisture_ocr"]["percent"] == 9.8
