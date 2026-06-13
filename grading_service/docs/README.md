# Documentation Index

This folder contains the project documentation that is not required to stay at the repository root.

## Main Sets

- `prompts/model-doc/` - ragi grading prompt documents and product/model planning notes.
- `specs/ai-grain-moisture/` - moisture estimation, capture, preprocessing, training, mobile, backend, confidence, and roadmap specs.
- `archive/grain-grade-md-files/` - preserved imported export of the older "Grain Grade MD files" folder.

## RAG Docs Used by Runtime

The RAG engine reads these files from `rag/`:

- `rag/FAO_BIS_RAGI_RULES.md`
- `rag/AUTHORIZED_RAGI_DATA_SOURCES.md`
- `rag/ARCHITECTURE.md`
- `rag/UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md`
- `rag/crop_knowledge/**/*` when available

Do not move those four files without updating `src/ai_grain_grade/rag_engine.py` and rebuilding `data/rag/rag_index.json`.
