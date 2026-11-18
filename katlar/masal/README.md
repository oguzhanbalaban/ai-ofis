# Masal Shorts · Piksel Ofis

3-8 yaş için dikey (9:16) **çocuk hikayesi YouTube Shorts** videoları üreten 8 ajanlı bir sistem ve
ajanların çalışmasını canlı izleyebileceğiniz **piksel sanat ofis paneli**.

- **Backend:** Python · FastAPI · LangGraph (8 düğümlü durum makinesi) · WebSocket · SQLite
- **Video:** FFmpeg filtre grafiği (Ken Burns `zoompan`, `xfade` geçişler, ASS karaoke altyazı,
  müzik ducking) → **1080x1920, 60 fps, H.264 MP4**
- **Frontend:** React + Vite · HTML5 Canvas üzerinde kodla çizilmiş özgün piksel ofis motoru
  (AI Ekip ofis panelinin sahne motoru ve tasarım diliyle: açık/koyu tema, departmanlar, pano, karakter kartı)

> **Varsayılan: `MOCK_MODE=true`.** Hiçbir API anahtarı gerekmez, hiçbir ücretli servis kendiliğinden çağrılmaz.
> Ekran kartı varsa sahneler **FLUX.2 [klein]** ile çizilir, masal **Chatterbox** ile duygulu Türkçe okunur
> (ikisi de yerel, ücretsiz, ticari kullanıma açık; kurulum: `yerel-modeller.ps1`). Kurulu değilse kodla
> çizilmiş yer tutucu görseller ve Piper sesi kullanılır. Panelden iş başına **fal.ai / OpenAI** çizim ve
> **ElevenLabs** ses API'leri de seçilebilir (ücretli, anahtar gerekir) — bkz.
> [Yerel motorlar](#5a-yerel-yapay-zekâ-motorları-ekran-kartında-ücretsiz).

---

## İçindekiler
1. [Gereksinimler](#1-gereksinimler)
2. [Kurulum](#2-kurulum)
3. [Çalıştırma](#3-çalıştırma)
4. [Paneli kullanma](#4-paneli-kullanma)
5. [Ajanlar ve akış](#5-ajanlar-ve-akış) · [Yerel motorlar](#5a-yerel-yapay-zekâ-motorları-ekran-kartında-ücretsiz) · [Ses motorları](#5b-ses-motorları-chatterbox--elevenlabs--piper)
6. [`.env` alanları](#6-env-alanları)
7. [Gerçek moda geçiş](#7-gerçek-moda-geçiş)
8. [YouTube yükleme güvenliği](#8-youtube-yükleme-güvenliği)
9. [Proje ağacı](#9-proje-ağacı)
10. [Test ve sorun giderme](#10-test-ve-sorun-giderme)

---

## 1. Gereksinimler

| Araç | Sürüm | Not |
|---|---|---|
| Python | 3.11+ (3.13 ile denendi) | `python --version` |
| Node.js | 18+ (22 ile denendi) | `node --version`, `npm --version` |
| FFmpeg | 6+ önerilir | **İsteğe bağlı.** Sistemde yoksa `pip` ile gelen `imageio-ffmpeg` ikilisi (FFmpeg 9, libass dahil) otomatik kullanılır. `ffprobe` ise yalnızca sistem kurulumunda gelir; yoksa video incelemesi `ffmpeg -i` çıktısından yapılır. |

FFmpeg'i sisteme kurmak isterseniz (Windows, resmi derleme sağlayıcısı gyan.dev):

```powershell
winget install --id Gyan.FFmpeg -e
```

Kurulumdan sonra yeni bir terminal açın; `ffmpeg -version` ve `ffprobe -version` çalışmalıdır.
Alternatif olarak `.env` içinde `FFMPEG_PATH` / `FFPROBE_PATH` ile tam yol verebilirsiniz.

---

## 2. Kurulum

### Kolay yol (Windows PowerShell 5.1)

```powershell
powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\kurulum.ps1"
```

`kurulum.ps1` şunları yapar: Python/Node/FFmpeg kontrolü → `backend\.venv` oluşturma →
`pip install -r requirements.txt` → **Piper Türkçe ses modelini indirme** (yoksa, ~60 MB, Hugging Face
`rhasspy/piper-voices`; atlamak için `-PiperYok`) → `npm install` → `.env` yoksa `.env.example`'dan kopyalama.
Sistem aracı **kurmaz**; eksikse ne yapmanız gerektiğini yazar.

### Elle kurulum

```powershell
# 1) Backend (Python sanal ortamı)
cd <ofis klasörü>\katlar\masal\backend
python -m venv .venv
.\.venv\Scripts\python -m pip install --upgrade pip
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python scripts\piper_ses_indir.py      # Piper Türkçe ses modeli (~60 MB, bir kez)

# 2) Frontend
cd ..\frontend
npm install

# 3) Ortam dosyası
cd ..
copy .env.example .env
```

---

## 3. Çalıştırma

### Kolay yol

Tam yol verdiğiniz için hangi klasörde olursanız olun çalışır:

```powershell
# backend :8000 + Vite paneli :5173 — gizli çalışır, terminal penceresi açılmaz
powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\baslat.ps1"
# tek port: paneli derler, her şey :8000'den
powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\baslat.ps1" -Tek
# durdurmak için
powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\durdur.ps1"
```

> `.\baslat.ps1` gibi göreli yol yalnızca önce `cd <ofis klasörü>\katlar\masal` yaptıysanız çalışır.

Ardından tarayıcıda **http://127.0.0.1:5173** (geliştirme) ya da **http://127.0.0.1:8000** (`-Tek`) adresi kendiliğinden açılır
(`-TarayiciAcma` ile açılmaz).

- **Pencere yok:** sunucular `conhost --headless` ile arka planda çalışır (bu makinede Windows Script Host kapalı olduğu için VBS kullanılmaz).
  Çıktılar `logs\backend.err.log` (uvicorn günlüğü), `logs\backend.out.log`, `logs\panel.out.log`, `logs\panel.err.log` dosyalarına yazılır; her başlatmada sıfırlanır.
- **Çıktıyı canlı görmek için** (hata ayıklarken): `baslat.ps1 -Gorunur` sunucuları eski usul iki pencerede açar.
- `baslat.ps1`'i iki kez çalıştırmak güvenlidir: açık olan sunucu yeniden başlatılmaz.
- `durdur.ps1` yalnızca bu projenin sunucularını kapatır (`logs\*.pid` + proje yolunu içeren dinleyiciler). Süren bir üretim varsa önce sorar; `-Zorla` ile sormaz.
  Yarıda kesilen iş bir sonraki açılışta `interrupted` olur ve panelden yeniden denenebilir.

### Elle

```powershell
# Terminal 1 — backend
cd <ofis klasörü>\katlar\masal\backend
.\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# Terminal 2 — panel (Vite, /api /ws /media isteklerini 8000'e yönlendirir)
cd <ofis klasörü>\katlar\masal\frontend
npm run dev
```

Tek porttan sunmak için: `cd frontend; npm run build` → backend `frontend/dist` klasörünü görürse paneli
`http://127.0.0.1:8000` adresinden kendisi sunar.

### Sunucusuz tek üretim (komut satırı)

```powershell
cd <ofis klasörü>\katlar\masal\backend
.\.venv\Scripts\python -m app.cli --topic "paylaşmak"
.\.venv\Scripts\python -m app.cli --topic "cesaret" --tts piper       # ses motorunu seç: piper | elevenlabs | babble | silence
.\.venv\Scripts\python -m app.cli --failure visual_timeout          # hata + yeniden deneme senaryosu
```

Çıktılar: `backend\data\outputs\<iş-id>\` (`final.mp4`, `thumb.jpg`, `subs.ass`, `images\`, `clips\`,
`audio\`, `publish\metadata.json`). Veritabanı: `backend\data\masal.db`.

> **Portlar:** backend 8000, panel 5173. 127.0.0.1:8765-8774 aralığı başka bir uygulamaya (AI Ekip paneli)
> ayrılmıştır; bu proje o aralığı kullanmaz.

---

## 4. Paneli kullanma

Panel, AI Ekip ofis panelinin düzenini izler (açık/koyu tema bilgisayarın ayarını izler):

- **Üst çubuk:** mod (MOCK / GERÇEK), yükleme durumu + `privacyStatus`, WebSocket bağlantısı ve çalışan ajan
  sayısı; **+ Yeni hikâye** ve onay bekleyen iş varsa yanıp sönen **🎞 Önizle & Onayla** düğmesi.
- **Ofis (piksel sahne):** Ekip üç departmanda oturur (*Yönetim & Yayın*, *Hikâye & Tasarım*, *Stüdyo*);
  ofiste dinlenme salonu, mutfak (kahve makinesi, otomat, sebil), **Üretim panosu** (aktif işin 7 adımı),
  sayaç televizyonu, saat, asansör ve seslendirme sürerken yanan **ON AIR** levhası vardır. Pencerelerdeki
  gökyüzü günün saatine göre değişir.
  - Çalışan ajan masasına yürür; ekranında kendi işi oynar (yazı, renk paleti, satır satır çizilen görsel,
    ses dalgası, zaman çizelgesi, QA işaretleri, yükleme çubuğu) ve balonunda o an ne yaptığını yazar
    (örn. *"Sahne 3/8 çiziliyor…"*). Bitince kısa bir *"✓ …"* balonu, hata verince kırmızı balon + titreme.
  - Bir adım bitince ajan sonraki istasyona dosyayı **yürüyerek götürür** (meşgulse JSON paketi uçar).
    Yeni istekte Yayıncı asansörden zarfı alıp Yönetmene getirir; onay bekleyen işte Yayıncının ekranında
    sarı **?** yanar; onayda konfeti, takılan işte panoda alarm çalar. Boştakiler gezer, sohbet eder.
  - **Bir ajana tıklayın** (ya da alttaki ekip çipine): log terminali o ajana süzülür ve sağ altta ajanın
    penceresi açılır (ayrıntılar + canlı logları). Aynı ajana yeniden tıklamak seçimi kaldırır.
    Penceredeki 🪪 düğmesi **karakter kartını** açar (portre, istatistik, görevi, motoru, son işleri).
  - Kahve makinesine tıklayınca boştakiler molaya çıkar; panoya tıklamak üretim panosuna götürür.
- **+ Yeni hikâye:** Konu girin (boşsa Yönetmen günün konusunu seçer). **🎨 Çizim motoru** ve **🎙 Ses motoru**
  iş başına seçilir (anahtarı/kurulumu olmayan seçenek kapalı görünür). “Senaryo testi” ile hata/yeniden
  deneme ve QA reddi akışlarını mock modda deneyebilirsiniz. İş sürerken basarsanız kuyruğa eklenir.
- **Canlı log terminali:** Ajanların logları ve her adımın JSON çıktısı (▸ JSON); ajana göre süzme
  çipleri, ⤓ takip ve temizle.
- **Üretim panosu:** İşler *Sırada / Üretiliyor / Onay bekliyor / Tamamlandı / Sorunlu* şeritlerinde
  (ya da ☰ Liste görünümünde) adım çubuğu, motorlar, süre ve maliyetle görünür; arama yapılabilir.
- **Önizleme ve onay çekmecesi:** QA'dan geçen video otomatik açılır (bir karta tıklayınca da açılır).
  Video + ölçüm bilgisi, *SEO & Taslak / QA / Hikaye / Görseller / Maliyet* sekmeleri ve seçenekler:
  - **✅ Onayla — taslak olarak sakla:** yalnızca yerel taslak; yükleme yok.
  - **⬆ Onayla ve YouTube'a yükle:** kutuyu işaretlemeden etkinleşmez. Mock modda yalnızca simülasyondur.
  - **↺ Revizyon iste:** hedef (hikaye / görsel promptları / görseller / ses / kurgu) + not → Yönetmen
    akışı o adımdan yeniden başlatır. Başarısız / yarıda kalan işler de buradan yeniden başlatılır.
- **Maliyet ve istatistik:** üretilen/onaylanan/yüklenen video sayısı, tahmini API maliyeti (mock modda
  “gerçek modda ne tutardı” tahmini; gerçek harcama $0) ve ajan bazında adım başarı oranları (satıra
  tıklayınca karakter kartı).

---

## 5. Ajanlar ve akış

```
START → Yönetmen ─→ Senarist → Görsel Yönetmen → Görsel Üretici → Ses → Kurgucu → QA ─→ Yayıncı → (onay bekler)
           ↑            │              │                 │           │        │      │
           └────────────┴──── hata ────┴─────────────────┴───────────┴────────┘      │
           └──────────────────────────── QA reddi (ilgili ajana geri) ───────────────┘
```

| # | Ajan | İstasyon | Görev (JSON çıktısı) |
|---|---|---|---|
| 1 | **Yönetmen** | Yönetmen Masası | Günün konusunu seçer, akışı yönlendirir; hata, QA reddi ve revizyonda ilgili adımı yeniden tetikler (`MAX_STEP_RETRIES`, `MAX_QA_ROUNDS`). |
| 2 | **Senarist** | Yazar Köşesi | 3-8 yaş, pozitif mesajlı, ≤130 kelime, 6-8 sahne, ilk cümlesi “hook” olan hikaye (`story`). |
| 3 | **Görsel Yönetmen** | Çizim Masası | Sabit **stil + karakter çapası** ve seed ile 9:16 sahne promptları (`art`). |
| 4 | **Görsel Üretici** | Render İstasyonu | Görselleri üretir (mock: Pillow ile kodla çizilmiş pastel sahneler; gerçek: fal.ai / OpenAI) ve her sahneye FFmpeg ile **Ken Burns** (zoom/pan) uygular (`visuals`). Aynı prompt için görseller önbellekten kullanılır. |
| 5 | **Ses** | Ses Kayıt Kabini | Türkçe seslendirme + **kelime zaman damgaları** (Piper: çevrimdışı, fonem hizalaması; ElevenLabs: *with-timestamps* veya Whisper; test: mırıltı/sessizlik) + telifsiz müzik (`audio`). |
| 6 | **Kurgucu** | Kurgu Stüdyosu | Klipler + ses + müzik (konuşmada otomatik kısılır) + orta-altta **kelime kelime renkli vurgulu karaoke altyazı** → 1080x1920 60 fps MP4 (`edit`). |
| 7 | **QA & Güvenlik** | Kalite Kontrol Alanı | Metin ve prompt güvenliği, kelime/sahne sınırları, çözünürlük, fps, ses kanalı, ses-video süre senkronu, dosya bütünlüğü. Sorun varsa Yönetmen aracılığıyla ilgili ajana geri gönderir (`qa`). |
| 8 | **Yayıncı** | Yayın Terminali | SEO başlık/açıklama/etiket + `privacyStatus=private`, `selfDeclaredMadeForKids=true` gövdesiyle **yerel taslak paketi** (`publish/metadata.json`). **Asla kendiliğinden yüklemez.** |

Akış kodu: `backend/app/graph.py`. API belgesi (Swagger): **http://127.0.0.1:8000/docs**. Grafiğin Mermaid
çıktısı: `GET /api/graph`.

---

## 5a. Yerel yapay zekâ motorları (ekran kartında, ücretsiz)

NVIDIA ekran kartı varsa (RTX 3060 12 GB ve üstü önerilir) çizim ve seslendirme API anahtarı olmadan,
ücretsiz ve ticari kullanıma açık lisanslı modellerle bu bilgisayarda yapılır:

| | Çizim: **FLUX.2 [klein] 4B** | Ses: **Chatterbox Multilingual** |
|---|---|---|
| Geliştirici / lisans | Black Forest Labs · **Apache 2.0** (ticari serbest) | Resemble AI · **MIT** (ticari serbest) |
| İndirme | ~15 GB | ~3 GB + Whisper large-v3-turbo ~1,6 GB |
| Ne yapar | Önce kahramanın **karakter referansını** çizer, sonra her sahneyi bu referansla çizer (karakter her sahnede aynı kalır) | Her cümleyi duygulu okur; **Whisper her cümleyi dinler**, senaryoya uymayan okumayı yeniden okutur; karaoke zamanları Whisper'dan |
| Ayarlar | `FLUX_STEPS`, `FLUX_WIDTH/HEIGHT`, `FLUX_REFERENCE` | `CHATTERBOX_EXAGGERATION`, `CHATTERBOX_CFG_WEIGHT`, `CHATTERBOX_REFERENCE` |

Kurulum (bir kez; ~20 GB indirir, ağır paketler ana backend'den ayrı sanal ortamlara kurulur):

```powershell
powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\yerel-modeller.ps1"
```

Sonra backend'i yeniden başlatın (`durdur.ps1` + `baslat.ps1`). Panelde **🎨 Çizim motoru** ve **🎙 Ses motoru**
listelerinde yerel motorlar etkinleşir ve varsayılan olur (`IMAGE_PROVIDER=auto`, `TTS_PROVIDER=auto`).

- **Süre (RTX 4070 Ti, 12 GB):** 8 sahne + karakter referansı ~2,5-3 dk (sahne başına ~15-20 sn),
  seslendirme ~1-1,5 dk; bir videonun tamamı ~5 dk. İlk çalıştırmada model diskten okunduğu için birkaç dakika daha sürer.
- **Ekran kartı belleği:** Windows masaüstü (dwm.exe) açık pencerelere göre birkaç GB VRAM tutar. FLUX işçisi boş
  belleğe bakar; 11 GB'tan azsa ağırlıkları 8 bit saklar (hesap bf16, kalite farkı çok küçük). Böylece model
  sistem RAM'ine taşmaz (taşarsa çizim 20-50 kat yavaşlar). Panelde hangi kipin kullanıldığı iş ayrıntısında görünür.
- Modeller `backend\models\hf`, sanal ortamlar `backend\engines\.venv-flux` / `.venv-ses` altındadır (git dışı).
- Backend motorları alt süreç olarak çalıştırır; adım bitince ekran kartı belleği tamamen boşalır.
  Motor günlükleri her işin klasöründe: `images\flux_motor.log`, `audio\ses_motor.log`.
- **Kendi anlatıcı sesiniz:** `assets\voices\anlatici.wav` (10-20 sn, temiz, hakkı size ait kayıt) koyarsanız
  Chatterbox masalı o sesle okur. Ayrıntı: `assets\voices\BENIOKU.txt`.

**API seçenekleri** (yine panelden iş başına): çizimde `fal` (fal.ai FLUX, `FAL_KEY`) ve `openai`
(gpt-image-1, `OPENAI_API_KEY`), seste `elevenlabs`. Anahtar girilmeden listede kapalı görünürler ve
**yalnızca açıkça seçildiklerinde** çağrılırlar (MOCK_MODE'dan bağımsız).

## 5b. Ses motorları (Chatterbox + ElevenLabs + Piper)

Ses motoru **her üretimde paneldeki “🎙 Ses motoru” listesinden** seçilir. Varsayılan `.env` → `TTS_PROVIDER=auto`
(kurulu olan ilki: Chatterbox → Piper → test mırıltısı). Chatterbox için yukarıdaki bölüme bakın; Piper ve
ElevenLabs karşılaştırması:

| | **Piper** (varsayılan) | **ElevenLabs** |
|---|---|---|
| Nerede çalışır | Bu bilgisayarda, internetsiz | ElevenLabs bulut API'si |
| Ücret | Ücretsiz | Hesabınızdan karakter başına kredi (panelde tahmini maliyet) |
| Kurulum | `piper-tts` (pip) + model `tr_TR-dfki-medium` (~60 MB, bir kez) | `.env` → `ELEVENLABS_API_KEY` + `ELEVENLABS_VOICE_ID` |
| Kelime zaman damgası | Gerçek: model fonem hizalaması | Gerçek: ElevenLabs hizalaması (ya da `TIMESTAMP_PROVIDER=whisper`) |
| Ses | Tek Türkçe erkek sesi, anlaşılır | Çok daha doğal; ses kütüphanesinden kadın/erkek seçilebilir |
| **Lisans** | **CC BY-NC-SA 4.0 — ticari olmayan kullanım** | ElevenLabs planınızın şartları (ücretli planlar ticari kullanıma izin verir) |
| MOCK_MODE | Mock modda da çalışır | Mock modda da çalışır, ama **yalnızca açıkça seçildiğinde** çağrılır |

> ⚠️ **Lisans uyarısı:** Hugging Face'teki tek Türkçe Piper modeli (`tr_TR-dfki-medium`), *CC BY-NC-SA 4.0*
> lisanslı DFKI veri setiyle eğitilmiştir (model kartı: `backend/models/piper/tr_TR-dfki-medium.MODEL_CARD.txt`).
> Bu, **para kazanılan** bir YouTube kanalında kullanımın lisansla çelişebileceği anlamına gelir. Piper'ı
> deneme, taslak ve ticari olmayan kullanım için kullanın; para kazanılan yayınlar için ElevenLabs'i seçin.

**ElevenLabs'i açmak için:**
1. elevenlabs.io → *Profile → API Keys* ile bir anahtar oluşturun.
2. *Voices* bölümünden sıcak, masalsı bir ses seçin → *Copy voice ID*.
3. `.env` dosyasına `ELEVENLABS_API_KEY=...` ve `ELEVENLABS_VOICE_ID=...` yazın; `ELEVENLABS_MODEL=eleven_multilingual_v2` Türkçeyi destekler.
4. Backend'i yeniden başlatın. Paneldeki ses listesinde ElevenLabs etkinleşir; varsayılan yapmak için `TTS_PROVIDER=elevenlabs`.

**Piper ayarları:** `PIPER_LENGTH_SCALE` (1.0 normal; 1.1-1.2 çocuklar için daha yavaş), `PIPER_VOICE`, `PIPER_MODEL_DIR`.
Model eksikse panel Piper seçeneğini kapalı gösterir; `backend\.venv\Scripts\python backend\scripts\piper_ses_indir.py` ile indirin.

---

## 6. `.env` alanları

Tüm alanlar `.env.example` içinde açıklamalıdır. Özet:

| Alan | Varsayılan | Açıklama |
|---|---|---|
| `MOCK_MODE` | `true` | `false` olunca gerçek API'ler kullanılır (ücretli). |
| `MOCK_STEP_DELAY` | `1.5` | Mock modda animasyonları izlemek için bekleme çarpanı (`0` = hızlı). |
| `TTS_PROVIDER` | `auto` | Varsayılan ses motoru: `auto` / `chatterbox` / `elevenlabs` / `piper` / `babble` / `silence` (panelden iş başına değiştirilir). |
| `CHATTERBOX_EXAGGERATION` / `CHATTERBOX_CFG_WEIGHT` / `CHATTERBOX_TEMPERATURE` | `0.55` / `0.5` / `0.8` | Duygu yoğunluğu, tempo/vurgu, çeşitlilik. |
| `CHATTERBOX_REFERENCE` | `assets/voices/anlatici.wav` | İsteğe bağlı anlatıcı ses örneği. |
| `PIPER_VOICE` / `PIPER_MODEL_DIR` / `PIPER_LENGTH_SCALE` | `tr_TR-dfki-medium` / `backend/models/piper` / `1.12` | Piper modeli ve konuşma hızı. |
| `MOCK_VOICE` | `babble` | Piper modeli yoksa kullanılacak test sesi: `babble` ya da `silence`. |
| `BACKEND_HOST` / `BACKEND_PORT` | `127.0.0.1` / `8000` | Sunucu adresi. |
| `MUSIC_DIR` | `assets/music` | **Gerçek modda** kendi telifsiz müzik dosyalarınızın klasörü. |
| `LLM_PROVIDER` / `LLM_MODEL` | `anthropic` / boş | `anthropic` (varsayılan model `claude-sonnet-5-5`) ya da `openai`. |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` | boş | LLM ve (OpenAI ise) görsel/Whisper anahtarları. |
| `IMAGE_PROVIDER` | `auto` | Varsayılan çizim motoru: `auto` (yerel FLUX varsa o) / `flux_local` / `fal` (`FAL_KEY`, `FAL_MODEL`) / `openai` (`OPENAI_IMAGE_MODEL`, `OPENAI_IMAGE_QUALITY`) / `placeholder`. |
| `FLUX_STEPS` / `FLUX_WIDTH` / `FLUX_HEIGHT` / `FLUX_REFERENCE` | `4` / `1088` / `1920` / `true` | Yerel FLUX adım sayısı, çözünürlük ve karakter referansı. |
| `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` | boş | Sıcak, masalsı bir ses seçip kimliğini girin. |
| `TIMESTAMP_PROVIDER` | `elevenlabs` | `elevenlabs` (hizalama) ya da `whisper`. |
| `MUSIC_VOLUME` | `0.22` | Müzik seviyesi. |
| `RENDER_FPS` / `RENDER_PRESET` / `RENDER_CRF` | `60` / `veryfast` / `20` | Çıktı ayarları. |
| `SUBTITLE_FONT` | `Comic Sans MS` | Altyazı yazı tipi (sistemde kurulu olmalı). |
| `FFMPEG_PATH` / `FFPROBE_PATH` | boş | Elle FFmpeg yolu. |
| `YOUTUBE_UPLOAD_ENABLED` | `false` | `true` olmadan onaylasanız bile yükleme yapılmaz. |
| `YOUTUBE_PRIVACY_STATUS` | `private` | `private` / `unlisted` / `public`. |
| `YOUTUBE_CATEGORY_ID` | `1` | 1 Film & Animation, 24 Entertainment, 27 Education. |
| `YOUTUBE_CLIENT_SECRETS` / `YOUTUBE_TOKEN_FILE` | `secrets/...` | OAuth dosyaları (git'e eklenmez). |
| `MAX_STEP_RETRIES` / `MAX_QA_ROUNDS` | `2` / `2` | Yönetmenin yeniden deneme sınırları. |
| `PRICE_*` | — | Tahmini maliyet tablosu. |

---

## 7. Gerçek moda geçiş

1. Ek paketleri kurun (YouTube kütüphaneleri):
   ```powershell
   cd backend
   .\.venv\Scripts\python -m pip install -r requirements-real.txt
   ```
2. `.env` içine kendi anahtarlarınızı girin: `ANTHROPIC_API_KEY` (veya `LLM_PROVIDER=openai` + `OPENAI_API_KEY`),
   `FAL_KEY` (veya `IMAGE_PROVIDER=openai`). Ses için Piper ücretsizdir; ElevenLabs isterseniz
   `ELEVENLABS_API_KEY` + `ELEVENLABS_VOICE_ID` girin (bkz. [Ses motorları](#5b-ses-motorları-piper--elevenlabs)).
   `TIMESTAMP_PROVIDER=whisper` seçerseniz `OPENAI_API_KEY` de gerekir.
3. (İsteğe bağlı) `assets/music/` klasörüne **kullanım hakkına sahip olduğunuz** telifsiz müzikleri koyun.
   Klasör boşsa sentetik müzik kutusu melodisi kullanılır. Hiçbir müzik otomatik indirilmez.
4. `.env` → `MOCK_MODE=false`, backend'i yeniden başlatın. Üst çubukta **GERÇEK MOD** rozeti görünür.
5. İlk denemeleri kısa tutun ve panelde tahmini maliyeti izleyin.

LLM model adlarını hesabınızda erişilebilir olanlara göre `LLM_MODEL` ile ayarlayın.

---

## 8. YouTube yükleme güvenliği

Publisher (Yayıncı) **hiçbir koşulda kendiliğinden yükleme yapmaz.** LangGraph akışındaki Yayıncı düğümü
yalnızca SEO metnini ve `publish/metadata.json` taslak paketini üretir ve iş **“Onay bekliyor”** durumunda durur.

Gerçek yükleme için hepsi birden gereklidir:

1. `MOCK_MODE=false`
2. `YOUTUBE_UPLOAD_ENABLED=true`
3. OAuth jetonu: Google Cloud Console'da *YouTube Data API v3*'ü etkinleştirip bir **Masaüstü OAuth istemcisi**
   oluşturun, JSON'u `secrets/client_secret.json` olarak kaydedin ve yetkilendirmeyi **kendiniz** çalıştırın:
   ```powershell
   cd backend
   .\.venv\Scripts\python scripts\youtube_yetkilendir.py
   ```
   Sunucu OAuth akışını hiçbir zaman kendisi başlatmaz.
4. Paneldeki önizleme çekmecesinde onay kutusunu işaretleyip **“⬆ Onayla ve YouTube'a yükle”**ye basmanız.

Yükleme `privacyStatus=private` (varsayılan) ve `selfDeclaredMadeForKids=true` ile yapılır; videoyu
YouTube Studio'dan inceleyip kendiniz yayına alırsınız. Mock modda “yükle” düğmesi yalnızca simülasyon yapar.

---

## 9. Proje ağacı

```
masal-shorts/
├─ .env.example            # tüm ayarlar (kopyalayıp .env yapın)
├─ README.md
├─ kurulum.ps1             # venv + pip + npm + .env (UTF-8 BOM)
├─ baslat.ps1              # backend + panel başlatıcı, varsayılan gizli (UTF-8 BOM)
├─ durdur.ps1              # sunucuları kapatır (UTF-8 BOM)
├─ yerel-modeller.ps1      # FLUX.2 klein + Chatterbox kurulumu (UTF-8 BOM)
├─ assets/music/           # gerçek mod için kendi telifsiz müzikleriniz
├─ assets/voices/          # isteğe bağlı anlatıcı ses örneği (anlatici.wav)
├─ backend/
│  ├─ requirements.txt / requirements-real.txt
│  ├─ app/
│  │  ├─ main.py           # FastAPI: REST + /ws WebSocket + /media + derlenmiş panel
│  │  ├─ graph.py          # LangGraph durum makinesi (8 düğüm)
│  │  ├─ jobs.py           # iş kuyruğu, onay / revizyon / yükleme akışı
│  │  ├─ events.py         # WebSocket olay yolu (ajan durumu, log, iş, istatistik)
│  │  ├─ db.py             # SQLite (işler, adım çalıştırmaları, maliyetler)
│  │  ├─ config.py, state.py, pricing.py, mock_data.py, cli.py
│  │  ├─ agents/           # director, storyteller, art_director, visual_generator,
│  │  │                    # audio_voice, editor, qa_safety, publisher, base, registry
│  │  └─ services/         # ffmpeg, video, images, audio, piper_tts, chatterbox_tts,
│  │                    # local_engines, llm, safety, youtube
│  ├─ engines/             # yerel motor işçileri: flux_worker.py, ses_worker.py (+ .venv-flux, .venv-ses)
│  ├─ models/piper/        # indirilen Piper ses modeli (git'e eklenmez)
│  ├─ models/hf/           # FLUX / Chatterbox / Whisper modelleri (git'e eklenmez)
│  ├─ scripts/youtube_yetkilendir.py   # yalnızca elle çalıştırılır
│  ├─ scripts/piper_ses_indir.py       # Piper Türkçe ses modelini indirir
│  └─ tests/test_pipeline.py
└─ frontend/
   ├─ package.json, vite.config.js, index.html
   └─ src/
      ├─ App.jsx, useMasal.js, sabitler.js, styles.css
      ├─ components/       # OfisSahnesi, LogTerminal, UretimPanosu, OnizlemeCekmecesi,
      │                    # YeniHikaye, Karakter (karakter kartı + ajan penceresi), Istatistik
      └─ office/           # pikselOfis.js — AI Ekip PikselOfis motorundan uyarlanan Canvas sahnesi
```

Piksel karakterler, mobilyalar ve yer tutucu sahne görselleri tamamen kod içinde çizilir; dışarıdan hiçbir
görsel, yazı tipi ya da müzik varlığı kullanılmaz.

---

## 10. Test ve sorun giderme

```powershell
cd backend
.\.venv\Scripts\python -m pytest -q
```

Test, mock hattı uçtan uca çalıştırır ve çıktının 1080x1920, 60 fps, sesli ve 40-60 sn olduğunu doğrular;
Piper modeli varsa kelime hizalamasının gerçek olduğunu da sınar.

| Belirti | Çözüm |
|---|---|
| `FFmpeg bulunamadı` | `pip install -r requirements.txt` (imageio-ffmpeg) ya da sistem FFmpeg'i kurup `FFMPEG_PATH` verin. |
| Ses mırıltı gibi, konuşma yok | Piper modeli eksik: `backend\.venv\Scripts\python backend\scripts\piper_ses_indir.py`, sonra panelde “Piper”ı seçin. |
| ElevenLabs seçeneği kapalı | `.env`'de `ELEVENLABS_API_KEY` ve `ELEVENLABS_VOICE_ID` dolu olmalı; backend'i yeniden başlatın. |
| Altyazı yazı tipi farklı | `SUBTITLE_FONT` sistemde kurulu bir yazı tipi olmalı (örn. `Arial Black`). |
| Panel “Bağlantı bekleniyor” | Backend 8000'de çalışıyor mu? `http://127.0.0.1:8000/api/health` |
| 8000/5173 dolu | `.env` → `BACKEND_PORT`, Vite için `MASAL_BACKEND` ortam değişkeni ve `vite.config.js` portu. |
| Yarıda kalan işler | Sunucu yeniden başlarsa “Yarıda kaldı” olarak işaretlenir; önizleme çekmecesinden revizyon ile yeniden başlatabilirsiniz. |
