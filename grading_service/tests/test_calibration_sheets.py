from pathlib import Path

import pytest

from ai_grain_grade.physics_proxies import PhysicsProxiesExtractor


FIXTURE_DIR = Path("examples") / "calibration-sheets"


def _require_fixture(name: str) -> Path:
    path = FIXTURE_DIR / name
    if not path.exists():
        pytest.skip(f"missing calibration fixture: {path}")
    return path


def test_precision_sheet_uses_100mm_active_zone():
    extractor = PhysicsProxiesExtractor()
    result = extractor.extract_all_proxies(str(_require_fixture("sheet-1.jpeg")))

    calibration = result["calibration"]
    assert calibration["available"] is True
    assert calibration["sheet_style"] == "precision-white"
    assert calibration["calibration_reference"] == "100mm-active-grain-zone"
    assert 4.0 <= calibration["pixels_per_mm"] <= 4.8
    assert result["sample_field"]["source"] == "printed-active-zone"
    assert result["calibrated_geometry"]["grain_area_mm2"] == 0.0
    grid = result["grid_box_analysis"]
    assert grid["available"] is True
    assert grid["active_field"]["major_rows"] == 10
    assert grid["active_field"]["major_cols"] == 10
    assert grid["active_field"]["major_occupied_cells"] == 0
    assert grid["big_sheet_grid"]["available"] is True


def test_blue_grading_sheet_uses_aruco_blue_grid():
    extractor = PhysicsProxiesExtractor()
    result = extractor.extract_all_proxies(str(_require_fixture("sheet-2.jpeg")))

    calibration = result["calibration"]
    assert calibration["available"] is True
    assert calibration["source"] == "aruco-blue-grid"
    assert calibration["sheet_style"] == "blue-grading"
    assert calibration["marker_count"] == 4
    assert 4.5 <= calibration["pixels_per_mm"] <= 5.5
    assert result["sample_field"]["source"] == "printed-blue-grid"
    assert result["grid_box_analysis"]["available"] is True


def test_grain_example_crops_to_printed_active_zone():
    extractor = PhysicsProxiesExtractor()
    result = extractor.extract_all_proxies(
        str(_require_fixture("grain-grade-calibration-example.jpeg"))
    )

    calibration = result["calibration"]
    geometry = result["calibrated_geometry"]
    assert calibration["available"] is True
    assert calibration["calibration_reference"] == "100mm-active-grain-zone"
    assert result["sample_field"]["source"] == "printed-active-zone"
    assert 0.20 <= geometry["grain_fill_ratio"] <= 0.60
    assert 1.0 <= geometry["median_equiv_diameter_mm"] <= 2.0
    grid = result["grid_box_analysis"]
    assert grid["available"] is True
    assert grid["active_field"]["major_rows"] == 10
    assert grid["active_field"]["major_cols"] == 10
    assert grid["active_field"]["major_occupied_cells"] > 20
    assert grid["active_field"]["minor_occupied_cells"] > 500
    assert grid["grain_count"] > 20
    assert grid["per_grain_grid_samples"][0]["active_major_cell"]["cell_mm"] == 10.0
    assert grid["per_grain_grid_samples"][0]["active_minor_cell"]["cell_mm"] == 1.0
