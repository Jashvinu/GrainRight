"""
Deterministic FAO/BIS-aligned threshold rules for ragi grading.

The model can describe the image, but this engine owns the final threshold
decision for moisture, foreign matter, visible hazards, and defect load.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from .paths import LEGACY_RAG_DOCS_DIR, RAG_DOCS_DIR


GRADE_ORDER = {"C": 0, "B": 1, "A": 2}
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")


@dataclass(frozen=True)
class RagiRuleThresholds:
    """Conservative operator-assist thresholds from the RAG rule anchor."""

    moisture_a_max: float = 12.0
    moisture_b_max: float = 13.0
    moisture_c_max: float = 14.0

    foreign_a_max: float = 0.10
    foreign_b_max: float = 0.75
    foreign_c_max: float = 1.0

    other_grain_a_max: float = 1.0
    other_grain_b_max: float = 2.0
    other_grain_c_max: float = 4.0

    damaged_a_max: float = 3.1
    damaged_b_max: float = 6.3
    damaged_c_max: float = 9.5

    off_tone_a_max: float = 5.0
    off_tone_c_min: float = 10.0
    size_dev_a_max: float = 5.0
    size_dev_c_min: float = 15.0
    shape_defect_a_max: float = 5.0
    shape_defect_c_min: float = 10.0
    broken_c_min: float = 5.0


@dataclass
class RuleDecision:
    grade: str
    score: int
    reject: bool
    reject_reasons: List[str] = field(default_factory=list)
    broken_grain: float = 0.0
    foreign_matter: float = 0.0
    uniformity: float = 70.0
    mold_visible: bool = False
    rule_hits: List[str] = field(default_factory=list)
    grain_grade: str = "B"
    grain_score: int = 75
    moisture_score: int = 100
    final_score: int = 75
    score_breakdown: Dict[str, Any] = field(default_factory=dict)


def _as_float(value: Any, default: float) -> float:
    if value is None:
        return default
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    match = NUMBER_RE.search(str(value))
    if match:
        try:
            return float(match.group(0))
        except ValueError:
            return default
    return default


def _as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value).strip().lower()
    return text in {"true", "yes", "y", "1", "present", "visible", "detected"}


def _as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, Iterable):
        return [str(item) for item in value]
    return [str(value)]


def _grade_value(value: Any) -> str:
    text = str(value or "B").strip().upper()
    if text in GRADE_ORDER:
        return text
    if "GRADE A" in text:
        return "A"
    if "GRADE C" in text:
        return "C"
    return "B"


def _clip_score(value: float, low: float = 0.0, high: float = 100.0) -> int:
    return int(round(max(low, min(high, value))))


def _score_to_grade(score: int) -> str:
    if score >= 90:
        return "A"
    if score >= 75:
        return "B"
    return "C"


def _score_max_metric(value: float, grade_a: float, grade_b: float, grade_c: float) -> int:
    """Map a lower-is-better metric to a continuous 0-100 score."""
    if value <= grade_a:
        span = max(abs(grade_a), 0.01)
        return _clip_score(90.0 + ((grade_a - value) / span) * 10.0)
    if value <= grade_b:
        span = max(grade_b - grade_a, 0.01)
        return _clip_score(75.0 + ((grade_b - value) / span) * 14.0)
    if value <= grade_c:
        span = max(grade_c - grade_b, 0.01)
        return _clip_score(60.0 + ((grade_c - value) / span) * 14.0)
    span = max(grade_c - grade_b, grade_b - grade_a, abs(grade_c), 1.0)
    return _clip_score(60.0 - ((value - grade_c) / span) * 35.0, low=20.0)


def _score_min_metric(value: float, grade_a: float, grade_b: float, grade_c: float) -> int:
    """Map a higher-is-better metric to a continuous 0-100 score."""
    if value >= grade_a:
        span = max(100.0 - grade_a, 1.0)
        return _clip_score(90.0 + ((value - grade_a) / span) * 10.0)
    if value >= grade_b:
        span = max(grade_a - grade_b, 0.01)
        return _clip_score(75.0 + ((value - grade_b) / span) * 14.0)
    if value >= grade_c:
        span = max(grade_b - grade_c, 0.01)
        return _clip_score(60.0 + ((value - grade_c) / span) * 14.0)
    span = max(grade_b - grade_c, grade_a - grade_b, grade_c, 1.0)
    return _clip_score(60.0 - ((grade_c - value) / span) * 35.0, low=20.0)


def _risk_score(moisture_risk: Any) -> int:
    label = str(getattr(moisture_risk, "value", moisture_risk or "")).upper()
    if label == "LOW":
        return 100
    if label == "MODERATE":
        return 82
    if label == "HIGH":
        return 65
    if label == "CRITICAL":
        return 35
    return 85


def _weighted_average(scores: Dict[str, int], weights: Dict[str, float]) -> int:
    usable = [(name, float(score), float(weights.get(name, 1.0))) for name, score in scores.items()]
    usable = [item for item in usable if item[2] > 0]
    if not usable:
        return 75
    total_weight = sum(item[2] for item in usable)
    return _clip_score(sum(score * weight for _name, score, weight in usable) / total_weight)


def _grade_from_score(score: int) -> str:
    if score >= 88:
        return "A"
    if score >= 72:
        return "B"
    return "C"


def _clamp_score_to_grade(score: int, grade: str) -> int:
    if grade == "A":
        return _clip_score(score, low=88, high=100)
    if grade == "B":
        return _clip_score(score, low=72, high=87)
    return _clip_score(score, low=20, high=71)


def _score_breakdown_payload(
    *,
    grain_grade: str,
    grain_score: int,
    moisture_score: int,
    final_score: int,
    metrics: Dict[str, Dict[str, Any]],
    penalties: List[Dict[str, Any]],
    rule_source: str,
) -> Dict[str, Any]:
    return {
        "grain_grade": grain_grade,
        "grain_score": grain_score,
        "moisture_score": moisture_score,
        "final_score": final_score,
        "metrics": metrics,
        "penalties": penalties,
        "rule_source": rule_source,
    }


class RagiRuleEngine:
    """Applies hard ragi thresholds after VLM interpretation."""

    def __init__(self, thresholds: Optional[RagiRuleThresholds] = None):
        self.thresholds = thresholds or RagiRuleThresholds()

    def evaluate(
        self,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        moisture_risk: Any = None,
        moisture_percent: Optional[float] = None,
        moisture_calibrated: bool = True,
    ) -> RuleDecision:
        t = self.thresholds

        llm_grade = _grade_value(response_json.get("quality_grade", "B"))
        off_tone = _as_float(response_json.get("off_tone_fraction"), 8.0)
        size_dev = _as_float(response_json.get("size_deviation"), 8.0)
        shape_defect = _as_float(response_json.get("shape_defect_fraction"), 8.0)
        broken_grain = _as_float(response_json.get("broken_grain_percent"), 2.0)
        foreign_matter = _as_float(response_json.get("foreign_matter_percent"), 0.5)
        other_grains = _as_float(response_json.get("other_edible_grains_percent"), 0.0)
        bimodal_color = _as_bool(response_json.get("bimodal_color_detected", False))
        mold_visible = _as_bool(response_json.get("mold_visible", False))
        visible_defects = [item.lower() for item in _as_list(response_json.get("visible_defects"))]

        darkness = _as_float(
            physics_proxies.get("lab_features", {}).get("color_darkness_index"),
            0.0,
        )
        clumping = _as_float(physics_proxies.get("clumping", {}).get("density"), 0.0)
        uniformity = _as_float(physics_proxies.get("uniformity_score"), 70.0)
        roughness = _as_float(physics_proxies.get("roughness_score"), 50.0)
        grain_coverage = _as_float(physics_proxies.get("grain_mask_coverage"), 0.5)

        moisture_label = str(getattr(moisture_risk, "value", moisture_risk or "")).upper()
        calibrated_moisture = _as_float(moisture_percent, -1.0)
        damaged_like = max(broken_grain, shape_defect)
        metric_scores = {
            "off_tone_fraction": _score_max_metric(off_tone, t.off_tone_a_max, t.off_tone_c_min, 35.0),
            "size_deviation": _score_max_metric(size_dev, t.size_dev_a_max, t.size_dev_c_min, 30.0),
            "shape_defect_fraction": _score_max_metric(shape_defect, t.shape_defect_a_max, t.shape_defect_c_min, 25.0),
            "broken_grain_percent": _score_max_metric(broken_grain, t.damaged_a_max, t.broken_c_min, t.damaged_c_max),
            "foreign_matter_percent": _score_max_metric(foreign_matter, t.foreign_a_max, t.foreign_b_max, t.foreign_c_max),
            "other_edible_grains_percent": _score_max_metric(other_grains, t.other_grain_a_max, t.other_grain_b_max, t.other_grain_c_max),
        }
        metric_details = {
            name: {"value": round(value, 3), "score": metric_scores[name]}
            for name, value in {
                "off_tone_fraction": off_tone,
                "size_deviation": size_dev,
                "shape_defect_fraction": shape_defect,
                "broken_grain_percent": broken_grain,
                "foreign_matter_percent": foreign_matter,
                "other_edible_grains_percent": other_grains,
            }.items()
        }
        metric_weights = {
            "off_tone_fraction": 18,
            "size_deviation": 14,
            "shape_defect_fraction": 14,
            "broken_grain_percent": 12,
            "foreign_matter_percent": 22,
            "other_edible_grains_percent": 8,
        }
        grain_score_base = _weighted_average(metric_scores, metric_weights)
        moisture_score_base = (
            _score_max_metric(calibrated_moisture, t.moisture_a_max, t.moisture_b_max, t.moisture_c_max)
            if calibrated_moisture >= 0
            else _risk_score(moisture_risk)
        )

        def _decision_scores(
            final_grade: str,
            grain_grade: str,
            penalty_reasons: List[str],
        ) -> tuple[int, Dict[str, Any]]:
            penalties = [
                {"name": f"penalty_{index + 1}", "points": 12, "reason": reason}
                for index, reason in enumerate(penalty_reasons)
            ]
            raw_final = min(grain_score_base, moisture_score_base) - sum(
                int(item["points"]) for item in penalties
            )
            if final_grade == "A":
                final_score = _clip_score(raw_final, low=90, high=100)
            elif final_grade == "B":
                final_score = _clip_score(raw_final, low=75, high=89)
            else:
                final_score = _clip_score(raw_final, low=20, high=74)
            breakdown = _score_breakdown_payload(
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                metrics=metric_details,
                penalties=penalties,
                rule_source="ragi_fallback_rules",
            )
            return final_score, breakdown

        hazard_terms = (
            "mold",
            "mould",
            "fungus",
            "fungal",
            "insect",
            "weevil",
            "webbing",
            "stone",
            "glass",
            "metal",
            "deleterious",
            "obnoxious",
        )
        visible_hazard = mold_visible or any(
            any(term in defect for term in hazard_terms) for defect in visible_defects
        )

        hard_reasons: List[str] = []
        rule_hits: List[str] = []

        if visible_hazard:
            hard_reasons.append("Hard reject gate: visible mould, insect, stone, or deleterious material")
            rule_hits.append("hazard_gate")
        if foreign_matter > t.foreign_c_max:
            hard_reasons.append(f"Foreign matter {foreign_matter:.2f}% exceeds {t.foreign_c_max:.2f}%")
            rule_hits.append("foreign_matter_reject")
        if other_grains > t.other_grain_c_max:
            hard_reasons.append(f"Other edible grains {other_grains:.2f}% exceeds {t.other_grain_c_max:.2f}%")
            rule_hits.append("other_grains_reject")
        if damaged_like > t.damaged_c_max:
            hard_reasons.append(f"Defect load {damaged_like:.2f}% exceeds {t.damaged_c_max:.2f}%")
            rule_hits.append("damaged_reject")
        if calibrated_moisture > t.moisture_c_max:
            hard_reasons.append(f"Moisture {calibrated_moisture:.1f}% exceeds {t.moisture_c_max:.1f}%")
            rule_hits.append("moisture_reject")
        elif moisture_label == "CRITICAL":
            hard_reasons.append("Critical proxy moisture risk")
            rule_hits.append("moisture_reject")

        if hard_reasons:
            grain_grade = "C" if any("Moisture" not in reason and "moisture" not in reason for reason in hard_reasons) else _score_to_grade(grain_score_base)
            final_score, breakdown = _decision_scores("C", grain_grade, hard_reasons)
            return RuleDecision(
                grade="C",
                score=final_score,
                reject=True,
                reject_reasons=hard_reasons,
                broken_grain=broken_grain,
                foreign_matter=foreign_matter,
                uniformity=min(uniformity, 35.0),
                mold_visible=mold_visible or visible_hazard,
                rule_hits=rule_hits,
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        proxy_quality_risk = (
            clumping > 0.32
            or darkness > 62
            or uniformity < 52
            or grain_coverage < 0.12
        )
        proxy_downgrade = (
            clumping > 0.18
            or darkness > 50
            or uniformity < 68
            or roughness < 25
        )
        proxy_grade_a_ok = (
            clumping < 0.12
            and darkness < 45
            and uniformity >= 72
            and roughness >= 20
            and grain_coverage >= 0.15
        )

        moisture_blocks_a = (
            moisture_label in {"MODERATE", "HIGH", "CRITICAL"}
            or calibrated_moisture > t.moisture_a_max
        )
        moisture_forces_c = (
            moisture_label == "HIGH"
            or calibrated_moisture > t.moisture_b_max
        )

        grade_c_reasons: List[str] = []
        if moisture_forces_c:
            grade_c_reasons.append("Moisture is above Grade B range")
            rule_hits.append("moisture_c")
        if foreign_matter > t.foreign_b_max:
            grade_c_reasons.append("Foreign matter is in Grade C range")
            rule_hits.append("foreign_matter_c")
        if other_grains > t.other_grain_b_max:
            grade_c_reasons.append("Other edible grains are in Grade C range")
            rule_hits.append("other_grains_c")
        if damaged_like > t.damaged_b_max:
            grade_c_reasons.append("Defect load is in Grade C range")
            rule_hits.append("damaged_c")
        if (
            off_tone > t.off_tone_c_min
            or size_dev > t.size_dev_c_min
            or shape_defect > t.shape_defect_c_min
            or broken_grain > t.broken_c_min
            or bimodal_color
            or proxy_quality_risk
            or (llm_grade == "C" and proxy_downgrade)
        ):
            grade_c_reasons.append("Visual defect thresholds indicate Grade C")
            rule_hits.append("visual_c")

        if grade_c_reasons:
            visual_reasons = [reason for reason in grade_c_reasons if not reason.lower().startswith("moisture")]
            grain_grade = "C" if visual_reasons else _score_to_grade(grain_score_base)
            final_score, breakdown = _decision_scores("C", grain_grade, grade_c_reasons)
            return RuleDecision(
                grade="C",
                score=final_score,
                reject=False,
                reject_reasons=list(dict.fromkeys(grade_c_reasons)),
                broken_grain=broken_grain,
                foreign_matter=foreign_matter,
                uniformity=min(uniformity, 55.0),
                mold_visible=False,
                rule_hits=list(dict.fromkeys(rule_hits)),
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        grade_a_ok = (
            llm_grade == "A"
            and not moisture_blocks_a
            and off_tone < t.off_tone_a_max
            and size_dev < t.size_dev_a_max
            and shape_defect < t.shape_defect_a_max
            and broken_grain <= t.damaged_a_max
            and foreign_matter <= t.foreign_a_max
            and other_grains <= t.other_grain_a_max
            and not bimodal_color
            and proxy_grade_a_ok
        )
        if grade_a_ok:
            final_score, breakdown = _decision_scores("A", "A", [])
            return RuleDecision(
                grade="A",
                score=final_score,
                reject=False,
                reject_reasons=[],
                broken_grain=broken_grain,
                foreign_matter=foreign_matter,
                uniformity=max(uniformity, 90.0),
                mold_visible=False,
                rule_hits=["grade_a_all_gates_pass"],
                grain_grade="A",
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        b_reasons: List[str] = []
        if moisture_blocks_a:
            b_reasons.append("Moisture blocks Grade A")
            rule_hits.append("moisture_b")
        if foreign_matter > t.foreign_a_max:
            b_reasons.append("Foreign matter above premium range")
            rule_hits.append("foreign_matter_b")
        if damaged_like > t.damaged_a_max:
            b_reasons.append("Defect load above premium range")
            rule_hits.append("damaged_b")
        if proxy_downgrade or llm_grade != "A":
            b_reasons.append("Lot is usable but not premium")
            rule_hits.append("visual_b")

        grain_grade = "B" if b_reasons else _score_to_grade(grain_score_base)
        final_score, breakdown = _decision_scores("B", grain_grade, b_reasons)
        return RuleDecision(
            grade="B",
            score=final_score,
            reject=False,
            reject_reasons=[],
            broken_grain=broken_grain,
            foreign_matter=foreign_matter,
            uniformity=float(max(55.0, min(uniformity, 85.0))),
            mold_visible=False,
            rule_hits=list(dict.fromkeys(rule_hits or b_reasons)),
            grain_grade=grain_grade,
            grain_score=grain_score_base,
            moisture_score=moisture_score_base,
            final_score=final_score,
            score_breakdown=breakdown,
        )


def normalize_crop_name(crop_type: Any) -> str:
    """Normalize crop labels used by UI, datasets, and rule files."""
    text = str(crop_type or "").strip().lower().replace("-", " ").replace("_", " ")
    text = " ".join(text.split())
    if not text or text == "auto":
        return ""
    if text in {
        "ragi",
        "finger millet",
        "finger millets",
        "fingermillet",
        "fingermillets",
        "ragi / fingermillets",
        "ragi/fingermillets",
        "ragi/fingermillet",
    }:
        return "finger_millets"
    if text in {"bajari", "bajri", "bajara", "bajra", "pearl millet", "pearlmillet"}:
        return "bajra"
    if text in {"rice", "paddy", "dhan"}:
        return "rice"
    return text.replace(" ", "_")


@dataclass(frozen=True)
class CropMetricRule:
    """One typed metric from a crop grading YAML file."""

    name: str
    direction: str
    grade_a: float
    grade_b: float
    grade_c: float

    def grade_for_value(self, value: float) -> str:
        if self.direction == "min":
            if value < self.grade_c:
                return "REJECT"
            if value < self.grade_b:
                return "C"
            if value < self.grade_a:
                return "B"
            return "A"
        if value > self.grade_c:
            return "REJECT"
        if value > self.grade_b:
            return "C"
        if value > self.grade_a:
            return "B"
        return "A"

    def summary(self) -> str:
        op = ">=" if self.direction == "min" else "<="
        return (
            f"{self.name}: A {op} {self.grade_a:g}, "
            f"B {op} {self.grade_b:g}, C {op} {self.grade_c:g}"
        )


@dataclass(frozen=True)
class CropRuleSet:
    """Typed crop rule set loaded from knowledge/rag/crop_knowledge/grading_rules."""

    crop: str
    metrics: Dict[str, CropMetricRule]
    weights: Dict[str, float] = field(default_factory=dict)
    grade_a_score: int = 90
    grade_b_score: int = 75
    grade_c_score: int = 60

    def describe(self, limit: int = 14) -> List[str]:
        return [rule.summary() for rule in list(self.metrics.values())[:limit]]


def _extract_rule_blocks(text: str) -> Dict[str, Dict[str, float]]:
    """Parse the repository's compact YAML rule files without adding PyYAML."""
    metrics: Dict[str, Dict[str, float]] = {}
    current_metric = ""
    in_grading_engine = False
    for raw_line in text.splitlines():
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if indent == 0:
            in_grading_engine = line == "grading_engine:"
            current_metric = ""
            continue

        if not in_grading_engine:
            continue

        metric_match = re.match(r"([a-zA-Z_][a-zA-Z0-9_]*):\s*$", line)
        if metric_match and indent <= 2 and not line.startswith("grade_"):
            current_metric = metric_match.group(1)
            metrics.setdefault(current_metric, {})
            continue

        grade_match = re.match(
            r"grade_([abcABC]):\s*\{\s*(max|min)\s*:\s*(-?\d+(?:\.\d+)?)\s*\}",
            line,
        )
        if grade_match and current_metric:
            grade = grade_match.group(1).lower()
            bound = grade_match.group(2).lower()
            value = float(grade_match.group(3))
            metrics.setdefault(current_metric, {})[f"grade_{grade}_{bound}"] = value
    return metrics


def _extract_score_blocks(text: str) -> Dict[str, int]:
    scores: Dict[str, int] = {}
    in_grade_decision = False
    for raw_line in text.splitlines():
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if indent == 0:
            in_grade_decision = line == "grade_decision:"
            continue
        if not in_grade_decision:
            continue
        match = re.match(r"(grade_[abcABC]_score):\s*(\d+)\s*$", line)
        if match:
            scores[match.group(1).lower()] = int(match.group(2))
    return scores


def _extract_weight_blocks(text: str) -> Dict[str, float]:
    weights: Dict[str, float] = {}
    in_weights = False
    for raw_line in text.splitlines():
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if indent == 0:
            in_weights = line == "scoring_weights:"
            continue
        if not in_weights:
            continue
        match = re.match(r"([a-zA-Z_][a-zA-Z0-9_]*):\s*(-?\d+(?:\.\d+)?)\s*$", line)
        if match:
            weights[match.group(1)] = float(match.group(2))
    return weights


def _build_rule_set_from_yaml(path: Path, crop_name: str) -> Optional[CropRuleSet]:
    if not path.exists():
        return None
    blocks = _extract_rule_blocks(path.read_text(encoding="utf-8"))
    if not blocks:
        return None

    metrics: Dict[str, CropMetricRule] = {}
    for metric, values in blocks.items():
        direction = "max" if "grade_a_max" in values else "min"
        suffix = direction
        required = [f"grade_a_{suffix}", f"grade_b_{suffix}", f"grade_c_{suffix}"]
        if not all(key in values for key in required):
            continue
        metrics[metric] = CropMetricRule(
            name=metric,
            direction=direction,
            grade_a=float(values[required[0]]),
            grade_b=float(values[required[1]]),
            grade_c=float(values[required[2]]),
        )

    if not metrics:
        return None

    text = path.read_text(encoding="utf-8")
    scores = _extract_score_blocks(text)
    weights = _extract_weight_blocks(text)
    return CropRuleSet(
        crop=crop_name,
        metrics=metrics,
        weights=weights,
        grade_a_score=scores.get("grade_a_score", 90),
        grade_b_score=scores.get("grade_b_score", 75),
        grade_c_score=scores.get("grade_c_score", 60),
    )


class CropRuleEngine:
    """Crop-aware deterministic threshold router backed by crop rule YAML files."""

    RULE_FILE_BY_CROP = {
        "finger_millets": "fingermillet_rules.yaml",
        "bajra": "bajari_rules.yaml",
        "rice": "rice_rules.yaml",
    }

    def __init__(self, rules_dir: Optional[str | Path] = None):
        default_rules_dir = RAG_DOCS_DIR / "crop_knowledge" / "grading_rules"
        if not default_rules_dir.exists():
            default_rules_dir = LEGACY_RAG_DOCS_DIR / "crop_knowledge" / "grading_rules"
        self.rules_dir = Path(rules_dir) if rules_dir else default_rules_dir
        self._fallback = RagiRuleEngine()
        self._rule_sets: Dict[str, Optional[CropRuleSet]] = {}

    def _rule_set_for_crop(self, crop_type: Any) -> Optional[CropRuleSet]:
        crop = normalize_crop_name(crop_type)
        if not crop:
            return None
        if crop in self._rule_sets:
            return self._rule_sets[crop]
        filename = self.RULE_FILE_BY_CROP.get(crop)
        rule_set = (
            _build_rule_set_from_yaml(self.rules_dir / filename, crop)
            if filename
            else None
        )
        self._rule_sets[crop] = rule_set
        return rule_set

    def describe_crop_rules(self, crop_type: Any) -> List[str]:
        rule_set = self._rule_set_for_crop(crop_type)
        if not rule_set:
            return []
        return rule_set.describe()

    def moisture_thresholds(self, crop_type: Any) -> tuple[float, float, float]:
        """Return A/B/C maximum moisture thresholds for the selected crop."""
        rule_set = self._rule_set_for_crop(crop_type)
        if rule_set:
            rule = rule_set.metrics.get("moisture")
            if rule and rule.direction == "max":
                return rule.grade_a, rule.grade_b, rule.grade_c
        fallback = self._fallback.thresholds
        return fallback.moisture_a_max, fallback.moisture_b_max, fallback.moisture_c_max

    def _response_float(
        self,
        response_json: Dict[str, Any],
        keys: Iterable[str],
        default: Optional[float] = None,
    ) -> Optional[float]:
        for key in keys:
            if key in response_json and response_json.get(key) is not None:
                return _as_float(response_json.get(key), default if default is not None else 0.0)
        return default

    def _metric_value(
        self,
        metric: str,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        moisture_percent: Optional[float],
    ) -> float:
        uniformity = _as_float(physics_proxies.get("uniformity_score"), 70.0)
        if metric == "moisture":
            return _as_float(moisture_percent, 0.0)
        if metric == "broken_grains":
            return self._response_float(
                response_json,
                ("broken_grains_percent", "broken_grain_percent"),
                0.0,
            ) or 0.0
        if metric == "damaged_grains":
            return self._response_float(
                response_json,
                ("damaged_grains_percent", "damaged_grain_percent"),
                0.0,
            ) or 0.0
        if metric == "chalky_grains":
            return self._response_float(
                response_json,
                ("chalky_grains_percent", "chalky_grain_percent"),
                0.0,
            ) or 0.0
        if metric == "foreign_matter":
            return self._response_float(
                response_json,
                ("foreign_matter_percent", "foreign_matter"),
                0.0,
            ) or 0.0
        if metric == "organic_extraneous_matter":
            return self._response_float(
                response_json,
                ("organic_extraneous_matter_percent", "organic_extraneous_matter"),
                self._response_float(response_json, ("foreign_matter_percent",), 0.0),
            ) or 0.0
        if metric == "inorganic_extraneous_matter":
            return self._response_float(
                response_json,
                ("inorganic_extraneous_matter_percent", "inorganic_extraneous_matter"),
                0.0,
            ) or 0.0
        if metric == "other_edible_grains":
            return self._response_float(
                response_json,
                ("other_edible_grains_percent", "other_edible_grains"),
                0.0,
            ) or 0.0
        if metric == "immature_grains":
            return self._response_float(
                response_json,
                ("immature_grains_percent", "immature_grains"),
                0.0,
            ) or 0.0
        if metric == "weevilled_grains":
            visible_defects = " ".join(_as_list(response_json.get("visible_defects"))).lower()
            default = 5.0 if any(term in visible_defects for term in ("weevil", "insect")) else 0.0
            return self._response_float(
                response_json,
                ("weevilled_grains_percent", "weevilled_grains"),
                default,
            ) or 0.0
        if metric == "color_uniformity":
            return self._response_float(
                response_json,
                ("color_uniformity_score",),
                self._response_float(response_json, ("off_tone_fraction",), None),
            ) if "color_uniformity_score" in response_json else (
                100.0 - _as_float(response_json.get("off_tone_fraction"), 100.0 - uniformity)
            )
        if metric == "size_uniformity":
            return self._response_float(
                response_json,
                ("size_uniformity_score",),
                100.0 - _as_float(response_json.get("size_deviation"), 100.0 - uniformity),
            ) or 0.0
        if metric == "shape_uniformity":
            return self._response_float(
                response_json,
                ("shape_uniformity_score",),
                100.0 - _as_float(response_json.get("shape_defect_fraction"), 100.0 - uniformity),
            ) or 0.0
        if metric == "surface_defects":
            return self._response_float(
                response_json,
                ("surface_defects_percent", "surface_defects"),
                0.0,
            ) or 0.0
        return self._response_float(response_json, (f"{metric}_percent", metric), 0.0) or 0.0

    def _metric_score(self, rule: CropMetricRule, value: float) -> int:
        if rule.direction == "min":
            return _score_min_metric(value, rule.grade_a, rule.grade_b, rule.grade_c)
        return _score_max_metric(value, rule.grade_a, rule.grade_b, rule.grade_c)

    def _weights_for_metrics(self, rule_set: CropRuleSet) -> Dict[str, float]:
        weights: Dict[str, float] = {}
        purity_metrics = {
            "foreign_matter",
            "organic_extraneous_matter",
            "inorganic_extraneous_matter",
            "other_edible_grains",
        }
        present_purity = purity_metrics.intersection(rule_set.metrics)
        split_purity = (
            float(rule_set.weights.get("purity", 0.0)) / len(present_purity)
            if present_purity
            else 0.0
        )
        for metric in rule_set.metrics:
            if metric in rule_set.weights:
                weights[metric] = float(rule_set.weights[metric])
            elif metric in purity_metrics and split_purity > 0:
                weights[metric] = split_purity
            else:
                weights[metric] = 1.0
        return weights

    def _evaluate_crop_rules(
        self,
        rule_set: CropRuleSet,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        moisture_risk: Any = None,
        moisture_percent: Optional[float] = None,
    ) -> RuleDecision:
        llm_grade = _grade_value(response_json.get("quality_grade", "B"))
        llm_score = _as_float(response_json.get("quality_score"), 0.0)
        mold_visible = _as_bool(response_json.get("mold_visible", False))
        visible_defects = [item.lower() for item in _as_list(response_json.get("visible_defects"))]
        hazard_terms = (
            "mold",
            "mould",
            "fungus",
            "fungal",
            "insect",
            "weevil",
            "webbing",
            "stone",
            "glass",
            "metal",
            "deleterious",
            "obnoxious",
        )
        visible_hazard = mold_visible or any(
            any(term in defect for term in hazard_terms) for defect in visible_defects
        )

        values: Dict[str, float] = {}
        metric_grades: Dict[str, str] = {}
        metric_scores: Dict[str, int] = {}
        metric_details: Dict[str, Dict[str, Any]] = {}
        hard_reasons: List[str] = []
        grade_c_reasons: List[str] = []
        b_reasons: List[str] = []
        rule_hits: List[str] = []
        hard_reject_metrics = {
            "moisture",
            "foreign_matter",
            "organic_extraneous_matter",
            "inorganic_extraneous_matter",
            "weevilled_grains",
        }

        if visible_hazard:
            hard_reasons.append("Hard reject gate: visible mould, insect, stone, or deleterious material")
            rule_hits.extend(["hazard_gate", f"{rule_set.crop}_hazard_gate"])

        moisture_label = str(getattr(moisture_risk, "value", moisture_risk or "")).upper()
        for metric, rule in rule_set.metrics.items():
            value = self._metric_value(metric, response_json, physics_proxies, moisture_percent)
            values[metric] = value
            metric_grade = rule.grade_for_value(value)
            metric_score = self._metric_score(rule, value)

            if metric == "moisture" and moisture_percent is None:
                if moisture_label == "CRITICAL":
                    metric_grade = "REJECT"
                elif moisture_label == "HIGH":
                    metric_grade = "C"
                elif moisture_label == "MODERATE":
                    metric_grade = "B"
                metric_score = _risk_score(moisture_risk)

            metric_grades[metric] = metric_grade
            metric_scores[metric] = metric_score
            metric_details[metric] = {
                "value": round(value, 3),
                "grade": metric_grade,
                "score": metric_score,
                "thresholds": {
                    "direction": rule.direction,
                    "grade_a": rule.grade_a,
                    "grade_b": rule.grade_b,
                    "grade_c": rule.grade_c,
                },
            }

            if metric_grade == "REJECT" and metric in hard_reject_metrics:
                comparator = "below" if rule.direction == "min" else "exceeds"
                hard_reasons.append(
                    f"{metric.replace('_', ' ').title()} {value:.2f}% {comparator} Grade C threshold {rule.grade_c:.2f}"
                )
                rule_hits.extend([f"{metric}_reject", f"{rule_set.crop}_{metric}_reject"])
            elif metric_grade == "REJECT":
                grade_c_reasons.append(
                    f"{metric.replace('_', ' ').title()} is outside Grade C range; grain health penalty"
                )
                rule_hits.extend([f"{metric}_health_penalty", f"{rule_set.crop}_{metric}_health_penalty"])
            elif metric_grade == "C":
                grade_c_reasons.append(f"{metric.replace('_', ' ').title()} is in Grade C range")
                rule_hits.extend([f"{metric}_c", f"{rule_set.crop}_{metric}_c"])
            elif metric_grade == "B":
                b_reasons.append(f"{metric.replace('_', ' ').title()} blocks Grade A")
                rule_hits.extend([f"{metric}_b", f"{rule_set.crop}_{metric}_b"])

        if moisture_label == "CRITICAL" and "moisture" not in rule_set.metrics:
            hard_reasons.append("Critical proxy moisture risk")
            rule_hits.append("moisture_reject")
            metric_scores["moisture"] = _risk_score(moisture_risk)
            metric_details["moisture"] = {
                "value": moisture_percent,
                "grade": "REJECT",
                "score": metric_scores["moisture"],
                "thresholds": {"source": "moisture_risk"},
            }

        broken = values.get("broken_grains", _as_float(response_json.get("broken_grain_percent"), 0.0))
        foreign = values.get(
            "foreign_matter",
            values.get("organic_extraneous_matter", 0.0)
            + values.get("inorganic_extraneous_matter", 0.0),
        )
        uniformity_values = [
            values[key]
            for key in ("color_uniformity", "size_uniformity", "shape_uniformity")
            if key in values
        ]
        uniformity = (
            sum(uniformity_values) / len(uniformity_values)
            if uniformity_values
            else _as_float(physics_proxies.get("uniformity_score"), 70.0)
        )
        weights = self._weights_for_metrics(rule_set)
        grain_metric_scores = {
            metric: score
            for metric, score in metric_scores.items()
            if metric != "moisture"
        }
        grain_metric_weights = {
            metric: weight
            for metric, weight in weights.items()
            if metric != "moisture"
        }
        grain_score_base = _weighted_average(grain_metric_scores, grain_metric_weights)
        moisture_score_base = metric_scores.get("moisture", _risk_score(moisture_risk))

        def _decision_scores(
            final_grade: str,
            grain_grade: str,
            penalty_reasons: List[str],
        ) -> tuple[int, Dict[str, Any]]:
            penalties = []
            for index, reason in enumerate(penalty_reasons):
                lowered = reason.lower()
                if "blocks grade a" in lowered:
                    points = 3
                elif "grade c range" in lowered:
                    points = 5
                elif "grain health penalty" in lowered:
                    points = 7
                else:
                    points = 10
                penalties.append({"name": f"penalty_{index + 1}", "points": points, "reason": reason})
            raw_final = min(grain_score_base, moisture_score_base) - sum(
                int(item["points"]) for item in penalties
            )
            final_score = _clamp_score_to_grade(raw_final, final_grade)
            breakdown = _score_breakdown_payload(
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                metrics=metric_details,
                penalties=penalties,
                rule_source=f"{rule_set.crop}_yaml_rules",
            )
            return final_score, breakdown

        if hard_reasons:
            visual_hard = [
                reason for reason in hard_reasons if not reason.lower().startswith("moisture")
            ]
            grain_grade = "C" if visual_hard else _score_to_grade(grain_score_base)
            final_score, breakdown = _decision_scores("C", grain_grade, hard_reasons)
            return RuleDecision(
                grade="C",
                score=final_score,
                reject=True,
                reject_reasons=list(dict.fromkeys(hard_reasons)),
                broken_grain=broken,
                foreign_matter=foreign,
                uniformity=min(uniformity, 35.0),
                mold_visible=mold_visible or visible_hazard,
                rule_hits=list(dict.fromkeys(rule_hits)),
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        clumping = _as_float(physics_proxies.get("clumping", {}).get("density"), 0.0)
        darkness = _as_float(physics_proxies.get("lab_features", {}).get("color_darkness_index"), 0.0)
        roughness = _as_float(physics_proxies.get("roughness_score"), 50.0)
        grain_coverage = _as_float(physics_proxies.get("grain_mask_coverage"), 0.5)
        proxy_grade_a_ok = (
            clumping < 0.18
            and darkness < 58
            and uniformity >= 68
            and roughness >= 18
            and grain_coverage >= 0.10
        )
        moisture_c_reasons = [
            reason for reason in grade_c_reasons if reason.lower().startswith("moisture")
        ]
        grain_health_c_reasons = [
            reason for reason in grade_c_reasons if not reason.lower().startswith("moisture")
        ]
        rice_tolerated_visual_c_reasons = [
            reason
            for reason in grain_health_c_reasons
            if (
                rule_set.crop == "rice"
                and "outside grade c" not in reason.lower()
                and any(
                    term in reason.lower()
                    for term in (
                        "color uniformity",
                        "size uniformity",
                        "shape uniformity",
                    )
                )
            )
        ]
        rice_blocking_c_reasons = [
            reason
            for reason in grade_c_reasons
            if reason not in rice_tolerated_visual_c_reasons
        ]

        if moisture_c_reasons:
            grain_grade = _grade_from_score(grain_score_base)
            final_score, breakdown = _decision_scores("C", grain_grade, grade_c_reasons)
            return RuleDecision(
                grade="C",
                score=final_score,
                reject=False,
                reject_reasons=list(dict.fromkeys(grade_c_reasons)),
                broken_grain=broken,
                foreign_matter=foreign,
                uniformity=min(uniformity, 60.0),
                mold_visible=False,
                rule_hits=list(dict.fromkeys(rule_hits)),
                grain_grade=grain_grade,
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        grade_a_blocking_terms = (
            "moisture",
            "foreign matter",
            "organic extraneous",
            "inorganic extraneous",
            "other edible",
            "weevilled",
        )
        grade_a_blocking_reasons = [
            reason
            for reason in b_reasons
            if any(term in reason.lower() for term in grade_a_blocking_terms)
        ]
        tolerated_grade_a_reasons = [
            reason for reason in b_reasons if reason not in grade_a_blocking_reasons
        ]
        grade_a_score_gate_ok = (
            llm_grade != "C"
            and proxy_grade_a_ok
            and not grade_c_reasons
            and moisture_score_base >= 90
            and grain_score_base >= 88
            and not grade_a_blocking_reasons
            and len(tolerated_grade_a_reasons) <= 2
        )
        rice_low_moisture_a_gate_ok = (
            rule_set.crop == "rice"
            and llm_grade in {"A", "B"}
            and not rice_blocking_c_reasons
            and moisture_score_base >= 90
            and grain_score_base >= 78
            and llm_score >= 70
            and len(rice_tolerated_visual_c_reasons) <= 2
        )

        if grade_a_score_gate_ok or rice_low_moisture_a_gate_ok:
            grade_a_penalties = list(
                dict.fromkeys(tolerated_grade_a_reasons + rice_tolerated_visual_c_reasons)
            )
            final_score, breakdown = _decision_scores("A", "A", grade_a_penalties)
            return RuleDecision(
                grade="A",
                score=final_score,
                reject=False,
                reject_reasons=[],
                broken_grain=broken,
                foreign_matter=foreign,
                uniformity=max(uniformity, 88.0),
                mold_visible=False,
                rule_hits=list(dict.fromkeys(rule_hits + [f"{rule_set.crop}_grade_a_score_gate_pass"])),
                grain_grade="A",
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        severe_grain_c = (
            grain_score_base < 68
            and (
                len(grain_health_c_reasons) >= 3
                or llm_grade == "C"
            )
        )
        if severe_grain_c:
            final_score, breakdown = _decision_scores("C", "C", grade_c_reasons)
            return RuleDecision(
                grade="C",
                score=final_score,
                reject=False,
                reject_reasons=list(dict.fromkeys(grade_c_reasons)),
                broken_grain=broken,
                foreign_matter=foreign,
                uniformity=min(uniformity, 60.0),
                mold_visible=False,
                rule_hits=list(dict.fromkeys(rule_hits)),
                grain_grade="C",
                grain_score=grain_score_base,
                moisture_score=moisture_score_base,
                final_score=final_score,
                score_breakdown=breakdown,
            )

        if grain_health_c_reasons:
            b_reasons.extend(grain_health_c_reasons)
        if llm_grade != "A":
            b_reasons.append("Lot is usable but not premium")
            rule_hits.append("visual_b")

        grain_grade = "B" if b_reasons else _grade_from_score(grain_score_base)
        final_score, breakdown = _decision_scores("B", grain_grade, b_reasons)
        return RuleDecision(
            grade="B",
            score=final_score,
            reject=False,
            reject_reasons=[],
            broken_grain=broken,
            foreign_matter=foreign,
            uniformity=float(max(55.0, min(uniformity, 85.0))),
            mold_visible=False,
            rule_hits=list(dict.fromkeys(rule_hits or b_reasons)),
            grain_grade=grain_grade,
            grain_score=grain_score_base,
            moisture_score=moisture_score_base,
            final_score=final_score,
            score_breakdown=breakdown,
        )

    def evaluate(
        self,
        response_json: Dict[str, Any],
        physics_proxies: Dict[str, Any],
        moisture_risk: Any = None,
        moisture_percent: Optional[float] = None,
        moisture_calibrated: bool = True,
        crop_type: Any = None,
    ) -> RuleDecision:
        rule_set = self._rule_set_for_crop(crop_type)
        if rule_set:
            return self._evaluate_crop_rules(
                rule_set=rule_set,
                response_json=response_json,
                physics_proxies=physics_proxies,
                moisture_risk=moisture_risk,
                moisture_percent=moisture_percent,
            )
        return self._fallback.evaluate(
            response_json=response_json,
            physics_proxies=physics_proxies,
            moisture_risk=moisture_risk,
            moisture_percent=moisture_percent,
            moisture_calibrated=moisture_calibrated,
        )
