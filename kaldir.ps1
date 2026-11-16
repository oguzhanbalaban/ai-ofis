<#
kaldir.ps1 - AI Ekip zamanlanmış görevini kaldırır ve çalışan döngüyü durdurur.
Görevler, dallar, raporlar ve günlükler silinmez.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
if (Get-ScheduledTask -TaskName 'AI-Ekip' -TaskPath '\AI-Ekip\' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'AI-Ekip' -TaskPath '\AI-Ekip\' -Confirm:$false
    Write-Host 'Zamanlanmış görev kaldırıldı.'
} else { Write-Host 'Zamanlanmış görev zaten yok.' }
$k = Json-Oku (Join-Path $YolDurum 'kalp.json')
if ($k -and $k.pid) {
    $p = Get-Process -Id ([int]$k.pid) -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq 'powershell') {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $p.Id 2>&1 | Out-Null } finally { $ErrorActionPreference = $eap }
        Write-Host "Çalışan döngü durduruldu (PID $($p.Id))."
    }
}
Write-Host "Veriler yerinde: $Kok"
