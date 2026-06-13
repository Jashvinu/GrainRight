# AI Grain Grade

AI Grain Grade is a FastAPI + React application for grain quality grading. It combines image-derived OpenCV physics proxies, crop rules, lexical RAG over grading documents, and a cloud OpenAI-compatible Qwen-VL endpoint.

## What This Project Does

- Accepts a grain image and a moisture-meter display image through a React inspection console.
- Extracts the exact meter moisture value with OCR before grading.
- Requires grain type and variety selection from `knowledge/rag/crop_knowledge`.
- Extracts deterministic image signals with OpenCV from the grain image.
- Retrieves authoritative grading and moisture rules from local Markdown indexes.
- Calls the configured cloud Qwen-VL provider for meter OCR and vision inference.
- Applies deterministic safety and grading rules before returning the final result.
- Stores human corrections as feedback examples for reuse and audit review.

## Quick Start

1. Create and activate your Python environment.
2. Install backend dependencies:

```powershell
pip install -r requirements.txt
```

3. Create a local `.env` from the template:

```powershell
Copy-Item .env.example .env
```

4. Fill in `QWEN_VL_API_KEY` in `.env`.
5. Start the backend:

```powershell
uvicorn backend.app.main:app --reload --port 8000
```

6. Start the frontend in a second terminal:

```powershell
cd frontend
npm install
npm run dev
```

Frontend URL: `http://localhost:5173`
Backend health: `http://localhost:8000/api/health`
API docs: `http://localhost:8000/docs`

## Docker Deployment

For compose-based local validation:

```powershell
docker compose up --build
```

Compose starts:

- backend API on `http://localhost:8000`
- frontend dev server on `http://localhost:5173`
- feedback/upload data persisted in the `feedback_data` volume

Cloud Qwen inference is configured through runtime environment variables:

- `QWEN_VL_PROVIDER` - usually `dashscope` for the default cloud path.
- `QWEN_VL_API_KEY` - required API key for the configured provider.
- `QWEN_VL_BASE_URL` - optional OpenAI-compatible base URL override.
- `QWEN_VL_MODEL` - optional model override.
- `QWEN_VL_TIMEOUT_SECONDS` - optional request timeout override.
- `QWEN_VL_ENABLE_THINKING` - keep `false` for faster upload analysis and strict JSON output.
- `QWEN_VL_FALLBACK_MODELS` - comma-separated fallback list for DashScope invalid-model errors.

## Main Entry Points

- `backend/app/main.py` - FastAPI application and API routes.
- `backend/app/services.py` - runtime config, upload handling, model pipeline orchestration, feedback submission.
- `frontend/src/App.tsx` - React inspection workspace.
- `src/ai_grain_grade/vision_rag_pipeline.py` - cloud Qwen-VL calls, safety gate, RAG-guided grading, fallback logic.
- `src/ai_grain_grade/physics_proxies.py` - OpenCV feature extraction from grain images.
- `src/ai_grain_grade/rule_engine.py` - deterministic crop grading thresholds.
- `src/ai_grain_grade/rag_engine.py` - Markdown chunking and lexical retrieval.
- `src/ai_grain_grade/feedback.py` - JSON feedback storage and similar-correction retrieval.

## Directory Map

```text
.
|-- app.py                         # FastAPI app launcher
|-- backend/                       # FastAPI API layer
|-- frontend/                      # React + Vite + TypeScript app
|-- Dockerfile                     # Backend container image
|-- docker-compose.yml             # Local backend/frontend validation
|-- src/ai_grain_grade/            # Core Python model package
|-- tests/                         # Python tests
|-- requirements.txt               # Backend Python dependencies
|-- .env.example                   # Local environment template
|-- data/rag/                      # Local RAG indexes
|-- data/feedback/                 # Example and runtime feedback records
|-- knowledge/rag/                 # Runtime RAG source documents
|-- examples/                      # Example calibration images
|-- graphify-out/                  # Code knowledge graph outputs
|-- scripts/                       # Local helper scripts
|-- supabase/                      # Supabase migrations and edge functions
```

## API

- `GET /api/health` - service readiness, runtime status, feedback count.
- `GET /api/runtime` - model/provider status without secrets.
- `GET /api/crops` - crop and variety catalog derived from `knowledge/rag/crop_knowledge`.
- `POST /api/analyze` - multipart upload with:
  - `grain_image`: grain lot JPG/PNG.
  - `moisture_image`: moisture machine display JPG/PNG.
  - `crop_type`: one of the crop catalog values, such as `finger_millets`, `rice`, or `bajra`.
  - `crop_variety`: selected variety label.
  - `confidence_threshold`: optional 0-100 review floor.
  - `manual_moisture_percent`: backend-only operator fallback when the meter display is unreadable; the React app uses OCR from `moisture_image`.
- `POST /api/feedback` - stores operator correction for a previous analysis.

## Runtime Configuration

The active app reads these Qwen variables:

- `QWEN_VL_PROVIDER` - `dashscope`, `siliconflow`, or `custom`.
- `QWEN_VL_API_KEY` - preferred API key variable.
- `DASHSCOPE_API_KEY` - DashScope fallback alias.
- `QWEN_VL_BASE_URL` - optional OpenAI-compatible base URL override.
- `QWEN_VL_MODEL` - optional model override.
- `QWEN_VL_TIMEOUT_SECONDS` - optional cloud request timeout.
- `QWEN_VL_ENABLE_THINKING` - defaults to `false` for Qwen3-VL calls.
- `QWEN_VL_FALLBACK_MODELS` - defaults to `qwen3-vl-flash,qwen-vl-plus`.
- `CROP_MODEL_ROUTES` - optional JSON map for crop-specific routing.
- `CROP_MODEL_ROUTES_PATH` - optional path containing the same crop route map.

Secrets belong in `.env`; `.env` and `*.env` are ignored by git.

## RAG Knowledge Sources

The local RAG index reads:

- `knowledge/rag/FAO_BIS_RAGI_RULES.md`
- `knowledge/rag/AUTHORIZED_RAGI_DATA_SOURCES.md`
- `knowledge/rag/ARCHITECTURE.md`
- `knowledge/rag/UNIFIED_RAGI_QUALITY_AND_MOISTURE_SPEC.md`
- `knowledge/rag/crop_knowledge/**/*`

The chunk index lives at `data/rag/rag_index.json`.

## Tests

Run the backend and model tests with:

```powershell
python -m pytest
```

Run the frontend build check with:

```powershell
cd frontend
npm run build
```

Cloud provider tests mock HTTP calls and do not require a real API key.

## Project Notes

- Supabase migrations are present for future persistent storage, but the active app currently stores feedback as local JSON.
- `graphify-out/GRAPH_REPORT.md` is useful for architecture navigation; the central nodes are `FeedbackCollector`, `PhysicsProxiesExtractor`, `RAGEngine`, and `VisionRAGPipeline`.
