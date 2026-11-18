"""Seslendirme, kelime zaman damgaları ve arka plan müziği.

Mock mod: telifsiz, kodla üretilmiş "mırıltı" ses (ya da sessizlik) + sahte ama tutarlı
kelime zaman damgaları + sentetik yumuşak müzik kutusu melodisi.
Gerçek mod: ElevenLabs (with-timestamps) ve isteğe bağlı OpenAI Whisper hizalaması.
"""
from __future__ import annotations

import base64
import random
import re
import wave
from pathlib import Path

import httpx
import numpy as np

from ..config import settings
from .ffmpeg import run_ffmpeg

SR = 44100
VOWELS = set("aeıioöuüAEIİOÖUÜâîû")
MUSIC_EXT = {".mp3", ".wav", ".ogg", ".m4a", ".flac"}


def tokenize_scenes(scenes: list[dict]) -> list[dict]:
    """Sahneleri kelimelere böl; her kelime hangi sahneye ait bilgisini taşır."""
    tokens = []
    for si, sc in enumerate(scenes):
        for wd in sc["text"].split():
            tokens.append({"word": wd, "scene": si})
    return tokens


def full_text(scenes: list[dict]) -> str:
    return " ".join(sc["text"].strip() for sc in scenes)


# ---------------------------------------------------------------- mock zamanlama
def mock_timestamps(scenes: list[dict], target_range=(46.0, 53.0)) -> tuple[list[dict], float]:
    tokens = tokenize_scenes(scenes)
    t = 0.35
    raw = []
    for i, tok in enumerate(tokens):
        letters = re.sub(r"[^\wçğıöşüÇĞİÖŞÜ]", "", tok["word"])
        dur = 0.2 + 0.058 * len(letters)
        pause = 0.06
        if tok["word"].endswith((",", ";", ":")):
            pause = 0.2
        if tok["word"].endswith((".", "!", "?")):
            pause = 0.38
        nxt = tokens[i + 1] if i + 1 < len(tokens) else None
        if nxt and nxt["scene"] != tok["scene"]:
            pause = 0.5
        raw.append([t, t + dur])
        t += dur + pause
    total = t
    lo, hi = target_range
    scale = 1.0
    if total < lo:
        scale = min(1.35, lo / total)
    elif total > hi:
        scale = max(0.8, hi / total)
    words = []
    for tok, (s, e) in zip(tokens, raw):
        words.append({"word": tok["word"], "scene": tok["scene"], "start": round(s * scale, 3), "end": round(e * scale, 3)})
    return words, round(total * scale, 3)


def _write_wav(path: Path, samples: np.ndarray) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    return path


def synth_babble(path: Path, words: list[dict], duration: float, silent: bool = False) -> Path:
    """Kelime zaman damgalarına oturan sevimli, anlamsız 'masal mırıltısı'."""
    n = int((duration + 0.2) * SR)
    out = np.zeros(n, dtype=np.float64)
    if silent:
        return _write_wav(path, out)
    rnd = random.Random(len(words))
    scale_notes = [1.0, 9 / 8, 5 / 4, 4 / 3, 3 / 2]
    base = 300.0
    for wi, w in enumerate(words):
        syl = max(1, sum(1 for ch in w["word"] if ch in VOWELS))
        start, end = w["start"], w["end"]
        span = (end - start) / syl
        is_q = w["word"].endswith("?")
        is_end = w["word"].endswith((".", "!"))
        for k in range(syl):
            s0 = int((start + k * span) * SR)
            length = int(span * 0.88 * SR)
            if length <= 32 or s0 + length >= n:
                continue
            f = base * rnd.choice(scale_notes)
            if k == syl - 1 and is_q:
                f *= 1.25
            elif k == syl - 1 and is_end:
                f *= 0.82
            tt = np.arange(length) / SR
            vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt)
            ph = 2 * np.pi * f * np.cumsum(vib) / SR
            wave_ = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
            env = np.ones(length)
            a, r = min(int(0.012 * SR), length // 3), min(int(0.06 * SR), length // 2)
            env[:a] = np.linspace(0, 1, a)
            env[-r:] = np.linspace(1, 0, r)
            out[s0:s0 + length] += 0.16 * wave_ * env
    return _write_wav(path, out)


def synth_music(path: Path, duration: float) -> Path:
    """Telifsiz sentetik müzik: yumuşak pad akorları + müzik kutusu arpeji (Do majör)."""
    n = int(duration * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    chords = [
        (261.63, 329.63, 392.00),  # C
        (220.00, 261.63, 329.63),  # Am
        (174.61, 220.00, 261.63),  # F
        (196.00, 246.94, 293.66),  # G
    ]
    chord_len = 3.2
    for ci in range(int(duration / chord_len) + 1):
        s0 = int(ci * chord_len * SR)
        if s0 >= n:
            break
        length = min(int((chord_len + 0.8) * SR), n - s0)
        tt = np.arange(length) / SR
        env = np.minimum(1, tt / 0.9) * np.minimum(1, np.maximum(0, (chord_len + 0.8 - tt) / 0.9))
        for f in chords[ci % 4]:
            out[s0:s0 + length] += 0.05 * np.sin(2 * np.pi * f * tt) * env
        # müzik kutusu notaları
        for k in range(8):
            ns = s0 + int(k * 0.4 * SR)
            if ns >= n:
                break
            f = chords[ci % 4][[0, 1, 2, 1, 2, 0, 1, 2][k]] * 2
            ln = min(int(1.2 * SR), n - ns)
            nt = np.arange(ln) / SR
            out[ns:ns + ln] += 0.06 * np.sin(2 * np.pi * f * nt) * np.exp(-nt / 0.35)
    fade = int(min(1.5, duration / 4) * SR)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    out = np.tanh(out * 1.3) * 0.7
    return _write_wav(path, out)


def pick_user_music() -> Path | None:
    d = settings.music_dir
    if not d.exists():
        return None
    files = sorted(p for p in d.iterdir() if p.suffix.lower() in MUSIC_EXT)
    return random.choice(files) if files else None


# ---------------------------------------------------------------- gerçek mod
def _chars_to_words(text: str, alignment: dict, tokens: list[dict]) -> list[dict]:
    chars = alignment.get("characters") or []
    starts = alignment.get("character_start_times_seconds") or []
    ends = alignment.get("character_end_times_seconds") or []
    words, cur, cs, ce = [], "", None, None
    for ch, s, e in zip(chars, starts, ends):
        if ch.isspace():
            if cur:
                words.append((cur, cs, ce))
            cur, cs, ce = "", None, None
            continue
        if not cur:
            cs = s
        cur += ch
        ce = e
    if cur:
        words.append((cur, cs, ce))
    return _map_times(tokens, [(s, e) for _, s, e in words])


def _map_times(tokens: list[dict], times: list[tuple[float, float]]) -> list[dict]:
    """Zaman listesini kendi kelime listemize eşle (sayı farklıysa orantılı)."""
    if not times:
        raise RuntimeError("Zaman damgası alınamadı.")
    out = []
    for i, tok in enumerate(tokens):
        j = i if len(times) == len(tokens) else min(len(times) - 1, round(i * (len(times) - 1) / max(1, len(tokens) - 1)))
        s, e = times[j]
        out.append({**tok, "start": round(float(s), 3), "end": round(float(e), 3)})
    return out


async def elevenlabs_tts(scenes: list[dict], out_dir: Path) -> tuple[Path, list[dict] | None, float]:
    if not (settings.elevenlabs_api_key and settings.elevenlabs_voice_id):
        raise RuntimeError("ELEVENLABS_API_KEY / ELEVENLABS_VOICE_ID tanımlı değil (.env).")
    text = full_text(scenes)
    tokens = tokenize_scenes(scenes)
    use_alignment = settings.timestamp_provider == "elevenlabs"
    endpoint = "/with-timestamps" if use_alignment else ""
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{settings.elevenlabs_voice_id}{endpoint}"
    body = {
        "text": text,
        "model_id": settings.elevenlabs_model,
        "voice_settings": {"stability": 0.55, "similarity_boost": 0.75, "style": 0.35, "use_speaker_boost": True},
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    mp3 = out_dir / "voice.mp3"
    async with httpx.AsyncClient(timeout=180) as client:
        r = await client.post(
            url,
            params={"output_format": "mp3_44100_128"},
            headers={"xi-api-key": settings.elevenlabs_api_key, "accept": "application/json" if use_alignment else "audio/mpeg"},
            json=body,
        )
        r.raise_for_status()
        if use_alignment:
            data = r.json()
            mp3.write_bytes(base64.b64decode(data["audio_base64"]))
            words = _chars_to_words(text, data.get("alignment") or data.get("normalized_alignment") or {}, tokens)
        else:
            mp3.write_bytes(r.content)
            words = None
    wav = out_dir / "voice.wav"
    run_ffmpeg(["-i", str(mp3), "-ac", "1", "-ar", str(SR), str(wav)])
    with wave.open(str(wav)) as wf:
        duration = wf.getnframes() / wf.getframerate()
    return wav, words, duration


async def whisper_timestamps(wav: Path, scenes: list[dict]) -> list[dict]:
    if not settings.openai_api_key:
        raise RuntimeError("Whisper hizalaması için OPENAI_API_KEY gerekli (.env).")
    async with httpx.AsyncClient(timeout=180) as client:
        with open(wav, "rb") as fh:
            r = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                data={"model": "whisper-1", "response_format": "verbose_json", "language": "tr",
                      "timestamp_granularities[]": "word"},
                files={"file": (wav.name, fh, "audio/wav")},
            )
        r.raise_for_status()
        words = r.json().get("words") or []
    return _map_times(tokenize_scenes(scenes), [(w["start"], w["end"]) for w in words])
