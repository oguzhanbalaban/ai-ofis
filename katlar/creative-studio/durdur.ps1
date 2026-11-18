#requires -version 5.1
<#
  Creative Studio sunucularını durdurur (backend + Vite paneli; gizli ya da pencereli fark etmez).
      powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\creative-studio\durdur.ps1"
  Süren bir üretim varsa önce sorar; -Zorla ile sormadan durdurur.
  Yalnızca bu projenin sunucularına dokunur (logs\*.pid ve proje yolunu içeren dinleyici süreçler).
#>
param([switch]$Zorla)

$ErrorActionPreference = 'Stop'
$Kok = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $Kok 'logs'
$PanelPort = 5173

function Uyari([string]$m) { Write-Host "[uyarı]  $m" -ForegroundColor Yellow }
function Bilgi([string]$m) { Write-Host "[durdur] $m" -ForegroundColor Cyan }
function Tamam([string]$m) { Write-Host "[tamam]  $m" -ForegroundColor Green }

$port = 8000
$envFile = Join-Path $Kok '.env'
if (Test-Path $envFile) {
    $satir = Select-String -Path $envFile -Pattern '^\s*BACKEND_PORT\s*=\s*(\d+)' | Select-Object -First 1
    if ($satir) { $port = [int]$satir.Matches[0].Groups[1].Value }
}

# Süren üretim varsa uyar (durdurulursa iş "interrupted" olur; panelden yeniden denenebilir)
if (-not $Zorla) {
    try {
        $isler = Invoke-RestMethod "http://127.0.0.1:$port/api/jobs" -TimeoutSec 3
        $aktif = @($isler | Where-Object { $_.status -in @('queued', 'running', 'uploading') })
        if ($aktif.Count) {
            Uyari ("Şu an süren üretim var: " + (($aktif | ForEach-Object { "$($_.topic) [$($_.status)]" }) -join ', '))
            $cevap = Read-Host "Yine de durdurulsun mu? (e/h)"
            if ($cevap -notmatch '^\s*e') { Bilgi "Vazgeçildi."; exit 0 }
        }
    } catch { }
}

function Surec([int]$id) { Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue }
function Agaci-Kapat([int]$id, [string]$ad) {
    & taskkill.exe /PID $id /T /F *> $null
    Tamam "$ad durduruldu (pid $id)"
}

$durduruldu = 0
foreach ($ad in 'backend', 'panel') {
    $pidDosya = Join-Path $logDir "$ad.pid"
    if (Test-Path $pidDosya) {
        $id = [int]((Get-Content $pidDosya -Raw).Trim())
        $s = Surec $id
        # PID yeniden kullanılmış olabilir: yalnızca gerçekten bizim başlatıcımızsa öldür
        if ($s -and $s.Name -eq 'powershell.exe' -and $s.CommandLine -like "*-Sunucu $ad*" -and $s.CommandLine -like "*$Kok*") {
            Agaci-Kapat $id $ad
            $durduruldu++
        }
        Remove-Item $pidDosya -Force -ErrorAction SilentlyContinue
    }
}

# Yedek: pid dosyası olmadan (ör. elle) başlatılmış ama bu projeye ait dinleyiciler
Start-Sleep -Milliseconds 500
foreach ($p in @($port, $PanelPort)) {
    $baglanti = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $baglanti) { continue }
    $s = Surec $baglanti.OwningProcess
    if ($s -and $s.CommandLine -like "*$Kok*") {
        Agaci-Kapat $s.ProcessId ":$p dinleyicisi"
        $durduruldu++
    } else {
        Uyari ":$p başka bir uygulamaya ait ($($s.Name)); dokunulmadı."
    }
}

if ($durduruldu -eq 0) { Bilgi "Çalışan Creative Studio sunucusu yok." }
