"""
Integration Testing Suite for Millets Now
==========================================

Comprehensive test coverage for all pipeline components.
Run: pytest test_suite.py -v

Author: Copilot
Date: 2026-04-29
"""

import pytest
from datetime import timezone
import tempfile
import json
import numpy as np
import shutil
import uuid
import warnings
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Our modules
from ai_grain_grade.physics_proxies import PhysicsProxiesExtractor
from ai_grain_grade.vision_rag_pipeline import (
    VisionRAGPipeline,
    QualityGrade,
    MoistureRisk,
)
from ai_grain_grade.feedback import FeedbackCollector, GradingFeedbackItem


class TestPhysicsProxies:
    """Test physics proxy extraction."""

    @pytest.fixture
    def extractor(self):
        return PhysicsProxiesExtractor()

    @pytest.fixture
    def dummy_image(self):
        """Create a dummy test image."""
        # Create a simple test image (200x200, 3-channel)
        img = np.ones((200, 200, 3), dtype=np.uint8)
        img[:, :] = [100, 80, 60]  # Brownish (ragi color)

        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            import cv2
            cv2.imwrite(f.name, img)
            return f.name

    def test_extraction_output_structure(self, extractor, dummy_image):
        """Test that extraction returns expected structure."""
        result = extractor.extract_all_proxies(dummy_image)

        assert "texture_entropy" in result
        assert "lab_features" in result
        assert "clumping" in result
        assert "roughness_score" in result
        assert "specular_highlights_ratio" in result
        assert "uniformity_score" in result

    def test_entropy_in_valid_range(self, extractor, dummy_image):
        """Test entropy is in valid range (0-4 bits for 16 bins)."""
        result = extractor.extract_all_proxies(dummy_image)
        entropy = result["texture_entropy"]

        assert 0 <= entropy <= 4, f"Entropy {entropy} out of range"

    def test_lab_features_bounds(self, extractor, dummy_image):
        """Test LAB features are within bounds."""
        result = extractor.extract_all_proxies(dummy_image)
        lab = result["lab_features"]

        # OpenCV LAB range: [0, 255]. Empty masks return finite neutral defaults.
        assert np.isfinite(lab["l_mean"])
        assert np.isfinite(lab["color_darkness_index"])
        assert 0 <= lab["l_mean"] <= 255, f"L* {lab['l_mean']} out of range"
        assert 0 <= lab["color_darkness_index"] <= 100, "Darkness index out of range"

    def test_blank_image_returns_finite_defaults_without_runtime_warnings(self, extractor, tmp_path):
        """Bad photos with no segmented grain should not produce NaN proxy values."""
        import cv2

        blank_path = tmp_path / "blank.jpg"
        blank = np.full((160, 160, 3), 255, dtype=np.uint8)
        cv2.imwrite(str(blank_path), blank)

        with warnings.catch_warnings():
            warnings.simplefilter("error", RuntimeWarning)
            result = extractor.extract_all_proxies(str(blank_path))

        lab = result["lab_features"]
        assert result["grain_mask_coverage"] == 0.0
        assert lab["l_mean"] == 255.0
        assert lab["l_std"] == 0.0
        assert lab["color_darkness_index"] == 0.0
        assert result["clumping"]["density"] == 0.0
        assert result["roughness_score"] == 0.0
        assert result["uniformity_score"] == 0.0

    def test_clumping_density_valid(self, extractor, dummy_image):
        """Test clumping density is 0-1."""
        result = extractor.extract_all_proxies(dummy_image)
        clumping = result["clumping"]["density"]

        assert 0 <= clumping <= 1, f"Clumping {clumping} out of range"

    def test_invalid_image_raises_error(self, extractor):
        """Test that invalid image path raises error."""
        with pytest.raises(ValueError):
            extractor.extract_all_proxies("/nonexistent/image.jpg")


class TestVisionRAGPipeline:
    """Test Vision-RAG pipeline."""

    @pytest.fixture
    def pipeline(self):
        return VisionRAGPipeline(
            siliconflow_api_key="test-key",
            vector_db_type="local",
        )

    @pytest.fixture
    def mock_proxies(self):
        return {
            "texture_entropy": 3.5,
            "lab_features": {
                "l_mean": 65.0,
                "l_std": 10.0,
                "a_mean": 8.0,
                "b_mean": 22.0,
                "color_darkness_index": 35.0,
            },
            "clumping": {
                "density": 0.15,
                "cluster_count": 100,
                "avg_cluster_size": 50.0,
            },
            "roughness_score": 75.0,
            "specular_highlights_ratio": 0.05,
            "uniformity_score": 80.0,
            "grain_mask_coverage": 0.7,
        }

    def test_rag_chunks_loaded(self, pipeline):
        """Test that RAG chunks are loaded in the engine."""
        assert hasattr(pipeline, "rag_engine")
        assert len(pipeline.rag_engine.chunks) > 0

    def test_safety_gate_detection(self, pipeline):
        """Test safety gate detection logic."""
        # Mock the Qwen call to detect hazard
        with patch.object(
            pipeline,
            "_call_qwen_vision",
            return_value=json.dumps({
                "hazard_found": True,
                "hazard_type": "mold",
                "confidence": 0.9,
            }),
        ):
            finding = pipeline._pass1_safety_gate("dummy.jpg")

            assert finding.hazard_detected is True
            assert finding.hazard_type == "mold"
            assert finding.confidence == 0.9

    def test_moisture_risk_and_calibration(self, pipeline, mock_proxies):
        """Test moisture risk classification and calibration."""
        # LOW risk: zero darkness, zero clumping, max entropy
        mock_proxies["lab_features"]["color_darkness_index"] = 0
        mock_proxies["clumping"]["density"] = 0.0
        mock_proxies["texture_entropy"] = 40.0 # Match the 40 threshold in code
        
        # Score = (0 + 0*200 + max(0, 40-40)*5) / 3 = 0
        risk, percent, is_calib = pipeline._estimate_moisture_risk(mock_proxies)
        assert risk == MoistureRisk.LOW
        assert percent <= 11.5
        assert is_calib is False

        # CRITICAL risk
        mock_proxies["lab_features"]["color_darkness_index"] = 80
        mock_proxies["clumping"]["density"] = 0.5
        mock_proxies["texture_entropy"] = 1.0
        
        risk, percent, is_calib = pipeline._estimate_moisture_risk(mock_proxies)
        assert risk == MoistureRisk.CRITICAL
        assert percent >= 15.0
        assert is_calib is False

    def test_deterministic_grading_logic(self, pipeline):
        """Test deterministic grading rules."""
        # Grade A criteria
        response = {
            "quality_grade": "A",
            "off_tone_fraction": 2.0,
            "size_deviation": 3.0,
            "shape_defect_fraction": 2.0,
            "broken_grain_percent": 0.5,
            "foreign_matter_percent": 0.05,
            "mold_visible": False,
        }
        proxies = {
            "lab_features": {"color_darkness_index": 35.0},
            "clumping": {"density": 0.05},
            "uniformity_score": 82.0,
            "roughness_score": 45.0,
            "grain_mask_coverage": 0.45,
        }
        grade = pipeline._apply_grading_logic(response, proxies)
        assert grade["grade"] == QualityGrade.A

        # Current FAO/BIS rule anchor blocks Grade A above 0.10% foreign matter.
        response["foreign_matter_percent"] = 0.5
        grade = pipeline._apply_grading_logic(response, proxies)
        assert grade["grade"] == QualityGrade.B

        # Grade C criteria (safety gate)
        response["mold_visible"] = True
        grade = pipeline._apply_grading_logic(response, proxies)
        assert grade["grade"] == QualityGrade.C
        assert grade["reject"] is True

    def test_rag_context_retrieval(self, pipeline, mock_proxies):
        """Test RAG context retrieval."""
        context = pipeline._retrieve_rag_context(mock_proxies)

        assert isinstance(context, list)
        assert len(context) > 0
        assert all("content" in chunk for chunk in context)

    def test_result_formatting(self, pipeline):
        """Test result formatting for API."""
        # Create a mock grading result
        from ai_grain_grade.vision_rag_pipeline import GradingResult
        from datetime import datetime

        result = GradingResult(
            quality_grade=QualityGrade.B,
            quality_score=75,
            reject_recommended=False,
            reject_reasons=[],
            broken_grain_percent=2.0,
            foreign_matter_percent=0.8,
            uniformity_score=75.0,
            mold_visible=False,
            moisture_risk=MoistureRisk.MODERATE,
            moisture_estimate_calibrated=False,
            moisture_percent_estimate=None,
            overall_confidence=80,
            pass1_confidence=100,
            pass2_confidence=75,
            timestamp=datetime.now(timezone.utc).isoformat(),
            model_version="v1",
            rag_chunks_used=5,
        )

        formatted = pipeline.format_result_for_api(result)

        assert "quality" in formatted
        assert "moisture" in formatted
        assert "confidence" in formatted
        assert "audit" in formatted
        assert formatted["quality"]["grade"] == "B"
        assert formatted["moisture"]["risk_level"] == "MODERATE"


class TestFeedbackCollection:
    """Test cloud-runtime feedback collection components."""

    @pytest.fixture
    def feedback_items(self):
        """Create mock feedback items."""
        return [
            GradingFeedbackItem(
                sample_id="S001",
                image_path="/path/to/img1.jpg",
                farm_id="FARM-A",
                predicted_grade="B",
                true_grade="A",
                predicted_moisture_risk="MODERATE",
                true_moisture_risk="LOW",
                image_features={
                    "texture_entropy": 3.5,
                    "l_mean": 65,
                    "clumping_density": 0.1,
                    "roughness_score": 75,
                    "uniformity_score": 80,
                },
                confidence=75,
                timestamp="2026-04-29T10:00:00Z",
                device_model="iPhone 12",
            ),
            GradingFeedbackItem(
                sample_id="S002",
                image_path="/path/to/img2.jpg",
                farm_id="FARM-B",
                predicted_grade="A",
                true_grade="C",  # False-safe!
                predicted_moisture_risk="LOW",
                true_moisture_risk="CRITICAL",
                image_features={
                    "texture_entropy": 2.0,
                    "l_mean": 50,
                    "clumping_density": 0.4,
                    "roughness_score": 40,
                    "uniformity_score": 50,
                },
                confidence=85,
                timestamp="2026-04-29T10:15:00Z",
                device_model="Samsung A50",
            ),
        ]

    def test_feedback_collector(self, feedback_items):
        """Test feedback collection."""
        tmpdir = Path(f".feedback_test_{uuid.uuid4().hex}")
        tmpdir.mkdir(exist_ok=False)
        try:
            collector = FeedbackCollector(storage_path=tmpdir)

            for item in feedback_items:
                success = collector.submit_feedback(item)
                assert success is True

            # Check pending count
            pending = collector.get_pending_count()
            assert pending == len(feedback_items)

            # Load feedback
            loaded = collector.load_all_feedback()
            assert len(loaded) == len(feedback_items)

            similar = collector.retrieve_similar_feedback(
                {
                    "texture_entropy": 2.1,
                    "lab_features": {"color_darkness_index": 52},
                    "clumping": {"density": 0.39},
                    "roughness_score": 42,
                    "uniformity_score": 51,
                },
                limit=1,
            )
            assert len(similar) == 1
            assert similar[0]["sample_id"] == "S002"
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


class TestIntegration:
    """End-to-end integration tests."""

    def test_end_to_end_workflow(self):
        """Test complete pipeline: image → proxies → RAG → result."""
        # Create dummy image
        img = np.ones((200, 200, 3), dtype=np.uint8)
        img[:, :] = [100, 80, 60]

        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            import cv2
            cv2.imwrite(f.name, img)
            image_path = f.name

        try:
            # 1. Extract proxies
            extractor = PhysicsProxiesExtractor()
            proxies = extractor.extract_all_proxies(image_path)
            assert proxies is not None

            # 2. Initialize pipeline
            pipeline = VisionRAGPipeline(
                siliconflow_api_key="test-key",
                vector_db_type="local",
            )

            # 3. Mock Qwen inference
            with patch.object(
                pipeline,
                "_call_qwen_vision",
                return_value=json.dumps({
                    "quality_grade": "B",
                    "quality_score": 75,
                    "off_tone_fraction": 5.0,
                    "size_deviation": 5.0,
                    "shape_defect_fraction": 3.0,
                    "broken_grain_percent": 2.0,
                    "foreign_matter_percent": 0.8,
                    "mold_visible": False,
                    "model_confidence": 80,
                }),
            ):
                # 4. Inference
                result = pipeline.infer(image_path, proxies)

                # Assertions
                assert result.quality_grade in [
                    QualityGrade.A,
                    QualityGrade.B,
                    QualityGrade.C,
                ]
                assert result.moisture_risk in [
                    MoistureRisk.LOW,
                    MoistureRisk.MODERATE,
                    MoistureRisk.HIGH,
                    MoistureRisk.CRITICAL,
                ]
                assert 0 <= result.overall_confidence <= 100

        finally:
            # Cleanup
            import os
            try:
                os.unlink(image_path)
            except:
                pass

    def test_feedback_queue_threshold(self):
        """Test feedback collection threshold tracking."""
        # Create mock feedback
        feedback_items = [
            GradingFeedbackItem(
                sample_id=f"S{i:03d}",
                image_path=f"/tmp/img{i}.jpg",
                farm_id=f"FARM-{i % 3}",
                predicted_grade="B",
                true_grade=["A", "B", "C"][i % 3],
                predicted_moisture_risk="MODERATE",
                true_moisture_risk=["LOW", "MODERATE", "HIGH"][i % 3],
                image_features={
                    "texture_entropy": 3.5 + i * 0.1,
                    "l_mean": 65,
                    "clumping_density": 0.1 + i * 0.01,
                    "roughness_score": 75,
                    "uniformity_score": 80,
                },
                confidence=75,
                timestamp="2026-04-29T10:00:00Z",
                device_model="iPhone 12",
            )
            for i in range(10)
        ]

        # Store feedback
        tmpdir = Path(f".feedback_test_{uuid.uuid4().hex}")
        tmpdir.mkdir(exist_ok=False)
        try:
            collector = FeedbackCollector(storage_path=tmpdir)

            for item in feedback_items:
                collector.submit_feedback(item)

            should_review = collector.check_review_threshold(threshold=5)
            assert should_review is True

            # Load and verify
            loaded = collector.load_all_feedback()
            assert len(loaded) == len(feedback_items)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
