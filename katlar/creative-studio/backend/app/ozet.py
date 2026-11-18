"""Günlük özet (AI Ekip ofisindeki 12:30 / 18:30 özet raporlarının karşılığı).

OZET_SAATLERI (varsayılan "12:30,18:30") saatlerinde günün özeti data/raporlar/ozet-<tarih>.md dosyasına yazılır ve
bildirilir. Panelden istenince o anki özet her zaman üretilebilir (GET /api/ozet).
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta

from . import db
from .agents.registry import AGENT_BY_ID
from .config import settings
from .ofis import ofis

log = logging.getLogger("studio.ozet")

_DURUM_TR = {
    "queued": "Sırada", "running": "Üretiliyor", "awaiting_approval": "Onay bekliyor", "approved": "Onaylandı",
    "uploading": "Yükleniyor", "uploaded": "Yüklendi", "failed": "Takıldı", "interrupted": "Yarıda kaldı",
    "cancelled": "İptal edildi",
}


def _gun_araligi(tarih: str) -> tuple[float, float]:
    d = datetime.strptime(tarih, "%Y-%m-%d")
    return d.timestamp(), (d + timedelta(days=1)).timestamp()


def gunun_isleri(tarih: str) -> list[dict]:
    bas, son = _gun_araligi(tarih)
    with db._lock:  # noqa: SLF001
        rows = db.conn().execute(
            "SELECT * FROM jobs WHERE (created_at >= ? AND created_at < ?) OR (updated_at >= ? AND updated_at < ?) "
            "ORDER BY created_at", (bas, son, bas, son)).fetchall()
    return [db._row_to_job(r) for r in rows]  # noqa: SLF001


def _gunun_adimlari(tarih: str) -> dict:
    bas, son = _gun_araligi(tarih)
    with db._lock:  # noqa: SLF001
        rows = db.conn().execute(
            "SELECT agent, SUM(status='success'), SUM(status='fail'), COALESCE(SUM(cost_usd),0) FROM step_runs "
            "WHERE started_at >= ? AND started_at < ? GROUP BY agent", (bas, son)).fetchall()
    return {r[0]: {"ok": int(r[1] or 0), "hata": int(r[2] or 0), "maliyet": float(r[3] or 0)} for r in rows}


def ozet_metni(tarih: str | None = None) -> dict:
    tarih = tarih or time.strftime("%Y-%m-%d")
    isler = gunun_isleri(tarih)
    bas, son = _gun_araligi(tarih)
    yeni = [j for j in isler if bas <= (j.get("created_at") or 0) < son]
    say: dict[str, int] = {}
    for j in isler:
        say[j["status"]] = say.get(j["status"], 0) + 1
    video = sum(1 for j in isler if j.get("video_path"))
    maliyet = sum(float(j.get("cost_usd") or 0) for j in yeni)
    adimlar = _gunun_adimlari(tarih)
    insan = datetime.strptime(tarih, "%Y-%m-%d").strftime("%d.%m.%Y")
    satirlar = [
        f"# Creative Studio · günlük özet · {insan}",
        "",
        f"_Oluşturma: {time.strftime('%d.%m.%Y %H:%M')} · Ofis: {ofis.ozet()['ad']} · "
        f"Mod: {'MOCK' if settings.mock_mode else 'GERÇEK'}_",
        "",
        "## Sayılar",
        f"- Bugün açılan iş: **{len(yeni)}** · üzerinde çalışılan iş: {len(isler)} · video çıkan: {video}",
        "- Durumlar: " + (", ".join(f"{_DURUM_TR.get(k, k)} {v}" for k, v in sorted(say.items())) or "—"),
        f"- Tahmini maliyet (bugün açılan işler): ${maliyet:.3f}"
        + (" (mock: gerçek harcama yok)" if settings.mock_mode else ""),
    ]
    onay = [j for j in isler if j["status"] == "awaiting_approval"]
    if onay:
        satirlar += ["", "## Onayını bekleyenler"]
        satirlar += [f"- #{j['id']} “{j.get('title') or j.get('topic') or 'konu'}”" for j in onay]
    takilan = [j for j in isler if j["status"] in {"failed", "interrupted"}]
    if takilan:
        satirlar += ["", "## Takılanlar"]
        satirlar += [f"- #{j['id']} “{j.get('title') or j.get('topic') or 'konu'}”: {(j.get('error') or '')[:160]}" for j in takilan]
    if isler:
        satirlar += ["", "## İşler", "| No | Hikâye | Durum | Maliyet |", "|---|---|---|---|"]
        for j in isler:
            ad = (j.get("title") or j.get("topic") or "(konu seçildi)").replace("|", "/")
            satirlar.append(f"| {j['id']} | {ad} | {_DURUM_TR.get(j['status'], j['status'])} | ${float(j.get('cost_usd') or 0):.3f} |")
    if adimlar:
        satirlar += ["", "## Ajanlar (bugünkü adımlar)", "| Ajan | Başarılı | Hatalı |", "|---|---|---|"]
        for a, d in adimlar.items():
            satirlar.append(f"| {AGENT_BY_ID.get(a, {}).get('name', a)} | {d['ok']} | {d['hata']} |")
    if not isler:
        satirlar += ["", "Bugün iş yok."]
    metin = "\n".join(satirlar) + "\n"
    kisa = (f"{len(yeni)} yeni iş, {video} video, {len(onay)} onay bekliyor"
            + (f", {len(takilan)} takıldı" if takilan else "") + ".")
    return {"tarih": tarih, "metin": metin, "kisa": kisa}


def _rapor_klasoru():
    k = settings.data_dir / "raporlar"
    k.mkdir(parents=True, exist_ok=True)
    return k


def yaz(tarih: str | None = None) -> dict:
    o = ozet_metni(tarih)
    p = _rapor_klasoru() / f"ozet-{o['tarih']}.md"
    p.write_text(o["metin"], encoding="utf-8")
    o["dosya"] = str(p)
    return o


def saatler() -> list[str]:
    out = []
    for s in (settings.ozet_saatleri or "").split(","):
        s = s.strip()
        try:
            datetime.strptime(s, "%H:%M")
            out.append(s)
        except ValueError:
            continue
    return out


async def zamanlayici() -> None:
    """Belirlenen saatlerde günün özetini yazar ve bildirir (her saat günde bir kez)."""
    from .bildirim import bildir

    durum_dosyasi = _rapor_klasoru() / ".ozet-zamanlari.json"
    while True:
        try:
            simdi = datetime.now()
            bugun = simdi.strftime("%Y-%m-%d")
            try:
                yapilan = json.loads(durum_dosyasi.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                yapilan = {}
            for s in saatler():
                hedef = datetime.strptime(f"{bugun} {s}", "%Y-%m-%d %H:%M")
                anahtar = f"{bugun} {s}"
                # Saat geldiyse ve bugün bu saat için yazılmadıysa (sunucu o an kapalıysa 2 saate kadar telafi eder)
                if hedef <= simdi < hedef + timedelta(hours=2) and not yapilan.get(anahtar):
                    o = await asyncio.to_thread(yaz, bugun)
                    yapilan = {k: v for k, v in yapilan.items() if k.startswith(bugun)}
                    yapilan[anahtar] = time.time()
                    durum_dosyasi.write_text(json.dumps(yapilan), encoding="utf-8")
                    await bildir(f"Günlük özet ({s})", o["kisa"], anahtar=f"ozet:{anahtar}", aralik_dk=0)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("Günlük özet yazılamadı")
        await asyncio.sleep(60)
