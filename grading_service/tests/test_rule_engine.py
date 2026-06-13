from ai_grain_grade.rule_engine import CropRuleEngine, RagiRuleEngine


BASE_PROXIES = {
    "lab_features": {"color_darkness_index": 35.0},
    "clumping": {"density": 0.05},
    "uniformity_score": 82.0,
    "roughness_score": 45.0,
    "grain_mask_coverage": 0.45,
}


def test_grade_a_requires_premium_fao_bis_thresholds():
    engine = RagiRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "off_tone_fraction": 2.0,
            "size_deviation": 2.0,
            "shape_defect_fraction": 2.0,
            "broken_grain_percent": 1.0,
            "foreign_matter_percent": 0.05,
            "other_edible_grains_percent": 0.2,
            "bimodal_color_detected": False,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=11.5,
    )

    assert decision.grade == "A"
    assert decision.reject is False


def test_moisture_above_outer_ragi_range_rejects():
    engine = RagiRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "off_tone_fraction": 2.0,
            "size_deviation": 2.0,
            "shape_defect_fraction": 2.0,
            "broken_grain_percent": 1.0,
            "foreign_matter_percent": 0.05,
            "bimodal_color_detected": False,
            "mold_visible": False,
        },
        BASE_PROXIES,
        moisture_risk="CRITICAL",
        moisture_percent=14.5,
    )

    assert decision.grade == "C"
    assert decision.reject is True
    assert "moisture_reject" in decision.rule_hits


def test_foreign_matter_cannot_pass_outer_threshold():
    engine = RagiRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "foreign_matter_percent": 1.2,
            "broken_grain_percent": 1.0,
            "shape_defect_fraction": 2.0,
            "mold_visible": False,
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=11.5,
    )

    assert decision.grade == "C"
    assert decision.reject is True
    assert "foreign_matter_reject" in decision.rule_hits


def test_crop_rule_engine_uses_rice_foreign_matter_thresholds():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "off_tone_fraction": 2.0,
            "size_deviation": 2.0,
            "shape_defect_fraction": 2.0,
            "broken_grain_percent": 1.0,
            "foreign_matter_percent": 0.6,
            "other_edible_grains_percent": 0.0,
            "bimodal_color_detected": False,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=11.5,
        crop_type="rice",
    )

    assert decision.grade == "C"
    assert decision.reject is True
    assert "foreign_matter_reject" in decision.rule_hits


def test_crop_rule_engine_keeps_single_rice_damaged_grain_issue_at_grade_b():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "broken_grains_percent": 1.0,
            "damaged_grains_percent": 3.0,
            "chalky_grains_percent": 0.5,
            "foreign_matter_percent": 0.05,
            "color_uniformity_score": 96.0,
            "size_uniformity_score": 93.0,
            "shape_uniformity_score": 92.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=11.5,
        crop_type="rice",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert "damaged_grains_c" in decision.rule_hits
    assert "broken_grains_c" not in decision.rule_hits


def test_crop_rule_engine_keeps_single_millet_extraneous_issue_at_grade_b():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "organic_extraneous_matter_percent": 0.05,
            "inorganic_extraneous_matter_percent": 0.15,
            "damaged_grains_percent": 0.1,
            "immature_grains_percent": 1.0,
            "weevilled_grains_percent": 0.0,
            "color_uniformity_score": 96.0,
            "size_uniformity_score": 93.0,
            "shape_uniformity_score": 92.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=11.5,
        crop_type="bajra",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert "inorganic_extraneous_matter_c" in decision.rule_hits
    assert "organic_extraneous_matter_c" not in decision.rule_hits


def test_crop_rule_engine_allows_clean_low_moisture_rice_grade_a_with_scores():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "broken_grains_percent": 1.0,
            "damaged_grains_percent": 0.5,
            "chalky_grains_percent": 0.5,
            "foreign_matter_percent": 0.05,
            "color_uniformity_score": 97.0,
            "size_uniformity_score": 94.0,
            "shape_uniformity_score": 93.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    assert decision.grade == "A"
    assert decision.grain_grade == "A"
    assert decision.score >= 90
    assert decision.grain_score >= 90
    assert decision.moisture_score >= 90
    assert decision.score_breakdown["metrics"]["moisture"]["grade"] == "A"


def test_crop_rule_engine_allows_grade_a_with_small_visual_b_metric():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "broken_grains_percent": 1.0,
            "damaged_grains_percent": 0.5,
            "chalky_grains_percent": 0.5,
            "foreign_matter_percent": 0.05,
            "color_uniformity_score": 92.0,
            "size_uniformity_score": 94.0,
            "shape_uniformity_score": 93.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    assert decision.grade == "A"
    assert decision.grain_grade == "A"
    assert decision.reject is False
    assert decision.score >= 88
    assert "rice_grade_a_score_gate_pass" in decision.rule_hits
    assert any(
        item["reason"] == "Color Uniformity blocks Grade A"
        for item in decision.score_breakdown["penalties"]
    )


def test_crop_rule_engine_low_moisture_keeps_commercial_grain_at_grade_b():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "broken_grains_percent": 5.0,
            "damaged_grains_percent": 1.2,
            "chalky_grains_percent": 3.0,
            "foreign_matter_percent": 0.15,
            "color_uniformity_score": 84.0,
            "size_uniformity_score": 81.0,
            "shape_uniformity_score": 82.0,
            "surface_defects_percent": 3.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=8.8,
        crop_type="rice",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert decision.score >= 72
    assert decision.moisture_score >= 90


def test_crop_rule_engine_latest_low_moisture_rice_log_metrics_grade_a():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "quality_score": 72,
            "broken_grains_percent": 6.0,
            "damaged_grains_percent": 1.5,
            "chalky_grains_percent": 3.2,
            "foreign_matter_percent": 0.18,
            "color_uniformity_score": 82.0,
            "size_uniformity_score": 78.0,
            "shape_uniformity_score": 80.0,
            "surface_defects_percent": 4.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    assert decision.grade == "A"
    assert decision.grain_grade == "A"
    assert decision.reject is False
    assert decision.score >= 88
    assert decision.moisture_score >= 90
    assert "rice_grade_a_score_gate_pass" in decision.rule_hits


def test_crop_rule_engine_brown_indrayani_low_moisture_tolerates_color_uniformity():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "quality_score": 72,
            "broken_grains_percent": 6.0,
            "damaged_grains_percent": 1.5,
            "chalky_grains_percent": 3.2,
            "foreign_matter_percent": 0.18,
            "color_uniformity_score": 78.0,
            "size_uniformity_score": 76.0,
            "shape_uniformity_score": 79.0,
            "surface_defects_percent": 4.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=8.8,
        crop_type="rice",
    )

    assert decision.grade == "A"
    assert decision.grain_grade == "A"
    assert decision.reject is False
    assert decision.mold_visible is False
    assert "rice_hazard_gate" not in decision.rule_hits
    assert "rice_grade_a_score_gate_pass" in decision.rule_hits


def test_crop_rule_engine_missing_rice_surface_metric_does_not_fallback_to_shape_defect():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "quality_score": 72,
            "off_tone_fraction": 18.0,
            "shape_defect_fraction": 12.0,
            "broken_grains_percent": 6.0,
            "foreign_matter_percent": 0.18,
            "color_uniformity_score": 82.0,
            "size_uniformity_score": 78.0,
            "shape_uniformity_score": 80.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    metrics = decision.score_breakdown["metrics"]
    assert metrics["chalky_grains"]["value"] == 0.0
    assert metrics["surface_defects"]["value"] == 0.0
    assert decision.grade == "A"
    assert "rice_chalky_grains_health_penalty" not in decision.rule_hits
    assert "rice_surface_defects_health_penalty" not in decision.rule_hits


def test_crop_rule_engine_low_moisture_rice_health_penalties_are_b_not_forced_c():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "B",
            "broken_grains_percent": 6.0,
            "damaged_grains_percent": 0.0,
            "chalky_grains_percent": 18.0,
            "foreign_matter_percent": 0.18,
            "color_uniformity_score": 82.0,
            "size_uniformity_score": 76.0,
            "shape_uniformity_score": 88.0,
            "surface_defects_percent": 12.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert decision.score >= 72
    assert decision.grain_score >= 72
    assert decision.moisture_score >= 90
    assert "rice_chalky_grains_health_penalty" in decision.rule_hits
    assert "rice_surface_defects_health_penalty" in decision.rule_hits


def test_crop_rule_engine_low_moisture_millet_feedback_case_is_b_not_c():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "C",
            "organic_extraneous_matter_percent": 0.4,
            "inorganic_extraneous_matter_percent": 0.0,
            "damaged_grains_percent": 0.0,
            "immature_grains_percent": 0.0,
            "weevilled_grains_percent": 0.0,
            "color_uniformity_score": 62.0,
            "size_uniformity_score": 72.0,
            "shape_uniformity_score": 78.0,
            "surface_defects_percent": 22.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=8.8,
        crop_type="finger_millets",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert decision.score >= 72
    assert decision.moisture_score >= 90
    assert "finger_millets_surface_defects_health_penalty" in decision.rule_hits


def test_crop_rule_engine_one_over_outer_visual_metric_is_b_not_auto_c():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "broken_grains_percent": 1.0,
            "damaged_grains_percent": 0.5,
            "chalky_grains_percent": 10.0,
            "foreign_matter_percent": 0.05,
            "color_uniformity_score": 96.0,
            "size_uniformity_score": 93.0,
            "shape_uniformity_score": 92.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=9.8,
        crop_type="rice",
    )

    assert decision.grade == "B"
    assert decision.grain_grade == "B"
    assert decision.reject is False
    assert "rice_chalky_grains_health_penalty" in decision.rule_hits
    assert decision.moisture_score >= 90


def test_crop_rule_engine_keeps_very_low_grain_health_score_at_grade_c():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "C",
            "organic_extraneous_matter_percent": 0.45,
            "inorganic_extraneous_matter_percent": 0.0,
            "damaged_grains_percent": 0.0,
            "immature_grains_percent": 0.0,
            "weevilled_grains_percent": 0.0,
            "color_uniformity_score": 60.0,
            "size_uniformity_score": 61.0,
            "shape_uniformity_score": 61.0,
            "surface_defects_percent": 30.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="LOW",
        moisture_percent=8.8,
        crop_type="finger_millets",
    )

    assert decision.grade == "C"
    assert decision.grain_grade == "C"
    assert decision.reject is False
    assert decision.grain_score < 68


def test_crop_rule_engine_high_moisture_downgrades_final_but_keeps_grain_grade():
    engine = CropRuleEngine()
    decision = engine.evaluate(
        {
            "quality_grade": "A",
            "broken_grains_percent": 1.0,
            "damaged_grains_percent": 0.5,
            "chalky_grains_percent": 0.5,
            "foreign_matter_percent": 0.05,
            "color_uniformity_score": 97.0,
            "size_uniformity_score": 94.0,
            "shape_uniformity_score": 93.0,
            "surface_defects_percent": 1.0,
            "mold_visible": False,
            "visible_defects": [],
        },
        BASE_PROXIES,
        moisture_risk="HIGH",
        moisture_percent=13.6,
        crop_type="rice",
    )

    assert decision.grade == "C"
    assert decision.grain_grade == "A"
    assert decision.reject is False
    assert decision.moisture_score < decision.grain_score
    assert any(item["reason"].startswith("Moisture") for item in decision.score_breakdown["penalties"])
