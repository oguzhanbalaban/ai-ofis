"""Bildirimler (AI Ekip ofisindeki gibi): video onay bekliyor, üretim takıldı, günlük özet.

Kanallar:
- Panel: her bildirim WebSocket ile panele gider (sağ altta kısa bilgi).
- Masaüstü: Windows bildirimi (BILDIRIM_MASAUSTU, varsayılan açık). Yereldir; veri bilgisayardan çıkmaz.
- Telefon (isteğe bağlı, varsayılan KAPALI): BILDIRIM_TELEFON=ntfy + BILDIRIM_NTFY_KONU, ya da
  BILDIRIM_TELEFON=ai-ekip (AI Ekip ofisinin ayarlar.json > bildirim.telefon kanalını paylaşır, başlık "Studio · ").
Aynı konu (anahtar) BILDIRIM_ARALIK_DK içinde bir kez bildirilir. Kayıt: data/bildirimler.jsonl
"""
from __future__ import annotations

import asyncio
import json
import logging
import subprocess
import sys
import time
from pathlib import Path

import httpx

from .config import settings
from .events import bus

log = logging.getLogger("studio.bildirim")

# AI Ekip ofisinin Windows bildirimleriyle aynı uygulama kimliği (PowerShell): ayrı bir kayıt gerektirmez
_UYGULAMA_KIMLIGI = r"{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
_TOAST_BETIGI = r"""
$ErrorActionPreference = 'Stop'
$b = [Console]::In.ReadToEnd() | ConvertFrom-Json
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$e = { param($x) [Security.SecurityElement]::Escape([string]$x) }
$xml = '<toast activationType="protocol" launch="{0}"><visual><binding template="ToastGeneric"><text>{1}</text><text>{2}</text></binding></visual></toast>' -f (& $e $b.adres), (& $e $b.baslik), (& $e $b.metin)
$d = New-Object Windows.Data.Xml.Dom.XmlDocument
$d.LoadXml($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($b.uygulama).Show([Windows.UI.Notifications.ToastNotification]::new($d))
"""

_son: dict[str, float] = {}


def _kayit_dosyasi() -> Path:
    return settings.data_dir / "bildirimler.jsonl"


def son_bildirimler(n: int = 30) -> list[dict]:
    p = _kayit_dosyasi()
    if not p.exists():
        return []
    out = []
    for satir in p.read_text(encoding="utf-8", errors="replace").splitlines()[-n:]:
        try:
            out.append(json.loads(satir))
        except ValueError:
            continue
    return out


def _masaustu(baslik: str, metin: str) -> None:
    if sys.platform != "win32":
        return
    girdi = json.dumps({"baslik": baslik, "metin": metin, "adres": settings.bildirim_panel_adresi,
                        "uygulama": _UYGULAMA_KIMLIGI}, ensure_ascii=False)
    try:
        subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", _TOAST_BETIGI],
            input=girdi.encode("utf-8"), capture_output=True, timeout=25,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        log.warning("Masaüstü bildirimi gösterilemedi: %s", exc)


def _ai_ekip_telefon() -> dict | None:
    """AI Ekip ofisinin telefon kanalı (bildirim.telefon) — yalnızca BILDIRIM_TELEFON=ai-ekip iken okunur."""
    yol = settings.ai_ekip_ayarlar
    if not yol or not yol.exists():
        return None
    try:
        tel = (json.loads(yol.read_text(encoding="utf-8-sig")).get("bildirim") or {}).get("telefon") or {}
    except (OSError, ValueError):
        return None
    if tel.get("kanal") == "ntfy" and tel.get("ntfy_konu"):
        return {"sunucu": tel.get("ntfy_sunucu") or "https://ntfy.sh", "konu": tel["ntfy_konu"]}
    return None


def _telefon_hedefi() -> dict | None:
    kanal = settings.bildirim_telefon
    if kanal == "ntfy" and settings.bildirim_ntfy_konu:
        return {"sunucu": settings.bildirim_ntfy_sunucu, "konu": settings.bildirim_ntfy_konu}
    if kanal == "ai-ekip":
        return _ai_ekip_telefon()
    return None


async def _telefon(baslik: str, metin: str, onem: str) -> None:
    hedef = _telefon_hedefi()
    if not hedef:
        return
    govde = {"topic": hedef["konu"], "title": baslik, "message": metin, "tags": ["clapper"],
             "priority": 4 if onem == "yuksek" else 3}
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            (await c.post(str(hedef["sunucu"]).rstrip("/"), json=govde)).raise_for_status()
    except Exception as exc:  # noqa: BLE001 — bildirim üretimi asla durdurmasın
        log.warning("Telefon bildirimi gönderilemedi: %s", exc)


async def bildir(baslik: str, metin: str, anahtar: str | None = None, onem: str = "normal",
                 aralik_dk: float | None = None) -> bool:
    """Bildirimi yayınlar. Aynı anahtar aralık içinde tekrar gelirse bastırılır (False döner)."""
    aralik = settings.bildirim_aralik_dk if aralik_dk is None else aralik_dk
    simdi = time.time()
    if anahtar:
        if anahtar in _son and simdi - _son[anahtar] < aralik * 60:
            return False
        _son[anahtar] = simdi
    dis_baslik = baslik if baslik.startswith(settings.bildirim_on_ek) else settings.bildirim_on_ek + baslik
    kayit = {"zaman": simdi, "baslik": baslik, "metin": metin, "onem": onem}
    try:
        settings.ensure_dirs()
        with _kayit_dosyasi().open("a", encoding="utf-8") as f:
            f.write(json.dumps(kayit, ensure_ascii=False) + "\n")
    except OSError:
        pass
    await bus.broadcast({"type": "notify", "notify": kayit})
    if settings.bildirim_masaustu:
        await asyncio.to_thread(_masaustu, dis_baslik, metin)
    await _telefon(dis_baslik, metin, onem)
    return True


async def is_durumu_bildir(job: dict) -> None:
    """İş bittiğinde (onaya düştü / takıldı) bildir."""
    durum = job.get("status")
    ad = job.get("title") or job.get("topic") or job.get("id")
    if durum == "awaiting_approval":
        await bildir("Video onay bekliyor", f"“{ad}” hazır. Panelde önizle ve onayla; sen onaylamadan hiçbir şey yüklenmez.",
                     anahtar=f"onay:{job.get('id')}:{job.get('revision_count') or 0}", onem="yuksek", aralik_dk=0)
    elif durum == "failed":
        await bildir("Üretim takıldı", f"“{ad}”: {(job.get('error') or 'bilinmeyen hata')[:160]}",
                     anahtar=f"takildi:{job.get('id')}", onem="yuksek")


def gorunur_ayarlar() -> dict:
    tel = _telefon_hedefi()
    return {"masaustu": settings.bildirim_masaustu, "telefon": settings.bildirim_telefon if tel else "kapali"}


