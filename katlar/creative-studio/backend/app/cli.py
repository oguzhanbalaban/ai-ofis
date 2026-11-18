"""Komut satırından tek bir mock üretim çalıştırır (sunucu gerekmez).

Kullanım (backend klasöründe):
    .venv\\Scripts\\python -m app.cli --topic "paylaşmak"
"""
from __future__ import annotations

import argparse
import asyncio
import json

from . import db
from .config import settings
from .events import bus
from .jobs import runner
from .services.ffmpeg import probe


async def _main(topic: str | None, failure: str, tts: str | None, image: str | None) -> int:
    from .agents.audio_voice import resolve_provider
    from .services import images

    settings.ensure_dirs()
    db.init_db()
    bus.loop = asyncio.get_running_loop()
    summary = await runner.create(topic, {"failure": failure, "tts": resolve_provider(tts),
                                        "image": images.resolve_provider(image)})
    job_id = runner.queue.get_nowait()
    await runner._run(job_id)  # noqa: SLF001 — CLI için doğrudan çalıştır
    job = db.get_job(job_id)
    edit = job["state"].get("edit") or {}
    print("\n=== SONUÇ ===")
    print("İş:", job_id, "| durum:", job["status"], "| başlık:", job.get("title"))
    aud = job["state"].get("audio") or {}
    print("Ses:", aud.get("voice_source"), "| zaman damgası:", aud.get("timestamp_source"),
          "| ses süresi:", aud.get("voice_duration"))
    vis = (job["state"].get("visuals") or {}).get("engine") or {}
    print("Çizim:", vis.get("label"), "| süre:", vis.get("seconds"), "| referans:", vis.get("reference"))
    if edit.get("video_path"):
        info = probe(edit["video_path"])
        print("Video:", edit["video_path"])
        print(json.dumps(info, ensure_ascii=False, indent=2))
    print("QA:", json.dumps((job["state"].get("qa") or {}).get("checks"), ensure_ascii=False, indent=1))
    _ = summary
    return 0 if job["status"] == "awaiting_approval" else 1


def main() -> None:
    ap = argparse.ArgumentParser(description="Creative Studio tek seferlik üretim")
    ap.add_argument("--topic", default=None)
    ap.add_argument("--failure", default="none", choices=["none", "visual_timeout", "qa_reject"])
    ap.add_argument("--tts", default=None, choices=["chatterbox", "piper", "elevenlabs", "babble", "silence"],
                    help="Ses motoru (varsayılan: .env → TTS_PROVIDER)")
    ap.add_argument("--image", default=None, choices=["flux_local", "fal", "openai", "placeholder"],
                    help="Çizim motoru (varsayılan: .env → IMAGE_PROVIDER)")
    args = ap.parse_args()
    raise SystemExit(asyncio.run(_main(args.topic, args.failure, args.tts, args.image)))


if __name__ == "__main__":
    main()
