<#
telefon-kur.ps1 - Ofis panelini telefondan (ev dışından da) açıp yönetmek için Tailscale ile uzaktan erişimi kurar.
Bunu SEN bir kez çalıştırırsın.

Önce:
  1. Bilgisayara Tailscale'i kur: https://tailscale.com/download/windows (kurulum yönetici izni ister) ve hesabınla giriş yap.
  2. Telefona Tailscale uygulamasını kur (App Store / Google Play) ve AYNI hesapla giriş yap.
  3. Tailscale yönetim sayfasında HTTPS sertifikalarını aç: https://login.tailscale.com/admin/dns  (MagicDNS açık, "HTTPS Certificates" > Enable)
Sonra:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ofis\telefon-kur.ps1

Ne yapar:
  - Telefon simgelerini üretir (ofis\simge-180/192/512.png).
  - ofis\uzak.json'a bilgisayarın Tailscale adresini ve senin Tailscale hesabını yazar: panel uzaktan yalnızca bu hesabı kabul eder.
  - Panel sunucusunu yeniden başlatır ve "tailscale serve" ile yalnızca senin Tailscale ağına açar: https://<bilgisayar>.<ağ>.ts.net/
    Panel yine yalnızca 127.0.0.1'i dinler; güvenlik duvarına dokunulmaz; internete açılmaz (Funnel kullanılmaz).
  - Panel sunucusu hep açık kalsın diye "\AI-Ekip\Ofis" zamanlanmış görevini kurar (oturum açılınca başlar, 10 dakikada bir kontrol eder).

  .\telefon-kur.ps1 -Kaldir     uzaktan erişimi kapatır (serve sıfırlanır, uzak.json ve zamanlanmış görev silinir)
  .\telefon-kur.ps1 -Simgeler   yalnızca simgeleri üretir
#>
param([switch]$Kaldir, [switch]$Simgeler)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Ofis = $PSScriptRoot
$Utf8 = New-Object Text.UTF8Encoding $false
$UzakDosyasi = Join-Path $Ofis 'uzak.json'
$GorevAdi = 'Ofis'; $GorevYolu = '\AI-Ekip\'

function Simge-Uret {
    Add-Type -AssemblyName System.Drawing
    foreach ($boyut in 180, 192, 512) {
        $bmp = New-Object Drawing.Bitmap $boyut, $boyut
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $o = $boyut / 32.0
        $g.Clear([Drawing.ColorTranslator]::FromHtml('#161a23'))
        foreach ($d in @(@('#fb923c', 9, 17), @('#7aa7ff', 16, 13), @('#4fd1a1', 23, 17))) {
            $f = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($d[0]))
            $g.FillEllipse($f, [float](($d[1] - 3.6) * $o), [float](($d[2] - 3.6) * $o), [float](7.2 * $o), [float](7.2 * $o)); $f.Dispose()
        }
        $f = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#b4875a'))
        $g.FillRectangle($f, [float](6 * $o), [float](21.5 * $o), [float](20 * $o), [float](2.6 * $o)); $f.Dispose()
        $g.Dispose()
        $bmp.Save((Join-Path $Ofis "simge-$boyut.png"), [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    Write-Host 'Simgeler üretildi.'
}
function Tailscale-Exe {
    foreach ($a in @((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'))) { if ($a -and (Test-Path -LiteralPath $a)) { return $a } }
    $c = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
function Sunucu-Bilgisi { try { return (Get-Content -LiteralPath (Join-Path $Ofis 'sunucu.json') -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }
function Panel-Yeniden-Baslat {
    $s = Sunucu-Bilgisi
    if ($s -and $s.pid) {
        $p = Get-Process -Id ([int]$s.pid) -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -eq 'powershell') { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 2 }
    }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -WindowStyle Hidden `
        -ArgumentList ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ofis 'ofis.ps1'))
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $s = Sunucu-Bilgisi
        if ($s -and $s.pid -and (Get-Process -Id ([int]$s.pid) -ErrorAction SilentlyContinue)) { return [int]$s.port }
    }
    throw 'Panel sunucusu başlatılamadı; ofis\ofis.log dosyasına bak.'
}
function Gorev-Kur {
    $kullanici = "$env:USERDOMAIN\$env:USERNAME"
    $eylem = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') `
        -Argument ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ofis 'ofis.ps1')) -WorkingDirectory $Ofis
    $tetik = New-ScheduledTaskTrigger -AtLogOn -User $kullanici
    $tetik.Delay = 'PT1M'
    $desen = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)).Repetition
    $desen.Duration = ''
    $tetik.Repetition = $desen
    $kimlik = New-ScheduledTaskPrincipal -UserId $kullanici -LogonType Interactive -RunLevel Limited
    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -Compatibility Win8
    $ayar.Hidden = $true
    if (Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Confirm:$false }
    Register-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Action $eylem -Trigger $tetik -Principal $kimlik -Settings $ayar `
        -Description 'AI Ekip ofis paneli: telefondan erişim için panel sunucusunu açık tutar (ikinci kopya kendiliğinden çıkar).' | Out-Null
    Write-Host 'Zamanlanmış görev kuruldu: \AI-Ekip\Ofis (oturum açılınca başlar, 10 dakikada bir kontrol eder).'
}

if ($Simgeler) { Simge-Uret; return }

$ts = Tailscale-Exe
if ($Kaldir) {
    if ($ts) { & $ts serve reset 2>&1 | Out-Host }
    if (Test-Path -LiteralPath $UzakDosyasi) { Remove-Item -LiteralPath $UzakDosyasi -Force }
    if (Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Confirm:$false }
    [void](Panel-Yeniden-Baslat)
    Write-Host 'Uzaktan erişim kapatıldı. Panel yine yalnızca bu bilgisayardan açılır.'
    return
}

if (-not $ts) {
    Write-Host 'Tailscale bulunamadı. Önce https://tailscale.com/download/windows adresinden kurup hesabınla giriş yap, sonra bu betiği yeniden çalıştır.'
    exit 1
}
$st = (& $ts status --json) -join "`n" | ConvertFrom-Json
if ($st.BackendState -ne 'Running') {
    Write-Host "Tailscale bağlı değil (durum: $($st.BackendState)). Görev çubuğundaki Tailscale simgesinden giriş yapıp bağlan, sonra yeniden dene."
    exit 1
}
$hostAdi = ([string]$st.Self.DNSName).TrimEnd('.').ToLowerInvariant()
$kullanici = ''
$u = $st.User.PSObject.Properties[[string]$st.Self.UserID]
if ($u) { $kullanici = ([string]$u.Value.LoginName).ToLowerInvariant() }
if (-not $hostAdi) { Write-Host 'Bilgisayarın Tailscale adı alınamadı. Yönetim sayfasında MagicDNS açık mı? https://login.tailscale.com/admin/dns'; exit 1 }
if (-not @($st.CertDomains).Count) {
    Write-Host 'Tailscale ağında HTTPS sertifikaları kapalı. Şu sayfada "HTTPS Certificates" > Enable de, sonra betiği yeniden çalıştır:'
    Write-Host '  https://login.tailscale.com/admin/dns'
    exit 1
}
if (-not $kullanici) { Write-Host 'Tailscale hesap adı alınamadı; yeniden giriş yapıp dene.'; exit 1 }

Simge-Uret
[IO.File]::WriteAllText($UzakDosyasi, (ConvertTo-Json -InputObject ([ordered]@{ hostlar = @($hostAdi); kullanicilar = @($kullanici); kurulum = (Get-Date).ToString('o') })), $Utf8)
Write-Host "Uzak erişim ayarı yazıldı: $hostAdi (yalnızca $kullanici)"
$port = Panel-Yeniden-Baslat
Write-Host "Panel sunucusu yeniden başladı (127.0.0.1:$port)."
$cikti = & $ts serve --bg --https=443 "http://127.0.0.1:$port" 2>&1
$kod = $LASTEXITCODE
$cikti | Out-Host
if ($kod -ne 0) {
    Write-Host 'tailscale serve başarısız oldu. Yukarıdaki mesajda bir bağlantı varsa açıp onayla, sonra betiği yeniden çalıştır.'
    exit 1
}
Gorev-Kur
Write-Host ''
Write-Host '================ HAZIR ================'
Write-Host "Telefonda Tailscale açıkken tarayıcıda şu adresi aç:  https://$hostAdi/"
Write-Host 'Sonra tarayıcının menüsünden "Ana ekrana ekle" de; panel uygulama gibi açılır.'
Write-Host 'Bu adres yalnızca senin Tailscale cihazlarından açılır; internete açık değildir.'
