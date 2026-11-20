<#
kanit-siniri.test.ps1 - Otomatik kontrolün değişen dosya sınırını sınar: kanıt klasörlerindeki dosyalar (ayarlar.json >
gorev.kanit_klasorleri, ayar yoksa cikti/) kendi sınırıyla (gorev.max_kanit_dosya, ayar yoksa 300, 0 = sınırsız) ayrı sayılır;
kapsam taşması sınırı (gorev.max_degisen_dosya) yalnızca kod ve öbür dosyalara uygulanır. Kanıt klasörüne taşınan kod dosyası eski
yolundan da sayılır; inceleme diff'inde kod önce gelir. Yazılım ekibi (ekip.ps1 > Adim-Kontrol) ve Outsource Consultant
(danisman.ps1 > Danisman-Kontrol) aynı kuralı kullanır. Çevrimdışıdır: hiçbir ajan çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\kanit-siniri.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-kanit-siniri-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
Copy-Item -LiteralPath (Join-Path $Kaynak 'kadro.json') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
# Kaynağın değerleri ne olursa olsun bilinen değerlerle sına; kanıt ayarları silinir ki varsayılanlar da sınansın
$ayarJ.gorev.max_degisen_dosya = 60
$ayarJ.gorev.max_tur = 3
foreach ($a in 'max_kanit_dosya', 'kanit_klasorleri') { if ($ayarJ.gorev.PSObject.Properties[$a]) { $ayarJ.gorev.PSObject.Properties.Remove($a) } }
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @() }) | ConvertTo-Json -Depth 5), $bom)

. (Join-Path $kum 'ortak.ps1')
. (Join-Path $kum 'rapor.ps1')
. (Join-Path $kum 'ekip.ps1')
if ($Kok -ne $kum) { throw "Betikler kum havuzunu değil $Kok klasörünü kullanıyor; test durduruldu" }
Ayarlari-Yukle

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
# Bellekteki ayarın kanıt alanlarını sıfırlar, verilenleri yazar (boş tablo = varsayılanlar)
function Gorev-Ayari([hashtable]$Degerler) {
    foreach ($a in 'max_kanit_dosya', 'kanit_klasorleri') { if ($Ayar.gorev.PSObject.Properties[$a]) { $Ayar.gorev.PSObject.Properties.Remove($a) } }
    foreach ($k in $Degerler.Keys) { $Ayar.gorev | Add-Member -Force -NotePropertyName $k -NotePropertyValue $Degerler[$k] }
}
function Yollar([string]$On, [int]$Adet) { return @(1..$Adet | ForEach-Object { '{0}{1:000}.md' -f $On, $_ }) }
function Liste-Satirlari([string]$Rapor) { return @(($Rapor -split "\r?\n") | Where-Object { $_ -like '- *' }) }
function G([string]$Klasor) {
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = (& git -c core.autocrlf=false -c core.quotepath=off -C $Klasor @args 2>&1 | Out-String) } finally { $ErrorActionPreference = $eap }
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') başarısız: $o" }
    return $o
}
# Tabanı commit'lenmiş bir depo: src\ altında kod, cikti\ altında eski bir kanıt
function Depo-Kur([string]$Ad, [int]$KodAdet) {
    $d = Join-Path $kum $Ad
    New-Item -ItemType Directory -Force (Join-Path $d 'src'), (Join-Path $d 'cikti') | Out-Null
    G $d init -q | Out-Null
    foreach ($i in 1..$KodAdet) { [IO.File]::WriteAllText((Join-Path $d ('src\m{0:000}.py' -f $i)), "x = $i`n", $utf8) }
    [IO.File]::WriteAllText((Join-Path $d 'cikti\eski.md'), "eski`n", $utf8)
    G $d add -A | Out-Null
    G $d -c user.name=test -c user.email=test@localhost commit -q -m taban | Out-Null
    return $d
}
function Dosyalar-Yaz([string]$Klasor, [string]$On, [int]$Adet) {
    foreach ($i in 1..$Adet) { [IO.File]::WriteAllText((Join-Path $Klasor ('{0}{1:000}.md' -f $On, $i)), "içerik $i`n", $utf8) }
}
function Gorev-Nesnesi([string]$Id, [string]$Klasor) {
    return [pscustomobject]@{ id = $Id; baslik = "Deneme $Id"; tip = 'yazilim'; proje = ''; asama = 'kontrol'; tur = 1; max_tur = 3; deneme = 0
        calisma_klasoru = $Klasor; dogrulama = $null; qa_testi = $false; gecmis = @() }
}
function Kontrol-Raporu($G, [int]$Tur) { return [IO.File]::ReadAllText((Join-Path (Gorev-Klasoru $G.id) "tur$Tur\kontrol.md"), $bom) }

try {
    Write-Host ''; Write-Host 'K1: varsayılanlar (kanıt klasörü cikti/, kanıt sınırı 300)'
    $r = Dosya-Siniri-Denetle (@('host/tests/test_a.py') + (Yollar 'cikti/kanit-' 150))
    Dogrula '1 kod + 150 kanıt: sorun yok' ($r.sorunlar.Count -eq 0) ($r.sorunlar -join ' | ')
    Dogrula 'sayımlar: kod 1, kanıt 150, toplam 151' ($r.kod.Count -eq 1 -and $r.kanit.Count -eq 150 -and $r.toplam -eq 151) "kod $($r.kod.Count), kanıt $($r.kanit.Count), toplam $($r.toplam)"
    Dogrula 'rapor: başlık ve iki sınırlı sayım satırı' ($r.rapor.Contains('### Değişen dosyalar (151)') -and $r.rapor.Contains('Kod ve öbür dosyalar: 1 / 60 · kanıt (cikti/): 150 / 300'))
    $l = Liste-Satirlari $r.rapor
    Dogrula 'liste: önce kod dosyası, 40 satır + kalan sayısı' ($l[0] -eq '- host/tests/test_a.py' -and $l.Count -eq 41 -and $l[-1] -eq '- … ve 111 dosya daha') "$($l.Count) satır; ilk: $($l[0]); son: $($l[-1])"
    $r = Dosya-Siniri-Denetle (Yollar 'src/m' 61)
    Dogrula '61 kod dosyası: kapsam taşması' ($r.sorunlar.Count -eq 1 -and $r.sorunlar[0] -eq 'Çok fazla dosya değişmiş (61 kod ve öbür dosya, sınır 60); kapsam taşmış olabilir.') ($r.sorunlar -join ' | ')
    $r = Dosya-Siniri-Denetle ((Yollar 'src/m' 60) + (Yollar 'cikti/k' 300))
    Dogrula 'tam sınırda (60 kod + 300 kanıt): sorun yok' ($r.sorunlar.Count -eq 0) ($r.sorunlar -join ' | ')
    $r = Dosya-Siniri-Denetle (Yollar 'cikti/k' 301)
    Dogrula '301 kanıt: yalnızca kanıt sınırı aşılır' ($r.sorunlar.Count -eq 1 -and $r.sorunlar[0] -like 'Çok fazla kanıt dosyası değişmiş (301, sınır 300; cikti/)*') ($r.sorunlar -join ' | ')

    Write-Host ''; Write-Host 'K2: hangi yol kanıt sayılır'
    $durumlar = [ordered]@{ 'cikti/a.md' = $true; 'CIKTI/Rapor.md' = $true; '"cikti/a b.md"' = $true; 'cikti\alt\x.md' = $true; '/cikti/x.md' = $true
        'host/cikti/x.md' = $false; 'ciktilar/x.md' = $false; 'cikti' = $false; 'src/cikti.py' = $false }
    $yanlis = @($durumlar.Keys | Where-Object { (Kanit-Dosyasi-mi $_ @('cikti/')) -ne $durumlar[$_] })
    Dogrula 'yalnızca kökteki cikti/ (büyük/küçük harf, tırnak, ters bölü)' ($yanlis.Count -eq 0) ($yanlis -join ', ')

    Write-Host ''; Write-Host 'K3: ayarlar'
    Gorev-Ayari @{ max_kanit_dosya = 0 }
    $r = Dosya-Siniri-Denetle (Yollar 'cikti/k' 1000)
    Dogrula 'max_kanit_dosya 0: kanıt sınırsız' ($r.sorunlar.Count -eq 0 -and $r.rapor.Contains('1000 / sınırsız')) ($r.sorunlar -join ' | ')
    Gorev-Ayari @{ kanit_klasorleri = @() }
    $r = Dosya-Siniri-Denetle (@('host/a.py') + (Yollar 'cikti/k' 150))
    Dogrula 'kanit_klasorleri boş: eski davranış, 151 dosya kapsam sınırına sayılır' ($r.kod.Count -eq 151 -and $r.sorunlar.Count -eq 1 -and $r.rapor.Contains('kanıt klasörü tanımlı değil')) ($r.sorunlar -join ' | ')
    Gorev-Ayari @{ kanit_klasorleri = @('kanit\', '/docs/rapor', ' '); max_kanit_dosya = 5 }
    Dogrula 'klasör adları düzgünleşir' ((@(Kanit-Klasorleri) -join ',') -eq 'kanit/,docs/rapor/') (@(Kanit-Klasorleri) -join ',')
    $r = Dosya-Siniri-Denetle @('kanit/a.md', 'docs/rapor/b.md', 'docs/c.md', 'cikti/d.md')
    Dogrula 'özel klasörler: cikti/ artık kod sayılır' ($r.kanit.Count -eq 2 -and $r.kod.Count -eq 2 -and $r.rapor.Contains('kanıt (kanit/, docs/rapor/): 2 / 5')) "kod $($r.kod.Count), kanıt $($r.kanit.Count)"
    Gorev-Ayari @{}
    Dogrula 'ayar yoksa varsayılan: cikti/' ((@(Kanit-Klasorleri) -join ',') -eq 'cikti/')

    Write-Host ''; Write-Host 'K4: inceleme diffinde kod önce'
    $p1 = "diff --git a/cikti/a.md b/cikti/a.md`nnew file mode 100644`n--- /dev/null`n+++ b/cikti/a.md`n@@ -0,0 +1 @@`n+kanıt`n"
    $p2 = "diff --git a/host/x.py b/host/x.py`n--- a/host/x.py`n+++ b/host/x.py`n@@ -1 +1 @@`n-a`n+b`n"
    $p3 = "diff --git `"a/cikti/b c.md`" `"b/cikti/b c.md`"`n+y`n"
    Dogrula 'kod parçası öne, kanıtlar kendi sırasıyla arkaya, içerik aynı' ((Diff-Kod-Once ($p1 + $p3 + $p2)) -ceq ($p2 + $p1 + $p3))
    Dogrula 'kanıt yoksa ve boşsa diff değişmez' ((Diff-Kod-Once $p2) -ceq $p2 -and (Diff-Kod-Once '') -eq '')

    Write-Host ''; Write-Host 'K5: yazılım ekibinin otomatik kontrolü (Adim-Kontrol, gerçek git)'
    $d1 = Depo-Kur 'depo-a' 3
    [IO.File]::WriteAllText((Join-Path $d1 'src\m001.py'), "x = 100`n", $utf8)
    Dosyalar-Yaz $d1 'cikti\kanit-' 70
    $g1 = Gorev-Nesnesi '0901-kanit-cok' $d1
    Adim-Kontrol $g1
    Dogrula '1 kod + 70 kanıt: geçer (eskiden 71 > 60 diye kalırdı)' ($g1.son_kontrol -eq 'GEÇTİ' -and $g1.asama -eq 'denetim') "$($g1.asama) / $($g1.son_kontrol)"
    Dogrula 'kontrol raporunda ayrı sayım' ((Kontrol-Raporu $g1 1).Contains('Kod ve öbür dosyalar: 1 / 60 · kanıt (cikti/): 70 / 300'))
    $df = Diff-Hazirla $g1
    $ham = [IO.File]::ReadAllText((Join-Path (Tur-Klasoru $g1) 'degisiklik.diff'), $bom)
    Dogrula 'inceleme diffi kodla başlar; dosyadaki ham diff git sırasında kalır' ($df.diff.StartsWith('diff --git a/src/m001.py') -and $ham.StartsWith('diff --git a/cikti/')) (($df.diff -split "`n")[0])

    $d2 = Depo-Kur 'depo-b' 61
    G $d2 mv src cikti/src | Out-Null
    $g2 = Gorev-Nesnesi '0902-kod-kanita-tasindi' $d2
    Adim-Kontrol $g2
    Dogrula 'kanıt klasörüne taşınan 61 kod dosyası eski yolundan sayılır: KALDI, yeni tur' ($g2.son_kontrol -eq 'KALDI' -and $g2.asama -eq 'gelistirme' -and [int]$g2.tur -eq 2) "$($g2.asama) / $($g2.son_kontrol) / tur $($g2.tur)"
    Dogrula 'sorun metni: 61 kod ve öbür dosya' ((Kontrol-Raporu $g2 1).Contains('Çok fazla dosya değişmiş (61 kod ve öbür dosya, sınır 60)'))

    Write-Host ''; Write-Host 'K6: Outsource Consultant kontrolü (Danisman-Kontrol, git kipi)'
    $d3 = Depo-Kur 'depo-c' 2
    Dosyalar-Yaz $d3 'cikti\rapor-' 80
    $g3 = Gorev-Nesnesi '0903-danisman-kanit' $d3; Ayarla $g3 'danisman_mod' 'git'
    Danisman-Kontrol $g3
    Dogrula '80 kanıt dosyası: geçer, tamamlamaya gider' ($g3.son_kontrol -eq 'GEÇTİ' -and $g3.asama -eq 'tamamla') "$($g3.asama) / $($g3.son_kontrol)"
    $d4 = Depo-Kur 'depo-d' 2
    Dosyalar-Yaz $d4 'src\yeni-' 61
    $g4 = Gorev-Nesnesi '0904-danisman-kod' $d4; Ayarla $g4 'danisman_mod' 'git'
    Danisman-Kontrol $g4
    Dogrula '61 yeni kod dosyası: kapsam taşması, KALDI' ($g4.son_kontrol -eq 'KALDI' -and (Kontrol-Raporu $g4 1).Contains('61 kod ve öbür dosya, sınır 60')) "$($g4.asama) / $($g4.son_kontrol)"

    Write-Host ''; Write-Host 'K7: eski sayım kalmadı'
    $eski = @('ekip.ps1', 'danisman.ps1' | Where-Object { [IO.File]::ReadAllText((Join-Path $Kaynak $_), $bom) -match '\$dosyalar\.Count -gt \[int\]\$Ayar\.gorev\.max_degisen_dosya' })
    Dogrula 'ekip.ps1 ve danisman.ps1 ortak kuralı kullanır' ($eski.Count -eq 0) ($eski -join ', ')
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "Kum havuzu korundu: $kum" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
