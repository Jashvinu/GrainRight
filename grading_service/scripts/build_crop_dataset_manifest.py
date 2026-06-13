#!/usr/bin/env python3
"""Build deterministic crop-aware dataset manifests from local archive datasets."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import zipfile
from datetime import datetime, timezone
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST_PATH = PROJECT_ROOT / "data" / "dataset_manifests" / "crop_dataset_manifest.json"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def _split_flags(raw: str) -> List[str]:
    """Split comma/space/semicolon-separated quality flags."""
    if not raw:
        return []
    values = []
    for chunk in re.split(r"[,\s;]+", raw.strip()):
        token = chunk.strip().lower()
        if token:
            values.append(token)
    return values


def _sample_matches_quality_filters(
    sample: Dict[str, Any],
    include_flags: Optional[List[str]] = None,
    exclude_flags: Optional[List[str]] = None,
) -> bool:
    """Return True when a sample passes configured quality-filter semantics."""
    sample_flags = {str(flag).lower() for flag in sample.get("quality_flags", [])}
    include_set = {flag for flag in (include_flags or [])}
    exclude_set = {flag for flag in (exclude_flags or [])}
    if include_set and not include_set.issubset(sample_flags):
        return False
    if exclude_set and sample_flags.intersection(exclude_set):
        return False
    return True


def normalize_crop_name(archive_name: str) -> str:
    """Map archive names to canonical crop identifiers."""
    raw = Path(archive_name).stem.lower()
    raw = raw.replace("_", " ")
    raw = re.sub(r"\bdataset\b", "", raw)
    raw = re.sub(r"\s+", " ", raw).strip()
    if not raw:
        return "unknown"
    if raw in {"bajari", "bajri", "bajra"}:
        return "bajra"
    if raw in {"finger millets", "fingermillets", "fingermillet", "ragi", "nachani"}:
        return "finger_millets"
    if raw in {"rice", "dhan", "paddy"}:
        return "rice"
    return raw


def label_from_path(member_path: str) -> Optional[str]:
    """Infer label from directory/name tokens, e.g., Grade A."""
    parts = [part for part in Path(member_path).parts if part]
    for part in reversed(parts[:-1]):
        match = re.search(r"\bgrade[\s_-]*([abcABC])\b", part or "", re.IGNORECASE)
        if match:
            return match.group(1).upper()
    fname = Path(member_path).name
    filename = re.sub(r"[^a-z0-9._-]", " ", fname.lower())
    match = re.search(r"\bgrade[\s_-]*([abcABC])\b", filename, re.IGNORECASE)
    if match:
        return match.group(1).upper()
    return None


@dataclass
class ManifestEntry:
    sample_id: str
    archive_name: str
    member_path: str
    crop: str
    label: Optional[str]
    image_uri: str
    source_archive_path: str
    quality_flags: List[str]


def build_entries(archive_path: Path) -> Tuple[List[ManifestEntry], List[str]]:
    crop = normalize_crop_name(archive_path.name)
    entries: List[ManifestEntry] = []
    errors: List[str] = []

    with zipfile.ZipFile(archive_path, "r") as zf:
        names = [name for name in zf.namelist() if not name.endswith("/")]
        seen_extensions: Counter[str] = Counter()
        non_image_count = 0
        for member in names:
            ext = Path(member).suffix.lower()
            if ext not in IMAGE_EXTS:
                if ext:
                    non_image_count += 1
                continue
            if ext:
                seen_extensions[ext] += 1
            label = label_from_path(member)
            flags: List[str] = []
            if not label:
                flags.append("missing_label")
            if len(Path(member).parts) < 2:
                flags.append("flat_archive_path")
            sample_id = hashlib.sha1(f"{archive_path.name}|{member}".encode("utf-8")).hexdigest()[:20]
            image_uri = f"{archive_path.name}::{member}"
            entries.append(
                ManifestEntry(
                    sample_id=sample_id,
                    archive_name=archive_path.name,
                    member_path=member,
                    crop=crop,
                    label=label,
                    image_uri=image_uri,
                    source_archive_path=str(archive_path.resolve()),
                    quality_flags=flags,
                )
            )
        if not entries:
            errors.append("no_image_files")
        if non_image_count:
            errors.append(f"non_image_files:{non_image_count}")
        if seen_extensions:
            extension_summary = ", ".join(
                f"{ext}:{count}" for ext, count in sorted(seen_extensions.items(), key=lambda item: item[0])
            )
            errors.append(f"extension_profile:{extension_summary}")
    return entries, errors


def stable_split(
    sample_ids: List[str],
    seed: int,
    train_ratio: float,
    crop: str,
) -> Dict[str, List[str]]:
    rng = random.Random(f"{seed}:{crop}")
    ids = list(sample_ids)
    rng.shuffle(ids)
    total = len(ids)
    train_count = int(total * train_ratio)
    return {
        "train": ids[:train_count],
        "val": ids[train_count:],
    }


def build_manifest(
    source_dir: Path,
    seed: int,
    train_ratio: float,
    require_labels: bool,
) -> Dict[str, Any]:
    source_dir = source_dir.expanduser()
    if not source_dir.exists():
        raise FileNotFoundError(f"Dataset directory does not exist: {source_dir}")

    zip_files = sorted(source_dir.glob("*.zip"), key=lambda path: path.name.lower())
    all_entries: List[ManifestEntry] = []
    malformed: List[str] = []
    archive_errors = {}

    for archive in zip_files:
        try:
            entries, errors = build_entries(archive)
            all_entries.extend(entries)
            if errors:
                archive_errors[archive.name] = errors
        except Exception as exc:
            malformed.append(str(archive))
            archive_errors[archive.name] = [f"read_error:{exc}"]
            continue

    if require_labels and any(entry.label is None for entry in all_entries):
        missing = [entry.sample_id for entry in all_entries if not entry.label]
        raise RuntimeError(
            f"require_labels=True, but {len(missing)} samples are missing labels."
        )

    no_image_archives = sum(
        1
        for _archive_name, issues in archive_errors.items()
        if any(issue.startswith("no_image_files") for issue in issues)
    )

    per_crop: Dict[str, List[ManifestEntry]] = defaultdict(list)
    for entry in all_entries:
        per_crop[entry.crop].append(entry)

    manifest_per_crop: Dict[str, Any] = {}
    train_val_ids: Dict[str, Dict[str, List[str]]] = {}
    for crop, entries in sorted(per_crop.items(), key=lambda item: item[0]):
        ids = [entry.sample_id for entry in entries]
        splits = stable_split(ids, seed=seed, train_ratio=train_ratio, crop=crop)
        train_val_ids[crop] = splits
        label_counter = Counter(entry.label or "missing" for entry in entries)
        manifest_per_crop[crop] = {
            "total": len(entries),
            "label_counts": dict(label_counter),
            "missing_labels": label_counter.get("missing", 0),
            "sample_ids": ids,
            "split": splits,
        }

    all_label_counter = Counter(entry.label or "missing" for entry in all_entries)
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "seed": seed,
        "source_dir": str(source_dir.resolve()),
        "train_ratio": train_ratio,
        "require_labels": require_labels,
        "totals": {
            "archives": len(zip_files),
            "malformed_archives": len(malformed),
            "images": len(all_entries),
            "archives_without_images": no_image_archives,
            "labels": dict(all_label_counter),
            "label_unknown": all_label_counter.get("missing", 0),
        },
        "archive_errors": archive_errors,
        "crops": manifest_per_crop,
        "samples": [asdict(entry) for entry in all_entries],
        "splits": {
            crop: split_data for crop, split_data in sorted(train_val_ids.items())
        },
    }
    return manifest


def emit_training_artifacts(
    manifest: Dict[str, Any],
    output_dir: Path,
    include_flags: Optional[List[str]] = None,
    exclude_flags: Optional[List[str]] = None,
) -> None:
    """Write per-crop train/val jsonl records for future Qwen tuning jobs."""
    output_dir.mkdir(parents=True, exist_ok=True)
    samples = {entry["sample_id"]: entry for entry in manifest.get("samples", [])}
    for crop, split in manifest.get("splits", {}).items():
        split_train = split.get("train", [])
        split_val = split.get("val", [])
        all_split_ids = split_train + split_val
        if not include_flags and not exclude_flags:
            stable_train = {"train": split_train, "val": split_val}
        else:
            filtered_sample_ids = [
                sample_id
                for sample_id in all_split_ids
                if _sample_matches_quality_filters(
                    samples.get(sample_id, {}),
                    include_flags=include_flags,
                    exclude_flags=exclude_flags,
                )
            ]
            crop_seed = f"{manifest.get('seed', 0)}:{crop}"
            stable_train = stable_split(
                filtered_sample_ids,
                seed=manifest.get("seed", 0),
                train_ratio=float(manifest.get("train_ratio", 0.8)),
                crop=crop_seed,
            )
        for split_name in ("train", "val"):
            output_path = output_dir / f"{crop}_{split_name}.jsonl"
            with output_path.open("w", encoding="utf-8") as handle:
                for sample_id in stable_train.get(split_name, []):
                    sample = samples.get(sample_id)
                    if not sample:
                        continue
                    sample_payload = {
                        "image_uri": sample.get("image_uri"),
                        "crop": sample.get("crop"),
                        "label": sample.get("label"),
                        "sample_id": sample_id,
                        "source_archive_path": sample.get("source_archive_path"),
                        "member_path": sample.get("member_path"),
                        "quality_flags": sample.get("quality_flags", []),
                        "split": split_name,
                    }
                    handle.write(json.dumps(sample_payload, ensure_ascii=False) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        default=str(PROJECT_ROOT / "crop_type_dataset"),
        help="Directory containing per-crop zip files.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_MANIFEST_PATH),
        help="Manifest output file path.",
    )
    parser.add_argument("--seed", type=int, default=1337, help="Deterministic seed for train/val split.")
    parser.add_argument(
        "--train-ratio",
        type=float,
        default=0.8,
        help="Train split ratio (val ratio is the remainder).",
    )
    parser.add_argument(
        "--require-labels",
        action="store_true",
        help="Fail manifest creation if any image is missing labels.",
    )
    parser.add_argument(
        "--emit-training-dir",
        default="",
        help="Optional path for per-crop JSONL training artifacts.",
    )
    parser.add_argument(
        "--require-quality-flags",
        default="",
        help="Comma-separated quality flags that must all be present for training export.",
    )
    parser.add_argument(
        "--exclude-quality-flags",
        default="",
        help="Comma-separated quality flags that exclude samples from training export.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    source_dir = Path(args.source_dir)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not 0.0 < args.train_ratio < 1.0:
        raise ValueError("train-ratio must be between 0 and 1.")

    manifest = build_manifest(
        source_dir=source_dir,
        seed=args.seed,
        train_ratio=args.train_ratio,
        require_labels=args.require_labels,
    )
    output_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    if args.emit_training_dir:
        include_quality_flags = _split_flags(args.require_quality_flags)
        exclude_quality_flags = _split_flags(args.exclude_quality_flags)
        emit_training_artifacts(
            manifest,
            Path(args.emit_training_dir),
            include_flags=include_quality_flags,
            exclude_flags=exclude_quality_flags,
        )
        include_text = ",".join(include_quality_flags) or "none"
        exclude_text = ",".join(exclude_quality_flags) or "none"
        print(
            f"Training artifacts written to {args.emit_training_dir} "
            f"with include_flags={include_text} exclude_flags={exclude_text}"
        )

    total = manifest["totals"]["images"]
    malformed = manifest["totals"]["malformed_archives"]
    label_unknown = manifest["totals"]["label_unknown"]
    print(f"Manifest written to {output_path}")
    print(
        f"Archives: {manifest['totals']['archives']} | images: {total} | missing labels: {label_unknown} | malformed archives: {malformed}"
    )
    for crop, details in manifest["crops"].items():
        print(
            f"{crop}: total={details['total']} train={len(details['split']['train'])} val={len(details['split']['val'])}"
        )


if __name__ == "__main__":
    main()
