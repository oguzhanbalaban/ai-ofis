"""İş kuyruğu: üretimleri sırayla çalıştırır, durumu SQLite'a yazar, onay/revizyon akışlarını yönetir."""
from __future__ import annotations

import asyncio
import json
import time
import uuid
from pathlib import Path

from . import db
from .agents.registry import AGENT_BY_ID, PIPELINE_STEPS, REVISION_TARGETS
from .config import settings
from .events import bus
from .services import youtube

ACTIVE = {"queued", "running", "uploading"}


def _media_url(job_id: str, path: str | None, version: float | None = None) -> str | None:
    if not path:
        return None
    try:
        rel = Path(path).resolve().relative_to((settings.outputs_dir / job_id).resolve()).as_posix()
    except ValueError:
        return None
    v = f"?v={int(version)}" if version else ""
    return f"/media/{job_id}/{rel}{v}"


def summarize(job_id: str, state: dict, status: str | None = None, row: dict | None = None) -> dict:
    row = row or db.get_job(job_id) or {}
    story = state.get("story") or {}
    edit = state.get("edit") or {}
    publish = state.get("publish") or {}
    cost = state.get("cost") or {}
    updated = row.get("updated_at") or time.time()
    return {
        "id": job_id,
        "topic": state.get("topic") or row.get("topic"),
        "title": story.get("title") or row.get("title"),
        "status": status or row.get("status"),
        "created_at": row.get("created_at"),
        "updated_at": updated,
        "mock": row.get("mock", settings.mock_mode),
        "options": state.get("options") or {},
        "step_status": state.get("step_status") or {s: "pending" for s in PIPELINE_STEPS},
        "current_agent": next((a for a, s in (state.get("step_status") or {}).items() if s == "working"), None),
        "cost_usd": round(sum(cost.values()), 5),
        "cost_by_agent": cost,
        "error": state.get("error") or row.get("error"),
        "video_url": _media_url(job_id, edit.get("video_path"), updated),
        "thumb_url": _media_url(job_id, edit.get("thumb_path"), updated),
        "duration": (edit.get("probe") or {}).get("duration"),
        "probe": edit.get("probe"),
        "story": {k: story.get(k) for k in ("title", "moral", "hook", "text", "word_count", "est_duration_sec")}
        if story else None,
        "qa": state.get("qa"),
        "publish": publish or None,
        "revision_count": state.get("revision_count") or 0,
        "youtube_video_id": row.get("youtube_video_id"),
        "tts": (state.get("options") or {}).get("tts"),
        "voice": {k: (state.get("audio") or {}).get(k) for k in ("voice_source", "timestamp_source", "engine")}
        if state.get("audio") else None,
        "image": (state.get("options") or {}).get("image"),
        "visuals": {
            "engine": (state.get("visuals") or {}).get("engine"),
            "images": [s.get("image_url") for s in (state.get("visuals") or {}).get("scenes", [])],
        } if state.get("visuals") else None,
    }


async def persist_state(job_id: str, state: dict, status: str | None = None) -> None:
    fields: dict = {"state": _slim(state)}
    if status:
        fields["status"] = status
    story = state.get("story") or {}
    if story.get("title"):
        fields["title"] = story["title"]
    if state.get("topic"):
        fields["topic"] = state["topic"]
    fields["cost_usd"] = round(sum((state.get("cost") or {}).values()), 5)
    edit = state.get("edit") or {}
    if edit.get("video_path"):
        fields["video_path"] = edit["video_path"]
    db.update_job(job_id, **fields)
    await bus.job(summarize(job_id, state, status))


def _slim(state: dict) -> dict:
    return json.loads(json.dumps(state, ensure_ascii=False, default=str))


class JobRunner:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self.current: str | None = None
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        if not self._task:
            self._task = asyncio.create_task(self._worker(), name="masal-job-runner")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass

    async def _worker(self) -> None:
        while True:
            job_id = await self.queue.get()
            self.current = job_id
            try:
                await self._run(job_id)
            except Exception as exc:  # noqa: BLE001
                db.update_job(job_id, status="failed", error=str(exc))
                await bus.log(f"İş beklenmedik biçimde durdu: {exc}", level="error", job_id=job_id)
            finally:
                self.current = None
                await bus.agent("director", "IDLE", None, None)
                await bus.stats(db.stats())
                job = db.get_job(job_id)
                if job:
                    await bus.job(summarize(job_id, job["state"], row=job))

    async def _run(self, job_id: str) -> None:
        from .graph import graph

        job = db.get_job(job_id)
        if not job:
            return
        state = job["state"]
        db.update_job(job_id, status="running", error=None)
        await bus.agent("director", "WORKING", "Ekip toplanıyor…", job_id)
        t0 = time.time()
        final = await graph.ainvoke(state, config={"recursion_limit": 80})
        final = dict(final)
        if final.get("route") == "fail":
            await persist_state(job_id, final, status="failed")
            db.update_job(job_id, error=final.get("error") or "Akış durduruldu.")
            await bus.log("Üretim başarısız oldu.", agent="director", level="error", job_id=job_id)
            return
        final["revision"] = None
        await persist_state(job_id, final, status="awaiting_approval")
        await bus.log(
            f"Video hazır ve onay bekliyor ({time.time() - t0:.0f} sn). Panelde “İncele” ile önizleyin.",
            agent="director",
            data={"video": (final.get("edit") or {}).get("video_path"),
                  "tahmini_maliyet_usd": round(sum((final.get("cost") or {}).values()), 4)},
            job_id=job_id,
        )

    # ---------------------------------------------------------------- API eylemleri
    async def create(self, topic: str | None, options: dict) -> dict:
        job_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:4]
        job_dir = settings.outputs_dir / job_id
        job_dir.mkdir(parents=True, exist_ok=True)
        state = {
            "job_id": job_id,
            "topic": (topic or "").strip() or None,
            "options": options,
            "job_dir": str(job_dir),
            "retries": {},
            "qa_rounds": 0,
            "revision_count": 0,
            "story_variant": 0,
            "history": [],
            "cost": {},
            "step_status": {s: "pending" for s in PIPELINE_STEPS},
        }
        db.create_job(job_id, state["topic"], settings.mock_mode, state)
        await self.queue.put(job_id)
        pos = self.queue.qsize() + (1 if self.current else 0)
        await bus.log(f"Yeni iş kuyruğa alındı: {job_id}" + (f" (sırada {pos}.)" if pos > 1 else ""),
                      data={"topic": state["topic"] or "(günün konusu)", "options": options}, job_id=job_id)
        job = db.get_job(job_id)
        summary = summarize(job_id, state, "queued", row=job)
        await bus.job(summary)
        return summary

    async def revise(self, job_id: str, target_key: str, note: str) -> dict:
        job = db.get_job(job_id)
        if not job:
            raise LookupError("İş bulunamadı.")
        if job["status"] not in {"awaiting_approval", "failed", "interrupted"}:
            raise ValueError(f"Bu durumda revizyon istenemez: {job['status']}")
        target = REVISION_TARGETS.get(target_key, target_key)
        if target not in PIPELINE_STEPS or target in {"qa_safety", "publisher"}:
            raise ValueError("Geçersiz revizyon hedefi.")
        # Hedeften önceki adımların çıktısı yoksa (ör. erken hata) baştan başla
        needed = {"art_director": "story", "visual_generator": "art", "audio_voice": "visuals", "editor": "audio"}
        state = job["state"]
        if target in needed and not state.get(needed[target]):
            target = "storyteller"
        state.update(
            revision={"target": target, "note": note.strip()[:500], "pending": True, "at": time.time()},
            revision_count=int(state.get("revision_count") or 0) + 1,
            failed_step=None, error=None, qa_feedback=None, started=True,
        )
        if not state.get("story"):
            state["revision"]["target"] = "storyteller"
        db.update_job(job_id, state=state, status="queued", error=None)
        await self.queue.put(job_id)
        await bus.log(f"Revizyon kuyruğa alındı → {AGENT_BY_ID[target]['role']}", data=state["revision"],
                      job_id=job_id)
        summary = summarize(job_id, state, "queued")
        await bus.job(summary)
        return summary

    async def approve(self, job_id: str, upload: bool, confirm: bool) -> dict:
        job = db.get_job(job_id)
        if not job:
            raise LookupError("İş bulunamadı.")
        if job["status"] != "awaiting_approval":
            raise ValueError(f"Yalnızca onay bekleyen işler onaylanabilir (şu an: {job['status']}).")
        state = job["state"]
        publish = dict(state.get("publish") or {})
        if upload and not confirm:
            raise PermissionError("Yükleme için onay kutusunun işaretlenmesi gerekir.")

        if not upload:
            publish.update(status="approved_draft", approved_at=time.time())
            state["publish"] = publish
            await bus.agent("publisher", "WORKING", "Taslak arşivlendi (yükleme yok) ✓", job_id)
            await bus.log("Kullanıcı videoyu onayladı. Yerel taslak olarak saklandı; YouTube'a yükleme yapılmadı.",
                          agent="publisher", data={"draft": publish.get("draft_path")}, job_id=job_id)
            await persist_state(job_id, state, status="approved")
            await asyncio.sleep(2.0)
            await bus.agent("publisher", "IDLE", None, None)
            await bus.stats(db.stats())
            return summarize(job_id, state, "approved")

        # --- kullanıcı yüklemeyi açıkça onayladı
        if settings.mock_mode:
            db.update_job(job_id, status="uploading")
            for pct in (0, 25, 50, 75, 100):
                await bus.agent("publisher", "WORKING", f"Yükleme SİMÜLASYONU… %{pct}", job_id)
                await asyncio.sleep(0.6)
            publish.update(status="approved_mock_upload", approved_at=time.time(), uploaded=False,
                           upload={"simulated": True, "privacyStatus": youtube.privacy_status(),
                                   "selfDeclaredMadeForKids": True,
                                   "note": "MOCK_MODE: YouTube'a hiçbir şey gönderilmedi."})
            state["publish"] = publish
            await bus.log("Mock modda yükleme simüle edildi; YouTube'a hiçbir istek gönderilmedi.",
                          agent="publisher", data=publish["upload"], job_id=job_id)
            await persist_state(job_id, state, status="approved")
            await bus.agent("publisher", "IDLE", None, None)
            await bus.stats(db.stats())
            return summarize(job_id, state, "approved")

        if not settings.youtube_upload_enabled:
            raise PermissionError("YOUTUBE_UPLOAD_ENABLED=false. Yükleme kapalı; .env içinden bilinçli olarak açın.")

        db.update_job(job_id, status="uploading")
        await bus.agent("publisher", "WORKING", f"YouTube'a yükleniyor ({youtube.privacy_status()})…", job_id)
        try:
            meta = {k: publish.get(k) for k in ("title", "description", "tags")}
            res = await asyncio.to_thread(youtube.upload, Path(state["edit"]["video_path"]), meta, True)
        except Exception as exc:
            db.update_job(job_id, status="awaiting_approval")
            await bus.agent("publisher", "IDLE", None, None)
            await bus.log(f"Yükleme yapılamadı: {exc}", agent="publisher", level="error", job_id=job_id)
            raise
        publish.update(status="uploaded", uploaded=True, upload=res, approved_at=time.time())
        state["publish"] = publish
        db.update_job(job_id, youtube_video_id=res.get("video_id"))
        await bus.log(f"YouTube'a yüklendi ({res.get('privacyStatus')}): {res.get('url')}", agent="publisher",
                      data=res, job_id=job_id)
        await persist_state(job_id, state, status="uploaded")
        await bus.agent("publisher", "IDLE", None, None)
        await bus.stats(db.stats())
        return summarize(job_id, state, "uploaded")


runner = JobRunner()
