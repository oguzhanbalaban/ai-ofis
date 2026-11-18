"""Ofis durumu (AI Ekip ofisindeki "Ofisi kapat / aç" ve "Duraklat / Sürdür"): data/ofis.json'da kalıcıdır.

- acik          : ekip sıradaki işleri alır.
- duraklatildi  : kısa mola; süren iş biter, sıradakiler bekler, boştakiler salona geçer.
- kapali        : mesai bitti; süren iş biter, sıradakiler bekler, ekip vedalaşıp asansörle çıkar.

Sunucuyu kapatmak (durdur.ps1, binadaki "Katı kapat") ayrı bir şeydir; bu yalnızca ekibin iş alıp almamasıdır.
"""
from __future__ import annotations

import asyncio
import json
import time

from .config import settings
from .events import bus

DURUMLAR = ("acik", "duraklatildi", "kapali")
EYLEMLER = {"ac": "acik", "surdur": "acik", "duraklat": "duraklatildi", "kapat": "kapali"}
_ADLAR = {"acik": "açık", "duraklatildi": "duraklatıldı", "kapali": "kapalı"}


class Ofis:
    def __init__(self) -> None:
        self._durum = "acik"
        self._zaman = time.time()
        self._kim = ""

    def _dosya(self):
        return settings.data_dir / "ofis.json"

    def yukle(self) -> None:
        try:
            d = json.loads(self._dosya().read_text(encoding="utf-8"))
            if d.get("durum") in DURUMLAR:
                self._durum = d["durum"]
                self._zaman = float(d.get("zaman") or time.time())
                self._kim = str(d.get("kim") or "")
        except (OSError, ValueError):
            pass

    @property
    def durum(self) -> str:
        return self._durum

    @property
    def acik(self) -> bool:
        return self._durum == "acik"

    def ozet(self) -> dict:
        return {"durum": self._durum, "ad": _ADLAR[self._durum], "zaman": self._zaman, "kim": self._kim}

    async def ayarla(self, eylem: str, kim: str = "panel") -> dict:
        yeni = EYLEMLER.get(eylem)
        if not yeni:
            raise ValueError(f"Bilinmeyen eylem: {eylem}")
        if yeni == self._durum:
            return self.ozet()
        eski = self._durum
        self._durum, self._zaman, self._kim = yeni, time.time(), kim
        try:
            settings.ensure_dirs()
            self._dosya().write_text(json.dumps({"durum": yeni, "zaman": self._zaman, "kim": kim}), encoding="utf-8")
        except OSError:
            pass
        metin = {
            "acik": "Ofis açıldı; ekip sıradaki işlere döndü." if eski == "kapali" else "Ekip moladan döndü; sıradaki işler sürüyor.",
            "duraklatildi": "Ekip duraklatıldı (mola). Süren iş biter; sıradakiler bekler.",
            "kapali": "Ofis kapatıldı; mesai bitti. Süren iş biter, yeni iş alınmaz (sıradakiler bekler).",
        }[yeni]
        await bus.log(metin, agent="director", data={"ofis": yeni, "kim": kim})
        await bus.broadcast({"type": "office", "office": self.ozet()})
        return self.ozet()

    async def acik_bekle(self) -> None:
        # Olay döngüsüne bağlı bir asyncio.Event yerine kısa yoklama: testlerde her asyncio.run yeni döngü açar
        while self._durum != "acik":
            await asyncio.sleep(0.5)


ofis = Ofis()
