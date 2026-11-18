"""Piper ile çevrimdışı Türkçe seslendirme + fonem hizalamasından gerçek kelime zaman damgaları.

- İnternet, API anahtarı ya da ücret gerektirmez (model bir kez indirilir: scripts/piper_ses_indir.py).
- Model ONNX grafiği bellekte yamalanır (piper-tts[alignment]); her fonemin kaç ses örneği
  sürdüğü alınır ve boşluk/noktalama fonemlerinden kelime sınırları çıkarılır.
- Hizalama alınamazsa cümle süresi kelimelere harf sayısına göre bölünür (yedek yol).

LİSANS: Varsayılan tr_TR-dfki-medium modeli CC BY-NC-SA 4.0 (ticari olmayan) veriyle eğitilmiştir.
"""
from __future__ import annotations

import threading
import wave
from pathlib import Path
from typing import Callable

import numpy as np

from ..config import settings

SENTENCE_PAUSE = 0.14   # cümleler arası ek sessizlik (sn)
SCENE_PAUSE = 0.38      # sahneler arası ek sessizlik (sn)
LEAD_IN = 0.30          # baştaki sessizlik (sn)
_PUNCT = set(",.!?;:…\"'«»()-–—")

_voice = None
_voice_aligned = False
_lock = threading.Lock()


def model_path() -> Path:
    return settings.piper_model_dir / f"{settings.piper_voice}.onnx"


def available() -> bool:
    if not model_path().exists() or not model_path().with_suffix(".onnx.json").exists():
        return False
    try:
        import piper  # noqa: F401
    except ImportError:
        return False
    return True


def license_note() -> str:
    card = settings.piper_model_dir / f"{settings.piper_voice}.MODEL_CARD.txt"
    if card.exists() and "by-nc" in card.read_text(encoding="utf-8", errors="ignore").lower():
        return "CC BY-NC-SA 4.0 (ticari olmayan kullanım)"
    return "model kartına bakın"


def _load():
    global _voice, _voice_aligned
    with _lock:
        if _voice is None:
            from piper import PiperVoice

            try:
                _voice = PiperVoice.load(str(model_path()), include_alignments=True)
                _voice_aligned = True
            except Exception:  # onnx paketi yoksa hizalamasız yükle
                _voice = PiperVoice.load(str(model_path()))
                _voice_aligned = False
    return _voice


def _words_from_alignment(chunk) -> list[tuple[float, float]] | None:
    """Fonem hizalamasından (başlangıç, bitiş) saniye listesi; kelimeler boşluk/noktalama ile ayrılır."""
    al = chunk.phoneme_alignments
    if not al:
        return None
    sr = chunk.sample_rate
    out, pos, start, has = [], 0, None, False
    for a in al:
        p = a.phoneme
        boundary = p == " " or p in _PUNCT or p in ("^", "$", "_")
        if boundary:
            if has:
                out.append((start / sr, pos / sr))
            start, has = None, False
        else:
            if not has:
                start, has = pos, True
        pos += int(a.num_samples)
    if has:
        out.append((start / sr, pos / sr))
    return out


def _speech_bounds(audio: np.ndarray, sr: int) -> tuple[float, float]:
    """Yedek yol için: sessiz baş/son kısımları kırp."""
    env = np.abs(audio)
    idx = np.where(env > 0.02)[0]
    if not len(idx):
        return 0.0, len(audio) / sr
    return idx[0] / sr, idx[-1] / sr


def _proportional(tokens: list[str], s: float, e: float) -> list[tuple[float, float]]:
    weights = [max(1, len(t.strip("".join(_PUNCT)))) + 1 for t in tokens]
    total = sum(weights)
    out, t = [], s
    for w in weights:
        d = (e - s) * w / total
        out.append((t, t + d * 0.92))
        t += d
    return out


def _map(tokens: list[str], times: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(times) == len(tokens):
        return times
    if not times:
        return []
    # Kelime sayısı farklıysa (sayı açılımı, kesme işareti vb.) orantılı eşle
    return [times[min(len(times) - 1, round(i * (len(times) - 1) / max(1, len(tokens) - 1)))]
            for i in range(len(tokens))]


def synthesize(scenes: list[dict], out_dir: Path,
               on_progress: Callable[[int, int], None] | None = None) -> tuple[Path, list[dict], float, dict]:
    """Sahneleri seslendir; (wav_yolu, kelimeler, süre, bilgi) döndürür."""
    from piper.config import SynthesisConfig

    voice = _load()
    sr = int(voice.config.sample_rate)
    cfg = SynthesisConfig(length_scale=settings.piper_length_scale)
    parts: list[np.ndarray] = [np.zeros(int(LEAD_IN * sr), dtype=np.float32)]
    t = LEAD_IN
    words: list[dict] = []
    aligned_chunks = fallback_chunks = 0
    total_scenes = len(scenes)

    for si, sc in enumerate(scenes):
        if on_progress:
            on_progress(si + 1, total_scenes)
        tokens = sc["text"].split()
        scene_times: list[tuple[float, float]] = []
        chunk_tokens_needed = len(tokens)
        chunks = list(voice.synthesize(sc["text"], cfg, include_alignments=_voice_aligned))
        for ci, ch in enumerate(chunks):
            audio = ch.audio_float_array.astype(np.float32)
            rel = _words_from_alignment(ch) if _voice_aligned else None
            if rel:
                aligned_chunks += 1
            else:
                fallback_chunks += 1
                # Bu parçaya düşen kelime sayısını fonem boşluklarından tahmin et
                n = max(1, "".join(ch.phonemes).strip().count(" ") + 1)
                if ci == len(chunks) - 1:
                    n = max(1, chunk_tokens_needed - len(scene_times))
                s, e = _speech_bounds(audio, sr)
                rel = _proportional(tokens[len(scene_times):len(scene_times) + n], s, e)
            scene_times.extend((t + a, t + b) for a, b in rel)
            parts.append(audio)
            t += len(audio) / sr
            if ci < len(chunks) - 1:
                parts.append(np.zeros(int(SENTENCE_PAUSE * sr), dtype=np.float32))
                t += SENTENCE_PAUSE
        for tok, (a, b) in zip(tokens, _map(tokens, scene_times)):
            words.append({"word": tok, "scene": si, "start": round(a, 3), "end": round(b, 3)})
        if si < total_scenes - 1:
            parts.append(np.zeros(int(SCENE_PAUSE * sr), dtype=np.float32))
            t += SCENE_PAUSE

    audio = np.concatenate(parts)
    out_dir.mkdir(parents=True, exist_ok=True)
    wav = out_dir / "voice.wav"
    pcm = (np.clip(audio, -1, 1) * 32767 * 0.92).astype("<i2")
    with wave.open(str(wav), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())
    duration = len(audio) / sr
    info = {
        "engine": "piper",
        "voice": settings.piper_voice,
        "sample_rate": sr,
        "length_scale": settings.piper_length_scale,
        "aligned_sentences": aligned_chunks,
        "fallback_sentences": fallback_chunks,
        "license": license_note(),
    }
    return wav, words, round(duration, 3), info
