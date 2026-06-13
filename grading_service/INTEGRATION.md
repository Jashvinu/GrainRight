# grading_service — REFERENCE ONLY (not deployed)

This directory is **vendored** from
[Atharva-007/GrainGrade-Detection](https://github.com/Atharva-007/GrainGrade-Detection) and is kept
as the **reference implementation** of the grain-grading pipeline.

> ⚠️ The app does **not** call this service. Grain grading runs in **Supabase Edge Functions**
> (`supabase/functions/grain-grade`, `grain-grade-feedback`, `grain-crops`) like the rest of the
> app's AI. The deterministic rule thresholds in `_shared/grain-rules.ts` are ported from this
> project's `src/ai_grain_grade/rule_engine.py` + `moisture_calibration.py`. Keep them in sync.

- **What it is:** a FastAPI service that grades a grain lot from a grain + moisture-meter photo
  using OpenCV proxies, a crop rule engine, RAG over BIS/FAO docs, and a Qwen-VL model. See
  `README.md` for upstream docs.
- **Why keep it:** it is the authoritative source for the grading rules and the BIS/FAO knowledge
  base under `knowledge/rag/`. Use it to validate or extend the TypeScript port.
- **Live integration:** [`../docs/11_grain_grading_integration.md`](../docs/11_grain_grading_integration.md).

## Run locally (for reference / rule validation only)

```bash
cd grading_service
pip install -r requirements.txt
cp .env.example .env          # set QWEN_VL_API_KEY (reuse the app's VLM key)
uvicorn backend.app.main:app --reload --port 8000
```
