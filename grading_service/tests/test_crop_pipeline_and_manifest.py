"""Tests for crop-aware metadata and crop dataset manifest validation."""

from __future__ import annotations

import pytest
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

from PIL import Image

from ai_grain_grade.feedback import FeedbackCollector, GradingFeedbackItem
from ai_grain_grade.vision_rag_pipeline import (
    GradingResult,
    MoistureRisk,
    QualityGrade,
    VisionRAGPipeline,
)
from scripts.build_crop_dataset_manifest import build_manifest, emit_training_artifacts


def _write_jpeg_entry(zf: ZipFile, member: str, color: tuple[int, int, int] = (100, 70, 40)) -> None:
    """Create a tiny in-memory JPEG for deterministic zip fixtures."""
    buffer = BytesIO()
    Image.new("RGB", (32, 32), color=color).save(buffer, format="JPEG")
    zf.writestr(member, buffer.getvalue())


def _make_image_archive(path: Path, members: dict[str, bool]) -> None:
    """
    Create a synthetic archive for manifest tests.

    `members` maps arcname -> is_image
    """
    with ZipFile(path, "w") as archive:
        for member, is_image in members.items():
            if is_image:
                _write_jpeg_entry(archive, member)
            else:
                archive.writestr(member, "metadata entry")


def _fake_physics_proxies() -> dict[str, object]:
    return {
        "lab_features": {"color_darkness_index": 38.0},
        "clumping": {"density": 0.08},
        "uniformity_score": 85.0,
        "texture_entropy": 3.8,
        "roughness_score": 28.0,
        "grain_mask_coverage": 0.78,
    }


def test_infer_carries_crop_metadata_into_result(tmp_path):
    """selected_crop fields must persist on GradingResult for downstream consumers."""
    image = Image.new("RGB", (24, 24), color=(90, 60, 50))
    proxy = {
        "grain_mask_coverage": 0.62,
        "uniformity_score": 82.0,
        "lab_features": {"color_darkness_index": 28.0},
        "clumping": {"density": 0.08},
        "roughness_score": 43.0,
        "texture_entropy": 2.1,
        "specular_highlights_ratio": 0.04,
    }

    with BytesIO() as image_buffer:
        image.save(image_buffer, format="JPEG")
        image_path = tmp_path / "temp_ragi_crop_test.jpg"
        image_path.write_bytes(image_buffer.getvalue())

        pipeline = VisionRAGPipeline(
            qwen_provider="dashscope",
            qwen_model="qwen3-vl-plus",
            qwen_base_url="https://example.test/compatible-mode/v1",
            qwen_api_key="test-token",
            rag_retrieval_mode="lexical",
        )
    original_pass1 = pipeline._pass1_safety_gate
    original_pass2 = pipeline._pass2_rag_grading

    try:

        def _fake_pass2(
            image_path: str,
            physics_proxies,
            timestamp: str,
            crop_type=None,
            selected_crop=None,
            selected_variety=None,
            selected_crop_confidence=0.0,
            selection_source: str = "default",
            crop_route=None,
            measured_moisture_percent=None,
            moisture_source: str = "grain_proxy",
            moisture_ocr_confidence=None,
        ):
            assert crop_type == "rice"
            assert selected_crop == "rice"
            assert selected_variety == "Basmati"
            assert selected_crop_confidence == 1.0
            assert selection_source == "manual"
            assert measured_moisture_percent == 12.4
            return GradingResult(
                quality_grade=QualityGrade.B,
                quality_score=82,
                reject_recommended=False,
                reject_reasons=["synthetic test"],
                broken_grain_percent=1.5,
                foreign_matter_percent=0.3,
                uniformity_score=82.0,
                mold_visible=False,
                moisture_risk=MoistureRisk.LOW,
                moisture_estimate_calibrated=True,
                moisture_percent_estimate=9.9,
                overall_confidence=86,
                pass1_confidence=88,
                pass2_confidence=85,
                timestamp=timestamp,
                model_version="qwen3-vl-plus",
                rag_chunks_used=4,
                selected_crop=selected_crop,
                selected_variety=selected_variety,
                selected_crop_confidence=selected_crop_confidence,
                selection_source=selection_source,
                measured_moisture_percent=measured_moisture_percent,
                moisture_source=moisture_source,
                moisture_ocr_confidence=moisture_ocr_confidence,
                applied_rules=[
                    {
                        "rule_id": "manual_crop_hint",
                        "rule_name": "Manual crop path",
                        "source_file": "ui_select",
                        "evidence": "User selected Rice.",
                        "rule_confidence": 100.0,
                    }
                ],
            )

        pipeline._pass1_safety_gate = lambda image_path, crop_route=None, crop_type=None: type(
            "SafetyFind",
            (object,),
            {"hazard_detected": False},
        )()
        pipeline._pass2_rag_grading = _fake_pass2

        result = pipeline.infer(
            str(image_path),
            proxy,
            crop_type="RICE",
            crop_variety="Basmati",
            measured_moisture_percent=12.4,
            moisture_source="moisture_meter_ocr",
            moisture_ocr_confidence=0.9,
        )

        assert result.selected_crop == "rice"
        assert result.selected_variety == "Basmati"
        assert result.selection_source == "manual"
        assert result.measured_moisture_percent == 12.4
        assert result.selected_crop_confidence == 1.0
        assert isinstance(result.applied_rules, list)
        assert len(result.applied_rules) == 1
        assert result.applied_rules[0]["rule_id"] == "manual_crop_hint"
    finally:
        if image_path.exists():
            image_path.unlink()
        pipeline._pass1_safety_gate = original_pass1
        pipeline._pass2_rag_grading = original_pass2


def test_manifest_collects_validation_issues_and_malformed_archives(tmp_path):
    """Manifesting should report non-image and malformed archive issues without aborting."""
    _make_image_archive(
        tmp_path / "Rice dataset.zip",
        {
            "Grade_A/rice_01.jpg": True,
            "notes.txt": False,
        },
    )

    # Archive with no image files at all
    _make_image_archive(
        tmp_path / "Bajra dataset.zip",
        {"README.txt": False},
    )

    # Corrupt archive body
    (tmp_path / "bad.zip").write_bytes(b"not-a-valid-zip")

    manifest = build_manifest(
        source_dir=tmp_path,
        seed=1337,
        train_ratio=0.8,
        require_labels=False,
    )

    assert manifest["totals"]["archives"] == 3
    assert manifest["totals"]["malformed_archives"] == 1
    assert manifest["totals"]["archives_without_images"] == 1
    assert "non_image_files:1" in manifest["archive_errors"]["Rice dataset.zip"]
    assert "no_image_files" in manifest["archive_errors"]["Bajra dataset.zip"]
    assert any("read_error" in issue for issue in manifest["archive_errors"]["bad.zip"])


def test_manifest_hard_validation_only_when_labels_required(tmp_path):
    """Only require_labels=True should fail hard when annotations are missing."""
    _make_image_archive(
        tmp_path / "Ragi dataset.zip",
        {
            "img_unlabeled.jpg": True,
        },
    )

    manifest = build_manifest(
        source_dir=tmp_path,
        seed=13,
        train_ratio=0.8,
        require_labels=False,
    )
    assert manifest["totals"]["label_unknown"] == 1

    with pytest.raises(RuntimeError, match="require_labels=True"):
        build_manifest(
            source_dir=tmp_path,
            seed=13,
            train_ratio=0.8,
            require_labels=True,
        )


def test_crop_prompt_includes_crop_context_in_rag_prompt():
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )
    rag_context: list[dict] = []
    feedback_context: list[dict] = []

    assert (
        "Grade this Rice batch"
        in pipeline._build_grading_prompt(_fake_physics_proxies(), rag_context, feedback_context, selected_crop="RICE")
    )
    assert (
        "chalky_grains: A <= 2"
        in pipeline._build_grading_prompt(_fake_physics_proxies(), rag_context, feedback_context, selected_crop="RICE")
    )
    assert (
        "finger millet"
        in pipeline._build_grading_prompt(_fake_physics_proxies(), rag_context, feedback_context, selected_crop="Ragi")
        .lower()
    )
    assert (
        "bajra"
        in pipeline._build_grading_prompt(_fake_physics_proxies(), rag_context, feedback_context, selected_crop="Bajra")
        .lower()
    )
    assert (
        "grain"
        in pipeline._build_grading_prompt(_fake_physics_proxies(), rag_context, feedback_context, selected_crop=None)
        .lower()
    )


def test_crop_prompt_includes_variety_and_machine_moisture():
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )

    prompt = pipeline._build_grading_prompt(
        _fake_physics_proxies(),
        [],
        [],
        selected_crop="rice",
        selected_variety="Basmati",
        measured_moisture_percent=13.6,
        moisture_source="moisture_meter_ocr",
    )

    assert "Selected variety: Basmati" in prompt
    assert "Authoritative moisture meter reading: 13.60%" in prompt
    assert "Choose exactly one final grade from A, B, or C" in prompt


def test_measured_moisture_overrides_visual_proxy_for_crop_rules():
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )
    response_json = {
        "quality_grade": "A",
        "broken_grains_percent": 1.0,
        "damaged_grains_percent": 0.5,
        "chalky_grains_percent": 0.5,
        "foreign_matter_percent": 0.05,
        "color_uniformity_score": 96.0,
        "size_uniformity_score": 93.0,
        "shape_uniformity_score": 92.0,
        "surface_defects_percent": 1.0,
        "mold_visible": False,
        "visible_defects": [],
    }
    proxies = pipeline._with_operator_context(
        _fake_physics_proxies(),
        selected_crop="rice",
        crop_variety="Basmati",
        measured_moisture_percent=13.6,
        moisture_source="moisture_meter_ocr",
        moisture_ocr_confidence=0.94,
    )
    moisture_risk, moisture_percent, is_calibrated = pipeline._resolve_moisture_measurement(
        proxies,
        crop_type="rice",
    )
    grade = pipeline._apply_grading_logic(
        response_json,
        proxies,
        moisture_risk=moisture_risk,
        moisture_percent=moisture_percent,
        moisture_calibrated=is_calibrated,
        crop_type="rice",
    )

    assert moisture_risk == MoistureRisk.HIGH
    assert moisture_percent == 13.6
    assert grade["grade"] == QualityGrade.C
    assert "rice_moisture_c" in grade["rule_hits"]


def test_fallback_grading_uses_crop_yaml_rule_path():
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )

    result = pipeline._fallback_grading(
        _fake_physics_proxies(),
        timestamp="2026-06-11T00:00:00+00:00",
        selected_crop="rice",
        selected_crop_confidence=1.0,
        selection_source="manual",
        route_meta={"fallback_used": True},
    )

    assert result.selected_crop == "rice"
    assert result.manual_review_required is True
    assert any(rule["rule_id"].startswith("rice_") for rule in result.applied_rules)
    assert any(rule["rule_id"] == "fallback_deterministic_rules" for rule in result.applied_rules)


def test_call_qwen_vision_routes_with_crop_fallback_metadata(tmp_path, monkeypatch):
    image = Image.new("RGB", (20, 20), color=(255, 230, 190))
    with BytesIO() as image_buffer:
        image.save(image_buffer, format="JPEG")
        image_path = tmp_path / "routing_probe.jpg"
        image_path.write_bytes(image_buffer.getvalue())

    class FakeResponse:
        def __init__(self, payload: dict) -> None:
            self._payload = payload

        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return self._payload

    class FakeClient:
        calls = 0

        def __init__(self, *_, **__):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def post(self, _endpoint: str, headers=None, json=None):  # noqa: A002
            FakeClient.calls += 1
            if FakeClient.calls == 1:
                raise RuntimeError("crop route unavailable")
            return FakeResponse(
                {
                    "choices": [
                        {
                            "message": {
                                "content": "{\"quality_grade\": \"A\", \"quality_score\": 90, \"off_tone_fraction\": 1.0, \"size_deviation\": 2.0, \"shape_defect_fraction\": 1.0, \"broken_grain_percent\": 1.0, \"foreign_matter_percent\": 0.5, \"other_edible_grains_percent\": 0.0, \"bimodal_color_detected\": false, \"mold_visible\": false, \"visible_defects\": [], \"model_confidence\": 75, \"brief_reason\": \"fallback check\"}",
                            }
                        }
                    ]
                }
            )

    monkeypatch.setattr(
        "ai_grain_grade.vision_rag_pipeline.httpx.Client",
        FakeClient,
    )

    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://default.example/compatible-mode/v1",
        qwen_api_key="default-token",
        rag_retrieval_mode="lexical",
    )
    response_text, route_meta = pipeline._call_qwen_vision(
        str(image_path),
        "Classify the grain sample.",
        max_tokens=10,
        crop_route={"provider": "dashscope", "model": "qwen-crop-rice", "base_url": "https://crop.example/compatible-mode/v1", "api_key": "crop-token"},
        include_route_metadata=True,
    )

    assert response_text.startswith("{\"quality_grade\":")
    assert route_meta["route_label"] == "default"
    assert route_meta["model"] == "qwen3-vl-plus"
    assert route_meta["fallback_used"] is True
    assert any("crop route" in item for item in route_meta["attempted_routes"])
    assert FakeClient.calls == 2


def test_call_qwen_vision_crop_route_success_is_not_fallback(tmp_path, monkeypatch):
    image = Image.new("RGB", (20, 20), color=(255, 230, 190))
    with BytesIO() as image_buffer:
        image.save(image_buffer, format="JPEG")
        image_path = tmp_path / "routing_success.jpg"
        image_path.write_bytes(image_buffer.getvalue())

    class FakeResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return {
                "choices": [
                    {
                        "message": {
                            "content": "{\"quality_grade\": \"A\", \"quality_score\": 90}"
                        }
                    }
                ]
            }

    class FakeClient:
        calls = 0

        def __init__(self, *_, **__):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def post(self, _endpoint: str, headers=None, json=None):  # noqa: A002
            FakeClient.calls += 1
            return FakeResponse()

    monkeypatch.setattr("ai_grain_grade.vision_rag_pipeline.httpx.Client", FakeClient)

    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://default.example/compatible-mode/v1",
        qwen_api_key="default-token",
        rag_retrieval_mode="lexical",
    )
    _response_text, route_meta = pipeline._call_qwen_vision(
        str(image_path),
        "Classify the grain sample.",
        max_tokens=10,
        crop_route={
            "provider": "dashscope",
            "model": "qwen-crop-rice",
            "base_url": "https://crop.example/compatible-mode/v1",
            "api_key": "crop-token",
        },
        include_route_metadata=True,
    )

    assert route_meta["route_label"] == "crop route"
    assert route_meta["fallback_used"] is False
    assert FakeClient.calls == 1


def test_repair_grading_json_uses_crop_route(monkeypatch):
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )
    captured: dict[str, object] = {}
    expected_route = {
        "provider": "dashscope",
        "model": "qwen-crop-bajra",
        "base_url": "https://crop.example/compatible-mode/v1",
    }

    def _fake_text_model(
        prompt: str,
        max_tokens: int = 180,
        crop_route: dict[str, str] | None = None,
        include_route_metadata: bool = False,
    ):
        captured["crop_route"] = crop_route or {}
        return "{\"quality_grade\": \"A\", \"quality_score\": 90, \"off_tone_fraction\": 2, \"size_deviation\": 3, \"shape_defect_fraction\": 2, \"broken_grain_percent\": 1, \"foreign_matter_percent\": 0.5, \"other_edible_grains_percent\": 0, \"bimodal_color_detected\": false, \"mold_visible\": false, \"visible_defects\": [], \"model_confidence\": 80, \"brief_reason\": \"repair used\"}"  # noqa: E501

    monkeypatch.setattr(pipeline, "_call_text_model", _fake_text_model)
    result = pipeline._repair_grading_json(
        "Model output failed to return strict JSON",
        _fake_physics_proxies(),
        crop_route=expected_route,
    )
    assert captured["crop_route"] == expected_route
    assert result["quality_grade"] == "A"


def test_recover_grading_fields_preserves_rice_specific_metrics_from_malformed_json():
    pipeline = VisionRAGPipeline(rag_retrieval_mode="lexical")
    raw_text = """
    {
      "quality_grade": "B",
      "quality_score": 72,
      "broken_grains_percent": 6,
      "damaged_grains_percent": 1.5,
      "chalky_grains_percent": 3.2,
      "foreign_matter_percent": 0.18,
      "color_uniformity_score": 82,
      "size_uniformity_score": 78,
      "shape_uniformity_score": 80,
      "surface_defects_percent": 4,
      "measured_moisture_percent": 9.8,
      "bimodal_color_detected": false,
      "mold_visible": false,
    """

    recovered = pipeline._recover_grading_fields_from_text(raw_text)

    assert recovered["quality_grade"] == "B"
    assert recovered["chalky_grains_percent"] == 3.2
    assert recovered["surface_defects_percent"] == 4
    assert recovered["broken_grains_percent"] == 6
    assert recovered["foreign_matter_percent"] == 0.18
    assert recovered["bimodal_color_detected"] is False
    assert recovered["mold_visible"] is False


def test_malformed_recovery_does_not_turn_mold_field_name_into_hazard():
    pipeline = VisionRAGPipeline(rag_retrieval_mode="lexical")
    raw_text = """
    {
      "quality_grade": "B",
      "quality_score": 72,
      "broken_grains_percent": 6,
      "damaged_grains_percent": 1.5,
      "chalky_grains_percent": 3.2,
      "foreign_matter_percent": 0.18,
      "organic_extraneous_matter_percent": 0.05,
      "inorganic_extraneous_matter_percent": 0.13,
      "color_uniformity_score": 78,
      "size_uniformity_score": 76,
      "shape_uniformity_score": 79,
      "surface_defects_percent": 4,
      "measured_moisture_percent": 8.8,
      "bimodal_color_detected": false,
      "mold_visible": false,
      "visible_defect
    """

    heuristic = pipeline._extract_grading_hints_from_text(raw_text, _fake_physics_proxies())
    recovered = pipeline._recover_grading_fields_from_text(raw_text)
    merged = pipeline._merge_recovered_grading_fields(heuristic, recovered)

    assert merged["mold_visible"] is False
    assert "mold" not in merged["visible_defects"]
    assert merged["foreign_matter_percent"] == 0.18
    assert merged["broken_grains_percent"] == 6
    assert merged["quality_grade"] == "B"


def test_manifest_records_quality_flags_for_validation(tmp_path):
    _make_image_archive(
        tmp_path / "Ragi dataset.zip",
        {
            "Grade_B/ragi_a.jpg": True,
            "ragi_flat.jpg": True,
            "notes.txt": False,
        },
    )

    manifest = build_manifest(
        source_dir=tmp_path,
        seed=13,
        train_ratio=0.7,
        require_labels=False,
    )

    rice_like_sample = [
        sample for sample in manifest["samples"] if sample["member_path"] == "ragi_flat.jpg"
    ][0]
    assert "missing_label" in rice_like_sample["quality_flags"]
    assert "flat_archive_path" in rice_like_sample["quality_flags"]

    grade_sample = next(
        sample for sample in manifest["samples"] if sample["member_path"] == "Grade_B/ragi_a.jpg"
    )
    assert "missing_label" not in grade_sample["quality_flags"]
    assert "flat_archive_path" not in grade_sample["quality_flags"]
    assert "no_image_files" not in manifest["archive_errors"]["Ragi dataset.zip"]
    assert any(
        "extension_profile:" in issue for issue in manifest["archive_errors"]["Ragi dataset.zip"]
    )


def test_manifest_label_and_crop_normalization_handle_grade_spacing(tmp_path):
    _make_image_archive(
        tmp_path / "Ragi dataset.zip",
        {
            "Grade A/ragi_a.jpg": True,
            "Grade-C/ragi_c.jpg": True,
        },
    )

    manifest = build_manifest(
        source_dir=tmp_path,
        seed=13,
        train_ratio=0.5,
        require_labels=True,
    )

    assert set(manifest["crops"]) == {"finger_millets"}
    labels = {sample["member_path"]: sample["label"] for sample in manifest["samples"]}
    assert labels["Grade A/ragi_a.jpg"] == "A"
    assert labels["Grade-C/ragi_c.jpg"] == "C"
    assert all("flat_archive_path" not in sample["quality_flags"] for sample in manifest["samples"])


def test_rag_context_promotes_finger_millet_alias_paths():
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-token",
        rag_retrieval_mode="lexical",
    )

    class FakeRag:
        def retrieve(self, _query, k=8):
            return [
                {
                    "source": "knowledge/rag/UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md",
                    "title": "generic",
                    "content": "generic rules",
                    "retrieval_score": 9.0,
                },
                {
                    "source": "knowledge/rag/crop_knowledge/FingerMillets/GPU45.MD",
                    "title": "finger",
                    "content": "finger millet rules",
                    "retrieval_score": 1.0,
                },
            ]

    pipeline.rag_engine = FakeRag()
    results = pipeline._retrieve_rag_context(_fake_physics_proxies(), crop_type="Ragi", k=2)

    assert results[0]["source"].endswith("FingerMillets/GPU45.MD")


def test_feedback_similarity_filters_by_crop(tmp_path):
    collector = FeedbackCollector(storage_path=tmp_path)
    base_item = {
        "sample_id": "sample",
        "image_path": "image.jpg",
        "farm_id": "farm",
        "predicted_grade": "B",
        "true_grade": "A",
        "predicted_moisture_risk": "LOW",
        "true_moisture_risk": "LOW",
        "image_features": _fake_physics_proxies(),
        "confidence": 80.0,
        "timestamp": "2026-06-11T00:00:00Z",
        "device_model": "test",
    }
    collector.submit_feedback(
        GradingFeedbackItem(**base_item, selected_crop="rice", notes="rice correction")
    )
    collector.submit_feedback(
        GradingFeedbackItem(
            **{**base_item, "sample_id": "finger"},
            selected_crop="finger_millets",
            notes="finger correction",
        )
    )

    results = collector.retrieve_similar_feedback(
        _fake_physics_proxies(),
        selected_crop="ragi",
        limit=3,
    )

    assert [item["sample_id"] for item in results] == ["finger"]

def test_training_artifact_filtering_is_deterministic(tmp_path):
    """Quality-filtered exports should be stable by seed and preserve filter semantics."""
    _make_image_archive(
        tmp_path / "Rice dataset.zip",
        {
            "Grade_A/rice_labeled_a.jpg": True,
            "Grade_B/rice_labeled_b.jpg": True,
            "rice_missing_1.jpg": True,
            "rice_missing_2.jpg": True,
            "readme.txt": False,
        },
    )

    manifest = build_manifest(
        source_dir=tmp_path,
        seed=42,
        train_ratio=0.5,
        require_labels=False,
    )

    first = tmp_path / "training_a"
    emit_training_artifacts(
        manifest,
        output_dir=first,
        include_flags=["missing_label"],
        exclude_flags=[],
    )

    second = tmp_path / "training_b"
    emit_training_artifacts(
        manifest,
        output_dir=second,
        include_flags=["missing_label"],
        exclude_flags=[],
    )

    def _read_lines(out_dir: Path, split: str):
        rows = []
        target = out_dir / f"rice_{split}.jsonl"
        with target.open("r", encoding="utf-8") as handle:
            for row in handle:
                rows.append(row.strip())
        return rows

    train_a = _read_lines(first, "train")
    val_a = _read_lines(first, "val")
    train_b = _read_lines(second, "train")
    val_b = _read_lines(second, "val")

    assert train_a == train_b
    assert val_a == val_b
    assert train_a or val_a
    assert all("missing_label" in row for row in (train_a + val_a))
