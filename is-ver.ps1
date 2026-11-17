<#
is-ver.ps1 - Ekibe türünü seçmeden iş verir (paneldeki "İş ver" düğmesi bunu çağırır).
İşi Yönetici alır, okur ve kimin yapacağına kendisi karar verir: yazılım ekibi (proje seçer ya da yeni depo açtırır),
sistem yöneticisi + network (sunucu / kurulum), kadrodan bir uzman ya da İK'nın işe alacağı yeni bir çalışan.

Örnekler:
  .\is-ver.ps1 -Baslik "Kelime oyunu" -Aciklama "Flutter ile Türkçe kelime bulmaca oyunu; 3 oda, kayıt/devam"
  .\is-ver.ps1 -Baslik "LAB-SRV yavaş" -Aciklama "Yönetim konsolunun açılışı 2 dk sürüyor, nedenini bul ve düzelt" -Oncelik 1
  .\is-ver.ps1 -Baslik "Logo" -Aciklama "Uygulamaya logo tasarla" -Ipucu ornek-uygulama -Rol tasarimci-grafik

  -Ipucu   isteğe bağlı: ilgili proje adı ya da klasör (Yönetici dikkate alır)
  -Rol     isteğe bağlı: önerilen çalışanın anahtarı (Yönetici uygun görmezse başkasına verir)
  -Kabul / -Dogrulama / -Oncelik / -MaxTur  gorev-ekle.ps1 ile aynı
#>
param(
    [Parameter(Mandatory)][string]$Baslik,
    [Parameter(Mandatory)][string]$Aciklama,
    [string[]]$Kabul = @(),
    [string[]]$Dogrulama = @(),
    [string]$Ipucu = '',
    [string]$Rol = '',
    [ValidateRange(1, 3)][int]$Oncelik = 2,
    [ValidateRange(0, 10)][int]$MaxTur = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle

$Ipucu = $Ipucu.Trim()
$ipucuMetni = ''
if ($Ipucu) {
    $p = Proje-Bul $Ipucu
    if ($p) { $ipucuMetni = "$($p.ad) (``$($p.klasor)``)" }
    elseif (Test-Path -LiteralPath $Ipucu -PathType Container) { $Ipucu = (Resolve-Path -LiteralPath $Ipucu).Path.TrimEnd('\'); $ipucuMetni = "klasör ``$Ipucu``" }
    else { $ipucuMetni = $Ipucu }
}
$Rol = $Rol.Trim()
$rolMetni = ''
if ($Rol) {
    $kadro = Json-Oku (Join-Path $Kok 'kadro.json')
    $uye = $null
    foreach ($u in @($kadro.uyeler)) { if ($u -and [string]$u.anahtar -eq $Rol) { $uye = $u } }
    if ($uye) { $rolMetni = "$($uye.ad) ($Rol)" } else { $rolMetni = $Rol }
}

$numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
$no = 1
if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 }
$id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
$gk = Gorev-Klasoru $id
New-Item -ItemType Directory -Force $gk | Out-Null

$kabulMetni = '- (belirtilmedi; Yönetici planda test edilebilir ölçütler belirlesin)'
if ($Kabul.Count -gt 0) { $kabulMetni = ($Kabul | ForEach-Object { "- $_" }) -join "`n" }
$satirlar = @("# $Baslik", '', '- Tür: Yönetici yönlendirecek (yazılım, sunucu / kurulum ya da uzman işi)')
if ($ipucuMetni) { $satirlar += "- İlgili proje / klasör (kullanıcının ipucu): $ipucuMetni" }
if ($rolMetni) { $satirlar += "- Önerilen çalışan (kullanıcının ipucu): $rolMetni" }
$satirlar += @(
    "- Öncelik: $Oncelik", "- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '',
    '## Açıklama', '', $Aciklama, '',
    '## Kabul ölçütleri', '', $kabulMetni, '',
    '## Notlar ve yanıtlar', '',
    '(Yönetici soru sorarsa yanıtlarını buraya yazıp dosyayı kaydet; ekip kendiliğinden devam eder.)'
)
Metin-Yaz (Join-Path $gk 'gorev.md') ($satirlar -join "`n")

$maxTur = [int]$Ayar.gorev.max_tur
if ($MaxTur -gt 0) { $maxTur = $MaxTur }
$durum = [pscustomobject]@{
    id = $id; baslik = $Baslik; tip = 'genel'; proje = 'yönetici'; klasor = ''; ipucu = $Ipucu; istenen_rol = $Rol; oncelik = $Oncelik
    asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; dogrulama = @($Dogrulama | Where-Object { $_ })
    olusturma = (Simdi); guncelleme = (Simdi); gecmis = @()
}
Json-Yaz $durum (Join-Path $gk 'durum.json')
Gunluk "İş verildi (Yönetici yönlendirecek): $id"
Write-Host "İş eklendi: $id"
Write-Host "Klasör: $gk"
