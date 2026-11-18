"""YouTube OAuth yetkilendirmesi — YALNIZCA kullanıcı tarafından elle çalıştırılır.

Sunucu bu betiği hiçbir zaman kendiliğinden çalıştırmaz.

Kullanım (backend klasöründe):
    .venv\\Scripts\\python scripts\\youtube_yetkilendir.py

Önkoşullar:
  1. Google Cloud Console'da bir proje açıp "YouTube Data API v3"ü etkinleştirin.
  2. "OAuth istemci kimliği" (Masaüstü uygulaması) oluşturup JSON'u
     secrets/client_secret.json olarak kaydedin (yolu .env -> YOUTUBE_CLIENT_SECRETS ile değiştirebilirsiniz).
  3. pip install -r requirements-real.txt
Betik tarayıcıda Google onay sayfasını açar; onay sonrası jeton secrets/youtube_token.json'a yazılır.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import settings  # noqa: E402
from app.services.youtube import SCOPES  # noqa: E402


def main() -> int:
    secrets = settings.youtube_client_secrets
    if not secrets.exists():
        print(f"İstemci sırrı bulunamadı: {secrets}")
        return 1
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        print("Önce: pip install -r requirements-real.txt")
        return 1
    answer = input("Google hesabınız için YouTube yükleme izni istenecek. Devam edilsin mi? (evet/hayır): ")
    if answer.strip().lower() not in {"evet", "e", "yes", "y"}:
        print("İptal edildi.")
        return 0
    flow = InstalledAppFlow.from_client_secrets_file(str(secrets), SCOPES)
    creds = flow.run_local_server(host="127.0.0.1", port=8090, open_browser=True)
    settings.youtube_token_file.parent.mkdir(parents=True, exist_ok=True)
    settings.youtube_token_file.write_text(creds.to_json(), encoding="utf-8")
    print(f"Jeton kaydedildi: {settings.youtube_token_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
