<#
talep-ekle.ps1 - Ekibin altyapı çalışanlarına (sistem yöneticisi + network) sunucu / kurulum talebi ekler.
Talep git deposu gerektirmez. Ekip en geç birkaç dakika içinde (genellikle 20 sn) talebi alır.

Örnekler:
  .\talep-ekle.ps1 -Baslik "LAB-SRV servis kontrolü" -Aciklama "LAB-SRV üzerinde servis 6400'de dinlemiyor, düzelt" -Hedef LAB-SRV `
      -Kabul "6400 portu ana makineden açık","CMC açılıyor" `
      -Dogrulama 'powershell -NoProfile -Command "if (-not (Test-NetConnection 192.0.2.10 -Port 6400 -InformationLevel Quiet)) { exit 1 }"'

  -Hedef      ilgili makineler (ayarlar.json > altyapi.makineler adları; boşsa lider belirler)
  -Kabul      kabul ölçütleri (birden çok: "a","b")
  -Dogrulama  ana makinede çalışacak kontrol komutları (cmd.exe; başarısızlıkta 0 dışı kodla çıkmalı)
  -Oncelik    1 = en acil, 3 = düşük (varsayılan 2)
#>
param(
    [Parameter(Mandatory)][string]$Baslik,
    [Parameter(Mandatory)][string]$Aciklama,
    [string[]]$Hedef = @(),
    [string[]]$Kabul = @(),
    [string[]]$Dogrulama = @(),
    [ValidateRange(1, 3)][int]$Oncelik = 2,
    [ValidateRange(0, 10)][int]$MaxTur = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle

$bilinen = @($Ayar.altyapi.makineler | Where-Object { $_ } | ForEach-Object { [string]$_.ad })
$hedefler = @($Hedef | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$tanimsiz = @($hedefler | Where-Object { $bilinen -notcontains $_ })
if ($tanimsiz.Count) { Write-Host "Uyarı: ayarlar.json'da tanımlı olmayan hedef: $($tanimsiz -join ', ') (yine de eklendi)" }

$numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
$no = 1
if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 }
$id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
$gk = Gorev-Klasoru $id
New-Item -ItemType Directory -Force $gk | Out-Null

$hedefMetni = '(belirtilmedi; lider belirlesin)'
if ($hedefler.Count -gt 0) { $hedefMetni = $hedefler -join ', ' }
$kabulMetni = '- (belirtilmedi; lider planda test edilebilir ölçütler belirlesin)'
if ($Kabul.Count -gt 0) { $kabulMetni = ($Kabul | ForEach-Object { "- $_" }) -join "`n" }
$md = @"
# $Baslik

- Tür: sunucu / kurulum talebi (sistem yöneticisi + network)
- Hedef makineler: $hedefMetni
- Öncelik: $Oncelik
- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))

## Açıklama

$Aciklama

## Kabul ölçütleri

$kabulMetni

## Notlar ve yanıtlar

(Lider soru sorarsa yanıtlarını buraya yazıp dosyayı kaydet; ekip kendiliğinden devam eder.)
"@
Metin-Yaz (Join-Path $gk 'gorev.md') $md

$maxTur = [int]$Ayar.gorev.max_tur
if ($MaxTur -gt 0) { $maxTur = $MaxTur }
$durum = [pscustomobject]@{
    id = $id; baslik = $Baslik; tip = 'altyapi'; proje = 'altyapı'; klasor = ''; hedef = @($hedefler); oncelik = $Oncelik
    asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; dogrulama = @($Dogrulama | Where-Object { $_ })
    olusturma = (Simdi); guncelleme = (Simdi); gecmis = @()
}
Json-Yaz $durum (Join-Path $gk 'durum.json')
Gunluk "Talep eklendi: $id (altyapı; hedef: $hedefMetni)"
Write-Host "Talep eklendi: $id"
Write-Host "Klasör: $gk"
