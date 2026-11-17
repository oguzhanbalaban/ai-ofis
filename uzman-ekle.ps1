<#
uzman-ekle.ps1 - Ekibe uzman işi ekler: tasarım, çizim, arayüz, mimari, güvenlik denetimi, e-posta/iletişim, işe alım…
Yönetici işi kadrodaki uygun çalışana verir; uygun kimse yoksa İnsan Kaynakları yeni bir çalışan işe alır.

Örnekler:
  .\uzman-ekle.ps1 -Baslik "Tilki karakteri" -Aciklama "2D platform oyunu için ana karakter: karakter sayfası ve 4 poz" -Rol tasarimci-grafik
  .\uzman-ekle.ps1 -Baslik "Kese uygulaması arayüzü" -Aciklama "Gelir-gider uygulamasının mobil ekranları" -Rol tasarimci-ui
  .\uzman-ekle.ps1 -Baslik "Gelen kutusu özeti" -Aciklama "Son 2 günün önemli e-postalarını özetle, bana bildir" -Rol iletisim
  .\uzman-ekle.ps1 -Baslik "Seslendirme uzmanı" -Aciklama "Oyun için ses efekti ve müzik hazırlayacak birini işe al" -Rol ik

  -Rol     kadro.json'daki çalışanın anahtarı (boşsa yönetici seçer)
  -Klasor  işle ilgili, çalışanın okuyacağı klasör (ör. bir proje)
#>
param(
    [Parameter(Mandatory)][string]$Baslik,
    [Parameter(Mandatory)][string]$Aciklama,
    [string]$Rol = '',
    [string]$Klasor = '',
    [string[]]$Kabul = @(),
    [string[]]$Dogrulama = @(),
    [ValidateRange(1, 3)][int]$Oncelik = 2,
    [ValidateRange(0, 10)][int]$MaxTur = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle

$kadro = Json-Oku (Join-Path $Kok 'kadro.json')
$uye = $null
if ($Rol) {
    foreach ($u in @($kadro.uyeler)) { if ($u -and [string]$u.anahtar -eq $Rol) { $uye = $u } }
    if (-not $uye) { throw "Kadroda böyle bir çalışan yok: '$Rol'. Geçerli anahtarlar: $(@($kadro.uyeler | Where-Object { $_.uzman_isi } | ForEach-Object { $_.anahtar }) -join ', ')" }
}
if ($Klasor) {
    if (-not (Test-Path -LiteralPath $Klasor -PathType Container)) { throw "Klasör bulunamadı: $Klasor" }
    $Klasor = (Resolve-Path -LiteralPath $Klasor).Path.TrimEnd('\')
}

$numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
$no = 1
if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 }
$id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
$gk = Gorev-Klasoru $id
New-Item -ItemType Directory -Force $gk | Out-Null

$kime = '(yönetici seçer)'; if ($uye) { $kime = "$($uye.ad) ($Rol)" }
$kabulMetni = '- (belirtilmedi; yönetici brifte ölçüt belirlesin)'
if ($Kabul.Count -gt 0) { $kabulMetni = ($Kabul | ForEach-Object { "- $_" }) -join "`n" }
$ilgili = ''; if ($Klasor) { $ilgili = "`n- İlgili klasör: ``$Klasor``" }
$md = @"
# $Baslik

- Tür: uzman işi
- İstenen çalışan: $kime$ilgili
- Öncelik: $Oncelik
- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))

## Açıklama

$Aciklama

## Kabul ölçütleri

$kabulMetni

## Notlar ve yanıtlar

(Yönetici soru sorarsa yanıtlarını buraya yazıp dosyayı kaydet; ekip kendiliğinden devam eder.)
"@
Metin-Yaz (Join-Path $gk 'gorev.md') $md

$maxTur = [int]$Ayar.gorev.max_tur
if ($MaxTur -gt 0) { $maxTur = $MaxTur }
$durum = [pscustomobject]@{
    id = $id; baslik = $Baslik; tip = 'uzman'; proje = 'uzman'; klasor = ''; hedef_rol = $Rol; kaynak_klasor = $Klasor; oncelik = $Oncelik
    asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; dogrulama = @($Dogrulama | Where-Object { $_ })
    olusturma = (Simdi); guncelleme = (Simdi); gecmis = @()
}
Json-Yaz $durum (Join-Path $gk 'durum.json')
Gunluk "Uzman işi eklendi: $id (çalışan: $kime)"
Write-Host "İş eklendi: $id"
Write-Host "Klasör: $gk"
