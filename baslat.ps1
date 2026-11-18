<#
baslat.ps1 - AI Ekip giriş noktası (Zamanlanmış görev "conhost --headless powershell ..." ile çağırır).

  * Döngü zaten çalışıyor ve kalp atışı tazeyse hemen çıkar (10 dakikada bir gelen bekçi tetikleri böyle biter).
  * Kalp atışı ayarlar.dongu.bekci_dk'dan eskiyse donmuş döngüyü sonlandırır ve yerine geçer.
  * Betikler değişirse döngü kendini yeni sürümle yeniden yükler.

Elle deneme:
  powershell -NoProfile -ExecutionPolicy Bypass -File baslat.ps1 -Konsol -BosBitir
#>
param([switch]$Konsol, [int]$AdimSiniri = 0, [switch]$BosBitir)
$ErrorActionPreference = 'Stop'
$script:Konsol = [bool]$Konsol

# Claude masaüstü uygulamasından devralınan değişkenler arka plandaki claude.exe'yi bozar (401); temizle.
$adlar = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } | ForEach-Object { $_.Name })
foreach ($a in $adlar) { Remove-Item -LiteralPath "env:$a" -ErrorAction SilentlyContinue }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'rapor.ps1')
. (Join-Path $PSScriptRoot 'ekip.ps1')
Ayarlari-Yukle

function Kalp-Yasi-Dk {
    $k = Json-Oku (Join-Path $YolDurum 'kalp.json')
    if (-not $k -or -not $k.zaman) { return [pscustomobject]@{ dk = 9999; pid = 0 } }
    return [pscustomobject]@{ dk = ((Get-Date) - [datetime]$k.zaman).TotalMinutes; pid = [int]$k.pid }
}

# Şirket binası: ana kat (bu görev) açık alt katların döngülerini de ayakta tutar (ortak.ps1 > Bina-Bekcisi)
if ($KatKimligi -eq 'ana') { try { Bina-Bekcisi } catch { Gunluk "Bina bekçisi hatası: $($_.Exception.Message)" 'UYARI' } }
# Her katın kendi döngü kilidi var (ana: Local\AIEkipDongusu, diğerleri: Local\AIEkipDongusu_<kat>)
$mutex = New-Object Threading.Mutex($false, (Kat-Dongu-Kilidi $KatKimligi))
$sahip = $false
try { $sahip = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sahip = $true }

if (-not $sahip) {
    $kalp = Kalp-Yasi-Dk
    if ($kalp.dk -lt [double]$Ayar.dongu.bekci_dk) { exit 0 }   # döngü sağlıklı
    # Uyku/hazırda bekletmeden yeni uyanmış olabilir: kendine gelmesi için bekle, tekrar bak
    Start-Sleep -Seconds 90
    $kalp = Kalp-Yasi-Dk
    if ($kalp.dk -lt [double]$Ayar.dongu.bekci_dk) { exit 0 }
    Gunluk ('Bekçi: kalp atışı {0:N0} dk önce; döngü (PID {1}) donmuş sayılıp yeniden başlatılıyor' -f $kalp.dk, $kalp.pid) 'UYARI'
    if ($kalp.pid -gt 0 -and $kalp.pid -ne $PID -and (Get-Process -Id $kalp.pid -ErrorAction SilentlyContinue)) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $kalp.pid 2>&1 | Out-Null } catch {} finally { $ErrorActionPreference = $eap }
    }
    try { $sahip = $mutex.WaitOne(60000) } catch [Threading.AbandonedMutexException] { $sahip = $true }
    if (-not $sahip) { Gunluk 'Bekçi: döngü kilidi alınamadı; çıkılıyor' 'HATA'; exit 1 }
    Bildir -Baslik "$(Ofis-Adi) yeniden başlatıldı" -Metin ('Döngü {0:N0} dakikadır yanıt vermiyordu; bekçi yeniden başlattı.' -f $kalp.dk) -Anahtar 'bekci' -Onem 'yuksek'
}

try {
    $sonuc = 'yeniden'
    while ($sonuc -eq 'yeniden') {
        # Her turda betikleri yeniden yükle: güncellenen sürüm yeniden başlatmaya gerek kalmadan devreye girer
        . (Join-Path $PSScriptRoot 'ortak.ps1')
        . (Join-Path $PSScriptRoot 'rapor.ps1')
        . (Join-Path $PSScriptRoot 'ekip.ps1')
        $sonuc = Ekip-Dongusu -AdimSiniri $AdimSiniri -BosBitir:$BosBitir
    }
    Gunluk "Döngü sona erdi ($sonuc)"
} catch {
    Gunluk "Döngü çöktü: $($_.Exception.Message)" 'HATA'
    throw
} finally {
    Kalp 'durdu'
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
