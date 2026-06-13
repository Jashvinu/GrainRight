from __future__ import annotations

import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote

import httpx
from dotenv import load_dotenv
from fastapi import HTTPException

from ai_grain_grade.paths import PROJECT_ROOT, SESSION_UPLOADS_DIR


DEFAULT_GRAIN_BUCKET = "grain-images"
DEFAULT_MOISTURE_BUCKET = "moisture-images"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _clean_url(value: str) -> str:
    return value.rstrip("/")


def _safe_path_part(value: str, default: str) -> str:
    part = re.sub(r"[^a-zA-Z0-9_.-]+", "_", str(value or "")).strip("._")
    return part or default


def _safe_filename(value: str, default: str = "image.jpg") -> str:
    name = Path(value or default).name
    return _safe_path_part(name, default)


class SupabaseStore:
    """Small Supabase REST/Storage client using the existing httpx dependency."""

    def __init__(self) -> None:
        load_dotenv(PROJECT_ROOT / ".env")
        self.url = _clean_url(os.getenv("SUPABASE_URL", ""))
        self.anon_key = os.getenv("SUPABASE_ANON_KEY", "")
        self.service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
        self.timeout = float(os.getenv("SUPABASE_HTTP_TIMEOUT_SECONDS", "30"))
        self.analysis_table = os.getenv("SUPABASE_ANALYSIS_TABLE", "analysis_jobs")
        self.logs_table = os.getenv("SUPABASE_ANALYSIS_LOGS_TABLE", "analysis_logs")
        self.corrections_table = os.getenv("SUPABASE_CORRECTIONS_TABLE", "operator_corrections")
        self.grain_bucket = os.getenv("SUPABASE_GRAIN_BUCKET", DEFAULT_GRAIN_BUCKET)
        self.moisture_bucket = os.getenv("SUPABASE_MOISTURE_BUCKET", DEFAULT_MOISTURE_BUCKET)

    @property
    def configured(self) -> bool:
        return bool(self.url and self.service_role_key)

    def ensure_configured(self) -> None:
        if not self.configured:
            missing = []
            if not self.url:
                missing.append("SUPABASE_URL")
            if not self.service_role_key:
                missing.append("SUPABASE_SERVICE_ROLE_KEY")
            raise HTTPException(
                status_code=503,
                detail=f"Supabase is not configured. Missing {', '.join(missing)}.",
            )

    def _headers(self, *, prefer: Optional[str] = None) -> Dict[str, str]:
        self.ensure_configured()
        headers = {
            "apikey": self.service_role_key,
            "Authorization": f"Bearer {self.service_role_key}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        return headers

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[Dict[str, Any]] = None,
        json_body: Any = None,
        headers: Optional[Dict[str, str]] = None,
    ) -> Any:
        self.ensure_configured()
        request_headers = headers or self._headers()
        url = f"{self.url}{path}"
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.request(
                    method,
                    url,
                    params=params,
                    json=json_body,
                    headers=request_headers,
                )
                response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text or str(exc)
            raise HTTPException(status_code=exc.response.status_code, detail=detail) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"Supabase request failed: {exc}") from exc

        if not response.content:
            return None
        try:
            return response.json()
        except ValueError:
            return response.text

    def authorize_user(self, authorization: Optional[str]) -> Dict[str, Any]:
        required = os.getenv("SUPABASE_AUTH_REQUIRED", "1").strip().lower() not in {"0", "false", "no"}
        if not required:
            return {}
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(status_code=401, detail="Missing Supabase bearer token.")
        token = authorization.split(" ", 1)[1].strip()
        if not token:
            raise HTTPException(status_code=401, detail="Missing Supabase bearer token.")

        api_key = self.anon_key or self.service_role_key
        if not self.url or not api_key:
            raise HTTPException(status_code=503, detail="Supabase auth is not configured.")
        headers = {
            "apikey": api_key,
            "Authorization": f"Bearer {token}",
        }
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(f"{self.url}/auth/v1/user", headers=headers)
                response.raise_for_status()
                user = response.json()
        except httpx.HTTPStatusError as exc:
            raise HTTPException(status_code=401, detail="Invalid Supabase bearer token.") from exc
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"Supabase auth check failed: {exc}") from exc
        return user if isinstance(user, dict) else {}

    def build_storage_paths(
        self,
        analysis_id: str,
        *,
        owner_id: Optional[str] = None,
        grain_name: str = "grain.jpg",
        moisture_name: str = "meter.jpg",
    ) -> Dict[str, str]:
        grain_file = _safe_filename(grain_name, "grain.jpg")
        moisture_file = _safe_filename(moisture_name, "meter.jpg")
        prefix = f"{_safe_path_part(owner_id, 'shared')}/{analysis_id}"
        return {
            "grain": f"{self.grain_bucket}/{prefix}/{grain_file}",
            "moisture": f"{self.moisture_bucket}/{prefix}/{moisture_file}",
        }

    def create_analysis_job(self, row: Dict[str, Any]) -> Dict[str, Any]:
        payload = dict(row)
        payload.setdefault("created_at", utc_now())
        payload.setdefault("updated_at", utc_now())
        result = self._request(
            "POST",
            f"/rest/v1/{self.analysis_table}",
            json_body=payload,
            headers=self._headers(prefer="return=representation"),
        )
        if isinstance(result, list) and result:
            return result[0]
        return payload

    def get_analysis_job(self, analysis_id: str) -> Dict[str, Any]:
        result = self._request(
            "GET",
            f"/rest/v1/{self.analysis_table}",
            params={"id": f"eq.{analysis_id}", "select": "*"},
        )
        if not result:
            raise HTTPException(status_code=404, detail="Analysis job not found.")
        return result[0]

    def update_analysis_job(self, analysis_id: str, fields: Dict[str, Any]) -> Dict[str, Any]:
        payload = dict(fields)
        payload["updated_at"] = utc_now()
        result = self._request(
            "PATCH",
            f"/rest/v1/{self.analysis_table}",
            params={"id": f"eq.{analysis_id}"},
            json_body=payload,
            headers=self._headers(prefer="return=representation"),
        )
        if isinstance(result, list) and result:
            return result[0]
        return payload

    def insert_analysis_log(self, analysis_id: str, stage: str, payload: Dict[str, Any], *, service: str = "grading-service", latency_ms: Optional[int] = None) -> Dict[str, Any]:
        row = {
            "analysis_id": analysis_id,
            "stage": stage,
            "service": service,
            "payload": payload,
            "latency_ms": latency_ms,
            "created_at": utc_now(),
        }
        result = self._request(
            "POST",
            f"/rest/v1/{self.logs_table}",
            json_body=row,
            headers=self._headers(prefer="return=representation"),
        )
        if isinstance(result, list) and result:
            return result[0]
        return row

    def insert_operator_correction(self, row: Dict[str, Any]) -> Dict[str, Any]:
        payload = dict(row)
        payload.setdefault("created_at", utc_now())
        result = self._request(
            "POST",
            f"/rest/v1/{self.corrections_table}",
            json_body=payload,
            headers=self._headers(prefer="return=representation"),
        )
        if isinstance(result, list) and result:
            return result[0]
        return payload

    def list_queued_jobs(self, limit: int = 1) -> List[Dict[str, Any]]:
        result = self._request(
            "GET",
            f"/rest/v1/{self.analysis_table}",
            params={
                "status": "eq.queued",
                "select": "*",
                "order": "created_at.asc",
                "limit": str(max(1, limit)),
            },
        )
        return result if isinstance(result, list) else []

    def parse_storage_path(self, storage_path: str) -> Tuple[str, str]:
        value = (storage_path or "").strip()
        if not value:
            raise HTTPException(status_code=422, detail="Storage path is empty.")
        if value.startswith("supabase://"):
            value = value[len("supabase://") :]
        parts = value.split("/", 1)
        if len(parts) != 2:
            raise HTTPException(status_code=422, detail="Storage path must include bucket and object path.")
        return parts[0], parts[1]

    def materialize_storage_path(self, storage_path: str, *, purpose: str) -> str:
        value = (storage_path or "").strip()
        if value.lower().startswith(("http://", "https://")):
            return self._download_url(value, purpose=purpose)
        bucket, object_path = self.parse_storage_path(value)
        encoded_object = "/".join(quote(part, safe="") for part in object_path.split("/"))
        headers = {
            "apikey": self.service_role_key,
            "Authorization": f"Bearer {self.service_role_key}",
        }
        url = f"{self.url}/storage/v1/object/{quote(bucket, safe='')}/{encoded_object}"
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(url, headers=headers)
                response.raise_for_status()
                content = response.content
        except httpx.HTTPStatusError as exc:
            raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text or str(exc)) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"Supabase storage download failed: {exc}") from exc
        return self._write_runtime_file(content, Path(object_path).suffix, purpose=purpose)

    def _download_url(self, url: str, *, purpose: str) -> str:
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(url)
                response.raise_for_status()
                content = response.content
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=502, detail=f"Image download failed: {exc}") from exc
        return self._write_runtime_file(content, Path(url).suffix, purpose=purpose)

    def _write_runtime_file(self, content: bytes, suffix: str, *, purpose: str) -> str:
        if not content:
            raise HTTPException(status_code=400, detail="Downloaded image is empty.")
        suffix = suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png"}:
            suffix = ".jpg"
        safe_purpose = re.sub(r"[^a-zA-Z0-9_-]+", "_", purpose).strip("_") or "api"
        SESSION_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
        path = SESSION_UPLOADS_DIR / f"{safe_purpose}_{uuid.uuid4().hex[:12]}{suffix}"
        path.write_bytes(content)
        return str(path)


_store: Optional[SupabaseStore] = None


def get_supabase_store() -> SupabaseStore:
    global _store
    if _store is None:
        _store = SupabaseStore()
    return _store
