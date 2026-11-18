"""5. Audio & Voice Agent: seslendirme, kelime bazlı zaman damgaları ve telifsiz arka plan müziği.

Ses motoru iş başına seçilir (panel → "Ses motoru", varsayılan .env → TTS_PROVIDER, "auto"):
- chatterbox : Chatterbox Multilingual, ekran kartında, ücretsiz, MIT; duygulu anlatım. Whisper her
               cümleyi dinler, kötü okunanı yeniden okutur; zaman damgaları Whisper'dan.
- piper      : çevrimdışı, ücretsiz Türkçe ses; zaman damgaları fonem hizalamasından (gerçek)
- elevenlabs : ücretli API (ELEVENLABS_API_KEY + ELEVENLABS_VOICE_ID); zaman damgaları
               ElevenLabs hizalamasından ya da Whisper'dan. MOCK_MODE'dan bağımsız olarak,
               yalnızca açıkça seçildiğinde çağrılır.
- babble     : anlamsız sentetik "mırıltı" + sahte zaman damgaları (test)
- silence    : sessizlik + sahte zaman damgaları (test)
"""
from __future__ import annotations

import asyncio
import json
from pathlib import Path

from .. import pricing
from ..config import settings
from ..events import bus
from ..services import audio, chatterbox_tts, piper_tts
from .base import AgentContext, agent_node

TAIL = 1.4  # son kelimeden sonra kapanış süresi (sn)
VALID = {"chatterbox", "piper", "elevenlabs", "babble", "silence"}


def resolve_provider(requested: str | None) -> str:
    """İstenen motor geçersizse ya da "auto" ise: chatterbox > piper > babble (kurulu olan ilki)."""
    p = (requested or settings.tts_provider or "auto").lower()
    if p in VALID:
        return p
    if chatterbox_tts.available():
        return "chatterbox"
    return "piper" if piper_tts.available() else "babble"


@agent_node("audio_voice", "Mikrofon test ediliyor…")
async def audio_voice_node(state: dict, ctx: AgentContext) -> dict:
    story = state["story"]
    scenes = story["scenes"]
    adir = Path(state["job_dir"]) / "audio"
    adir.mkdir(parents=True, exist_ok=True)
    text = audio.full_text(scenes)
    provider = resolve_provider((state.get("options") or {}).get("tts"))
    engine_info: dict = {"engine": provider}

    await ctx.say("Mikrofon test ediliyor… 1, 2, 3")
    await ctx.pace(0.6)

    if provider == "chatterbox" and not chatterbox_tts.available():
        await ctx.log("Chatterbox kurulu değil (yerel-modeller.ps1); Piper'a geçildi.", level="warn")
        provider = "piper"
    if provider == "piper" and not piper_tts.available():
        await ctx.log("Piper modeli bulunamadı; sentetik mırıltıya geçildi. "
                      "Kurmak için: backend\\.venv\\Scripts\\python scripts\\piper_ses_indir.py", level="warn")
        provider = "babble"

    if provider == "chatterbox":
        loop = asyncio.get_running_loop()
        agent_id, job_id = ctx.agent_id, ctx.job_id

        def say_threadsafe(text: str) -> None:
            loop.call_soon_threadsafe(lambda: asyncio.ensure_future(bus.agent(agent_id, "WORKING", text, job_id)))

        def progress(i: int, n: int, match: float) -> None:
            say_threadsafe(f"Chatterbox okuyor… cümle {i}/{n} (Whisper uyumu %{match * 100:.0f})")

        await ctx.say("Chatterbox ekran kartında seslendiriyor…")
        voice, words, duration, engine_info = await asyncio.to_thread(
            chatterbox_tts.synthesize, scenes, adir, progress, say_threadsafe)
        ts_source = "whisper-hizalama"
        voice_source = "Chatterbox Multilingual · yerel ekran kartı" + (
            f" · ses örneği: {engine_info['reference_voice']}" if engine_info.get("reference_voice") else "")
        await ctx.log(f"Chatterbox: {engine_info['sentences']} cümle, ortalama Whisper uyumu "
                      f"%{engine_info['avg_match'] * 100:.0f}, yeniden okunan {engine_info['retakes']}",
                      data=engine_info)
        await ctx.say("Kelime zaman damgaları hizalandı ✓")
        await ctx.pace(0.5)
    elif provider == "piper":
        loop = asyncio.get_running_loop()
        agent_id, job_id = ctx.agent_id, ctx.job_id

        def progress(i: int, n: int) -> None:
            loop.call_soon_threadsafe(lambda: asyncio.ensure_future(
                bus.agent(agent_id, "WORKING", f"Piper seslendiriyor… sahne {i}/{n}", job_id)))

        await ctx.say("Piper ile seslendiriliyor…")
        voice, words, duration, engine_info = await asyncio.to_thread(piper_tts.synthesize, scenes, adir, progress)
        ts_source = "piper-fonem-hizalama" if engine_info.get("aligned_sentences") else "piper-orantılı"
        voice_source = f"Piper · {engine_info['voice']} (çevrimdışı)"
        await ctx.say("Kelime zaman damgaları hizalandı ✓")
        await ctx.pace(0.5)
    elif provider == "elevenlabs":
        await ctx.say("ElevenLabs ile seslendiriliyor…")
        voice, words, duration = await audio.elevenlabs_tts(scenes, adir)
        ctx.add_cost(pricing.tts_cost(len(text)))
        ts_source = "elevenlabs-alignment"
        if words is None:
            await ctx.say("Whisper ile kelime hizalaması…")
            words = await audio.whisper_timestamps(voice, scenes)
            ctx.add_cost(pricing.whisper_cost(duration))
            ts_source = "whisper"
        voice_source = f"ElevenLabs · {settings.elevenlabs_model}"
        engine_info = {"engine": "elevenlabs", "model": settings.elevenlabs_model,
                       "voice_id": settings.elevenlabs_voice_id[:6] + "…"}
    else:
        silent = provider == "silence"
        await ctx.say("Sessizlik kaydediliyor (test)…" if silent else "Mırıltı sesi üretiliyor (test)…")
        words, duration = audio.mock_timestamps(scenes)
        voice = adir / "voice.wav"
        await asyncio.to_thread(audio.synth_babble, voice, words, duration + 0.3, silent)
        await ctx.pace(1.0)
        await ctx.say("Sahte kelime zaman damgaları yazılıyor…")
        await ctx.pace(0.8)
        ts_source = "sahte"
        voice_source = "sessizlik (test)" if silent else "sentetik mırıltı (test)"

    total = round(max(duration, words[-1]["end"] if words else 0) + TAIL, 3)

    await ctx.say("Arka plan müziği ekleniyor…")
    user_music = None if ctx.mock else audio.pick_user_music()
    if user_music:
        music, music_source = user_music, f"kullanıcı dosyası: {user_music.name}"
    else:
        music = adir / "music.wav"
        await asyncio.to_thread(audio.synth_music, music, total + 0.5)
        music_source = "sentetik müzik kutusu (telifsiz, kodla üretildi)"
    await ctx.pace(0.6)

    (adir / "words.json").write_text(json.dumps(words, ensure_ascii=False, indent=1), encoding="utf-8")
    await ctx.say(f"{len(words)} kelime, {total:.1f} sn ✓")
    await ctx.pace(0.4)
    out = {"audio": {
        "provider": provider,
        "voice_path": str(voice),
        "voice_source": voice_source,
        "engine": engine_info,
        "music_path": str(music),
        "music_source": music_source,
        "voice_duration": round(duration, 3),
        "total_duration": total,
        "timestamp_source": ts_source,
        "word_count": len(words),
        "words": words,
    }}
    if (state.get("fix_request") or {}).get("target") == "audio_voice":
        out["fix_request"] = None
    return out
