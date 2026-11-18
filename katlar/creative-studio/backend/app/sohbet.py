"""Ajanlarla sohbet (AI Ekip ofisindeki sohbet penceresinin Creative Studio karşılığı).

- Bir ajana panelden yazılır; ajan kendi rolüyle, stüdyonun o anki durumunu bilerek kısa yanıt verir.
- Salt okunur: sohbette dosya değiştirilmez, komut çalıştırılmaz, iş başlatılmaz, yükleme yapılmaz.
- Kullanıcı yeni bir video isterse ajan yanıtına bir KONU önerisi ekler (```konu {...}```); panelde
  "Gözden geçir ve ekibe ver" ile Yeni hikâye formu dolar, kullanıcı onaylayınca iş başlar. Onaysız hiçbir şey başlamaz.
- Motor (SOHBET_MOTORU): claude (bilgisayardaki Claude Code, abonelik) · llm (.env LLM API'si, gerçek modda) ·
  yerel (yapay zekâsız, paneldeki verilerden) · auto. Claude çağrısı günlük sınırlı ve AI Ekip'in kullanım kartını
  (ai-devir\\claude_kullanim.json) dikkate alır: kalan hak azsa Claude çağrılmaz.
Kayıtlar: data/sohbet/<ajan>.jsonl, günlük sayaç data/sohbet/sayac.json
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from . import db
from .agents.registry import AGENT_BY_ID, AGENTS
from .config import settings
from .events import bus
from .ofis import ofis

log = logging.getLogger("studio.sohbet")

MAX_MESAJ = 2000
_DURUM_TR = {
    "queued": "sırada", "running": "üretiliyor", "awaiting_approval": "onay bekliyor", "approved": "onaylandı",
    "uploading": "yükleniyor", "uploaded": "yüklendi", "failed": "takıldı", "interrupted": "yarıda kaldı",
    "cancelled": "iptal edildi",
}

# Rol tanımları (paneldeki karakter kartıyla aynı görev metni + sohbette işine yarayan ayrıntılar)
ROLLER = {
    "director": ("Günün konusunu seçer, hattı yönetir; bir adım hata verirse yeniden tetikler, QA reddinde işi geri gönderir.",
                 "Akışın tamamını, işlerin durumunu ve kimin ne yaptığını bilirsin. Konu seçimi ve sıra senin işin."),
    "storyteller": ("Konuyu 45-60 saniyelik, sahnelere bölünmüş bir çocuk masalına çevirir; kanca cümlesini ve mesajı yazar.",
                    "3-8 yaş, pozitif mesaj, en çok 130 kelime, 6-8 sahne, ilk cümle merak uyandıran bir kanca."),
    "art_director": ("Kahramanın görünüşünü sabitler, her sahne için çizim istemini ve karakter referansını hazırlar.",
                     "Pastel, sıcak, çocuklara uygun bir görsel dil; her sahnede aynı kahraman (stil + karakter çapası, seed)."),
    "visual_generator": ("Sahneleri seçilen çizim motoruyla çizer ve Ken Burns hareketli ara klipleri üretir.",
                         "Motorlar: FLUX.2 klein (yerel ekran kartı), fal.ai, OpenAI ya da kodla çizilmiş yer tutucu."),
    "audio_voice": ("Hikâyeyi seslendirir, kelime zamanlarını çıkarır (karaoke altyazı için) ve müziği ekler.",
                    "Motorlar: Chatterbox (yerel, duygulu), ElevenLabs (ücretli), Piper (çevrimdışı), test sesleri."),
    "editor": ("Klipleri, sesi ve karaoke altyazıyı FFmpeg ile 1080x1920 dikey videoya birleştirir.",
               "60 fps H.264, geçişler, konuşmada kısılan müzik, kelime kelime renklenen altyazı."),
    "qa_safety": ("Videoyu ve metni pedagojik ve teknik açıdan denetler; sorun varsa ilgili ajana geri gönderir.",
                  "Güvenlik, kelime/sahne sınırları, çözünürlük, fps, ses, süre senkronu ve dosya bütünlüğü."),
    "publisher": ("SEO başlığı, açıklama ve etiketleri hazırlar; yalnız kullanıcının onayıyla (varsayılan private) yükler.",
                  "Kendiliğinden asla yükleme yapmazsın; her video önce yerel taslaktır, karar kullanıcınındır."),
}


class SohbetHatasi(RuntimeError):
    pass


# ---------------------------------------------------------------- yardımcılar
def _klasor() -> Path:
    k = settings.data_dir / "sohbet"
    k.mkdir(parents=True, exist_ok=True)
    return k


def _dosya(ajan: str) -> Path:
    return _klasor() / f"{ajan}.jsonl"


def _ajan_dogrula(ajan: str) -> dict:
    meta = AGENT_BY_ID.get(ajan)
    if not meta:
        raise LookupError(f"Böyle bir ajan yok: {ajan}")
    return meta


def gecmis(ajan: str, n: int = 80) -> list[dict]:
    _ajan_dogrula(ajan)
    p = _dosya(ajan)
    if not p.exists():
        return []
    out = []
    for satir in p.read_text(encoding="utf-8", errors="replace").splitlines()[-n:]:
        try:
            out.append(json.loads(satir))
        except ValueError:
            continue
    return out


def _ekle(ajan: str, kayit: dict) -> dict:
    kayit = {"id": f"{int(time.time() * 1000)}-{os.urandom(2).hex()}", "zaman": time.time(), **kayit}
    with _dosya(ajan).open("a", encoding="utf-8") as f:
        f.write(json.dumps(kayit, ensure_ascii=False) + "\n")
    return kayit


def temizle(ajan: str) -> None:
    """Sohbeti temizle: eski yazışma silinmez, tarihli bir dosyaya taşınır."""
    _ajan_dogrula(ajan)
    p = _dosya(ajan)
    if p.exists() and p.stat().st_size:
        p.rename(p.with_name(f"{ajan}-{time.strftime('%Y%m%d-%H%M%S')}.jsonl.eski"))


def _kisa(metin: str, en: int) -> str:
    metin = (metin or "").strip()
    return metin if len(metin) <= en else metin[: en - 1].rstrip() + "…"


# ---------------------------------------------------------------- motor seçimi
def claude_yolu() -> str | None:
    if settings.claude_exe and Path(settings.claude_exe).exists():
        return settings.claude_exe
    w = shutil.which("claude")
    if w:
        return w
    p = Path.home() / ".local" / "bin" / ("claude.exe" if os.name == "nt" else "claude")
    return str(p) if p.exists() else None


def _sayac_dosyasi() -> Path:
    return _klasor() / "sayac.json"


def _sayac() -> dict:
    bugun = time.strftime("%Y-%m-%d")
    try:
        s = json.loads(_sayac_dosyasi().read_text(encoding="utf-8"))
        if s.get("tarih") == bugun:
            return s
    except (OSError, ValueError):
        pass
    return {"tarih": bugun, "claude": 0, "llm": 0, "yerel": 0}


def _sayac_artir(motor: str) -> None:
    s = _sayac()
    s[motor] = int(s.get(motor) or 0) + 1
    try:
        _sayac_dosyasi().write_text(json.dumps(s), encoding="utf-8")
    except OSError:
        pass


def claude_engeli() -> str | None:
    """Claude kullanılamıyorsa nedeni (None = kullanılabilir)."""
    if not claude_yolu():
        return "Claude Code bu bilgisayarda bulunamadı"
    kullanilan = int(_sayac().get("claude") or 0)
    if settings.sohbet_gunluk_sinir > 0 and kullanilan >= settings.sohbet_gunluk_sinir:
        return f"günlük sohbet sınırı doldu ({kullanilan}/{settings.sohbet_gunluk_sinir})"
    kart = settings.claude_kullanim_dosyasi
    try:
        if kart and kart.exists():
            k = json.loads(kart.read_text(encoding="utf-8-sig"))
            zaman = datetime.fromisoformat(str(k.get("guncelleme_zamani")))
            if zaman.tzinfo is None:
                zaman = zaman.astimezone()
            yas_saat = (datetime.now(timezone.utc) - zaman).total_seconds() / 3600
            kalan = int(k.get("kalan_yuzde"))
            if yas_saat < 3 and kalan < settings.sohbet_min_kalan_yuzde:
                return f"Claude kullanım hakkı az (kalan %{kalan}); hakkın korunuyor"
    except (OSError, ValueError, TypeError):
        pass
    return None


def _llm_hazir() -> bool:
    if settings.mock_mode:
        return False
    if settings.llm_provider == "anthropic":
        return bool(settings.anthropic_api_key)
    return bool(settings.openai_api_key)


def motor_sec() -> tuple[str, str | None]:
    """(motor, açıklama). Açıklama, istenen motor kullanılamadığında kullanıcıya gösterilir."""
    istenen = settings.sohbet_motoru if settings.sohbet_motoru in {"auto", "claude", "llm", "yerel"} else "auto"
    if istenen == "yerel":
        return "yerel", None
    neden = None
    if istenen in {"auto", "claude"}:
        neden = claude_engeli()
        if not neden:
            return "claude", None
        if istenen == "claude":
            return "yerel", f"Claude kullanılamadı: {neden}."
    if istenen in {"auto", "llm"} and _llm_hazir():
        return "llm", None
    if istenen == "llm":
        return "yerel", "LLM sohbeti yalnızca MOCK_MODE=false ve API anahtarıyla çalışır."
    return "yerel", (f"Claude kullanılamadı: {neden}." if neden and "bulunamadı" not in neden else None)


def motor_bilgisi() -> dict:
    motor, neden = motor_sec()
    ad = {"claude": f"Claude Code ({settings.sohbet_model})", "llm": f"LLM API ({settings.effective_llm_model})",
          "yerel": "yerel (yapay zekâsız, paneldeki verilerden)"}[motor]
    return {"motor": motor, "ad": ad, "not": neden, "bugun": _sayac(), "sinir": settings.sohbet_gunluk_sinir}


# ---------------------------------------------------------------- bağlam
def _son_isler(n: int = 8) -> list[dict]:
    try:
        return db.list_jobs(n)
    except Exception:  # noqa: BLE001
        return []


def _is_satiri(j: dict) -> str:
    st = j.get("state") or {}
    opt = st.get("options") or {}
    ad = (st.get("story") or {}).get("title") or j.get("title") or j.get("topic") or "(konu seçiliyor)"
    parca = [f"#{j['id']}", f"“{ad}”", f"[{_DURUM_TR.get(j.get('status'), j.get('status'))}]"]
    motor = " · ".join(x for x in (opt.get("image"), opt.get("tts")) if x)
    if motor:
        parca.append(f"motorlar: {motor}")
    if j.get("cost_usd"):
        parca.append(f"tahmini ${j['cost_usd']:.3f}")
    if st.get("revision_count"):
        parca.append(f"{st['revision_count']} revizyon")
    if j.get("error") and j.get("status") in {"failed", "cancelled", "interrupted"}:
        parca.append(f"not: {_kisa(j['error'], 140)}")
    return " ".join(parca)


def _ajan_calismasi(ajan: str, isler: list[dict]) -> str:
    """Ajanın en son katıldığı işteki çıktısının kısa özeti."""
    for j in isler:
        st = j.get("state") or {}
        if ajan == "storyteller" and st.get("story"):
            s = st["story"]
            return (f"Son hikâyen: “{s.get('title')}” — mesaj: {s.get('moral')}; kanca: {s.get('hook')}; "
                    f"{s.get('word_count')} kelime, {len(s.get('scenes') or [])} sahne.\nMetin: {_kisa(s.get('text') or '', 900)}")
        if ajan == "art_director" and st.get("art"):
            a = st["art"]
            sahneler = a.get("scenes") or a.get("prompts") or []
            return f"Son sahne planın: {len(sahneler)} sahne; stil: {_kisa(str(a.get('style') or a.get('style_anchor') or ''), 300)}"
        if ajan == "visual_generator" and st.get("visuals"):
            v = st["visuals"]
            return f"Son çizimin: {len(v.get('scenes') or [])} sahne, motor {v.get('engine')}."
        if ajan == "audio_voice" and st.get("audio"):
            a = st["audio"]
            return f"Son seslendirmen: motor {a.get('engine') or a.get('provider')}, zaman damgası {a.get('timestamp_source')}."
        if ajan == "editor" and st.get("edit"):
            p = (st["edit"].get("probe") or {})
            return f"Son kurgun: {p.get('width')}x{p.get('height')}, {p.get('fps')} fps, {p.get('duration')} sn."
        if ajan == "qa_safety" and st.get("qa"):
            q = st["qa"]
            sorunlar = "; ".join(str(x) for x in (q.get("issues") or [])[:5]) or "sorun yok"
            return f"Son QA raporun: {'geçti' if q.get('passed') else 'reddetti'} — {_kisa(sorunlar, 500)}"
        if ajan == "publisher" and st.get("publish"):
            p = st["publish"]
            return f"Son taslağın: “{p.get('title')}”, durum {p.get('status')}, privacyStatus {p.get('privacyStatus')}."
        if ajan == "director" and st.get("history"):
            h = st["history"][-3:]
            return "Son yönlendirmelerin: " + "; ".join(f"{x.get('route')} ({x.get('reason')})" for x in h)
    return "(henüz bir çıktın yok)"


def _baglam(ajan: str) -> dict:
    isler = _son_isler(8)
    ajanlar = []
    for a in AGENTS:
        st = bus.agents.get(a["id"], {})
        durum = {"WORKING": "çalışıyor", "ERROR": "hata verdi", "CHATTING": "sohbette"}.get(st.get("status"), "boşta")
        ajanlar.append(f"- {a['name']} ({a['role']}): {durum}" + (f" — {st['task']}" if st.get("task") else ""))
    loglar = [l for l in list(bus.logs) if l.get("agent") == ajan][-8:]
    return {"isler": isler, "ajanlar": "\n".join(ajanlar),
            "loglar": "\n".join(f"- {time.strftime('%H:%M', time.localtime(l['ts']))} {l['message']}" for l in loglar) or "(kayıt yok)"}


def _istem(ajan: str, metin: str, onceki: list[dict], b: dict) -> str:
    meta = AGENT_BY_ID[ajan]
    gorev, ayrinti = ROLLER.get(ajan, ("", ""))
    stats = {}
    try:
        stats = db.stats()
    except Exception:  # noqa: BLE001
        pass
    gecmis_metni = "\n\n".join(
        f"{'Kullanıcı' if m.get('kim') == 'sen' else meta['name']}: {_kisa(m.get('metin') or '', 1500)}"
        for m in onceki if m.get("kim") in {"sen", "ajan"}
    ) or "(bu sohbetin ilk mesajı)"
    isler = "\n".join(f"- {_is_satiri(j)}" for j in b["isler"]) or "(henüz iş yok)"
    return f"""# Sohbet
Sen **Creative Studio**'da (3-8 yaş çocuklar için dikey 9:16 masal YouTube Shorts videoları üreten 8 ajanlı bir stüdyo)
**{meta['name']}** olarak çalışıyorsun: {meta['role']}, istasyonun {meta['station']}. Stüdyonun sahibi (kullanıcı) sana
piksel ofis panelindeki sohbet penceresinden yazıyor. Bugün: {time.strftime('%d.%m.%Y %H:%M')}.

## Rolün
{gorev}
{ayrinti}

## Bu sohbetin kuralları
- Türkçe, kısa ve samimi yanıt ver (genelde 2-8 cümle; gerekirse kısa maddeler). Bir ekip arkadaşı gibi, kendi rolünün bakış açısıyla konuş.
- Bu sohbette yalnızca konuşursun: dosya değiştirmez, komut çalıştırmaz, iş başlatmaz, video yüklemezsin.
- Bilmediğin şeyi uydurma; emin değilsen söyle. Parola, anahtar ya da kişisel veri yazma.
- YouTube'a yükleme kararı her zaman kullanıcınındır; yalnızca paneldeki önizleme çekmecesinden onayla yapılır.
- Kullanıcı yeni bir video / masal isterse (ya da sen bir konu önermek istersen) işi bu sohbette yapmaya çalışma: kısaca nasıl
  olacağını anlat ve yanıtının EN SONUNA tek bir konu önerisi ekle (geçerli JSON, tek blok). Kullanıcı panelde
  "Gözden geçir ve ekibe ver" ile onaylar; onaysız hiçbir şey başlamaz:
```konu
{{"konu": "Kısa ve net masal konusu (en fazla 110 karakter)"}}
```
  Yalnızca gerçekten yeni bir video istendiğinde ya da önerdiğinde ekle; sıradan sorularda ekleme.

## Stüdyonun şu anki durumu
Ofis: {ofis.ozet()['ad']} · Mod: {'MOCK (dış API çağrısı yok)' if settings.mock_mode else 'GERÇEK'} · Yükleme: {'onayla açık' if settings.upload_possible else 'kapalı'} (privacyStatus {settings.youtube_privacy_status})
Toplam iş {stats.get('jobs_total', 0)}, video {stats.get('videos_rendered', 0)}, onaylanan {stats.get('approved', 0)}, takılan {stats.get('failed', 0)}, tahmini toplam maliyet ${stats.get('cost_total_usd', 0)}
Ekip:
{b['ajanlar']}

## Son işler (en yeni üstte)
{isler}

## Senin son çalışman
{_ajan_calismasi(ajan, b['isler'])}

## Senin son kayıtların
{b['loglar']}

## Sohbet geçmişi
{gecmis_metni}

## Kullanıcının yeni mesajı
{metin}
"""


# ---------------------------------------------------------------- motorlar
def _claude_cagir(istem: str) -> str:
    exe = claude_yolu()
    if not exe:
        raise SohbetHatasi("Claude Code bulunamadı.")
    # Claude masaüstü uygulamasından / .env'den gelen değişkenler CLI'ı API anahtarına ya da başka oturuma yönlendirmesin
    env = {k: v for k, v in os.environ.items() if not k.upper().startswith(("CLAUDE", "ANTHROPIC"))}
    komut = [exe, "-p", "--output-format", "json", "--no-session-persistence", "--model", settings.sohbet_model, "--tools", ""]
    try:
        r = subprocess.run(komut, input=istem.encode("utf-8"), capture_output=True, env=env,
                           cwd=str(_klasor()), timeout=settings.sohbet_zaman_asimi_sn,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except subprocess.TimeoutExpired as exc:
        raise SohbetHatasi(f"Claude {settings.sohbet_zaman_asimi_sn} sn içinde yanıt vermedi.") from exc
    except OSError as exc:
        raise SohbetHatasi(f"Claude çalıştırılamadı: {exc}") from exc
    cikti = r.stdout.decode("utf-8", "replace").strip()
    j = None
    for satir in reversed(cikti.splitlines()):
        try:
            j = json.loads(satir)
            break
        except ValueError:
            continue
    if not isinstance(j, dict):
        hata = r.stderr.decode("utf-8", "replace").strip()[-300:]
        raise SohbetHatasi(f"Claude yanıtı çözülemedi (kod {r.returncode}): {hata or cikti[-300:]}")
    if j.get("is_error") or j.get("subtype") != "success":
        raise SohbetHatasi(f"Claude hata döndürdü: {_kisa(str(j.get('result') or j.get('subtype')), 300)}")
    return str(j.get("result") or "").strip()


async def _llm_cagir(istem: str) -> str:
    from .services import llm

    sistem = ("Bir çocuk masalı video stüdyosunda ekip arkadaşı olarak sohbet ediyorsun. Yanıtını yalnızca JSON olarak ver: "
              '{"yanit": "Türkçe kısa yanıt", "konu": null ya da "yeni video için konu önerisi"}')
    out = await llm.complete(sistem, istem, max_tokens=900)
    try:
        d = llm.parse_json(out)
        yanit = str(d.get("yanit") or "").strip()
        if d.get("konu"):
            yanit += "\n```konu\n" + json.dumps({"konu": str(d["konu"])}, ensure_ascii=False) + "\n```"
        return yanit or out
    except Exception:  # noqa: BLE001
        return out


_TIRNAK = re.compile(r"[\"“”'‘’«»]([^\"“”'‘’«»]{3,110})[\"“”'‘’«»]")
_ISTEK = ("hikaye", "hikâye", "masal", "video", "konu", "shorts")
_FIIL = ("yap", "üret", "hazırla", "istiyorum", "olsun", "anlat", "çiz", "oluştur", "öner", "çek", "yaz")


def _konu_cikar(metin: str) -> str | None:
    m = _TIRNAK.search(metin)
    if m:
        return m.group(1).strip()
    kucuk = metin.lower()
    for anahtar in (" hakkında", " konulu", " ile ilgili", " üzerine"):
        i = kucuk.find(anahtar)
        if i > 3:
            parca = re.split(r"[.!?\n,;:]", metin[:i])[-1]
            parca = re.sub(r"^(bir|bana|bize|lütfen|şimdi|yeni)\s+", "", parca.strip(), flags=re.I)
            if len(parca) >= 3:
                return _kisa(parca, 110)
    return None


def _yerel_yanit(ajan: str, metin: str, b: dict) -> str:
    """Yapay zekâsız yanıt: niyeti basit anahtar kelimelerle anlar, gerçek verilerden konuşur."""
    meta = AGENT_BY_ID[ajan]
    gorev, ayrinti = ROLLER.get(ajan, ("", ""))
    k = metin.lower()
    st = bus.agents.get(ajan, {})
    simdi = st.get("task") if st.get("status") == "WORKING" else None
    isler = b["isler"]
    son = isler[0] if isler else None

    def durum_cumlesi() -> str:
        if simdi:
            return f"Şu an işteyim: {simdi}."
        if not ofis.acik:
            return f"Ofis şu an {ofis.ozet()['ad']}; ekip yeni iş almıyor."
        return "Şu an boştayım, yeni bir hikâye gelirse hazırım."

    if any(x in k for x in _ISTEK) and any(x in k for x in _FIIL):
        konu = _konu_cikar(metin)
        if not konu:
            temiz = re.sub(r"\b(bir|bana|bize|lütfen|yeni|hikaye|hikâye|masal|video|videosu|konulu|yap|yapar mısın|üret|"
                           r"hazırla|istiyorum|olsun|anlat|oluştur|öner)\b", " ", metin, flags=re.I)
            temiz = re.sub(r"\s+", " ", temiz).strip(" .,!?")
            konu = _kisa(temiz, 110) if len(temiz) >= 3 else None
        if konu:
            return (f"Güzel fikir! Bunu ekibe şöyle önerebilirim: “{konu}”. Onaylarsan Yönetmen işi sıraya alır; "
                    f"senaryo, çizim, ses ve kurgu bitince önizleme senin onayına gelir.\n```konu\n"
                    + json.dumps({"konu": konu}, ensure_ascii=False) + "\n```")
        return ("Yeni bir masal için konuyu biraz açar mısın? Örneğin: “paylaşmanın önemi” ya da “karanlıktan korkmayan "
                "tavşan”. Konu boş kalırsa Yönetmen günün konusunu kendisi seçer.")
    if any(x in k for x in ("merhaba", "selam", "günaydın", "iyi akşamlar", "naber", "nasılsın")):
        return f"Merhaba! Ben {meta['name']}, {meta['role'].lower()}. {durum_cumlesi()}"
    if any(x in k for x in ("ne yapıyorsun", "durum", "meşgul", "ne var", "neler oluyor", "ne alemde")):
        cumle = durum_cumlesi()
        if son:
            cumle += f" En son iş: {_is_satiri(son)}."
        return cumle
    if any(x in k for x in ("maliyet", "ücret", "para", "harca", "fiyat", "$")):
        s = db.stats()
        return (f"Tahmini toplam maliyet ${s.get('cost_total_usd', 0)}; video başına ${s.get('cost_per_video_usd', 0)}. "
                + ("Mock modda gerçek harcama yok, bunlar “gerçek modda ne tutardı” tahminleri." if settings.mock_mode else ""))
    if any(x in k for x in ("kaç", "istatistik", "toplam", "sayı")):
        s = db.stats()
        return (f"Şimdiye kadar {s.get('jobs_total', 0)} iş, {s.get('videos_rendered', 0)} video; "
                f"{s.get('approved', 0)} onaylı, {s.get('awaiting_approval', 0)} onay bekleyen, {s.get('failed', 0)} takılan iş var.")
    if any(x in k for x in ("son iş", "son video", "en son", "son hikaye", "son hikâye", "ne yaptın", "çıktı")):
        return _ajan_calismasi(ajan, isler) + (f"\nİş: {_is_satiri(son)}" if son else "")
    if any(x in k for x in ("görevin", "ne iş", "ne yaparsın", "kimsin", "rolün", "yardım")):
        return f"Ben {meta['name']}, {meta['station']} benim yerim. {gorev} {ayrinti}"
    return (f"{durum_cumlesi()} {gorev} Bana durumu, son çalışmamı ya da yeni bir masal fikrini sorabilirsin. "
            "(Bu yanıt yapay zekâsız, yerel verilerden; bilgisayarda Claude Code varsa daha ayrıntılı konuşurum.)")


_KONU_BLOK = re.compile(r"```konu\s*(\{.*?\})\s*```", re.S)


def konu_ayikla(metin: str) -> tuple[str, dict | None]:
    """Yanıttaki ```konu {...}``` bloğunu ayıklar → (görünen metin, öneri)."""
    oneri = None
    for m in _KONU_BLOK.finditer(metin or ""):
        try:
            d = json.loads(m.group(1))
            konu = _kisa(str(d.get("konu") or ""), 110)
            if konu and konu != "Kısa ve net masal konusu (en fazla 110 karakter)":
                oneri = {"konu": konu}
        except ValueError:
            continue
    return _KONU_BLOK.sub("", metin or "").strip(), oneri


# ---------------------------------------------------------------- akış
class Sohbet:
    def __init__(self) -> None:
        self.isleniyor: dict[str, float] = {}
        self._sinir: asyncio.Semaphore | None = None

    def durum(self) -> dict:
        return {"isleniyor": sorted(self.isleniyor), **motor_bilgisi()}

    async def gonder(self, ajan: str, metin: str) -> dict:
        _ajan_dogrula(ajan)
        metin = (metin or "").strip()
        if not metin:
            raise ValueError("Mesaj boş.")
        if len(metin) > MAX_MESAJ:
            raise ValueError(f"Mesaj en fazla {MAX_MESAJ} karakter olabilir.")
        if ajan in self.isleniyor:
            raise ValueError("Önceki mesajın yanıtı yazılıyor; biraz bekle.")
        kayit = _ekle(ajan, {"kim": "sen", "metin": metin})
        await bus.broadcast({"type": "chat", "ajan": ajan, "mesaj": kayit})
        self.isleniyor[ajan] = time.time()
        await bus.broadcast({"type": "chat_typing", "ajan": ajan, "yaziyor": True})
        asyncio.create_task(self._yanitla(ajan, metin), name=f"studio-sohbet-{ajan}")
        return kayit

    async def _yanitla(self, ajan: str, metin: str) -> None:
        if self._sinir is None:
            self._sinir = asyncio.Semaphore(3)
        onceki_durum = bus.agents.get(ajan, {}).get("status")
        sahnede = onceki_durum not in {"WORKING", "ERROR"}
        if sahnede:  # masasına geçip yazar (işi varsa işini bölmez)
            await bus.agent(ajan, "CHATTING", "💬 Sohbette yanıt yazıyor…", None)
        motor, not_ = motor_sec()
        try:
            async with self._sinir:
                gecmis_ = [m for m in gecmis(ajan, 17) if m.get("kim") in {"sen", "ajan"}][:-1][-16:]
                b = _baglam(ajan)
                if motor == "claude":
                    _sayac_artir("claude")
                    try:
                        ham = await asyncio.to_thread(_claude_cagir, _istem(ajan, metin, gecmis_, b))
                    except SohbetHatasi as exc:
                        log.warning("Claude sohbeti başarısız: %s", exc)
                        motor, not_ = "yerel", f"{exc} Yerel yanıt verildi."
                        ham = _yerel_yanit(ajan, metin, b)
                elif motor == "llm":
                    _sayac_artir("llm")
                    try:
                        ham = await _llm_cagir(_istem(ajan, metin, gecmis_, b))
                    except Exception as exc:  # noqa: BLE001
                        motor, not_ = "yerel", f"LLM yanıt vermedi ({_kisa(str(exc), 160)}). Yerel yanıt verildi."
                        ham = _yerel_yanit(ajan, metin, b)
                else:
                    _sayac_artir("yerel")
                    ham = _yerel_yanit(ajan, metin, b)
            gorunen, oneri = konu_ayikla(ham)
            kayit = {"kim": "ajan", "metin": gorunen or "(boş yanıt)", "motor": motor}
            if oneri:
                kayit["oneri"] = oneri
            if not_:
                kayit["not"] = not_
            kayit = _ekle(ajan, kayit)
            await bus.broadcast({"type": "chat", "ajan": ajan, "mesaj": kayit})
        except Exception as exc:  # noqa: BLE001
            log.exception("Sohbet yanıtı yazılamadı")
            kayit = _ekle(ajan, {"kim": "sistem", "metin": f"Yanıt yazılamadı: {_kisa(str(exc), 200)}"})
            await bus.broadcast({"type": "chat", "ajan": ajan, "mesaj": kayit})
        finally:
            self.isleniyor.pop(ajan, None)
            await bus.broadcast({"type": "chat_typing", "ajan": ajan, "yaziyor": False})
            if sahnede and bus.agents.get(ajan, {}).get("status") == "CHATTING":
                await bus.agent(ajan, "IDLE", None, None)


sohbet = Sohbet()
