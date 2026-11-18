"""7. QA & Safety Agent: çocuk güvenliği (metin + prompt), senkron ve dosya bütünlüğü denetimi.
Sorun varsa Yönetmen üzerinden ilgili ajana geri gönderir."""
from __future__ import annotations

from pathlib import Path

from .. import pricing
from ..config import settings
from ..services import llm, safety
from .base import AgentContext, agent_node


@agent_node("qa_safety", "Kontrol listesi açılıyor…")
async def qa_safety_node(state: dict, ctx: AgentContext) -> dict:
    story, art, aud, edit = state["story"], state["art"], state["audio"], state["edit"]
    options = state.get("options") or {}
    checks: list[dict] = []
    issues: list[dict] = []

    def check(name: str, ok: bool, detail: str, target: str | None = None, blocking: bool = True) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail})
        if not ok and blocking:
            issues.append({"check": name, "target": target or "editor", "reason": detail})

    # --- pedagojik metin denetimi
    await ctx.say("Hikaye metni okunuyor…")
    await ctx.pace(0.6)
    hits = safety.check_story_text(story["text"])
    check("Çocuğa uygun dil", not hits, "Uygun" if not hits else f"Uygunsuz ifade: {', '.join(hits)}", "storyteller")
    check("Kelime sınırı (≤130)", story["word_count"] <= 130, f"{story['word_count']} kelime", "storyteller")
    check("Sahne sayısı (6-8)", 6 <= len(story["scenes"]) <= 8, f"{len(story['scenes'])} sahne", "storyteller")
    check("Dikkat çekici giriş (hook)", bool(story.get("hook")), story.get("hook", "")[:60], "storyteller",
          blocking=False)

    if not ctx.mock:
        await ctx.say("LLM pedagojik değerlendirme…")
        data, pc, oc = await llm.complete_json(
            "Sen 3-8 yaş çocuk içeriği için pedagojik güvenlik denetçisisin. Yalnızca JSON döndür.",
            'Şu hikayeyi değerlendir ve {"safe": bool, "issues": [str]} döndür:\n' + story["text"],
            max_tokens=400,
        )
        ctx.add_cost(pricing.llm_cost(pc, oc))
        check("LLM pedagojik onay", bool(data.get("safe")), "; ".join(data.get("issues", [])) or "Uygun",
              "storyteller")
    else:
        ctx.add_cost(pricing.llm_cost(900, 150))

    await ctx.say("Görsel promptları denetleniyor…")
    await ctx.pace(0.5)
    bad_prompts = [s["index"] for s in art["scenes"] if safety.check_prompt(s["prompt"])]
    check("Güvenli görsel promptları", not bad_prompts,
          "Uygun" if not bad_prompts else f"Sorunlu sahneler: {bad_prompts}", "art_director")
    anchor_ok = all(art["character_anchor"] in s["prompt"] for s in art["scenes"])
    check("Karakter tutarlılık çapası", anchor_ok, "Tüm sahnelerde aynı çapa" if anchor_ok else "Eksik", "art_director")

    # --- teknik denetim
    await ctx.say("Ses-video senkronu ölçülüyor…")
    await ctx.pace(0.6)
    info = edit.get("probe", {})
    video_path = Path(edit["video_path"])
    exists = video_path.exists() and video_path.stat().st_size > 100_000
    check("Dosya bütünlüğü", exists, f"{video_path.name} · {info.get('size_bytes', 0) / 1e6:.1f} MB", "editor")
    res_ok = info.get("width") == 1080 and info.get("height") == 1920
    check("Çözünürlük 1080x1920", res_ok, f"{info.get('width')}x{info.get('height')}", "editor")
    fps_ok = abs(float(info.get("fps") or 0) - settings.render_fps) < 0.6
    check(f"Kare hızı {settings.render_fps} fps", fps_ok, f"{info.get('fps')} fps", "editor")
    check("Ses kanalı", bool(info.get("has_audio")), info.get("audio_codec") or "yok", "editor")
    dur = float(info.get("duration") or 0)
    sync_ok = abs(dur - float(aud["total_duration"])) <= 0.35
    check("Ses-video süre senkronu", sync_ok, f"video {dur:.2f} sn / ses {aud['total_duration']:.2f} sn", "editor")
    last_word_ok = aud["words"][-1]["end"] <= dur
    check("Son kelime video içinde", last_word_ok, f"{aud['words'][-1]['end']:.2f} sn", "audio_voice")
    check("Karaoke altyazı olayları", edit.get("subtitle_events", 0) > 0, f"{edit.get('subtitle_events', 0)} olay",
          "editor")
    in_range = 40 <= dur <= 60
    check("Shorts süresi (≤60 sn)", in_range, f"{dur:.1f} sn", "storyteller", blocking=dur > 60)

    # --- simüle QA reddi (gösterim amaçlı)
    qa_round = int(state.get("qa_rounds") or 0)
    if options.get("failure") == "qa_reject" and qa_round == 0:
        check("Altyazı okunabilirliği", False, "Vurgu rengi kontrastı düşük (simülasyon)", "editor")

    passed = not issues
    await ctx.say("Onaylandı ✓ Yayına hazır" if passed else f"{len(issues)} sorun → geri gönderiliyor")
    await ctx.pace(0.6)
    qa = {"passed": passed, "checks": checks, "issues": issues, "round": qa_round + 1}
    out: dict = {"qa": qa}
    if not passed:
        target = issues[0]["target"]
        out["qa_feedback"] = {"target": target, "reasons": [i["reason"] for i in issues if i["target"] == target]}
    return out


def route_after_qa(state: dict) -> str:
    if state.get("failed_step"):
        return "director"
    return "publisher" if (state.get("qa") or {}).get("passed") else "director"
