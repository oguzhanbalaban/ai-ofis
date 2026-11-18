"""WebSocket olay yolu: ajan durumları, loglar, iş güncellemeleri ve istatistikler."""
from __future__ import annotations

import asyncio
import itertools
import json
import logging
import time
from collections import deque
from typing import Any

from fastapi import WebSocket

from .agents.registry import AGENTS

log = logging.getLogger("studio.events")

_MAX_DATA_CHARS = 6000


def _clip_data(data: Any) -> Any:
    """Log terminaline gönderilen JSON'u makul boyutta tut."""
    if data is None:
        return None
    try:
        raw = json.dumps(data, ensure_ascii=False, default=str)
    except (TypeError, ValueError):
        return str(data)[:_MAX_DATA_CHARS]
    if len(raw) <= _MAX_DATA_CHARS:
        return json.loads(raw)
    return {"_kirpildi": True, "onizleme": raw[:_MAX_DATA_CHARS] + " …"}


class EventBus:
    def __init__(self) -> None:
        self.clients: set[WebSocket] = set()
        self.logs: deque[dict] = deque(maxlen=600)
        self._ids = itertools.count(1)
        self.loop: asyncio.AbstractEventLoop | None = None
        self.agents: dict[str, dict] = {
            a["id"]: {"id": a["id"], "status": "IDLE", "task": None, "job_id": None, "since": time.time()}
            for a in AGENTS
        }

    # ---- bağlantı yönetimi -------------------------------------------------
    async def connect(self, ws: WebSocket, snapshot: dict) -> None:
        await ws.accept()
        self.clients.add(ws)
        await ws.send_text(json.dumps({"type": "snapshot", **snapshot}, ensure_ascii=False, default=str))

    def disconnect(self, ws: WebSocket) -> None:
        self.clients.discard(ws)

    async def broadcast(self, message: dict) -> None:
        if not self.clients:
            return
        text = json.dumps(message, ensure_ascii=False, default=str)
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send_text(text)
            except Exception:  # bağlantı kopmuş olabilir
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)

    def emit_threadsafe(self, coro_factory) -> None:
        """Bir iş parçacığından (ör. FFmpeg ilerleme okuyucusu) olay yayınla."""
        if self.loop and self.loop.is_running():
            asyncio.run_coroutine_threadsafe(coro_factory(), self.loop)

    # ---- yüksek seviye olaylar ---------------------------------------------
    async def agent(self, agent_id: str, status: str, task: str | None = None, job_id: str | None = None) -> None:
        st = self.agents.setdefault(agent_id, {"id": agent_id})
        changed = st.get("status") != status
        st.update({"status": status, "task": task, "job_id": job_id})
        if changed:
            st["since"] = time.time()
        await self.broadcast({"type": "agent", "agent": dict(st)})

    async def task(self, agent_id: str, task: str) -> None:
        st = self.agents.get(agent_id, {})
        await self.agent(agent_id, st.get("status", "WORKING"), task, st.get("job_id"))

    async def log(
        self,
        message: str,
        agent: str | None = None,
        level: str = "info",
        data: Any = None,
        job_id: str | None = None,
    ) -> None:
        entry = {
            "id": next(self._ids),
            "ts": time.time(),
            "level": level,
            "agent": agent,
            "job_id": job_id,
            "message": message,
            "data": _clip_data(data),
        }
        self.logs.append(entry)
        lvl = {"error": logging.ERROR, "warn": logging.WARNING}.get(level, logging.INFO)
        log.log(lvl, "[%s] %s", agent or "sistem", message)
        await self.broadcast({"type": "log", "log": entry})

    async def handoff(self, src: str | None, dst: str, job_id: str | None = None) -> None:
        await self.broadcast({"type": "handoff", "from": src, "to": dst, "job_id": job_id})

    async def job(self, job_summary: dict) -> None:
        await self.broadcast({"type": "job", "job": job_summary})

    async def stats(self, stats: dict) -> None:
        await self.broadcast({"type": "stats", "stats": stats})

    def agents_list(self) -> list[dict]:
        return [dict(v) for v in self.agents.values()]


bus = EventBus()
