"""8. Publisher Agent (YouTube Yayıncısı): SEO başlık/açıklama/etiket üretir ve yerel TASLAK paketi hazırlar.

Bu düğüm hiçbir koşulda YouTube'a yükleme yapmaz. Yükleme yalnızca kullanıcı paneldeki onay
modalında açıkça onay verdiğinde `jobs.approve()` → `services.youtube.upload()` ile yapılır.
"""
from __future__ import annotations

import json
from pathlib import Path

from .. import pricing
from ..config import settings
from ..services import llm
from ..services.youtube import build_body, privacy_status
from .base import AgentContext, agent_node

SPECIES_EMOJI = {"bunny": "🐰", "bear": "🐻", "turtle": "🐢", "cloud": "☁️"}


def seo_template(story: dict) -> dict:
    hero = story.get("hero", {})
    emoji = SPECIES_EMOJI.get(hero.get("species", ""), "✨")
    title = f"{story['title']} {emoji} | Kısa Masal #Shorts"
    if len(title) > 100:
        title = title[:97] + "…"
    description = (
        f"{story['title']} — 3-8 yaş için kısa, eğitici bir masal.\n\n"
        f"💡 Mesaj: {story.get('moral', '')}\n"
        f"📚 Konu: {story.get('topic', '')}\n\n"
        "Uyku öncesi, yolculukta ya da kahvaltıda birlikte izleyin; sonra çocuğunuza masaldaki soruyu sorun!\n\n"
        "#masal #çocukmasalları #kısamasal #eğiticihikaye #shorts"
    )
    tags = ["masal", "çocuk masalları", "kısa masal", "eğitici hikaye", "uyku masalı", "okul öncesi",
            story.get("topic", ""), hero.get("name", ""), "shorts"]
    return {"title": title, "description": description, "tags": [t for t in tags if t]}


@agent_node("publisher", "SEO paketi hazırlanıyor…")
async def publisher_node(state: dict, ctx: AgentContext) -> dict:
    story, edit = state["story"], state["edit"]
    job_dir = Path(state["job_dir"])
    await ctx.say("SEO başlığı yazılıyor…")
    meta = seo_template(story)
    if not ctx.mock:
        try:
            data, pc, oc = await llm.complete_json(
                "Türkçe YouTube Shorts SEO uzmanısın; çocuk içeriği kurallarına uyarsın. Yalnızca JSON döndür.",
                'Şu masal için {"title": str(<=90 karakter, #Shorts içersin), "description": str, "tags": [str]} üret:\n'
                + json.dumps({"title": story["title"], "moral": story.get("moral"), "text": story["text"]},
                             ensure_ascii=False),
                max_tokens=600,
            )
            ctx.add_cost(pricing.llm_cost(pc, oc))
            meta = {"title": data.get("title") or meta["title"], "description": data.get("description") or
                    meta["description"], "tags": data.get("tags") or meta["tags"]}
        except Exception as exc:  # SEO opsiyonel; şablona düş
            await ctx.log(f"SEO LLM çağrısı başarısız, şablon kullanıldı: {exc}", level="warn")
    else:
        ctx.add_cost(pricing.llm_cost(800, 400))
    await ctx.pace(0.8)

    await ctx.say("Taslak paketi kaydediliyor…")
    body = build_body(meta)
    draft_dir = job_dir / "publish"
    draft_dir.mkdir(parents=True, exist_ok=True)
    draft = {
        "youtube_request_body": body,
        "video_file": edit["video_path"],
        "thumbnail": edit.get("thumb_path"),
        "note": "Bu bir TASLAKTIR. Yükleme yalnızca paneldeki onay modalında açık onayla yapılır.",
    }
    draft_path = draft_dir / "metadata.json"
    draft_path.write_text(json.dumps(draft, ensure_ascii=False, indent=2), encoding="utf-8")
    await ctx.pace(0.6)
    await ctx.say("Onay bekleniyor (taslak, private) ⏸")
    await ctx.pace(0.6)
    return {"publish": {
        **meta,
        "privacyStatus": privacy_status(),
        "selfDeclaredMadeForKids": True,
        "categoryId": body["snippet"]["categoryId"],
        "draft_path": str(draft_path),
        "status": "awaiting_approval",
        "upload_possible": settings.upload_possible,
        "uploaded": False,
    }}
