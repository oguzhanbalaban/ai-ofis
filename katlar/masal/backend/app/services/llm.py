"""Gerçek mod LLM çağrıları (Anthropic veya OpenAI). Mock modda hiç çağrılmaz."""
from __future__ import annotations

import json
import re

import httpx

from ..config import settings


class LLMError(RuntimeError):
    pass


async def complete(system: str, user: str, max_tokens: int = 1500) -> str:
    if settings.mock_mode:
        raise LLMError("Mock modda gerçek LLM çağrısı yapılmaz.")
    provider = settings.llm_provider
    model = settings.effective_llm_model
    async with httpx.AsyncClient(timeout=120) as client:
        if provider == "anthropic":
            if not settings.anthropic_api_key:
                raise LLMError("ANTHROPIC_API_KEY tanımlı değil (.env).")
            r = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "x-api-key": settings.anthropic_api_key,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                },
                json={"model": model, "max_tokens": max_tokens, "system": system,
                      "messages": [{"role": "user", "content": user}]},
            )
            r.raise_for_status()
            data = r.json()
            return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
        if provider == "openai":
            if not settings.openai_api_key:
                raise LLMError("OPENAI_API_KEY tanımlı değil (.env).")
            r = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {settings.openai_api_key}"},
                json={"model": model, "response_format": {"type": "json_object"},
                      "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]},
            )
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
    raise LLMError(f"Bilinmeyen LLM_PROVIDER: {provider}")


def parse_json(text: str) -> dict:
    """Model çıktısından ilk JSON nesnesini çıkar."""
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
    if fence:
        text = fence.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        raise LLMError("Model yanıtında JSON bulunamadı.")
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError as exc:
        raise LLMError(f"JSON ayrıştırılamadı: {exc}") from exc


async def complete_json(system: str, user: str, max_tokens: int = 1500) -> tuple[dict, int, int]:
    """(json, istem_karakteri, çıktı_karakteri) döndürür — maliyet tahmini için."""
    out = await complete(system, user, max_tokens)
    return parse_json(out), len(system) + len(user), len(out)
