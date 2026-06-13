# Unified Specification: Ragi Quality Grading and Moisture-Risk Screening

## Status

This document consolidates the current Markdown corpus into one implementation-ready specification for finger millet (ragi).

It resolves conflicts across:

- legacy grading-only documents in `docs/prompts/model-doc/`
- the newer `Claude MD file/` planning set
- the newer moisture-risk architecture in `docs/specs/ai-grain-moisture/`

## Canonical Scope

The system is a camera-assisted inspection workflow for finger millet only.

It has two separate but related outputs:

- grain quality grade
- moisture-risk estimate

This system is not:

- a certified moisture meter
- a regulatory certification engine
- a generic all-crop classifier

## Source Priority

When documents disagree, use this precedence:

1. `docs/specs/ai-grain-moisture/AI_GRAIN_MOISTURE_MASTER_SPEC.md`
2. `docs/specs/ai-grain-moisture/README.md`
3. `docs/prompts/model-doc/grades_comparison.md`
4. current implementation behavior in `legacy/model-doc-app/streamlit_grading_app.py`
5. older grading-only docs in `docs/prompts/model-doc/finger_millet_ai_grading.md` and `docs/prompts/model-doc/Claude MD file/`

## Canonical Product Definition

The recommended product is a validation-first pipeline that:

- guides the operator through controlled image capture
- rejects invalid captures before inference
- estimates quality grade from visible defects and contamination
- estimates moisture risk from optical proxy signals
- exposes calibrated moisture percentage only when calibration exists
- records confidence, warning reasons, and audit metadata

## Canonical Outputs

### Quality Output

Use a three-tier quality grade:

- `A`: premium food grade
- `B`: commercial food grade
- `C`: processing-grade or low-quality catch-all

Do not use a separate `D` grade in the active deployment.

Legacy `D` behavior should be represented as:

- `quality_grade: "C"`
- `reject_recommended: true`
- `reject_reasons: [...]`

### Moisture Output

Treat moisture as a separate axis from quality.

Recommended internal moisture-risk bands:

- `LOW`: `<= 11.5%`
- `MODERATE`: `> 11.5% and <= 13.0%`
- `HIGH`: `> 13.0% and < 15.0%`
- `CRITICAL`: `>= 15.0%`

These thresholds are provisional and must be recalibrated on measured ragi data.

For a simplified UI, `CRITICAL` may be rendered as `HIGH` plus a mandatory warning, but the model and backend should preserve the more specific state.

## Input Contract

Each physical sample should contain:

- crop: `finger_millet`
- 6 raw images
- 3 views x flash/no-flash pairs
- capture metadata
- validation report
- optional measured moisture labels

### Required 6-Image Capture Set

1. Top view, no flash
2. Top view, flash
3. Slight angle, no flash
4. Slight angle, flash
5. Lighting-variation view, no flash
6. Lighting-variation view, flash

### Required Capture Conditions

- distance about `20-25 cm`
- top view near `90 degrees`
- angled view about `15-25 degrees`
- locked exposure
- locked white balance
- locked focus
- locked zoom
- visible calibration grid
- visible white/gray reference patch
- limited overlap and pile thickness

### Required Metadata

At minimum:

- `sample_id`
- `crop`
- `batch_id`
- `device_model`
- `view_type`
- `flash_used`
- `capture_distance_cm`
- `calibration_grid_version`
- `reference_patch_version`
- temperature and humidity if available

For moisture training or calibration, also require:

- repeated measured moisture readings
- moisture measurement method
- averaged ground-truth moisture
- reading variability

## End-to-End Pipeline

### 1. Capture and Validation

Reject before inference if any of the following occur:

- unreadable file
- screenshot or chat UI
- missing grid
- missing reference patch
- severe blur
- severe underexposure
- severe overexposure
- flash/no-flash misalignment
- mixed crop content
- excessive grain overlap

### 2. Preprocessing

Perform:

- file decode and integrity checks
- grid detection
- scale estimation
- perspective correction
- reference patch normalization
- LAB and HSV conversion
- flash/no-flash alignment
- pair difference map generation
- stable crop-region extraction

Never overwrite raw images.

### 3. Segmentation

Estimate:

- grain region
- overlap and clumping
- broken grain regions
- foreign matter
- dust/fines
- segmentation confidence

For ragi, patch-level analysis is acceptable when per-grain segmentation is unstable.

### 4. Feature Extraction

Use both learned and explicit features:

- specular highlight ratio
- flash/no-flash deltas
- texture and entropy
- LAB/HSV color statistics
- clumping and density features
- broken grain fraction
- foreign matter fraction

No single visual feature should determine moisture or quality alone.

### 5. Model Inference

Use a crop-specific hybrid model with:

- shared lightweight vision encoder
- flash/no-flash difference branch
- handcrafted feature branch
- metadata branch
- fusion layer
- uncertainty head

Recommended outputs:

- moisture regression head
- moisture-risk classification head
- quality grade head
- broken grain head
- foreign matter head
- confidence head

### 6. Calibration

Apply crop-specific calibration after raw model inference.

Calibration must remain separate from base model weights when possible.

Do not expose moisture percentage to users unless:

- measured moisture labels exist
- calibration has been fit
- calibration metrics are acceptable

### 7. Confidence and Decision Layer

Confidence should combine:

- model confidence
- image quality
- cross-view consistency
- flash/no-flash consistency
- calibration confidence
- metadata completeness
- in-distribution score

Recommended action policy:

- high confidence: show full result
- medium confidence: show result with caution
- low confidence: recommend retake or meter confirmation
- very low confidence: reject prediction
- high-risk prediction with low confidence: still warn and require meter confirmation

## Canonical Quality Grading Logic

Use the following order of operations.

### Hard Safety Gate

If any of the following are detected:

- biological hazard
- visible mold
- webbing
- insect damage
- visible stones
- foreign matter `> 3%`

Then:

- set `quality_grade = "C"`
- set `reject_recommended = true`

### Grade A Rule

Assign `A` only if all are true:

- off-tone grain fraction `< 5%`
- size deviation `< 5%`
- shape defect fraction `< 5%`
- foreign matter `< 1%`
- no biological hazards
- no strong dullness or moisture clumping

### Grade C Rule

Assign `C` if any are true and the hard safety gate did not already trigger:

- clearly bimodal color distribution
- off-tone fraction in roughly the `10-35%` range
- size deviation roughly `15-30%`
- shape defect fraction roughly `10-25%`
- visible quality degradation inconsistent with Grade B

### Grade B Rule

Assign `B` when the batch is not `A`, not safety-reject, and not clearly `C`.

Typical B characteristics:

- off-tone fraction around `5-10%`
- minor size or shape variance
- foreign matter around `1-3%`
- no hazard signals

## Recommended Quality Output Schema

```json
{
  "quality_grade": "B",
  "quality_score": 78,
  "reject_recommended": false,
  "reject_reasons": [],
  "broken_grain_percent": 3.2,
  "foreign_matter_percent": 0.8,
  "uniformity_score": 81,
  "mold_visible": false
}
```

## Recommended Moisture Output Schema

```json
{
  "moisture_risk": "MODERATE",
  "moisture_percent_estimate": 12.6,
  "moisture_estimate_calibrated": true,
  "confidence": 78,
  "action": "dry_or_confirm_with_meter"
}
```

If calibration is absent or confidence is too low, omit or suppress `moisture_percent_estimate`.

## Data and Evaluation Requirements

### Training Data Rules

- do not train on screenshots
- do not use visual guesses as moisture labels
- do not mix crops in the first production model
- do not split by image only

### Split Rules

Split by:

- farm
- batch
- date
- device

Do not allow the same physical batch in both train and test.

### Minimum Dataset Targets

For ragi:

- prototype: `500-1,000` measured samples
- strong model: `5,000-10,000` measured samples
- production: multi-region, multi-season, multi-device coverage

### Metrics

Moisture regression:

- MAE
- RMSE
- R2

Moisture-risk classification:

- precision
- recall
- F1
- confusion matrix
- false-safe rate

Quality grading:

- grade accuracy
- macro F1
- defect percentage error

Reliability:

- expected calibration error
- rejection rate
- confidence versus accuracy

Operational:

- invalid image rate
- retake rate
- inference latency
- meter-confirmation rate

## Current Known Limitations

- RGB images observe moisture proxies, not internal moisture directly.
- The current screenshot-heavy image folder is not a valid training dataset.
- Quality grading thresholds are more mature than moisture estimation thresholds.
- Device shift and lighting shift remain major risks until calibration data exists.
- The active codebase implements quality grading only; moisture-risk architecture is specified but not yet fully realized in the current Streamlit grader.

## Legacy Migration Notes

Use these normalization rules when converting older docs into implementation work:

- replace legacy `Grade D` with `quality_grade = "C"` plus `reject_recommended = true`
- treat `grades_comparison.md` as the authoritative grade-boundary table
- treat the moisture master spec as the authoritative system architecture
- treat empty placeholder files as incomplete and non-authoritative
- treat `Gemma 4` references as planning-era model guidance, not proof of the current runtime

## Final Guidance

This project should be implemented as a controlled, auditable ragi inspection workflow.

The correct near-term milestone is not a larger model. It is:

- valid measured data
- deterministic validation
- calibration-ready preprocessing
- conservative confidence logic
- explicit separation of moisture risk from quality grade

