<#
kur.ps1 - AI Ekip'i oturum açılışında otomatik başlatan zamanlanmış görevi kurar (Engineering Manager gerekmez).

  Tetik   : oturum açıldıktan GecikmeDk dakika sonra; ardından her BekciDk dakikada bir bekçi kontrolü
  Çalışma : conhost --headless -> powershell -> baslat.ps1 (pencere görünmez)
            Not: Windows Script Host bazı makinelerde kapalı olduğundan wscript/VBS kullanılmaz.
  Kaldır  : .\kaldir.ps1
#>
param([ValidateRange(0, 60)][int]$GecikmeDk = 5, [ValidateRange(5, 60)][int]$BekciDk = 10, [switch]$SimdiBaslat)
$ErrorActionPreference = 'Stop'
$Kok = $PSScriptRoot
$Ps1 = Join-Path $Kok 'baslat.ps1'
$GorevAdi = 'AI-Ekip'
$GorevYolu = '\AI-Ekip\'
foreach ($f in @($Ps1, (Join-Path $Kok 'ekip.ps1'), (Join-Path $Kok 'ortak.ps1'), (Join-Path $Kok 'rapor.ps1'))) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Eksik dosya: $f" }
}
$kullanici = "$env:USERDOMAIN\$env:USERNAME"

# conhost --headless: PowerShell penceresi hiç görünmez; PowerShell bitene kadar görev "Çalışıyor" kalır
$eylem = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" `
    -Argument ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $Ps1) -WorkingDirectory $Kok
$tetik = New-ScheduledTaskTrigger -AtLogOn -User $kullanici
$tetik.Delay = "PT${GecikmeDk}M"
# Oturum açma tetiğine tekrar deseni: ilk çalıştırmadan sonra her BekciDk dakikada bir bekçi kontrolü (süresiz)
$desen = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $BekciDk)).Repetition
$desen.Duration = ''
$tetik.Repetition = $desen

$kimlik = New-ScheduledTaskPrincipal -UserId $kullanici -LogonType Interactive -RunLevel Limited
$ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel -Compatibility Win8
$ayar.Hidden = $true

if (Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Confirm:$false
    Write-Host 'Önceki görev kaldırıldı.'
}
Register-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu -Action $eylem -Trigger $tetik -Principal $kimlik -Settings $ayar `
    -Description 'AI Ekip: Claude (Engineering Manager/Code Reviewer) + Codex (Full-Stack Developer) görev döngüsü. Oturum açıldıktan sonra başlar, bekçi her 10 dakikada sağlığını kontrol eder.' | Out-Null

# Ne istediğimizi değil, kayıtta gerçekten ne olduğunu göster
$kayit = Get-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu
$t = $kayit.Triggers[0]
Write-Host "Görev kuruldu: $GorevYolu$GorevAdi"
Write-Host ("  Tetik     : oturum açılışı ({0}), gecikme {1}" -f $kullanici, $t.Delay)
Write-Host ("  Tekrar    : her {0}, süre: {1}" -f $t.Repetition.Interval, $(if ($t.Repetition.Duration) { $t.Repetition.Duration } else { 'süresiz' }))
Write-Host ("  Ayarlar   : çoklu örnek={0}, süre sınırı={1}, pil={2}" -f $kayit.Settings.MultipleInstances, $kayit.Settings.ExecutionTimeLimit, (-not $kayit.Settings.DisallowStartIfOnBatteries))

if ($SimdiBaslat) {
    Start-ScheduledTask -TaskName $GorevAdi -TaskPath $GorevYolu
    Write-Host 'Görev şimdi başlatıldı.'
}
