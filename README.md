# AI Ofis

Windows üzerinde çalışan, görevleri planlayıp geliştiren ve bağımsız incelemeden geçiren kişisel yapay zeka ofisi. Paket; betikleri, görsel paneli, anonim ayar şablonlarını ve tam kadroyu içerir. Temiz klasörü ZIP olarak da iletebilirsiniz; çalışırken kaynak sisteme ihtiyaç duymaz.

Kadro: lider, geliştirici, denetçi, yazılım mimarı, sistem yöneticisi, network, siber güvenlik, UI/UX, grafik/illüstrasyon, ses/müzik, insan kaynakları ve haberleşme. **12 çalışan**, 14 akış istemi ve 7 uzman talimatı vardır. Claude, Codex ve Gemini birlikte veya tek başına kullanılabilir; araç zincirleri değiştirilebilir.

Görev kuyruğu, Git worktree ile ayrı çalışma klasörleri, otomatik kontroller, uzman incelemeleri, limitte yedek modele geçiş, HTML raporları ve ofis paneli dahildir. VMware envanteri, masaüstü/ntfy bildirimleri, Gmail ve Tailscale üzerinden telefon paneli isteğe bağlıdır.

## Gereksinimler

- Windows 10/11, Windows PowerShell 5.1 veya üstü. Panel ve zamanlanmış görevler Windows PowerShell ile çalışır.
- Git for Windows; yazılım görevleri için var olan bir Git deposu ve commit yapabilen Git kullanıcı yapılandırması.
- En az bir kurulu AI aracı: Claude CLI, Codex uygulaması/CLI veya Gemini CLI. Hesapla giriş, model erişimi ve yeterli kota gerekir. Abonelikler pakete dahil değildir.
- Tek araç kullanılıyorsa geliştirici ve denetçi için erişilebilir **iki farklı model** gerekir. Sihirbaz her araç için birincil ve denetim/yedek modellerini sorar. Önerilen model adlarını hesabınızdaki adlarla değiştirin.
- E-posta okuma için isteğe bağlı Python 3 (yalnızca standart kütüphane); VM envanteri için VMware Player/Workstation; telefon paneli için bilgisayarda ve telefonda Tailscale.

Sihirbaz araç dosyalarını tespit eder ve giriş/abonelik hazırlığını sorar; ağ üzerinden hesap veya model erişimini doğrulamaz, yazılım indirmez. Kurulum kaynakları: [Claude](https://code.claude.com/docs/en/setup), [Codex](https://developers.openai.com/codex/), [Gemini](https://geminicli.com/), [Git](https://git-scm.com/download/win).

## Hızlı başlangıç

GitHub deponuzun **Code → HTTPS** adresini yer tutucunun yerine yazın veya ZIP'i kalıcı bir klasöre çıkartın. PowerShell'i o klasörde açın:

```powershell
git clone <DEPO_HTTPS_ADRESI> ai-ofis
cd ai-ofis
powershell -NoProfile -ExecutionPolicy Bypass -File .\kur-ofis.ps1
```

ZIP ile kurulumda ilk iki komut yerine çıkarttığınız klasöre geçin. Çalıştırma ilkesi seçeneği yalnızca bu PowerShell süreci içindir. Yönetici oturumu gerekmez; isteğe bağlı özelliklerin kurulum hataları ekranda bildirilir.

Sihirbaz sırasıyla araçları/modelleri, giriş hazırlığını, altyapı/VM tercihlerini, bildirimleri, özet/çalışma saatlerini ve ilk projeyi sorar. IP bilinmiyorsa boş bırakabilirsiniz. VMware varsa `vmrun list` ile seçtiğiniz klasörlerdeki `.vmx` dosyaları birleştirilir; her VM eklenmeden önce gösterilir. Kapalı VM'ler de dosyalarından bulunur. `C:\VMs`, `D:\VMs`, `H:\VMs` ve Belgeler altındaki `Virtual Machines` önerilir; başka klasörler de girilebilir. Tüm disk veya ağ taraması yapılmaz. VMware yokken fiziksel/uzak makineleri elle ekleyebilirsiniz.

Bağlantı bilgileri dosyasının yalnızca yolu kaydedilir; içeriği pakete kopyalanmaz. Sihirbaz parola istemez. Makine IP'leri kullanıcıdan alınır. Tekrar kurulum mevcut makine/proje kayıtlarını korur; bulunan VM yeniden seçilirse kaydı güncellenir. Yeniden çalıştırmadan önce ofis döngüsünü kapatın. Giriş hazır değilse sihirbaz yeni otomatik başlangıç görevi kurmaz.

Görev eklemeden önce:

```powershell
.\baslat.ps1 -Konsol -BosBitir
.\durum.ps1
.\ofis\ofis.ps1 -Ac
```

Boş kuyrukta ilk komut `Hazır görev kalmadı` yazıp çıkar. Panel varsayılan olarak `http://127.0.0.1:8765/` adresindedir; port doluysa seçtiği adres `ofis/sunucu.json` dosyasına yazılır. Paket `ofis/panel.html` dosyasını içerir; ekran görüntüsü bu sürüme eklenmemiştir.

## Kullanım

```powershell
# Var olan Git deposu ilk görevde otomatik kaydedilir
.\gorev-ekle.ps1 -Proje C:\Projeler\Uygulama -Baslik "İlk görev" -Aciklama "İstenen değişiklik" -Kabul "Testler geçer"
.\baslat.ps1 -Konsol           # Kuyruğu işler; sürekli döngü
.\durum.ps1                   # Durum ve rapor üretir
.\durum.ps1 -Ac               # HTML raporu açar
.\durum.ps1 -Duraklat
.\durum.ps1 -Surdur
.\durum.ps1 -Devam 0001 -Not "Ek açıklama"

.\talep-ekle.ps1 -Baslik "Servis denetimi" -Aciklama "Laboratuvar sunucusunu incele" -Hedef LAB-SRV
.\uzman-ekle.ps1 -Baslik "Arayüz önerisi" -Aciklama "Bir tasarım önerisi hazırla" -Rol tasarimci-ui

# İsteğe bağlı özellikleri sonradan kur veya kaldır
.\kur.ps1                     # Oturum açılışı + bekçi; hemen başlatmaz
.\kaldir.ps1                  # Otomatik görevi ve çalışan döngüyü kaldırır
.\ofis\kisayol-olustur.ps1
.\ofis\kisayol-olustur.ps1 -Kaldir
.\eposta-kur.ps1              # Gmail uygulama şifresi; Windows DPAPI ile saklanır
.\ofis\telefon-kur.ps1        # Önce Tailscale kurulumu ve giriş gerekir
.\ofis\telefon-kur.ps1 -Kaldir
```

`-BosBitir` hazır işler varsa onları da işler. Soru bekleyen görevin `gorevler/<no>/gorev.md` dosyasına yanıt yazılınca ekip yeniden planlar. Rapor `raporlar/son-rapor.html` dosyasındadır. Zamanlanmış görevler ve kısayollar kurulu klasöre bağlıdır; klasörü taşırsanız yeniden kurun. Aynı Windows oturumunda tek ofis kurulumu çalıştırın.

Altyapı sistem/network rolleri ve `tam` yetkili uzmanlar görev sırasında korumasız komut çalıştırabilir. Makineleri ve `altyapi.kurallar` bölümünü kendi yetki kapsamınıza göre düzenleyin; başka kurulumdaki yetkiler bu pakete aktarılmaz. ntfy konusunu bilenler bildirimlere erişebilir; içerikler seçili ntfy sunucusuna gider. Telefon paneli ise Tailscale üzerinden kendi hesabınıza açılır.

## Yapılandırma ve dağıtım

| Anonim şablon | Kişisel dosya | İçerik |
| --- | --- | --- |
| `ayarlar.json` | `ayarlar.yerel.json` | Roller, modeller, araç yolları, saatler, limitler, makineler, bildirimler |
| `kadro.json` | `kadro.yerel.json` | Çalışanlar, talimat yolları, yetkiler, uzman araç zincirleri |
| `projeler.json` | `projeler.yerel.json` | Proje klasörleri, temel dal ve doğrulama komutları |

Yerel dosya varsa tamamı kullanılır; şablonla alan bazında birleştirilmez. Dosya yoksa anonim şablon kullanılır. Yeni proje ve işe alım kayıtları da yerel dosyalara yazılır. Araçlar ve modeller sonradan yerel dosyalardan değiştirilebilir veya sihirbaz yeniden çalıştırılabilir. Yerleşik roller `ayarlar.yerel.json > roller`, uzmanlar `kadro.yerel.json > uyeler[*].araclar` içinden okunur. `claude/codex/gemini > exe` tam yolu değiştirebilir. Yeni araç türü eklemek ayrıca `ortak.ps1` içinde çalıştırıcı gerektirir.

`dongu.calisma_saatleri` geceyi aşan aralıkları destekler; `00:00-24:00` sürekli çalışmadır. `gunluk_sinir` çağrı sayısını, `gorev.max_tur` düzeltme turunu sınırlar. Projelerdeki `dogrulama` komutları kullanıcı tarafından tanımlanır. E-posta bilgileri `durum/eposta.json` içinde yalnızca aynı Windows kullanıcısının çözebildiği biçimde tutulur.

`.gitignore` kişisel ayarları ve yedeklerini, görev içeriklerini, durum/günlük/rapor/çalışma klasörlerini, e-posta/bağlantı bilgilerini ve panel oturum bilgilerini dışarıda bırakır. Bunları zorla Git'e eklemeyin. GitHub'a yayımlarken kaynakları veya GitHub **Download ZIP** arşivini paylaşın. **Kurulmuş klasörün tamamını ZIP'lemek kişisel dosyaları da içerir; dağıtım için temiz klon kullanın.** MIT lisansı `LICENSE` dosyasındadır. Paket depo kaydı veya yayın işlemini otomatik yapmaz.

Paylaşılabilir ZIP'i kaynak klasöründe aşağıdaki komutla üretin. Betik sabit dosya listesi kullanır; kişisel dosyaları, sonradan eklenen dosyaları ve çalışma verilerini arşive almaz. Dağıtılan JSON şablonlarını anonim tutun. Çıktı `dagitim/ai-ofis.zip` ve SHA256 özeti ekranda gösterilir. ZIP'i olduğu gibi iletin; alıcı klasöre çıkartıp `kur-ofis.ps1` çalıştırabilir. GitHub Release'e aynı ZIP eklenebilir.

```powershell
.\paketle.ps1
```

## Akış ve dosyalar

```text
Görev / talep / uzman işi → Lider planı → Çalışan uygulaması
                                    ↓
                         Otomatik kontroller → Bağımsız denetçi
                                    ↑                 ↓
                              Düzeltme ← RET     Lider kabulü
                                                      ↓
                     Yazılım: görev dalına commit / diğer: teslim raporu

yeni → plan → gelistirme → kontrol → denetim → kabul → tamamla → tamam
                   ↖ düzeltme         ↘ takildi / bekliyor_kullanici
```

Ana döngü `baslat.ps1`/`ekip.ps1`, ortak işlevler `ortak.ps1`, yerel dosya seçimi `yapilandirma.ps1`, altyapı `altyapi.ps1`, uzman/İK `uzman.ps1`, posta `posta.ps1` ve `araclar/posta_oku.py`, panel `ofis/` altındadır. İstemler `istemler/` içindedir. PowerShell dosyalarını Türkçe karakterler için **UTF-8 BOM** olarak kaydedin.

## Çevrimdışı kontroller

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\testler\dagitim.test.ps1
```

Ek paket gerekmez. Kontroller ayrıştırma/şablon bütünlüğünü, kişisel ayar ayrımını, araç seçimlerini, giriş doğrulamasını, benzetilmiş VM keşfini ve boş kuyruk/görev ekleme/durum akışını geçici çalışma kopyasında sınar. Ağ, gerçek VM yönetimi, masaüstü değişikliği veya zamanlanmış görev kurulumu yapmaz. Gerçek AI çağrıları ve isteğe bağlı sistem bütünleşmeleri kurulumunuzda ayrıca denenmelidir.
