<#
proje-ekle.ps1 - Fikir hattına yeni konu ekler (tip = yaratici). Paneldeki "Yeni konu" formu bunu çağırır.
Konu sırasıyla fikir, eleştiri, POC planı, maliyet ve karardan geçer; onaylanan POC AI Ofis'e (ya da yerel teslime) gider.

  $g = .\proje-ekle.ps1 -Konu "Metin tabanlı macera oyunu" -Alan oyun [-Proje "C:\Projeler\Oyun"] [-Oncelik 1]

  -Proje  POC'un yapılacağı proje adı ya da klasörü (boşsa ayarlar.json > yaratici.varsayilan_proje); ajanlar hedefi değiştiremez.
Çıktı: görev kaydı (nesne); konsola "Konu eklendi: <no>" yazar.
#>
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Konu,
    [string]$Alan = 'genel',
    [string]$Proje = '',
    [ValidateRange(1, 3)][int]$Oncelik = 2
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'yaratici.ps1')
Ayarlari-Yukle
$Konu = $Konu.Trim()
if (-not $Konu) { throw 'Konu boş olamaz.' }
$Alan = ([string]$Alan).Trim(); if (-not $Alan) { $Alan = 'genel' }

# Görev numarası: gorevler\NNNN-<konu> (aynı anda eklenen başka işle çakışırsa sonraki numara)
$id = ''
for ($i = 0; $i -lt 20 -and -not $id; $i++) {
    $numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
    $no = 1; if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 + $i }
    $aday = '{0:D4}-{1}' -f $no, (Slug $Konu)
    $gk = Gorev-Klasoru $aday
    if (-not (Test-Path -LiteralPath $gk)) { New-Item -ItemType Directory -Force $gk | Out-Null; $id = $aday }
}
if (-not $id) { throw 'Yeni görev numarası alınamadı.' }

$maxTur = [int]$Ayar.gorev.max_tur; if ($maxTur -lt 1) { $maxTur = 3 }
$g = [pscustomobject][ordered]@{
    id = $id; baslik = $Konu; tip = 'yaratici'; alan = $Alan; proje = $Proje; klasor = ''; oncelik = $Oncelik
    asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; sonraki_deneme = $null; son_hata = ''; dogrulama = @()
    revizyon = 0; geri_bildirimler = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @()
}
Yaratici-Gorev-Hazirla $g $Alan $Proje
$hedef = '(teslimde varsayılan hedef)'; if ($g.proje) { $hedef = [string]$g.proje }
Metin-Yaz (Join-Path $gk 'gorev.md') (@(
    "# $Konu", '',
    '- Tür: fikir hattı (konu)', "- Alan: $Alan", "- Hedef proje: $hedef", "- Öncelik: $Oncelik", "- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '',
    '## Amaç', '', $Konu, '',
    '## Notlar ve yanıtlar', '',
    '(Ek bilgi vermek istersen buraya yazıp kaydet; fikir hattı sonraki adımlarda okur.)'
) -join "`n")
Json-Yaz $g (Join-Path $gk 'durum.json')
Gunluk "Fikir hattına konu eklendi: $id"
Write-Host "Konu eklendi: $id"
Write-Output $g
