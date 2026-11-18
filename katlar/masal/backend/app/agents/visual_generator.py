"""4. Visual Generator Agent: sahne görsellerini üretir ve FFmpeg ile Ken Burns hareketi uygular."""
from __future__ import annotations

import asyncio
import hashlib
from pathlib import Path

from .. import pricing
from ..config import settings
from ..services import images, local_engines, video
from ..services.audio import mock_timestamps
from .base import AgentContext, agent_node


def _est_scene_durations(story: dict) -> list[float]:
    """Seslendirme henüz yokken sahne sürelerini tahmin et (Kurgucu daha sonra tam keser)."""
    words, total = mock_timestamps(story["scenes"])
    spans = video.scene_spans(words, len(story["scenes"]), total + 1.2)
    return [e - s for s, e in spans]


def _scene_seed(sc: dict) -> int:
    # Aynı tohum her sahnede aynı kompozisyonu üretir; sahne numarasıyla kaydır.
    return (int(sc.get("seed") or 0) + sc["index"] * 7919) % 2_147_483_647


async def _flux_batch(ctx: AgentContext, art: dict, story: dict, pending: list[tuple[dict, Path]],
                      img_dir: Path, total: int) -> dict:
    """Eksik sahneleri tek FLUX işçisi çalıştırmasında çiz (model bir kez yüklenir)."""
    raw_dir = img_dir / "raw"
    ref = None
    if settings.flux_reference and art.get("reference_prompt"):
        rh = hashlib.sha1(art["reference_prompt"].encode("utf-8")).hexdigest()[:8]
        ref = {"prompt": art["reference_prompt"], "seed": int(art.get("seed") or 0),
               "out": str(img_dir / f"character_ref_{rh}.png")}
    request = {
        "width": settings.flux_width, "height": settings.flux_height, "steps": settings.flux_steps,
        "guidance": 1.0, "reference": ref, "use_reference": bool(ref),
        "items": [{"prompt": sc["prompt"], "seed": _scene_seed(sc), "out": str(raw_dir / path.name)}
                  for sc, path in pending],
    }
    names = {str(raw_dir / path.name): sc["index"] for sc, path in pending}

    def on_event(ev: dict) -> None:
        if ev.get("type") == "status":
            asyncio.ensure_future(ctx.say(ev["message"]))
        elif ev.get("type") == "progress":
            idx = names.get(ev.get("out"), ev.get("done"))
            asyncio.ensure_future(ctx.say(f"FLUX çizdi: sahne {idx}/{total} ({ev.get('seconds', 0):.0f} sn)"))

    await ctx.say(f"FLUX ekran kartında çiziyor… ({len(pending)} sahne)")
    res = await local_engines.run_worker_async("flux", request, img_dir, on_event, timeout=1800)
    for sc, path in pending:
        await asyncio.to_thread(images.fit_9x16, raw_dir / path.name, path)
    await ctx.log(f"FLUX: {len(pending)} görsel {res.get('seconds')} sn ({res.get('device')}, {res.get('precision')})",
                  data={"karakter_referansi": res.get("reference"), "adim": settings.flux_steps})
    return {"reference": res.get("reference"), "seconds": res.get("seconds"), "device": res.get("device"),
            "precision": res.get("precision"), "free_vram_gb": res.get("free_vram_gb")}


@agent_node("visual_generator", "Çizim masası hazırlanıyor…")
async def visual_generator_node(state: dict, ctx: AgentContext) -> dict:
    story, art = state["story"], state["art"]
    job_dir = Path(state["job_dir"])
    img_dir, clip_dir = job_dir / "images", job_dir / "clips"
    options = state.get("options") or {}
    retries = (state.get("retries") or {}).get("visual_generator", 0)
    total = len(art["scenes"])
    provider = images.resolve_provider(options.get("image"))
    if options.get("image") and provider != options.get("image"):
        await ctx.log(f"İstenen çizim motoru ({options.get('image')}) kullanılamıyor; {provider} ile devam.",
                      level="warn")
    engine: dict = {"provider": provider, "label": images.IMAGE_LABELS[provider]}

    plan = []
    for sc in art["scenes"]:
        h = hashlib.sha1(f"{provider}|{sc['prompt']}".encode("utf-8")).hexdigest()[:8]
        plan.append((sc, img_dir / f"scene_{sc['index']:02d}_{h}.png"))
    pending = [(sc, p) for sc, p in plan if not p.exists()]
    if len(pending) < total:
        await ctx.say(f"{total - len(pending)} sahne önbellekten ✓")
        await ctx.pace(0.3)

    if pending and provider == "flux_local":
        engine.update(await _flux_batch(ctx, art, story, pending, img_dir, total))
    elif pending:
        for sc, path in pending:
            i = sc["index"]
            await ctx.say(f"Sahne {i}/{total} çiziliyor…")
            if provider == "placeholder":
                await asyncio.to_thread(images.render_placeholder, path, story["scenes"][i - 1],
                                        story.get("hero", {}), i, total, sc["prompt"])
                await ctx.pace(0.5)
            else:
                await images.generate_api(provider, path, sc["prompt"], sc.get("negative", ""), seed=_scene_seed(sc))

    results = []
    for sc, path in plan:
        i = sc["index"]
        results.append({"index": i, "image_path": str(path), "image_url": _media_url(state["job_id"], path)})
        if options.get("failure") == "visual_timeout" and retries == 0 and i == 3:
            raise TimeoutError("Görsel API zaman aşımı (simülasyon: Sahne 3)")

    ctx.add_cost(pricing.image_cost(len(pending), provider))

    # Ken Burns ara klipleri (paralel, en fazla 3 FFmpeg aynı anda)
    durations = _est_scene_durations(story)
    sem = asyncio.Semaphore(3)
    done = 0

    async def kb(res: dict, dur: float) -> None:
        nonlocal done
        motion = video.MOTIONS[(res["index"] - 1) % len(video.MOTIONS)]
        clip = clip_dir / f"clip_{res['index']:02d}.mp4"
        async with sem:
            await asyncio.to_thread(video.render_ken_burns, Path(res["image_path"]), clip, dur + 1.5, motion)
        done += 1
        await ctx.say(f"Ken Burns hareketi {done}/{total} ({motion})")
        res.update({"clip_path": str(clip), "motion": motion, "clip_seconds": round(dur + 1.5, 2)})

    await ctx.say(f"Ken Burns hareketi 0/{total}…")
    await asyncio.gather(*(kb(r, d) for r, d in zip(results, durations)))
    await ctx.say(f"{total} hareketli sahne hazır ✓")
    await ctx.pace(0.4)
    ref = engine.get("reference")
    if ref and Path(ref).exists():
        engine["reference_url"] = _media_url(state["job_id"], Path(ref))
    out = {"visuals": {"scenes": results, "fps": settings.render_fps, "new_images": len(pending),
                       "provider": provider, "engine": engine}}
    if (state.get("fix_request") or {}).get("target") == "visual_generator":
        out["fix_request"] = None
    return out


def _media_url(job_id: str, path: Path) -> str:
    rel = path.resolve().relative_to((settings.outputs_dir / job_id).resolve()).as_posix()
    return f"/media/{job_id}/{rel}"
