"""Chatterbox Multilingual (yerel, MIT) seslendirme: işçi cümleleri okur, burada birleştirilir.

İşçi (backend/engines/ses_worker.py) her cümleyi ayrı okur, Whisper ile dinleyip kötü okunanları
yeniden okur ve kelime zamanlarını döndürür. Burada cümleler, Piper ile aynı ritimde (baş boşluğu,
cümle ve sahne araları) tek bir voice.wav'da birleştirilir; kelime zamanları mutlak saniyeye çevrilir.
Whisper'ın eşleştiremediği kelimelerin zamanı komşularından harf sayısına göre doldurulur.
"""
from __future__ import annotations

import re
import wave
from pathlib import Path
from typing import Callable

import numpy as np

from ..config import settings
from . import local_engines
from .piper_tts import LEAD_IN, SCENE_PAUSE, SENTENCE_PAUSE, _proportional

_SPLIT = re.compile(r"(?<=[.!?…])\s+")


def available() -> bool:
    return local_engines.available("ses")


def split_sentences(text: str) -> list[str]:
    return [s for s in _SPLIT.split(text.strip()) if s.strip()]


def _read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as wf:
        sr = wf.getframerate()
        data = np.frombuffer(wf.readframes(wf.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
        if wf.getnchannels() > 1:
            data = data.reshape(-1, wf.getnchannels()).mean(axis=1)
    return data, sr


def _fill_gaps(tokens: list[str], times: list[dict | None], duration: float) -> list[tuple[float, float]]:
    """Eşleşmeyen kelimeleri komşu eşleşmelerin arasına harf sayısına göre yerleştir."""
    if not any(times):
        return _proportional(tokens, 0.05, max(0.1, duration - 0.05))
    out: list[tuple[float, float] | None] = [(t["start"], t["end"]) if t else None for t in times]
    i = 0
    while i < len(out):
        if out[i] is not None:
            i += 1
            continue
        j = i
        while j < len(out) and out[j] is None:
            j += 1
        s = out[i - 1][1] if i > 0 else 0.03
        e = out[j][0] if j < len(out) else max(s + 0.1, duration - 0.03)
        if e <= s:
            e = s + 0.08 * (j - i)
        for k, span in enumerate(_proportional(tokens[i:j], s, e)):
            out[i + k] = span
        i = j
    # Whisper bazen kelime sonlarını bir sonrakinin başına taşır: sıralı ve çakışmasız yap
    fixed, last = [], 0.0
    for a, b in out:
        a = max(a, last)
        b = max(b, a + 0.05)
        fixed.append((a, min(b, duration)))
        last = a
    return fixed


def synthesize(scenes: list[dict], out_dir: Path, on_progress: Callable[[int, int, float], None] | None = None,
               on_status: Callable[[str], None] | None = None) -> tuple[Path, list[dict], float, dict]:
    """Bloklar (asyncio.to_thread ile çağırın). (wav_yolu, kelimeler, süre, bilgi) döndürür."""
    sentences, owners = [], []
    for si, sc in enumerate(scenes):
        for sent in split_sentences(sc["text"]):
            sentences.append({"text": sent})
            owners.append(si)
    ref = settings.chatterbox_reference if settings.chatterbox_reference.exists() else None
    request = {
        "language": "tr",
        "out_dir": str(out_dir / "cumleler"),
        "reference_wav": str(ref) if ref else None,
        "exaggeration": settings.chatterbox_exaggeration,
        "cfg_weight": settings.chatterbox_cfg_weight,
        "temperature": settings.chatterbox_temperature,
        "seed": 1234,
        "min_match": 0.75,
        "max_attempts": 3,
        "sentences": sentences,
    }

    def on_event(ev: dict) -> None:
        if ev.get("type") == "progress" and on_progress:
            on_progress(ev["done"], ev["total"], ev.get("match", 0))
        elif ev.get("type") == "status" and on_status:
            on_status(ev["message"])

    res = local_engines.run_worker("ses", request, out_dir, on_event, timeout=1800)
    sr = int(res["sample_rate"])
    parts = [np.zeros(int(LEAD_IN * sr), dtype=np.float32)]
    t = LEAD_IN
    words: list[dict] = []
    matches, retakes = [], 0
    for n, (sent, owner, item) in enumerate(zip(sentences, owners, res["sentences"])):
        audio, wsr = _read_wav(Path(item["wav"]))
        if wsr != sr:
            raise RuntimeError(f"Beklenmeyen örnekleme hızı {wsr} (beklenen {sr})")
        tokens = sent["text"].split()
        spans = _fill_gaps(tokens, item["words"], len(audio) / sr)
        for tok, (a, b) in zip(tokens, spans):
            words.append({"word": tok, "scene": owner, "start": round(t + a, 3), "end": round(t + b, 3)})
        parts.append(audio)
        t += len(audio) / sr
        matches.append(item["match"])
        retakes += item["attempts"] - 1
        if n < len(sentences) - 1:
            pause = SCENE_PAUSE if owners[n + 1] != owner else SENTENCE_PAUSE
            parts.append(np.zeros(int(pause * sr), dtype=np.float32))
            t += pause

    audio = np.concatenate(parts)
    peak = float(np.max(np.abs(audio))) or 1.0
    audio = audio * min(1.0, 0.92 / peak)
    out_dir.mkdir(parents=True, exist_ok=True)
    wav = out_dir / "voice.wav"
    with wave.open(str(wav), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes((np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes())
    info = {
        "engine": "chatterbox",
        "model": "Chatterbox Multilingual",
        "sample_rate": sr,
        "sentences": len(sentences),
        "avg_match": round(sum(matches) / max(1, len(matches)), 3),
        "min_match": round(min(matches), 3) if matches else None,
        "retakes": retakes,
        "reference_voice": ref.name if ref else None,
        "exaggeration": settings.chatterbox_exaggeration,
        "cfg_weight": settings.chatterbox_cfg_weight,
        "device": res.get("device"),
        "whisper_device": res.get("whisper_device"),
        "seconds": res.get("seconds"),
        "license": "MIT (ticari kullanım serbest)",
    }
    return wav, words, round(len(audio) / sr, 3), info
