from __future__ import annotations

import os
import time

from fastapi import HTTPException

from backend.app.job_runner import run_analysis_job
from backend.app.services import get_services
from backend.app.supabase_store import get_supabase_store


def main() -> None:
    store = get_supabase_store()
    store.ensure_configured()
    services = get_services()
    interval = float(os.getenv("GRADING_WORKER_POLL_SECONDS", "3"))
    batch_size = int(os.getenv("GRADING_WORKER_BATCH_SIZE", "1"))
    print("Grading worker started. Polling Supabase analysis_jobs.")
    while True:
        jobs = store.list_queued_jobs(limit=batch_size)
        if not jobs:
            time.sleep(interval)
            continue
        for job in jobs:
            analysis_id = str(job.get("id") or "")
            if not analysis_id:
                continue
            try:
                run_analysis_job(analysis_id, store, services)
                print(f"Completed analysis job {analysis_id}.")
            except HTTPException as exc:
                print(f"Failed analysis job {analysis_id}: {exc.detail}")
            except Exception as exc:
                print(f"Failed analysis job {analysis_id}: {exc}")


if __name__ == "__main__":
    main()
