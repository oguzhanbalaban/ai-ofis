"""LangGraph durum şeması. Ajanlar birbirine bu sözlük üzerinden JSON aktarır."""
from __future__ import annotations

from typing import Any, Optional, TypedDict


class PipelineState(TypedDict, total=False):
    job_id: str
    topic: Optional[str]
    options: dict[str, Any]          # {simulate_failure: bool, ...}
    job_dir: str

    # Yönetmenin yönlendirme kararı (bir sonraki düğüm) ve akış meta verisi
    route: str
    started: bool
    fix_request: Optional[dict]      # {target, reasons[], source: qa|user}
    story_variant: int
    last_agent: Optional[str]
    failed_step: Optional[str]
    error: Optional[str]
    retries: dict[str, int]
    qa_rounds: int
    qa_feedback: Optional[dict]      # {target, reasons[]}
    revision: Optional[dict]         # {target, note}
    revision_count: int
    history: list[dict]
    step_status: dict[str, str]      # agent -> pending|working|done|failed
    cost: dict[str, float]           # agent -> tahmini USD

    # Ajan çıktıları (JSON)
    story: dict
    art: dict
    visuals: dict
    audio: dict
    edit: dict
    qa: dict
    publish: dict
