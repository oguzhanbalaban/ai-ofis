"""Arka plan (</> kod) çekmecesi: stüdyonun kaynak dosyalarını salt okunur gösterir (AI Ekip panelindeki gibi).

Yalnızca aşağıdaki listede eşleşen dosyalar okunur; .env, secrets, veri ve model klasörleri asla listelenmez.
"""
from __future__ import annotations

from pathlib import Path

from .config import PROJECT_DIR

# (grup, glob) — sıra paneldeki sırayı belirler
_DESENLER = [
    ("Belgeler", "README.md"),
    ("Belgeler", ".env.example"),
    ("Başlatıcılar", "baslat.ps1"),
    ("Başlatıcılar", "durdur.ps1"),
    ("Başlatıcılar", "kurulum.ps1"),
    ("Başlatıcılar", "yerel-modeller.ps1"),
    ("Ajanlar", "backend/app/agents/*.py"),
    ("Akış ve sunucu", "backend/app/*.py"),
    ("Servisler", "backend/app/services/*.py"),
    ("Yerel motorlar", "backend/engines/*.py"),
    ("Yerel motorlar", "backend/engines/*.txt"),
    ("Betikler", "backend/scripts/*.py"),
    ("Betikler", "backend/requirements*.txt"),
    ("Testler", "backend/tests/*.py"),
    ("Panel", "frontend/index.html"),
    ("Panel", "frontend/package.json"),
    ("Panel", "frontend/vite.config.js"),
    ("Panel", "frontend/src/*.js"),
    ("Panel", "frontend/src/*.jsx"),
    ("Panel", "frontend/src/*.css"),
    ("Panel", "frontend/src/components/*.jsx"),
    ("Panel", "frontend/src/office/*.js"),
]
_YASAK_PARCALAR = {".env", "secrets", "data", "models", ".venv", "node_modules", "__pycache__", ".git"}
MAX_BOYUT = 600_000


def _guvenli(p: Path) -> bool:
    try:
        rel = p.resolve().relative_to(PROJECT_DIR.resolve())
    except ValueError:
        return False
    return not any(parca in _YASAK_PARCALAR for parca in rel.parts) and p.is_file()


def liste() -> list[dict]:
    gorulen: set[str] = set()
    out = []
    for grup, desen in _DESENLER:
        for p in sorted(PROJECT_DIR.glob(desen)):
            if not _guvenli(p):
                continue
            rel = p.relative_to(PROJECT_DIR).as_posix()
            if rel in gorulen:
                continue
            gorulen.add(rel)
            try:
                boyut = p.stat().st_size
            except OSError:
                continue
            out.append({"yol": rel, "grup": grup, "boyut": boyut})
    return out


def oku(yol: str) -> dict:
    izinli = {d["yol"] for d in liste()}
    if yol not in izinli:
        raise LookupError("Bu dosya kod çekmecesinde gösterilmez.")
    p = PROJECT_DIR / yol
    if p.stat().st_size > MAX_BOYUT:
        raise ValueError("Dosya çok büyük.")
    metin = p.read_text(encoding="utf-8-sig", errors="replace")
    return {"yol": yol, "metin": metin, "satir": metin.count("\n") + 1}


def ara(sorgu: str, en_fazla: int = 200) -> list[dict]:
    sorgu = (sorgu or "").strip()
    if len(sorgu) < 2:
        return []
    k = sorgu.lower()
    out = []
    for d in liste():
        try:
            metin = (PROJECT_DIR / d["yol"]).read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
        for i, satir in enumerate(metin.splitlines(), 1):
            if k in satir.lower():
                out.append({"yol": d["yol"], "satir": i, "metin": satir.strip()[:200]})
                if len(out) >= en_fazla:
                    return out
    return out
