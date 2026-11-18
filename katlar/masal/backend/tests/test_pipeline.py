"""Mock hattın uçtan uca testi: gerçek FFmpeg render'ı, QA geri dönüşü ve yükleme güvenliği."""
import asyncio
import os
from pathlib import Path

import pytest

from app import db
from app.config import settings
from app.events import bus
from app.jobs import runner
from app.services import piper_tts, safety, youtube
from app.services.ffmpeg import probe


def _run(topic, failure="none"):
    async def go():
        settings.ensure_dirs()
        db.init_db()
        bus.loop = asyncio.get_running_loop()
        await runner.create(topic, {"failure": failure})
        job_id = runner.queue.get_nowait()
        await runner._run(job_id)  # noqa: SLF001
        return db.get_job(job_id)

    return asyncio.run(go())


def test_mock_mode_default_and_safe_upload_settings():
    assert settings.mock_mode is True
    assert settings.upload_possible is False
    assert youtube.privacy_status() == "private"


def test_end_to_end_mock_video():
    job = _run("paylaşmak")
    assert job["status"] == "awaiting_approval", job.get("error")
    state = job["state"]
    video = Path(state["edit"]["video_path"])
    assert video.exists()
    info = probe(video)
    assert (info["width"], info["height"]) == (1080, 1920)
    assert abs(float(info["fps"]) - 60) < 0.6
    assert info["has_audio"]
    assert 40 <= info["duration"] <= 60
    assert state["qa"]["passed"] is True
    assert state["story"]["word_count"] <= 130
    if piper_tts.available():
        assert state["audio"]["provider"] == "piper"
        assert state["audio"]["timestamp_source"] == "piper-fonem-hizalama"
    assert 6 <= len(state["story"]["scenes"]) <= 8
    pub = state["publish"]
    assert pub["privacyStatus"] == "private"
    assert pub["selfDeclaredMadeForKids"] is True
    assert pub["uploaded"] is False
    assert Path(pub["draft_path"]).exists()


@pytest.mark.skipif(not piper_tts.available(), reason="Piper modeli indirilmemiş")
def test_piper_voice_has_real_word_alignment(tmp_path):
    scenes = [{"text": "Kaplumbağa Tosba'nın elinde sihirli bir tohum vardı!"},
              {"text": "Ama bu tohum ne zaman büyüyecekti?"}]
    wav, words, duration, info = piper_tts.synthesize(scenes, tmp_path)
    assert wav.exists() and duration > 2
    assert [w["word"] for w in words] == " ".join(s["text"] for s in scenes).split()
    assert info["aligned_sentences"] == 2 and info["fallback_sentences"] == 0
    starts = [w["start"] for w in words]
    assert starts == sorted(starts)
    assert all(w["end"] > w["start"] for w in words)
    assert words[-1]["end"] <= duration


def test_visual_timeout_is_retried_by_director():
    job = _run("cesaret", failure="visual_timeout")
    assert job["status"] == "awaiting_approval"
    assert job["state"]["retries"].get("visual_generator") == 1


def test_youtube_upload_refused_in_mock_even_if_confirmed():
    with pytest.raises(youtube.UploadRefused):
        youtube.upload(Path("yok.mp4"), {"title": "t", "description": "d"}, user_confirmed=True)
    with pytest.raises(youtube.UploadRefused):
        youtube.upload(Path("yok.mp4"), {"title": "t", "description": "d"}, user_confirmed=False)


def test_image_provider_resolution_falls_back_safely():
    from app.services import images

    avail = images.available_providers()
    assert avail["fal"] is False and avail["openai"] is False  # testte anahtar yok
    assert images.resolve_provider("fal") in ("flux_local", "placeholder")
    assert images.resolve_provider("placeholder") == "placeholder"


def test_api_image_providers_parse_responses_without_network(tmp_path, monkeypatch):
    """fal.ai ve OpenAI istek/yanıt şekli: ağa çıkmadan sahte taşıyıcıyla denenir."""
    import base64
    import io

    import httpx
    from PIL import Image

    from app.services import images

    buf = io.BytesIO()
    Image.new("RGB", (1024, 1536), (200, 180, 255)).save(buf, "PNG")
    png = buf.getvalue()
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        if request.url.host == "fal.run":
            return httpx.Response(200, json={"images": [{"url": "https://cdn.example/x.png"}]})
        if request.url.host == "cdn.example":
            return httpx.Response(200, content=png)
        if request.url.host == "api.openai.com":
            return httpx.Response(200, json={"data": [{"b64_json": base64.b64encode(png).decode()}]})
        return httpx.Response(404)

    monkeypatch.setattr(settings, "fal_key", "sahte")
    monkeypatch.setattr(settings, "openai_api_key", "sahte")

    async def go():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            a = await images.generate_api("fal", tmp_path / "fal.png", "a bunny", seed=7, client=client)
            b = await images.generate_api("openai", tmp_path / "oa.png", "a bunny", "text", client=client)
        return a, b

    a, b = asyncio.run(go())
    for p in (a, b):
        assert Image.open(p).size == (1080, 1920)
    fal_req = seen[0]
    assert fal_req.headers["Authorization"] == "Key sahte"
    assert b'"seed":7' in fal_req.content.replace(b" ", b"")
    oa_req = [r for r in seen if r.url.host == "api.openai.com"][0]
    assert oa_req.headers["Authorization"] == "Bearer sahte"
    assert b"Avoid: text" in oa_req.content


def test_chatterbox_gap_filling_keeps_word_order():
    from app.services.chatterbox_tts import _fill_gaps, split_sentences

    assert split_sentences("Bir gün geçti. İki gün geçti! Ne oldu?") == ["Bir gün geçti.", "İki gün geçti!", "Ne oldu?"]
    toks = "Kaplumbağa Tosba sihirli bir tohum buldu".split()
    times = [{"start": 0.1, "end": 0.6}, None, None, {"start": 1.5, "end": 1.7}, None, {"start": 2.4, "end": 2.9}]
    spans = _fill_gaps(toks, times, 3.0)
    assert len(spans) == len(toks)
    starts = [a for a, _ in spans]
    assert starts == sorted(starts) and all(b > a for a, b in spans) and spans[-1][1] <= 3.0
    assert _fill_gaps(toks, [None] * len(toks), 2.0)[-1][1] <= 2.0


@pytest.mark.skipif(os.environ.get("RUN_GPU_TESTS") != "1", reason="GPU testi: RUN_GPU_TESTS=1 ile çalıştırın")
def test_local_gpu_engines_end_to_end():
    """Yerel FLUX + Chatterbox ile tam üretim (birkaç dakika sürer, ekran kartı ister)."""
    from app.services import chatterbox_tts, local_engines

    if not (local_engines.available("flux") and chatterbox_tts.available()):
        pytest.skip("Yerel motorlar kurulu değil (yerel-modeller.ps1)")

    async def go():
        settings.ensure_dirs()
        db.init_db()
        bus.loop = asyncio.get_running_loop()
        await runner.create("sabırlı olmak", {"failure": "none", "tts": "chatterbox", "image": "flux_local"})
        job_id = runner.queue.get_nowait()
        await runner._run(job_id)  # noqa: SLF001
        return db.get_job(job_id)

    job = asyncio.run(go())
    assert job["status"] == "awaiting_approval", job.get("error")
    st = job["state"]
    assert st["visuals"]["provider"] == "flux_local"
    assert st["audio"]["provider"] == "chatterbox"
    assert st["audio"]["engine"]["avg_match"] >= 0.7
    info = probe(Path(st["edit"]["video_path"]))
    assert (info["width"], info["height"]) == (1080, 1920) and info["has_audio"]


def test_safety_filters():
    assert safety.check_story_text("Kuşun kanatları parlıyordu ve vurgu yaptı.") == []
    assert "silah" in safety.check_story_text("Elinde bir silah vardı.")
    assert safety.check_prompt("cute bunny. Negative: scary, gun") == []
    assert safety.check_prompt("a bunny holding a gun")
