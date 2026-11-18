"""FastAPI uygulaması: REST API + WebSocket (/ws) + medya dosyaları + (varsa) derlenmiş panel."""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

import asyncio
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import db
from .agents.registry import AGENTS
from .config import PROJECT_DIR, settings
from .events import bus
from .jobs import runner, summarize
from .services.ffmpeg import tool_info

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("studio")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    settings.ensure_dirs()
    db.init_db()
    bus.loop = asyncio.get_running_loop()
    runner.start()
    info = tool_info()
    log.info("Creative Studio başladı | MOCK_MODE=%s | ffmpeg=%s | ffprobe=%s",
             settings.mock_mode, info["ffmpeg"], info["ffprobe"])
    await bus.log(
        f"Sunucu hazır. Mod: {'MOCK (API anahtarı gerekmez)' if settings.mock_mode else 'GERÇEK'} · "
        f"Yükleme: {'açık (yalnızca onayla)' if settings.upload_possible else 'kapalı'}",
        data={"ffmpeg": info["ffmpeg_version"], "ffprobe": info["ffprobe"] or "yok (ffmpeg -i yedeği)"},
    )
    yield
    await runner.stop()


app = FastAPI(title="Creative Studio", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1:5173", "http://localhost:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

settings.ensure_dirs()
app.mount("/media", StaticFiles(directory=str(settings.outputs_dir)), name="media")


class NewJob(BaseModel):
    topic: str | None = Field(default=None, max_length=120)
    failure: Literal["none", "visual_timeout", "qa_reject"] = "none"
    tts: Literal["chatterbox", "piper", "elevenlabs", "babble", "silence"] | None = None
    image: Literal["flux_local", "fal", "openai", "placeholder"] | None = None


class Revise(BaseModel):
    target: Literal["story", "art", "visuals", "audio", "edit"]
    note: str = Field(default="", max_length=500)


class Approve(BaseModel):
    upload: bool = False
    confirm: bool = False


def _snapshot() -> dict:
    return {
        "agents_meta": AGENTS,
        "agents": bus.agents_list(),
        "logs": list(bus.logs)[-250:],
        "jobs": [summarize(j["id"], j["state"], row=j) for j in db.list_jobs(25)],
        "stats": db.stats(),
        "config": settings.public_dict(),
        "current_job": runner.current,
    }


@app.get("/api/health")
async def health() -> dict:
    return {"ok": True, "mock_mode": settings.mock_mode, "tools": tool_info()}


@app.get("/api/config")
async def get_config() -> dict:
    return settings.public_dict()


@app.get("/api/agents")
async def get_agents() -> dict:
    return {"meta": AGENTS, "state": bus.agents_list()}


@app.get("/api/jobs")
async def list_jobs(limit: int = 25) -> list[dict]:
    return [summarize(j["id"], j["state"], row=j) for j in db.list_jobs(min(limit, 200))]


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str, full: bool = False) -> dict:
    job = db.get_job(job_id)
    if not job:
        raise HTTPException(404, "İş bulunamadı.")
    out = summarize(job_id, job["state"], row=job)
    if full:
        out["state"] = job["state"]
    return out


@app.post("/api/jobs")
async def create_job(body: NewJob) -> dict:
    from .agents.audio_voice import resolve_provider
    from .services import chatterbox_tts, images, piper_tts

    tts = resolve_provider(body.tts)
    if tts == "elevenlabs" and not (settings.elevenlabs_api_key and settings.elevenlabs_voice_id):
        raise HTTPException(400, "ElevenLabs seçildi ama .env içinde ELEVENLABS_API_KEY / ELEVENLABS_VOICE_ID yok.")
    if tts == "piper" and not piper_tts.available():
        raise HTTPException(400, "Piper modeli yok. Kurmak için: backend\\.venv\\Scripts\\python scripts\\piper_ses_indir.py")
    if tts == "chatterbox" and not chatterbox_tts.available():
        raise HTTPException(400, "Chatterbox kurulu değil. Kurmak için proje kökünde: yerel-modeller.ps1")
    if body.image and not images.available_providers().get(body.image):
        need = {"flux_local": "yerel-modeller.ps1 ile FLUX kurulumu", "fal": ".env içinde FAL_KEY",
                "openai": ".env içinde OPENAI_API_KEY"}.get(body.image, "")
        raise HTTPException(400, f"Çizim motoru '{body.image}' kullanılamıyor: {need} gerekli.")
    image = images.resolve_provider(body.image)
    options = {"failure": body.failure, "tts": tts, "image": image}
    return await runner.create(body.topic, options)


@app.post("/api/jobs/{job_id}/revise")
async def revise_job(job_id: str, body: Revise) -> dict:
    try:
        return await runner.revise(job_id, body.target, body.note)
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc


@app.post("/api/jobs/{job_id}/approve")
async def approve_job(job_id: str, body: Approve) -> dict:
    try:
        return await runner.approve(job_id, body.upload, body.confirm)
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
    except PermissionError as exc:
        raise HTTPException(403, str(exc)) from exc
    except Exception as exc:  # yükleme hatası
        raise HTTPException(502, f"Yükleme başarısız: {exc}") from exc


@app.get("/api/stats")
async def get_stats() -> dict:
    return db.stats()


@app.get("/api/graph")
async def get_graph() -> dict:
    from .graph import mermaid

    return {"mermaid": mermaid()}


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    await bus.connect(ws, _snapshot())
    try:
        while True:
            msg = await ws.receive_text()
            if msg == "ping":
                await ws.send_text('{"type":"pong"}')
    except WebSocketDisconnect:
        pass
    finally:
        bus.disconnect(ws)


# --- derlenmiş panel (npm run build sonrası) tek porttan sunulur
DIST = PROJECT_DIR / "frontend" / "dist"
if DIST.exists():
    app.mount("/assets", StaticFiles(directory=str(DIST / "assets")), name="assets")

    @app.get("/{path:path}", include_in_schema=False)
    async def spa(path: str):
        target = DIST / path
        if path and target.is_file() and DIST in target.resolve().parents:
            return FileResponse(target)
        return FileResponse(DIST / "index.html")
