"""Çocuk güvenliği için kural tabanlı metin denetimi (QA ajanının ilk savunma hattı).

Gerçek modda QA ayrıca LLM ile pedagojik değerlendirme yapar; bu liste her modda çalışır.
"""
from __future__ import annotations

import re

# Önek eşleşmesi (Türkçe ekleri yakalamak için kelime başında aranır)
PREFIX_TR = [
    "öldür", "ölüm", "kanlı", "silah", "tabanca", "bıçak", "intihar", "uyuşturucu", "alkol", "sigara",
    "korkunç", "dehşet", "şeytan", "aptal", "salak", "gerizekal", "nefret", "kumar",
]
# Tam kelime eşleşmesi ("kanat", "vurgu" gibi masum kelimeleri yakalamamak için)
EXACT_TR = ["kan", "vur", "vurdu", "vurdum", "döv", "dövdü", "döverim"]

PREFIX_EN = [
    "kill", "blood", "weapon", "gore", "horror", "scary", "violen", "drug", "alcohol", "cigarette",
    "nsfw", "nude", "sexy", "demon", "zombie", "knife",
]
EXACT_EN = ["gun", "guns"]

_WORD = r"[\wçğıöşü]"


def _hits(text: str, prefixes: list[str], exact: list[str]) -> list[str]:
    low = text.lower().replace("i̇", "i")
    found = []
    for root in prefixes:
        if re.search(rf"(?<!{_WORD}){re.escape(root)}", low):
            found.append(root)
    for word in exact:
        if re.search(rf"(?<!{_WORD}){re.escape(word)}(?!{_WORD})", low):
            found.append(word)
    return found


def check_story_text(text: str) -> list[str]:
    return _hits(text, PREFIX_TR, EXACT_TR)


def check_prompt(prompt: str) -> list[str]:
    # Negatif prompt kısmı yasak kelimeler içerebilir; yalnızca pozitif kısmı denetle.
    positive = prompt.split("Negative:")[0]
    return _hits(positive, PREFIX_EN, EXACT_EN)
