"""AI Ekip ofisinden gelen özellikler: ofis aç/kapat/duraklat, iş iptali, sohbet, bildirim, günlük özet, kod çekmecesi."""
import asyncio
import json
import time
from pathlib import Path

import pytest

from app import bildirim, db, kaynak, ozet
from app import sohbet as sohbet_modulu
from app.config import settings
from app.events import bus
from app.jobs import JobRunner
from app.ofis import ofis


def _hazirla():
    settings.ensure_dirs()
    db.init_db()
    bus.loop = asyncio.get_running_loop()


async def _bekle(kosul, sn=60.0):
    son = time.time() + sn
    while time.time() < son:
        if kosul():
            return True
        await asyncio.sleep(0.1)
    return False


def test_ofis_duraklatinca_is_bekler_iptal_ve_surdur():
    async def go():
        _hazirla()
        r = JobRunner()
        r.start()
        try:
            await ofis.ayarla("duraklat", kim="test")
            assert json.loads((settings.data_dir / "ofis.json").read_text(encoding="utf-8"))["durum"] == "duraklatildi"
            j1 = await r.create("paylaşmak", {"failure": "none"})
            j2 = await r.create("cesaret", {"failure": "none"})
            await asyncio.sleep(1.5)
            assert db.get_job(j1["id"])["status"] == "queued"  # duraklatılmış ofis iş almaz
            assert r.current is None

            iptal = await r.cancel(j2["id"])  # sıradaki işi iptal
            assert iptal["status"] == "cancelled"
            with pytest.raises(ValueError):
                await r.cancel(j2["id"])  # iptal edilmiş iş yeniden iptal edilemez

            await ofis.ayarla("surdur", kim="test")
            assert await _bekle(lambda: (db.get_job(j1["id"]) or {}).get("status") == "running"
                                and r.current == j1["id"], 30)
            await asyncio.sleep(1.0)  # bir adımın ortasına denk gelsin
            sonuc = await r.cancel(j1["id"])
            assert sonuc["status"] == "cancelled"
            assert await _bekle(lambda: r.current is None, 10)
            await asyncio.sleep(0.8)  # iptal edilmiş j2 kuyruktan atlanır, başlamaz
            assert db.get_job(j2["id"])["status"] == "cancelled"
            assert r.current is None
            with db._lock:  # noqa: SLF001
                acik = db.conn().execute(
                    "SELECT COUNT(*) FROM step_runs WHERE job_id=? AND status='running'", (j1["id"],)).fetchone()[0]
            assert acik == 0
            assert db.stats()["cancelled"] >= 2
            assert all(a["status"] != "WORKING" or a.get("job_id") != j1["id"] for a in bus.agents.values())
        finally:
            await ofis.ayarla("ac", kim="test")
            await r.stop()

    asyncio.run(go())


def test_iptal_edilen_is_panodan_yeniden_baslatilabilir():
    async def go():
        _hazirla()
        r = JobRunner()
        j = await r.create("dostluk", {"failure": "none"})
        await r.cancel(j["id"])
        out = await r.revise(j["id"], "story", "Panodan baştan başlatıldı")
        assert out["status"] == "queued"

    asyncio.run(go())


def test_sohbet_yerel_yanit_ve_konu_onerisi(monkeypatch):
    monkeypatch.setattr(settings, "sohbet_motoru", "yerel")

    async def go():
        _hazirla()
        with pytest.raises(LookupError):
            await sohbet_modulu.sohbet.gonder("yok-boyle-ajan", "merhaba")
        with pytest.raises(ValueError):
            await sohbet_modulu.sohbet.gonder("storyteller", "   ")
        await sohbet_modulu.sohbet.gonder("storyteller", "Bana “paylaşan sincap” hakkında bir masal videosu yap")
        assert await _bekle(lambda: "storyteller" not in sohbet_modulu.sohbet.isleniyor, 10)
        m = sohbet_modulu.gecmis("storyteller")
        assert [x["kim"] for x in m[-2:]] == ["sen", "ajan"]
        assert m[-1]["oneri"] == {"konu": "paylaşan sincap"}
        assert "```" not in m[-1]["metin"]
        assert m[-1]["motor"] == "yerel"
        await sohbet_modulu.sohbet.gonder("director", "merhaba, ne yapıyorsun?")
        assert await _bekle(lambda: "director" not in sohbet_modulu.sohbet.isleniyor, 10)
        assert "oneri" not in sohbet_modulu.gecmis("director")[-1]
        assert bus.agents["director"]["status"] != "CHATTING"
        sohbet_modulu.temizle("director")
        assert sohbet_modulu.gecmis("director") == []

    asyncio.run(go())


def test_konu_blogu_ayiklanir():
    metin, oneri = sohbet_modulu.konu_ayikla('Olur!\n```konu\n{"konu": "Uykucu ayı kışa hazırlanıyor"}\n```')
    assert metin == "Olur!" and oneri == {"konu": "Uykucu ayı kışa hazırlanıyor"}
    assert sohbet_modulu.konu_ayikla("düz yanıt") == ("düz yanıt", None)
    _, bozuk = sohbet_modulu.konu_ayikla("```konu\n{bozuk}\n```")
    assert bozuk is None


def test_claude_kullanim_karti_hakki_korur(tmp_path, monkeypatch):
    sahte = tmp_path / "claude.exe"
    sahte.write_text("")
    kart = tmp_path / "claude_kullanim.json"
    kart.write_text(json.dumps({"guncelleme_zamani": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "kalan_yuzde": 12}))
    monkeypatch.setattr(settings, "claude_exe", str(sahte))
    monkeypatch.setattr(settings, "claude_kullanim_dosyasi", kart)
    monkeypatch.setattr(settings, "sohbet_motoru", "auto")
    assert "hakkı az" in (sohbet_modulu.claude_engeli() or "")
    motor, neden = sohbet_modulu.motor_sec()
    assert motor == "yerel" and "hakkı az" in (neden or "")  # mock modda LLM'e de geçmez
    kart.write_text(json.dumps({"guncelleme_zamani": "2020-01-01T00:00:00+03:00", "kalan_yuzde": 5}))
    assert sohbet_modulu.claude_engeli() is None  # bayat kart dikkate alınmaz


def test_bildirim_ayni_konuyu_bastirir_ve_telefon_varsayilan_kapali(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "bildirim_masaustu", False)

    async def go():
        _hazirla()
        once = len(bildirim.son_bildirimler(1000))
        assert await bildirim.bildir("Deneme", "ilk", anahtar="deneme-konu") is True
        assert await bildirim.bildir("Deneme", "ikinci", anahtar="deneme-konu") is False
        assert len(bildirim.son_bildirimler(1000)) == once + 1

    asyncio.run(go())
    assert bildirim._telefon_hedefi() is None  # noqa: SLF001
    ayar = tmp_path / "ayarlar.json"
    konu = "deneme-konusu"  # (sabit metin olarak yazılmaz: paket taraması kişisel bildirim konusu sanmasın)
    ayar.write_text(json.dumps({"bildirim": {"telefon": {"kanal": "ntfy", "ntfy_konu": konu}}}), encoding="utf-8")
    monkeypatch.setattr(settings, "bildirim_telefon", "ai-ekip")
    monkeypatch.setattr(settings, "ai_ekip_ayarlar", ayar)
    assert bildirim._telefon_hedefi() == {"sunucu": "https://ntfy.sh", "konu": konu}  # noqa: SLF001


def test_gunluk_ozet_yazilir():
    async def go():
        _hazirla()
        await JobRunner().create("sabır", {"failure": "none"})

    asyncio.run(go())
    o = ozet.yaz()
    assert o["metin"].startswith("# Creative Studio · günlük özet")
    assert "Bugün açılan iş" in o["metin"]
    assert Path(o["dosya"]).exists() and Path(o["dosya"]).parent.name == "raporlar"
    assert ozet.saatler() == []  # testte zamanlayıcı kapalı


def test_kod_cekmecesi_yalnizca_izinli_dosyalari_okur():
    yollar = {d["yol"] for d in kaynak.liste()}
    assert "backend/app/main.py" in yollar and "README.md" in yollar
    assert not any(y == ".env" or y.startswith(("secrets", "backend/data", "backend/models")) for y in yollar)
    for yasak in (".env", "../.env", "backend/data/studio.db", "C:/Windows/win.ini"):
        with pytest.raises(LookupError):
            kaynak.oku(yasak)
    assert "FastAPI" in kaynak.oku("backend/app/main.py")["metin"]
    assert any(s["yol"] == "backend/app/sohbet.py" for s in kaynak.ara("konu_ayikla"))
