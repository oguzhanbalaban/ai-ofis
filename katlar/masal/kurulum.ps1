#requires -version 5.1
<#
  Masal Shorts kurulum betiği (Windows PowerShell 5.1)
  Kullanım:  powershell -ExecutionPolicy Bypass -File .\kurulum.ps1

  Yaptıkları: Python / Node / FFmpeg kontrolü, backend\.venv oluşturma, pip paketleri,
  npm paketleri ve .env dosyasını .env.example'dan oluşturma.
  Sistem aracı KURMAZ; eksik olanı nasıl kuracağınızı yazar.
#>
param(
    [switch]$GercekMod,
    [switch]$PiperYok   # Piper Türkçe ses modelini (~60 MB) indirme
)

$ErrorActionPreference = 'Stop'
$Kok = Split-Path -Parent $MyInvocation.MyCommand.Path

function Bilgi([string]$m) { Write-Host "[kurulum] $m" -ForegroundColor Cyan }
function Uyari([string]$m) { Write-Host "[uyarı]   $m" -ForegroundColor Yellow }
function Tamam([string]$m) { Write-Host "[tamam]   $m" -ForegroundColor Green }

# 1) Araç kontrolü --------------------------------------------------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Uyari "Python bulunamadı. Kurmak için: winget install --id Python.Python.3.13 -e  (ya da python.org)"
    exit 1
}
Tamam ("Python: " + (& python --version 2>&1))

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) {
    Uyari "Node.js/npm bulunamadı. Kurmak için: winget install --id OpenJS.NodeJS.LTS -e  (ya da nodejs.org)"
    exit 1
}
Tamam ("Node: " + (& node --version) + " / npm " + (& npm.cmd --version))

$ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ff) {
    Tamam "FFmpeg: $($ff.Source)"
} else {
    Uyari "Sistem FFmpeg'i yok. Sorun değil: pip ile gelen imageio-ffmpeg ikilisi kullanılacak."
    Uyari "ffprobe dahil tam kurulum isterseniz: winget install --id Gyan.FFmpeg -e"
}

# 2) Python sanal ortamı ------------------------------------------------------------
$venv = Join-Path $Kok 'backend\.venv'
$venvPy = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $venvPy)) {
    Bilgi "Sanal ortam oluşturuluyor: $venv"
    & python -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw "venv oluşturulamadı" }
}
Bilgi "pip paketleri kuruluyor…"
& $venvPy -m pip install --upgrade pip --quiet
$req = if ($GercekMod) { 'backend\requirements-real.txt' } else { 'backend\requirements.txt' }
& $venvPy -m pip install -r (Join-Path $Kok $req) --quiet
if ($LASTEXITCODE -ne 0) { throw "pip install başarısız" }
Tamam "Python paketleri hazır ($req)"

# 2b) Piper Türkçe ses modeli (çevrimdışı seslendirme) ---------------------------------
if ($PiperYok) {
    Bilgi "Piper modeli atlandı (-PiperYok). Ses motoru olarak ElevenLabs ya da test sesi kullanılabilir."
} else {
    Bilgi "Piper Türkçe ses modeli denetleniyor (yoksa Hugging Face rhasspy/piper-voices'tan ~60 MB indirilir)…"
    Push-Location (Join-Path $Kok 'backend')
    try {
        & $venvPy scripts\piper_ses_indir.py
        if ($LASTEXITCODE -ne 0) { Uyari "Piper modeli indirilemedi; daha sonra: backend\.venv\Scripts\python backend\scripts\piper_ses_indir.py" }
    } finally {
        Pop-Location
    }
    Uyari "Piper tr_TR-dfki modeli CC BY-NC-SA 4.0 (ticari olmayan) veriyle eğitilmiştir. Para kazanılan yayın için ElevenLabs önerilir."
}

# 3) Frontend paketleri ---------------------------------------------------------------
Bilgi "npm paketleri kuruluyor…"
Push-Location (Join-Path $Kok 'frontend')
try {
    & npm.cmd install --no-fund --no-audit
    if ($LASTEXITCODE -ne 0) { throw "npm install başarısız" }
} finally {
    Pop-Location
}
Tamam "npm paketleri hazır"

# 4) .env -------------------------------------------------------------------------------
$envFile = Join-Path $Kok '.env'
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $Kok '.env.example') $envFile
    Tamam ".env oluşturuldu (MOCK_MODE=true). Gerçek anahtarları yalnızca bu dosyaya yazın."
} else {
    Bilgi ".env zaten var; dokunulmadı."
}

Write-Host ""
Tamam ("Kurulum bitti. Başlatmak için:  powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Kok 'baslat.ps1') + "`"")
if (-not (Test-Path (Join-Path $Kok 'backend\engines\.venv-flux\Scripts\python.exe'))) {
    Bilgi ("Gerçek yapay zekâ çizimi + duygulu Türkçe ses için (NVIDIA ekran kartı, ~20 GB, ücretsiz):  powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Kok 'yerel-modeller.ps1') + "`"")
}
