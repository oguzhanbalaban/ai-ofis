# AI Ofis

Windows için kişisel yapay zeka ofisi kurulum paketi. Görevleri lider, geliştirici, denetçi ve uzman rolleri arasında dağıtır; inceleme, raporlama ve tarayıcıdan yönetim paneli sunar. Claude, Codex ve Gemini araçları birlikte veya ayrı kullanılabilir.

## Gereksinimler

- Windows 10/11 ve Windows PowerShell 5.1 veya üstü.
- Git for Windows ve commit oluşturmak için ayarlanmış Git kullanıcı adı/e-postası.
- En az bir kurulu AI aracı (Claude CLI, Codex uygulaması/CLI veya Gemini CLI), açık oturum ve yeterli model kotası. Abonelikler pakete dahil değildir. Geliştirme ve denetim için farklı modeller seçin; tek araçla kullanımda iki erişilebilir model gerekir.
- Paket doğrudan Node.js gerektirmez; seçtiğiniz AI aracının kendi kurulum gereksinimlerini ayrıca tamamlayın.
- İsteğe bağlı: e-posta okuma için Python 3, VM envanteri için VMware, telefon erişimi için Tailscale.

## Kurulum

1. Git ve kullanacağınız AI aracını kurup hesabınıza giriş yapın. Sihirbaz bunları indirmez ve model erişimini çevrimiçi doğrulamaz.
2. PowerShell'de depoyu kalıcı bir klasöre indirin ve sihirbazı başlatın:

   ```powershell
   git clone https://github.com/oguzhanbalaban/deneme-proje.git ai-ofis
   cd ai-ofis
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
   .\kur-ofis.ps1
   ```

   Size `ai-ofis.zip` iletildiyse veya GitHub'dan **Code → Download ZIP** ile indirdiyseniz: ZIP'i kalıcı bir klasöre çıkartın, PowerShell'i o klasörde açın ve son iki satırı çalıştırın.

   Windows varsayılan olarak `.ps1` betiklerini çalıştırmaz ("running scripts is disabled on this system" hatası). `Set-ExecutionPolicy -Scope Process` satırı izni **yalnızca o PowerShell penceresi için** açar; sistem ayarını değiştirmez. Yeni bir PowerShell penceresinde betik çalıştırmadan önce bu satırı yeniden yazın. Ofisin otomatik başlatma görevi ve masaüstü kısayolu bu izni kendisi verir.

3. Sihirbazda araç/model, bildirim ve ilk proje seçimlerini tamamlayın. VM ve telefon seçenekleri isteğe bağlıdır; başlangıçta kapalı bırakabilirsiniz. Temel kurulum yönetici oturumu gerektirmez.
4. Aynı pencerede durumu kontrol edin, sonra paneli açın:

   ```powershell
   .\durum.ps1
   .\ofis\ofis.ps1 -Ac
   ```

   Panel tarayıcıda açılır. Bu PowerShell penceresi panelin sunucusudur: panel kullanıldığı sürece açık kalmalıdır (kapatmak için Ctrl+C). Paneli pencere olmadan açmak için sihirbazın oluşturduğu **AI Ekip Ofisi** masaüstü kısayolunu kullanın.

Panel varsayılan olarak `http://127.0.0.1:8765/` adresini kullanır. Port doluysa kullanılan adres `ofis/sunucu.json` dosyasındadır.

## İlk görev

Var olan Git projenizin yolunu kullanın:

```powershell
.\gorev-ekle.ps1 -Proje C:\Projeler\Uygulama -Baslik "İlk görev" -Aciklama "İstenen değişiklik" -Kabul "Testler geçer"
.\baslat.ps1 -Konsol
```

Konsol kuyruğu sürekli işler (durdurmak için Ctrl+C). `durum.ps1 -Duraklat` ile duraklatabilir, `durum.ps1 -Surdur` ile sürdürebilirsiniz. HTML raporu `raporlar/son-rapor.html` dosyasına yazılır. Oturum açılışında otomatik çalıştırmak için `kur.ps1`, otomatik görevi kaldırmak için `kaldir.ps1` kullanılır. Aynı Windows oturumunda tek ofis kurulumu çalıştırın; yeniden kurulumdan önce döngüyü kapatın.

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
| `baslat.ps1`, `ekip.ps1`, `ortak.ps1` | Görev döngüsü ve ortak işlevler |
| `gorev-ekle.ps1`, `talep-ekle.ps1`, `uzman-ekle.ps1` | Yazılım, altyapı ve uzman işi ekleme |
| `ayarlar.json`, `kadro.json`, `projeler.json` | Anonim ayar, kadro ve proje şablonları |
| `istemler/` | Rol ve uzman talimatları |
| `ofis/` | Web paneli ve telefon erişimi araçları |
| `araclar/`, `posta.ps1`, `eposta-kur.ps1` | İsteğe bağlı e-posta desteği |
| `testler/dagitim.test.ps1` | Çevrimdışı dağıtım kontrolleri |
| `paketle.ps1`, `LICENSE` | Paylaşılabilir ZIP üretimi ve MIT lisansı |

Kurulum kişisel ayarları `*.yerel.json` dosyalarına yazar. Bu dosyalar şablonların tamamının yerine geçer ve Git'e eklenmez. Makine erişimlerini ve yetkileri kendi ortamınıza göre belirleyin; altyapı rolleri sistem komutları çalıştırabilir. Parolaları ve kişisel ayarları paylaşmayın. Dağıtım için temiz klon veya `paketle.ps1` ile üretilen `dagitim/ai-ofis.zip` kullanın; kurulmuş klasörün tamamını ZIP'lemeyin.

Kontrol: `powershell -NoProfile -ExecutionPolicy Bypass -File .\testler\dagitim.test.ps1` (Git klonunda da ZIP'ten açılmış klasörde de çalışır). Gerçek AI çağrıları ve isteğe bağlı entegrasyonlar ayrıca denenmelidir.
