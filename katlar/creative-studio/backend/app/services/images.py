"""Sahne görselleri: yerel FLUX.2 [klein], fal.ai / OpenAI API'leri ya da Pillow ile kodla çizilmiş yer tutucu."""
from __future__ import annotations

import base64
import math
import random
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from ..config import settings

W, H = 1080, 1920
SS = 2  # süper örnekleme: 2x çiz, küçült -> yumuşak kenarlar

SKY = {
    "sabah": ((255, 214, 190), (178, 222, 255)),
    "gun": ((170, 220, 255), (120, 190, 250)),
    "aksam": ((196, 170, 235), (255, 170, 150)),
    "gece": ((24, 30, 78), (88, 64, 140)),
}
GROUND = {
    "orman": [(150, 214, 140), (112, 190, 120), (86, 160, 100)],
    "tepe": [(170, 225, 150), (130, 200, 130), (100, 175, 110)],
    "bahce": [(176, 226, 140), (140, 206, 120), (118, 180, 104)],
    "tarla": [(244, 214, 128), (226, 190, 100), (200, 164, 84)],
    "kasaba": [(170, 220, 160), (146, 200, 150), (120, 176, 136)],
}


def _font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in (("arialbd.ttf", "segoeuib.ttf") if bold else ("arial.ttf", "segoeui.ttf")):
        for base in (Path("C:/Windows/Fonts"), Path("/usr/share/fonts/truetype/dejavu")):
            p = base / name
            if p.exists():
                return ImageFont.truetype(str(p), size)
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf", size)
    except OSError:
        return ImageFont.load_default(size=size)


def _lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _gradient(size, top, bottom) -> Image.Image:
    w, h = size
    img = Image.new("RGB", (1, h))
    for y in range(h):
        img.putpixel((0, y), _lerp(top, bottom, y / max(1, h - 1)))
    return img.resize((w, h))


def _cloud(d: ImageDraw.ImageDraw, cx, cy, s, fill):
    for dx, dy, r in ((-1.0, 0.1, 0.55), (-0.35, -0.25, 0.7), (0.4, -0.15, 0.62), (1.0, 0.12, 0.5), (0.0, 0.2, 0.6)):
        x, y, rr = cx + dx * s, cy + dy * s, r * s
        d.ellipse([x - rr, y - rr * 0.8, x + rr, y + rr * 0.8], fill=fill)


def _star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    d.polygon(pts, fill=fill)


def _heart(d, cx, cy, s, fill):
    d.ellipse([cx - s, cy - s * 0.6, cx, cy + s * 0.3], fill=fill)
    d.ellipse([cx, cy - s * 0.6, cx + s, cy + s * 0.3], fill=fill)
    d.polygon([(cx - s * 0.98, cy), (cx + s * 0.98, cy), (cx, cy + s * 1.05)], fill=fill)


def _eyes_face(d, cx, cy, s, happy=True):
    ink = (60, 44, 52)
    for side in (-1, 1):
        ex = cx + side * s * 0.33
        d.ellipse([ex - s * 0.09, cy - s * 0.12, ex + s * 0.09, cy + s * 0.08], fill=ink)
        d.ellipse([ex - s * 0.03, cy - s * 0.09, ex + s * 0.03, cy - s * 0.03], fill=(255, 255, 255))
        d.ellipse([ex - s * 0.2 + side * s * 0.08, cy + s * 0.12, ex + s * 0.06 + side * s * 0.08, cy + s * 0.26],
                  fill=(255, 170, 180))
    if happy:
        d.arc([cx - s * 0.16, cy + s * 0.05, cx + s * 0.16, cy + s * 0.28], 10, 170, fill=ink, width=max(3, int(s * 0.04)))


def _hero(d, species, cx, cy, s, color, accent):
    color = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
    accent = tuple(int(accent[i:i + 2], 16) for i in (1, 3, 5))
    outline = (90, 70, 80)
    lw = max(4, int(s * 0.035))
    if species == "bunny":
        for side in (-1, 1):
            ex = cx + side * s * 0.28
            d.ellipse([ex - s * 0.16, cy - s * 1.35, ex + s * 0.16, cy - s * 0.45], fill=color, outline=outline, width=lw)
            d.ellipse([ex - s * 0.08, cy - s * 1.22, ex + s * 0.08, cy - s * 0.58], fill=accent)
        d.ellipse([cx - s * 0.55, cy + s * 0.25, cx + s * 0.55, cy + s * 1.25], fill=color, outline=outline, width=lw)
        d.ellipse([cx - s * 0.6, cy - s * 0.6, cx + s * 0.6, cy + s * 0.45], fill=color, outline=outline, width=lw)
        _eyes_face(d, cx, cy - s * 0.1, s)
    elif species == "bear":
        for side in (-1, 1):
            ex = cx + side * s * 0.48
            d.ellipse([ex - s * 0.22, cy - s * 0.82, ex + s * 0.22, cy - s * 0.38], fill=color, outline=outline, width=lw)
            d.ellipse([ex - s * 0.11, cy - s * 0.7, ex + s * 0.11, cy - s * 0.48], fill=accent)
        d.ellipse([cx - s * 0.62, cy + s * 0.2, cx + s * 0.62, cy + s * 1.3], fill=color, outline=outline, width=lw)
        d.ellipse([cx - s * 0.3, cy + s * 0.45, cx + s * 0.3, cy + s * 1.0], fill=accent)
        d.ellipse([cx - s * 0.62, cy - s * 0.62, cx + s * 0.62, cy + s * 0.45], fill=color, outline=outline, width=lw)
        d.ellipse([cx - s * 0.24, cy + s * 0.02, cx + s * 0.24, cy + s * 0.32], fill=accent)
        _eyes_face(d, cx, cy - s * 0.12, s)
    elif species == "turtle":
        d.ellipse([cx - s * 0.95, cy + s * 0.15, cx + s * 0.95, cy + s * 1.25], fill=accent, outline=outline, width=lw)
        for i in range(-1, 2):
            d.ellipse([cx + i * s * 0.45 - s * 0.18, cy + s * 0.4, cx + i * s * 0.45 + s * 0.18, cy + s * 0.75],
                      fill=_lerp(accent, (255, 255, 255), 0.25))
        d.ellipse([cx - s * 0.5, cy - s * 0.65, cx + s * 0.5, cy + s * 0.35], fill=color, outline=outline, width=lw)
        _eyes_face(d, cx, cy - s * 0.2, s * 0.85)
    else:  # cloud
        _cloud(d, cx, cy + s * 0.2, s * 0.95, (255, 255, 255))
        _eyes_face(d, cx, cy + s * 0.15, s * 0.9)


def _prop(d, prop, cx, cy, s, t_rand: random.Random):
    if prop == "apple":
        d.ellipse([cx - s, cy - s, cx + s, cy + s], fill=(232, 72, 72), outline=(150, 40, 50), width=6)
        d.ellipse([cx - s * 0.55, cy - s * 0.6, cx - s * 0.15, cy - s * 0.2], fill=(255, 150, 150))
        d.rectangle([cx - 6, cy - s * 1.35, cx + 6, cy - s * 0.85], fill=(110, 80, 50))
        d.ellipse([cx + 4, cy - s * 1.4, cx + s * 0.6, cy - s * 1.05], fill=(110, 190, 90))
    elif prop in ("star", "moon"):
        for _ in range(14):
            _star(d, t_rand.uniform(80, W * SS - 80), t_rand.uniform(80, H * SS * 0.42), t_rand.uniform(12, 30),
                  (255, 240, 170))
    elif prop == "heart":
        _heart(d, cx, cy, s, (255, 120, 150))
    elif prop in ("flower", "sprout", "seed"):
        stem_h = s * (2.2 if prop == "flower" else 1.0 if prop == "sprout" else 0.2)
        d.rectangle([cx - 8, cy - stem_h, cx + 8, cy + s * 0.4], fill=(90, 170, 90))
        if prop == "flower":
            for i in range(6):
                a = i * math.pi / 3
                px, py = cx + math.cos(a) * s * 0.55, cy - stem_h + math.sin(a) * s * 0.55
                d.ellipse([px - s * 0.42, py - s * 0.42, px + s * 0.42, py + s * 0.42], fill=(255, 150, 200))
            d.ellipse([cx - s * 0.4, cy - stem_h - s * 0.4, cx + s * 0.4, cy - stem_h + s * 0.4], fill=(255, 220, 90))
        elif prop == "sprout":
            d.ellipse([cx - s * 0.8, cy - stem_h - s * 0.3, cx, cy - stem_h + s * 0.15], fill=(130, 210, 110))
            d.ellipse([cx, cy - stem_h - s * 0.3, cx + s * 0.8, cy - stem_h + s * 0.15], fill=(130, 210, 110))
        else:
            d.ellipse([cx - s * 0.35, cy - s * 0.2, cx + s * 0.35, cy + s * 0.3], fill=(150, 100, 60))
    elif prop in ("rain", "water"):
        for _ in range(26):
            x, y = t_rand.uniform(100, W * SS - 100), t_rand.uniform(H * SS * 0.2, H * SS * 0.62)
            d.ellipse([x - 9, y - 20, x + 9, y + 12], fill=(140, 200, 255))
    elif prop == "firefly":
        for _ in range(9):
            x, y = cx + t_rand.uniform(-s * 4, s * 4), cy + t_rand.uniform(-s * 3, s * 1.5)
            d.ellipse([x - 26, y - 26, x + 26, y + 26], fill=(255, 250, 170))
    elif prop == "friend":
        fx, fy = cx, cy
        d.ellipse([fx - s * 0.7, fy - s * 0.4, fx + s * 0.7, fy + s * 0.9], fill=(196, 140, 96), outline=(90, 70, 80), width=6)
        d.ellipse([fx - s * 0.62, fy - s * 1.2, fx + s * 0.62, fy - s * 0.05], fill=(210, 156, 110), outline=(90, 70, 80), width=6)
        _eyes_face(d, fx, fy - s * 0.65, s * 0.9)


def render_placeholder(path: Path, scene: dict, hero: dict, index: int, total: int, prompt: str) -> Path:
    """Telifsiz, tamamen kodla çizilmiş 1080x1920 pastel masal sahnesi."""
    rnd = random.Random(f"{hero.get('name')}-{index}-{scene.get('setting')}")
    w, h = W * SS, H * SS
    time_of_day = scene.get("time", "gun")
    setting = scene.get("setting", "orman")
    top, bottom = SKY.get(time_of_day, SKY["gun"])
    indoor = setting in ("oda", "yuva")

    img = _gradient((w, h), top, bottom)
    d = ImageDraw.Draw(img)

    if indoor:
        wall = (250, 226, 200) if setting == "yuva" else (200, 196, 240)
        if time_of_day == "gece":
            wall = _lerp(wall, (40, 40, 90), 0.55)
        d.rectangle([0, 0, w, h], fill=wall)
        # pencere
        wx0, wy0, wx1, wy1 = w * 0.18, h * 0.12, w * 0.82, h * 0.42
        win = _gradient((int(wx1 - wx0), int(wy1 - wy0)), top, bottom)
        img.paste(win, (int(wx0), int(wy0)))
        d.rectangle([wx0, wy0, wx1, wy1], outline=(150, 110, 90), width=28)
        d.line([(w / 2, wy0), (w / 2, wy1)], fill=(150, 110, 90), width=20)
        if time_of_day == "gece":
            d.ellipse([w * 0.58, h * 0.16, w * 0.72, h * 0.24], fill=(255, 246, 200))
            for _ in range(8):
                _star(d, rnd.uniform(wx0 + 60, wx1 - 60), rnd.uniform(wy0 + 60, wy1 - 60), rnd.uniform(10, 22),
                      (255, 240, 170))
        floor = (214, 170, 130) if setting == "yuva" else (170, 140, 200)
        d.rectangle([0, h * 0.62, w, h], fill=_lerp(floor, (30, 30, 60), 0.35 if time_of_day == "gece" else 0))
        if setting == "oda":  # yatak
            d.rounded_rectangle([w * 0.08, h * 0.6, w * 0.92, h * 0.78], radius=60, fill=(255, 190, 210))
            d.rounded_rectangle([w * 0.1, h * 0.56, w * 0.36, h * 0.64], radius=50, fill=(255, 255, 255))
    else:
        # güneş / ay
        if time_of_day == "gece":
            d.ellipse([w * 0.66, h * 0.08, w * 0.86, h * 0.19], fill=(255, 246, 200))
            d.ellipse([w * 0.71, h * 0.07, w * 0.91, h * 0.18], fill=top)
            for _ in range(22):
                _star(d, rnd.uniform(40, w - 40), rnd.uniform(40, h * 0.45), rnd.uniform(8, 20), (255, 240, 170))
        else:
            sx, sy = (w * 0.76, h * 0.12) if time_of_day != "aksam" else (w * 0.5, h * 0.4)
            glow = (255, 236, 170) if time_of_day != "aksam" else (255, 190, 140)
            d.ellipse([sx - 260, sy - 260, sx + 260, sy + 260], fill=_lerp(glow, top, 0.5))
            d.ellipse([sx - 170, sy - 170, sx + 170, sy + 170], fill=glow)
        cloud_fill = (255, 255, 255) if time_of_day != "gece" else (120, 110, 170)
        for _ in range(3 if setting != "gokyuzu" else 7):
            _cloud(d, rnd.uniform(w * 0.1, w * 0.9), rnd.uniform(h * 0.08, h * (0.35 if setting != "gokyuzu" else 0.8)),
                   rnd.uniform(130, 220), cloud_fill)
        if setting != "gokyuzu":
            layers = GROUND.get(setting, GROUND["orman"])
            for li, col in enumerate(layers):
                if time_of_day == "gece":
                    col = _lerp(col, (30, 40, 90), 0.6)
                elif time_of_day == "aksam":
                    col = _lerp(col, (200, 120, 150), 0.18)
                base = h * (0.55 + li * 0.08)
                for k in range(4):
                    cx = rnd.uniform(-0.2, 1.2) * w
                    rx = rnd.uniform(0.45, 0.8) * w
                    d.ellipse([cx - rx, base - 220, cx + rx, base + 900], fill=col)
                d.rectangle([0, base + 300, w, h], fill=col)
            if setting in ("orman", "bahce", "tepe"):
                for _ in range(5):
                    tx = rnd.choice([rnd.uniform(0.02, 0.28), rnd.uniform(0.72, 0.98)]) * w
                    ty = h * rnd.uniform(0.55, 0.64)
                    trunk = (140, 100, 70) if time_of_day != "gece" else (70, 60, 80)
                    leaf = (96, 176, 110) if time_of_day != "gece" else (40, 80, 90)
                    d.rectangle([tx - 24, ty - 40, tx + 24, ty + 220], fill=trunk)
                    d.ellipse([tx - 170, ty - 330, tx + 170, ty + 40], fill=leaf)
            if setting == "kasaba":
                for i in range(5):
                    hx = w * (0.08 + i * 0.2)
                    hy = h * 0.6
                    col = [(255, 200, 200), (200, 220, 255), (255, 236, 180), (210, 250, 210), (240, 210, 255)][i]
                    d.rectangle([hx - 110, hy - 160, hx + 110, hy + 60], fill=col)
                    d.polygon([(hx - 140, hy - 160), (hx + 140, hy - 160), (hx, hy - 300)], fill=(220, 110, 110))
                    d.rectangle([hx - 30, hy - 60, hx + 30, hy + 60], fill=(150, 100, 80))
        else:
            for _ in range(4):
                _cloud(d, rnd.uniform(w * 0.1, w * 0.9), rnd.uniform(h * 0.6, h * 0.85), rnd.uniform(160, 260),
                       (255, 255, 255) if time_of_day != "gece" else (120, 110, 170))

    # kahraman ve sahne nesnesi (altyazı alanının üstünde)
    hero_s = 340 + rnd.uniform(-20, 30)
    hx = w * (0.42 + rnd.uniform(-0.06, 0.06))
    hy = h * 0.5
    prop = scene.get("prop", "")
    if prop in ("star", "moon", "rain", "water", "firefly"):
        _prop(d, prop, w * 0.7, h * 0.4, 70, rnd)
    _hero(d, hero.get("species", "bunny"), hx, hy, hero_s, hero.get("color", "#ffffff"), hero.get("accent", "#ffaacc"))
    if prop in ("apple", "heart", "flower", "sprout", "seed"):
        _prop(d, prop, w * 0.76, h * 0.6, 110, rnd)
    elif prop == "friend":
        _prop(d, prop, w * 0.78, h * 0.6, 180, rnd)

    img = img.filter(ImageFilter.GaussianBlur(radius=1.2))
    img = img.resize((W, H), Image.LANCZOS)

    # MOCK etiketi ve prompt özeti (üst bölge, altyazı alanından uzakta)
    d2 = ImageDraw.Draw(img, "RGBA")
    d2.rounded_rectangle([40, 40, W - 40, 250], radius=34, fill=(255, 255, 255, 180))
    d2.text((70, 58), f"MOCK GÖRSEL · Sahne {index}/{total}", font=_font(40), fill=(90, 70, 110, 255))
    # Stil çapası her sahnede aynı; etikette sahneye özgü kısmı göster.
    marker = f"Scene {index}:"
    shown = prompt[prompt.index(marker):] if marker in prompt else prompt
    words, line, lines = shown.split(), "", []
    f_small = _font(26, bold=False)
    for wd in words:
        trial = (line + " " + wd).strip()
        if d2.textlength(trial, font=f_small) > W - 140:
            lines.append(line)
            line = wd
            if len(lines) == 4:
                break
        else:
            line = trial
    if line and len(lines) < 4:
        lines.append(line)
    for i, ln in enumerate(lines):
        d2.text((70, 112 + i * 32), ln, font=f_small, fill=(80, 80, 100, 230))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=False)
    return path


# ---------------------------------------------------------------------------------------------
# Çizim motorları (panelde iş başına seçilir; varsayılan .env → IMAGE_PROVIDER, "auto")
#   flux_local  : FLUX.2 [klein] 4B, ekran kartında, ücretsiz (yerel-modeller.ps1 ile kurulur)
#   fal         : fal.ai FLUX API (FAL_KEY)
#   openai      : OpenAI gpt-image-1 API (OPENAI_API_KEY)
#   placeholder : kodla çizilmiş pastel yer tutucu (test)
# API'ler MOCK_MODE'dan bağımsız olarak yalnızca açıkça seçildiklerinde çağrılır.
# ---------------------------------------------------------------------------------------------
IMAGE_PROVIDERS = ("flux_local", "fal", "openai", "placeholder")
IMAGE_LABELS = {
    "flux_local": "FLUX.2 [klein] 4B · yerel ekran kartı",
    "fal": "fal.ai FLUX API",
    "openai": "OpenAI gpt-image-1 API",
    "placeholder": "kodla çizilmiş yer tutucu (test)",
}


def available_providers() -> dict[str, bool]:
    from . import local_engines

    return {
        "flux_local": local_engines.available("flux"),
        "fal": bool(settings.fal_key),
        "openai": bool(settings.openai_api_key),
        "placeholder": True,
    }


def resolve_provider(requested: str | None) -> str:
    """İstenen motor yoksa / kurulu değilse: yerel FLUX varsa o, yoksa yer tutucu."""
    avail = available_providers()
    p = (requested or settings.image_provider or "auto").lower()
    if p in avail and avail[p]:
        return p
    return "flux_local" if avail["flux_local"] else "placeholder"


def fit_9x16(src: Path, dst: Path) -> Path:
    """Görseli ortadan 9:16'ya kırp ve 1080x1920'ye getir (Ken Burns hattı bu boyutu bekler)."""
    img = Image.open(src).convert("RGB")
    w, h = img.size
    target = W / H
    if abs(w / h - target) > 0.005:
        if w / h > target:  # fazla geniş: yanlardan kırp
            nw = int(round(h * target))
            img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:  # fazla uzun: üstten/alttan kırp
            nh = int(round(w / target))
            img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    if img.size != (W, H):
        img = img.resize((W, H), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst, "PNG")
    return dst


async def generate_api(provider: str, path: Path, prompt: str, negative: str = "", seed: int | None = None,
                       client: httpx.AsyncClient | None = None) -> Path:
    """fal.ai ya da OpenAI ile tek görsel. Yalnızca kullanıcı bu motoru açıkça seçtiğinde çağrılır."""
    own = client is None
    client = client or httpx.AsyncClient(timeout=180)
    try:
        if provider == "fal":
            if not settings.fal_key:
                raise RuntimeError("FAL_KEY tanımlı değil (.env).")
            body = {"prompt": prompt, "image_size": {"width": 864, "height": 1536}, "num_images": 1,
                    "enable_safety_checker": True}
            if seed is not None:
                body["seed"] = seed
            r = await client.post(
                f"https://fal.run/{settings.fal_model}",
                headers={"Authorization": f"Key {settings.fal_key}"},
                json=body,
            )
            r.raise_for_status()
            url = r.json()["images"][0]["url"]
            img = await client.get(url)
            img.raise_for_status()
            raw = img.content
        elif provider == "openai":
            if not settings.openai_api_key:
                raise RuntimeError("OPENAI_API_KEY tanımlı değil (.env).")
            full = f"{prompt} Avoid: {negative}." if negative else prompt
            r = await client.post(
                "https://api.openai.com/v1/images/generations",
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                json={"model": settings.openai_image_model, "prompt": full, "size": "1024x1536", "n": 1,
                      "quality": settings.openai_image_quality},
            )
            r.raise_for_status()
            raw = base64.b64decode(r.json()["data"][0]["b64_json"])
        else:
            raise RuntimeError(f"Bilinmeyen görsel API'si: {provider}")
    finally:
        if own:
            await client.aclose()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".download")
    tmp.write_bytes(raw)
    fit_9x16(tmp, path)
    tmp.unlink(missing_ok=True)
    return path
