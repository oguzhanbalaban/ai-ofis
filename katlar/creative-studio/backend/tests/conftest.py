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

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
