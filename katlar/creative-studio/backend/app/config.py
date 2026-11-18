"""Ayarlar: proje kökündeki .env dosyasından okunur.

Varsayılanlar bilinçli olarak güvenli taraftadır:
- MOCK_MODE=true  -> hiçbir dış API çağrılmaz.
- YOUTUBE_UPLOAD_ENABLED=false -> onay verilse bile yalnızca yerel taslak üretilir.
- YOUTUBE_PRIVACY_STATUS=private
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = BACKEND_DIR.parent

# Önce proje kökündeki .env, sonra backend/.env (varsa) okunur.
load_dotenv(PROJECT_DIR / ".env", override=False)
load_dotenv(BACKEND_DIR / ".env", override=False)


def _bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "evet", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, "").strip() or default)
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, "").strip() or default)
    except ValueError:
        return default


def _str(name: str, default: str = "") -> str:
    val = os.getenv(name)
    return default if val is None or val.strip() == "" else val.strip()


def _path(name: str, default: Path) -> Path:
    raw = _str(name)
    if not raw:
        return default
    p = Path(os.path.expandvars(os.path.expanduser(raw)))  # %USERPROFILE%, ~ desteklenir
    return p if p.is_absolute() else (PROJECT_DIR / p).resolve()


@dataclass
class Settings:
    mock_mode: bool = field(default_factory=lambda: _bool("MOCK_MODE", True))
    host: str = field(default_factory=lambda: _str("BACKEND_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: _int("BACKEND_PORT", 8000))

    data_dir: Path = field(default_factory=lambda: _path("DATA_DIR", BACKEND_DIR / "data"))
    music_dir: Path = field(default_factory=lambda: _path("MUSIC_DIR", PROJECT_DIR / "assets" / "music"))
    secrets_dir: Path = field(default_factory=lambda: _path("SECRETS_DIR", PROJECT_DIR / "secrets"))

    # LLM (Senarist + Görsel Yönetmen + QA metin denetimi + Yayıncı SEO)
    llm_provider: str = field(default_factory=lambda: _str("LLM_PROVIDER", "anthropic").lower())
    llm_model: str = field(default_factory=lambda: _str("LLM_MODEL", ""))
    anthropic_api_key: str = field(default_factory=lambda: _str("ANTHROPIC_API_KEY"))
    openai_api_key: str = field(default_factory=lambda: _str("OPENAI_API_KEY"))

    # Görsel üretim — varsayılan çizim motoru: auto (yerel FLUX kuruluysa o, değilse yer tutucu)
    # | flux_local | fal | openai | placeholder. Panelde iş başına değiştirilebilir.
    image_provider: str = field(default_factory=lambda: _str("IMAGE_PROVIDER", "auto").lower())
    fal_key: str = field(default_factory=lambda: _str("FAL_KEY"))
    fal_model: str = field(default_factory=lambda: _str("FAL_MODEL", "fal-ai/flux/schnell"))
    openai_image_model: str = field(default_factory=lambda: _str("OPENAI_IMAGE_MODEL", "gpt-image-1"))
    openai_image_quality: str = field(default_factory=lambda: _str("OPENAI_IMAGE_QUALITY", "medium").lower())
    # Yerel FLUX.2 [klein] 4B
    flux_steps: int = field(default_factory=lambda: _int("FLUX_STEPS", 4))
    flux_width: int = field(default_factory=lambda: _int("FLUX_WIDTH", 1088))
    flux_height: int = field(default_factory=lambda: _int("FLUX_HEIGHT", 1920))
    flux_reference: bool = field(default_factory=lambda: _bool("FLUX_REFERENCE", True))

    # Ses
    elevenlabs_api_key: str = field(default_factory=lambda: _str("ELEVENLABS_API_KEY"))
    elevenlabs_voice_id: str = field(default_factory=lambda: _str("ELEVENLABS_VOICE_ID"))
    elevenlabs_model: str = field(default_factory=lambda: _str("ELEVENLABS_MODEL", "eleven_multilingual_v2"))
    timestamp_provider: str = field(default_factory=lambda: _str("TIMESTAMP_PROVIDER", "elevenlabs").lower())
    # Varsayılan ses motoru: auto (chatterbox > piper > babble) | chatterbox (yerel ekran kartı)
    # | piper (çevrimdışı) | elevenlabs (ücretli API) | babble (mırıltı) | silence
    tts_provider: str = field(default_factory=lambda: _str("TTS_PROVIDER", "auto").lower())
    chatterbox_exaggeration: float = field(default_factory=lambda: _float("CHATTERBOX_EXAGGERATION", 0.55))
    chatterbox_cfg_weight: float = field(default_factory=lambda: _float("CHATTERBOX_CFG_WEIGHT", 0.5))
    chatterbox_temperature: float = field(default_factory=lambda: _float("CHATTERBOX_TEMPERATURE", 0.8))
    # İsteğe bağlı anlatıcı ses örneği (10-20 sn, temiz kayıt; hakkı size ait olmalı). Yoksa modelin kendi sesi.
    chatterbox_reference: Path = field(
        default_factory=lambda: _path("CHATTERBOX_REFERENCE", PROJECT_DIR / "assets" / "voices" / "anlatici.wav")
    )
    piper_voice: str = field(default_factory=lambda: _str("PIPER_VOICE", "tr_TR-dfki-medium"))
    piper_model_dir: Path = field(default_factory=lambda: _path("PIPER_MODEL_DIR", BACKEND_DIR / "models" / "piper"))
    piper_length_scale: float = field(default_factory=lambda: _float("PIPER_LENGTH_SCALE", 1.12))
    mock_voice: str = field(default_factory=lambda: _str("MOCK_VOICE", "babble").lower())  # piper yoksa: babble | silence
    music_volume: float = field(default_factory=lambda: _float("MUSIC_VOLUME", 0.22))

    # Kurgu
    render_fps: int = field(default_factory=lambda: _int("RENDER_FPS", 60))
    render_preset: str = field(default_factory=lambda: _str("RENDER_PRESET", "veryfast"))
    render_crf: int = field(default_factory=lambda: _int("RENDER_CRF", 20))
    subtitle_font: str = field(default_factory=lambda: _str("SUBTITLE_FONT", "Comic Sans MS"))
    ffmpeg_path: str = field(default_factory=lambda: _str("FFMPEG_PATH"))
    ffprobe_path: str = field(default_factory=lambda: _str("FFPROBE_PATH"))

    # Yayın — güvenli varsayılanlar
    youtube_upload_enabled: bool = field(default_factory=lambda: _bool("YOUTUBE_UPLOAD_ENABLED", False))
    youtube_privacy_status: str = field(default_factory=lambda: _str("YOUTUBE_PRIVACY_STATUS", "private").lower())
    youtube_category_id: str = field(default_factory=lambda: _str("YOUTUBE_CATEGORY_ID", "1"))
    youtube_client_secrets: Path = field(
        default_factory=lambda: _path("YOUTUBE_CLIENT_SECRETS", PROJECT_DIR / "secrets" / "client_secret.json")
    )
    youtube_token_file: Path = field(
        default_factory=lambda: _path("YOUTUBE_TOKEN_FILE", PROJECT_DIR / "secrets" / "youtube_token.json")
    )

    # Akış denetimi
    max_step_retries: int = field(default_factory=lambda: _int("MAX_STEP_RETRIES", 2))
    max_qa_rounds: int = field(default_factory=lambda: _int("MAX_QA_ROUNDS", 2))
    # Mock modda animasyonların izlenebilmesi için adım içi bekleme çarpanı (0 = beklemesiz)
    mock_step_delay: float = field(default_factory=lambda: _float("MOCK_STEP_DELAY", 1.5))

    # Ajanlarla sohbet (AI Ekip ofisindeki sohbet penceresi): auto | claude | llm | yerel
    #   claude : bilgisayardaki Claude Code (abonelik; API anahtarı kullanılmaz), araçsız ve salt okunur
    #   llm    : .env'deki LLM API'si (ücretli; yalnızca MOCK_MODE=false iken)
    #   yerel  : yapay zekâsız, paneldeki verilerden kısa yanıt (hiçbir dış çağrı yok)
    #   auto   : claude varsa o, yoksa (gerçek modda) llm, yoksa yerel
    sohbet_motoru: str = field(default_factory=lambda: _str("SOHBET_MOTORU", "auto").lower())
    sohbet_model: str = field(default_factory=lambda: _str("SOHBET_MODEL", "sonnet"))
    sohbet_gunluk_sinir: int = field(default_factory=lambda: _int("SOHBET_GUNLUK_SINIR", 60))
    sohbet_zaman_asimi_sn: int = field(default_factory=lambda: _int("SOHBET_ZAMAN_ASIMI_SN", 180))
    claude_exe: str = field(default_factory=lambda: _str("CLAUDE_EXE"))
    # Etkileşimli Claude oturumlarının yazdığı kullanım kartı: kalan hak %SOHBET_MIN_KALAN_YUZDE altındaysa Claude çağrılmaz
    claude_kullanim_dosyasi: Path = field(
        default_factory=lambda: _path("CLAUDE_KULLANIM_DOSYASI", Path.home() / "ai-devir" / "claude_kullanim.json")
    )
    sohbet_min_kalan_yuzde: int = field(default_factory=lambda: _int("SOHBET_MIN_KALAN_YUZDE", 30))

    # Bildirimler: panel her zaman; masaüstü (Windows) varsayılan açık; telefon varsayılan KAPALI
    bildirim_masaustu: bool = field(default_factory=lambda: _bool("BILDIRIM_MASAUSTU", True))
    bildirim_telefon: str = field(default_factory=lambda: _str("BILDIRIM_TELEFON", "kapali").lower())  # kapali | ntfy | ai-ekip
    bildirim_ntfy_sunucu: str = field(default_factory=lambda: _str("BILDIRIM_NTFY_SUNUCU", "https://ntfy.sh"))
    bildirim_ntfy_konu: str = field(default_factory=lambda: _str("BILDIRIM_NTFY_KONU"))
    bildirim_aralik_dk: float = field(default_factory=lambda: _float("BILDIRIM_ARALIK_DK", 60))
    bildirim_on_ek: str = field(default_factory=lambda: _str("BILDIRIM_ON_EK", "Studio · "))
    bildirim_panel_adresi: str = field(default_factory=lambda: _str("BILDIRIM_PANEL_ADRESI", "http://127.0.0.1:5173/"))
    ai_ekip_ayarlar: Path = field(
        default_factory=lambda: _path("AI_EKIP_AYARLAR", Path.home() / "ai-ekip" / "ayarlar.json")
    )
    # Günlük özet (data/raporlar/ozet-<tarih>.md + bildirim); "kapali" = kapalı
    ozet_saatleri: str = field(default_factory=lambda: _str("OZET_SAATLERI", "12:30,18:30"))

    @property
    def outputs_dir(self) -> Path:
        return self.data_dir / "outputs"

    @property
    def db_path(self) -> Path:
        yeni = self.data_dir / "studio.db"
        # Eski ad (Masal Shorts) döneminden kalan veritabanı varsa bir kez yeni adına taşınır
        eski = self.data_dir / "masal.db"
        if not yeni.exists() and eski.exists():
            for ek in ("", "-wal", "-shm"):
                e = eski.with_name(eski.name + ek)
                if e.exists():
                    e.rename(yeni.with_name(yeni.name + ek))
        return yeni

    @property
    def effective_llm_model(self) -> str:
        if self.llm_model:
            return self.llm_model
        return "claude-sonnet-5-5" if self.llm_provider == "anthropic" else "gpt-4o-mini"

    @property
    def upload_possible(self) -> bool:
        """Gerçek YouTube yüklemesi teknik olarak mümkün mü (onay hâlâ ayrıca gerekir)."""
        return (not self.mock_mode) and self.youtube_upload_enabled

    def ensure_dirs(self) -> None:
        for d in (self.data_dir, self.outputs_dir, self.music_dir):
            d.mkdir(parents=True, exist_ok=True)

    def public_dict(self) -> dict:
        """Panelde gösterilecek, sır içermeyen ayarlar."""
        from .agents.audio_voice import resolve_provider as resolve_tts
        from .services import images, local_engines, piper_tts

        piper_ok = piper_tts.available()
        return {
            "mock_mode": self.mock_mode,
            "tts_provider": resolve_tts(None),
            "tts_available": {
                "chatterbox": local_engines.available("ses"),
                "piper": piper_ok,
                "elevenlabs": bool(self.elevenlabs_api_key and self.elevenlabs_voice_id),
                "babble": True,
            },
            "chatterbox_reference": self.chatterbox_reference.exists(),
            "piper_voice": self.piper_voice,
            "piper_license": piper_tts.license_note() if piper_ok else None,
            "llm_provider": self.llm_provider,
            "llm_model": self.effective_llm_model,
            "image_provider": images.resolve_provider(None),
            "image_available": images.available_providers(),
            "timestamp_provider": self.timestamp_provider,
            "render_fps": self.render_fps,
            "youtube_upload_enabled": self.youtube_upload_enabled,
            "youtube_privacy_status": self.youtube_privacy_status,
            "upload_possible": self.upload_possible,
            "ozet_saatleri": self.ozet_saatleri,
            "keys_present": {
                "anthropic": bool(self.anthropic_api_key),
                "openai": bool(self.openai_api_key),
                "fal": bool(self.fal_key),
                "elevenlabs": bool(self.elevenlabs_api_key and self.elevenlabs_voice_id),
                "youtube_client_secrets": self.youtube_client_secrets.exists(),
                "youtube_token": self.youtube_token_file.exists(),
            },
        }


settings = Settings()
