import os
import sys
import tempfile
from pathlib import Path

# Testler her zaman mock modda, geçici bir veri klasöründe ve beklemesiz çalışır.
_TMP = tempfile.mkdtemp(prefix="studio-test-")
os.environ["MOCK_MODE"] = "true"
os.environ["MOCK_STEP_DELAY"] = "0"
os.environ["DATA_DIR"] = _TMP
os.environ["YOUTUBE_UPLOAD_ENABLED"] = "false"
# Hızlı ve belirlenimci: yer tutucu görsel + Piper. Yerel GPU motorlarının testi ayrı (RUN_GPU_TESTS=1).
os.environ["IMAGE_PROVIDER"] = "placeholder"
os.environ["TTS_PROVIDER"] = "piper"
# Testler .env'deki gerçek anahtarları asla görmesin (dış API çağrısı imkânsız olsun).
for _k in ("FAL_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ELEVENLABS_API_KEY", "ELEVENLABS_VOICE_ID"):
    os.environ[_k] = ""
# Testler masaüstüne / telefona bildirim göndermez, Claude'u çağırmaz, günlük özet zamanlayıcısı kapalı
os.environ["BILDIRIM_MASAUSTU"] = "false"
os.environ["BILDIRIM_TELEFON"] = "kapali"
os.environ["SOHBET_MOTORU"] = "yerel"
os.environ["OZET_SAATLERI"] = "kapali"
os.environ["AI_EKIP_AYARLAR"] = str(Path(_TMP) / "ai-ekip-yok.json")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
