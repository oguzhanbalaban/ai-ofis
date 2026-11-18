"""FFmpeg/ffprobe bulma, ilerleme okuyarak çalıştırma ve dosya inceleme."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
from functools import lru_cache
from pathlib import Path
from typing import Callable

from ..config import settings

_NO_WINDOW = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0


class FFmpegError(RuntimeError):
    pass


@lru_cache(maxsize=1)
def ffmpeg_exe() -> str:
    """Öncelik: FFMPEG_PATH > PATH'teki ffmpeg > imageio-ffmpeg paketindeki ikili."""
    if settings.ffmpeg_path and Path(settings.ffmpeg_path).exists():
        return settings.ffmpeg_path
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as exc:  # pragma: no cover
        raise FFmpegError(
            "FFmpeg bulunamadı. README'deki FFmpeg kurulum adımına bakın ya da FFMPEG_PATH ayarlayın."
        ) from exc


@lru_cache(maxsize=1)
def ffprobe_exe() -> str | None:
    if settings.ffprobe_path and Path(settings.ffprobe_path).exists():
        return settings.ffprobe_path
    found = shutil.which("ffprobe")
    if found:
        return found
    sibling = Path(ffmpeg_exe()).with_name("ffprobe.exe" if sys.platform == "win32" else "ffprobe")
    return str(sibling) if sibling.exists() else None


def tool_info() -> dict:
    exe = ffmpeg_exe()
    try:
        first = subprocess.run(
            [exe, "-hide_banner", "-version"], capture_output=True, text=True, creationflags=_NO_WINDOW, timeout=20
        ).stdout.splitlines()[0]
    except Exception:  # pragma: no cover
        first = "?"
    return {"ffmpeg": exe, "ffmpeg_version": first, "ffprobe": ffprobe_exe()}


def run_ffmpeg(
    args: list[str],
    cwd: Path | None = None,
    total_seconds: float | None = None,
    on_progress: Callable[[float], None] | None = None,
) -> None:
    """FFmpeg'i çalıştır; `-progress pipe:1` çıktısından yüzde hesapla."""
    cmd = [ffmpeg_exe(), "-hide_banner", "-y", "-nostats", "-loglevel", "error"]
    if on_progress and total_seconds:
        cmd += ["-progress", "pipe:1"]
    cmd += args
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=_NO_WINDOW,
    )
    last_pct = -1.0
    assert proc.stdout is not None and proc.stderr is not None
    err_chunks: list[str] = []
    err_thread = threading.Thread(target=lambda: err_chunks.append(proc.stderr.read()), daemon=True)
    err_thread.start()
    for line in proc.stdout:
        if not (on_progress and total_seconds):
            continue
        line = line.strip()
        if line.startswith("out_time_us=") or line.startswith("out_time_ms="):
            try:
                us = int(line.split("=", 1)[1])
            except ValueError:
                continue
            pct = max(0.0, min(100.0, us / 1_000_000 / total_seconds * 100.0))
            if pct - last_pct >= 4 or pct >= 99.9:
                last_pct = pct
                on_progress(pct)
    code = proc.wait()
    err_thread.join(timeout=10)
    stderr = "".join(err_chunks)
    if code != 0:
        raise FFmpegError(f"FFmpeg {code} koduyla çıktı: {stderr.strip()[-1200:]}")


def probe(path: Path) -> dict:
    """Video/ses bilgisini döndür. ffprobe yoksa `ffmpeg -i` çıktısını ayrıştırır."""
    path = Path(path)
    if not path.exists():
        raise FFmpegError(f"Dosya yok: {path}")
    probe_bin = ffprobe_exe()
    if probe_bin:
        out = subprocess.run(
            [probe_bin, "-v", "error", "-show_entries",
             "format=duration,size:stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels",
             "-of", "json", str(path)],
            capture_output=True, text=True, encoding="utf-8", creationflags=_NO_WINDOW, timeout=60,
        )
        if out.returncode != 0:
            raise FFmpegError(f"ffprobe hatası: {out.stderr.strip()[-500:]}")
        data = json.loads(out.stdout or "{}")
        streams = data.get("streams", [])
        v = next((s for s in streams if s.get("codec_type") == "video"), {})
        a = next((s for s in streams if s.get("codec_type") == "audio"), {})
        fps = None
        if v.get("r_frame_rate") and "/" in v["r_frame_rate"]:
            n, d = v["r_frame_rate"].split("/")
            fps = round(float(n) / float(d), 3) if float(d) else None
        return {
            "tool": "ffprobe",
            "duration": float(data.get("format", {}).get("duration", 0) or 0),
            "size_bytes": int(data.get("format", {}).get("size", 0) or path.stat().st_size),
            "width": v.get("width"),
            "height": v.get("height"),
            "fps": fps,
            "video_codec": v.get("codec_name"),
            "audio_codec": a.get("codec_name"),
            "has_audio": bool(a),
            "sample_rate": int(a["sample_rate"]) if a.get("sample_rate") else None,
        }
    # Yedek: ffmpeg -i ile ayrıştır
    res = subprocess.run(
        [ffmpeg_exe(), "-hide_banner", "-i", str(path)],
        capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=_NO_WINDOW, timeout=60,
    )
    text = res.stderr
    info: dict = {"tool": "ffmpeg -i", "size_bytes": path.stat().st_size, "has_audio": " Audio: " in text}
    m = re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)", text)
    if m:
        h, mi, s = m.groups()
        info["duration"] = int(h) * 3600 + int(mi) * 60 + float(s)
    m = re.search(r"Video: (\w+).*?, (\d{2,5})x(\d{2,5})", text)
    if m:
        info["video_codec"], info["width"], info["height"] = m.group(1), int(m.group(2)), int(m.group(3))
    m = re.search(r"(\d+(?:\.\d+)?) fps", text)
    if m:
        info["fps"] = float(m.group(1))
    m = re.search(r"Audio: (\w+).*?(\d+) Hz", text)
    if m:
        info["audio_codec"], info["sample_rate"] = m.group(1), int(m.group(2))
    return info


def env_has_ffmpeg_on_path() -> bool:
    return shutil.which("ffmpeg") is not None or bool(os.getenv("FFMPEG_PATH"))
