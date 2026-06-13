"""
RAG engine for ragi grading knowledge retrieval.

This version indexes the authoritative root Markdown specs, chunks them
carefully, and retrieves with a weighted lexical scorer. It deliberately avoids
local embedding models so production inference stays cloud-Qwen only.
"""

from __future__ import annotations

import json
import logging
import math
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from .paths import LEGACY_RAG_DOCS_DIR, PROJECT_ROOT, RAG_DOCS_DIR, RAG_INDEX_PATH

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOKEN_RE = re.compile(r"[a-z0-9]+")
HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*$")
MAX_CHARS_PER_CHUNK = 1200
OVERLAP_CHARS = 180
INDEX_VERSION = 2
DEFAULT_INDEX_PATH = RAG_INDEX_PATH
DEFAULT_DOCS_DIR = RAG_DOCS_DIR
LEGACY_DOCS_DIR = LEGACY_RAG_DOCS_DIR
CROP_KNOWLEDGE_DIR = DEFAULT_DOCS_DIR / "crop_knowledge"
CROP_KNOWLEDGE_EXTENSIONS = {".md", ".markdown", ".yaml", ".yml"}


def _norm_path(path: str | Path) -> str:
    return Path(path).as_posix().lower()


class RAGEngine:
    def __init__(
        self,
        index_path: str | Path = DEFAULT_INDEX_PATH,
        retrieval_mode: str = "lexical",
    ):
        self.index_path = Path(index_path)
        self.repo_root = PROJECT_ROOT
        self.docs_dir = DEFAULT_DOCS_DIR if DEFAULT_DOCS_DIR.exists() else LEGACY_DOCS_DIR
        self.crop_docs_dir = self.docs_dir / "crop_knowledge"
        self.retrieval_mode = "lexical"
        if retrieval_mode.lower().strip() != "lexical":
            logger.warning("Only lexical RAG is supported in the cloud-only build.")
        self.chunks: List[Dict[str, Any]] = []
        self._search_docs: Optional[List[Dict[str, Any]]] = None
        self.load_index()

    def _invalidate_cache(self):
        self._search_docs = None

    def load_index(self):
        """Load an existing chunk index from disk."""
        self._invalidate_cache()
        if not self.index_path.exists():
            logger.warning("RAG index not found. Call index_documents() to build it.")
            self.chunks = []
            return

        try:
            with open(self.index_path, "r", encoding="utf-8") as f:
                payload = json.load(f)

            if isinstance(payload, dict):
                payload = payload.get("chunks", [])
            if not isinstance(payload, list):
                raise ValueError("RAG index payload must be a list of chunks")

            self.chunks = [chunk for chunk in payload if isinstance(chunk, dict)]
            logger.info("✓ Loaded %s chunks from %s", len(self.chunks), self.index_path)
        except Exception as e:
            logger.error("Failed to load index: %s", e)
            self.chunks = []

    def save_index(self):
        """Persist the current chunk list to disk."""
        try:
            with open(self.index_path, "w", encoding="utf-8") as f:
                json.dump(self.chunks, f, indent=2, ensure_ascii=False)
            logger.info("✓ Saved %s chunks to %s", len(self.chunks), self.index_path)
        except Exception as e:
            logger.error("Failed to save index: %s", e)

    def needs_rebuild(self) -> bool:
        """Detect whether the on-disk index predates the current chunk schema."""
        if not self.chunks:
            return True
        sample = self.chunks[0]
        existing_sources = {str(chunk.get("source", "")) for chunk in self.chunks}
        required_sources = {
            str(path.relative_to(self.repo_root)).replace("\\", "/")
            for path in self.discover_documents()
            if path.exists()
        }
        return (
            sample.get("index_version") != INDEX_VERSION
            or "source_priority" not in sample
            or "position" not in sample
            or "tags" not in sample
            or not required_sources.issubset(existing_sources)
        )

    def discover_documents(self) -> List[Path]:
        """Discover the canonical Markdown sources for retrieval."""
        canonical = [
            self.docs_dir / filename
            for filename in (
                "FAO_BIS_RAGI_RULES.md",
                "AUTHORIZED_RAGI_DATA_SOURCES.md",
                "ARCHITECTURE.md",
                "UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md",
            )
        ]

        ordered_paths: List[Path] = [*canonical]
        if self.crop_docs_dir.exists():
            for candidate in sorted(self.crop_docs_dir.rglob("*"), key=lambda item: str(item).lower()):
                if not candidate.is_file():
                    continue
                if candidate.suffix.lower() not in CROP_KNOWLEDGE_EXTENSIONS and candidate.suffix != "":
                    continue
                ordered_paths.append(candidate)

        # Keep deterministic order while deduplicating path aliases.
        deduped: List[Path] = []
        seen: set[str] = set()
        for path in ordered_paths:
            key = str(path.resolve()).lower()
            if key in seen:
                continue
            seen.add(key)
            deduped.append(path)
        return deduped

    def _is_retrieval_document(self, path: Path) -> bool:
        norm = _norm_path(path.relative_to(self.repo_root))
        if norm in {
            "knowledge/rag/unified_ragi_quality_and_moisture_spec.md",
            "knowledge/rag/architecture.md",
            "knowledge/rag/fao_bis_ragi_rules.md",
            "knowledge/rag/authorized_ragi_data_sources.md",
            "docs/rag/unified_ragi_quality_and_moisture_spec.md",
            "docs/rag/architecture.md",
            "docs/rag/fao_bis_ragi_rules.md",
            "docs/rag/authorized_ragi_data_sources.md",
        }:
            return True
        if norm.startswith("knowledge/rag/crop_knowledge/"):
            return True
        if norm.startswith("docs/rag/crop_knowledge/"):
            return True
        return False

    def index_documents(self, doc_paths: Optional[List[str]] = None):
        """Chunk and index the knowledge-base Markdown corpus."""
        if doc_paths is None:
            paths = self.discover_documents()
        else:
            paths = [Path(path_str) for path_str in doc_paths]

        self.chunks = []
        self._invalidate_cache()

        for path in paths:
            if not path.exists():
                logger.warning("Document not found: %s", path)
                continue

            logger.info("Indexing %s...", path)
            self.chunks.extend(self._chunk_markdown(path))

        self.save_index()

    def _chunk_markdown(self, path: Path) -> List[Dict[str, Any]]:
        text = self._read_text(path)
        if not text.strip():
            return []

        resolved_path = path.resolve()
        try:
            relative_source = str(resolved_path.relative_to(self.repo_root)).replace("\\", "/")
        except ValueError:
            relative_source = str(path).replace("\\", "/")
        source_priority = self._source_priority(relative_source)
        chunks: List[Dict[str, Any]] = []
        position = 0

        current_title = path.stem.replace("_", " ")
        current_level = 0
        buffer: List[str] = []

        def flush_section(title: str, heading_level: int, body_lines: List[str]):
            nonlocal position
            body = "\n".join(body_lines).strip()
            if not body:
                return
            parts = self._split_body(body)
            for part_index, part in enumerate(parts):
                chunk_title = title if len(parts) == 1 else f"{title} (part {part_index + 1})"
                tags = self._derive_tags(relative_source, chunk_title, part)
                chunks.append(
                    {
                        "id": f"{path.stem}_{position:04d}",
                        "source": relative_source,
                        "title": chunk_title,
                        "content": part,
                        "tokens": self._tokenize(f"{chunk_title}\n{part}"),
                        "source_priority": source_priority,
                        "position": position,
                        "section_level": heading_level,
                        "tags": sorted(tags),
                        "index_version": INDEX_VERSION,
                    }
                )
                position += 1

        for line in text.splitlines():
            heading_match = HEADING_RE.match(line)
            if heading_match:
                flush_section(current_title, current_level, buffer)
                current_level = len(heading_match.group(1))
                current_title = heading_match.group(2).strip()
                buffer = []
                continue
            buffer.append(line)

        flush_section(current_title, current_level, buffer)
        return chunks

    def _split_body(self, body: str) -> List[str]:
        body = body.strip()
        if not body:
            return []
        if len(body) <= MAX_CHARS_PER_CHUNK:
            return [body]

        parts: List[str] = []
        start = 0
        while start < len(body):
            end = min(len(body), start + MAX_CHARS_PER_CHUNK)
            if end < len(body):
                soft_break = body.rfind("\n", start + MAX_CHARS_PER_CHUNK // 2, end)
                if soft_break > start:
                    end = soft_break
            part = body[start:end].strip()
            if part:
                parts.append(part)
            if end >= len(body):
                break
            next_start = max(start + 1, end - OVERLAP_CHARS)
            if next_start <= start:
                next_start = end
            start = next_start
        return parts

    def _read_text(self, path: Path) -> str:
        try:
            return path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            return path.read_text(encoding="cp1252", errors="replace")

    def _source_priority(self, source: str) -> float:
        norm = _norm_path(source)
        priority_rules = [
            ("fao_bis_ragi_rules.md", 6.0),
            ("authorized_ragi_data_sources.md", 5.5),
            ("unified_ragi_quality_and_moisture_spec.md", 5.0),
            ("architecture.md", 4.0),
        ]
        if "/crop_knowledge/" in f"/{norm}":
            if "grading_rules" in norm:
                return 4.5
            return 3.5
        for pattern, priority in priority_rules:
            if pattern in norm:
                return priority
        return 2.5

    def _derive_tags(self, source: str, title: str, content: str) -> set[str]:
        tags = set(self._tokenize(f"{source} {title}"))
        text = f"{title}\n{content[:400]}".lower()
        keyword_groups = {
            "grade": ["grade", "grading", "quality", "matrix", "score"],
            "moisture": ["moisture", "clumping", "darkness", "calibration"],
            "safety": ["hazard", "mold", "insect", "webbing", "foreign", "stone"],
            "confidence": ["confidence", "uncertainty", "retake"],
            "training": ["training", "dataset", "split", "feedback"],
            "validation": ["validation", "reject", "blur", "exposure", "screenshot"],
            "standards": ["fao", "bis", "standard", "procurement", "sampling"],
            "thresholds": ["threshold", "limit", "range", "percent"],
        }
        for tag, keywords in keyword_groups.items():
            if any(keyword in text for keyword in keywords):
                tags.add(tag)
        return tags

    def _tokenize(self, text: str) -> List[str]:
        return [
            tok
            for tok in TOKEN_RE.findall(text.lower())
            if len(tok) > 1 or tok in {"a", "b", "c"}
        ]

    def _build_search_docs(self) -> List[Dict[str, Any]]:
        docs: List[Dict[str, Any]] = []
        if not self.chunks:
            return docs

        doc_freq: Dict[str, int] = {}
        tokenized: List[List[str]] = []

        for chunk in self.chunks:
            tokens = chunk.get("tokens") or self._tokenize(
                f"{chunk.get('title', '')}\n{chunk.get('content', '')}"
            )
            tokenized.append(tokens)
            for token in set(tokens):
                doc_freq[token] = doc_freq.get(token, 0) + 1

        num_docs = len(self.chunks)
        for chunk, tokens in zip(self.chunks, tokenized):
            tf: Dict[str, int] = {}
            for token in tokens:
                tf[token] = tf.get(token, 0) + 1

            docs.append(
                {
                    "chunk": chunk,
                    "tokens": tokens,
                    "tf": tf,
                    "doc_freq": doc_freq,
                    "num_docs": num_docs,
                    "source_norm": _norm_path(chunk["source"]),
                    "title_lc": chunk["title"].lower(),
                    "text_lc": chunk["content"].lower(),
                    "tag_set": set(chunk.get("tags", [])),
                }
            )
        return docs

    def _ensure_search_docs(self) -> List[Dict[str, Any]]:
        if self._search_docs is None:
            self._search_docs = self._build_search_docs()
        return self._search_docs

    def _select_scored_chunks(
        self,
        scored: List[tuple[Dict[str, Any], float]],
        k: int,
        retrieval_method: str,
    ) -> List[Dict[str, Any]]:
        scored.sort(key=lambda item: item[1], reverse=True)

        selected: List[Dict[str, Any]] = []
        per_source_counts: Dict[str, int] = {}
        seen_titles: set[tuple[str, str]] = set()

        for chunk, score in scored:
            source = chunk["source"]
            title_key = (source, chunk["title"])
            if per_source_counts.get(source, 0) >= 2:
                continue
            if title_key in seen_titles and len(selected) >= max(2, k // 2):
                continue

            item = dict(chunk)
            item["retrieval_score"] = round(float(score), 4)
            item["retrieval_method"] = retrieval_method
            selected.append(item)
            seen_titles.add(title_key)
            per_source_counts[source] = per_source_counts.get(source, 0) + 1

            if len(selected) >= k:
                break

        return selected

    def _query_intent_boost(
        self,
        doc: Dict[str, Any],
        query_lc: str,
        query_terms: List[str],
    ) -> float:
        score = 0.0
        source_norm = doc["source_norm"]
        title_lc = doc["title_lc"]
        text_lc = doc["text_lc"]

        if "grade a" in query_lc and "grade_a_ragi_vision_prompt.md" in source_norm:
            score += 2.4
        if "grade a" in query_lc and "grade a" in title_lc:
            score += 1.6
        if "grade b" in query_lc and "grade_b_ragi_vision_prompt.md" in source_norm:
            score += 2.4
        if "grade b" in query_lc and "grade b" in title_lc:
            score += 1.6
        if "grade c" in query_lc and "grade_c_ragi_vision_prompt.md" in source_norm:
            score += 2.4
        if "grade c" in query_lc and "grade c" in title_lc:
            score += 1.6
        if any(term in query_terms for term in ("threshold", "matrix", "bimodal")):
            if "grades_comparison.md" in source_norm:
                score += 2.0
        if any(term in query_terms for term in ("confidence", "uncertainty")):
            if "confidence_system.md" in source_norm:
                score += 2.0
        if any(term in query_terms for term in ("calibration", "meter")):
            if "calibration_system.md" in source_norm:
                score += 2.0
        if any(term in query_terms for term in ("failure", "reject", "retake", "screenshot")):
            if "failure_modes.md" in source_norm or "image_validation.md" in source_norm:
                score += 2.1
        if any(term in query_terms for term in ("feedback", "dataset", "training")):
            if "training_pipeline.md" in source_norm or "dataset_collection.md" in source_norm:
                score += 1.8
        if any(term in title_lc for term in ("grade", "quality")) and "grade" in query_terms:
            score += 0.4
        if "finger millet" in query_lc and "finger millet" in text_lc[:300]:
            score += 0.25
        return score

    def retrieve(self, query: str, k: int = 5) -> List[Dict[str, Any]]:
        """Retrieve top-k chunks using lexical scoring."""
        return self._retrieve_lexical(query, k)

    def _retrieve_lexical(self, query: str, k: int = 5) -> List[Dict[str, Any]]:
        """Retrieve top-k chunks using weighted lexical scoring with source priors."""
        docs = self._ensure_search_docs()
        if not docs:
            return []

        query_terms = self._tokenize(query)
        if not query_terms:
            return []

        unique_terms = set(query_terms)
        query_lc = query.lower()
        scored: List[tuple[Dict[str, Any], float]] = []

        for doc in docs:
            tf = doc["tf"]
            doc_freq = doc["doc_freq"]
            num_docs = doc["num_docs"]
            title_lc = doc["title_lc"]
            text_lc = doc["text_lc"]
            token_count = max(1, len(doc["tokens"]))

            score = 0.0
            term_hits = 0

            for term in unique_terms:
                freq = tf.get(term, 0)
                if not freq:
                    continue
                term_hits += 1
                idf = math.log(1.0 + (num_docs + 1) / (1 + doc_freq.get(term, 0)))
                score += (1.0 + math.log(freq)) * idf
                if term in title_lc:
                    score += 0.45 * idf
                if f" {term} " in f" {text_lc} ":
                    score += 0.12 * idf

            if not term_hits:
                continue

            coverage = term_hits / max(1, len(unique_terms))
            score *= 0.65 + 0.35 * coverage
            score /= token_count ** 0.18
            score += 0.35 * float(doc["chunk"].get("source_priority", 1.0))

            tag_overlap = len(doc["tag_set"].intersection(unique_terms))
            score += 0.18 * tag_overlap
            score += self._query_intent_boost(doc, query_lc, query_terms)

            scored.append((doc["chunk"], float(score)))

        return self._select_scored_chunks(scored, k, "lexical")

    def format_context(
        self,
        retrieved_chunks: List[Dict[str, Any]],
        reverse: bool = True,
    ) -> str:
        """
        Format retrieved chunks for prompt use.

        When reverse=True, the most relevant chunk is placed last so it sits
        closest to the task instruction in the final prompt.
        """
        if not retrieved_chunks:
            return "No relevant documents found in the knowledge base."

        ordered = list(retrieved_chunks)
        ordered.sort(
            key=lambda chunk: (
                chunk.get("retrieval_score", 0.0),
                chunk.get("source_priority", 0.0),
                chunk.get("position", 0),
            ),
            reverse=not reverse,
        )

        parts = ["### KNOWLEDGE BASE CONTEXT ###"]
        for chunk in ordered:
            parts.append(
                (
                    f"\nSOURCE: {chunk['source']} | SECTION: {chunk['title']} "
                    f"| SCORE: {chunk.get('retrieval_score', 0.0):.2f}"
                )
            )
            parts.append(chunk["content"])
            parts.append("-" * 40)
        return "\n".join(parts)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    engine = RAGEngine(retrieval_mode="lexical")
    engine.index_documents()
    results = engine.retrieve("What are the Grade A criteria and failure modes?", k=5)
    print(engine.format_context(results))
