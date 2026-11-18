"""2. Storyteller Agent (Senarist): 3-8 yaş, pozitif mesajlı, 45-55 sn (≤130 kelime), 6-8 sahne."""
from __future__ import annotations

from .. import pricing
from ..mock_data import pick_story
from ..services import llm
from ..services.audio import mock_timestamps
from .base import AgentContext, agent_node

MAX_WORDS = 130

SYSTEM = (
    "Sen 3-8 yaş çocukları için Türkçe masal yazan, pedagojiye duyarlı bir senaristsin. "
    "Şiddet, korku, aşağılama, tehlikeli davranış ve marka içermeyen; eğitici ve pozitif mesajlı "
    "hikayeler yazarsın. Yalnızca geçerli JSON döndür."
)

USER_TMPL = """Konu: {topic}
{fix}
Kurallar:
- Toplam en fazla 130 kelime, sesli okunduğunda 45-55 saniye.
- İlk cümle (ilk 3 saniye) merak uyandıran bir "hook" olsun.
- Hikayeyi 6-8 sahneye böl. Son sahne çocuğa sıcak bir soru ya da mesajla bitsin.
- Tek bir sevimli ana kahraman (hayvan ya da nesne) olsun.
JSON şeması:
{{"title": str, "moral": str,
  "hero": {{"name": str, "species": "bunny|bear|turtle|cloud|other", "description_en": str}},
  "scenes": [{{"text": str, "setting": str, "time": "sabah|gun|aksam|gece", "visual_en": str}}]}}"""


def _finalize(raw: dict, topic: str) -> dict:
    scenes = []
    for i, sc in enumerate(raw["scenes"], start=1):
        scenes.append({
            "index": i,
            "text": sc["text"].strip(),
            "setting": sc.get("setting", "orman"),
            "time": sc.get("time", "gun"),
            "prop": sc.get("prop", ""),
            "visual_en": sc.get("visual_en", ""),
        })
    words = sum(len(s["text"].split()) for s in scenes)
    _, est = mock_timestamps(scenes, target_range=(0, 999))
    first = scenes[0]["text"] if scenes else ""
    hook = first.split("!")[0] + "!" if "!" in first else first.split(".")[0]
    return {
        "title": raw["title"],
        "topic": topic,
        "moral": raw.get("moral", ""),
        "age_range": "3-8",
        "language": "tr",
        "hook": hook.strip(),
        "hero": raw.get("hero", {}),
        "scenes": scenes,
        "word_count": words,
        "est_duration_sec": round(est, 1),
        "text": " ".join(s["text"] for s in scenes),
    }


def _validate(story: dict) -> None:
    n = len(story["scenes"])
    if not 6 <= n <= 8:
        raise ValueError(f"Sahne sayısı 6-8 olmalı, {n} geldi.")
    if story["word_count"] > MAX_WORDS:
        raise ValueError(f"Hikaye {story['word_count']} kelime; sınır {MAX_WORDS}.")


@agent_node("storyteller", "Hikaye fikri düşünülüyor…")
async def storyteller_node(state: dict, ctx: AgentContext) -> dict:
    topic = state.get("topic") or "paylaşmak"
    fix = state.get("fix_request") or {}
    variant = int(state.get("story_variant") or 0)
    if fix.get("target") == "storyteller":
        variant += 1

    if ctx.mock:
        await ctx.say("Hikaye fikri düşünülüyor…")
        await ctx.pace(1.0)
        raw = pick_story(topic, variant)
        await ctx.say(f"“{raw['title']}” yazılıyor…")
        await ctx.pace(1.2)
        prompt_chars, out_chars = len(SYSTEM) + 600, 1400  # gerçek modda ne tutardı
        if fix.get("reasons"):
            await ctx.log("Revizyon/QA notu dikkate alındı (mock: farklı bir hikaye şablonu seçildi).",
                          data={"notlar": fix.get("reasons")})
    else:
        await ctx.say("LLM ile hikaye yazılıyor…")
        fix_txt = ""
        if fix.get("target") == "storyteller" and fix.get("reasons"):
            fix_txt = "Önceki taslak için düzeltme notları: " + "; ".join(fix["reasons"])
        raw, prompt_chars, out_chars = await llm.complete_json(SYSTEM, USER_TMPL.format(topic=topic, fix=fix_txt))

    story = _finalize(raw, topic)
    await ctx.say("Sahnelere bölünüyor…")
    await ctx.pace(0.6)
    _validate(story)
    ctx.add_cost(pricing.llm_cost(prompt_chars, out_chars))
    await ctx.say(f"{len(story['scenes'])} sahne, {story['word_count']} kelime ✓")
    await ctx.pace(0.5)
    out = {"story": story, "story_variant": variant}
    if fix.get("target") == "storyteller":
        out["fix_request"] = None
    return out
