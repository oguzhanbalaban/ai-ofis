# AI Ekip Ofisi: kendi kodumuz üzerinde çalışma rehberi

Bu depo **AI Ekip Ofisi'nin kendi kodunun aynasıdır** (ayna: `{AYNA}`, canlı ofis: `{CANLI}`). Şu an bu depoda bir görev dalında
çalışıyorsun. Canlı ofise doğrudan dokunma: değişikliğin testlerden, QA'dan ve Code Reviewer onayından geçince **motor kendisi**
aynanın main'ine birleştirir, canlıya kopyalar, doğrular; doğrulama geçmezse geri alır. Senin işin: küçük, geriye uyumlu, testli değişiklik.

## Yapı
- Şirket binası: `katlar.json` (ana kat = AI Ekip Ofisi; diğer katlar `katlar\<id>`: Data and Analytics, Creativity; Creative Studio
  ayrı bir uygulama, kendi deposu). Kod tek; her kat kendi verisiyle (kadro, ayarlar, görevler) kendi döngüsünde çalışır.
- Motor (Windows PowerShell 5.1): `ortak.ps1` (dosya / JSON, kat çözümü `AIEKIP_KAT` → `$Kok` veri, `$KodKok` kod; Ajan-Cagir, bildirim),
  `ekip.ps1` (aşamalar, ana döngü), `planlama.ps1` (Product Manager, Explorer, QA), `yonlendirme.ps1` (İş ver), `uzman.ps1`,
  `altyapi.ps1`, `yardim.ps1`, `cozucu.ps1` (Incident Manager), `komut.ps1` / `paralel.ps1`, `yonetim.ps1` (CTO),
  `danisman.ps1`, `iletisim.ps1` (katlar arası Comms), `yaratici.ps1` / `kopru.ps1` (fikir hattı), `kendini.ps1` (bu akış: ayna ve canlıya alma).
- Panel: `ofis\ofis.ps1` (127.0.0.1 TcpListener; istek başına kat seçimi), `ofis\bina.html` (kat seçici kabuk), `ofis\panel.html`
  (kat paneli; ilk `<script>` PikselOfis sahne motoru IIFE, ikinci betik paneli bağlar), `ofis\panel-creativity.html`, `ofis\sohbet.ps1`.
- İstemler `istemler\*.md` (şablon değişkenleri `{GOREV}` gibi), rol talimatları `istemler\kadro\`. Bir katın aynı adlı dosyası
  `katlar\<id>\istemler\` altındaysa o kullanılır.
- Ayar dosyaları (`ayarlar.json`, `kadro.json`, `projeler.json`, katlarınkiler de) aynada testler için vardır ama **canlıya alınmaz**
  (çalışırken değişirler). Yeni bir ayar gerekiyorsa kod, ayar yokken makul bir varsayılanla çalışmalı (`ayarlar.json > blok` okunurken
  eksikse varsayılan). Canlıda ayar değişikliği gerekiyorsa raporunda açıkça yaz.

## Kurallar (bunlar canlıyı bozar)
- `.ps1` dosyaları **UTF-8 BOM** ile kaydedilmeli (Türkçe karakterler); Windows PowerShell 5.1 sözdizimi (`?.`, `??`, `&&` yok).
- PowerShell değişkenleri büyük / küçük harf duyarsızdır: fonksiyonda `$kok` yazmak `$Kok`'u gölgeler. ortak.ps1'i dot-source eden
  bir betikte `[string]$Kat` / `$Kok` adlı parametre kullanma. Fonksiyona `H` adı verme.
- Ana döngü kök klasördeki bir `.ps1` değişince kendini yeniden yükler: yükleme sırasında hata veren kod ofisi durdurur.
  Her yeni modül `ekip.ps1`'de dot-source edilir; üst düzeyde yalnızca fonksiyon ve `$script:` değişken tanımı.
- Görev / durum dosyalarına (`gorevler\`, `durum\`, `calisma\`, `katlar\*\gorevler` ...) ve canlı klasöre yazma; parola / anahtar yazma.
- Panel HTML'de satır içi betikler nonce'lu CSP ile çalışır; dış kaynak ekleme. İlk betikteki (PikselOfis) değişkenler ikinci betikten
  görünmez; `PikselOfis.*` üzerinden eriş.
- Değişikliği küçük tut; davranışı değişen yer için testine bak ya da test ekle (`testler\*.test.ps1`, çevrimdışı, sahte ajanlı kum havuzu).

## Testler (kontrol aşamasında otomatik koşar; sen de koşabilirsin)
    powershell -NoProfile -ExecutionPolicy Bypass -File testler\ofis-duman.test.ps1     (ayrıştırma, BOM, JSON, sayfa betikleri, kat yükleme)
    powershell -NoProfile -ExecutionPolicy Bypass -File testler\katlar.test.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File testler\planlama-katmani.test.ps1
Testler kendi kum havuzlarını `%TEMP%` altında kurar; canlı ofise dokunmaz.

## Canlıya alma
Onay kapısından sonra aşama `canliya_al`: dal aynanın main'ine birleşir, kapsamdaki dosyalar (kök `.ps1`, `ofis\`, `istemler\`,
`testler\`, `araclar\`, `katlar.json`, `katlar\<id>\istemler|bilgi|araclar`) yedeklenip canlıya kopyalanır; betikler ayrıştırılır,
her kat ayrı süreçte yüklenir, panel değiştiyse yeniden başlatılıp sayfa ve API denetlenir. Geçmezse canlı yedekten geri yüklenir.
Canlıya almadan sonraki saatte döngü üst üste hata verirse son canlıya alma kendiliğinden geri alınır.
