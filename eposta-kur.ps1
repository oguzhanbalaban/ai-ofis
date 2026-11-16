<#
eposta-kur.ps1 - Haberleşme ve koordinasyon çalışanının e-posta hesabını kurar (bunu SEN bir kez çalıştırırsın).

Gmail için önce bir "uygulama şifresi" oluştur:
  Google Hesabı > Güvenlik > 2 Adımlı Doğrulama (açık olmalı) > Uygulama şifreleri > ad ver (ör. AI Ekip) > Oluştur
  Çıkan 16 harfli şifreyi aşağıda sorulduğunda yapıştır. Bu, asıl Gmail şifren DEĞİLDİR; istediğin an iptal edebilirsin.

Şifre durum\eposta.json içinde Windows DPAPI ile şifrelenir: yalnızca bu bilgisayardaki bu Windows kullanıcısı çözebilir.
Ekip e-postaları imap.gmail.com (okuma, okundu işaretlemez) ve smtp.gmail.com (gönderme) üzerinden kullanır.

  .\eposta-kur.ps1          kur ya da değiştir (adres + uygulama şifresi sorar, sonra giriş dener)
  .\eposta-kur.ps1 -Dene    yalnızca giriş dener ve son 3 iletinin konusunu gösterir
  .\eposta-kur.ps1 -Sil     kayıtlı hesabı siler
#>
param([switch]$Dene, [switch]$Sil)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'posta.ps1')
function Kalp([string]$Durum) { }   # döngünün kalp atışı dosyasına bu betik yazmasın
Ayarlari-Yukle
$yol = Join-Path $YolDurum 'eposta.json'

if ($Sil) {
    foreach ($f in @($yol, "$yol.bak")) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    Write-Host 'Kayıtlı e-posta hesabı silindi. (Google hesabındaki uygulama şifresini de iptal etmeyi unutma.)'
    return
}
if (-not $Dene) {
    Write-Host 'AI Ekip e-posta kurulumu (Gmail). Uygulama şifresi gerekir; ayrıntılar bu dosyanın başında.'
    $adres = (Read-Host 'Gmail adresin').Trim()
    if ($adres -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw "Geçerli bir e-posta adresi değil: $adres" }
    $sifre = Read-Host 'Uygulama şifresi (ekranda görünmez)' -AsSecureString
    if ($sifre.Length -lt 8) { throw 'Şifre çok kısa görünüyor.' }
    $kayit = [ordered]@{
        adres = $adres; imap = 'imap.gmail.com'; smtp = 'smtp.gmail.com'; smtp_port = 587
        sifre = (ConvertFrom-SecureString $sifre); kayit = (Simdi)
    }
    Json-Yaz $kayit $yol
    Write-Host "Kaydedildi: $yol (şifre DPAPI ile şifreli)"
}
Write-Host 'Giriş deneniyor…'
$p = Posta-Oku 3
if (-not $p.basarili) { Write-Host "Giriş BAŞARISIZ: $($p.hata)"; Write-Host 'Uygulama şifresini ve 2 Adımlı Doğrulama''nın açık olduğunu kontrol et.'; exit 1 }
Write-Host "Giriş başarılı. Gelen kutusundaki son $(@($p.iletiler).Count) iletinin konusu:"
foreach ($m in @($p.iletiler)) { Write-Host "  - $($m.konu)" }
Write-Host 'Haberleşme çalışanı artık e-posta okuyup gönderebilir.'
