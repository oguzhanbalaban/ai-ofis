# AI Ofis

Windows için kişisel yapay zeka ofisi kurulum paketi. Verilen işi **Engineering Manager** okuyup Software Developer, Code Reviewer, altyapı ve uzman rollerine dağıtır; çalışanlar iş sırasında Engineering Manager üzerinden birbirinden **yardım** ister, uygulamaları **QA Engineer** çalıştırıp test eder, takılan işleri **Incident Manager** inceler. İnceleme, raporlama, token/bağlam kullanım panosu ve tarayıcıdan yönetim paneli sunar. Claude, Codex ve Gemini araçları birlikte veya ayrı kullanılabilir; varsayılan rol zincirleri Claude öncelikli, Codex yedektir (sihirbaz seçtiğiniz araçlara göre uyarlar).

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

`is-ver.ps1` ve panelde **+ İş ver** tür sormaz; iş doğrudan Engineering Manager'a gider (rol anahtarı `lider` geriye uyumluluk için durur, her yerde Engineering Manager adıyla görünür). Engineering Manager işi okur ve `yonlendirme.ps1` ile karar verir: **YAZILIM** (kayıtlı bir proje ya da `ayarlar.json > gorev.yeni_proje_kok` altında, boşsa `%USERPROFILE%\ai-ekip-projeler` içinde yeni bir git deposu), **ALTYAPI** (System Administrator + Network Engineer), **UZMAN** (kadrodan bir çalışan), **ISE_ALIM** (İK önce işe alır) ya da **SORU_VAR**. Gerekçe `gorev.md`'ye eklenir. İsteğe bağlı ipuçları: `-Ipucu` (proje adı ya da klasör) ve `-Rol` (önerilen çalışan).

## Çalışanlar, unvanlar ve model seçimi

Unvanlar gerçek şirket pozisyonlarıdır: Engineering Manager, Incident Manager, Solution Architect, Software Developer, Code Reviewer, System Administrator, Network Engineer, QA Engineer, Security Engineer, UI/UX Designer, Graphic Designer & Illustrator, HR Specialist, Communications Coordinator, Sound Designer. Türkçe karşılıkları `kadro.json > rol_tr` alanındadır; rol anahtarları (`lider`, `gelistirici`, `sistem`…) değişmez. İK'nın işe aldığı yeni çalışanlar da İngilizce unvan ve Türkçe karşılıkla eklenir.

Her çalışanın kullandığı modeller bir zincirdir: ilk model günlük sınırda ya da kilitliyse sonrakine geçilir. Zinciri paneldeki **karakter kartından** seçersiniz: Kadro bölümünde bir karta (ya da sohbet penceresinde ⓘ > **Karakter kartı**) tıklayın; model ekleyin / çıkarın, ↑↓ ile sırayı (önceliği) değiştirin, Codex için düşünme eforunu seçin ve **Kaydet**. Kayıt `ayarlar.yerel.json > roller` içine yazılır (önceki hâli `.bak`); **Kadro varsayılanına dön** rolün satırını siler ve `kadro.json > araclar` geçerli olur. Seçilebilen modeller `ayarlar.json > model_katalogu` içindedir (Claude Opus 5.5, Fable 5.2, Sonnet 5.5, Haiku 5.5, "en güncel" kısaltmaları; Codex gpt-6.1-sol, gpt-6-astra); kurulumda seçtiğiniz modeller kataloğa kendiliğinden eklenir, katalog dışı model kaydedilmez. Varsayılan olarak Engineering Manager önce Opus 5.5, sonra Fable 5.2, en son Codex kullanır.

## Ekip içi yardımlaşma

Bir çalışan iş sırasında kendi yapamayacağı ama ekipte başkasının yapabileceği bir şeyle karşılaşırsa (yazılım/SDK kurulumu, emülatör, ağ ayarı, uygulamayı çalıştırıp test etmek, tasarım varlığı, güvenlik görüşü, yalnızca sizin verebileceğiniz bir bilgi) işi başarısız saymaz: çıktısının sonuna bir ```` ```yardim {json} ```` bloğu ekler (talimat her uygun istemin sonuna kendiliğinden eklenir). Akış `yardim.ps1` içindedir:

1. Görev **Engineering Manager'da (yardım isteği)** aşamasına geçer; istek `gorevler\<no>\yardim-istek-N.md` dosyasına yazılır.
2. Engineering Manager (`istemler\yonetici-yardim.md`) karar verir: **ATA** (kadrodan birine öncelikli yardım işi; sistem/network için altyapı talebi, diğerleri için uzman işi), **YANIT** (bilgi ya da yol gösterme), **ISE_ALIM** (İK işe alır) ya da **KULLANICI** (size sorar; yanıtladığınızda iş yeniden planlanmaz, kaldığı aşamadan sürer).
3. Görev **Ekipten yardım bekliyor** aşamasında bekler; yardım işleri bitince kaldığı aşamadan sürer. Gelen sonuçlar `yardim-sonuclari.md` dosyasında toplanır ve o görevin sonraki her ajan istemine "EKİPTEN GELEN YARDIM" olarak eklenir.

Engineering Manager planda ön iş de isteyebilir: `YARDIM: <kadro anahtarı> | <iş>` satırları geliştirmeden önce yardım işi olarak açılır (ör. SDK kurulumu → sistem). Sınırlar `ayarlar.json > yardimlasma` içindedir: `etkin`, `gorev_basina_en_fazla` (4), `derinlik` (2; yardım işinin yardım işi en fazla bu kadar). Panelde **Ekip içi yardım** sütunu, kartta isteyen ve istek, görev ayrıntısında **Ekip içi yardım** sekmesi görünür. Incident Manager, buna rağmen takılan işler için güvenlik ağıdır.

## QA Engineer ve kullanıcı testleri

Kabul ölçütlerindeki "kullanıcı testi", "gerçek kullanıcı", "N kullanıcıdan M'i" gibi maddeleri **QA Engineer'ın** (`tester`, `istemler\kadro\tester.md`) simüle kullanıcı testi karşılar ve raporda bu açıkça "simüle kullanıcı testi" diye belirtilir. QA Engineer uygulamayı derleyip çalıştırır, kabul ölçütlerini işlev testiyle sınar, farklı kullanıcı profilleriyle (persona) senaryoları uygular, ekran görüntüsü ve günlükle kanıtlar ve `test-raporu.md` yazar. Tam yetkiyle çalışır (komut çalıştırabilir); yetkisini kendi ortamınıza göre `kadro.json` (kurulumdan sonra `kadro.yerel.json`) içinde değiştirebilirsiniz.

- Yazılım işlerinde Engineering Manager `EK_INCELEME: tester` der: Code Reviewer onayından sonra QA Engineer test eder (`istemler\tester-inceleme.md`); çıktılar `calisma\<no>-test\` klasörüne yazılır. Test edilen git ağacında bıraktığı değişiklikler (Software Developer'ın işi korunarak) geri alınır.
- Uzman işlerinde `INCELEYEN: tester` ya da test işinin kendisi için `SORUMLU: tester` seçilir. Herhangi bir çalışan da yardım isteğiyle QA Engineer'ı çağırabilir.

Bu sürümden önceki bir kurulumdan yükseltiyorsanız kişisel ayarlarınız şablonun yerine geçtiği için yeni özellikler kendiliğinden gelmez: `ayarlar.json` içindeki `yardimlasma` bloğunu `ayarlar.yerel.json`'a, `kadro.json` içindeki `tester` üyesini `kadro.yerel.json`'a kopyalayın (blok yoksa yardımlaşma kapalı kalır).

## Incident Manager: takılan işler

Bir adım defalarca başarısız olunca ya da tur sınırı dolunca iş takılır. Incident Manager (`cozucu.ps1`) bunu hemen bildirmek yerine inceler (salt okunur) ve karar verir: engeli kaldırabilecek çalışana **yardım işi** açar (iş bitince takılan iş kaldığı yerden sürer), geçici sorunlarda **yeniden dener**, iş yanlış ekipteyse **aktarır** ya da ekipte çözebilecek kimse yoksa size tam olarak ne yapmanız gerektiğini bildirir. Her müdahale `gorevler\<no>\cozum-N.md` dosyasına yazılır. Sınırlar `ayarlar.json > sorun_giderici` içindedir (`etkin`, `gorev_basina_en_fazla`, `en_eski_saat`); panelde ya da `durum.ps1 -Devam <no>` ile "Devam" demeniz hakkı sıfırlar.

Incident Manager başarısız, takılan ve iptal edilen işleri **kök nedene** göre de sınıflar: takılan işte teşhisle birlikte, iptal edilen ya da başka yoldan biten işlerde ofis boşken ayrı bir adımla (`istemler\sorun-kategori.md`, son 7 gün). Kategoriler: araç sınırı, araç hatası, ortam/kurulum eksik, gereksinim belirsiz, kabul ölçütü karşılanamaz, kod hatası, yanlış ekip/kapsam, zaman aşımı, kullanıcı kararı, ekip sistemi hatası, diğer. Görevde `kok_neden` (kategori, özet, önlem) tutulur, dökümü `gorevler\<no>\kok-neden.md`. Panelde kartta kırmızı etiket ve kullanım bölümünde **Başarısızlık ve iptal nedenleri** kartı görünür.

## Token ve bağlam kullanımı

Her ajan çağrısı `durum\kullanim\kullanim-yyyyMM.jsonl` dosyasına yazılır: rol, görev, araç/model, süre, giriş/önbellek/çıkış tokenleri ve bağlam doluluğu (Claude için `stream-json` çıktısı, Codex için `%USERPROFILE%\.codex\sessions` oturum dosyası okunur). Panelin **Token ve bağlam kullanımı** bölümü bugün / 7 / 30 günlük özeti, çalışan başına dağılımı, grafiği ve en çok tüketen işleri gösterir. Bu sürümden önceki bir kurulumdan yükseltiyorsanız eski ajan günlüklerini bir kez aktarmak için `araclar\kullanim-gecmis.ps1` çalıştırılabilir. Bağlam penceresi her çağrıda modelin bildirdiği değerdir (güncel Claude modellerinde 1 M token).

Bölümün başındaki **limit ve boşta tüketim şeridi**: Claude ve Codex hesaplarınızın 5 saatlik ve haftalık kullanım yüzdesi ile sıfırlanma saati (%60 üstü sarı, %85 üstü kırmızı), **Ofis görevsizken** (ekibin bir göreve bağlı olmayan çağrıları: sohbet, kategorileme, yönlendirme) ve **Ofis dışı** (bilgisayardaki diğer Claude Code / Codex oturumları; ekiple aynı hesap limitini paylaşır). Claude yüzdeleri ekibin son Claude çağrısından, Codex yüzdeleri en yeni Codex oturum dosyasından okunur; ekip o araçla henüz çalışmadıysa "ölçüm yok" görünür.

## Panel

- **Görev panosu:** şeritler işin yolculuğudur: Sırada → Planlama → Yapılıyor → İnceleme → Bekliyor (yardım / sizin yanıtınız) → Takıldı → Tamamlandı (son 3 gün; "Biten ve iptalleri göster" ile hepsi ve İptal şeridi). Kartta tür renk şeridi, adım çubuğu, işin şu an kimde olduğu, yardım ve Incident Manager rozetleri, kök neden etiketi, proje ya da hedef, son hareket ve harcanan token görünür. Üstte arama, tür süzgeci ve sıralanabilir **Liste** görünümü vardır; seçimler tarayıcıda hatırlanır. Karta tıklayınca görev ayrıntısı açılır.
- **Karakter kartı:** piksel portre, unvan ve Türkçe karşılığı, durum, son 30 günün çağrı / başarı / token / bağlam / süre değerleri, yetenekler (üstlendiği adımlar, yetki), gerçekte çalışan modeller, katıldığı son işler, rol talimatı ve model zinciri düzenleyici.
- **Arka plan (`</> kod`):** sayfanın sağ kenarındaki küçük sekme; döngü betiklerini, paneli, adım istemlerini, rol talimatlarını, ayarları, araçları, testleri ve bu belgeyi salt okunur gösterir (satır numaralı; Markdown biçimli görünüm). Yalnızca bu listedeki dosyalar okunur; ayarlardaki gizli değerler (bildirim konusu, parola) maskelenir.

Bu sürümden önceki bir kurulumdan yükseltiyorsanız: `ayarlar.json` içindeki `model_katalogu` bloğunu ve `roller.lider` zincirini `ayarlar.yerel.json`'a, `kadro.json` içindeki üyelerin `ad` ve `rol_tr` alanlarını `kadro.yerel.json`'a kopyalayın. Katalog yoksa model seçici yalnızca mevcut zinciri gösterir ve yeni model eklenemez.

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
| `gorev-ekle.ps1`, `talep-ekle.ps1`, `uzman-ekle.ps1` | Yazılım, altyapı ve uzman işini doğrudan ekleme |
| `ayarlar.json`, `kadro.json`, `projeler.json` | Anonim ayar, kadro ve proje şablonları |
| `istemler/` | Rol ve uzman talimatları |
| `ofis/` | Web paneli ve telefon erişimi araçları |
| `araclar/`, `posta.ps1`, `eposta-kur.ps1` | İsteğe bağlı e-posta desteği, kullanım geçmişi aktarımı |
| `testler/` | Çevrimdışı testler: dağıtım, Engineering Manager/Incident Manager/kullanım kaydı, iptal yarışı, ekip içi yardımlaşma/QA Engineer |
| `paketle.ps1`, `LICENSE` | Paylaşılabilir ZIP üretimi ve MIT lisansı |

Kurulum kişisel ayarları `*.yerel.json` dosyalarına yazar. Bu dosyalar şablonların tamamının yerine geçer ve Git'e eklenmez. Makine erişimlerini ve yetkileri kendi ortamınıza göre belirleyin; altyapı rolleri sistem komutları çalıştırabilir. Parolaları ve kişisel ayarları paylaşmayın. Dağıtım için temiz klon veya `paketle.ps1` ile üretilen `dagitim/ai-ofis.zip` kullanın; kurulmuş klasörün tamamını ZIP'lemeyin.

Kontrol: `powershell -NoProfile -ExecutionPolicy Bypass -File .\testler\dagitim.test.ps1` (Git klonunda da ZIP'ten açılmış klasörde de çalışır). `testler\yonetici-cozucu.test.ps1`, `testler\iptal-yarisi.test.ps1` ve `testler\yardimlasma.test.ps1` sahte bir ajanla geçici bir klasörde çalışır; gerçek AI aracı çağırmaz. Gerçek AI çağrıları ve isteğe bağlı entegrasyonlar ayrıca denenmelidir.
