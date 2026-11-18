<#
paralel.ps1 - Paralel çalışma hattı: kullanıcının panelden verdiği komutla (Devam et / Devral) bir işi ana döngünün sırasını
beklemeden ayrı bir süreçte yürütür. Panel sunucusu (ofis.ps1 > /api/komut) ya da durum.ps1 -Komut görünmez pencerede başlatır:

  powershell -NoProfile -ExecutionPolicy Bypass -File paralel.ps1 -Gorev <no> -Kim <kadro anahtarı> [-Komut devam|devral] [-Konsol]

  * Görev kilidini alır (ortak.ps1 > Gorev-Kilidi-Al): ana döngü ve diğer hatlar bu işi o sırada yürütmez. Alamazsa çıkar.
  * İş etkin bir aşamadaysa adım adım ilerletir (ekip.ps1 > Gorev-Ilerlet); iş tamamlanınca, takılınca, soru sorunca, yardım
    beklemeye geçince, yeniden deneme beklerken, adım sınırında (ayarlar.json > paralel.adim_siniri), ekip duraklatılınca
    (DURDUR) ya da kullanıcı hattı durdurunca (gorevler\<no>\paralel-durdur) durur; iş kaldığı yerden ana sıraya döner.
  * Döngünün kalp atışı dosyasına (kalp.json; bekçi izler) yazmaz: hattın durumu durum\paralel\<no>.json (panel okur).
#>
param(
    [Parameter(Mandatory)][string]$Gorev,
    [Parameter(Mandatory)][string]$Kim,
    [ValidateSet('devam', 'devral')][string]$Komut = 'devam',
    [switch]$Konsol
)
$ErrorActionPreference = 'Stop'
$script:Konsol = [bool]$Konsol
# Claude masaüstü uygulamasından devralınan değişkenler arka plandaki claude.exe'yi bozar (401); temizle
$adlar = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } | ForEach-Object { $_.Name })
foreach ($a in $adlar) { Remove-Item -LiteralPath "env:$a" -ErrorAction SilentlyContinue }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'rapor.ps1')
. (Join-Path $PSScriptRoot 'ekip.ps1')
Ayarlari-Yukle
# Bu süreç döngünün kalp atışı dosyasına yazmasın; hattın kendi kaydına yazsın (komut.ps1 > Paralel-Kalp)
function Kalp([string]$Durum) { Paralel-Kalp $Durum }

if ($Gorev -notmatch '^\d{4}(-[A-Za-z0-9-]{1,60})?$') { throw "Geçersiz görev numarası: $Gorev" }
if ($Kim -notmatch '^[a-z][a-z0-9-]{1,39}$') { throw "Geçersiz çalışan anahtarı: $Kim" }
$phKlasor = Get-ChildItem -LiteralPath $YolGorev -Directory | Where-Object { $_.Name -eq $Gorev -or $_.Name -like "$Gorev-*" } | Select-Object -First 1
if (-not $phKlasor) { throw "Görev bulunamadı: $Gorev" }
$phId = $phKlasor.Name
$script:ParalelGorev = $phId
$script:ParalelBilgi = [ordered]@{
    pid = $PID; gorev = $phId; kim = $Kim; emir = $Komut; baslangic = (Simdi); zaman = (Simdi)
    durum = 'başlıyor'; adim = ''; asama = ''; adim_sayisi = 0
}

$phKilit = Gorev-Kilidi-Al $phId
if ($phKilit -and (Dongu-Bu-Iste-mi $phId)) { Gorev-Kilidi-Birak $phKilit; $phKilit = $null }   # ana döngü bu işte (kilitsiz adım)
if (-not $phKilit) {
    Gunluk "Paralel hat: görev $phId şu an başka bir süreçte yürütülüyor; hat açılmadı" 'UYARI'
    $script:ParalelBilgi = $null
    Paralel-Kaydi-Sil $phId
    exit 0
}
$phNeden = ''
$phAdim = 0
try {
    Paralel-Kalp 'başladı'
    Gunluk "=== Paralel hat başladı: görev $phId, $(Calisan-Adi $Kim) ($Komut) (PID $PID) ==="
    $phDurdur = Paralel-Durdur-Dosyasi $phId
    if (Test-Path -LiteralPath $phDurdur) { Remove-Item -LiteralPath $phDurdur -Force }   # önceki hattan kalmış
    while ($true) {
        Ayarlari-Yukle
        $phSinir = (Paralel-Ayari).adim_siniri
        if (Test-Path -LiteralPath (Join-Path $Kok 'DURDUR')) { $phNeden = 'ekip duraklatıldı'; break }
        if (Test-Path -LiteralPath $phDurdur) { $phNeden = 'kullanıcı hattı durdurdu'; break }
        $phG = Gorev-Diskten $phId
        if (-not $phG) { $phNeden = 'görev kaydı okunamadı'; break }
        if ($AktifAsamalar -notcontains [string]$phG.asama) { $phNeden = Asama-Adi $phG.asama; break }
        if ($phG.sonraki_deneme) {
            $phSd = $null; try { $phSd = [datetime][string]$phG.sonraki_deneme } catch {}
            if ($phSd -and $phSd -gt (Get-Date)) { $phNeden = 'yeniden deneme bekliyor ({0})' -f $phSd.ToString('HH:mm'); break }
        }
        if ($phAdim -ge $phSinir) { $phNeden = "adım sınırı ($phSinir)"; break }
        $script:ParalelBilgi.asama = [string]$phG.asama
        Gorev-Ilerlet $phG
        if ($script:IlerletmeAtlandi) { $phNeden = 'iş başka bir süreçte yürütülüyor'; break }
        $phAdim++
        $script:ParalelBilgi.adim_sayisi = $phAdim
        $script:AktifAdim = ''
        Paralel-Kalp 'adım bitti'
        Start-Sleep -Seconds 2
    }
} catch {
    $phNeden = 'hata: ' + $_.Exception.Message
    Gunluk ("Paralel hat (görev {0}) hata: {1} @ {2}" -f $phId, $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) 'HATA'
} finally {
    try {
        $phG = Gorev-Diskten $phId
        if ($phG) {
            Gecmis-Ekle $phG 'paralel çalışma bitti' ('{0}, {1} adım; {2}' -f (Calisan-Adi $Kim), $phAdim, $phNeden)
            Gorev-Kaydet $phG
        }
    } catch { Gunluk "Paralel hat (görev $phId) bitiş kaydı yazılamadı: $($_.Exception.Message)" 'UYARI' }
    try { $phDf = Paralel-Durdur-Dosyasi $phId; if (Test-Path -LiteralPath $phDf) { Remove-Item -LiteralPath $phDf -Force } } catch {}
    $script:ParalelBilgi = $null
    Paralel-Kaydi-Sil $phId
    Gorev-Kilidi-Birak $phKilit
    Gunluk "Paralel hat bitti: görev $phId, $phAdim adım ($phNeden)"
}
