<#
durum.ps1 - AI Ekip'in anlık durumu ve görev yönetimi.

  .\durum.ps1                       durum özeti
  .\durum.ps1 -Ac                   HTML raporu tarayıcıda aç
  .\durum.ps1 -Devam 0003           takılan/bekleyen görevi sürdür (gerekirse bir tur hakkı daha verir)
  .\durum.ps1 -Devam 0003 -Not "..."  sürdürürken Software Developerʼa kendi notunu ekle
  .\durum.ps1 -Iptal 0003           görevi iptal et (dal ve dosyalar silinmez)
  .\durum.ps1 -Duraklat / -Surdur   tüm ekibi duraklat / sürdür (DURDUR dosyası)
  .\durum.ps1 -KilitleriSifirla     araç kilitlerini kaldır (ör. "claude auth login" yaptıktan sonra)
#>
param([string]$Devam, [string]$Not, [string]$Iptal, [switch]$Ac, [switch]$Duraklat, [switch]$Surdur, [switch]$KilitleriSifirla)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ortak.ps1')
. (Join-Path $PSScriptRoot 'rapor.ps1')
. (Join-Path $PSScriptRoot 'ekip.ps1')
Ayarlari-Yukle

function Gorev-Bul([string]$Kisa) {
    $d = Get-ChildItem -LiteralPath $YolGorev -Directory | Where-Object { $_.Name -eq $Kisa -or $_.Name -like "$Kisa-*" } | Select-Object -First 1
    if (-not $d) { throw "Görev bulunamadı: $Kisa" }
    return (Gorev-Oku $d.Name)
}

$durdurDosyasi = Join-Path $Kok 'DURDUR'
if ($Duraklat) { Metin-Yaz $durdurDosyasi "Ekip $((Get-Date).ToString('dd.MM.yyyy HH:mm'))'de duraklatıldı.`n"; Write-Host 'Ekip duraklatıldı (çalışan adım bitince bekler).' }
if ($Surdur -and (Test-Path -LiteralPath $durdurDosyasi)) { Remove-Item -LiteralPath $durdurDosyasi -Force; Write-Host 'Ekip sürdürülüyor.' }
if ($KilitleriSifirla) { Json-Yaz (New-Object psobject) (Join-Path $YolDurum 'kilitler.json'); Write-Host 'Araç kilitleri kaldırıldı; ekip bir sonraki adımda tüm araçları yeniden dener.' }

if ($Devam) {
    $g = Gorev-Bul $Devam
    # Ortak sürdürme mantığı (cozucu.ps1 > Gorev-Surdur): soru bekliyorsa yeniden plan; tur sınırına takıldıysa bir tur
    # daha; değilse takıldığı aşamadan. Kullanıcının "Devam" demesi Incident Managerʼın hakkını da sıfırlar.
    Gorev-Surdur $g $Not 'kullanıcı' 'Kullanıcının notu'
    Gorev-Kaydet $g
    Write-Host "Görev $($g.id) sürdürülüyor: $(Asama-Adi $g.asama) (tur $($g.tur)/$($g.max_tur))"
}
if ($Iptal) {
    $g = Gorev-Bul $Iptal
    Gecmis-Ekle $g 'kullanıcı iptal etti'
    $g.asama = 'iptal'
    Gorev-Kaydet $g
    Write-Host "Görev $($g.id) iptal edildi. Dal ($($g.dal)) ve çalışma klasörü yerinde duruyor."
}

Rapor-Uret
if ($Ac) { Start-Process (Join-Path $YolRapor 'son-rapor.html') }

# ---- özet
$k = Json-Oku (Join-Path $YolDurum 'kalp.json')
$dongu = 'çalışmıyor'
if ($k -and $k.zaman) {
    $dk = [int]((Get-Date) - [datetime]$k.zaman).TotalMinutes
    $canli = $false
    if ($k.pid) { $canli = [bool](Get-Process -Id ([int]$k.pid) -ErrorAction SilentlyContinue) }
    $dongu = '{0} ({1} dk önce, PID {2}{3})' -f $k.durum, $dk, $k.pid, $(if ($canli) { '' } else { ', süreç yok' })
}
Write-Host ''
Write-Host "AI Ekip - $((Get-Date).ToString('dd.MM.yyyy HH:mm'))"
Write-Host "Döngü   : $dongu"
if (Test-Path -LiteralPath $durdurDosyasi) { Write-Host 'DURUM   : DURAKLATILDI (durum.ps1 -Surdur ile sürdür)' }
Write-Host "Ekip    : $(Ekip-Durumu-Kisa)"
$s = Sayac-Oku
Write-Host ("Bugün   : {0} tamamlandı, {1} takıldı | Claude {2}/{3}, Codex {4}/{5} çağrı" -f [int]$s.tamamlanan, [int]$s.takilan, [int]$s.claude, $Ayar.gunluk_sinir.claude, [int]$s.codex, $Ayar.gunluk_sinir.codex)
$kl = Kilit-Oku
foreach ($p in $kl.PSObject.Properties) {
    if ($p.Value -and ([datetime]$p.Value.bitis) -gt (Get-Date)) { Write-Host ("Kısıt   : {0} -> {1} ({2}'e kadar)" -f $p.Name, $p.Value.neden, ([datetime]$p.Value.bitis).ToString('dd.MM HH:mm')) }
}
Write-Host ''
$liste = @(Gorevleri-Listele)
if ($liste.Count -eq 0) { Write-Host 'Henüz görev yok. Eklemek için: .\gorev-ekle.ps1 -Proje <ad|klasör> -Baslik "..." -Aciklama "..."' }
else {
    $liste | ForEach-Object {
        [pscustomobject]@{ No = $_.id; Durum = (Asama-Adi $_.asama); Tur = ('{0}/{1}' -f $_.tur, $_.max_tur); Dal = $_.dal; Not = (Kisalt ([string]$_.son_hata) 70) }
    } | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
}
Write-Host "Rapor   : $(Join-Path $YolRapor 'son-rapor.html')"
