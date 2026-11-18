"""YouTube Data API v3 yüklemesi.

GÜVENLİK KURALLARI (kod düzeyinde zorunlu):
1. Bu modül yalnızca kullanıcı paneldeki onay modalında "YouTube'a yükle" seçeneğini
   işaretleyip onayladığında, /api/jobs/{id}/approve uç noktası üzerinden çağrılır.
   LangGraph akışındaki Publisher düğümü buraya HİÇ dokunmaz; yalnızca taslak üretir.
2. MOCK_MODE=true iken gerçek yükleme asla yapılmaz (simülasyon döner).
3. YOUTUBE_UPLOAD_ENABLED=false iken (varsayılan) gerçek yükleme reddedilir.
4. privacyStatus varsayılanı "private"; selfDeclaredMadeForKids her zaman True.
5. OAuth akışı sunucu içinden başlatılmaz. Yetkilendirme yalnızca kullanıcının elle
   çalıştırdığı `backend/scripts/youtube_yetkilendir.py` ile yapılır.
"""
from __future__ import annotations

from pathlib import Path

from ..config import settings

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]
ALLOWED_PRIVACY = {"private", "unlisted", "public"}


class UploadRefused(RuntimeError):
    pass


def privacy_status() -> str:
    p = settings.youtube_privacy_status
    return p if p in ALLOWED_PRIVACY else "private"


def build_body(meta: dict) -> dict:
    return {
        "snippet": {
            "title": meta["title"][:100],
            "description": meta["description"][:4900],
            "tags": meta.get("tags", [])[:30],
            "categoryId": settings.youtube_category_id,
            "defaultLanguage": "tr",
            "defaultAudioLanguage": "tr",
        },
        "status": {
            "privacyStatus": privacy_status(),
            "selfDeclaredMadeForKids": True,
            "embeddable": True,
        },
    }


def upload(video: Path, meta: dict, user_confirmed: bool) -> dict:
    """Gerçek yükleme. Koşullar sağlanmazsa UploadRefused fırlatır."""
    if not user_confirmed:
        raise UploadRefused("Kullanıcı onayı olmadan yükleme yapılmaz.")
    if settings.mock_mode:
        raise UploadRefused("MOCK_MODE=true: gerçek yükleme devre dışı.")
    if not settings.youtube_upload_enabled:
        raise UploadRefused("YOUTUBE_UPLOAD_ENABLED=false: yalnızca yerel taslak üretildi.")
    token = settings.youtube_token_file
    if not token.exists():
        raise UploadRefused(
            "YouTube yetkilendirmesi yok. Önce `backend/scripts/youtube_yetkilendir.py` betiğini kendiniz çalıştırın."
        )
    try:
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except ImportError as exc:  # pragma: no cover
        raise UploadRefused("Google kütüphaneleri kurulu değil: pip install -r requirements-real.txt") from exc

    creds = Credentials.from_authorized_user_file(str(token), SCOPES)
    if not creds.valid:
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            token.write_text(creds.to_json(), encoding="utf-8")
        else:
            raise UploadRefused("YouTube jetonu geçersiz; yetkilendirme betiğini yeniden çalıştırın.")
    yt = build("youtube", "v3", credentials=creds, cache_discovery=False)
    media = MediaFileUpload(str(video), mimetype="video/mp4", chunksize=8 * 1024 * 1024, resumable=True)
    request = yt.videos().insert(part="snippet,status", body=build_body(meta), media_body=media)
    response = None
    while response is None:
        _status, response = request.next_chunk()
    vid = response.get("id")
    return {"video_id": vid, "url": f"https://youtu.be/{vid}", "privacyStatus": privacy_status()}
