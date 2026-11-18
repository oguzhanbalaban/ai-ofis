"""6. Editor Agent (Kurgucu): görseller + ses + müzik + karaoke altyazı → 1080x1920 60fps MP4."""
from __future__ import annotations

import asyncio
from pathlib import Path

from ..config import settings
from ..events import bus
from ..services import video
from ..services.ffmpeg import probe
from .base import AgentContext, agent_node


@agent_node("editor", "Zaman çizelgesi kuruluyor…")
async def editor_node(state: dict, ctx: AgentContext) -> dict:
    job_dir = Path(state["job_dir"])
    story, visuals, aud = state["story"], state["visuals"], state["audio"]
    words, total = aud["words"], float(aud["total_duration"])
    n = len(story["scenes"])
    # Revizyon ya da QA geri dönüşünde altyazı vurgu paletini değiştir.
    variant = int(state.get("revision_count") or 0) + int(state.get("qa_rounds") or 0)

    await ctx.say("Zaman çizelgesi kuruluyor…")
    spans = video.scene_spans(words, n, total)
    await ctx.pace(0.6)

    await ctx.say("Karaoke altyazılar hazırlanıyor…")
    subs = video.build_ass(words, job_dir / "subs.ass", variant=variant)
    await ctx.pace(0.6)

    clips = [Path(s["clip_path"]) for s in sorted(visuals["scenes"], key=lambda x: x["index"])]
    out_path = job_dir / "final.mp4"
    loop = asyncio.get_running_loop()
    agent_id, job_id = ctx.agent_id, ctx.job_id

    def on_progress(pct: float) -> None:
        loop.call_soon_threadsafe(
            lambda: asyncio.ensure_future(bus.agent(agent_id, "WORKING", f"Render alınıyor… %{pct:.0f}", job_id))
        )

    await ctx.say("Render alınıyor… %0")
    await asyncio.to_thread(
        video.compose_final, clips, spans, Path(aud["voice_path"]), Path(aud["music_path"]), subs, out_path,
        total, on_progress,
    )
    await ctx.say("Kapak karesi çıkarılıyor…")
    thumb = await asyncio.to_thread(video.thumbnail, out_path, job_dir / "thumb.jpg", min(2.0, total / 3))
    info = await asyncio.to_thread(probe, out_path)
    await ctx.say(f"{info.get('width')}x{info.get('height')} · {info.get('duration', 0):.1f} sn ✓")
    await ctx.pace(0.4)
    out = {"edit": {
        "video_path": str(out_path),
        "thumb_path": str(thumb),
        "subtitles_path": str(subs),
        "subtitle_events": sum(1 for ln in subs.read_text(encoding="utf-8").splitlines() if ln.startswith("Dialogue:")),
        "scene_spans": [[round(s, 3), round(e, 3)] for s, e in spans],
        "target": {"width": video.OUT_W, "height": video.OUT_H, "fps": settings.render_fps},
        "probe": info,
    }}
    if (state.get("fix_request") or {}).get("target") == "editor":
        out["fix_request"] = None
    return out
