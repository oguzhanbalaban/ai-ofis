#requires -version 5.1
<#
  Masal Shorts — yerel yapay zekâ motorlarının kurulumu (ekran kartında çalışır, API anahtarı gerekmez)

      powershell -ExecutionPolicy Bypass -File "<ofis klasörü>\katlar\masal\yerel-modeller.ps1"
      ... -Sadece flux     # yalnızca çizim motoru
      ... -Sadece ses      # yalnızca seslendirme motoru

  Kurulanlar (hepsi proje klasöründe, git dışında):
    flux : FLUX.2 [klein] 4B  (black-forest-labs, Apache 2.0, ~15 GB)      -> backend\engines\.venv-flux
    ses  : Chatterbox Multilingual (Resemble AI, MIT, ~3 GB)
           + faster-whisper large-v3-turbo (MIT, ~1,6 GB, karaoke zamanlaması) -> backend\engines\.venv-ses
  Modeller backend\models\hf altına iner (HF_HOME). Ağır bağımlılıklar ana backend venv'ini kirletmesin
  diye her motorun kendi sanal ortamı vardır; backend onları alt süreç olarak çağırır.
  NVIDIA ekran kartı gerekir (RTX 3060 12 GB ve üstü önerilir).
#>
param(
    [ValidateSet('hepsi', 'flux', 'ses')][string]$Sadece = 'hepsi'
)

$ErrorActionPreference = 'Stop'
$Kok = Split-Path -Parent $MyInvocation.MyCommand.Path
$Motorlar = Join-Path $Kok 'backend\engines'
$env:HF_HOME = Join-Path $Kok 'backend\models\hf'
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = '1'
$env:PYTHONUTF8 = '1'

function Bilgi([string]$m) { Write-Host "[yerel] $m" -ForegroundColor Cyan }
function Uyari([string]$m) { Write-Host "[uyarı] $m" -ForegroundColor Yellow }
function Tamam([string]$m) { Write-Host "[tamam] $m" -ForegroundColor Green }

$gpu = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>$null
if (-not $gpu) {
    Uyari "NVIDIA ekran kartı bulunamadı. Yerel motorlar işlemcide çok yavaş çalışır; API seçeneklerini (fal.ai / OpenAI / ElevenLabs) kullanın."
    exit 1
}
Tamam "Ekran kartı: $gpu"

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { Uyari "Python bulunamadı (kurulum.ps1'deki talimatlara bakın)."; exit 1 }

function Venv-Hazirla([string]$ad, [string[]]$torchPaketleri, [string]$torchIndex, [string]$gereksinim) {
    $venv = Join-Path $Motorlar ".venv-$ad"
    $vpy = Join-Path $venv 'Scripts\python.exe'
    # Not: komut çıktıları Out-Host'a gider; yoksa PowerShell onları fonksiyonun dönüş değerine katar.
    if (-not (Test-Path $vpy)) {
        Bilgi "$ad sanal ortamı oluşturuluyor: $venv"
        & python -m venv $venv | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "$ad venv oluşturulamadı" }
    }
    & $vpy -m pip install --upgrade pip --quiet | Out-Host
    Bilgi "$ad : PyTorch (CUDA) kuruluyor… (ilk seferde ~2,5 GB)"
    & $vpy -m pip install @torchPaketleri --index-url $torchIndex --quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$ad : torch kurulamadı" }
    Bilgi "$ad : paketler kuruluyor…"
    & $vpy -m pip install -r (Join-Path $Motorlar $gereksinim) --quiet | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$ad : pip install başarısız" }
    return $vpy
}

if ($Sadece -in 'hepsi', 'flux') {
    $vpy = Venv-Hazirla 'flux' @('torch') 'https://download.pytorch.org/whl/cu128' 'requirements-flux.txt'
    Bilgi "FLUX.2 [klein] 4B indiriliyor (~15 GB; yarıda kalırsa betiği yeniden çalıştırın, kaldığı yerden sürer)…"
    & $vpy (Join-Path $Motorlar 'flux_worker.py') --indir
    if ($LASTEXITCODE -ne 0) { throw "FLUX modeli indirilemedi" }
    & $vpy (Join-Path $Motorlar 'flux_worker.py') --kontrol
    if ($LASTEXITCODE -ne 0) { throw "FLUX denetimi başarısız" }
    Tamam "Çizim motoru hazır: FLUX.2 [klein] 4B (Apache 2.0, ticari kullanım serbest)"
}

if ($Sadece -in 'hepsi', 'ses') {
    $vpy = Venv-Hazirla 'ses' @('torch==2.6.0', 'torchaudio==2.6.0') 'https://download.pytorch.org/whl/cu124' 'requirements-ses.txt'
    Bilgi "Chatterbox Multilingual + Whisper indiriliyor (~5 GB)…"
    & $vpy (Join-Path $Motorlar 'ses_worker.py') --indir
    if ($LASTEXITCODE -ne 0) { throw "Ses modelleri indirilemedi" }
    & $vpy (Join-Path $Motorlar 'ses_worker.py') --kontrol
    if ($LASTEXITCODE -ne 0) { throw "Ses motoru denetimi başarısız" }
    Tamam "Seslendirme motoru hazır: Chatterbox Multilingual (MIT) + faster-whisper"
}

Write-Host ""
Tamam "Bitti. Backend'i yeniden başlatın (durdur.ps1 + baslat.ps1); panelde yeni motorlar seçilebilir olur."
