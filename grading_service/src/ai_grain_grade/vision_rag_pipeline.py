"""
Vision-RAG Pipeline for Ragi Quality Grading
==============================================

Two-pass inference engine:
  Pass 1: Safety-Gate Detection (Bounding boxes for hazards: mold, stones, insects)
  Pass 2: RAG-Guided Grading (Retrieve relevant BIS rules, output deterministic Grade)

Integrates:
  - Vector DB (Supabase/Pinecone) with .md grading rules
  - Qwen3-VL/Qwen-VL cloud OpenAI-compatible API for vision understanding
  - Local RAG chunking and retrieval over authoritative rules
  - Deterministic grading logic based on UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md

Author: Copilot
Date: 2026-04-29
"""

import os
import json
import asyncio
import logging
import inspect
from typing import Dict, List, Tuple, Any, Optional, Callable
from dataclasses import dataclass, field
from enum import Enum
import httpx
import numpy as np
from datetime import datetime, timezone
from pathlib import Path
from pathlib import PurePosixPath
from PIL import Image

# Our modules
from .paths import FEEDBACK_DIR, RAG_INDEX_PATH
from .rag_engine import RAGEngine
from .moisture_calibration import MoistureCalibrator
from .feedback import FeedbackCollector
from .rule_engine import CropRuleEngine, normalize_crop_name

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return str(raw).strip().lower() in {"1", "true", "yes", "on"}


def _env_csv(name: str, default: Tuple[str, ...]) -> List[str]:
    raw = os.getenv(name)
    if raw is None:
        return list(default)
    return [item.strip() for item in raw.split(",") if item.strip()]


def _first_env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default


LEGACY_SILICONFLOW_MODEL = "Qwen/Qwen2.5-VL-7B-Instruct"
DEFAULT_DASHSCOPE_MODEL = "qwen3-vl-plus"
DEFAULT_DASHSCOPE_FALLBACK_MODELS = ("qwen3-vl-flash", "qwen-vl-plus")
DEFAULT_DASHSCOPE_BASE_URL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
DEFAULT_SILICONFLOW_BASE_URL = "https://api.siliconflow.cn/v1"
CLOUD_QWEN_PROVIDERS = {"dashscope", "siliconflow", "custom"}


class QualityGrade(str, Enum):
    """Canonical three-tier quality grading."""
    A = "A"
    B = "B"
    C = "C"


class MoistureRisk(str, Enum):
    """Moisture risk classification."""
    LOW = "LOW"
    MODERATE = "MODERATE"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


@dataclass
class SafetyGateFinding:
    """Result of Pass 1: Safety Gate Detection."""
    hazard_detected: bool
    hazard_type: Optional[str]  # mold, stone, insect, webbing, foreign_matter
    confidence: float
    bounding_boxes: List[Dict[str, float]]  # {x, y, w, h} in normalized coords


@dataclass
class GradingResult:
    """Final grading output from Pass 2."""
    quality_grade: QualityGrade
    quality_score: int  # 0-100
    reject_recommended: bool
    reject_reasons: List[str]
    
    # Quality breakdown
    broken_grain_percent: float
    foreign_matter_percent: float
    uniformity_score: float
    mold_visible: bool
    
    # Moisture
    moisture_risk: MoistureRisk
    moisture_estimate_calibrated: bool
    moisture_percent_estimate: Optional[float]
    
    # Confidence
    overall_confidence: int  # 0-100
    pass1_confidence: int
    pass2_confidence: int
    
    # Audit metadata
    timestamp: str
    model_version: str
    rag_chunks_used: int
    grain_quality_grade: QualityGrade = QualityGrade.B
    grain_quality_score: int = 75
    moisture_quality_score: int = 100
    score_breakdown: Dict[str, Any] = field(default_factory=dict)
    selected_crop: Optional[str] = None
    selected_variety: Optional[str] = None
    selected_crop_confidence: float = 0.0
    selection_source: str = "default"
    applied_rules: List[Dict[str, Any]] = field(default_factory=list)
    route_label: str = "default"
    route_provider: Optional[str] = None
    route_model: Optional[str] = None
    route_base_url: Optional[str] = None
    route_fallback_used: bool = False
    route_attempts: List[str] = field(default_factory=list)
    route_error: Optional[str] = None
    operator_summary: str = ""
    manual_review_required: bool = False
    signal_highlights: List[str] = field(default_factory=list)
    measured_moisture_percent: Optional[float] = None
    moisture_source: str = "grain_proxy"
    moisture_ocr_confidence: Optional[float] = None


class VisionRAGPipeline:
    """
    End-to-end Vision + RAG pipeline for deterministic ragi grading.
    """

    def __init__(
        self,
        siliconflow_api_key: str = "",
        qwen_model: str = LEGACY_SILICONFLOW_MODEL,
        vector_db_type: str = "local",
        vector_db_url: Optional[str] = None,
        vector_db_key: Optional[str] = None,
        feedback_storage_path: Optional[str] = None,
        rag_retrieval_mode: str = "lexical",
        qwen_provider: Optional[str] = None,
        qwen_base_url: Optional[str] = None,
        qwen_api_key: Optional[str] = None,
        qwen_timeout_seconds: Optional[float] = None,
        crop_model_routes: Optional[Dict[str, Any]] = None,
        crop_model_routes_path: Optional[str] = None,
    ):
        """
        Args:
            siliconflow_api_key: Backward-compatible API key for SiliconFlow inference
            qwen_model: Model identifier
            vector_db_type: 'supabase', 'pinecone', or 'local' (JSON fallback)
            rag_retrieval_mode: 'lexical' for the lightweight local scorer.
            qwen_provider: 'dashscope', 'siliconflow', or 'custom'.
            qwen_base_url: OpenAI-compatible base URL for cloud providers.
            qwen_api_key: Cloud provider API key. Falls back to env vars.
            qwen_timeout_seconds: HTTP timeout for non-streaming cloud calls.
        """
        provider = (qwen_provider or os.getenv("QWEN_VL_PROVIDER") or "").strip().lower()
        if not provider:
            provider = "dashscope"
        if provider not in CLOUD_QWEN_PROVIDERS:
            logger.warning("Unknown Qwen provider %r; using custom OpenAI-compatible mode", provider)
            provider = "custom"

        env_model = os.getenv("QWEN_VL_MODEL")
        if env_model:
            qwen_model = env_model
        elif provider == "dashscope" and qwen_model == LEGACY_SILICONFLOW_MODEL:
            qwen_model = DEFAULT_DASHSCOPE_MODEL

        self.qwen_provider = provider
        self.qwen_model = qwen_model
        self.vector_db_type = vector_db_type
        self.vector_db_url = vector_db_url
        self.vector_db_key = vector_db_key
        self._last_message_meta: Dict[str, Any] = {}
        self._last_image_payload_meta: Dict[str, Any] = {}

        if provider == "dashscope":
            self.qwen_base_url = (
                qwen_base_url
                or _first_env(
                    "QWEN_VL_BASE_URL",
                    "DASHSCOPE_BASE_URL",
                    default=DEFAULT_DASHSCOPE_BASE_URL,
                )
            )
            self.qwen_api_key = (
                qwen_api_key
                or _first_env("QWEN_VL_API_KEY", "DASHSCOPE_API_KEY")
            )
        elif provider == "siliconflow":
            self.qwen_base_url = (
                qwen_base_url
                or _first_env(
                    "QWEN_VL_BASE_URL",
                    "SILICONFLOW_BASE_URL",
                    default=DEFAULT_SILICONFLOW_BASE_URL,
                )
            )
            self.qwen_api_key = (
                qwen_api_key
                or siliconflow_api_key
                or _first_env("QWEN_VL_API_KEY", "SILICONFLOW_API_KEY")
            )
        else:
            self.qwen_base_url = qwen_base_url or os.getenv("QWEN_VL_BASE_URL", "")
            self.qwen_api_key = qwen_api_key or os.getenv("QWEN_VL_API_KEY", "")

        self.qwen_timeout_seconds = float(
            qwen_timeout_seconds
            if qwen_timeout_seconds is not None
            else _env_float("QWEN_VL_TIMEOUT_SECONDS", 75.0)
        )
        self.qwen_enable_thinking = _env_bool("QWEN_VL_ENABLE_THINKING", False)
        self.qwen_fallback_models = _env_csv(
            "QWEN_VL_FALLBACK_MODELS",
            DEFAULT_DASHSCOPE_FALLBACK_MODELS,
        )
        self.siliconflow_key = self.qwen_api_key
        self.siliconflow_endpoint = (
            self.qwen_base_url if provider == "siliconflow" else DEFAULT_SILICONFLOW_BASE_URL
        )
        self._last_route_meta: Dict[str, Any] = {}
        self._default_route_label = "default"
        self.last_grading_audit: Dict[str, Any] = {}

        # Initialize Moisture Calibrator
        self.moisture_calibrator = MoistureCalibrator()
        self.rule_engine = CropRuleEngine()

        # Initialize RAG Engine
        self.rag_engine = RAGEngine(
            index_path=str(RAG_INDEX_PATH),
            retrieval_mode=rag_retrieval_mode,
        )
        self.feedback_collector = FeedbackCollector(
            storage_path=str(feedback_storage_path or FEEDBACK_DIR)
        )
        self.default_crop_hint = self._normalize_crop_hint(
            _first_env("DEFAULT_CROP_HINT", "ragi")
        )
        self.crop_model_routes = self._load_crop_model_routes(
            crop_model_routes,
            crop_model_routes_path,
        )
        
        # Initial indexing if empty or outdated
        if not self.rag_engine.chunks or self.rag_engine.needs_rebuild():
            self._init_rag_knowledge_base()

        if self.crop_model_routes:
            logger.info(
                "Vision-RAG Pipeline initialized (%s/%s) with %d crop-specific route(s)",
                self.qwen_provider,
                self.qwen_model,
                len(self.crop_model_routes),
            )
        else:
            logger.info(
                "Initialized Vision-RAG Pipeline (%s/%s)",
                self.qwen_provider,
                self.qwen_model,
            )

    def _init_rag_knowledge_base(self):
        """Load grading and moisture rules from the repository Markdown corpus."""
        self.rag_engine.index_documents()
        logger.info(
            "RAG knowledge base indexed with %d chunks",
            len(self.rag_engine.chunks),
        )

    def warm_up_retrieval(self):
        """Warm the local lexical rule retriever before the user starts analysis."""
        try:
            self.rag_engine.retrieve(
                "FAO BIS ragi moisture foreign matter damaged grains thresholds",
                k=1,
            )
        except Exception as e:
            logger.warning("RAG warm-up skipped: %s", e)

    def _provider_label(self) -> str:
        return f"{self.qwen_provider}/{self.qwen_model}"

    def _load_crop_model_routes(
        self,
        routes: Optional[Dict[str, Any]],
        routes_path: Optional[str],
    ) -> Dict[str, Dict[str, str]]:
        """Load optional crop->route overrides for serving and training migration."""
        normalized: Dict[str, Dict[str, str]] = {}

        if routes is not None:
            route_payload = routes
        else:
            route_payload = {}
            if routes_path:
                try:
                    route_path = Path(routes_path)
                    if route_path.exists():
                        with route_path.open("r", encoding="utf-8") as handle:
                            route_payload = json.load(handle) or {}
                    else:
                        logger.warning("Crop route file not found: %s", routes_path)
                except Exception as exc:
                    logger.warning("Failed to load crop route map %s: %s", routes_path, exc)

        if not isinstance(route_payload, dict):
            logger.warning("Ignoring invalid crop route payload; expected JSON object.")
            return {}

        for crop_name, route_raw in route_payload.items():
            normalized_crop = self._normalize_crop_hint(crop_name)
            if not normalized_crop:
                continue

            if isinstance(route_raw, str):
                model = route_raw.strip()
                if model:
                    normalized[normalized_crop] = {"model": model}
                continue

            if not isinstance(route_raw, dict):
                continue
            model = str(route_raw.get("model", "")).strip()
            if not model:
                continue

            normalized_route: Dict[str, str] = {"model": model}
            base_url = str(route_raw.get("base_url", route_raw.get("endpoint", ""))).strip()
            api_key = str(route_raw.get("api_key", route_raw.get("token", ""))).strip()
            provider = str(route_raw.get("provider", self.qwen_provider)).strip().lower()
            if base_url:
                normalized_route["base_url"] = base_url
            if api_key:
                normalized_route["api_key"] = api_key
            if provider:
                normalized_route["provider"] = provider
            normalized[normalized_crop] = normalized_route

        return normalized

    def _resolve_crop_route(self, crop_name: Optional[str]) -> Optional[Dict[str, str]]:
        """Resolve crop-aware route override for Qwen calls."""
        if not crop_name:
            return None
        normalized = self._normalize_crop_hint(crop_name)
        if not normalized:
            return None
        return self.crop_model_routes.get(normalized)

    def _crop_prompt_context(self, crop_type: Optional[str]) -> Dict[str, str]:
        """Return crop-aware language snippets for prompt builders."""
        normalized = self._normalize_crop_hint(crop_type)
        if normalized == "finger_millets":
            return {
                "crop_label": "finger millet",
                "crop_display": "Finger Millets",
                "safety_name": "finger millet",
                "safety_crop_label": "finger millet (ragi)",
                "ruleset_hint": "finger millet",
            }
        if normalized == "bajra":
            return {
                "crop_label": "bajra",
                "crop_display": "Bajra",
                "safety_name": "bajra",
                "safety_crop_label": "bajra",
                "ruleset_hint": "bajra",
            }
        if normalized == "rice":
            return {
                "crop_label": "rice",
                "crop_display": "Rice",
                "safety_name": "rice",
                "safety_crop_label": "rice",
                "ruleset_hint": "rice",
            }
        if normalized:
            return {
                "crop_label": normalized,
                "crop_display": normalized.title(),
                "safety_name": normalized,
                "safety_crop_label": normalized,
                "ruleset_hint": normalized,
            }
        return {
            "crop_label": "grain",
            "crop_display": "Grain",
            "safety_name": "grain",
            "safety_crop_label": "general grain",
            "ruleset_hint": "grain",
        }

    def _crop_rule_summary(self, crop_type: Optional[str]) -> str:
        """Return compact crop YAML thresholds for prompt grounding."""
        lines = self.rule_engine.describe_crop_rules(crop_type)
        if not lines:
            return "- No crop-specific YAML thresholds found; use retrieved rule anchors."
        return "\n".join(f"- {line}" for line in lines)

    def _resolve_crop_selection(
        self,
        crop_hint: Optional[str],
        physics_proxies: Optional[Dict[str, Any]] = None,
    ) -> Tuple[Optional[str], float, str]:
        """Resolve explicit crop choice, detected crop, or fallback default."""
        if crop_hint:
            normalized = self._normalize_crop_hint(crop_hint)
            if normalized:
                return normalized, 1.0, "manual"

        detected_crop: Optional[str] = None
        if isinstance(physics_proxies, dict):
            detected_crop = (
                self._normalize_crop_hint(physics_proxies.get("crop_type"))
                or self._normalize_crop_hint(physics_proxies.get("detected_crop"))
                or self._normalize_crop_hint(physics_proxies.get("crop_hint"))
            )
        if detected_crop:
            return detected_crop, 0.88, "detected"

        return self.default_crop_hint, 0.45, "default"

    def _with_operator_context(
        self,
        physics_proxies: Dict[str, Any],
        selected_crop: Optional[str],
        crop_variety: Optional[str],
        measured_moisture_percent: Optional[float],
        moisture_source: str,
        moisture_ocr_confidence: Optional[float],
    ) -> Dict[str, Any]:
        """Attach operator-selected crop/variety and machine moisture to the audit context."""
        enriched = dict(physics_proxies or {})
        if selected_crop:
            enriched["crop_type"] = selected_crop
        if crop_variety:
            enriched["crop_variety"] = crop_variety
        if measured_moisture_percent is not None:
            enriched["machine_moisture"] = {
                "percent": float(measured_moisture_percent),
                "source": moisture_source,
                "ocr_confidence": moisture_ocr_confidence,
            }
        return enriched

    def _risk_from_measured_moisture(
        self,
        moisture_percent: float,
        crop_type: Optional[str],
    ) -> MoistureRisk:
        """Classify machine moisture against the selected crop's A/B/C thresholds."""
        grade_a_max, grade_b_max, grade_c_max = self.rule_engine.moisture_thresholds(crop_type)
        if moisture_percent <= grade_a_max:
            return MoistureRisk.LOW
        if moisture_percent <= grade_b_max:
            return MoistureRisk.MODERATE
        if moisture_percent <= grade_c_max:
            return MoistureRisk.HIGH
        return MoistureRisk.CRITICAL

    def _resolve_moisture_measurement(
        self,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str],
        measured_moisture_percent: Optional[float] = None,
    ) -> Tuple[MoistureRisk, float, bool]:
        """Use meter moisture when available; otherwise fall back to grain-photo proxies."""
        machine_moisture = physics_proxies.get("machine_moisture") or {}
        resolved = (
            measured_moisture_percent
            if measured_moisture_percent is not None
            else machine_moisture.get("percent")
        )
        if resolved is not None:
            percent = float(resolved)
            return self._risk_from_measured_moisture(percent, crop_type), percent, True
        return self._estimate_moisture_risk(physics_proxies)

    def _chat_completions_endpoint(self, base_url: Optional[str] = None) -> str:
        base = (base_url or self.qwen_base_url or "").rstrip("/")
        if not base:
            raise ValueError("Qwen cloud base URL is not configured")
        if base.endswith("/chat/completions"):
            return base
        return f"{base}/chat/completions"

    def _cloud_headers(self, api_key: Optional[str] = None) -> Dict[str, str]:
        headers = {"Content-Type": "application/json"}
        resolved_key = api_key if api_key is not None else self.qwen_api_key
        if resolved_key:
            headers["Authorization"] = f"Bearer {resolved_key}"
        return headers

    def _extract_message_text(self, message: Dict[str, Any]) -> str:
        content = message.get("content", "")
        if isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(str(item.get("text", "")))
                elif isinstance(item, str):
                    text_parts.append(item)
            content = "\n".join(part for part in text_parts if part)
        if isinstance(content, str) and content.strip():
            return content
        return str(
            message.get("reasoning_content", "")
            or message.get("reasoning", "")
            or message.get("thinking", "")
        ).strip()

    def _openai_payload_options(
        self,
        payload: Dict[str, Any],
        provider: Optional[str] = None,
        model: Optional[str] = None,
    ) -> Dict[str, Any]:
        route_provider = (provider or self.qwen_provider or "").strip().lower()
        route_model = str(model or payload.get("model") or self.qwen_model or "").strip().lower()
        if route_provider in {"dashscope", "custom"}:
            payload["response_format"] = {"type": "json_object"}
            if route_provider == "dashscope" and self._model_supports_thinking_toggle(route_model):
                payload["enable_thinking"] = bool(self.qwen_enable_thinking)
        elif route_provider == "siliconflow":
            payload.update(
                {
                    "seed": 7,
                    "reasoning_effort": "none",
                    "reasoning": {"effort": "none"},
                }
            )
        return payload

    def _model_supports_thinking_toggle(self, model: str) -> bool:
        model_name = str(model or "").lower()
        return (
            model_name.startswith("qwen3-vl")
            or model_name.startswith("qwen3.")
            or model_name.startswith("qwen-plus")
            or model_name.startswith("qwen-max")
        )

    def _format_cloud_error(self, exc: Exception) -> str:
        if isinstance(exc, httpx.HTTPStatusError):
            status = exc.response.status_code
            body = (exc.response.text or "").strip()
            body = " ".join(body.split())
            if body:
                return f"HTTP {status}: {body[:500]}"
            return f"HTTP {status}: {exc.response.reason_phrase}"
        return str(exc)

    def _should_try_model_fallback(self, exc: Exception) -> bool:
        if not isinstance(exc, httpx.HTTPStatusError):
            return False
        if exc.response.status_code not in {400, 404, 422}:
            return False
        detail = (exc.response.text or str(exc)).lower()
        return "model" in detail and any(
            marker in detail
            for marker in (
                "not found",
                "not exist",
                "does not exist",
                "invalid",
                "unsupported",
                "not support",
            )
        )

    def _fallback_routes_for_model(
        self,
        provider: str,
        current_model: str,
        base_url: str,
        api_key: str,
    ) -> List[Tuple[Dict[str, str], str]]:
        if provider != "dashscope":
            return []
        seen = {str(current_model or "").strip().lower()}
        fallbacks: List[Tuple[Dict[str, str], str]] = []
        for model in self.qwen_fallback_models:
            normalized = str(model or "").strip()
            if not normalized or normalized.lower() in seen:
                continue
            seen.add(normalized.lower())
            fallbacks.append(
                (
                    {
                        "provider": provider,
                        "model": normalized,
                        "base_url": base_url,
                        "api_key": api_key,
                    },
                    "model fallback",
                )
            )
        return fallbacks

    def _resolve_route_signature(
        self,
        route: Optional[Dict[str, str]],
    ) -> Tuple[str, str, str, str]:
        provider = (
            str((route or {}).get("provider", self.qwen_provider) or self.qwen_provider)
            .strip()
            .lower()
        )
        if provider and provider not in CLOUD_QWEN_PROVIDERS:
            provider = "custom"
        model = str((route or {}).get("model", self.qwen_model) or self.qwen_model).strip()
        base_url = (
            str((route or {}).get("base_url", (route or {}).get("endpoint", self.qwen_base_url) or self.qwen_base_url) or "")
            .strip()
            .rstrip("/")
        )
        api_key = str((route or {}).get("api_key", (route or {}).get("token", self.qwen_api_key) or self.qwen_api_key)).strip()
        return provider or "custom", model, base_url, api_key

    def _route_signature(self, route: Optional[Dict[str, str]]) -> Tuple[str, str, str]:
        if not route:
            return (
                self.qwen_provider or "",
                self.qwen_model or "",
                (self.qwen_base_url or "").rstrip("/"),
            )
        provider, model, base_url, _api_key = self._resolve_route_signature(route)
        return provider, model, base_url

    def _rule_id_to_name(self, rule_id: str) -> str:
        if not rule_id:
            return "Inference rule"
        label = str(rule_id).replace("_", " ").replace("-", " ").strip()
        return " ".join(word.capitalize() for word in label.split())

    def _build_applied_rules(
        self,
        rule_hits: List[str],
        rag_context: List[Dict[str, Any]],
        base_confidence: float,
        default_confidence: Optional[float] = None,
        fallback_prefix: str = "RAG-inferred policy",
    ) -> List[Dict[str, Any]]:
        confidence = float(base_confidence if base_confidence is not None else 70.0)
        confidence = float(np.clip(confidence, 0.0, 100.0))
        normalized_hits = [str(hit).strip() for hit in rule_hits or [] if str(hit).strip()]
        if not normalized_hits and not rag_context:
            return [
                {
                    "rule_id": "no_rule_hit",
                    "rule_name": fallback_prefix,
                    "source_file": "vision-rag decision engine",
                    "evidence": (
                        "No matching rule identifier was returned; deterministic grading policy still applied."
                    ),
                    "rule_confidence": confidence,
                }
            ]

        applied: List[Dict[str, Any]] = []
        used: set[str] = set()
        context_lookup = rag_context or []

        for hit in normalized_hits[:6]:
            if hit in used:
                continue
            used.add(hit)
            source_file = ""
            evidence = ""
            hit_lc = hit.lower()
            for chunk in context_lookup:
                chunk_id = str(chunk.get("id", "")).lower()
                source = str(chunk.get("source", "")).lower()
                title = str(chunk.get("title", "")).lower()
                content = str(chunk.get("content", ""))
                if hit_lc in chunk_id or hit_lc in title or hit_lc in content.lower():
                    source_file = str(chunk.get("source", ""))
                    evidence = content[:220].strip().replace("\n", " ")
                    break

            if not source_file:
                for chunk in context_lookup:
                    source = str(chunk.get("source", ""))
                    if source:
                        source_file = source
                        evidence = (
                            "Referenced during evidence retrieval; "
                            "rule match did not include direct token signal."
                        )
                        break

            if not source_file:
                source_file = "rag rule context"
                evidence = (
                    f"Grade-level policy rule `{hit}` was selected after rule-engine interpretation."
                )

            filename = source_file
            try:
                filename = PurePosixPath(source_file).name
            except Exception:
                filename = source_file.split("/")[-1]

            applied.append(
                {
                    "rule_id": hit,
                    "rule_name": self._rule_id_to_name(hit),
                    "source_file": filename,
                    "evidence": evidence[:300] if evidence else hit,
                    "rule_confidence": confidence,
                }
            )

        if not applied and context_lookup:
            for chunk in context_lookup[:3]:
                source = str(chunk.get("source", ""))
                evidence = str(chunk.get("content", ""))
                filename = ""
                try:
                    filename = PurePosixPath(source).name
                except Exception:
                    filename = source.split("/")[-1]
                applied.append(
                    {
                        "rule_id": "policy_context",
                        "rule_name": "RAG policy context",
                        "source_file": filename or "rag_policy_context",
                        "evidence": evidence[:300],
                        "rule_confidence": confidence,
                    }
                )
                if len(applied) >= 3:
                    break
        return applied

    def infer(
        self,
        image_path: str,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str] = None,
        crop_variety: Optional[str] = None,
        measured_moisture_percent: Optional[float] = None,
        moisture_source: str = "grain_proxy",
        moisture_ocr_confidence: Optional[float] = None,
    ) -> GradingResult:
        """
        Two-pass inference pipeline.
        
        Args:
            image_path: Path to grain image
            physics_proxies: Dict from physics_proxies.extract_all_proxies()
            
        Returns:
            Complete GradingResult
        """
        timestamp = datetime.now(timezone.utc).isoformat()
        self.last_grading_audit = {}
        selected_crop, selected_crop_confidence, selection_source = self._resolve_crop_selection(
            crop_type,
            physics_proxies=physics_proxies,
        )
        physics_proxies = self._with_operator_context(
            physics_proxies,
            selected_crop=selected_crop,
            crop_variety=crop_variety,
            measured_moisture_percent=measured_moisture_percent,
            moisture_source=moisture_source,
            moisture_ocr_confidence=moisture_ocr_confidence,
        )
        crop_route = self._resolve_crop_route(selected_crop)

        # PASS 1: Safety Gate Detection
        logger.info("PASS 1: Safety Gate Detection...")
        safety_finding = self._pass1_safety_gate(
            image_path,
            crop_route=crop_route,
            crop_type=selected_crop,
        )

        if safety_finding.hazard_detected:
            logger.warning("Safety hazard detected: %s", safety_finding.hazard_type)
            if measured_moisture_percent is not None:
                safety_moisture_risk = self._risk_from_measured_moisture(
                    float(measured_moisture_percent),
                    selected_crop,
                )
                safety_moisture_percent = float(measured_moisture_percent)
                safety_moisture_calibrated = True
            else:
                safety_moisture_risk = MoistureRisk.CRITICAL
                safety_moisture_percent = None
                safety_moisture_calibrated = False
            safety_grain_score = 35
            safety_moisture_score = {
                MoistureRisk.LOW: 100,
                MoistureRisk.MODERATE: 82,
                MoistureRisk.HIGH: 65,
                MoistureRisk.CRITICAL: 35,
            }.get(safety_moisture_risk, 35)
            safety_final_score = int(
                max(20, min(74, min(safety_grain_score, safety_moisture_score) - 12))
            )
            safety_breakdown = {
                "grain_grade": "C",
                "grain_score": safety_grain_score,
                "moisture_score": safety_moisture_score,
                "final_score": safety_final_score,
                "metrics": {
                    "safety_gate": {
                        "value": safety_finding.hazard_type,
                        "grade": "REJECT",
                        "score": safety_grain_score,
                    }
                },
                "penalties": [
                    {
                        "name": "safety_hazard",
                        "points": 12,
                        "reason": f"Safety hazard detected: {safety_finding.hazard_type}",
                    }
                ],
                "rule_source": "pass1_safety_gate",
            }
            self.last_grading_audit = {
                "stage": "pass1_safety_gate",
                "safety_finding": {
                    "hazard_detected": safety_finding.hazard_detected,
                    "hazard_type": safety_finding.hazard_type,
                    "confidence": safety_finding.confidence,
                    "bounding_boxes": safety_finding.bounding_boxes,
                },
                "score_breakdown": safety_breakdown,
            }
            # Immediate Grade C + reject
            return GradingResult(
                quality_grade=QualityGrade.C,
                quality_score=safety_final_score,
                reject_recommended=True,
                reject_reasons=[f"Safety hazard detected: {safety_finding.hazard_type}"],
                broken_grain_percent=0.0,
                foreign_matter_percent=5.0,
                uniformity_score=30,
                mold_visible=(safety_finding.hazard_type == "mold"),
                moisture_risk=safety_moisture_risk,
                moisture_estimate_calibrated=safety_moisture_calibrated,
                moisture_percent_estimate=safety_moisture_percent,
                overall_confidence=int(safety_finding.confidence * 100),
                pass1_confidence=int(safety_finding.confidence * 100),
                pass2_confidence=0,
                timestamp=timestamp,
                model_version=f"{self.qwen_provider}/{self.qwen_model}",
                rag_chunks_used=0,
                grain_quality_grade=QualityGrade.C,
                grain_quality_score=safety_grain_score,
                moisture_quality_score=safety_moisture_score,
                score_breakdown=safety_breakdown,
                selected_crop=selected_crop,
                selected_variety=crop_variety or None,
                selected_crop_confidence=selected_crop_confidence,
                selection_source=selection_source,
                route_label="default",
                route_provider=self.qwen_provider,
                route_model=self.qwen_model,
                route_base_url=self.qwen_base_url,
                route_fallback_used=False,
                route_attempts=[],
                applied_rules=[
                    {
                        "rule_id": "safety_hazard",
                        "rule_name": "Safety hazard gate",
                        "source_file": "pass1_hazard_detection",
                        "evidence": f"Hazard detected: {safety_finding.hazard_type}",
                        "rule_confidence": min(100.0, max(0.0, safety_finding.confidence * 100.0)),
                    }
                ],
                operator_summary=f"Hold this lot. Safety gate flagged {safety_finding.hazard_type}.",
                manual_review_required=True,
                signal_highlights=[f"Safety gate detected {safety_finding.hazard_type}"],
                measured_moisture_percent=measured_moisture_percent,
                moisture_source=moisture_source,
                moisture_ocr_confidence=moisture_ocr_confidence,
            )

        # PASS 2: RAG-Guided Quality & Moisture Grading
        logger.info("PASS 2: RAG-Guided Grading...")
        grading_result = self._pass2_rag_grading(
            image_path,
            physics_proxies,
            timestamp,
            crop_type=selected_crop,
            selected_crop=selected_crop,
            selected_variety=crop_variety,
            selected_crop_confidence=selected_crop_confidence,
            selection_source=selection_source,
            crop_route=crop_route,
            measured_moisture_percent=measured_moisture_percent,
            moisture_source=moisture_source,
            moisture_ocr_confidence=moisture_ocr_confidence,
        )

        return grading_result

    def estimate_moisture_risk(
        self,
        physics_proxies: Dict[str, Any],
    ) -> Tuple[MoistureRisk, float, bool]:
        """Public read-only wrapper used by clients to render proxy results before VLM inference."""
        return self._estimate_moisture_risk(physics_proxies)

    async def infer_async(
        self,
        image_path: str,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str] = None,
        crop_variety: Optional[str] = None,
        measured_moisture_percent: Optional[float] = None,
        moisture_source: str = "grain_proxy",
        moisture_ocr_confidence: Optional[float] = None,
        stream_callback: Optional[Callable[[str], Any]] = None,
    ) -> GradingResult:
        """
        Async inference entrypoint for web clients.

        The cloud HTTP work is moved to a worker thread so the wrapper can remain async-friendly.
        """
        return await asyncio.to_thread(
            self.infer,
            image_path,
            physics_proxies,
            crop_type,
            crop_variety,
            measured_moisture_percent,
            moisture_source,
            moisture_ocr_confidence,
        )

    def _pass1_safety_gate(
        self,
        image_path: str,
        crop_route: Optional[Dict[str, str]] = None,
        crop_type: Optional[str] = None,
    ) -> SafetyGateFinding:
        """
        Pass 1: Vision-based hazard detection.
        Uses Qwen-VL to identify: mold, stones, insects, webbing, excessive foreign matter.
        """
        try:
            # Prepare prompt for safety detection
            crop_context = self._crop_prompt_context(crop_type)
            crop_label = crop_context["safety_name"]
            safety_prompt = f"""Analyze this {crop_label} grain sample image for safety hazards.

Specifically look for:
1. Mold or fungal growth (white/gray patches, webbing)
2. Visible stones or rocks
3. Insect damage or presence
4. Foreign matter (sticks, chaff, debris)
5. Excessive grain clumping (often linked to moisture and storage issues)

Respond in JSON format:
{{
  "hazard_found": true/false,
  "hazard_type": "none" | "mold" | "stone" | "insect" | "webbing" | "foreign_matter",
  "confidence": 0.0-1.0,
  "description": "Brief explanation",
  "bounding_boxes": [{{"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.2}}]
}}"""

            response = self._call_qwen_vision(
                image_path,
                safety_prompt,
                max_tokens=280,
                crop_route=crop_route,
            )
            response_json = self._parse_json_response(response)

            hazard_detected = response_json.get("hazard_found", False)
            hazard_type = response_json.get("hazard_type", "none")
            confidence = response_json.get("confidence", 0.5)
            bboxes = response_json.get("bounding_boxes", [])

            if hazard_type == "none":
                hazard_type = None

            return SafetyGateFinding(
                hazard_detected=hazard_detected,
                hazard_type=hazard_type,
                confidence=confidence,
                bounding_boxes=bboxes,
            )

        except Exception as e:
            logger.error(f"Pass 1 failed: {e}. Assuming safe (low confidence).")
            return SafetyGateFinding(
                hazard_detected=False,
                hazard_type=None,
                confidence=0.3,  # Low confidence fallback
                bounding_boxes=[],
            )

    def _pass2_rag_grading(
        self,
        image_path: str,
        physics_proxies: Dict[str, Any],
        timestamp: str,
        crop_type: Optional[str] = None,
        selected_crop: Optional[str] = None,
        selected_variety: Optional[str] = None,
        selected_crop_confidence: float = 0.0,
        selection_source: str = "default",
        crop_route: Optional[Dict[str, str]] = None,
        measured_moisture_percent: Optional[float] = None,
        moisture_source: str = "grain_proxy",
        moisture_ocr_confidence: Optional[float] = None,
    ) -> GradingResult:
        """
        Pass 2: RAG-guided quality and moisture grading.
        Retrieves relevant rules from vector DB, sends to Qwen-VL with context.
        """
        try:
            # 1. Retrieve relevant RAG chunks
            rag_context = self._retrieve_rag_context(
                physics_proxies,
                crop_type=crop_type,
                crop_variety=selected_variety,
            )
            feedback_context = self._retrieve_feedback_context(
                physics_proxies,
                crop_type=selected_crop,
            )

            # 2. Build comprehensive grading prompt
            grading_prompt = self._build_grading_prompt(
                physics_proxies,
                rag_context,
                feedback_context,
                selected_crop=selected_crop,
                selected_variety=selected_variety,
                measured_moisture_percent=measured_moisture_percent,
                moisture_source=moisture_source,
            )

            # 3. Call Qwen-VL with image and prompt
            response, route_meta = self._call_qwen_vision(
                image_path,
                grading_prompt,
                max_tokens=260,
                physics_proxies=physics_proxies,
                crop_route=crop_route,
                include_route_metadata=True,
            )
            repair_source = (
                str(self._last_message_meta.get("content") or "").strip()
                or str(self._last_message_meta.get("reasoning") or "").strip()
                or str(response).strip()
            )
            response_json = self._parse_json_response(response)
            if not response_json:
                response_json = self._repair_grading_json(
                    repair_source,
                    physics_proxies,
                    crop_route=route_meta.get("route"),
                )
                if not response_json:
                    response_json = self._extract_grading_hints_from_text(
                        repair_source, physics_proxies
                    )
            recovered_fields = self._recover_grading_fields_from_text(repair_source)
            response_json = self._merge_recovered_grading_fields(
                response_json,
                recovered_fields,
            )

            # 4. Resolve moisture from the machine reading when present, otherwise use image proxies.
            moisture_risk, moisture_percent, is_calib = self._resolve_moisture_measurement(
                physics_proxies,
                crop_type=selected_crop,
                measured_moisture_percent=measured_moisture_percent,
            )

            # 5. Parse response and apply deterministic threshold rules
            grade = self._apply_grading_logic(
                response_json,
                physics_proxies,
                moisture_risk=moisture_risk,
                moisture_percent=moisture_percent,
                moisture_calibrated=is_calib,
                crop_type=selected_crop,
            )

            # 6. Compute confidence score
            overall_conf = self._compute_confidence(
                response_json, physics_proxies, rag_context
            )
            model_confidence = float(response_json.get("model_confidence", 70))
            reject_reasons = list(grade["reject_reasons"])
            reject_recommended = bool(grade["reject"])
            route_failed = bool(route_meta.get("fallback_used") or route_meta.get("error"))
            if moisture_risk == MoistureRisk.CRITICAL:
                reject_recommended = True
                reject_reasons.append("Critical moisture risk; dry immediately before storage")
            applied_rules = self._build_applied_rules(
                grade.get("rule_hits", []),
                rag_context,
                base_confidence=model_confidence,
                fallback_prefix="RAG-inferred grading policy",
            )

            signal_highlights = self._summarize_signals(physics_proxies, moisture_risk)
            if route_failed:
                signal_highlights = list(
                    dict.fromkeys(
                        [
                            "Crop-specific model route failed or fell back; manual review required",
                            *signal_highlights,
                        ]
                    )
                )
                applied_rules.append(
                    {
                        "rule_id": "crop_route_manual_review",
                        "rule_name": "Crop route fallback review",
                        "source_file": "vision_rag_pipeline._call_qwen_vision",
                        "evidence": route_meta.get("error")
                        or "Crop-specific route fell back to the default Qwen route.",
                        "rule_confidence": 80.0,
                    }
                )
                overall_conf = max(0, overall_conf - 10)
            operator_summary = self._build_operator_summary(
                grade["grade"],
                moisture_risk,
                reject_recommended,
                overall_conf,
                reject_reasons,
            )
            manual_review_required = (
                reject_recommended
                or overall_conf < 65
                or moisture_risk in {MoistureRisk.HIGH, MoistureRisk.CRITICAL}
                or route_failed
            )
            self.last_grading_audit = {
                "stage": "pass2_rag_grading",
                "raw_model_response": response,
                "parsed_model_response": response_json,
                "route_meta": {
                    "route_label": route_meta.get("route_label", self._default_route_label),
                    "provider": route_meta.get("provider"),
                    "model": route_meta.get("model"),
                    "base_url": route_meta.get("base_url"),
                    "fallback_used": bool(route_meta.get("fallback_used")),
                    "attempted_routes": route_meta.get("attempted_routes") or [],
                    "error": route_meta.get("error"),
                },
                "rag_context": rag_context,
                "feedback_context": feedback_context,
                "rule_decision": grade,
                "moisture": {
                    "risk": moisture_risk.value,
                    "percent": moisture_percent,
                    "calibrated": is_calib,
                },
            }

            return GradingResult(
                quality_grade=grade["grade"],
                quality_score=grade["score"],
                reject_recommended=reject_recommended,
                reject_reasons=list(dict.fromkeys(reject_reasons)),
                broken_grain_percent=grade.get("broken_grain", 0.0),
                foreign_matter_percent=grade.get("foreign_matter", 0.0),
                uniformity_score=grade.get("uniformity", 70.0),
                mold_visible=grade.get("mold_visible", False),
                moisture_risk=moisture_risk,
                moisture_estimate_calibrated=is_calib,
                moisture_percent_estimate=moisture_percent,
                overall_confidence=overall_conf,
                pass1_confidence=100,  # Passed safety gate
                pass2_confidence=min(100, int(model_confidence)),
                timestamp=timestamp,
                model_version=(
                    f"{route_meta.get('provider', self.qwen_provider)}/"
                    f"{route_meta.get('model', self.qwen_model)}"
                ),
                rag_chunks_used=len(rag_context),
                grain_quality_grade=grade["grain_grade"],
                grain_quality_score=grade["grain_score"],
                moisture_quality_score=grade["moisture_score"],
                score_breakdown=grade["score_breakdown"],
                selected_crop=selected_crop,
                selected_variety=selected_variety or None,
                selected_crop_confidence=selected_crop_confidence,
                selection_source=selection_source,
                route_label=route_meta.get("route_label", self._default_route_label),
                route_provider=route_meta.get("provider"),
                route_model=route_meta.get("model"),
                route_base_url=route_meta.get("base_url"),
                route_fallback_used=bool(route_meta.get("fallback_used")),
                route_attempts=route_meta.get("attempted_routes") or [],
                route_error=route_meta.get("error"),
                applied_rules=applied_rules,
                operator_summary=operator_summary,
                manual_review_required=manual_review_required,
                signal_highlights=signal_highlights,
                measured_moisture_percent=measured_moisture_percent,
                moisture_source=moisture_source,
                moisture_ocr_confidence=moisture_ocr_confidence,
            )

        except Exception as e:
            logger.error(f"Pass 2 failed: {e}")
            # Fallback to conservative grading based on physics proxies alone
            return self._fallback_grading(
                physics_proxies,
                timestamp,
                selected_crop=selected_crop,
                selected_variety=selected_variety,
                selected_crop_confidence=selected_crop_confidence,
                selection_source=selection_source,
                route_meta=self._last_route_meta,
                measured_moisture_percent=measured_moisture_percent,
                moisture_source=moisture_source,
                moisture_ocr_confidence=moisture_ocr_confidence,
            )

    def _build_rag_query(
        self,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str] = None,
        crop_variety: Optional[str] = None,
    ) -> str:
        """Create a retrieval query that reflects the current sample signals."""
        query_parts = [
            "FAO BIS grain grading thresholds",
            "quality grade a b c decision matrix",
            "moisture foreign matter damaged grains procurement ranges",
            "biological hazard mold insect weevil foreign matter reject",
        ]

        clumping = physics_proxies.get("clumping", {}).get("density", 0.0)
        darkness = physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0)
        entropy = physics_proxies.get("texture_entropy", 0.0)
        uniformity = physics_proxies.get("uniformity_score", 0.0)
        roughness = physics_proxies.get("roughness_score", 0.0)
        physical = physics_proxies.get("physical_properties", {}) or {}

        if clumping > 0.18 or darkness > 48 or entropy < 3.0:
            query_parts.append("moisture risk clumping darkness calibration")
        if uniformity < 70:
            query_parts.append("bimodal color off-tone grade c")
        if roughness < 30:
            query_parts.append("storage dullness smooth surface downgrade")
        if physical.get("size_class") in {"small", "large", "mixed"}:
            query_parts.append("grain size variation broken shrivelled immature damaged grains")
        if physical.get("reflectiveness_class") in {"dull", "high_shine"}:
            query_parts.append("surface reflectance shine dullness moisture optical proxy")
        if physics_proxies.get("grain_mask_coverage", 0.0) < 0.15:
            query_parts.append("image validation reject retake low coverage")
        normalized_crop = self._normalize_crop_hint(crop_type)
        if normalized_crop:
            crop_context = self._crop_prompt_context(normalized_crop)
            query_parts.append(f"crop-specific grading for {crop_context['ruleset_hint']}")
        if crop_variety:
            query_parts.append(f"variety-specific grading context {crop_variety}")
        machine_moisture = (physics_proxies.get("machine_moisture") or {}).get("percent")
        if machine_moisture is not None:
            query_parts.append(f"machine measured moisture {machine_moisture}% grade thresholds")

        return " ".join(query_parts)

    def _normalize_crop_hint(self, crop_type: Optional[str]) -> Optional[str]:
        """Normalize optional crop labels for best-effort retrieval guidance."""
        return normalize_crop_name(crop_type) or None

    def _crop_source_aliases(self, crop_type: Optional[str]) -> set[str]:
        normalized = self._normalize_crop_hint(crop_type)
        if normalized == "finger_millets":
            return {"finger_millets", "fingermillets", "finger millet", "ragi", "nachani"}
        if normalized == "bajra":
            return {"bajra", "bajari", "bajri", "bajara", "pearl millet", "pearlmillet"}
        if normalized == "rice":
            return {"rice", "paddy", "dhan"}
        return {normalized} if normalized else set()

    def _retrieve_rag_context(
        self,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str] = None,
        crop_variety: Optional[str] = None,
        k: int = 4,
    ) -> List[Dict[str, Any]]:
        """Retrieve authoritative chunks relevant to the sample's proxy profile."""
        normalized_crop = self._normalize_crop_hint(crop_type)
        query = self._build_rag_query(
            physics_proxies,
            crop_type=normalized_crop,
            crop_variety=crop_variety,
        )
        candidates = self.rag_engine.retrieve(query, k=max(k, 8))
        if not normalized_crop:
            return candidates[:k]

        preferred: List[Dict[str, Any]] = []
        fallback: List[Dict[str, Any]] = []
        aliases = self._crop_source_aliases(normalized_crop)
        for chunk in candidates:
            source = str(chunk.get("source", "")).lower()
            source_compact = source.replace("_", "").replace("-", "").replace(" ", "")
            if "/crop_knowledge/" in source and any(
                alias.replace("_", "").replace("-", "").replace(" ", "") in source_compact
                for alias in aliases
            ):
                preferred.append(chunk)
            else:
                fallback.append(chunk)

        if preferred:
            return (preferred + fallback)[:k]
        return candidates[:k]

    def _retrieve_feedback_context(
        self,
        physics_proxies: Dict[str, Any],
        crop_type: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Fetch similar human corrections so feedback helps before the next retrain."""
        return self.feedback_collector.retrieve_similar_feedback(
            physics_proxies,
            limit=3,
            selected_crop=self._normalize_crop_hint(crop_type),
        )

    def _build_grading_prompt(
        self,
        physics_proxies: Dict[str, Any],
        rag_context: List[Dict[str, Any]],
        feedback_context: List[Dict[str, Any]],
        selected_crop: Optional[str] = None,
        selected_variety: Optional[str] = None,
        measured_moisture_percent: Optional[float] = None,
        moisture_source: str = "grain_proxy",
    ) -> str:
        """Build comprehensive grading prompt with physics context and RAG rules."""
        context_str = self._compress_rag_context(rag_context)
        feedback_str = self._feedback_examples_to_text(feedback_context)
        crop_context = self._crop_prompt_context(selected_crop)
        crop_name = crop_context["crop_display"]
        ruleset_hint = crop_context["ruleset_hint"]
        crop_rule_summary = self._crop_rule_summary(selected_crop)
        variety_line = (
            f"- Selected variety: {selected_variety}"
            if selected_variety
            else "- Selected variety: not specified"
        )
        if measured_moisture_percent is not None:
            moisture_line = (
                f"- Authoritative moisture meter reading: {measured_moisture_percent:.2f}% "
                f"(source={moisture_source}). Use this value for moisture thresholds."
            )
        else:
            moisture_line = (
                "- No moisture meter reading was supplied; use image moisture proxies only as an estimate."
            )

        prompt = f"""Grade this {crop_name} batch. Return ONLY one JSON object with no prose.

Rules:
- Apply FAO/BIS-aligned {ruleset_hint} thresholds from the retrieved rule anchors.
- Hazard, mold, insects, stones, deleterious material, or metrics beyond Grade C => Grade C/reject.
- Machine moisture reading and crop-specific defect thresholds override the image model.
- Grade A only if the lot is very uniform, clean, and physics signals are dry/stable.
- If the batch looks mixed, bimodal, or moisture-heavy, prefer Grade C.
- Grade B is only for usable commercial lots without strong hazard or moisture signals.
- Choose exactly one final grade from A, B, or C.
{variety_line}
{moisture_line}

Crop YAML thresholds:
{crop_rule_summary}

Rule anchors:
{context_str}

Similar corrections:
{feedback_str}

Signals:
- darkness_index={physics_proxies['lab_features']['color_darkness_index']:.1f}
- clumping_density={physics_proxies['clumping']['density']:.3f}
- uniformity_score={physics_proxies['uniformity_score']:.1f}
- texture_entropy={physics_proxies['texture_entropy']:.2f}
- roughness_score={physics_proxies['roughness_score']:.1f}
- mask_coverage={physics_proxies['grain_mask_coverage']:.2%}
- machine_moisture_percent={measured_moisture_percent if measured_moisture_percent is not None else "not supplied"}

JSON schema:
{{
  "quality_grade": "A|B|C",
  "quality_score": 0-100,
  "off_tone_fraction": 0-100,
  "size_deviation": 0-100,
  "shape_defect_fraction": 0-100,
  "broken_grain_percent": 0-100,
  "broken_grains_percent": 0-100,
  "damaged_grains_percent": 0-100,
  "chalky_grains_percent": 0-100,
  "foreign_matter_percent": 0-100,
  "organic_extraneous_matter_percent": 0-100,
  "inorganic_extraneous_matter_percent": 0-100,
  "other_edible_grains_percent": 0-100,
  "immature_grains_percent": 0-100,
  "weevilled_grains_percent": 0-100,
  "color_uniformity_score": 0-100,
  "size_uniformity_score": 0-100,
  "shape_uniformity_score": 0-100,
  "surface_defects_percent": 0-100,
  "measured_moisture_percent": number|null,
  "bimodal_color_detected": true,
  "mold_visible": false,
  "visible_defects": ["short labels"],
  "model_confidence": 0-100,
  "brief_reason": "one sentence"
}}"""

        return prompt

    def _feedback_examples_to_text(self, feedback_context: List[Dict[str, Any]]) -> str:
        if not feedback_context:
            return "- No similar corrected samples are available yet."

        lines = []
        for item in feedback_context:
            correction_note = (
                item["notes"].strip()
                if item.get("notes")
                else "No operator note provided."
            )
            lines.append(
                (
                    f"- Sample {item['sample_id']}: model predicted {item['predicted_grade']} "
                    f"but human corrected to {item['true_grade']} "
                    f"(moisture {item['predicted_moisture_risk']} -> {item['true_moisture_risk']}, "
                    f"distance {item['distance']}). Note: {correction_note}"
                )
            )
        return "\n".join(lines)

    def _compress_rag_context(self, rag_context: List[Dict[str, Any]], max_chars: int = 900) -> str:
        """Condense retrieved rules so cloud model output budget is spent on JSON."""
        if not rag_context:
            return "- No retrieved rules available."

        lines: List[str] = []
        used = 0
        for chunk in rag_context:
            title = str(chunk.get("title", "Rule")).strip()
            content = " ".join(str(chunk.get("content", "")).split())
            if not content:
                continue
            snippet = content[:180].rstrip(" ,.;:")
            line = f"- {title}: {snippet}"
            used += len(line)
            if used > max_chars and lines:
                break
            lines.append(line)
        return "\n".join(lines) if lines else "- No retrieved rules available."

    def _call_text_model(
        self,
        prompt: str,
        max_tokens: int = 180,
        crop_route: Optional[Dict[str, str]] = None,
        include_route_metadata: bool = False,
    ):
        """Run a compact text-only repair pass against the configured model route."""
        attempted_routes: List[Dict[str, Any]] = []
        last_error: Optional[str] = None
        last_route: Dict[str, Any] = {}

        try:
            route_candidates: List[Tuple[Optional[Dict[str, str]], str]] = []
            if crop_route and self._route_signature(crop_route) != self._route_signature(None):
                route_candidates.append((crop_route, "crop route"))
            route_candidates.append((None, "default"))

            for route, route_label in route_candidates:
                provider, model, base_url, route_api_key = self._resolve_route_signature(route)
                route_record = {
                    "route_label": route_label,
                    "provider": provider,
                    "model": model,
                    "base_url": base_url,
                }
                attempted_routes.append(route_record)

                try:
                    endpoint = self._chat_completions_endpoint(base_url=base_url)
                    headers = self._cloud_headers(api_key=route_api_key)
                except Exception as exc:
                    last_error = str(exc)
                    continue

                payload = {
                    "model": model,
                    "messages": [
                        {
                            "role": "system",
                            "content": "Return only strict JSON. No reasoning.",
                        },
                        {"role": "user", "content": prompt},
                    ],
                    "max_tokens": max_tokens,
                    "temperature": 0.1,
                }
                payload = self._openai_payload_options(payload, provider=provider, model=model)

                try:
                    with httpx.Client(timeout=self.qwen_timeout_seconds) as client:
                        response = client.post(endpoint, headers=headers, json=payload)
                        response.raise_for_status()
                    message = response.json()["choices"][0]["message"]
                    final_text = self._extract_message_text(message)
                    last_route = {
                        "route_label": route_label,
                        "provider": provider,
                        "model": model,
                        "base_url": base_url,
                        "fallback_used": route_label == "default" and any(
                            item.get("route_label") == "crop route" for item in attempted_routes
                        ),
                        "attempted_routes": attempted_routes,
                        "error": None,
                        "route": route or {},
                    }
                    if include_route_metadata:
                        return final_text, last_route
                    self._last_route_meta = last_route
                    return final_text
                except Exception as exc:
                    last_error = str(exc)
                    continue

        except Exception as exc:
            last_error = str(exc)

        if not last_error:
            last_error = "Text model failed without a captured exception."

        error_meta = {
            "route_label": self._default_route_label,
            "provider": self.qwen_provider,
            "model": self.qwen_model,
            "base_url": self.qwen_base_url,
            "fallback_used": bool(route_candidates) and len(route_candidates) > 1,
            "attempted_routes": attempted_routes,
            "error": last_error,
            "route": {},
        }
        self._last_route_meta = error_meta
        if include_route_metadata:
            return "", error_meta

        logger.error(f"Text repair call failed: {last_error}")
        return ""

    def _prepare_image_payload(
        self,
        image_path: str,
        physics_proxies: Optional[Dict[str, Any]] = None,
        max_side: int = 1280,
        jpeg_quality: int = 95,
    ) -> Tuple[str, str]:
        """
        Crop to the calibrated sample field and preserve high image quality.
        """
        import base64
        import io

        image = Image.open(image_path).convert("RGB")
        original_size = image.size
        crop_source = "full"
        sample_field = (physics_proxies or {}).get("sample_field", {}) if physics_proxies else {}
        bbox = sample_field.get("bbox") if isinstance(sample_field, dict) else None
        if bbox and len(bbox) == 4:
            x, y, w, h = [int(v) for v in bbox]
            pad = int(max(w, h) * 0.08)
            left = max(0, x - pad)
            top = max(0, y - pad)
            right = min(image.width, x + w + pad)
            bottom = min(image.height, y + h + pad)
            if right > left and bottom > top:
                image = image.crop((left, top, right, bottom))
                crop_source = str(sample_field.get("source", "sample-field"))

        if max(image.size) > max_side:
            image.thumbnail((max_side, max_side))

        buffer = io.BytesIO()
        image.save(
            buffer,
            format="JPEG",
            quality=jpeg_quality,
            optimize=True,
            subsampling=0,
        )
        self._last_image_payload_meta = {
            "original_size": original_size,
            "sent_size": image.size,
            "crop_source": crop_source,
            "jpeg_quality": jpeg_quality,
        }
        payload = base64.b64encode(buffer.getvalue()).decode("utf-8")
        return payload, "image/jpeg"

    async def _emit_stream_update(
        self,
        stream_callback: Callable[[str], Any],
        text: str,
    ) -> None:
        """Invoke a streaming callback without assuming it is sync or async."""
        result = stream_callback(text)
        if inspect.isawaitable(result):
            await result
        await asyncio.sleep(0)

    async def _emit_grading_result_update(
        self,
        stream_callback: Optional[Callable[[str], Any]],
        grading_result: GradingResult,
        status: str,
        detail: Optional[str] = None,
    ) -> None:
        """Send a final structured decision snapshot to a live JSON callback."""
        if stream_callback is None:
            return
        payload: Dict[str, Any] = {
            "status": status,
            "grade": grading_result.quality_grade.value,
            "quality_score": grading_result.quality_score,
            "moisture_risk": grading_result.moisture_risk.value,
            "moisture_percent": grading_result.moisture_percent_estimate,
            "confidence": grading_result.overall_confidence,
            "reject_recommended": grading_result.reject_recommended,
            "reject_reasons": grading_result.reject_reasons,
            "crop": {
                "selected_crop": grading_result.selected_crop,
                "selection_source": grading_result.selection_source,
                "selected_crop_confidence": grading_result.selected_crop_confidence,
            },
            "applied_rules": grading_result.applied_rules[:4],
            "model_version": grading_result.model_version,
            "routing": {
                "route_label": grading_result.route_label,
                "route_provider": grading_result.route_provider,
                "route_model": grading_result.route_model,
                "route_base_url": grading_result.route_base_url,
                "route_fallback_used": grading_result.route_fallback_used,
                "route_attempts": grading_result.route_attempts,
                "route_error": grading_result.route_error,
            },
            "decision_summary": grading_result.operator_summary,
            "signals": grading_result.signal_highlights,
        }
        if detail:
            payload["detail"] = detail
        await self._emit_stream_update(stream_callback, json.dumps(payload, indent=2))

    def _call_qwen_vision(
        self,
        image_path: str,
        prompt: str,
        max_tokens: int = 500,
        physics_proxies: Optional[Dict[str, Any]] = None,
        crop_route: Optional[Dict[str, str]] = None,
        include_route_metadata: bool = False,
    ):
        """
        Call Qwen-VL through the configured cloud OpenAI-compatible provider.
        """
        image_data, image_type = self._prepare_image_payload(
            image_path,
            physics_proxies=physics_proxies,
        )

        route_candidates: List[Tuple[Optional[Dict[str, str]], str]] = []
        if crop_route and self._route_signature(crop_route) != self._route_signature(None):
            route_candidates.append((crop_route, "crop route"))
        route_candidates.append((None, "default"))

        attempted_routes: List[Dict[str, Any]] = []
        last_error: Optional[Exception] = None
        last_error_text = ""
        queued_fallback_signatures = set()
        route_index = 0
        while route_index < len(route_candidates):
            route, route_label = route_candidates[route_index]
            route_index += 1
            provider, model, base_url, route_api_key = self._resolve_route_signature(route)
            route_record = {
                "route_label": route_label,
                "provider": provider,
                "model": model,
                "base_url": base_url,
                "route": route or {},
            }
            attempted_routes.append(route_record)
            try:
                endpoint = self._chat_completions_endpoint(base_url=base_url)
            except ValueError as exc:
                last_error = exc
                last_error_text = self._format_cloud_error(exc)
                route_record["error"] = last_error_text
                logger.warning(
                    "Skipping route %s due to endpoint config error: %s",
                    route_label,
                    exc,
                )
                continue

            headers = self._cloud_headers(api_key=route_api_key)
            payload = {
                "model": model,
                "messages": [
                    {
                        "role": "system",
                        "content": "/no_think Return only the final JSON object. Do not include <think>, markdown, notes, or prose.",
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{image_type};base64,{image_data}"
                                },
                            },
                            {"type": "text", "text": prompt},
                        ],
                    }
                ],
                "max_tokens": max_tokens,
                "temperature": 0.3,  # Low temperature for deterministic output
                "top_p": 0.8,
                "stream": False,
            }
            payload = self._openai_payload_options(payload, provider=provider, model=model)
            try:
                with httpx.Client(timeout=self.qwen_timeout_seconds) as client:
                    response = client.post(endpoint, headers=headers, json=payload)
                    response.raise_for_status()

                result = response.json()
                choice = result["choices"][0]
                message = choice["message"]
                self._last_message_meta = {
                    "content": message.get("content", ""),
                    "reasoning": message.get("reasoning_content", "") or message.get("reasoning", ""),
                    "finish_reason": choice.get("finish_reason", ""),
                }
                final_text = self._extract_message_text(message)
                route_meta = {
                    "route_label": route_label,
                    "provider": provider,
                    "model": model,
                    "base_url": base_url,
                    "fallback_used": route_label == "model fallback" or (
                        route_label == "default"
                        and any(item.get("route_label") == "crop route" for item in attempted_routes)
                    ),
                    "attempted_routes": [
                        f"{r['route_label']}:{r['provider']}/{r['model']}@{r['base_url']}"
                        for r in attempted_routes
                    ],
                    "route": route or {},
                    "error": None,
                }
                self._last_route_meta = route_meta
                logger.info(
                    "Inference succeeded via %s route (%s/%s)",
                    route_label,
                    provider,
                    model,
                )
                if include_route_metadata:
                    return final_text, route_meta
                return final_text
            except Exception as exc:
                last_error = exc
                last_error_text = self._format_cloud_error(exc)
                route_record["error"] = last_error_text
                logger.warning(
                    "Qwen-VL API call failed via %s route (%s/%s): %s",
                    route_label,
                    provider,
                    model,
                    last_error_text,
                )
                if route_label == "crop route":
                    logger.warning("Falling back to default Qwen route.")
                if route_label == "default" and self._should_try_model_fallback(exc):
                    for fallback_route, fallback_label in self._fallback_routes_for_model(
                        provider,
                        model,
                        base_url,
                        route_api_key,
                    ):
                        signature = self._route_signature(fallback_route)
                        if signature in queued_fallback_signatures:
                            continue
                        queued_fallback_signatures.add(signature)
                        route_candidates.append((fallback_route, fallback_label))
                    if queued_fallback_signatures:
                        route_record["fallback_models_queued"] = [
                            signature[1] for signature in queued_fallback_signatures
                        ]
                        logger.warning("Trying configured Qwen fallback model route(s).")
                continue

        if last_error is None:
            last_error = RuntimeError("No Qwen route succeeded.")
            last_error_text = str(last_error)
        error_meta = {
            "route_label": self._default_route_label,
            "provider": self.qwen_provider,
            "model": self.qwen_model,
            "base_url": self.qwen_base_url,
            "fallback_used": bool(route_candidates) and len(route_candidates) > 1,
            "attempted_routes": [
                f"{r['route_label']}:{r['provider']}/{r['model']}@{r['base_url']}"
                for r in attempted_routes
            ],
            "route": {},
            "error": last_error_text or str(last_error),
        }
        self._last_route_meta = error_meta
        logger.error("Qwen-VL API call failed: %s", error_meta["error"])
        if include_route_metadata:
            return "", error_meta
        raise last_error

    def _parse_json_response(self, response: str) -> Dict[str, Any]:
        """Extract JSON from LLM response text."""
        try:
            import re
            if isinstance(response, dict):
                return response
            text = str(response or "").strip()
            if not text:
                return {}
            text = text.replace("```json", "```").replace("```JSON", "```")
            fenced = re.findall(r"```(?:json)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
            if fenced:
                for block in fenced:
                    block = block.strip()
                    if not block:
                        continue
                    try:
                        return json.loads(block)
                    except json.JSONDecodeError:
                        pass
            json_match = re.search(r"\{[\s\S]*\}", text)
            if json_match:
                json_str = json_match.group()
                return json.loads(json_str)
            else:
                logger.warning("No JSON found in response. Returning empty dict.")
                return {}
        except json.JSONDecodeError as e:
            logger.error(f"JSON parse error: {e}")
            return {}

    def _recover_grading_fields_from_text(self, raw_text: str) -> Dict[str, Any]:
        """Recover scalar grading fields from malformed JSON-like model text."""
        import re

        text = str(raw_text or "")
        if not text:
            return {}

        numeric_keys = {
            "quality_score",
            "off_tone_fraction",
            "size_deviation",
            "shape_defect_fraction",
            "broken_grain_percent",
            "broken_grains_percent",
            "damaged_grains_percent",
            "chalky_grains_percent",
            "foreign_matter_percent",
            "organic_extraneous_matter_percent",
            "inorganic_extraneous_matter_percent",
            "other_edible_grains_percent",
            "immature_grains_percent",
            "weevilled_grains_percent",
            "color_uniformity_score",
            "size_uniformity_score",
            "shape_uniformity_score",
            "surface_defects_percent",
            "measured_moisture_percent",
            "model_confidence",
        }
        recovered: Dict[str, Any] = {}
        for key in numeric_keys:
            match = re.search(
                rf'"{re.escape(key)}"\s*:\s*(-?\d+(?:\.\d+)?)',
                text,
                flags=re.IGNORECASE,
            )
            if match:
                number = float(match.group(1))
                recovered[key] = int(number) if number.is_integer() else number

        for key in ("bimodal_color_detected", "mold_visible"):
            match = re.search(
                rf'"{re.escape(key)}"\s*:\s*(true|false)',
                text,
                flags=re.IGNORECASE,
            )
            if match:
                recovered[key] = match.group(1).lower() == "true"

        grade_match = re.search(
            r'"quality_grade"\s*:\s*"([ABCabc])"',
            text,
            flags=re.IGNORECASE,
        )
        if grade_match:
            recovered["quality_grade"] = grade_match.group(1).upper()

        defects_match = re.search(
            r'"visible_defects"\s*:\s*\[([^\]]*)\]',
            text,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if defects_match:
            recovered["visible_defects"] = [
                item.strip()
                for item in re.findall(r'"([^"]+)"', defects_match.group(1))
                if item.strip()
            ]

        return recovered

    def _merge_recovered_grading_fields(
        self,
        response_json: Dict[str, Any],
        recovered_fields: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Prefer explicit quoted fields recovered from malformed model JSON."""
        if not recovered_fields:
            return response_json

        merged = dict(response_json or {})
        merged.update(recovered_fields)

        if recovered_fields.get("mold_visible") is False:
            visible_defects = merged.get("visible_defects", [])
            if isinstance(visible_defects, str):
                visible_defects = [visible_defects]
            if isinstance(visible_defects, list):
                merged["visible_defects"] = [
                    defect
                    for defect in visible_defects
                    if not any(
                        term in str(defect).lower()
                        for term in ("mold", "mould", "fungus", "fungal")
                    )
                ]

        return merged

    def _repair_grading_json(
        self,
        raw_text: str,
        physics_proxies: Dict[str, Any],
        crop_route: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        """Convert empty or reasoning-heavy model output into the compact grading schema."""
        if not raw_text:
            return {}
        repair_prompt = f"""Convert these model notes into strict JSON only.

Required keys:
quality_grade, quality_score, off_tone_fraction, size_deviation,
shape_defect_fraction, broken_grain_percent, foreign_matter_percent,
other_edible_grains_percent, broken_grains_percent, damaged_grains_percent,
chalky_grains_percent, organic_extraneous_matter_percent,
inorganic_extraneous_matter_percent, immature_grains_percent,
weevilled_grains_percent, color_uniformity_score, size_uniformity_score,
shape_uniformity_score, surface_defects_percent, bimodal_color_detected,
mold_visible, visible_defects, model_confidence, brief_reason

Use conservative values if uncertain.
Signals: darkness_index={physics_proxies['lab_features']['color_darkness_index']:.1f}, clumping_density={physics_proxies['clumping']['density']:.3f}, uniformity_score={physics_proxies['uniformity_score']:.1f}, texture_entropy={physics_proxies['texture_entropy']:.2f}

Notes:
{raw_text[:2200]}"""
        repaired = self._call_text_model(
            repair_prompt,
            max_tokens=220,
            crop_route=crop_route,
        )
        return self._parse_json_response(repaired)

    def _extract_grading_hints_from_text(
        self,
        raw_text: str,
        physics_proxies: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Heuristic backup when the cloud model returns reasoning text without final JSON."""
        import re

        text = str(raw_text or "").lower()
        if not text:
            return {}
        if not any(ch.isalpha() for ch in text):
            return {}
        recovered_fields = self._recover_grading_fields_from_text(raw_text)
        scan_text = re.sub(r'"[a-zA-Z_][a-zA-Z0-9_]*"\s*:', " ", text)
        scan_text = re.sub(r"\b(mold_visible|visible_defects)\b", " ", scan_text)

        grade = "B"
        if "grade c" in text or "-> grade c" in text or "grade=c" in text:
            grade = "C"
        elif "grade a" in text or "-> grade a" in text or "grade=a" in text:
            grade = "A"

        visible_defects = [
            str(item).strip().lower()
            for item in recovered_fields.get("visible_defects", [])
            if str(item).strip()
        ]
        if not visible_defects:
            for defect in ("mold", "stone", "insect", "webbing", "clumping", "shriveled", "mixed"):
                if re.search(rf"\b{re.escape(defect)}\b", scan_text):
                    visible_defects.append(defect)

        bimodal = "bimodal" in scan_text or "mixed batch" in scan_text or "two clearly distinct tones" in scan_text
        if "bimodal_color_detected" in recovered_fields:
            bimodal = bool(recovered_fields["bimodal_color_detected"])

        if "mold_visible" in recovered_fields:
            mold_visible = bool(recovered_fields["mold_visible"])
        else:
            no_mold = re.search(
                r"\b(no|none|not|without|absent|free of)\s+(visible\s+)?(mold|mould|fungus|fungal)\b",
                scan_text,
            )
            mold_visible = (
                "mold" in visible_defects
                or "mould" in visible_defects
                or bool(re.search(r"\b(mold|mould|fungus|fungal)\b", scan_text) and not no_mold)
            )
        if not mold_visible:
            visible_defects = [
                defect
                for defect in visible_defects
                if not any(term in defect for term in ("mold", "mould", "fung"))
            ]

        if recovered_fields.get("quality_grade") in {"A", "B", "C"}:
            grade = str(recovered_fields["quality_grade"])
        foreign_matter = float(recovered_fields.get("foreign_matter_percent", 0.5))
        if "foreign_matter_percent" not in recovered_fields:
            foreign_matter = (
                4.0
                if ("foreign matter >1" in scan_text or "stones" in scan_text or "debris" in scan_text)
                else 0.5
            )

        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        darkness = float(
            physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0)
        )
        uniformity = float(physics_proxies.get("uniformity_score", 70.0))

        off_tone = 14.0 if bimodal or uniformity < 68 else 6.0
        size_dev = 16.0 if grade == "C" else 7.0
        shape_defect = 12.0 if clumping > 0.18 or darkness > 50 else 4.0

        return {
            "quality_grade": grade,
            "quality_score": 55 if grade == "C" else 75 if grade == "B" else 90,
            "off_tone_fraction": off_tone,
            "size_deviation": size_dev,
            "shape_defect_fraction": shape_defect,
            "broken_grain_percent": 6.0 if grade == "C" else 2.0,
            "foreign_matter_percent": foreign_matter,
            "other_edible_grains_percent": 0.0,
            "bimodal_color_detected": bimodal,
            "mold_visible": mold_visible,
            "visible_defects": visible_defects,
            "model_confidence": 68 if grade == "C" else 72,
            "brief_reason": "Recovered from model reasoning text after empty structured output.",
        }

    def _apply_grading_logic(
        self,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        moisture_risk: Optional[MoistureRisk] = None,
        moisture_percent: Optional[float] = None,
        moisture_calibrated: bool = True,
        crop_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Apply deterministic FAO/BIS-aligned threshold rules."""
        decision = self.rule_engine.evaluate(
            response_json=response_json,
            physics_proxies=physics_proxies,
            moisture_risk=moisture_risk,
            moisture_percent=moisture_percent,
            moisture_calibrated=moisture_calibrated,
            crop_type=crop_type,
        )
        return {
            "grade": QualityGrade(decision.grade),
            "score": decision.score,
            "reject": decision.reject,
            "reject_reasons": decision.reject_reasons,
            "broken_grain": decision.broken_grain,
            "foreign_matter": decision.foreign_matter,
            "uniformity": decision.uniformity,
            "mold_visible": decision.mold_visible,
            "rule_hits": decision.rule_hits,
            "grain_grade": QualityGrade(decision.grain_grade),
            "grain_score": decision.grain_score,
            "moisture_score": decision.moisture_score,
            "score_breakdown": decision.score_breakdown,
        }

    def _estimate_moisture_risk(self, physics_proxies: Dict[str, Any]) -> Tuple[MoistureRisk, float, bool]:
        """
        Estimate moisture risk from physics proxy signals.
        Thresholds based on UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md
        """

        # Extract signals
        darkness_idx = physics_proxies["lab_features"]["color_darkness_index"]
        clumping = physics_proxies["clumping"]["density"]
        entropy = physics_proxies["texture_entropy"]
        calibration = physics_proxies.get("calibration", {}) or {}
        calibrated_geometry = physics_proxies.get("calibrated_geometry", {}) or {}
        physical = physics_proxies.get("physical_properties", {}) or {}
        calibration_available = bool(calibration.get("available")) and bool(calibration.get("mm_per_pixel"))

        # Composite moisture score (0-100)
        moisture_score = 0.0
        moisture_score += min(100, darkness_idx)  # Darkness: 0-100
        moisture_score += clumping * 200.0  # Clumping: 0-100
        moisture_score += max(0, 40 - entropy) * 5  # Low entropy: 0-100
        moisture_score /= 3.0

        if calibration_available:
            fill_ratio = float(calibrated_geometry.get("grain_fill_ratio") or physics_proxies.get("grain_mask_coverage", 0.0))
            clump_mm = float(calibrated_geometry.get("clump_equiv_diameter_mm") or 0.0)
            median_mm = float(calibrated_geometry.get("median_equiv_diameter_mm") or 0.0)
            grain_density = float(calibrated_geometry.get("grain_density_per_cm2") or 0.0)

            moisture_score += float(np.clip((fill_ratio - 0.35) * 90.0, -6.0, 14.0))
            moisture_score += float(np.clip((clump_mm - 2.1) * 5.5, 0.0, 16.0))
            if grain_density > 0.0:
                moisture_score += float(np.clip((35.0 - grain_density) * 0.08, -4.0, 6.0))
            if median_mm > 0.0:
                moisture_score += float(np.clip((2.0 - abs(median_mm - 1.45)) * 2.0, -1.5, 2.5))

        reflectiveness_class = str(physical.get("reflectiveness_class") or "")
        dark_fraction = float(physical.get("dark_fraction") or 0.0)
        highlight_fraction = float(physical.get("highlight_fraction") or 0.0)
        if reflectiveness_class == "dull" and dark_fraction > 0.30:
            moisture_score += float(np.clip(dark_fraction * 12.0, 0.0, 8.0))
        if highlight_fraction > 0.25:
            moisture_score += 2.0

        # Map to calibrated moisture percentage
        moisture_percent = self.moisture_calibrator.calibrate(moisture_score)
        is_calibrated = self.moisture_calibrator.get_is_calibrated() and calibration_available

        # Map to risk categories
        if moisture_score <= 30:
            risk = MoistureRisk.LOW
        elif moisture_score <= 50:
            risk = MoistureRisk.MODERATE
        elif moisture_score <= 70:
            risk = MoistureRisk.HIGH
        else:
            risk = MoistureRisk.CRITICAL
            
        return risk, moisture_percent, is_calibrated

    def _compute_confidence(
        self,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        rag_context: List[Dict[str, Any]],
    ) -> int:
        """Compute overall confidence (0-100) from model, image, and evidence consistency."""

        model_conf = float(response_json.get("model_confidence", 70))
        grade = str(response_json.get("quality_grade", "B")).upper()
        grain_coverage = float(physics_proxies.get("grain_mask_coverage", 0.5))
        uniformity = float(physics_proxies.get("uniformity_score", 70.0))
        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        darkness = float(
            physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0)
        )
        calibration_conf = float(physics_proxies.get("calibration", {}).get("grid_confidence", 0.0))

        image_quality = np.clip((grain_coverage * 140.0) + (uniformity * 0.4), 0, 100)
        rag_support = np.clip(
            sum(chunk.get("retrieval_score", 0.0) for chunk in rag_context) * 6.5,
            0,
            100,
        )

        if grade == "A":
            proxy_consistency = 95 if clumping < 0.12 and darkness < 45 and uniformity >= 72 else 45
        elif grade == "B":
            proxy_consistency = 85 if clumping < 0.22 and uniformity >= 60 else 55
        else:
            proxy_consistency = 90 if clumping > 0.18 or darkness > 50 or uniformity < 68 else 60

        overall = (
            0.45 * model_conf
            + 0.20 * image_quality
            + 0.20 * proxy_consistency
            + 0.15 * rag_support
        )
        if calibration_conf > 0:
            overall += 0.05 * (calibration_conf * 100.0)
        if (physics_proxies.get("machine_moisture") or {}).get("percent") is not None:
            overall += 4.0
        return int(np.clip(overall, 0, 100))

    def _fallback_grading(
        self,
        physics_proxies: Dict[str, Any],
        timestamp: str,
        selected_crop: Optional[str] = None,
        selected_variety: Optional[str] = None,
        selected_crop_confidence: float = 0.0,
        selection_source: str = "default",
        route_meta: Optional[Dict[str, Any]] = None,
        measured_moisture_percent: Optional[float] = None,
        moisture_source: str = "grain_proxy",
        moisture_ocr_confidence: Optional[float] = None,
    ) -> GradingResult:
        """Fallback grading when LLM inference fails."""

        moisture_risk, moisture_percent, is_calib = self._resolve_moisture_measurement(
            physics_proxies,
            crop_type=selected_crop,
            measured_moisture_percent=measured_moisture_percent,
        )
        darkness = float(physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0))
        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        uniformity = float(physics_proxies.get("uniformity_score", 70.0))
        roughness = float(physics_proxies.get("roughness_score", 50.0))
        coverage = float(physics_proxies.get("grain_mask_coverage", 0.5))

        off_tone = float(np.clip(max(0.0, darkness - 35.0) * 0.45 + max(0.0, 92.0 - uniformity) * 0.18, 0.0, 35.0))
        size_deviation = float(np.clip(max(0.0, 95.0 - uniformity) * 0.35, 0.0, 35.0))
        shape_defect = float(np.clip(max(0.0, 90.0 - uniformity) * 0.25 + clumping * 18.0, 0.0, 35.0))
        broken_grain = float(np.clip(max(0.0, 90.0 - uniformity) * 0.05 + clumping * 8.0, 0.0, 20.0))
        damaged_grains = float(np.clip(shape_defect * 0.14 + max(0.0, 35.0 - roughness) * 0.03, 0.0, 8.0))
        foreign_matter = float(np.clip(0.2 + max(0.0, 0.18 - coverage) * 6.0, 0.0, 3.0))
        surface_defects = float(np.clip(shape_defect + max(0.0, 45.0 - roughness) * 0.08, 0.0, 25.0))
        provisional_grade = "A" if (
            darkness < 42 and clumping < 0.10 and uniformity > 78 and roughness > 20
        ) else ("C" if darkness > 60 or clumping > 0.30 or uniformity < 55 else "B")

        fallback_response = {
            "quality_grade": provisional_grade,
            "quality_score": 65,
            "off_tone_fraction": off_tone,
            "size_deviation": size_deviation,
            "shape_defect_fraction": shape_defect,
            "broken_grain_percent": broken_grain,
            "broken_grains_percent": broken_grain,
            "damaged_grains_percent": damaged_grains,
            "chalky_grains_percent": off_tone,
            "foreign_matter_percent": foreign_matter,
            "organic_extraneous_matter_percent": foreign_matter,
            "inorganic_extraneous_matter_percent": 0.0,
            "other_edible_grains_percent": 0.0,
            "immature_grains_percent": size_deviation * 0.25,
            "weevilled_grains_percent": 0.0,
            "color_uniformity_score": max(0.0, 100.0 - off_tone),
            "size_uniformity_score": max(0.0, 100.0 - size_deviation),
            "shape_uniformity_score": max(0.0, 100.0 - shape_defect),
            "surface_defects_percent": surface_defects,
            "bimodal_color_detected": off_tone > 12.0,
            "mold_visible": False,
            "visible_defects": [],
            "model_confidence": 45,
            "brief_reason": "Qwen-VL unavailable; crop YAML rules applied to conservative proxy estimates.",
        }
        grade = self._apply_grading_logic(
            fallback_response,
            physics_proxies,
            moisture_risk=moisture_risk,
            moisture_percent=moisture_percent,
            moisture_calibrated=is_calib,
            crop_type=selected_crop,
        )
        signal_highlights = self._summarize_signals(physics_proxies, moisture_risk)
        signal_highlights = list(
            dict.fromkeys(
                [
                    "Qwen-VL unavailable; crop-aware deterministic fallback used",
                    *signal_highlights,
                ]
            )
        )
        reject_reasons: List[str] = list(grade.get("reject_reasons", []))
        reject_recommended = bool(grade.get("reject"))
        if moisture_risk == MoistureRisk.CRITICAL:
            reject_recommended = True
            reject_reasons.append("Critical moisture risk; dry immediately before storage")
        elif grade["grade"] == QualityGrade.C and not reject_reasons:
            reject_reasons.extend(
                self._build_proxy_fastpath_reasons(
                    physics_proxies=physics_proxies,
                    moisture_risk=moisture_risk,
                )
            )
        operator_summary = self._build_operator_summary(
            grade["grade"],
            moisture_risk,
            reject_recommended,
            40,
            reject_reasons,
        )
        selected_crop_display = selected_crop or self.default_crop_hint or "unknown"
        applied_rules = self._build_applied_rules(
            grade.get("rule_hits", []),
            [],
            base_confidence=60.0,
            fallback_prefix="Crop YAML deterministic fallback",
        )
        applied_rules.extend(
            [
            {
                "rule_id": "fallback_deterministic_rules",
                "rule_name": "Crop-aware deterministic proxy fallback",
                "source_file": "vision_rag_pipeline._fallback_grading",
                "evidence": (
                    "Qwen-VL returned unusable output; proxy estimates were evaluated by the crop YAML rule engine."
                ),
                "rule_confidence": 60.0,
            },
            {
                "rule_id": "fallback_crop_context",
                "rule_name": "Crop context preserved",
                "source_file": "vision_rag_pipeline._resolve_crop_selection",
                "evidence": f"Crop resolved to {selected_crop_display} via {selection_source}.",
                "rule_confidence": float(np.clip(selected_crop_confidence * 100.0, 0.0, 100.0)),
            },
            ]
        )
        self.last_grading_audit = {
            "stage": "deterministic_fallback",
            "route_meta": route_meta or {},
            "rule_decision": grade,
            "score_breakdown": grade.get("score_breakdown", {}),
            "moisture": {
                "risk": moisture_risk.value,
                "percent": moisture_percent,
                "calibrated": is_calib,
            },
        }

        return GradingResult(
            quality_grade=grade["grade"],
            quality_score=grade["score"],
            reject_recommended=reject_recommended,
            reject_reasons=list(dict.fromkeys(reject_reasons)),
            broken_grain_percent=grade.get("broken_grain", broken_grain),
            foreign_matter_percent=grade.get("foreign_matter", foreign_matter),
            uniformity_score=grade.get("uniformity", uniformity),
            mold_visible=grade.get("mold_visible", False),
            moisture_risk=moisture_risk,
            moisture_estimate_calibrated=is_calib,
            moisture_percent_estimate=moisture_percent,
            overall_confidence=40,
            pass1_confidence=100,
            pass2_confidence=30,
            timestamp=timestamp,
            model_version=f"{self._fallback_route_label(route_meta)}",
            rag_chunks_used=0,
            grain_quality_grade=grade["grain_grade"],
            grain_quality_score=grade["grain_score"],
            moisture_quality_score=grade["moisture_score"],
            score_breakdown=grade["score_breakdown"],
            selected_crop=selected_crop,
            selected_variety=selected_variety or None,
            selected_crop_confidence=selected_crop_confidence,
            selection_source=selection_source,
            route_label=(route_meta or {}).get("route_label", self._default_route_label),
            route_provider=(route_meta or {}).get("provider", self.qwen_provider),
            route_model=(route_meta or {}).get("model", f"{self.qwen_model}-fallback"),
            route_base_url=(route_meta or {}).get("base_url", self.qwen_base_url),
            route_fallback_used=bool((route_meta or {}).get("fallback_used", True)),
            route_attempts=(route_meta or {}).get("attempted_routes") or [],
            route_error=(route_meta or {}).get("error"),
            applied_rules=applied_rules,
            operator_summary=operator_summary,
            manual_review_required=True,
            signal_highlights=signal_highlights,
            measured_moisture_percent=measured_moisture_percent,
            moisture_source=moisture_source,
            moisture_ocr_confidence=moisture_ocr_confidence,
        )

    def _fallback_route_label(self, route_meta: Optional[Dict[str, Any]]) -> str:
        if not route_meta:
            return f"{self.qwen_model}-fallback"
        if route_meta.get("provider") and route_meta.get("model"):
            return f"{route_meta.get('provider')}/{route_meta.get('model')}"
        return f"{self.qwen_model}-fallback"

    def _summarize_signals(
        self,
        physics_proxies: Dict[str, Any],
        moisture_risk: MoistureRisk,
    ) -> List[str]:
        """Produce a short operator-facing summary of the strongest signals."""
        darkness = float(physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0))
        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        uniformity = float(physics_proxies.get("uniformity_score", 0.0))
        entropy = float(physics_proxies.get("texture_entropy", 0.0))
        physical = physics_proxies.get("physical_properties", {}) or {}
        machine_moisture = physics_proxies.get("machine_moisture") or {}
        highlights: List[str] = [f"Moisture risk: {moisture_risk.value}"]
        if machine_moisture.get("percent") is not None:
            highlights.append(
                f"Machine moisture: {float(machine_moisture.get('percent')):.2f}%"
            )
        if clumping > 0.18:
            highlights.append(f"Clumping is elevated ({clumping:.3f})")
        if darkness > 50:
            highlights.append(f"Darkness index is high ({darkness:.1f})")
        if uniformity < 68:
            highlights.append(f"Uniformity is weak ({uniformity:.1f}/100)")
        if entropy < 3.0:
            highlights.append(f"Texture entropy is low ({entropy:.2f})")
        if physical.get("size_class") in {"small", "large", "mixed"}:
            highlights.append(
                f"Grain size is {physical.get('size_class')} "
                f"(median {float(physical.get('median_diameter_mm') or 0.0):.2f} mm)"
            )
        if physical.get("reflectiveness_class") in {"dull", "high_shine"}:
            highlights.append(
                f"Reflectiveness is {physical.get('reflectiveness_class')} "
                f"({float(physical.get('reflectiveness_index') or 0.0):.1f}/100)"
            )
        return highlights

    def _build_proxy_fastpath_reasons(
        self,
        physics_proxies: Dict[str, Any],
        moisture_risk: MoistureRisk,
    ) -> List[str]:
        """Build non-generic reasons for deterministic proxy-only holds."""
        darkness = float(
            physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0)
        )
        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        uniformity = float(physics_proxies.get("uniformity_score", 70.0))
        entropy = float(physics_proxies.get("texture_entropy", 10.0))

        reasons: List[str] = []
        if darkness >= 60:
            reasons.append(f"Darkness index {darkness:.1f} is above the dry-lot range")
        if clumping >= 0.16:
            reasons.append(f"Clumping density {clumping:.3f} suggests moisture-linked aggregation")
        if uniformity <= 52:
            reasons.append(f"Uniformity {uniformity:.1f}/100 indicates a mixed or unstable lot")
        if entropy <= 3.0:
            reasons.append(f"Texture entropy {entropy:.2f} is consistent with a smoother, wetter grain surface")
        if not reasons:
            reasons.append(f"Proxy evidence points to a {moisture_risk.value.lower()} moisture-risk lot")
        return reasons

    def _score_proxy_fastpath(
        self,
        physics_proxies: Dict[str, Any],
        moisture_risk: MoistureRisk,
    ) -> int:
        """Compute a more meaningful quality score for proxy-only decisions."""
        darkness = float(
            physics_proxies.get("lab_features", {}).get("color_darkness_index", 0.0)
        )
        clumping = float(physics_proxies.get("clumping", {}).get("density", 0.0))
        uniformity = float(physics_proxies.get("uniformity_score", 70.0))
        entropy = float(physics_proxies.get("texture_entropy", 10.0))

        score = 76.0
        score -= max(0.0, darkness - 50.0) * 1.1
        score -= max(0.0, 62.0 - uniformity) * 1.0
        score -= max(0.0, 3.2 - entropy) * 12.0
        score -= max(0.0, clumping - 0.10) * 110.0
        if moisture_risk == MoistureRisk.CRITICAL:
            score -= 6.0
        elif moisture_risk == MoistureRisk.HIGH:
            score -= 4.0
        return int(np.clip(round(score), 22, 56))

    def _build_operator_summary(
        self,
        grade: QualityGrade,
        moisture_risk: MoistureRisk,
        reject_recommended: bool,
        overall_confidence: int,
        reject_reasons: List[str],
    ) -> str:
        """Create a concise action sentence for the UI."""
        if reject_recommended:
            if reject_reasons:
                reason = "; ".join(reject_reasons[:2])
            else:
                reason = "risk signals are too strong"
            return f"Hold this batch. {reason}."
        if moisture_risk == MoistureRisk.CRITICAL:
            return "Dry this batch immediately and recheck before storage."
        if moisture_risk == MoistureRisk.HIGH:
            return "Dry this batch before storage and confirm with operator review."
        if grade == QualityGrade.A and overall_confidence >= 75:
            return "This lot looks strong for direct food-grade handling."
        if grade == QualityGrade.B:
            return "This lot is usable, but not premium. Keep routine storage checks in place."
        if grade == QualityGrade.C:
            return "This lot is low grade and should be reworked, dried, or manually reviewed."
        return "Review this lot with an operator before release."

    def format_result_for_api(self, grading_result: GradingResult) -> Dict[str, Any]:
        """Format GradingResult for JSON API response."""
        return {
            "quality": {
                "grade": grading_result.quality_grade.value,
                "grain_grade": grading_result.grain_quality_grade.value,
                "score": grading_result.quality_score,
                "grain_score": grading_result.grain_quality_score,
                "moisture_score": grading_result.moisture_quality_score,
                "score_breakdown": grading_result.score_breakdown,
                "reject_recommended": grading_result.reject_recommended,
                "reject_reasons": grading_result.reject_reasons,
                "broken_grain_percent": grading_result.broken_grain_percent,
                "foreign_matter_percent": grading_result.foreign_matter_percent,
                "uniformity_score": grading_result.uniformity_score,
                "mold_visible": grading_result.mold_visible,
            },
            "moisture": {
                "risk_level": grading_result.moisture_risk.value,
                "percent_estimate": grading_result.moisture_percent_estimate,
                "machine_percent": grading_result.measured_moisture_percent,
                "source": grading_result.moisture_source,
                "ocr_confidence": grading_result.moisture_ocr_confidence,
                "calibrated": grading_result.moisture_estimate_calibrated,
            },
            "confidence": {
                "overall": grading_result.overall_confidence,
                "pass1_safety_gate": grading_result.pass1_confidence,
                "pass2_grading": grading_result.pass2_confidence,
            },
            "selection": {
                "selected_crop": grading_result.selected_crop,
                "selected_variety": grading_result.selected_variety,
                "selected_crop_confidence": grading_result.selected_crop_confidence,
                "selection_source": grading_result.selection_source,
            },
            "routing": {
                "route_label": grading_result.route_label,
                "route_provider": grading_result.route_provider,
                "route_model": grading_result.route_model,
                "route_base_url": grading_result.route_base_url,
                "route_fallback_used": grading_result.route_fallback_used,
                "route_attempts": grading_result.route_attempts,
                "route_error": grading_result.route_error,
            },
            "applied_rules": grading_result.applied_rules,
            "audit": {
                "timestamp": grading_result.timestamp,
                "model_version": grading_result.model_version,
                "rag_chunks_used": grading_result.rag_chunks_used,
            },
        }


# Minimal test
if __name__ == "__main__":
    import os

    api_key = os.getenv("SILICONFLOW_API_KEY", "your-key-here")

    # This would require a real image path and physics proxies
    pipeline = VisionRAGPipeline(siliconflow_api_key=api_key)
    print("Vision-RAG Pipeline ready")
