from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class RuntimeStatus(BaseModel):
    runtime_online: bool
    model_ready: bool
    runtime_label: str
    runtime_detail: str
    chunk_count: int
    crop_route_count: int = 0
    provider: str
    model: str
    provider_label: str


class HealthResponse(BaseModel):
    status: str
    runtime: RuntimeStatus
    pending_feedback: int


class CropVariety(BaseModel):
    value: str
    label: str
    source_file: Optional[str] = None


class CropOption(BaseModel):
    value: str
    label: str
    aliases: List[str] = Field(default_factory=list)
    varieties: List[CropVariety] = Field(default_factory=list)
    rule_summary: List[str] = Field(default_factory=list)


class CropCatalogResponse(BaseModel):
    crops: List[CropOption]


class AnalyzeResponse(BaseModel):
    analysis_id: str
    image_name: str
    grain_image_name: str
    moisture_image_name: Optional[str] = None
    quality: Dict[str, Any]
    moisture: Dict[str, Any]
    confidence: Dict[str, Any]
    selection: Dict[str, Any]
    routing: Dict[str, Any]
    applied_rules: List[Dict[str, Any]]
    audit: Dict[str, Any]
    proxy_summary: Dict[str, Any]
    manual_review_required: bool
    operator_summary: str
    signal_highlights: List[str]


class FeedbackRequest(BaseModel):
    analysis_id: str = Field(..., min_length=1)
    true_grade: str = Field(..., pattern="^(A|B|C)$")
    true_grain_grade: Optional[str] = Field(None, pattern="^(A|B|C)$")
    true_moisture_risk: str = Field(..., pattern="^(LOW|MODERATE|HIGH|CRITICAL)$")
    notes: str = ""


class FeedbackResponse(BaseModel):
    saved: bool
    pending_count: int
    analysis_id: str
    feedback_path: Optional[str] = None
    training_export_saved: bool = False
    session_log_path: Optional[str] = None


class AnalysisCreateRequest(BaseModel):
    crop_type: str = Field("finger_millets", min_length=1)
    variety: str = ""
    crop_variety: str = ""
    operator_id: Optional[str] = None
    tenant_id: Optional[str] = None
    batch_id: Optional[str] = None
    manual_moisture_percent: Optional[float] = Field(None, gt=0, le=50)
    confidence_threshold: int = Field(60, ge=0, le=100)


class AnalysisCreateResponse(BaseModel):
    analysis_id: str
    status: str
    grain_upload_path: str
    moisture_upload_path: Optional[str] = None


class AnalysisSubmitRequest(BaseModel):
    grain_image_path: str = Field(..., min_length=1)
    moisture_image_path: Optional[str] = None


class AnalysisJobResponse(BaseModel):
    analysis_id: str
    status: str
    job: Dict[str, Any]


class AnalysisSubmitResponse(BaseModel):
    analysis_id: str
    status: str
    background_started: bool = False


class OperatorCorrectionRequest(BaseModel):
    analysis_id: str = Field(..., min_length=1)
    corrected_final_grade: str = Field(..., pattern="^(A|B|C)$")
    corrected_grain_grade: Optional[str] = Field(None, pattern="^(A|B|C)$")
    corrected_moisture_percent: Optional[float] = Field(None, gt=0, le=50)
    notes: str = ""


class OperatorCorrectionResponse(BaseModel):
    saved: bool
    analysis_id: str
    correction: Dict[str, Any]


class ApiError(BaseModel):
    detail: str
    code: Optional[str] = None
