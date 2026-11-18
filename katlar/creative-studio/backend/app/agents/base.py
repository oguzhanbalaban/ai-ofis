"""Ajan düğümleri için ortak sarmalayıcı.

Her düğüm:
- Yönetmenden gelen JSON'u (state) alır, kendi JSON çıktısını döndürür,
- WebSocket'e WORKING/IDLE/ERROR durumlarını ve balon metinlerini yayınlar,
- adım çalıştırmasını ve tahmini maliyeti SQLite'a yazar,
- hata olursa istisnayı yutup `failed_step` ile Yönetmene geri döner.
"""
from __future__ import annotations

import asyncio
import functools
import time
import traceback
from typing import Any, Awaitable, Callable

from .. import db
from ..config import settings
from ..events import bus
from .registry import AGENT_BY_ID

NodeFn = Callable[[dict, "AgentContext"], Awaitable[dict]]


class AgentContext:
    def __init__(self, agent_id: str, state: dict) -> None:
        self.agent_id = agent_id
        self.state = state
        self.job_id: str = state["job_id"]
        self.cost = 0.0

    @property
    def mock(self) -> bool:
        return settings.mock_mode

    async def say(self, text: str) -> None:
        """Karakterin kafasının üstündeki balonu güncelle."""
        await bus.agent(self.agent_id, "WORKING", text, self.job_id)

    async def log(self, message: str, data: Any = None, level: str = "info") -> None:
        await bus.log(message, agent=self.agent_id, level=level, data=data, job_id=self.job_id)

    def add_cost(self, usd: float) -> None:
        self.cost += float(usd)

    async def pace(self, seconds: float | None = None) -> None:
        """Mock modda animasyonların izlenebilmesi için küçük bekleme."""
        if self.mock:
            await asyncio.sleep(settings.mock_step_delay if seconds is None else seconds * settings.mock_step_delay)


def job_summary(job_id: str, state: dict, status: str | None = None) -> dict:
    """Panelin iş kartı için hafif özet."""
    from ..jobs import summarize  # döngüsel içe aktarmayı önle

    return summarize(job_id, state, status)


def agent_node(agent_id: str, start_text: str) -> Callable[[NodeFn], Callable[[dict], Awaitable[dict]]]:
    meta = AGENT_BY_ID[agent_id]

    def deco(fn: NodeFn) -> Callable[[dict], Awaitable[dict]]:
        @functools.wraps(fn)
        async def wrapper(state: dict) -> dict:
            from ..jobs import persist_state  # döngüsel içe aktarmayı önle

            job_id = state["job_id"]
            prev = state.get("last_agent")
            step_status = dict(state.get("step_status") or {})
            step_status[agent_id] = "working"
            costs = dict(state.get("cost") or {})

            await bus.handoff(prev, agent_id, job_id)
            await bus.agent(agent_id, "WORKING", start_text, job_id)
            await bus.agent("director", "WORKING", f"Akış → {meta['role']} çalışıyor", job_id)
            await bus.log(f"{meta['name']} ({meta['role']}) göreve başladı.", agent=agent_id, job_id=job_id)
            await persist_state(job_id, {**state, "step_status": step_status}, status="running")

            step_id = db.start_step(job_id, agent_id)
            ctx = AgentContext(agent_id, state)
            t0 = time.time()
            try:
                out = await fn(state, ctx)
                costs[agent_id] = round(costs.get(agent_id, 0.0) + ctx.cost, 5)
                step_status[agent_id] = "done"
                db.finish_step(step_id, True, ctx.cost)
                payload = out.get(_output_key(agent_id)) if isinstance(out, dict) else None
                await bus.log(
                    f"{meta['role']} tamamlandı ({time.time() - t0:.1f} sn, tahmini ${ctx.cost:.4f}).",
                    agent=agent_id,
                    data=payload,
                    job_id=job_id,
                )
                result = {
                    **out,
                    "last_agent": agent_id,
                    "failed_step": None,
                    "error": None,
                    "step_status": step_status,
                    "cost": costs,
                }
            except Exception as exc:  # noqa: BLE001 — her hatayı Yönetmene ilet
                costs[agent_id] = round(costs.get(agent_id, 0.0) + ctx.cost, 5)
                step_status[agent_id] = "failed"
                msg = f"{type(exc).__name__}: {exc}"
                db.finish_step(step_id, False, ctx.cost, msg)
                await bus.agent(agent_id, "ERROR", f"Hata! {str(exc)[:60]}", job_id)
                await bus.log(
                    f"{meta['role']} hata verdi: {msg}",
                    agent=agent_id,
                    level="error",
                    data={"traceback": traceback.format_exc(limit=4)},
                    job_id=job_id,
                )
                await asyncio.sleep(1.5)
                result = {
                    "last_agent": agent_id,
                    "failed_step": agent_id,
                    "error": msg,
                    "step_status": step_status,
                    "cost": costs,
                }
            finally:
                await bus.agent(agent_id, "IDLE", None, None)

            await persist_state(job_id, {**state, **result})
            return result

        # LangGraph yalnızca (state) imzasını görsün; iç fonksiyonun (state, ctx) imzası gizlenir.
        del wrapper.__wrapped__
        return wrapper

    return deco


def _output_key(agent_id: str) -> str:
    return {
        "storyteller": "story",
        "art_director": "art",
        "visual_generator": "visuals",
        "audio_voice": "audio",
        "editor": "edit",
        "qa_safety": "qa",
        "publisher": "publish",
    }.get(agent_id, agent_id)
