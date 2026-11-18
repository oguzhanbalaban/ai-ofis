"""Piper Türkçe ses modelini indirir (çevrimdışı seslendirme için bir kez gerekir).

Kaynak: https://huggingface.co/rhasspy/piper-voices  (tr/tr_TR/dfki/medium)
Boyut: ~60 MB (.onnx) + yapılandırma (.onnx.json) + MODEL_CARD

LİSANS UYARISI: tr_TR-dfki modeli CC BY-NC-SA 4.0 lisanslı bir veri setiyle eğitilmiştir
(ticari olmayan kullanım). Para kazanılan yayınlarda ElevenLabs gibi ticari lisanslı
bir ses kullanmanız önerilir. Ayrıntı: indirilen MODEL_CARD dosyası.

Kullanım (backend klasöründe):
    .venv\\Scripts\\python scripts\\piper_ses_indir.py
    .venv\\Scripts\\python scripts\\piper_ses_indir.py --voice tr_TR-dfki-medium
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings  # noqa: E402

BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main"


def voice_path(voice: str) -> str:
    # tr_TR-dfki-medium -> tr/tr_TR/dfki/medium/tr_TR-dfki-medium
    locale, name, quality = voice.split("-", 2)
    lang = locale.split("_")[0]
    return f"{lang}/{locale}/{name}/{quality}/{voice}"


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    with httpx.stream("GET", url, follow_redirects=True, timeout=120) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        done = 0
        with open(tmp, "wb") as fh:
            for chunk in r.iter_bytes(1 << 20):
                fh.write(chunk)
                done += len(chunk)
                if total:
                    print(f"\r  {dest.name}: %{done * 100 // total} ({done / 1e6:.1f}/{total / 1e6:.1f} MB)", end="")
    print()
    tmp.replace(dest)


def main() -> int:
    ap = argparse.ArgumentParser(description="Piper ses modelini indir")
    ap.add_argument("--voice", default=settings.piper_voice)
    ap.add_argument("--force", action="store_true", help="Var olsa da yeniden indir")
    args = ap.parse_args()

    out = settings.piper_model_dir
    out.mkdir(parents=True, exist_ok=True)
    rel = voice_path(args.voice)
    files = [(f"{rel}.onnx", out / f"{args.voice}.onnx"),
             (f"{rel}.onnx.json", out / f"{args.voice}.onnx.json"),
             (f"{rel.rsplit('/', 1)[0]}/MODEL_CARD", out / f"{args.voice}.MODEL_CARD.txt")]
    for remote, dest in files:
        if dest.exists() and dest.stat().st_size > 0 and not args.force:
            print(f"  {dest.name}: zaten var, atlandı")
            continue
        download(f"{BASE}/{remote}", dest)
    print(f"Hazır: {out}")
    print("Not: tr_TR-dfki modeli CC BY-NC-SA 4.0 (ticari olmayan) veriyle eğitilmiştir; MODEL_CARD'a bakın.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
