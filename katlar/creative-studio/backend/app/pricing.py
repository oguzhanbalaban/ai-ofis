"""Tahmini API maliyetleri (USD).

Bunlar yaklaşık liste fiyatlarıdır; kendi planınıza göre .env içinden ezebilirsiniz.
Mock modda da hesaplanır ki panel "gerçek modda ne tutardı" bilgisini göstersin.
"""
from __future__ import annotations

import os


def _f(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, "") or default)
    except ValueError:
        return default


PRICE_LLM_PER_1K_TOKENS = _f("PRICE_LLM_PER_1K_TOKENS", 0.006)       # girdi+çıktı karışık ortalama
PRICE_IMAGE_EACH = _f("PRICE_IMAGE_EACH", 0.003)                     # flux/schnell ~ 1 MP görsel
PRICE_TTS_PER_1K_CHARS = _f("PRICE_TTS_PER_1K_CHARS", 0.30)          # ElevenLabs yaklaşık
PRICE_WHISPER_PER_MIN = _f("PRICE_WHISPER_PER_MIN", 0.006)
PRICE_YOUTUBE_UPLOAD = 0.0                                           # ücretsiz, kota tüketir


def llm_cost(prompt_chars: int, output_chars: int) -> float:
    tokens = (prompt_chars + output_chars) / 4.0
    return round(tokens / 1000.0 * PRICE_LLM_PER_1K_TOKENS, 5)


PRICE_OPENAI_IMAGE_EACH = _f("PRICE_OPENAI_IMAGE_EACH", 0.063)      # gpt-image-1, 1024x1536, medium


def image_cost(n: int, provider: str = "fal") -> float:
    """Yerel FLUX ve yer tutucu ücretsizdir (elektrik hariç)."""
    each = {"fal": PRICE_IMAGE_EACH * 1.33, "openai": PRICE_OPENAI_IMAGE_EACH}.get(provider, 0.0)
    return round(n * each, 5)


def tts_cost(chars: int) -> float:
    return round(chars / 1000.0 * PRICE_TTS_PER_1K_CHARS, 5)


def whisper_cost(seconds: float) -> float:
    return round(seconds / 60.0 * PRICE_WHISPER_PER_MIN, 5)
