"""FLUX.2 [klein] 4B yerel çizim işçisi (Black Forest Labs, Apache 2.0).

Ana backend'den bağımsız .venv-flux ortamında çalışır; backend onu alt süreç olarak çağırır.
    python flux_worker.py --indir        modeli backend/models/hf altına indirir
    python flux_worker.py --kontrol      CUDA + diffusers denetimi (JSON yazar)
    python flux_worker.py istek.json     çizim; stdout'a satır satır JSON olay yazar

istek.json:
    {"width": 1088, "height": 1920, "steps": 4, "guidance": 1.0,
     "reference": {"prompt": str, "seed": int, "out": str} | null,   # karakter referansı (isteğe bağlı)
     "use_reference": true,
     "items": [{"prompt": str, "seed": int, "out": str}, ...]}
Olaylar:
    {"type": "status", "message": str}
    {"type": "progress", "done": int, "total": int, "out": str, "seconds": float}
    {"type": "result", "images": [str], "reference": str | null, "seconds": float, "device": str}
    {"type": "error", "message": str}
"""
from __future__ import annotations

import json
import os
import sys
import time
import traceback
from pathlib import Path

REPO = "black-forest-labs/FLUX.2-klein-4B"
ALLOW = ["model_index.json", "scheduler/*", "text_encoder/*", "tokenizer/*", "transformer/*", "vae/*", "LICENSE.md"]
HERE = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(HERE.parent / "models" / "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")


def emit(**ev) -> None:
    sys.stdout.write(json.dumps(ev, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def indir() -> int:
    from huggingface_hub import snapshot_download

    path = snapshot_download(REPO, allow_patterns=ALLOW)
    print(f"FLUX.2 [klein] 4B hazır: {path}")
    return 0


def kontrol() -> int:
    import torch
    import diffusers

    info = {"torch": torch.__version__, "diffusers": diffusers.__version__, "cuda": torch.cuda.is_available(),
            "pipeline": hasattr(diffusers, "Flux2KleinPipeline")}
    if info["cuda"]:
        info["gpu"] = torch.cuda.get_device_name(0)
        info["vram_gb"] = round(torch.cuda.get_device_properties(0).total_memory / 1024 ** 3, 1)
    print(json.dumps(info, ensure_ascii=False))
    return 0 if info["cuda"] and info["pipeline"] else 1


def load_pipeline(precision: str = "auto"):
    """precision: auto | bf16 | fp8. Windows masaüstü (dwm) ekran kartı belleğinin birkaç GB'ını tutar;
    model belleğe sığmazsa sürücü sistem RAM'ine taşar ve çizim 20-50 kat yavaşlar. auto, boş belleğe
    bakar ve gerekirse ağırlıkları 8 bit saklar (hesap yine bf16; kalite farkı çok küçük, bellek yarıya iner)."""
    import torch
    from diffusers import Flux2KleinPipeline

    os.environ["HF_HUB_OFFLINE"] = "1"  # çizim sırasında ağa çıkma; model önceden indirilmiş olmalı
    pipe = Flux2KleinPipeline.from_pretrained(REPO, dtype=torch.bfloat16)
    free_gb = torch.cuda.mem_get_info()[0] / 1024 ** 3 if torch.cuda.is_available() else 0.0
    use_fp8 = precision == "fp8" or (precision == "auto" and free_gb < 11.0)
    if use_fp8:
        from diffusers.hooks import apply_layerwise_casting

        pipe.transformer.enable_layerwise_casting(storage_dtype=torch.float8_e4m3fn, compute_dtype=torch.bfloat16)
        apply_layerwise_casting(pipe.text_encoder, storage_dtype=torch.float8_e4m3fn, compute_dtype=torch.bfloat16,
                                skip_modules_pattern=("norm", "embed", "lm_head"))
    # Metin kodlayıcı ile dönüştürücü aynı anda sığmaz: her bileşen yalnızca kullanıldığı anda GPU'ya taşınır.
    pipe.enable_model_cpu_offload()
    pipe.set_progress_bar_config(disable=True)
    return pipe, {"precision": "fp8" if use_fp8 else "bf16", "free_vram_gb": round(free_gb, 1)}


def generate(pipe, prompt: str, seed: int, w: int, h: int, steps: int, guidance: float, refs=None):
    import torch

    kwargs = dict(prompt=prompt, width=w, height=h, num_inference_steps=steps, guidance_scale=guidance,
                  generator=torch.Generator(device="cpu").manual_seed(int(seed) % (2 ** 31)))
    if refs:
        kwargs["image"] = refs
    return pipe(**kwargs).images[0]


def run(req_path: str) -> int:
    t0 = time.time()
    req = json.loads(Path(req_path).read_text(encoding="utf-8"))
    w, h = int(req.get("width", 1088)), int(req.get("height", 1920))
    steps, guidance = int(req.get("steps", 4)), float(req.get("guidance", 1.0))
    items = req["items"]
    emit(type="status", message="FLUX modeli yükleniyor…")
    pipe, mem = load_pipeline(req.get("precision", "auto"))
    emit(type="status", message=f"FLUX hazır ({mem['precision']}, boş VRAM {mem['free_vram_gb']} GB)")
    import torch

    device = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu"
    refs, ref_out = None, None
    ref = req.get("reference")
    if ref and req.get("use_reference", True):
        from PIL import Image

        ref_out = ref["out"]
        if Path(ref_out).exists():
            img = Image.open(ref_out).convert("RGB")
            emit(type="status", message="Karakter referansı önbellekten")
        else:
            emit(type="status", message="Karakter referansı çiziliyor…")
            img = generate(pipe, ref["prompt"], ref["seed"], 1024, 1024, steps, guidance)
            Path(ref_out).parent.mkdir(parents=True, exist_ok=True)
            img.save(ref_out)
        # Koşullama için küçültülmüş kopya: daha az belirteç = daha az bellek ve daha hızlı çizim
        side = int(req.get("reference_side", 768))
        refs = [img.resize((side, side), Image.LANCZOS)]
    outs = []
    for i, it in enumerate(items, start=1):
        t1 = time.time()
        img = generate(pipe, it["prompt"], it["seed"], w, h, steps, guidance, refs)
        Path(it["out"]).parent.mkdir(parents=True, exist_ok=True)
        img.save(it["out"])
        outs.append(it["out"])
        emit(type="progress", done=i, total=len(items), out=it["out"], seconds=round(time.time() - t1, 2))
    emit(type="result", images=outs, reference=ref_out, seconds=round(time.time() - t0, 2), device=device, **mem)
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
    except Exception as exc:  # backend'e okunur hata ilet
        emit(type="error", message=f"{type(exc).__name__}: {exc}", trace=traceback.format_exc()[-2000:])
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
