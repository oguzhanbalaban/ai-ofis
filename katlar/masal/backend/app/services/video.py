"""Kurgu: Ken Burns sahne klipleri, karaoke altyazı (ASS) ve 1080x1920 MP4 son render.

Ağır iş doğrudan FFmpeg filtre grafiğiyle yapılır (zoompan, xfade, ass, sidechaincompress, amix);
60 fps'te MoviePy'nin kare kare Python işlemesine göre çok daha hızlıdır.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

from ..config import settings
from .ffmpeg import run_ffmpeg

OUT_W, OUT_H = 1080, 1920
WORK_W, WORK_H = 2160, 3840  # zoompan titremesini azaltmak için 2x çalışma çözünürlüğü
XFADE = 0.4

MOTIONS = ["zoom_in", "pan_right", "zoom_out", "pan_up", "zoom_in_left", "pan_left", "zoom_in", "pan_down"]

# Karaoke vurgusunda dönüşümlü renkler (ASS: &HBBGGRR)
HIGHLIGHT_COLORS = ["&H003DD9FF", "&H00B469FF", "&H00F0C84D", "&H0077E36B", "&H00FFA05A"]


def _zoompan_expr(motion: str, frames: int) -> tuple[str, str, str]:
    n = max(1, frames - 1)
    p = f"(on/{n})"
    zin, zout = f"(1.0+0.14*{p})", f"(1.14-0.14*{p})"
    cx, cy = "(iw-iw/zoom)/2", "(ih-ih/zoom)/2"
    if motion == "zoom_in":
        return zin, cx, cy
    if motion == "zoom_out":
        return zout, cx, cy
    if motion == "zoom_in_left":
        return zin, f"(iw-iw/zoom)*0.25", cy
    if motion == "pan_right":
        return "1.12", f"(iw-iw/zoom)*{p}", cy
    if motion == "pan_left":
        return "1.12", f"(iw-iw/zoom)*(1-{p})", cy
    if motion == "pan_up":
        return "1.12", cx, f"(ih-ih/zoom)*(1-{p})"
    if motion == "pan_down":
        return "1.12", cx, f"(ih-ih/zoom)*{p}"
    return zin, cx, cy


def render_ken_burns(image: Path, out: Path, duration: float, motion: str, fps: int | None = None) -> Path:
    """Tek bir durağan görselden yumuşak zoom/pan hareketli ara klip üret."""
    fps = fps or settings.render_fps
    frames = max(2, int(round(duration * fps)))
    z, x, y = _zoompan_expr(motion, frames)
    vf = (
        f"scale={WORK_W}:{WORK_H}:force_original_aspect_ratio=increase:flags=lanczos,"
        f"crop={WORK_W}:{WORK_H},"
        f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={OUT_W}x{OUT_H}:fps={fps},"
        f"format=yuv420p,setsar=1"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg([
        "-i", str(image), "-vf", vf, "-frames:v", str(frames),
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "14", "-pix_fmt", "yuv420p", "-an", str(out),
    ])
    return out


# ---------------------------------------------------------------- altyazı
def _ass_time(t: float) -> str:
    t = max(0.0, t)
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = t % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def _ass_escape(text: str) -> str:
    return text.replace("\\", "").replace("{", "(").replace("}", ")")


def chunk_words(words: list[dict], max_words: int = 3, max_chars: int = 18) -> list[list[dict]]:
    chunks, cur = [], []
    for w in words:
        trial = " ".join(x["word"] for x in cur + [w])
        if cur and (len(cur) >= max_words or len(trial) > max_chars or w["scene"] != cur[-1]["scene"]):
            chunks.append(cur)
            cur = []
        cur.append(w)
        if w["word"].endswith((".", "!", "?")):
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    return chunks


def build_ass(words: list[dict], path: Path, font: str | None = None, variant: int = 0) -> Path:
    """Kelime kelime vurgulanan (karaoke) büyük, renkli altyazılar — orta-alt bölge."""
    font = font or settings.subtitle_font
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {OUT_W}
PlayResY: {OUT_H}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Kids,{font},92,&H00FFFFFF,&H00FFFFFF,&H00402A1E,&H78000000,-1,0,0,0,100,100,1,0,1,7,4,2,60,60,430,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = []
    chunks = chunk_words(words)
    for ci, chunk in enumerate(chunks):
        next_start = chunks[ci + 1][0]["start"] if ci + 1 < len(chunks) else chunk[-1]["end"] + 0.6
        chunk_end = min(chunk[-1]["end"] + 0.35, next_start)
        for j, w in enumerate(chunk):
            start = w["start"]
            end = chunk[j + 1]["start"] if j + 1 < len(chunk) else chunk_end
            if end - start < 0.04:
                continue
            color = HIGHLIGHT_COLORS[(ci + variant) % len(HIGHLIGHT_COLORS)]
            parts = []
            for k, x in enumerate(chunk):
                word = _ass_escape(x["word"])
                if k == j:
                    parts.append(f"{{\\c{color}\\fscx114\\fscy114\\bord8}}{word}{{\\r}}")
                else:
                    parts.append(word)
            pop = "{\\fad(60,0)}" if j == 0 else ""
            lines.append(f"Dialogue: 0,{_ass_time(start)},{_ass_time(end)},Kids,,0,0,0,,{pop}{' '.join(parts)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + "\n".join(lines) + "\n", encoding="utf-8")
    return path


# ---------------------------------------------------------------- son render
def scene_spans(words: list[dict], n_scenes: int, total: float) -> list[tuple[float, float]]:
    """Her sahnenin ekranda kalacağı [başlangıç, bitiş) aralığı (ses zamanlamasına göre)."""
    firsts = []
    for si in range(n_scenes):
        sw = [w for w in words if w["scene"] == si]
        firsts.append(sw[0]["start"] if sw else None)
    # eksik sahne olursa eşit böl
    for i, f in enumerate(firsts):
        if f is None:
            firsts[i] = total * i / n_scenes
    spans = []
    for i in range(n_scenes):
        s = 0.0 if i == 0 else max(0.0, firsts[i] - 0.15)
        e = total if i == n_scenes - 1 else max(firsts[i + 1] - 0.15, s + 0.5)
        spans.append((s, e))
    return spans


def compose_final(
    clips: list[Path],
    spans: list[tuple[float, float]],
    voice: Path,
    music: Path,
    subs: Path,
    out: Path,
    total: float,
    on_progress: Callable[[float], None] | None = None,
) -> Path:
    fps = settings.render_fps
    n = len(clips)
    args: list[str] = []
    for c in clips:
        args += ["-i", str(c)]
    args += ["-i", str(voice), "-stream_loop", "-1", "-i", str(music)]

    parts = []
    for i, (s, e) in enumerate(spans):
        t_start = 0.0 if i == 0 else s - XFADE / 2
        t_end = total if i == n - 1 else e + XFADE / 2
        dur = max(0.3, t_end - t_start)
        # klip yetmezse son kareyi dondurarak uzat
        parts.append(
            f"[{i}:v]tpad=stop_mode=clone:stop_duration=5,trim=duration={dur:.3f},setpts=PTS-STARTPTS,"
            f"fps={fps},format=yuv420p,setsar=1[v{i}]"
        )
    last = "v0"
    for i in range(1, n):
        offset = spans[i][0] - XFADE / 2
        parts.append(f"[{last}][v{i}]xfade=transition=fade:duration={XFADE}:offset={offset:.3f}[x{i}]")
        last = f"x{i}"
    parts.append(f"[{last}]ass={subs.name}[vout]")

    va, ma = n, n + 1
    vol = settings.music_volume
    parts.append(f"[{va}:a]aformat=sample_rates=44100:channel_layouts=stereo,apad=whole_dur={total:.3f}[voice]")
    parts.append("[voice]asplit=2[vmain][vkey]")
    parts.append(
        f"[{ma}:a]aformat=sample_rates=44100:channel_layouts=stereo,"
        f"atrim=duration={total:.3f},asetpts=PTS-STARTPTS,volume={vol},"
        f"afade=t=in:d=1,afade=t=out:st={max(0.0, total - 1.8):.3f}:d=1.8[mus]"
    )
    parts.append("[mus][vkey]sidechaincompress=threshold=0.04:ratio=6:attack=30:release=500[duck]")
    parts.append("[vmain][duck]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[aout]")

    graph = ";".join(parts)
    # Hata ayıklama için grafiğin bir kopyası; komuta doğrudan verilir (sürüm uyumluluğu).
    (out.parent / "filtergraph.txt").write_text(graph.replace(";", ";\n"), encoding="utf-8")
    args += [
        "-filter_complex", graph,
        "-map", "[vout]", "-map", "[aout]",
        "-t", f"{total:.3f}", "-r", str(fps),
        "-c:v", "libx264", "-preset", settings.render_preset, "-crf", str(settings.render_crf),
        "-pix_fmt", "yuv420p", "-profile:v", "high", "-movflags", "+faststart",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        out.name,
    ]
    run_ffmpeg(args, cwd=out.parent, total_seconds=total, on_progress=on_progress)
    return out


def thumbnail(video: Path, out: Path, at: float = 1.5) -> Path:
    run_ffmpeg(["-ss", f"{at:.2f}", "-i", str(video), "-frames:v", "1", "-vf", "scale=360:-2", "-q:v", "3", str(out)])
    return out
