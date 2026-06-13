from __future__ import annotations

import json
import os
import re
import sys
import threading
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any, Dict, List, Optional

SRC_DIR = Path(__file__).resolve().parents[2] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

import cv2
import numpy as np
from dotenv import load_dotenv
from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps

from ai_grain_grade.feedback import FeedbackCollector, GradingFeedbackItem
from ai_grain_grade.paths import (
    FEEDBACK_DIR,
    FEEDBACK_TRAINING_EXPORT_PATH,
    LEGACY_RAG_DOCS_DIR,
    PROJECT_ROOT,
    RAG_DOCS_DIR,
    RAG_INDEX_PATH,
    SESSION_LOGS_DIR,
    SESSION_UPLOADS_DIR,
    ensure_runtime_dirs,
)
from ai_grain_grade.physics_proxies import PhysicsProxiesExtractor
from ai_grain_grade.rule_engine import CropRuleEngine, normalize_crop_name
from ai_grain_grade.vision_rag_pipeline import (
    CLOUD_QWEN_PROVIDERS,
    DEFAULT_DASHSCOPE_BASE_URL,
    DEFAULT_DASHSCOPE_MODEL,
    DEFAULT_SILICONFLOW_BASE_URL,
    LEGACY_SILICONFLOW_MODEL,
    VisionRAGPipeline,
)


CROP_KNOWLEDGE_DIR = RAG_DOCS_DIR / "crop_knowledge"
if not CROP_KNOWLEDGE_DIR.exists():
    CROP_KNOWLEDGE_DIR = LEGACY_RAG_DOCS_DIR / "crop_knowledge"
CROP_FOLDER_BY_VALUE = {
    "finger_millets": "FingerMillets",
    "rice": "Rice",
    "bajra": "Bajari",
}
CROP_LABELS = {
    "finger_millets": "Finger Millets",
    "rice": "Rice",
    "bajra": "Bajra",
}
CROP_ALIASES = {
    "finger_millets": ["Ragi", "Nachani", "Finger Millet"],
    "rice": ["Paddy", "Dhan"],
    "bajra": ["Bajari", "Bajri", "Pearl Millet"],
}
MOISTURE_VALUE_RE = re.compile(r"(?<!\d)(\d{1,3}(?:\.\d{1,2})?)(?!\d)")
AFTER_PERCENT_RE = re.compile(r"%[^\d]{0,8}(\d{1,3}(?:\.\d{1,2})?)")
PERCENT_CONTEXT_RE = re.compile(
    r"(?:moisture)[^\d]{0,12}(\d{1,3}(?:\.\d{1,2})?)|(\d{1,3}(?:\.\d{1,2})?)[^\d]{0,12}%",
    re.IGNORECASE,
)


def _first_env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


def _is_local_base_url(url: str) -> bool:
    text = str(url or "").lower()
    return any(marker in text for marker in ("localhost", "127.0.0.1", "0.0.0.0", "[::1]", "::1"))


def _load_crop_route_map() -> Dict[str, Any]:
    inline_map = os.getenv("CROP_MODEL_ROUTES", "").strip()
    if inline_map:
        try:
            parsed = json.loads(inline_map)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            return {}

    routes_path = os.getenv("CROP_MODEL_ROUTES_PATH", "").strip()
    if routes_path:
        try:
            route_path = Path(routes_path)
            if route_path.exists():
                parsed = json.loads(route_path.read_text(encoding="utf-8"))
                if isinstance(parsed, dict):
                    return parsed
        except Exception:
            return {}
    return {}


def qwen_runtime_config() -> Dict[str, Any]:
    requested_provider = os.getenv("QWEN_VL_PROVIDER", "dashscope").strip().lower()
    provider = requested_provider if requested_provider in CLOUD_QWEN_PROVIDERS else "dashscope"
    provider_warning = ""
    if requested_provider and requested_provider not in CLOUD_QWEN_PROVIDERS:
        provider_warning = f"Provider `{requested_provider}` is not supported; using `{provider}`."

    if provider == "siliconflow":
        model = os.getenv("QWEN_VL_MODEL", LEGACY_SILICONFLOW_MODEL)
        base_url = _first_env(
            "QWEN_VL_BASE_URL",
            "SILICONFLOW_BASE_URL",
            default=DEFAULT_SILICONFLOW_BASE_URL,
        )
        api_key = _first_env("QWEN_VL_API_KEY", "SILICONFLOW_API_KEY")
    else:
        model = os.getenv("QWEN_VL_MODEL", DEFAULT_DASHSCOPE_MODEL)
        base_url = _first_env(
            "QWEN_VL_BASE_URL",
            "DASHSCOPE_BASE_URL",
            default=DEFAULT_DASHSCOPE_BASE_URL if provider == "dashscope" else "",
        )
        api_key = _first_env("QWEN_VL_API_KEY", "DASHSCOPE_API_KEY")

    local_url_blocked = False
    if _is_local_base_url(base_url):
        local_url_blocked = True
        base_url = ""

    return {
        "provider": provider,
        "requested_provider": requested_provider,
        "model": model,
        "base_url": base_url,
        "api_key": api_key,
        "provider_warning": provider_warning,
        "local_url_blocked": local_url_blocked,
        "label": f"{provider}/{model}",
        "crop_model_routes": _load_crop_route_map(),
        "crop_model_routes_path": os.getenv("CROP_MODEL_ROUTES_PATH", "").strip(),
    }


def rag_chunk_count() -> int:
    if not RAG_INDEX_PATH.exists():
        return 0
    try:
        payload = json.loads(RAG_INDEX_PATH.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            payload = payload.get("chunks", [])
        return len(payload) if isinstance(payload, list) else 0
    except Exception:
        return 0


def runtime_status() -> Dict[str, Any]:
    cfg = qwen_runtime_config()
    status = {
        "runtime_online": False,
        "model_ready": False,
        "runtime_label": "Offline",
        "runtime_detail": "Cloud Qwen-VL runtime is not configured.",
        "chunk_count": rag_chunk_count(),
        "crop_route_count": len(cfg.get("crop_model_routes") or {}),
        "provider": cfg["provider"],
        "model": cfg["model"],
        "provider_label": cfg["label"],
    }
    if cfg["api_key"] and cfg["base_url"] and cfg["model"]:
        status["runtime_online"] = True
        status["model_ready"] = True
        status["runtime_label"] = "Cloud Ready"
        status["runtime_detail"] = (
            f"{cfg['provider']} is configured for {cfg['model']}. "
            "The API will call the cloud Qwen-VL endpoint during analysis."
        )
        if cfg["provider_warning"]:
            status["runtime_detail"] = f"{cfg['provider_warning']} {status['runtime_detail']}"
    else:
        missing = []
        if not cfg["api_key"]:
            missing.append("API key")
        if not cfg["base_url"]:
            missing.append("cloud base URL")
        if not cfg["model"]:
            missing.append("model")
        detail = f"Missing {', '.join(missing)} for {cfg['provider']} Qwen-VL."
        if cfg["provider_warning"]:
            detail = f"{cfg['provider_warning']} {detail}"
        if cfg["local_url_blocked"]:
            detail = f"{detail} Localhost Qwen endpoints are disabled in this build."
        status["runtime_label"] = "Cloud Config Needed"
        status["runtime_detail"] = detail
    return status


@dataclass
class AnalysisRecord:
    analysis_id: str
    image_path: str
    image_name: str
    moisture_image_path: Optional[str]
    moisture_image_name: Optional[str]
    crop_variety: Optional[str]
    measured_moisture_percent: Optional[float]
    moisture_reading: Dict[str, Any]
    proxies: Dict[str, Any]
    result: Any
    payload: Dict[str, Any]
    session_log_path: Optional[str] = None
    feedback_path: Optional[str] = None


def _display_label_from_name(name: str) -> str:
    label = Path(name).stem if "." in name else name
    label = label.replace("_", " ").replace("-", " ").strip()
    label = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", label)
    label = re.sub(r"(?<=[A-Za-z])(?=\d)", " ", label)
    return " ".join(label.split())


def _variety_value(label: str) -> str:
    return "_".join(label.lower().replace("(", "").replace(")", "").split())


def _supported_varieties_from_rule_file(path: Path) -> List[str]:
    if not path.exists():
        return []
    varieties: List[str] = []
    in_block = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line == "supported_varieties:":
            in_block = True
            continue
        if in_block and line.startswith("- "):
            varieties.append(_display_label_from_name(line[2:].strip()))
            continue
        if in_block and line and not line.startswith("#"):
            break
    return varieties


def _rule_file_for_crop(crop_value: str) -> Path:
    filename = CropRuleEngine.RULE_FILE_BY_CROP.get(crop_value, "")
    return CROP_KNOWLEDGE_DIR / "grading_rules" / filename


def _coerce_float(value: Any, default: float) -> float:
    if value is None:
        return default
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    match = MOISTURE_VALUE_RE.search(str(value))
    if not match:
        return default
    try:
        return float(match.group(1))
    except ValueError:
        return default


def _normalize_moisture_candidate(value: float) -> Optional[float]:
    """Normalize OCR values for LCD displays where the decimal point is missed."""
    if 0.0 < value <= 50.0:
        return value
    if 50.0 < value <= 250.0:
        shifted = value / 10.0
        if 3.0 <= shifted <= 25.0:
            return shifted
    return None


def _extract_percent_from_text(text: str) -> Optional[float]:
    for match in AFTER_PERCENT_RE.finditer(text or ""):
        value = _normalize_moisture_candidate(_coerce_float(match.group(1), -1.0))
        if value is not None:
            return value

    for match in PERCENT_CONTEXT_RE.finditer(text or ""):
        raw_value = match.group(1) or match.group(2)
        value = _normalize_moisture_candidate(_coerce_float(raw_value, -1.0))
        if value is not None:
            return value

    candidates = []
    for match in MOISTURE_VALUE_RE.finditer(text or ""):
        value = _normalize_moisture_candidate(_coerce_float(match.group(1), -1.0))
        if value is not None:
            candidates.append(value)
    if not candidates:
        return None
    return candidates[0]


def _crop_meter_display_image(image_path: str) -> str:
    """Crop the bright LCD area from a meter photo for more reliable OCR."""
    source = Path(image_path)
    image = cv2.imread(str(source))
    if image is None:
        return image_path

    height, width = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    hue_mask = cv2.inRange(hsv, np.array([18, 45, 110]), np.array([105, 255, 255]))
    blue, green, red = cv2.split(image)
    channel_mask = (
        (green.astype(np.int16) > 125)
        & (red.astype(np.int16) > 85)
        & (green.astype(np.int16) > blue.astype(np.int16) + 24)
        & (red.astype(np.int16) > blue.astype(np.int16) + 12)
    ).astype(np.uint8) * 255
    mask = cv2.bitwise_and(hue_mask, channel_mask)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (11, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.dilate(mask, kernel, iterations=1)

    contours, _hierarchy = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates: List[tuple[float, int, int, int, int]] = []
    frame_area = float(width * height)
    for contour in contours:
        x, y, box_width, box_height = cv2.boundingRect(contour)
        area = float(box_width * box_height)
        if area < frame_area * 0.004:
            continue
        aspect_ratio = box_width / max(float(box_height), 1.0)
        if aspect_ratio < 2.0 or aspect_ratio > 8.5:
            continue
        fill = cv2.countNonZero(mask[y : y + box_height, x : x + box_width]) / max(area, 1.0)
        top_half_bonus = 1.35 if y < height * 0.45 else 1.0
        candidates.append((area * fill * top_half_bonus, x, y, box_width, box_height))

    if not candidates:
        return image_path

    _score, x, y, box_width, box_height = max(candidates, key=lambda item: item[0])
    pad_x = int(box_width * 0.08)
    pad_y = int(box_height * 0.20)
    x1 = max(0, x - pad_x)
    y1 = max(0, y - pad_y)
    x2 = min(width, x + box_width + pad_x)
    y2 = min(height, y + box_height + pad_y)
    crop = image[y1:y2, x1:x2]
    if crop.size == 0:
        return image_path

    scale = max(1.0, min(3.0, 1100.0 / max(float(crop.shape[1]), 1.0)))
    if scale > 1.0:
        crop = cv2.resize(
            crop,
            None,
            fx=scale,
            fy=scale,
            interpolation=cv2.INTER_CUBIC,
        )

    SESSION_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    output = SESSION_UPLOADS_DIR / f"meter_display_{uuid.uuid4().hex[:10]}.jpg"
    cv2.imwrite(str(output), crop, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
    return str(output)


class AppServices:
    def __init__(self) -> None:
        load_dotenv(PROJECT_ROOT / ".env")
        ensure_runtime_dirs()
        cfg = qwen_runtime_config()
        self.extractor = PhysicsProxiesExtractor(
            grain_mask_threshold=50,
            morph_kernel_size=5,
        )
        self.pipeline = VisionRAGPipeline(
            qwen_provider=cfg["provider"],
            qwen_model=cfg["model"],
            qwen_base_url=cfg["base_url"],
            qwen_api_key=cfg["api_key"],
            crop_model_routes=cfg["crop_model_routes"],
            crop_model_routes_path=cfg["crop_model_routes_path"],
            vector_db_type="local",
            rag_retrieval_mode="lexical",
        )
        self.rule_engine = CropRuleEngine()
        self.feedback_collector = FeedbackCollector(storage_path=str(FEEDBACK_DIR))
        self.analyses: Dict[str, AnalysisRecord] = {}
        self._lock = threading.Lock()

    def _redact_for_log(self, value: Any) -> Any:
        if isinstance(value, dict):
            safe: Dict[str, Any] = {}
            for key, nested in value.items():
                key_text = str(key).lower()
                if any(secret in key_text for secret in ("api_key", "authorization", "secret", "token")):
                    safe[key] = "[redacted]"
                else:
                    safe[key] = self._redact_for_log(nested)
            return safe
        if isinstance(value, list):
            return [self._redact_for_log(item) for item in value]
        if isinstance(value, Path):
            return str(value)
        return value

    def _relative_path(self, path_value: Optional[str]) -> Optional[str]:
        if not path_value:
            return None
        path = Path(path_value)
        try:
            return str(path.resolve().relative_to(PROJECT_ROOT.resolve()))
        except Exception:
            return str(path_value)

    def _write_session_log(
        self,
        *,
        analysis_id: str,
        image_path: str,
        image_name: str,
        moisture_image_path: Optional[str],
        moisture_image_name: Optional[str],
        crop_type: Optional[str],
        crop_variety: Optional[str],
        moisture_reading: Dict[str, Any],
        proxies: Dict[str, Any],
        payload: Dict[str, Any],
    ) -> Optional[str]:
        try:
            timestamp = str(payload.get("audit", {}).get("timestamp") or datetime.now(timezone.utc).isoformat())
            day = timestamp[:10] if re.match(r"\d{4}-\d{2}-\d{2}", timestamp) else datetime.now(timezone.utc).strftime("%Y-%m-%d")
            log_dir = SESSION_LOGS_DIR / day
            log_dir.mkdir(parents=True, exist_ok=True)
            log_path = log_dir / f"{analysis_id}.json"
            session = {
                "analysis_id": analysis_id,
                "timestamp": timestamp,
                "inputs": {
                    "grain_image_name": image_name,
                    "grain_image_path": self._relative_path(image_path),
                    "moisture_image_name": moisture_image_name,
                    "moisture_image_path": self._relative_path(moisture_image_path),
                    "crop_type": crop_type,
                    "crop_variety": crop_variety,
                },
                "moisture_ocr": moisture_reading,
                "physics_proxies": proxies,
                "api_result": payload,
                "pipeline_audit": self._redact_for_log(getattr(self.pipeline, "last_grading_audit", {})),
                "correction": None,
            }
            log_path.write_text(
                json.dumps(self._redact_for_log(session), ensure_ascii=False, indent=2, default=str),
                encoding="utf-8",
            )
            return self._relative_path(str(log_path)) or str(log_path)
        except Exception as exc:
            return f"log_write_failed: {exc}"

    def _attach_feedback_to_session_log(
        self,
        record: AnalysisRecord,
        feedback_path: Optional[str],
        training_export_saved: bool,
        true_grade: str,
        true_grain_grade: Optional[str],
        true_moisture_risk: str,
        notes: str,
    ) -> None:
        if not record.session_log_path or record.session_log_path.startswith("log_write_failed:"):
            return
        try:
            log_path = PROJECT_ROOT / record.session_log_path
            payload = json.loads(log_path.read_text(encoding="utf-8"))
            payload["correction"] = {
                "true_grade": true_grade,
                "true_grain_grade": true_grain_grade or true_grade,
                "true_moisture_risk": true_moisture_risk,
                "notes": notes,
                "feedback_path": self._relative_path(feedback_path),
                "training_export_saved": training_export_saved,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            log_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
        except Exception:
            return

    def health(self) -> Dict[str, Any]:
        return {
            "status": "ok",
            "runtime": runtime_status(),
            "pending_feedback": self.feedback_collector.get_pending_count(),
        }

    def crop_catalog(self) -> Dict[str, Any]:
        crops: List[Dict[str, Any]] = []
        for crop_value, folder_name in CROP_FOLDER_BY_VALUE.items():
            variety_dir = CROP_KNOWLEDGE_DIR / folder_name / "Variety"
            seen: Dict[str, Dict[str, Any]] = {}
            if variety_dir.exists():
                for path in sorted(variety_dir.iterdir(), key=lambda item: item.name.lower()):
                    if not path.is_file():
                        continue
                    label = _display_label_from_name(path.name)
                    seen[_variety_value(label)] = {
                        "value": _variety_value(label),
                        "label": label,
                        "source_file": str(path.relative_to(PROJECT_ROOT)),
                    }
            for label in _supported_varieties_from_rule_file(_rule_file_for_crop(crop_value)):
                value = _variety_value(label)
                seen.setdefault(
                    value,
                    {
                        "value": value,
                        "label": label,
                        "source_file": None,
                    },
                )

            crops.append(
                {
                    "value": crop_value,
                    "label": CROP_LABELS[crop_value],
                    "aliases": CROP_ALIASES[crop_value],
                    "varieties": list(seen.values()),
                    "rule_summary": self.rule_engine.describe_crop_rules(crop_value),
                }
            )
        return {"crops": crops}

    async def save_upload(self, upload: UploadFile, purpose: str = "api") -> str:
        content_type = (upload.content_type or "").lower()
        if content_type not in {"image/jpeg", "image/png", "image/jpg"}:
            raise HTTPException(status_code=415, detail="Upload must be a JPG or PNG image.")

        raw = await upload.read()
        if not raw:
            raise HTTPException(status_code=400, detail="Uploaded image is empty.")

        try:
            image = ImageOps.exif_transpose(Image.open(BytesIO(raw))).convert("RGB")
            image.verify()
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Uploaded file is not a readable image.") from exc

        suffix = Path(upload.filename or "sample.jpg").suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png"}:
            suffix = ".jpg"
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        safe_purpose = re.sub(r"[^a-zA-Z0-9_-]+", "_", purpose).strip("_") or "api"
        saved_path = SESSION_UPLOADS_DIR / f"{safe_purpose}_{stamp}_{uuid.uuid4().hex[:8]}{suffix}"
        saved_path.write_bytes(raw)
        return str(saved_path)

    def extract_moisture_reading(
        self,
        moisture_image_path: Optional[str],
        manual_moisture_percent: Optional[float] = None,
    ) -> Dict[str, Any]:
        if manual_moisture_percent is not None:
            percent = self._validate_moisture_percent(manual_moisture_percent)
            return {
                "percent": percent,
                "source": "manual_override",
                "confidence": 1.0,
                "raw_text": "",
                "display_text": f"{percent:.2f}%",
            }
        if not moisture_image_path:
            raise HTTPException(
                status_code=422,
                detail="Upload a moisture meter image or provide manual_moisture_percent.",
            )

        prompt = """Read the digital grain moisture meter display.
Return ONLY one JSON object:
{
  "moisture_percent": number,
  "confidence": 0.0-1.0,
  "raw_text": "exact visible display text",
  "unit": "%"
}
Rules:
- Extract the measured moisture percentage from the meter screen.
- The display may say MEMORY FULL and then a commodity line such as MILLET % 08.8 or RICE-5Grn % 09.8.
- Preserve the decimal point from the LCD reading. If the visible reading is 08.8, return 8.8, not 88.
- Do not infer from the grain image.
- If no numeric moisture percentage is visible, return moisture_percent:null and confidence:0.
"""
        try:
            ocr_image_path = _crop_meter_display_image(moisture_image_path)
            response = self.pipeline._call_qwen_vision(
                ocr_image_path,
                prompt,
                max_tokens=140,
            )
            parsed = self.pipeline._parse_json_response(response)
        except Exception as exc:
            raise HTTPException(status_code=422, detail=f"Moisture meter OCR failed: {exc}") from exc

        raw_text = ""
        percent_value = None
        if isinstance(parsed, dict):
            raw_text = str(parsed.get("raw_text") or parsed.get("display_text") or "").strip()
            percent_value = (
                parsed.get("moisture_percent")
                or parsed.get("moisture")
                or parsed.get("percent")
                or parsed.get("reading")
            )
        text_percent = _extract_percent_from_text(raw_text or str(response))
        if text_percent is not None:
            percent_value = text_percent
        elif percent_value is not None:
            normalized = _normalize_moisture_candidate(_coerce_float(percent_value, -1.0))
            percent_value = normalized if normalized is not None else text_percent
        if percent_value is None:
            percent_value = _extract_percent_from_text(str(response))
        if percent_value is None:
            raise HTTPException(
                status_code=422,
                detail="Moisture meter OCR could not find a numeric moisture percentage.",
            )

        percent = self._validate_moisture_percent(percent_value)
        confidence = 0.0
        if isinstance(parsed, dict):
            confidence = _coerce_float(parsed.get("confidence"), 0.0)
        return {
            "percent": percent,
            "source": (
                "moisture_meter_ocr_display_crop"
                if "ocr_image_path" in locals() and ocr_image_path != moisture_image_path
                else "moisture_meter_ocr"
            ),
            "confidence": round(max(0.0, min(1.0, confidence)), 3),
            "raw_text": raw_text,
            "display_text": raw_text or f"{percent:.2f}%",
        }

    def _validate_moisture_percent(self, value: Any) -> float:
        percent = _coerce_float(value, -1.0)
        if percent <= 0.0 or percent > 50.0:
            raise HTTPException(status_code=422, detail="Moisture percent must be between 0 and 50.")
        return round(percent, 2)

    def analyze(
        self,
        image_path: str,
        image_name: str,
        crop_type: Optional[str],
        crop_variety: Optional[str],
        moisture_image_path: Optional[str],
        moisture_image_name: Optional[str],
        moisture_reading: Dict[str, Any],
        confidence_threshold: int,
        analysis_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        status = runtime_status()
        if not status["model_ready"]:
            raise HTTPException(status_code=503, detail=status["runtime_detail"])

        proxies = self.extractor.extract_all_proxies(image_path)
        crop_hint = None if not crop_type or crop_type.upper() == "AUTO" else crop_type
        normalized_crop = normalize_crop_name(crop_hint)
        variety = crop_variety.strip() if crop_variety else ""
        measured_moisture_percent = moisture_reading.get("percent")
        grading_result = self.pipeline.infer(
            image_path,
            proxies,
            crop_hint,
            crop_variety=variety or None,
            measured_moisture_percent=measured_moisture_percent,
            moisture_source=moisture_reading.get("source", "moisture_meter_ocr"),
            moisture_ocr_confidence=moisture_reading.get("confidence"),
        )
        payload = self.pipeline.format_result_for_api(grading_result)
        analysis_id = analysis_id or uuid.uuid4().hex
        payload.update(
            {
                "analysis_id": analysis_id,
                "image_name": image_name,
                "grain_image_name": image_name,
                "moisture_image_name": moisture_image_name,
                "proxy_summary": proxy_summary(proxies),
                "manual_review_required": bool(
                    grading_result.manual_review_required
                    or grading_result.overall_confidence < confidence_threshold
                ),
                "operator_summary": grading_result.operator_summary,
                "signal_highlights": grading_result.signal_highlights,
            }
        )
        payload["selection"]["requested_crop"] = normalized_crop or crop_hint
        payload["selection"]["requested_variety"] = variety or None
        payload["moisture"]["meter_reading"] = moisture_reading
        session_log_path = self._write_session_log(
            analysis_id=analysis_id,
            image_path=image_path,
            image_name=image_name,
            moisture_image_path=moisture_image_path,
            moisture_image_name=moisture_image_name,
            crop_type=normalized_crop or crop_hint,
            crop_variety=variety or None,
            moisture_reading=moisture_reading,
            proxies=proxies,
            payload=payload,
        )
        payload["audit"]["session_log_id"] = analysis_id
        payload["audit"]["session_log_path"] = session_log_path
        if session_log_path and not session_log_path.startswith("log_write_failed:"):
            # Re-write once so the file contains its own public audit pointer.
            self._write_session_log(
                analysis_id=analysis_id,
                image_path=image_path,
                image_name=image_name,
                moisture_image_path=moisture_image_path,
                moisture_image_name=moisture_image_name,
                crop_type=normalized_crop or crop_hint,
                crop_variety=variety or None,
                moisture_reading=moisture_reading,
                proxies=proxies,
                payload=payload,
            )
        with self._lock:
            self.analyses[analysis_id] = AnalysisRecord(
                analysis_id=analysis_id,
                image_path=image_path,
                image_name=image_name,
                moisture_image_path=moisture_image_path,
                moisture_image_name=moisture_image_name,
                crop_variety=variety or None,
                measured_moisture_percent=measured_moisture_percent,
                moisture_reading=moisture_reading,
                proxies=proxies,
                result=grading_result,
                payload=payload,
                session_log_path=session_log_path,
            )
        return payload

    def submit_feedback(
        self,
        analysis_id: str,
        true_grade: str,
        true_moisture_risk: str,
        notes: str = "",
        true_grain_grade: Optional[str] = None,
    ) -> Dict[str, Any]:
        with self._lock:
            record = self.analyses.get(analysis_id)
        if record is None:
            raise HTTPException(status_code=404, detail="Analysis not found. Run analysis again before submitting feedback.")

        result = record.result
        item = GradingFeedbackItem(
            sample_id=analysis_id,
            image_path=record.image_path,
            farm_id="API",
            batch_id=f"API-{analysis_id[:10]}",
            predicted_grade=result.quality_grade.value,
            true_grade=true_grade,
            predicted_moisture_risk=result.moisture_risk.value,
            true_moisture_risk=true_moisture_risk,
            image_features=record.proxies,
            confidence=float(result.overall_confidence),
            timestamp=result.timestamp,
            device_model="Web",
            notes=notes,
            selected_crop=result.selected_crop or "",
            selected_variety=result.selected_variety or record.crop_variety or "",
            selected_crop_confidence=float(result.selected_crop_confidence or 0.0),
            selection_source=result.selection_source or "",
            true_grain_grade=true_grain_grade or true_grade,
            session_log_path=record.session_log_path or "",
            score_breakdown=result.score_breakdown,
            meter_moisture_percent=record.measured_moisture_percent,
            applied_rules=result.applied_rules,
        )
        saved = self.feedback_collector.submit_feedback(item)
        feedback_path = (
            str(self.feedback_collector.last_saved_path)
            if self.feedback_collector.last_saved_path
            else None
        )
        training_export_saved = False
        if saved:
            training_export_saved = self.feedback_collector.append_training_export(
                item,
                FEEDBACK_TRAINING_EXPORT_PATH,
            )
            record.feedback_path = feedback_path
            self._attach_feedback_to_session_log(
                record,
                feedback_path=feedback_path,
                training_export_saved=training_export_saved,
                true_grade=true_grade,
                true_grain_grade=true_grain_grade,
                true_moisture_risk=true_moisture_risk,
                notes=notes,
            )
        return {
            "saved": saved,
            "pending_count": self.feedback_collector.get_pending_count(),
            "analysis_id": analysis_id,
            "feedback_path": self._relative_path(feedback_path),
            "training_export_saved": training_export_saved,
            "session_log_path": record.session_log_path,
        }


def proxy_summary(proxies: Dict[str, Any]) -> Dict[str, Any]:
    lab = proxies.get("lab_features", {}) or {}
    clumping = proxies.get("clumping", {}) or {}
    calibration = proxies.get("calibration", {}) or {}
    return {
        "texture_entropy": proxies.get("texture_entropy"),
        "roughness_score": proxies.get("roughness_score"),
        "grain_mask_coverage": proxies.get("grain_mask_coverage"),
        "uniformity_score": proxies.get("uniformity_score"),
        "darkness_index": lab.get("color_darkness_index"),
        "clumping_density": clumping.get("density"),
        "capture_distance_estimate_cm": proxies.get("capture_distance_estimate_cm"),
        "calibration_source": calibration.get("source"),
    }


_services: Optional[AppServices] = None
_services_lock = threading.Lock()


def get_services() -> AppServices:
    global _services
    if _services is None:
        with _services_lock:
            if _services is None:
                _services = AppServices()
    return _services
