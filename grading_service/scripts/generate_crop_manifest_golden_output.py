#!/usr/bin/env python3
"""Generate a tiny deterministic golden manifest + filtered JSONL artifacts.

Use this script to quickly verify dataset tooling output shape:

python scripts/generate_crop_manifest_golden_output.py
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from zipfile import ZipFile

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from scripts.build_crop_dataset_manifest import build_manifest, emit_training_artifacts


_JPEG_STUB = b"\xff\xd8\xff\xd9"


def _write_jpeg_entry(zf: ZipFile, member: str) -> None:
    zf.writestr(member, _JPEG_STUB)


def _build_sample_archives(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)

    with ZipFile(root / "Rice dataset.zip", "w") as archive:
        _write_jpeg_entry(archive, "grain_miss_a.jpg")
        _write_jpeg_entry(archive, "missing/rice_miss_b.jpg")
        _write_jpeg_entry(archive, "grade_a/rice_ok_a.jpg")

    with ZipFile(root / "Ragi dataset.zip", "w") as archive:
        _write_jpeg_entry(archive, "grade_a/ragi_ok_a.jpg")


def _clear_directory_contents(directory: Path) -> None:
    if not directory.exists():
        return
    for item in directory.iterdir():
        if item.is_dir():
            shutil.rmtree(item)
        else:
            item.unlink()


def main() -> None:
    repo_root = Path(__file__).resolve().parent
    golden_dir = repo_root / "golden_case"
    output_dir = golden_dir / "training"
    source_dir = golden_dir / "sample_archives"

    golden_dir.mkdir(parents=True, exist_ok=True)
    _clear_directory_contents(source_dir)
    _clear_directory_contents(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    _build_sample_archives(source_dir)

    manifest = build_manifest(
        source_dir=source_dir,
        seed=1337,
        train_ratio=0.5,
        require_labels=False,
    )

    output_manifest = golden_dir / "crop_dataset_manifest.golden.json"
    output_manifest.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    emit_training_artifacts(
        manifest,
        output_dir=output_dir,
        include_flags=["missing_label"],
        exclude_flags=[],
    )
    for artifact in output_dir.glob("*.jsonl"):
        if not artifact.name.startswith("rice_"):
            artifact.unlink()

    print("Generated golden manifest + filtered artifacts:")
    print(f"- manifest: {output_manifest}")
    for split in ("train", "val"):
        print(f"- rice_{split}: {output_dir / f'rice_{split}.jsonl'}")
    manifest_preview = {
        "generated_at": manifest["generated_at"],
        "source_dir": manifest["source_dir"],
        "totals": manifest["totals"],
        "crops": {crop: manifest["crops"][crop]["total"] for crop in sorted(manifest.get("crops", {}))},
        "label_counts": manifest["crops"]["rice"]["label_counts"],
        "seed": manifest["seed"],
        "train_ratio": manifest["train_ratio"],
    }
    print("\nSample manifest summary:")
    print(json.dumps(manifest_preview, indent=2, ensure_ascii=False))

    for split in ("train", "val"):
        artifact = output_dir / f"rice_{split}.jsonl"
        if not artifact.exists():
            continue
        first_line = artifact.read_text(encoding="utf-8").splitlines()[:1]
        sample_line = first_line[0] if first_line else "<empty>"
        print(f"\nSample {artifact.name} record:")
        print(sample_line)


if __name__ == "__main__":
    main()
