from __future__ import annotations

import os
import uuid
from pathlib import Path
from typing import Optional

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .schemas import (
    AnalysisCreateRequest,
    AnalysisCreateResponse,
    AnalysisJobResponse,
    AnalysisSubmitRequest,
    AnalysisSubmitResponse,
    AnalyzeResponse,
    CropCatalogResponse,
    FeedbackRequest,
    FeedbackResponse,
    HealthResponse,
    OperatorCorrectionRequest,
    OperatorCorrectionResponse,
    RuntimeStatus,
)
from .job_runner import run_analysis_job
from .services import AppServices, get_services, runtime_status
from .supabase_store import SupabaseStore, get_supabase_store, utc_now


app = FastAPI(
    title="AI Grain Grade API",
    version="1.0.0",
    description="FastAPI backend for grain image grading with OpenCV proxies, RAG rules, and Qwen-VL inference.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:4173",
        "http://127.0.0.1:4173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health", response_model=HealthResponse)
def health(services: AppServices = Depends(get_services)) -> dict:
    return services.health()


@app.get("/api/runtime", response_model=RuntimeStatus)
def runtime() -> dict:
    return runtime_status()


@app.get("/api/crops", response_model=CropCatalogResponse)
def crops(services: AppServices = Depends(get_services)) -> dict:
    return services.crop_catalog()


@app.get("/api/v1/crops", response_model=CropCatalogResponse)
def crops_v1(services: AppServices = Depends(get_services)) -> dict:
    return services.crop_catalog()


@app.post("/api/analyze", response_model=AnalyzeResponse)
async def analyze(
    grain_image: Optional[UploadFile] = File(None),
    moisture_image: Optional[UploadFile] = File(None),
    image: Optional[UploadFile] = File(None),
    crop_type: str = Form("finger_millets"),
    crop_variety: str = Form(""),
    manual_moisture_percent: Optional[float] = Form(None),
    confidence_threshold: int = Form(60),
    services: AppServices = Depends(get_services),
) -> dict:
    if confidence_threshold < 0 or confidence_threshold > 100:
        raise HTTPException(status_code=422, detail="confidence_threshold must be between 0 and 100.")
    grain_upload = grain_image or image
    if grain_upload is None:
        raise HTTPException(status_code=422, detail="Upload a grain image.")
    if moisture_image is None and manual_moisture_percent is None:
        raise HTTPException(status_code=422, detail="Upload a moisture meter image or enter a machine moisture percent.")

    image_path = await services.save_upload(grain_upload, purpose="grain")
    moisture_image_path = None
    moisture_image_name = None
    if moisture_image is not None:
        moisture_image_path = await services.save_upload(moisture_image, purpose="moisture_meter")
        moisture_image_name = moisture_image.filename or Path(moisture_image_path).name
    moisture_reading = services.extract_moisture_reading(
        moisture_image_path,
        manual_moisture_percent=manual_moisture_percent,
    )
    return services.analyze(
        image_path=image_path,
        image_name=grain_upload.filename or Path(image_path).name,
        crop_type=crop_type,
        crop_variety=crop_variety,
        moisture_image_path=moisture_image_path,
        moisture_image_name=moisture_image_name,
        moisture_reading=moisture_reading,
        confidence_threshold=confidence_threshold,
    )


@app.post("/api/feedback", response_model=FeedbackResponse)
def feedback(
    request: FeedbackRequest,
    services: AppServices = Depends(get_services),
) -> dict:
    return services.submit_feedback(
        analysis_id=request.analysis_id,
        true_grade=request.true_grade,
        true_grain_grade=request.true_grain_grade,
        true_moisture_risk=request.true_moisture_risk,
        notes=request.notes,
    )


@app.post("/api/v1/analysis", response_model=AnalysisCreateResponse)
def create_analysis(
    request: AnalysisCreateRequest,
    authorization: Optional[str] = Header(None),
    store: SupabaseStore = Depends(get_supabase_store),
) -> dict:
    user = store.authorize_user(authorization)
    analysis_id = str(uuid.uuid4())
    variety = (request.variety or request.crop_variety or "").strip()
    operator_id = request.operator_id or user.get("id")
    upload_paths = store.build_storage_paths(analysis_id, owner_id=operator_id)
    row = {
        "id": analysis_id,
        "operator_id": operator_id,
        "tenant_id": request.tenant_id,
        "batch_id": request.batch_id,
        "crop_type": request.crop_type,
        "variety": variety,
        "status": "created",
        "grain_image_path": upload_paths["grain"],
        "moisture_image_path": upload_paths["moisture"] if request.manual_moisture_percent is None else None,
        "manual_moisture_percent": request.manual_moisture_percent,
        "confidence_threshold": request.confidence_threshold,
        "created_at": utc_now(),
        "updated_at": utc_now(),
    }
    created = store.create_analysis_job(row)
    return {
        "analysis_id": created.get("id", analysis_id),
        "status": created.get("status", "created"),
        "grain_upload_path": upload_paths["grain"],
        "moisture_upload_path": upload_paths["moisture"] if request.manual_moisture_percent is None else None,
    }


@app.post("/api/v1/analysis/{analysis_id}/submit", response_model=AnalysisSubmitResponse)
def submit_analysis(
    analysis_id: str,
    request: AnalysisSubmitRequest,
    background_tasks: BackgroundTasks,
    authorization: Optional[str] = Header(None),
    services: AppServices = Depends(get_services),
    store: SupabaseStore = Depends(get_supabase_store),
) -> dict:
    store.authorize_user(authorization)
    job = store.get_analysis_job(analysis_id)
    if not request.moisture_image_path and job.get("manual_moisture_percent") is None:
        raise HTTPException(status_code=422, detail="moisture_image_path is required unless manual moisture was provided.")
    updated = store.update_analysis_job(
        analysis_id,
        {
            "status": "queued",
            "grain_image_path": request.grain_image_path,
            "moisture_image_path": request.moisture_image_path,
            "error_message": None,
        },
    )
    store.insert_analysis_log(
        analysis_id,
        "queued",
        {
            "grain_image_path": request.grain_image_path,
            "moisture_image_path": request.moisture_image_path,
        },
        service="api-gateway",
    )
    run_in_background = os.getenv("GRADING_BACKGROUND_ON_SUBMIT", "1").strip().lower() not in {"0", "false", "no"}
    if run_in_background:
        background_tasks.add_task(run_analysis_job, analysis_id, store, services)
    return {
        "analysis_id": analysis_id,
        "status": updated.get("status", "queued"),
        "background_started": run_in_background,
    }


@app.get("/api/v1/analysis/{analysis_id}", response_model=AnalysisJobResponse)
def get_analysis(
    analysis_id: str,
    authorization: Optional[str] = Header(None),
    store: SupabaseStore = Depends(get_supabase_store),
) -> dict:
    store.authorize_user(authorization)
    job = store.get_analysis_job(analysis_id)
    return {
        "analysis_id": analysis_id,
        "status": job.get("status", "unknown"),
        "job": job,
    }


@app.post("/api/v1/feedback", response_model=OperatorCorrectionResponse)
def feedback_v1(
    request: OperatorCorrectionRequest,
    authorization: Optional[str] = Header(None),
    store: SupabaseStore = Depends(get_supabase_store),
) -> dict:
    user = store.authorize_user(authorization)
    job = store.get_analysis_job(request.analysis_id)
    row = {
        "analysis_id": request.analysis_id,
        "operator_id": user.get("id") or job.get("operator_id"),
        "predicted_final_grade": job.get("final_grade"),
        "corrected_final_grade": request.corrected_final_grade,
        "predicted_grain_grade": job.get("grain_grade"),
        "corrected_grain_grade": request.corrected_grain_grade or request.corrected_final_grade,
        "predicted_moisture_percent": job.get("moisture_percent"),
        "corrected_moisture_percent": request.corrected_moisture_percent,
        "notes": request.notes,
    }
    correction = store.insert_operator_correction(row)
    store.insert_analysis_log(
        request.analysis_id,
        "operator_correction",
        correction,
        service="api-gateway",
    )
    return {
        "saved": True,
        "analysis_id": request.analysis_id,
        "correction": correction,
    }


FRONTEND_DIST = Path(__file__).resolve().parents[2] / "frontend" / "dist"
if FRONTEND_DIST.exists():
    app.mount("/assets", StaticFiles(directory=FRONTEND_DIST / "assets"), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    def serve_frontend(full_path: Optional[str] = None) -> FileResponse:
        path = FRONTEND_DIST / (full_path or "")
        if path.is_file():
            return FileResponse(path)
        return FileResponse(FRONTEND_DIST / "index.html")
