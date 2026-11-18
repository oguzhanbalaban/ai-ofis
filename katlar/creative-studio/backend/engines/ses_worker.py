"""Chatterbox Multilingual (Resemble AI, MIT) + faster-whisper yerel seslendirme işçisi.

Ana backend'den bağımsız .venv-ses ortamında çalışır; backend onu alt süreç olarak çağırır.
    python ses_worker.py --indir        modelleri backend/models/hf altına indirir
    python ses_worker.py --kontrol      CUDA + Türkçe desteği denetimi (JSON yazar)
    python ses_worker.py istek.json     seslendirme; stdout'a satır satır JSON olay yazar

Her cümle ayrı seslendirilir, baş/son sessizliği kırpılır, sonra Whisper ile yeniden yazıya
dökülür: Whisper'ın duyduğu metin senaryoya yeterince benzemiyorsa (yutulan/uydurulan kelime)
cümle farklı bir tohumla yeniden okunur ve en iyi deneme seçilir. Kelime zaman damgaları da
aynı Whisper geçişinden gelir (karaoke altyazı için).

istek.json:
    {"language": "tr", "out_dir": str, "reference_wav": str | null,
     "exaggeration": 0.55, "cfg_weight": 0.5, "temperature": 0.8, "seed": int,
     "min_match": 0.75, "max_attempts": 3,
     "sentences": [{"text": str}, ...]}
Olaylar:
    {"type": "status", "message": str}
    {"type": "progress", "done": int, "total": int, "match": float, "attempts": int}
    {"type": "result", "sample_rate": int, "sentences": [{"wav": str, "duration": float, "match": float,
                       "attempts": int, "words": [{"start": float, "end": float} | null, ...]}], ...}
    {"type": "error", "message": str}
"""
from __future__ import annotations

import difflib
import json
import os
import re
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(HERE.parent / "models" / "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
WHISPER = "large-v3-turbo"
_PUNCT = ",.!?;:…\"'«»()-–—’‘“”"


def emit(**ev) -> None:
    sys.stdout.write(json.dumps(ev, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _torch_dlls() -> None:
    """faster-whisper (ctranslate2) CUDA için cuBLAS/cuDNN DLL'lerini torch'un klasöründen bulsun."""
    try:
        import torch

        lib = Path(torch.__file__).parent / "lib"
        if lib.exists() and hasattr(os, "add_dll_directory"):
            os.add_dll_directory(str(lib))
            os.environ["PATH"] = str(lib) + os.pathsep + os.environ.get("PATH", "")
    except Exception:
        pass


def indir() -> int:
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
    from faster_whisper.utils import download_model

    ChatterboxMultilingualTTS.from_pretrained(device="cpu")
    print("Chatterbox Multilingual hazır")
    print("Whisper hazır:", download_model(WHISPER))
    return 0


def kontrol() -> int:
    import torch
    from chatterbox import mtl_tts

    langs = getattr(mtl_tts, "SUPPORTED_LANGUAGES", {})
    info = {"torch": torch.__version__, "cuda": torch.cuda.is_available(), "turkish": "tr" in langs}
    if info["cuda"]:
        info["gpu"] = torch.cuda.get_device_name(0)
    _torch_dlls()
    try:
        import ctranslate2

        info["whisper_cuda"] = ctranslate2.get_cuda_device_count() > 0
    except Exception as exc:
        info["whisper_cuda"] = f"hata: {exc}"
    print(json.dumps(info, ensure_ascii=False))
    return 0 if info["cuda"] and info["turkish"] else 1


def norm(word: str) -> str:
    w = word.strip().strip(_PUNCT).replace("İ", "i").replace("I", "ı").lower()
    w = w.translate(str.maketrans("âîû", "aiu"))  # hâlâ = hala
    return re.sub(r"[^\wçğıöşü]", "", w)


def trim(audio, sr: int, thresh: float = 0.012, pad: float = 0.06):
    import numpy as np

    env = np.abs(audio)
    win = max(1, int(sr * 0.01))
    smooth = np.convolve(env, np.ones(win) / win, mode="same")
    idx = np.where(smooth > thresh)[0]
    if not len(idx):
        return audio
    a = max(0, idx[0] - int(pad * sr))
    b = min(len(audio), idx[-1] + int(pad * sr))
    return audio[a:b]


def align(tokens: list[str], heard: list[dict]) -> tuple[list[dict | None], float]:
    """Senaryodaki kelimeleri Whisper'ın (ipuçlu) duyduklarıyla eşleştir; (zamanlar, benzerlik) döndür."""
    a = [norm(t) for t in tokens]
    b = [norm(w["word"]) for w in heard]
    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    times: list[dict | None] = [None] * len(tokens)
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            w = heard[blk.b + k]
            times[blk.a + k] = {"start": round(w["start"], 3), "end": round(w["end"], 3)}
    # Kelime düzeyinde benzerlik yerine harf düzeyinde oran: ekleri yanlış duyulan kelimeleri cezalandırmaz
    ratio = difflib.SequenceMatcher(a=" ".join(a), b=" ".join(b), autojunk=False).ratio()
    return times, round(ratio, 3)


def run(req_path: str) -> int:
    import numpy as np
    import soundfile as sf
    import torch

    t0 = time.time()
    req = json.loads(Path(req_path).read_text(encoding="utf-8"))
    out_dir = Path(req["out_dir"])
    out_dir.mkdir(parents=True, exist_ok=True)
    lang = req.get("language", "tr")
    sentences = req["sentences"]
    min_match = float(req.get("min_match", 0.75))
    max_attempts = int(req.get("max_attempts", 3))
    device = "cuda" if torch.cuda.is_available() else "cpu"

    os.environ["HF_HUB_OFFLINE"] = "1"
    emit(type="status", message="Chatterbox yükleniyor…")
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    tts = ChatterboxMultilingualTTS.from_pretrained(device=device)
    sr = int(tts.sr)
    ref = req.get("reference_wav") or None
    if ref and not Path(ref).exists():
        ref = None

    emit(type="status", message="Whisper yükleniyor…")
    _torch_dlls()
    from faster_whisper import WhisperModel

    try:
        whisper = WhisperModel(WHISPER, device=device, compute_type="float16" if device == "cuda" else "int8")
        whisper_device = device
    except Exception:
        whisper = WhisperModel(WHISPER, device="cpu", compute_type="int8")
        whisper_device = "cpu"

    import librosa

    def listen(audio, text: str) -> tuple[list[dict], float]:
        """(kelime zamanları, dürüst benzerlik). Dosya yerine 16 kHz dizi verilir: faster-whisper'ın
        PyAV ile dosya okuması sürüm uyumsuzluğuna açık."""
        a16 = librosa.resample(audio, orig_sr=sr, target_sr=16000).astype(np.float32)
        # 1) İpucusuz dinleme: kalite puanı. Senaryo ipucu verilirse Whisper kötü okumayı da
        #    senaryo gibi "duyar"; bu yüzden puan ipucusuz geçişten hesaplanır.
        segs, _ = whisper.transcribe(a16, language=lang, beam_size=5, condition_on_previous_text=False,
                                     vad_filter=False)
        heard = " ".join(s.text for s in segs)
        score = difflib.SequenceMatcher(a=" ".join(norm(t) for t in text.split()),
                                        b=" ".join(norm(t) for t in heard.split()), autojunk=False).ratio()
        # 2) İpuçlu dinleme: kelime sınırları senaryoyla daha iyi örtüşür (karaoke zamanları).
        segs, _ = whisper.transcribe(a16, language=lang, word_timestamps=True, beam_size=5,
                                     initial_prompt=text, condition_on_previous_text=False, vad_filter=False)
        words = [{"word": w.word, "start": w.start, "end": w.end} for s in segs for w in (s.words or [])]
        return words, round(score, 3)

    results = []
    base_seed = int(req.get("seed", 1234))
    for i, sent in enumerate(sentences):
        text = sent["text"].strip()
        tokens = text.split()
        best = None
        for attempt in range(1, max_attempts + 1):
            torch.manual_seed(base_seed + i * 101 + attempt * 7)
            kwargs = dict(language_id=lang, exaggeration=float(req.get("exaggeration", 0.55)),
                          cfg_weight=float(req.get("cfg_weight", 0.5)),
                          temperature=float(req.get("temperature", 0.8)))
            if ref:
                kwargs["audio_prompt_path"] = ref
            wav = tts.generate(text, **kwargs)
            audio = wav.squeeze().detach().cpu().numpy().astype(np.float32)
            audio = trim(audio, sr)
            path = out_dir / f"cumle_{i + 1:02d}_{attempt}.wav"
            sf.write(str(path), audio, sr, subtype="PCM_16")
            heard_words, ratio = listen(audio, text)
            times, _ = align(tokens, heard_words)
            cand = {"wav": str(path), "duration": round(len(audio) / sr, 3), "match": ratio, "attempts": attempt,
                    "words": times}
            if best is None or ratio > best["match"]:
                best = cand
            if ratio >= min_match:
                break
        results.append(best)
        emit(type="progress", done=i + 1, total=len(sentences), match=best["match"], attempts=best["attempts"])

    emit(type="result", sample_rate=sr, sentences=results, seconds=round(time.time() - t0, 2),
         device=device, whisper_device=whisper_device, reference=bool(ref))
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "--indir":
        return indir()
    if argv[0] == "--kontrol":
        return kontrol()
    try:
        return run(argv[0])
    except Exception as exc:
        emit(type="error", message=f"{type(exc).__name__}: {exc}", trace=traceback.format_exc()[-2000:])
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
