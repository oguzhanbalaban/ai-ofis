<#
gorev-ekle.ps1 - Ekibe yeni görev ekler. Ekip en geç birkaç dakika içinde görevi alır.

Örnekler:
  .\gorev-ekle.ps1 -Proje C:\Projeler\Uygulama -Baslik "Yüzde işlevi" -Aciklama "hesap.js'e yuzde() ekle" -Kabul "node --test geçer"
  .\gorev-ekle.ps1 -Proje C:\Projeler\Uygulama -Baslik "..." -Aciklama "..." -Dogrulama "dotnet build -c Release" -Oncelik 1

  -Proje      projeler.json'daki ad ya da bir git deposunun klasörü (yeni klasörler otomatik kaydedilir)
  -Kabul      kabul ölçütleri (birden çok: "a","b")
  -Dogrulama  bu göreve özel kontrol komutları (projenin komutlarına eklenir)
  -Oncelik    1 = en acil, 3 = düşük (varsayılan 2)
#>
param(
    [Parameter(Mandatory)][string]$Proje,
    [Parameter(Mandatory)][string]$Baslik,
    [Parameter(Mandatory)][string]$Aciklama,
    [string[]]$Kabul = @(),
    [string[]]$Dogrulama = @(),
    [ValidateRange(1, 3)][int]$Oncelik = 2,
    [ValidateRange(0, 10)][int]$MaxTur = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle

$p = Proje-Bul $Proje
if (-not $p) {
    if (-not (Test-Path -LiteralPath $Proje -PathType Container)) { throw "Proje bulunamadı: '$Proje'. projeler.json'daki bir ad ya da var olan bir klasör ver." }
    $klasor = (Resolve-Path -LiteralPath $Proje).Path.TrimEnd('\')
    $pj = Projeleri-Yukle
    $p = [pscustomobject]@{ ad = (Split-Path $klasor -Leaf); klasor = $klasor; temel_dal = ''; dogrulama = @() }
    $pj.projeler = @($pj.projeler) + $p
    Json-Yaz $pj (Join-Path $Kok 'projeler.json')
    Write-Host "Yeni proje kaydedildi: $($p.ad) ($klasor). Test/derleme komutlarını projeler.json > dogrulama'ya ekleyebilirsin."
}
Git-Calistir $p.klasor @('rev-parse', '--show-toplevel') -Sessiz | Out-Null
if ($script:GitKod -ne 0) { throw "Proje bir git deposu değil: $($p.klasor). Ekip yalnızca git depolarında, ayrı bir dalda çalışır." }

$numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
$no = 1
if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 }   # Measure-Object double döndürür; {0:D4} tamsayı ister
$id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
$gk = Gorev-Klasoru $id
New-Item -ItemType Directory -Force $gk | Out-Null

$kabulMetni = '- (belirtilmedi; lider planda test edilebilir ölçütler belirlesin)'
if ($Kabul.Count -gt 0) { $kabulMetni = ($Kabul | ForEach-Object { "- $_" }) -join "`n" }
$md = @"
# $Baslik

- Proje: $($p.ad) (``$($p.klasor)``)
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
    id = $id; baslik = $Baslik; proje = $p.ad; klasor = $p.klasor; oncelik = $Oncelik
    asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; dogrulama = @($Dogrulama)
    olusturma = (Simdi); guncelleme = (Simdi); gecmis = @()
}
Json-Yaz $durum (Join-Path $gk 'durum.json')
Gunluk "Görev eklendi: $id ($($p.ad))"
Write-Host "Görev eklendi: $id"
Write-Host "Klasör: $gk"
