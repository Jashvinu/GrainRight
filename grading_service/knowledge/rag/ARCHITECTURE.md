# Cloud Qwen3-VL RAG Architecture

This document describes the production inference architecture used by the
Streamlit app. The active runtime is cloud-only for model inference: no local
vision model, model weights, adapter weights, or local embedding model is loaded
by the app or Docker image.

## Runtime Flow

1. The operator uploads one ragi lot image.
2. OpenCV extracts deterministic physics proxies such as darkness, clumping,
   texture entropy, roughness, mask coverage, and calibrated grain geometry.
3. The lexical RAG engine retrieves the most relevant rule chunks from
   `docs/rag/` and the prebuilt `data/rag/rag_index.json`.
4. The app calls the configured cloud OpenAI-compatible Qwen3-VL endpoint.
5. The rule engine applies FAO/BIS-aligned guardrails over the model JSON.
6. The UI stores operator corrections as JSON feedback for future prompt
   context and audit review.

## Cloud Provider Contract

Supported providers are:

- `dashscope`
- `siliconflow`
- `custom`

Required runtime variables:

- `QWEN_VL_PROVIDER`
- `QWEN_VL_API_KEY`

Optional runtime variables:

- `QWEN_VL_BASE_URL`
- `QWEN_VL_MODEL`
- `QWEN_VL_TIMEOUT_SECONDS`

Localhost model endpoints are intentionally rejected by the Streamlit runtime.

## RAG Retrieval

The RAG engine uses weighted lexical scoring with source priorities and
domain-specific query boosts. It does not load sentence-transformer or other
local embedding models. This keeps Docker deployment portable and ensures
model reasoning comes from the cloud Qwen3-VL endpoint.

## Feedback Loop

Feedback records are stored under `data/feedback/feedback_data` as JSON.
Similar corrections are retrieved and summarized into future prompts, but the
application does not fine-tune or load model adapters. A deployment may export
the correction queue for separate offline review, but that is outside the
running app and outside the Docker image.

## Safety Behavior

Cloud Qwen3-VL performs the image interpretation, while deterministic code
remains responsible for:

- image quality checks
- moisture proxy estimation
- FAO/BIS threshold enforcement
- reject/hold guardrails
- confidence and manual-review flags

If the cloud endpoint is not configured, the UI disables analysis and shows the
missing environment variables.
