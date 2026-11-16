"""posta_oku.py - AI Ekip: gelen kutusundaki son iletileri okur (IMAP, salt okunur; iletileri okundu yapmaz).

Kimlik bilgileri ortam değişkenlerinden gelir (yalnızca bu sürece verilir):
  EKIP_POSTA_ADRES, EKIP_POSTA_SIFRE, EKIP_POSTA_IMAP (varsayılan imap.gmail.com)
Kullanım:  python -I posta_oku.py <adet>      -> JSON (UTF-8) stdout'a
           python -I posta_oku.py dene        -> yalnızca giriş denemesi
"""
import email
import imaplib
import json
import os
import re
import sys
from email.header import decode_header, make_header


def coz(deger):
    try:
        return str(make_header(decode_header(deger or "")))
    except Exception:
        return deger or ""


def govde(ileti):
    parcalar = ileti.walk() if ileti.is_multipart() else [ileti]
    html = ""
    for p in parcalar:
        if p.is_multipart() or "attachment" in str(p.get("Content-Disposition", "")).lower():
            continue
        tur = p.get_content_type()
        try:
            veri = p.get_payload(decode=True) or b""
            yazi = veri.decode(p.get_content_charset() or "utf-8", "replace")
        except Exception:
            continue
        if tur == "text/plain":
            return yazi
        if tur == "text/html" and not html:
            html = re.sub(r"<(script|style)[\s\S]*?</\1>", " ", yazi, flags=re.I)
            html = re.sub(r"<[^>]+>", " ", html)
    return re.sub(r"[ \t]+", " ", html)


def ekler(ileti):
    adlar = []
    for p in ileti.walk():
        if "attachment" in str(p.get("Content-Disposition", "")).lower():
            adlar.append(coz(p.get_filename() or "ek"))
    return adlar


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "20"
    sunucu = os.environ.get("EKIP_POSTA_IMAP") or "imap.gmail.com"
    m = imaplib.IMAP4_SSL(sunucu, 993)
    m.login(os.environ["EKIP_POSTA_ADRES"], os.environ["EKIP_POSTA_SIFRE"])
    if arg == "dene":
        m.logout()
        sys.stdout.buffer.write(b'{"giris": true}')
        return
    adet = max(1, min(100, int(arg)))
    m.select("INBOX", readonly=True)
    _, veri = m.search(None, "ALL")
    kimlikler = veri[0].split()[-adet:]
    sonuc = []
    for k in reversed(kimlikler):
        _, d = m.fetch(k, "(FLAGS BODY.PEEK[])")
        bayraklar = d[0][0].decode("ascii", "replace")
        ileti = email.message_from_bytes(d[0][1])
        sonuc.append({
            "kimden": coz(ileti.get("From")),
            "kime": coz(ileti.get("To")),
            "konu": coz(ileti.get("Subject")),
            "tarih": ileti.get("Date") or "",
            "okundu": "\\Seen" in bayraklar,
            "ekler": ekler(ileti),
            "metin": (govde(ileti) or "").strip()[:3000],
        })
    m.logout()
    sys.stdout.buffer.write(json.dumps(sonuc, ensure_ascii=False).encode("utf-8"))


if __name__ == "__main__":
    try:
        main()
    except Exception as hata:
        sys.stderr.write("HATA: %s\n" % hata)
        sys.exit(2)
