"""Yerel yapay zekâ motorları (ekran kartında): FLUX.2 [klein] çizim ve Chatterbox seslendirme.

Ağır bağımlılıklar (torch, diffusers, chatterbox) ana backend venv'inde DEĞİL, her motorun kendi
sanal ortamındadır (backend/engines/.venv-flux, .venv-ses). Backend işçiyi alt süreç olarak
başlatır, isteği JSON dosyasıyla verir, stdout'tan satır satır JSON olay okur. Böylece:
- ekran kartı belleği adım bitince süreçle birlikte tamamen boşalır,
- motorların sürüm çakışmaları (ör. chatterbox'ın sabit diffusers sürümü) ana uygulamayı bozmaz.
Kurulum: yerel-modeller.ps1 (proje kökü).
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import threading
import time
from pathlib import Path
from typing import Callable

from ..config import BACKEND_DIR

ENGINES_DIR = BACKEND_DIR / "engines"
HF_HOME = BACKEND_DIR / "models" / "hf"
_gpu_lock = threading.Lock()  # aynı anda tek GPU işçisi

ENGINES = {
    "flux": {"venv": ".venv-flux", "script": "flux_worker.py",
             "models": [("black-forest-labs/FLUX.2-klein-4B", "transformer/diffusion_pytorch_model.safetensors")]},
    "ses": {"venv": ".venv-ses", "script": "ses_worker.py",
            "models": [("ResembleAI/chatterbox", None),
                       ("mobiuslabsgmbh/faster-whisper-large-v3-turbo", "model.bin")]},
}


class EngineError(RuntimeError):
    pass


def _python(kind: str) -> Path:
    return ENGINES_DIR / ENGINES[kind]["venv"] / "Scripts" / "python.exe"


def _model_ready(repo: str, must_have: str | None) -> bool:
    snaps = HF_HOME / "hub" / f"models--{repo.replace('/', '--')}" / "snapshots"
    if not snaps.exists():
        return False
    for snap in snaps.iterdir():
        if must_have is None and any(snap.iterdir()):
            return True
        if must_have and (snap / must_have).exists():
            return True
    return False


def available(kind: str) -> bool:
    eng = ENGINES[kind]
    return _python(kind).exists() and all(_model_ready(r, f) for r, f in eng["models"])


def run_worker(kind: str, request: dict, work_dir: Path, on_event: Callable[[dict], None] | None = None,
               timeout: float = 1800) -> dict:
    """İşçiyi çalıştır (bloklar; asyncio.to_thread ile çağırın). Son 'result' olayını döndürür."""
    if not available(kind):
        raise EngineError(f"Yerel '{kind}' motoru kurulu değil. Kurmak için proje kökünde: yerel-modeller.ps1")
    work_dir.mkdir(parents=True, exist_ok=True)
    req_path = work_dir / f"{kind}_istek.json"
    req_path.write_text(json.dumps(request, ensure_ascii=False, indent=1), encoding="utf-8")
    log_path = work_dir / f"{kind}_motor.log"
    env = {**os.environ, "HF_HOME": str(HF_HOME), "HF_HUB_OFFLINE": "1", "PYTHONUTF8": "1",
           "PYTHONIOENCODING": "utf-8", "HF_HUB_DISABLE_SYMLINKS_WARNING": "1", "TQDM_DISABLE": "1"}
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    result, error = None, None
    with _gpu_lock, open(log_path, "w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.Popen([str(_python(kind)), str(ENGINES_DIR / ENGINES[kind]["script"]), str(req_path)],
                                stdout=subprocess.PIPE, stderr=log, cwd=str(ENGINES_DIR), env=env,
                                creationflags=flags, text=True, encoding="utf-8", errors="replace")
        killer = threading.Timer(timeout, proc.kill)
        killer.start()
        try:
            for line in proc.stdout:
                line = line.strip()
                if not line.startswith("{"):
                    log.write(line + "\n")
                    continue
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    log.write(line + "\n")
                    continue
                if ev.get("type") == "result":
                    result = ev
                elif ev.get("type") == "error":
                    error = ev
                    log.write(ev.get("trace", "") + "\n")
                if on_event:
                    on_event(ev)
            proc.wait()
        finally:
            killer.cancel()
    if error:
        raise EngineError(f"{kind} motoru hata verdi: {error.get('message')}")
    if result is None:
        tail = log_path.read_text(encoding="utf-8", errors="replace")[-800:]
        raise EngineError(f"{kind} motoru sonuç vermeden kapandı (çıkış {proc.returncode}). Günlük: {log_path}\n{tail}")
    return result


async def run_worker_async(kind: str, request: dict, work_dir: Path,
                           on_event: Callable[[dict], None] | None = None, timeout: float = 1800) -> dict:
    loop = asyncio.get_running_loop()

    def relay(ev: dict) -> None:
        if on_event:
            loop.call_soon_threadsafe(on_event, ev)

    t0 = time.time()
    res = await asyncio.to_thread(run_worker, kind, request, work_dir, relay, timeout)
    res.setdefault("wall_seconds", round(time.time() - t0, 2))
    return res
