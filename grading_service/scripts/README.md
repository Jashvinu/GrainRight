# Scripts

Local helper scripts for running or maintaining the project.

- `run_app.ps1` - starts the Streamlit app on port 8501.
- `run_streamlit_8520.cmd` - older helper kept for compatibility.

- `build_crop_dataset_manifest.py` - generates a deterministic crop manifest from
  `crop_type_dataset/*.zip`, validates image discovery, captures label/missing-label
  statistics, and can emit per-crop `train` / `val` JSONL artifacts for future
  model fine-tune jobs.

  ```bash
  python scripts/build_crop_dataset_manifest.py \
    --source-dir crop_type_dataset \
    --output data/dataset_manifests/crop_dataset_manifest.json \
    --emit-training-dir data/dataset_manifests/training
  ```

  Optional quality filtering can be applied when exporting training artifacts:

  ```bash
  python scripts/build_crop_dataset_manifest.py \
    --emit-training-dir data/dataset_manifests/training \
    --require-quality-flags flat_archive_path \
    --exclude-quality-flags missing_label
  ```

## Golden-case reference output

For operator onboarding, a compact sample is available in:

- `scripts/golden_case/crop_dataset_manifest.golden.json`
- `scripts/golden_case/training/rice_train.jsonl`
- `scripts/golden_case/training/rice_val.jsonl`

These outputs reflect a filtered export where `missing_label` samples are selected.
To regenerate the golden reference in your environment:

```bash
python scripts/generate_crop_manifest_golden_output.py
```

The script now prints a compact sample digest, including:

- totals + per-crop sample counts
- seed and split ratio
- one representative `train` JSONL row and one representative `val` JSONL row
