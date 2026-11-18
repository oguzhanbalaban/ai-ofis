<#
kendini-gelistirme.test.ps1 - Ofisin kendi kendini geliştirmesini sınar (kendini.ps1): ayna deposunun kurulması ve proje kaydı,
canlıdan eşitleme, görev dalında değişiklik, canlıya alma (birleştirme, yedek, kopya, ayar dosyalarının dışarıda kalması, doğrulama),
geri alma, bozuk değişikliğin doğrulamada yakalanıp otomatik geri alınması, otomatik kapalıyken onayla canlıya alma, güvenlik ağı.
Gerçek git depolarıyla, kum havuzunda; yapay zeka çağrılmaz, canlı ofise dokunulmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\kendini-gelistirme.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$ust = Join-Path $env:TEMP ('ai-ekip-kendini-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$kum = Join-Path $ust 'ofis'; $ayna = Join-Path $ust 'ofis-kaynak'
New-Item -ItemType Directory -Force $kum, (Join-Path $kum 'ofis') | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"
$env:AIEKIP_KAT = ''
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
Copy-Item -Path (Join-Path $Kaynak 'ofis\*.ps1') -Destination (Join-Path $kum 'ofis')
foreach ($f in @(Get-ChildItem -LiteralPath $kum -Recurse -Filter '*.ps1' -File)) {
    $t = [IO.File]::ReadAllText($f.FullName, $bom); $y = $t.Replace('Local\AIEkip', 'Local\AIEkipKendiniTest')
    if ($y -cne $t) { [IO.File]::WriteAllText($f.FullName, $y, $bom) }
}
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$ayarJ.bildirim.masaustu = $false; $ayarJ.bildirim.telefon = $null
$ayarJ | Add-Member -Force -NotePropertyName kendini_gelistirme -NotePropertyValue ([pscustomobject]@{ etkin = $true; otomatik = $true; kaynak_deposu = $ayna; guvenlik_agi_dk = 60 })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad) [pscustomobject][ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = $true; uzman_isi = $false; yetki = 'oku'; uzmanlik = "$ad işleri" } }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), (([pscustomobject]@{ surum = 1; uyeler = @((& $uye 'lider' 'Engineering Manager'), (& $uye 'gelistirici' 'Full-Stack Developer'), (& $uye 'denetci' 'Code Reviewer')) }) | ConvertTo-Json -Depth 5), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
. (Join-Path $kum 'ortak.ps1')
. (Join-Path $kum 'rapor.ps1')
. (Join-Path $kum 'ekip.ps1')
if ($KodKok -ne $kum) { throw "Betikler kum havuzunu değil $KodKok klasörünü kullanıyor" }
Ayarlari-Yukle

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Oku([string]$Y) { if (Test-Path -LiteralPath $Y) { return [IO.File]::ReadAllText($Y) }; return '' }
function Kendi-Gorevi([string]$Id) {
    $gk = Gorev-Klasoru $Id; New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# $Id`n"
    $g = [pscustomobject][ordered]@{ id = $Id; baslik = "Kendi $Id"; tip = 'yazilim'; proje = 'ai-ekip-ofis'; klasor = $ayna; asama = 'yeni'; tur = 1; max_tur = 3; deneme = 0
        dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @() }
    $h = Calisma-Agaci-Kur $g
    if ($h) { throw "Çalışma ağacı kurulamadı: $h" }
    return $g
}
function Dalda-Degistir($G, [scriptblock]$Is) {
    $wt = [string]$G.calisma_klasoru
    & $Is $wt
    Git-T -C $wt add -A | Out-Null
    Git-T -C $wt -c user.name=t -c user.email=t@t commit -q -m "degisiklik $($G.id)" | Out-Null
    $G.asama = 'canliya_al'
    Gorev-Kaydet $G
}

try {
    Write-Host ''
    Write-Host '1) Ayna depo ve proje kaydı'
    Kendi-Projesi-Hazirla
    $p = Proje-Bul 'ai-ekip-ofis'
    Dogrula 'ayna git deposu main dalında, ilk commit var' ((Test-Path -LiteralPath (Join-Path $ayna '.git')) -and (Git-T -C $ayna symbolic-ref --short HEAD) -eq 'main' -and [int](Git-T -C $ayna rev-list --count HEAD) -ge 1)
    Dogrula 'proje kaydı: kendi, temel dal main, doğrulama komutları' ($p -and $p.kendi -and $p.temel_dal -eq 'main' -and $p.klasor -eq $ayna -and @($p.dogrulama).Count -ge 1 -and @($p.dogrulama)[0] -match 'ofis-duman')
    Dogrula 'aynada kod, istemler, testler için ayar dosyaları ve ajan rehberi var' ((Test-Path (Join-Path $ayna 'ortak.ps1')) -and (Test-Path (Join-Path $ayna 'istemler\lider-plan.md')) -and (Test-Path (Join-Path $ayna 'ayarlar.json')) -and (Oku (Join-Path $ayna 'CLAUDE.md')) -match 'aynasıdır' -and (Oku (Join-Path $ayna 'AGENTS.md')) -match 'BOM')
    Dogrula 'yönlendirme proje tablosu ofisin kendi projesini anlatır' ((Projeler-Metni) -match 'PROJE: ai-ekip-ofis')
    Kendi-Projesi-Hazirla
    Dogrula 'ikinci çağrı yeni kayıt açmaz' (@((Projeleri-Yukle).projeler | Where-Object { $_.kendi }).Count -eq 1)
    Dogrula 'kapsam: kod / istem canlıya alınır, ayar JSON ve rehber alınmaz' ((Canliya-Alinir-mi 'ekip.ps1') -and (Canliya-Alinir-mi 'istemler\kadro\iletisim.md') -and (Canliya-Alinir-mi 'katlar\innovation-lab\istemler\lider-plan.md') -and -not (Canliya-Alinir-mi 'ayarlar.json') -and -not (Canliya-Alinir-mi 'katlar\innovation-lab\kadro.json') -and -not (Canliya-Alinir-mi 'CLAUDE.md'))

    Write-Host ''
    Write-Host '2) Canlıdan eşitleme'
    $once = [int](Git-T -C $ayna rev-list --count HEAD)
    [IO.File]::AppendAllText((Join-Path $kum 'istemler\lider-plan.md'), "`nCANLIDA-EKLENDI`n", $utf8)
    $h = Ofis-Kaynagi-Esitle 'test'
    Dogrula 'canlıdaki değişiklik aynaya commit edildi' ($h -eq '' -and [int](Git-T -C $ayna rev-list --count HEAD) -eq ($once + 1) -and (Oku (Join-Path $ayna 'istemler\lider-plan.md')) -match 'CANLIDA-EKLENDI') $h
    $h = Ofis-Kaynagi-Esitle 'test'
    Dogrula 'değişiklik yokken boş commit açılmaz' ([int](Git-T -C $ayna rev-list --count HEAD) -eq ($once + 1))

    Write-Host ''
    Write-Host '3) Görev dalında değişiklik → canlıya alma'
    $denetciOnce = Oku (Join-Path $kum 'istemler\denetci.md')
    $ayarOnce = Oku (Join-Path $kum 'ayarlar.json')
    $g1 = Kendi-Gorevi '0001-istem'
    Dogrula 'görev ofisin kendi projesi, çalışma ağacı aynanın dalı' ((Kendi-Projesi-mi $g1) -and $g1.dal -eq 'ekip/0001-istem' -and (Test-Path (Join-Path $g1.calisma_klasoru 'ortak.ps1')))
    Dalda-Degistir $g1 { param($wt)
        [IO.File]::AppendAllText((Join-Path $wt 'istemler\denetci.md'), "`nDALDA-EKLENDI`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $wt 'istemler\yeni-istem.md'), "yeni istem`n", $utf8)
        [IO.File]::AppendAllText((Join-Path $wt 'ayarlar.json'), ' ', $utf8) }
    Adim-CanliyaAl $g1; Gorev-Kaydet $g1
    $g1 = Gorev-Oku '0001-istem'
    $k1 = Json-Oku (Canli-Kayit-Yolu)
    Dogrula 'görev tamam; canlıda' ($g1.asama -eq 'tamam' -and $g1.canliya_alim.durum -eq 'canlida') "$($g1.asama) $(Kisalt ([string]$g1.son_hata) 200)"
    Dogrula 'değişen ve yeni istem canlıda; ayar dosyası canlıya alınmadı' ((Oku (Join-Path $kum 'istemler\denetci.md')) -match 'DALDA-EKLENDI' -and (Test-Path (Join-Path $kum 'istemler\yeni-istem.md')) -and (Oku (Join-Path $kum 'ayarlar.json')) -ceq $ayarOnce -and @($k1.atlanan) -contains 'ayarlar.json')
    Dogrula 'yedek: değişen dosyanın eski hali ve kayıt' ((Oku (Join-Path $k1.yedek 'istemler\denetci.md')) -ceq $denetciOnce -and (Test-Path (Join-Path $k1.yedek 'canliya-alim.json')) -and @($k1.eklenen) -contains 'istemler\yeni-istem.md')
    Dogrula 'ayna main birleştirmeyi içerir; doğrulama raporu yazıldı' ((Git-T -C $ayna log -1 --format=%s) -match 'Canlıya: #0001-istem' -and $k1.dogrulama -match 'Kat yüklendi: ana' -and (Test-Path (Join-Path (Gorev-Klasoru '0001-istem') 'canliya-alim.md')))

    Write-Host ''
    Write-Host '4) Geri alma (yalnızca son canlıya alma)'
    $h = Canliya-Alimi-Geri-Al '0002' 'test'
    Dogrula 'başka görevin numarasıyla geri alınamaz' ($h -match 'yalnızca en sonuncusu')
    $h = Canliya-Alimi-Geri-Al '0001' 'test'
    $g1 = Gorev-Oku '0001-istem'
    Dogrula 'canlı eski haline döndü, yeni dosya silindi' ($h -eq '' -and (Oku (Join-Path $kum 'istemler\denetci.md')) -ceq $denetciOnce -and -not (Test-Path (Join-Path $kum 'istemler\yeni-istem.md'))) $h
    Dogrula 'ayna geri alma commit''i; görev kaydı geri alındı' ((Oku (Join-Path $ayna 'istemler\denetci.md')) -notmatch 'DALDA-EKLENDI' -and $g1.canliya_alim.durum -eq 'geri_alindi' -and (Json-Oku (Canli-Kayit-Yolu)).geri_alindi)
    Dogrula 'ikinci geri alma yapılmaz' ((Canliya-Alimi-Geri-Al '' 'test') -match 'yok')

    Write-Host ''
    Write-Host '5) Bozuk değişiklik doğrulamada yakalanır, geri alınır'
    $raporOnce = Oku (Join-Path $kum 'rapor.ps1')
    $basOnce = Git-T -C $ayna rev-parse HEAD
    $g2 = Kendi-Gorevi '0002-bozuk'
    Dalda-Degistir $g2 { param($wt) [IO.File]::AppendAllText((Join-Path $wt 'rapor.ps1'), "`r`nfunction Bozuk-Islev {`r`n    if (`$true) {`r`n", $utf8) }
    Adim-CanliyaAl $g2; Gorev-Kaydet $g2
    $g2 = Gorev-Oku '0002-bozuk'
    Dogrula 'görev takıldı, neden doğrulama' ($g2.asama -eq 'takildi' -and [string]$g2.son_hata -match 'doğrulamadan geçmedi' -and $g2.canliya_alim.durum -eq 'geri_alindi') "$($g2.asama)"
    Dogrula 'canlı betik eski haliyle, ayna eski commit''te' ((Oku (Join-Path $kum 'rapor.ps1')) -ceq $raporOnce -and (Git-T -C $ayna rev-parse HEAD) -eq $basOnce)

    Write-Host ''
    Write-Host '6) Otomatik kapalı: onayla canlıya alma'
    $ayarJ.kendini_gelistirme.otomatik = $false
    [IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom); Ayarlari-Yukle
    $g3 = Kendi-Gorevi '0003-onay'
    Dalda-Degistir $g3 { param($wt) [IO.File]::AppendAllText((Join-Path $wt 'istemler\denetci.md'), "`nONAYLI`n", $utf8) }
    Adim-CanliyaAl $g3; Gorev-Kaydet $g3
    $g3 = Gorev-Oku '0003-onay'
    Dogrula 'otomatik kapalı: görev tamam, canlıya alma bekliyor, canlı değişmedi' ($g3.asama -eq 'tamam' -and $g3.canliya_alim.durum -eq 'bekliyor' -and (Oku (Join-Path $kum 'istemler\denetci.md')) -notmatch 'ONAYLI')
    $c = & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $kum 'durum.ps1') -CanliyaAl 0003 2>&1 | Out-String
    $g3 = Gorev-Oku '0003-onay'
    Dogrula 'durum.ps1 -CanliyaAl onayı: aşama canliya_al' ($g3.asama -eq 'canliya_al' -and $g3.canliya_al_onaylandi) (Kisalt $c 200)
    Adim-CanliyaAl $g3; Gorev-Kaydet $g3
    $g3 = Gorev-Oku '0003-onay'
    Dogrula 'onaydan sonra canlıya alındı' ($g3.asama -eq 'tamam' -and $g3.canliya_alim.durum -eq 'canlida' -and (Oku (Join-Path $kum 'istemler\denetci.md')) -match 'ONAYLI')

    Write-Host ''
    Write-Host '7) Güvenlik ağı'
    Dogrula 'iki hata geri almaz' (-not (Canliya-Alim-Guvenlik-Agi 2) -and (Oku (Join-Path $kum 'istemler\denetci.md')) -match 'ONAYLI')
    Dogrula 'üst üste üç hata son canlıya almayı geri alır' ((Canliya-Alim-Guvenlik-Agi 3) -and (Oku (Join-Path $kum 'istemler\denetci.md')) -notmatch 'ONAYLI')
    Dogrula 'geri alınmış canlıya alma için ağ yeniden tetiklenmez' (-not (Canliya-Alim-Guvenlik-Agi 5))
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) {
        try { Get-ChildItem -LiteralPath (Join-Path $kum 'calisma') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Git-T -C $ayna worktree remove --force $_.FullName | Out-Null } } catch {}
        Remove-Item -LiteralPath $ust -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host "Kum havuzu korundu: $ust" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
