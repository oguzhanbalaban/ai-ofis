#requires -version 5.1
<#
  Creative Studio başlatıcı (Windows PowerShell 5.1)

  Varsayılan: backend + Vite paneli GİZLİ çalışır (terminal penceresi açılmaz).
  Günlükler logs\ klasörüne yazılır; durdurmak için durdur.ps1.
      powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\creative-studio\baslat.ps1"
  Tek port modu: paneli derler, her şeyi backend portundan (varsayılan 8000) sunar.
      powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\creative-studio\baslat.ps1" -Tek
  Pencereli mod (hata ayıklarken çıktıyı canlı görmek için): -Gorunur
  Tarayıcıyı açmamak için: -TarayiciAcma

  Zaten çalışan sunucu yeniden başlatılmaz; betiği iki kez çalıştırmak güvenlidir.
#>
param(
    [switch]$Tek,
    [switch]$Gorunur,
    [switch]$TarayiciAcma,
    # İç kullanım: baslat.ps1 kendini bu parametreyle gizli/görünür konsolda yeniden çağırır.
    [ValidateSet('backend', 'panel')][string]$Sunucu
)

$ErrorActionPreference = 'Stop'
$Betik = $MyInvocation.MyCommand.Path
$Kok = Split-Path -Parent $Betik
$venvPy = Join-Path $Kok 'backend\.venv\Scripts\python.exe'
$backendDir = Join-Path $Kok 'backend'
$frontendDir = Join-Path $Kok 'frontend'
$viteJs = Join-Path $frontendDir 'node_modules\vite\bin\vite.js'
$logDir = Join-Path $Kok 'logs'
$PanelPort = 5173

function Uyari([string]$m) { Write-Host "[uyarı]  $m" -ForegroundColor Yellow }
function Bilgi([string]$m) { Write-Host "[başlat] $m" -ForegroundColor Cyan }
function Tamam([string]$m) { Write-Host "[tamam]  $m" -ForegroundColor Green }
function Dinliyor([int]$p) { [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) }

# Yeni kurulan araçların (ör. winget ile FFmpeg) görülmesi için PATH'i kayıt defterinden tazele.
# Alt süreçler bu ortamı devralır.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

# .env'den port oku (yoksa 8000)
$port = 8000
$envFile = Join-Path $Kok '.env'
if (Test-Path $envFile) {
    $satir = Select-String -Path $envFile -Pattern '^\s*BACKEND_PORT\s*=\s*(\d+)' | Select-Object -First 1
    if ($satir) { $port = [int]$satir.Matches[0].Groups[1].Value }
}
if ($port -ge 8765 -and $port -le 8774) {
    Uyari "BACKEND_PORT=$port, AI Ekip paneline ayrılmış 8765-8774 aralığında. Lütfen başka bir port seçin."
    exit 1
}

# ---------------------------------------------------------------------------------------
# İç mod: tek bir sunucuyu bu konsolda çalıştır (gizli konsolda çıktı logs\ altına yazılır)
# ---------------------------------------------------------------------------------------
if ($Sunucu) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $pidDosya = Join-Path $logDir "$Sunucu.pid"
    Set-Content -Path $pidDosya -Value $PID -Encoding Ascii
    $env:PYTHONUTF8 = '1'
    $env:PYTHONUNBUFFERED = '1'
    if ($Sunucu -eq 'backend') {
        $exe = $venvPy
        $argumanlar = @('-m', 'app')
        $calismaDizini = $backendDir
        $Host.UI.RawUI.WindowTitle = "Creative Studio - backend :$port"
    } else {
        $env:STUDIO_BACKEND = "http://127.0.0.1:$port"
        $exe = (Get-Command node.exe).Source
        $argumanlar = @("`"$viteJs`"", '--clearScreen', 'false')
        $calismaDizini = $frontendDir
        $Host.UI.RawUI.WindowTitle = "Creative Studio - panel :$PanelPort"
    }
    try {
        if ($Gorunur) {
            Set-Location -LiteralPath $calismaDizini
            & $exe @($argumanlar | ForEach-Object { $_.Trim('"') })
        } else {
            $env:NO_COLOR = '1'   # günlük dosyasına ANSI renk kodu yazılmasın
            $p = Start-Process -FilePath $exe -ArgumentList $argumanlar -WorkingDirectory $calismaDizini `
                -NoNewWindow -PassThru `
                -RedirectStandardOutput (Join-Path $logDir "$Sunucu.out.log") `
                -RedirectStandardError (Join-Path $logDir "$Sunucu.err.log")
            $p.WaitForExit()
        }
    } finally {
        if ((Test-Path $pidDosya) -and ((Get-Content $pidDosya -Raw).Trim() -eq "$PID")) {
            Remove-Item $pidDosya -Force -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

# ---------------------------------------------------------------------------------------
# Başlatıcı
# ---------------------------------------------------------------------------------------
if (-not (Test-Path $venvPy)) {
    Uyari ("Önce kurulum yapın:  powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Kok 'kurulum.ps1') + "`"")
    exit 1
}
if (-not $Tek -and -not (Test-Path $viteJs)) {
    Uyari "frontend\node_modules eksik. Önce kurulum.ps1'i çalıştırın."
    exit 1
}

function Sunucu-Baslat([string]$ad) {
    $psArg = "-NoProfile -ExecutionPolicy Bypass -File `"$Betik`" -Sunucu $ad"
    if ($Gorunur) {
        Start-Process powershell.exe -ArgumentList "$psArg -Gorunur"
    } else {
        # Windows Script Host bu makinede kapalı; gizli başlatma conhost --headless ile yapılır.
        Start-Process conhost.exe -ArgumentList "--headless powershell.exe $psArg" -WindowStyle Hidden
    }
}

$bekle = @()

if ($Tek) {
    Bilgi "Panel derleniyor (npm run build)…"
    Push-Location $frontendDir
    try {
        & npm.cmd run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build başarısız" }
    } finally {
        Pop-Location
    }
    $url = "http://127.0.0.1:$port"
} else {
    $url = "http://127.0.0.1:$PanelPort"
}

if (Dinliyor $port) {
    Bilgi "Backend zaten açık (:$port); yeniden başlatılmadı."
} else {
    Sunucu-Baslat 'backend'
    $bekle += [pscustomobject]@{ Ad = 'backend'; Port = $port }
}
if (-not $Tek) {
    if (Dinliyor $PanelPort) {
        Bilgi "Panel zaten açık (:$PanelPort); yeniden başlatılmadı."
    } else {
        Sunucu-Baslat 'panel'
        $bekle += [pscustomobject]@{ Ad = 'panel'; Port = $PanelPort }
    }
}

if ($bekle.Count) {
    Bilgi ("Sunucular açılıyor" + $(if ($Gorunur) { " (pencereli)" } else { " (gizli)" }) + "…")
    $son = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $son -and @($bekle | Where-Object { -not (Dinliyor $_.Port) }).Count) {
        Start-Sleep -Milliseconds 500
    }
    $hata = $false
    foreach ($s in $bekle) {
        if (Dinliyor $s.Port) {
            Tamam "$($s.Ad) hazır (:$($s.Port))"
        } else {
            $hata = $true
            Uyari "$($s.Ad) 60 sn içinde açılmadı (:$($s.Port))."
            foreach ($uzanti in 'err', 'out') {
                $log = Join-Path $logDir "$($s.Ad).$uzanti.log"
                if (Test-Path $log) {
                    Write-Host "---- $log (son satırlar) ----" -ForegroundColor DarkGray
                    Get-Content $log -Tail 15 | ForEach-Object { Write-Host "  $_" }
                }
            }
        }
    }
    if ($hata) { exit 1 }
}

Tamam "Panel: $url"
if (-not $Gorunur) {
    Bilgi "Pencere açılmadı; sunucular arka planda. Günlükler: $logDir"
}
Bilgi ("Durdurmak için:  powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Kok 'durdur.ps1') + "`"")
if (-not $TarayiciAcma) {
    Start-Process $url
}
