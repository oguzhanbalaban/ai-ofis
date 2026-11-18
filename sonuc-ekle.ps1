<#
sonuc-ekle.ps1 - Yerel teslimde (köprü yokken) onaylı POC'un uygulama çıktısını göreve ekler ve puanlamaya alır.

  .\sonuc-ekle.ps1 -Id 0003 -Dosya "C:\Projeler\Oyun\uygulama-raporu.md"

Dosya UTF-8 Markdown olmalı: uygulama özeti, diff/commit bilgisi, test sonuçları ve eksik kanıtlar. Kod yazmaz, komut çalıştırmaz.
#>
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Dosya
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
Ayarlari-Yukle
if (-not (Test-Path -LiteralPath $Dosya -PathType Leaf)) { throw "Çıktı dosyası bulunamadı: $Dosya" }
$metin = Metin-Oku (Resolve-Path -LiteralPath $Dosya).Path
if (-not $metin.Trim()) { throw 'Uygulama çıktısı boş olamaz.' }
$d = Get-ChildItem -LiteralPath $YolGorev -Directory | Where-Object { $_.Name -eq $Id -or $_.Name -like "$Id-*" } | Select-Object -First 1
if (-not $d) { throw "Görev bulunamadı: $Id" }
# Döngü ya da paralel hat bu işi yürütürken yazma (görev kilidi)
$kilit = Gorev-Kilidi-Al $d.Name
if (-not $kilit) { throw 'Görev şu an işleniyor; biraz sonra yeniden dene.' }
try {
    $g = Gorev-Oku $d.Name
    if (-not $g -or [string]$g.asama -ne 'bekleme' -or [string]$g.teslim_turu -ne 'yerel') {
        throw 'Yalnızca yerel teslimi bekleyen göreve çıktı eklenebilir.'
    }
    Metin-Yaz (Join-Path (Gorev-Klasoru $g.id) 'uygulama-ciktisi.md') $metin
    $k = [ordered]@{ zaman = (Simdi); asama = 'bekleme'; tur = $g.tur; olay = 'yerel uygulama çıktısı eklendi'; ayrinti = (Split-Path -Leaf $Dosya) }
    Ayarla $g 'gecmis' (@($g.gecmis | Where-Object { $_ }) + ([pscustomobject]$k))
    $g.asama = 'puanlama'; $g.deneme = 0
    Ayarla $g 'son_hata' ''
    Ayarla $g 'sonraki_deneme' $null
    Gorev-Kaydet $g
    Gunluk "Görev $($g.id): yerel uygulama çıktısı eklendi, puanlamaya alındı"
    Write-Output $g
} finally { Gorev-Kilidi-Birak $kilit }
