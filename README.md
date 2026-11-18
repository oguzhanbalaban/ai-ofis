# AI Ofis

Windows için kişisel yapay zeka ofisi kurulum paketi. Verilen işi **Engineering Manager** okuyup Full-Stack Developer, Code Reviewer, altyapı ve uzman rollerine dağıtır; çalışanlar iş sırasında Engineering Manager üzerinden birbirinden **yardım** ister, uygulamaları **QA Engineer** çalıştırıp test eder, takılan işleri **Incident Manager** inceler. İnceleme, raporlama, token/bağlam kullanım panosu ve tarayıcıdan yönetim paneli sunar. Claude, Codex ve Gemini araçları birlikte veya ayrı kullanılabilir; varsayılan rol zincirleri Claude öncelikli, Codex yedektir (sihirbaz seçtiğiniz araçlara göre uyarlar).

## Gereksinimler

- Windows 10/11 ve Windows PowerShell 5.1 veya üstü.
- Claude kullanacaksanız güncel Claude CLI (Opus 5.5 ve Fable 5.2 için 2.1.326 ya da sonrası; `claude update`). Eski sürüm bir modeli çalıştıramazsa o model 6 saat atlanır ve zincirdeki sonraki model denenir.
- Git for Windows ve commit oluşturmak için ayarlanmış Git kullanıcı adı/e-postası.
- En az bir kurulu AI aracı (Claude CLI, Codex uygulaması/CLI veya Gemini CLI), açık oturum ve yeterli model kotası. Abonelikler pakete dahil değildir. Geliştirme ve denetim için farklı modeller seçin; tek araçla kullanımda iki erişilebilir model gerekir.
- Paket doğrudan Node.js gerektirmez; seçtiğiniz AI aracının kendi kurulum gereksinimlerini ayrıca tamamlayın.
- İsteğe bağlı: e-posta okuma için Python 3, VM envanteri için VMware, telefon erişimi için Tailscale.

## Kurulum

1. Git ve kullanacağınız AI aracını kurup hesabınıza giriş yapın. Sihirbaz bunları indirmez ve model erişimini çevrimiçi doğrulamaz.
2. PowerShell'de depoyu kalıcı bir klasöre indirin ve sihirbazı başlatın:

   ```powershell
   git clone https://github.com/oguzhanbalaban/ai-ofis.git
   cd ai-ofis
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
   .\kur-ofis.ps1
   ```

   Size `ai-ofis.zip` iletildiyse veya GitHub'dan **Code → Download ZIP** ile indirdiyseniz: ZIP'i kalıcı bir klasöre çıkartın, PowerShell'i o klasörde açın ve son iki satırı çalıştırın.

   Windows varsayılan olarak `.ps1` betiklerini çalıştırmaz ("running scripts is disabled on this system" hatası). `Set-ExecutionPolicy -Scope Process` satırı izni **yalnızca o PowerShell penceresi için** açar; sistem ayarını değiştirmez. Yeni bir PowerShell penceresinde betik çalıştırmadan önce bu satırı yeniden yazın. Ofisin otomatik başlatma görevi ve masaüstü kısayolu bu izni kendisi verir.

3. Sihirbazda araç/model, bildirim ve ilk proje seçimlerini tamamlayın. VM ve telefon seçenekleri isteğe bağlıdır; başlangıçta kapalı bırakabilirsiniz. Temel kurulum Engineering Manager oturumu gerektirmez.
4. Aynı pencerede durumu kontrol edin, sonra paneli açın:

   ```powershell
   .\durum.ps1
   .\ofis\ofis.ps1 -Ac
   ```

   Panel tarayıcıda açılır. Bu PowerShell penceresi panelin sunucusudur: panel kullanıldığı sürece açık kalmalıdır (kapatmak için Ctrl+C). Paneli pencere olmadan açmak için sihirbazın oluşturduğu **AI Ekip Ofisi** masaüstü kısayolunu kullanın.

Panel varsayılan olarak `http://127.0.0.1:8765/` adresini kullanır. Port doluysa kullanılan adres `ofis/sunucu.json` dosyasındadır.

## İlk görev

En kolayı türü seçmeden iş vermektir (paneldeki **+ İş ver** de bunu kullanır):

```powershell
.\is-ver.ps1 -Baslik "İlk görev" -Aciklama "İstenen değişiklik" -Ipucu C:\Projeler\Uygulama -Kabul "Testler geçer"
.\baslat.ps1 -Konsol
```

Türü bilerek vermek isterseniz `gorev-ekle.ps1 -Proje <git klasörü>` (yazılım), `talep-ekle.ps1` (sunucu/kurulum) ve `uzman-ekle.ps1` (uzman işi) kullanılabilir.

Konsol kuyruğu sürekli işler (durdurmak için Ctrl+C). `durum.ps1 -Duraklat` ile duraklatabilir, `durum.ps1 -Surdur` ile sürdürebilirsiniz. HTML raporu `raporlar/son-rapor.html` dosyasına yazılır. Oturum açılışında otomatik çalıştırmak için `kur.ps1`, otomatik görevi kaldırmak için `kaldir.ps1` kullanılır. Aynı Windows oturumunda tek ofis kurulumu çalıştırın; yeniden kurulumdan önce döngüyü kapatın.

## İş ver: Engineering Manager yönlendirir

`is-ver.ps1` ve panelde **+ İş ver** tür sormaz; iş önce Product Manager'a (gereksinim analizi), sonra Engineering Manager'a gider (rol anahtarı `lider` geriye uyumluluk için durur, her yerde Engineering Manager adıyla görünür). Engineering Manager işi ve gereksinimleri okur ve `yonlendirme.ps1` ile karar verir: **YAZILIM** (kayıtlı bir proje ya da `ayarlar.json > gorev.yeni_proje_kok` altında, boşsa `%USERPROFILE%\ai-ekip-projeler` içinde yeni bir git deposu), **ALTYAPI** (System Administrator + Network Engineer), **UZMAN** (kadrodan bir çalışan), **ISE_ALIM** (İK önce işe alır) ya da **SORU_VAR**. Gerekçe `gorev.md`'ye eklenir. İsteğe bağlı ipuçları: `-Ipucu` (proje adı ya da klasör) ve `-Rol` (önerilen çalışan).

## Ekibin katmanları: planlama, geliştirme, doğrulama

Yazılım işleri katmanlı yürür (`planlama.ps1`; ayarlar `ayarlar.json > planlama`):

1. **Analiz** (Product Manager, `urun`): belirsiz talebi netleştirir ve `gorevler\<no>\gereksinimler.md` yazar: talep özeti, kullanıcı hikâyeleri, test edilebilir **kabul ölçütleri (Definition of Done)**, kapsam dışı, varsayımlar. Yalnızca sizin verebileceğiniz bir bilgi eksikse soru sorar (iş başına en fazla `urun_soru_hakki`); yanıtınızla yeniden analiz eder. Gereksinimler sonraki her istemde görev metnine eklenir.
2. **Keşif** (Codebase Explorer, `kasif`): görevin dalını salt okunur tarar ve `kesif.md` yazar: teknoloji yığını, klasör yapısı, etkilenecek dosyalar, önyüz / arka uç ayrımı, testler ve test komutu, güvenlik açısından hassas alanlar. Boş (yeni) depoda atlanır.
3. **Planlama** (Engineering Manager): gereksinimleri ve keşfi birleştirip planı yazar ve işi dağıtır: `IS: backend | …` ve `IS: frontend | …` satırlarıyla Backend / Frontend Developer'a böler (satır yoksa Full-Stack Developer işin tamamını yapar), `QA_TESTI: evet/hayır`, `EK_INCELEME: guvenlik, mimar`, `DOGRULAMA_EKLE: <test komutu>` (güvenli komut süzgeciyle).
4. **Kodlama**: parçalar planlanan sırayla, aynı dalda, her adımda bir parça yapılır; sonraki parça öncekilerin özetini ve sözleşmesini (API uçları, veri biçimi) görür.
5. **Doğrulama**: otomatik kontrol → **QA Engineer** birim / entegrasyon testi yazar ve tüm testleri koşturur, kullanıcıya dönük işte uygulamayı dener (bildirdiği test dosyaları dala eklenir, diğer değişiklikleri geri alınır) → **Code Reviewer** kodu, güvenliği ve QA raporunu inceler → Engineering Manager kabul ölçütlerine göre karar verir. Hata bulan `DUZELTECEK: frontend` yazarsa yeni turda yalnızca o geliştirici çalışır.

**Onay kapısı:** commit'ten önce bu turda Code Reviewer'ın (QA testi yapıldıysa QA Engineer'ın ve ek incelemelerin de) onayı aranır; yoksa iş incelemeye döner. Panoda işi kendiniz Tamamlandı'ya taşırsanız commit edilir ve mesaja not düşülür. Ekip push / merge yapmaz. Katmanlar `ayarlar.yerel.json > planlama` ile kapatılabilir (`analiz`, `kesif`, `qa_testi`, `onay_kapisi`); bir rol kadroda ya da model zincirinde yoksa o katman kendiliğinden atlanır.

## Şirket binası: katlar ve katlar arası iletişim (Comms)

Ofis çok katlı bir şirkettir. Panel açılınca solda **Kat** seçici (asansör) görünür; her kat ayrı bir ofistir, kendi kadrosu,
ayarları, görev panosu ve döngüsüyle çalışır, kod ortaktır:

| Kat | Ofis | Ne yapar |
| --- | --- | --- |
| 3 | **AI Ekip Ofisi** (ana kat, genel merkez) | Yazılım, altyapı, tasarım, test; verisi kök klasörde |
| 2 | **Data and Analytics Office** (`katlar\data-analytics`) | SAP Data Services ETL, BusinessObjects UNX universe ve Web Intelligence raporları; SAP ortamınızı `bilgi\sap-ortami.md` ve `altyapi.makineler` içine yazın |
| 1 | **Innovation Lab** (`katlar\innovation-lab`) | Fikir hattı: fikir → eleştiri → POC planı → maliyet → karar; onaylanan POC ana kata gider, sonuç puanlanır (stüdyo paneli) |
| Z | **Creative Studio** (`katlar\creative-studio`) | Uygulama katı: çocuk masalı YouTube Shorts üretim hattı (kendi sunucusu ve paneli; ajanlarla sohbet, ofisi aç / kapat / duraklat, iş iptali ve sürükle-bırak pano, bildirimler, günlük özet, </> kod çekmecesi). Kurulumu `katlar\creative-studio\README.md`; yayın / yükleme yalnızca sizin onayınızla |

- **Katlar arası iletişimi Communications Coordinator'lar (Comms) yürütür.** Bir iş başka bir katın uzmanlığındaysa katın yöneticisi
  `KARAR: KAT` verir (ya da bir çalışan başka kattan yardım ister); Comms isteği o katın ekibinin tek başına anlayacağı bir brife çevirir,
  hedef katta görev açar (uygulama katında API'sine iş verir), işi izler ve sonuç gelince kendi ekibine rapor yazar. Görev o sırada
  "Başka katta yapılıyor" bekler. Yazışmalar `sirket\yazismalar\` altında, panelde sol altta ve görevin "Kat yazışması" sekmesindedir.
- Bir iş geldiği kata geri gönderilemez; zincir en fazla iki kat derinliktir (`ayarlar.json > kat_iletisimi`).
- Alt katların ayarları yalnız kata özgü blokları taşır (roller, kat kuralları); araç yolları, bildirim, döngü ve model kataloğu ana kattan
  miras alınır. Kurulum sihirbazı katların rol zincirlerini de seçtiğiniz yapay zekaya uyarlar (`katlar\<id>\*.yerel.json`).
- Katlar kapalı başlar: panelde katı seçip **Katı aç** deyin; döngüsü başlar (ana katın bekçisi açık katları ayakta tutar). Kapatınca
  çalışan adım bitince döngü çıkar. **Katı kapat** her katta mesai kapanışıdır (ekip eve gider, kat görünür kalır; Creative Studio'da
  sunucular açık kalır). Ayrı **⏹ Durdur** tam durdurmadır: Creative Studio'nun sunucuları kapanır, ekip katının döngüsü süren
  adımıyla hemen durur; **▶ Başlat** geri açar. Ana kat yalnız kendi panelinden kapatılır. Yeni kat eklemek için `katlar.json`'a kat ve `katlar\<id>\` altına `kadro.json` / `ayarlar.json` koyun.

## Kendi kendini geliştirme: ofis kendi kodu üzerinde çalışır

Ekip ofisin kendisini (panel, ajanlar, akış, istemler, katlar, testler) geliştirebilir. Yol **ayna + denetimli canlıya alma**:

- Ofisin kodu, ofis klasörünün yanında bir **ayna git deposunda** tutulur (`<ofis klasörü>-kaynak`; ilk çalışmada kendiliğinden oluşur ve
  `projeler.json`'a `ai-ekip-ofis` adıyla kaydolur). Ofisle ilgili işleri Engineering Manager bu projeye verir; ekip olağan yazılım akışıyla
  çalışır (görev dalı, çalışma ağacı, testler, QA, Code Reviewer, onay kapısı). **Canlı ofise ajan dokunmaz.** Ajanların rehberi aynadaki
  `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` (kaynağı `istemler\ofis-gelistirme.md`).
- İş başlamadan ayna canlıyla eşitlenir; commit'ten sonra aşama **Canlıya alınıyor**: dal aynaya birleşir, değişen dosyalar yedeklenip
  canlıya kopyalanır (ayar JSON'ları hariç: onlar çalışırken değişir), bütün betikler ayrıştırılır, her kat ayrı süreçte yüklenir, panel
  değiştiyse yeniden başlatılıp sayfası ve API'si denetlenir. **Geçmezse canlı yedekten geri yüklenir**, görev takılır.
- Canlıya almadan sonraki bir saatte döngü üst üste hata verirse son canlıya alma **kendiliğinden geri alınır**. Görev ayrıntısındaki
  "Canlıya alma" sekmesinden ya da `.\durum.ps1 -GeriAl <no>` ile son canlıya almayı geri alabilirsiniz.
- `ayarlar.json > kendini_gelistirme`: `etkin`, `otomatik` (false: değişiklik onayınızı bekler, panelden "Canlıya al"), `kaynak_deposu`,
  `dogrulama` (kontrol aşamasında koşan testler; varsayılan duman + katlar + planlama + yardımlaşma testleri).

## Outsource Consultant: tek parça işler kendi yapay zekanıza

Paralel ekip çalışması gerektirmeyen, tek bağlam penceresinde baştan sona çözülebilecek işler iç ekibe dağıtılmaz (`danisman.ps1`, ayarlar `ayarlar.json > danisman`). "İş ver" ile gelen işi Product Manager analiz eder ve `ATAMA: danisman | ekip` kararı verir; danışmansa işi `## Danışman brifi` bölümünde tek, net bir isteme çevirir (panelde **Brif** sekmesi). İşi doğrudan danışmana verirseniz (karakter kartında **Bu çalışana iş ver**, sohbetteki iş önerisi ya da `is-ver.ps1 -Rol danisman`) yönlendirme zorunludur.

**Danışman sizin seçtiğiniz yapay zekadır.** Kurulumda seçtiğiniz araç danışman olur (birden çok araç seçerseniz sihirbaz hangisinin danışman olacağını sorar; sonra panelde karakter kartından değiştirebilirsiniz). Danışman o yapay zekanın terminal ajanı olarak başsız (headless) çalışır: Claude Code (`claude -p`), Codex CLI (`codex exec`) ya da Gemini CLI (`gemini -p`).

**Masa pakette gelir:** `danisman\` klasöründe çalışır ve kendi kural dosyasını yükler: Claude Code `CLAUDE.md`, Codex `AGENTS.md`, Gemini `GEMINI.md`. Ana dosya `CLAUDE.md`'dir (rol, öncelikler, çalışma alanı, terminalden diğer araç ve modellerin kullanımı, yasaklar); diğer ikisi her çalışmadan önce ondan kopyalanır, kuralları değiştirmek için yalnızca `CLAUDE.md`'yi düzenleyin. Danışmanın kalıcı notları `danisman\notlar\` (Git'e eklenmez). Bilgisayarınızda kurulu yapay zeka CLI'larının yolları her istemin ARAÇLAR bölümünde verilir; danışman gerektiğinde onları ikinci görüş için çağırabilir. İşin klasörü ayrıca açılır: proje bir git deposuysa görev dalı (`ekip/<no>`), değilse `calisma\<no>` (teslimler `cikti\`).

**İzinler (hiçbiri arka planda onay bekleyip kilitlenmez):** Claude Code: `--permission-mode dontAsk` + `--allowedTools` (`izinli_araclar`) + `--disallowedTools` (`yasak_araclar`: `git push`, remote, `vmrun`, güvenlik duvarı / Defender / yürütme ilkesi, kapatma…) + `--add-dir`. Codex: `-s workspace-write` (komutlar korumalı alanda; yazma yalnızca masada ve işin klasöründe), ağ `ag_erisimi` ile. Gemini: `--approval-mode yolo` + `--include-directories` (araç bazında yasak listesi yok; kurallar `GEMINI.md`'de). Hepsinde `push_engeli`: danışman çalışırken git push adresleri geçersiz bir yardımcıya yönlenir. Sonuç otomatik kontrolden geçer (değişen / korunan dosyalar, gizli bilgi, doğrulama komutları), git'te görev dalına "iç ekip incelemesi yapılmadı" notuyla commit edilir ya da `sonuc.md` yazılır; özet görevin kartına, bildirime ve Outsource Consultant'ın sohbetine gider.

## Yönetim: CTO

Engineering Manager tek tek işleri yönetir; **CTO** (`cto`, `yonetim.ps1`, ayarlar `ayarlar.json > yonetim`) sistemi yönetir. Ofis boştayken `aralik_saat` saatte bir ve son değerlendirmeden beri iş bittiyse / takıldıysa / iptal edildiyse (ya da panelde **Değerlendirme iste**, `durum.ps1 -Degerlendir`) yönetim değerlendirmesi yapar. Girdileri betik hesaplar: iş sonuçları ve tur sayıları, yeni tura dönme, takılma ve iptal nedenleri, kök nedenler, kuyruk, token / limit kullanımı, birleştirilmeyi bekleyen `ekip/*` dalları. Çıktıları: rapor (`durum\yonetim\degerlendirme-<tarih>.md`), her iş isteminde bütün çalışanlara giden **ekip ilkeleri** (`durum\yonetim\ekip-ilkeleri.md`, öğrenilen dersler; elle de düzenlenebilir), başlamamış işlerin önceliği ve en fazla 2 iş önerisi (kendiliğinden açılmaz; panelde **Gözden geçir ve ekibe ver** ile siz verirsiniz). Başarısız değerlendirme döngüyü durdurmaz, 2 saat sonra yeniden denenir.

## Çalışana doğrudan komut ve paralel hatlar

Panelde bir çalışanın karakter kartında **Komut ver** ya da görev ayrıntısında **Çalışana komut ver** ile bir işi seçip komut verebilirsiniz: **Devam et** işi ana sırayı beklemeden ayrı bir hatta (`paralel.ps1`) ilerletir; **Devral** o çalışanın işin şu anki adımının rolünü bu işte üstlenmesini sağlar (adım devralanın model zinciriyle çalışır). İsteğe bağlı talimat yazarsanız o işin bütün istemlerine eklenir. Aynı işi iki süreç aynı anda yürütmez (görev kilidi). Hat; iş bitince, takılınca, soru sorunca ya da adım sınırında kendiliğinden kapanır, görev ayrıntısından **Paralel hattı durdur** ile durdurulabilir. Sınırlar `ayarlar.json > paralel` içindedir (`etkin`, `en_fazla` 2 hat, `adim_siniri` 12); hatlar doluysa iş ana sırada öne alınır. Komut satırı: `.\durum.ps1 -Komut <no> -Kim <çalışan> [-Emir devam|devral] [-Not "..."]`, `.\durum.ps1 -ParalelDurdur <no>`.

## Çalışanlar, unvanlar ve model seçimi

Unvanlar gerçek şirket pozisyonlarıdır: Chief Technology Officer, Engineering Manager, Product Manager, Codebase Explorer, Outsource Consultant, Incident Manager, Solution Architect, Full-Stack Developer, Frontend Developer, Backend Developer, Code Reviewer, System Administrator, Network Engineer, QA Engineer, Security Engineer, UI/UX Designer, Graphic Designer & Illustrator, HR Specialist, Communications Coordinator, Sound Designer. Ofisin odaları `kadro.json > departman` alanından gelir: **Yönetim** (CTO), **Teknik koordinasyon** (Engineering Manager, Incident Manager, Solution Architect), **Karşılama ve planlama** (Product Manager, Codebase Explorer), Yazılım, Altyapı ve güvenlik, Tasarım, İK ve iletişim, **Dış danışmanlık** (Outsource Consultant). Türkçe karşılıkları `kadro.json > rol_tr` alanındadır; rol anahtarları (`lider`, `gelistirici`, `sistem`…) değişmez. İK'nın işe aldığı yeni çalışanlar da İngilizce unvan ve Türkçe karşılıkla eklenir.

Her çalışanın kullandığı modeller bir zincirdir: ilk model günlük sınırda ya da kilitliyse sonrakine geçilir. Zinciri paneldeki **karakter kartından** seçersiniz: Kadro bölümünde bir karta (ya da sohbet penceresinde ⓘ > **Karakter kartı**) tıklayın; model ekleyin / çıkarın, ↑↓ ile sırayı (önceliği) değiştirin, Codex için düşünme eforunu seçin ve **Kaydet**. Kayıt `ayarlar.yerel.json > roller` içine yazılır (önceki hâli `.bak`); **Kadro varsayılanına dön** rolün satırını siler ve `kadro.json > araclar` geçerli olur. Seçilebilen modeller `ayarlar.json > model_katalogu` içindedir (Claude Opus 5.5, Fable 5.2, Sonnet 5.5, Haiku 5.5, "en güncel" kısaltmaları; Codex gpt-6.1-sol, gpt-6-astra); kurulumda seçtiğiniz modeller kataloğa kendiliğinden eklenir, katalog dışı model kaydedilmez. Varsayılan olarak Engineering Manager önce Opus 5.5, sonra Fable 5.2, en son Codex kullanır.

## Ortak klasörler ve sıralı programlar (18.11.2026)

Ajanlar normalde yalnızca kendi iş klasörüne yazar. `ayarlar.json > ortak_klasorler.yollar` (varsayılan `programlar`, katın köküne göre)
bütün ajanlara **yazma adımlarında** ek yazılabilir klasör olarak açılır: Claude ve Codex'e `--add-dir`, Gemini'ye `--include-directories`.
Okuma adımları ve tam yetkili altyapı rolleri değişmez; olmayan klasör atlanır. İsteme "Ortak klasörler" notu ve işin numarası eklenir.

Kullanım: birbirini izleyen aşamalardan oluşan bir program için `programlar\<ad>\PROGRAM.md` kontrol listesi. Her aşamada iki kutu
vardır: **Yapıldı** (aşamayı uygulayan ajan işaretler, iş numarasını yazar) ve **Kontrol edildi** (kontrol eden ajan sonucu yazar,
GEÇTİ ise işaretler). Ofise sırayla "sıradaki aşamayı uygula" ve "son aşamayı kontrol et" işleri verilir; sıradaki aşama ancak önceki
aşama kontrolden geçince açılır.

- Çevrimdışı sınama: `powershell -NoProfile -ExecutionPolicy Bypass -File testler\ortak-klasor.test.ps1`.

## Ekip içi yardımlaşma

Bir çalışan iş sırasında kendi yapamayacağı ama ekipte başkasının yapabileceği bir şeyle karşılaşırsa (yazılım/SDK kurulumu, emülatör, ağ ayarı, uygulamayı çalıştırıp test etmek, tasarım varlığı, güvenlik görüşü, yalnızca sizin verebileceğiniz bir bilgi) işi başarısız saymaz: çıktısının sonuna bir ```` ```yardim {json} ```` bloğu ekler (talimat her uygun istemin sonuna kendiliğinden eklenir). Akış `yardim.ps1` içindedir:

1. Görev **Engineering Manager'da (yardım isteği)** aşamasına geçer; istek `gorevler\<no>\yardim-istek-N.md` dosyasına yazılır.
2. Engineering Manager (`istemler\yonetici-yardim.md`) karar verir: **ATA** (kadrodan birine öncelikli yardım işi; sistem/network için altyapı talebi, diğerleri için uzman işi), **YANIT** (bilgi ya da yol gösterme), **ISE_ALIM** (İK işe alır) ya da **KULLANICI** (size sorar; yanıtladığınızda iş yeniden planlanmaz, kaldığı aşamadan sürer).
3. Görev **Ekipten yardım bekliyor** aşamasında bekler; yardım işleri bitince kaldığı aşamadan sürer. Gelen sonuçlar `yardim-sonuclari.md` dosyasında toplanır ve o görevin sonraki her ajan istemine "EKİPTEN GELEN YARDIM" olarak eklenir.

**Birlikte çalışma (anlık yardım).** Kısa işlerde (kütüphane / paket kurmak, internetten belge ya da dosya indirmek, kodu derleyip çalıştırmak, geliştirme sırasında küçük test koşturmaları, servis / port kontrolü, kısa uzman görüşü) Engineering Manager **BIRLIKTE** kararı verir: seçtiği çalışan hemen, aynı adımın içinde, isteyenin çalışma klasöründe ve kendi yetkisiyle çalışır (`istemler\yardim-birlikte.md`). Ayrı iş açılmaz; sonuç `yardim-sonuclari.md` dosyasına yazılır ve iş isteyenle kaldığı yerden sürer. İndirilen dosyalar çalışma klasöründe `.ekip-yardim\` altına konur; yazılım işinde bu klasör commit'e ve kontrole girmez. Kimse kendi yetkisi dışındaki işi yapamaz ama her çalışan yapamadığı şey için yardım isteyebilir: paket / kütüphane, internet, kodu çalıştırma ve test, kurulum, gizli bilgi (Engineering Manager size sorar), planda olmayan büyük değişiklik onayı. Uzun işler (SDK / sunucu kurulumu gibi) ayrı yardım işi olarak açılır.

Engineering Manager planda ön iş de isteyebilir: `YARDIM: <kadro anahtarı> | <iş>` satırları geliştirmeden önce yardım işi olarak açılır (ör. SDK kurulumu → sistem). Sınırlar `ayarlar.json > yardimlasma` içindedir: `etkin`, `gorev_basina_en_fazla` (4), `derinlik` (2; yardım işinin yardım işi en fazla bu kadar). Panelde **Ekip içi yardım** sütunu, kartta isteyen ve istek, görev ayrıntısında **Ekip içi yardım** sekmesi görünür. Incident Manager, buna rağmen takılan işler için güvenlik ağıdır.

## QA Engineer ve kullanıcı testleri

Kabul ölçütlerindeki "kullanıcı testi", "gerçek kullanıcı", "N kullanıcıdan M'i" gibi maddeleri **QA Engineer'ın** (`tester`, `istemler\kadro\tester.md`) simüle kullanıcı testi karşılar ve raporda bu açıkça "simüle kullanıcı testi" diye belirtilir. QA Engineer uygulamayı derleyip çalıştırır, kabul ölçütlerini işlev testiyle sınar, farklı kullanıcı profilleriyle (persona) senaryoları uygular, ekran görüntüsü ve günlükle kanıtlar ve `test-raporu.md` yazar. Tam yetkiyle çalışır (komut çalıştırabilir); yetkisini kendi ortamınıza göre `kadro.json` (kurulumdan sonra `kadro.yerel.json`) içinde değiştirebilirsiniz.

- Yazılım işlerinde QA Engineer her işte **test** aşamasında çalışır (`istemler\qa-test.md`; Engineering Manager `QA_TESTI: hayır` diyebilir): birim / entegrasyon testi yazar ve koşturur, gerekirse uygulamayı dener; çıktılar `calisma\<no>-test\` klasörüne yazılır. QA testi kapalı bir işte `EK_INCELEME: tester` eski yolla Code Reviewer onayından sonra test ettirir (`istemler\tester-inceleme.md`). Test edilen git ağacında bıraktığı değişiklikler (geliştiricinin işi ve dala alınan test dosyaları korunarak) geri alınır.
- Uzman işlerinde `INCELEYEN: tester` ya da test işinin kendisi için `SORUMLU: tester` seçilir. Herhangi bir çalışan da yardım isteğiyle QA Engineer'ı çağırabilir.

Bu sürümden önceki bir kurulumdan yükseltiyorsanız kişisel ayarlarınız şablonun yerine geçtiği için yeni özellikler kendiliğinden gelmez: `ayarlar.json` içindeki `yardimlasma` bloğunu `ayarlar.yerel.json`'a, `kadro.json` içindeki `tester` üyesini `kadro.yerel.json`'a kopyalayın (blok yoksa yardımlaşma kapalı kalır).

## Incident Manager: takılan işler

Bir adım defalarca başarısız olunca ya da tur sınırı dolunca iş takılır. Incident Manager (`cozucu.ps1`) bunu hemen bildirmek yerine inceler (salt okunur) ve karar verir: engeli kaldırabilecek çalışana **yardım işi** açar (iş bitince takılan iş kaldığı yerden sürer), geçici sorunlarda **yeniden dener**, iş yanlış ekipteyse **aktarır** ya da ekipte çözebilecek kimse yoksa size tam olarak ne yapmanız gerektiğini bildirir. Her müdahale `gorevler\<no>\cozum-N.md` dosyasına yazılır. Sınırlar `ayarlar.json > sorun_giderici` içindedir (`etkin`, `gorev_basina_en_fazla`, `en_eski_saat`); panelde ya da `durum.ps1 -Devam <no>` ile "Devam" demeniz hakkı sıfırlar.

Incident Manager başarısız, takılan ve iptal edilen işleri **kök nedene** göre de sınıflar: takılan işte teşhisle birlikte, iptal edilen ya da başka yoldan biten işlerde ofis boşken ayrı bir adımla (`istemler\sorun-kategori.md`, son 7 gün). Kategoriler: araç sınırı, araç hatası, ortam/kurulum eksik, gereksinim belirsiz, kabul ölçütü karşılanamaz, kod hatası, yanlış ekip/kapsam, zaman aşımı, kullanıcı kararı, ekip sistemi hatası, diğer. Görevde `kok_neden` (kategori, özet, önlem) tutulur, dökümü `gorevler\<no>\kok-neden.md`. Panelde kartta kırmızı etiket ve kullanım bölümünde **Başarısızlık ve iptal nedenleri** kartı görünür.

## Fibonacci puanlama

Engineering Manager işi yönlendirirken ya da ilk kez planlarken maliyetini Fibonacci ölçeğiyle puanlar (1, 2, 3, 5, 8, 13, 21: emek + belirsizlik + risk); puanlarken kadronun yeteneklerini ve yetkilerini hesaba katar. İşi yapan çalışan ilk üstlendiğinde kendi puanını ayrıca verir. Çıktıdaki `PUAN:` satırı okunur ve en yakın Fibonacci sayısına yuvarlanır; bir kez puanlayana yeniden sorulmaz. Panelde her kartın sağ üstünde **EM 5** · **Developer 8** gibi, listede "Puan" sütununda görünür. Kapatmak için `ayarlar.yerel.json > puanlama.etkin = false`.

## Token ve bağlam kullanımı

Her ajan çağrısı `durum\kullanim\kullanim-yyyyMM.jsonl` dosyasına yazılır: rol, görev, araç/model, süre, giriş/önbellek/çıkış tokenleri ve bağlam doluluğu (Claude için `stream-json` çıktısı, Codex için `%USERPROFILE%\.codex\sessions` oturum dosyası okunur). Panelin **Token ve bağlam kullanımı** bölümü bugün / 7 / 30 günlük özeti, çalışan başına dağılımı, grafiği ve en çok tüketen işleri gösterir. Bu sürümden önceki bir kurulumdan yükseltiyorsanız eski ajan günlüklerini bir kez aktarmak için `araclar\kullanim-gecmis.ps1` çalıştırılabilir. Bağlam penceresi her çağrıda modelin bildirdiği değerdir (güncel Claude modellerinde 1 M token).

Bölümün başındaki **limit ve boşta tüketim şeridi**: Claude ve Codex hesaplarınızın 5 saatlik ve haftalık kullanım yüzdesi ile sıfırlanma saati (%60 üstü sarı, %85 üstü kırmızı), **Ofis görevsizken** (ekibin bir göreve bağlı olmayan çağrıları: sohbet, kategorileme, yönlendirme) ve **Ofis dışı** (bilgisayardaki diğer Claude Code / Codex oturumları; ekiple aynı hesap limitini paylaşır). Claude yüzdeleri ekibin son Claude çağrısından, Codex yüzdeleri en yeni Codex oturum dosyasından okunur; ekip o araçla henüz çalışmadıysa "ölçüm yok" görünür.

Altında **ekip performansı** kutucukları (seçili dönem): **En başarılı çalışanlar** (başarılı çağrı oranı, çağrı sayısı, bitmiş işlere katkı) ve **En çok sorun yaşayanlar** (takılma, başarısız adım ve başarısız çağrı). Hangi çalışana destek gerektiğini gösterir.

## Panel

- **Görev panosu:** şeritler işin yolculuğudur: Sırada → Planlama (analiz · keşif · plan) → Yapılıyor → Doğrulama (test · inceleme · onay) → Bekliyor (yardım / sizin yanıtınız) → Takıldı → Tamamlandı (son 3 gün; "Biten ve iptalleri göster" ile hepsi ve İptal şeridi). Kartta tür renk şeridi, adım çubuğu, işin şu an kimde olduğu, yardım ve Incident Manager rozetleri, kök neden etiketi, proje ya da hedef, son hareket ve harcanan token görünür. Üstte arama, tür süzgeci ve sıralanabilir **Liste** görünümü vardır; seçimler tarayıcıda hatırlanır. Karta tıklayınca görev ayrıntısı açılır. **Sürükle-bırak:** bir kartı başka şeride bırakınca iş o aşamaya taşınır (onay sorar): Sırada = baştan başlat, Planlama = yeniden planla, Yapılıyor = yeniden yap, İnceleme = otomatik kontrol + inceleme, Tamamlandı = incelemedeki işi tamamla (yazılımda commit), İptal. Geri taşımada yeni tur açılır, önceki turun raporları saklanır; adım sürerken taşınırsa süren ajan durdurulur. Klavye / telefon için aynısı görev ayrıntısındaki **Aşamaya taşı** menüsünde ya da `.\durum.ps1 -Tasi <no> -Asama plan` ile.
- **Karakter kartı:** piksel portre, unvan ve Türkçe karşılığı, durum, son 30 günün çağrı / başarı / token / bağlam / süre değerleri, yetenekler (üstlendiği adımlar, yetki), gerçekte çalışan modeller, katıldığı son işler, rol talimatı ve model zinciri düzenleyici.
- **Arka plan (`</> kod`):** sayfanın sağ kenarındaki küçük sekme; döngü betiklerini, paneli, adım istemlerini, rol talimatlarını, ayarları, araçları, testleri ve bu belgeyi salt okunur gösterir (satır numaralı; Markdown biçimli görünüm). Yalnızca bu listedeki dosyalar okunur; ayarlardaki gizli değerler (bildirim konusu, parola) maskelenir.

Bu sürümden önceki bir kurulumdan yükseltiyorsanız: `ayarlar.json` içindeki `model_katalogu` bloğunu ve `roller.lider` zincirini `ayarlar.yerel.json`'a, `kadro.json` içindeki üyelerin `ad` ve `rol_tr` alanlarını `kadro.yerel.json`'a kopyalayın. Katalog yoksa model seçici yalnızca mevcut zinciri gösterir ve yeni model eklenemez. Yeni katmanlar için ayrıca `ayarlar.json` içindeki `paralel`, `planlama`, `yonetim`, `danisman` bloklarını ve `roller` altındaki `urun`, `kasif`, `frontend`, `backend`, `cto`, `danisman` zincirlerini `ayarlar.yerel.json`'a; `kadro.json` içindeki `cto`, `urun`, `kasif`, `frontend`, `backend`, `danisman` üyelerini, `gelistirici`'nin yeni unvanını (Full-Stack Developer) ve departman adlarını `kadro.yerel.json`'a kopyalayın. Kopyalamazsanız ofis eskisi gibi çalışır; yalnızca yeni roller ve katmanlar atlanır.

## İsteğe bağlı özellikler

```powershell
.\eposta-kur.ps1              # Gmail uygulama şifresiyle ekip e-postası (şifre Windows DPAPI ile saklanır)
.\ofis\telefon-kur.ps1        # Paneli telefondan açmak için; önce bilgisayara ve telefona Tailscale kurulmalı
.\ofis\kisayol-olustur.ps1    # Masaüstüne panel kısayolu (sihirbaz da sorar)
```

## Dosya yapısı

| Dosya/klasör | İşlev |
| --- | --- |
| `kur-ofis.ps1` | Etkileşimli kurulum sihirbazı |
| `baslat.ps1`, `ekip.ps1`, `ortak.ps1` | Görev döngüsü, ortak işlevler, token/bağlam kaydı |
| `is-ver.ps1`, `yonlendirme.ps1` | Türü seçilmeden iş verme ve Engineering Manager'ın yönlendirmesi |
| `cozucu.ps1` | Incident Manager (takılan işler, kök neden kategorileri) |
| `yardim.ps1` | Ekip içi yardımlaşma ve QA Engineer çalıştırma |
| `planlama.ps1` | Product Manager, Codebase Explorer, iş dağılımı (Frontend / Backend), QA test aşaması, onay kapısı |
| `yonetim.ps1` | CTO: yönetim değerlendirmesi, ekip ilkeleri, önceliklendirme, iş önerisi |
| `komut.ps1`, `paralel.ps1` | Çalışana doğrudan komut (Devam et / Devral) ve paralel çalışma hatları |
| `kendini.ps1`, `istemler/ofis-gelistirme.md` | Kendi kendini geliştirme: ayna depo, canlıdan eşitleme, canlıya alma, doğrulama, geri alma |
| `katlar.json`, `katlar/`, `iletisim.ps1` | Şirket binası: katlar (her biri kendi verisiyle) ve katlar arası iletişim (Comms, yazışmalar) |
| `yaratici.ps1`, `kopru.ps1`, `proje-ekle.ps1`, `sonuc-ekle.ps1` | Fikir hattı (Innovation Lab katı) ve onaylı POC'un ana kata köprüsü |
| `ofis/bina.html`, `ofis/panel-innovation-lab.html` | Bina paneli (solda Kat seçici) ve Innovation Lab katının stüdyo paneli |
| `danisman.ps1`, `danisman/` | Outsource Consultant: tek parça işler seçilen yapay zekanın terminal ajanına; masa (`CLAUDE.md` ana kurallar, `AGENTS.md` / `GEMINI.md` kopyaları) |
| `gorev-ekle.ps1`, `talep-ekle.ps1`, `uzman-ekle.ps1` | Yazılım, altyapı ve uzman işini doğrudan ekleme |
| `ayarlar.json`, `kadro.json`, `projeler.json` | Anonim ayar, kadro ve proje şablonları |
| `istemler/` | Rol ve uzman talimatları |
| `ofis/` | Web paneli ve telefon erişimi araçları |
| `araclar/`, `posta.ps1`, `eposta-kur.ps1` | İsteğe bağlı e-posta desteği, kullanım geçmişi aktarımı |
| `testler/` | Çevrimdışı testler: dağıtım, Engineering Manager/Incident Manager/kullanım kaydı, iptal yarışı, ekip içi yardımlaşma/QA Engineer, komut ve paralel hat, planlama katmanı, CTO, Outsource Consultant |
| `paketle.ps1`, `LICENSE` | Paylaşılabilir ZIP üretimi ve MIT lisansı |

Kurulum kişisel ayarları `*.yerel.json` dosyalarına yazar. Bu dosyalar şablonların tamamının yerine geçer ve Git'e eklenmez. Makine erişimlerini ve yetkileri kendi ortamınıza göre belirleyin; altyapı rolleri sistem komutları çalıştırabilir. Parolaları ve kişisel ayarları paylaşmayın. Dağıtım için temiz klon veya `paketle.ps1` ile üretilen `dagitim/ai-ofis.zip` kullanın; kurulmuş klasörün tamamını ZIP'lemeyin.

Kontrol: `powershell -NoProfile -ExecutionPolicy Bypass -File .\testler\dagitim.test.ps1` (Git klonunda da ZIP'ten açılmış klasörde de çalışır). `testler\yonetici-cozucu.test.ps1`, `testler\iptal-yarisi.test.ps1`, `testler\yardimlasma.test.ps1`, `testler\birlikte-puan-tasima.test.ps1`, `testler\komut-paralel.test.ps1`, `testler\planlama-katmani.test.ps1`, `testler\yonetim-cto.test.ps1` ve `testler\danisman.test.ps1` sahte bir ajanla geçici bir klasörde çalışır; gerçek AI aracı çağırmaz. Gerçek AI çağrıları ve isteğe bağlı entegrasyonlar ayrıca denenmelidir.
