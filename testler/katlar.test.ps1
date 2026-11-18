<#
katlar.test.ps1 - Şirket binasını (katlar) ve katlar arası iletişimi (Comms) sınar: kat çözümü (AIEKIP_KAT, veri kökü, ayar mirası,
kilit adları, unvan uyarlama), Engineering Managerʼın KARAR: KAT yönlendirmesi (Comms brifi, hedef katta görev, yazışma), hedefin
ilerlemesi ve dönüşte Comms raporu, yardım isteğinin başka kattan karşılanması, uygulama katı (API kapalıyken bekleme, iş ve durum),
gönderen iptal edince hedefin geri çekilmesi, geri gönderme yasağı, bina bekçisi ve fikir hattının ana kata POC köprüsü.
Çevrimdışıdır: gerçek Claude / Codex çağrılmaz, uygulama API'si taklit edilir.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\katlar.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-katlar-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"
$env:AIEKIP_KAT = ''

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
# Canlı döngü / görev kilitleriyle karışmasın
foreach ($f in @(Get-ChildItem -LiteralPath $kum -Filter '*.ps1' -File)) {
    $t = [IO.File]::ReadAllText($f.FullName, $bom)
    $y = $t.Replace('Local\AIEkipDongusu', 'Local\AIEkipKatTestDongusu').Replace("'Local\AIEkipGorev'", "'Local\AIEkipKatTestGorev'").Replace('Local\AIEkipGorevNo_', 'Local\AIEkipKatTestGorevNo_')
    if ($y -cne $t) { [IO.File]::WriteAllText($f.FullName, $y, $bom) }
}
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$sahteAjan = Join-Path $kum 'sahte-ajan.cmd'
$ayarJ.claude.exe = $sahteAjan
$ayarJ.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayarJ.zaman_asimi_dk.claude = 5
$ayarJ.gunluk_sinir.claude = 1000
$s = { param($m) [pscustomobject]@{ arac = 'claude'; model = $m } }
$ayarJ.roller = [pscustomobject]@{ lider = @(& $s 'sahte-yonetici'); 'sorun-giderici' = @(& $s 'sahte-cozucu'); gelistirici = @(& $s 'sahte-gelistirici')
    denetci = @(& $s 'sahte-denetci'); sistem = @(& $s 'sahte-sistem'); ag = @(& $s 'sahte-ag'); iletisim = @(& $s 'sahte-comms') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $false; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName planlama -NotePropertyValue ([pscustomobject]@{ analiz = $false; kesif = $false; qa_testi = $false })
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
$ayarJ | Add-Member -Force -NotePropertyName danisman -NotePropertyValue ([pscustomobject]@{ etkin = $false })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $ek) $o = [ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = $true; uzman_isi = $false; yetki = 'oku'; uzmanlik = "$ad işleri" }; foreach ($k in $ek.Keys) { $o[$k] = $ek[$k] }; [pscustomobject]$o }
function Kadro-Yaz([string]$Klasor, $Uyeler) { New-Item -ItemType Directory -Force $Klasor | Out-Null; [IO.File]::WriteAllText((Join-Path $Klasor 'kadro.json'), (([pscustomobject]@{ surum = 1; uyeler = @($Uyeler) }) | ConvertTo-Json -Depth 6), $bom) }
Kadro-Yaz $kum @((& $uye 'lider' 'Engineering Manager' @{}), (& $uye 'sorun-giderici' 'Incident Manager' @{}), (& $uye 'gelistirici' 'Full-Stack Developer' @{ yetki = 'yaz' }),
    (& $uye 'denetci' 'Code Reviewer' @{}), (& $uye 'iletisim' 'Communications Coordinator' @{ uzman_isi = $true; yetki = 'yaz' }))
# Katlar: veri (ekip katı, kendi kadrosu; ayarların çoğunu ana kattan miras alır), fikir (fikir hattı katı), app (uygulama katı)
$veriK = Join-Path $kum 'katlar\veri'; $fikirK = Join-Path $kum 'katlar\fikir'
Kadro-Yaz $veriK @((& $uye 'lider' 'Data Lead' @{ kisa_ad = 'Data Lead' }), (& $uye 'gelistirici' 'Analytics Engineer' @{ yetki = 'yaz' }), (& $uye 'denetci' 'BI Technical Lead' @{}),
    (& $uye 'tester' 'BI QA Engineer' @{}), (& $uye 'iletisim' 'Data Comms' @{ uzman_isi = $true; yetki = 'yaz' }))
[IO.File]::WriteAllText((Join-Path $veriK 'ayarlar.json'), (([pscustomobject]@{ surum = 1; roller = [pscustomobject]@{ lider = @(& $s 'sahte-veri-lider'); iletisim = @(& $s 'sahte-veri-comms') }; gorev = [pscustomobject]@{ max_tur = 2 } }) | ConvertTo-Json -Depth 6), $bom)
Kadro-Yaz $fikirK @((& $uye 'lider' 'Creative Director' @{}), (& $uye 'fikirci' 'Creative Strategist' @{}), (& $uye 'iletisim' 'Comms' @{ uzman_isi = $true }))
[IO.File]::WriteAllText((Join-Path $fikirK 'ayarlar.json'), (([pscustomobject]@{ surum = 1; roller = [pscustomobject]@{ lider = @(& $s 'sahte-fikir-lider'); iletisim = @(& $s 'sahte-comms') } }) | ConvertTo-Json -Depth 6), $bom)
$katlarJ = [pscustomobject]@{ surum = 1; sirket = 'Test Şirketi'; katlar = @(
    [pscustomobject]@{ id = 'ana'; ad = 'Ana Ofis'; kisa_ad = 'Ana'; kat_no = 3; tur = 'ekip'; kok = ''; alan = 'yazılım' }
    [pscustomobject]@{ id = 'veri'; ad = 'Veri Katı'; kisa_ad = 'Veri'; kat_no = 2; tur = 'ekip'; kok = 'katlar\veri'; alan = 'SAP ETL ve raporlar' }
    [pscustomobject]@{ id = 'fikir'; ad = 'Fikir Katı'; kisa_ad = 'Fikir'; kat_no = 1; tur = 'ekip'; kok = 'katlar\fikir'; alan = 'fikir ve POC' }
    [pscustomobject]@{ id = 'app'; ad = 'Uygulama Katı'; kisa_ad = 'App'; kat_no = 0; tur = 'uygulama'; kok = ''; alan = 'masal videosu'; uygulama = [pscustomobject]@{ api = 'http://127.0.0.1:9/api'; adres = 'http://127.0.0.1:9/' } }
) }
[IO.File]::WriteAllText((Join-Path $kum 'katlar.json'), ($katlarJ | ConvertTo-Json -Depth 6), $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
$repo = Join-Path $kum 'depo'
New-Item -ItemType Directory -Force $repo | Out-Null
Git-T -C $repo init -q -b main
[IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "a`n", $ascii)
Git-T -C $repo add -A
Git-T -C $repo -c user.name=t -c user.email=t@t commit -q -m ilk
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @([pscustomobject]@{ ad = 'test'; klasor = $repo; temel_dal = ''; dogrulama = @() }) }) | ConvertTo-Json -Depth 5), $bom)
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo ARG=%*', 'set MODEL=',
    ':dongu', 'if "%~1"=="" goto bitti', 'if "%~1"=="--model" set MODEL=%~2', 'shift', 'goto dongu', ':bitti',
    'if defined MODEL if exist "%D%cikti-%MODEL%.txt" goto ozel', 'type "%D%sahte-cikti.txt"', 'exit /b 0',
    ':ozel', 'type "%D%cikti-%MODEL%.txt"', 'exit /b 0'
) -join "`r`n") + "`r`n", $ascii)
function Akis([string]$Metin) {
    $satirlar = @(
        ([ordered]@{ type = 'system'; subtype = 'init' } | ConvertTo-Json -Compress),
        ([ordered]@{ type = 'result'; subtype = 'success'; is_error = $false; num_turns = 1; result = $Metin; usage = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 10; cache_creation_input_tokens = 0; output_tokens = 5 } } | ConvertTo-Json -Compress -Depth 5))
    return (($satirlar -join "`n") + "`n")
}
function Model-Yanit([string]$Model, [string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum "cikti-$Model.txt"), (Akis $Metin), $utf8) }
[IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), (Akis 'YANLIS: beklenmeyen ajan'), $utf8)

# Kata geçiş: ortak.ps1 AIEKIP_KAT'ı okur (döngü yeniden yüklemesindeki gibi betikler aynı kapsamda yeniden yüklenir)
$KataGec = { param($Id) $env:AIEKIP_KAT = $Id; . (Join-Path $kum 'ortak.ps1'); . (Join-Path $kum 'rapor.ps1'); . (Join-Path $kum 'ekip.ps1'); Ayarlari-Yukle; Kadro-Rolleri-Yukle }
. $KataGec ''
if ($KodKok -ne $kum) { throw "Betikler kum havuzunu değil $KodKok klasörünü kullanıyor; test durduruldu" }

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Is([string]$Id, [string]$Tip, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# $Id`n`n## Açıklama`n`nSatış raporu gerekiyor.`n`n## Notlar ve yanıtlar`n"
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; tip = $Tip; proje = 'Engineering Manager'; klasor = ''; ipucu = ''; istenen_rol = ''; oncelik = 2; asama = $Asama
        tur = 1; max_tur = 3; deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); gereksinim_durumu = 'hazir' }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Adim([string]$Id) { Gorev-Ilerlet (Gorev-Oku $Id); return (Gorev-Oku $Id) }
function Kat-Gorevi([string]$Klasor, [string]$Id) { return ([IO.File]::ReadAllText((Join-Path $Klasor "gorevler\$Id\durum.json"), $bom) | ConvertFrom-Json) }
function Kat-Gorevi-Yaz([string]$Klasor, $G) { [IO.File]::WriteAllText((Join-Path $Klasor "gorevler\$($G.id)\durum.json"), ($G | ConvertTo-Json -Depth 10), $bom) }
function Cagrilar { if (Test-Path -LiteralPath (Join-Path $kum 'cagrilar.log')) { return [IO.File]::ReadAllText((Join-Path $kum 'cagrilar.log')) }; return '' }
$BRIF = "BASLIK: Satış raporu (ana kattan)`nKONU: Haftalık satış raporu`n`n## Brif`nAna kat haftalık satış raporu istiyor; toplamlar bölgeye göre.`n`n## Kabul`n- rapor dosyası var`n- toplamlar doğru"

try {
    Write-Host ''
    Write-Host '1) Kat çözümü'
    Dogrula 'ana kat: veri kökü kod kökü, kilitlerde kat eki yok' ($KatKimligi -eq 'ana' -and $Kok -eq $kum -and (Gorev-Kilit-Adi '0001-a') -notmatch '_ana') (Gorev-Kilit-Adi '0001-a')
    $sec = Kat-Secenegi-Metni 'yonlendirme'
    Dogrula 'yönlendirmeye KAT seçeneği ve diğer katlar eklenir (kendi katı yok)' ($sec -match 'KARAR: KAT' -and $sec -match '- veri: Veri Katı' -and $sec -match '- app: Uygulama Katı' -and $sec -notmatch '- ana:')
    . $KataGec 'veri'
    Dogrula 'veri katı: kök katlar\veri, ad, kilit eki' ($Kok -eq $veriK -and (Ofis-Adi) -eq 'Veri Katı' -and (Gorev-Kilit-Adi '0001-a') -like '*_veri_0001-a' -and (Kat-Dongu-Kilidi 'veri') -like '*_veri') "$Kok"
    Dogrula 'veri katı ayarları ana kattan miras alır (yalnız eksik bloklar)' ($Ayar.dongu -and $Ayar.claude.exe -eq $sahteAjan -and @($Ayar.roller.lider)[0].model -eq 'sahte-veri-lider' -and [int]$Ayar.gorev.max_tur -eq 2)
    Dogrula 'istem şablonu kodla gelir, unvanlar kata çevrilir' ((Unvan-Uyarla 'ENGINEERING MANAGER ve Code Reviewer; QA Engineer ile BI QA Engineer') -ceq 'DATA LEAD ve BI Technical Lead; BI QA Engineer ile BI QA Engineer')
    Dogrula 'veri katında Comms hazır, fikir hattı yok' ((Comms-Hazir-mi) -and -not (Yaratici-Katta-mi))
    $env:AIEKIP_KAT = 'yok-boyle-kat'
    $hata = ''; try { . (Join-Path $kum 'ortak.ps1') } catch { $hata = $_.Exception.Message }
    Dogrula 'bilinmeyen kat reddedilir' ($hata -match 'Bilinmeyen kat') $hata
    $env:AIEKIP_KAT = 'app'
    $hata = ''; try { . (Join-Path $kum 'ortak.ps1') } catch { $hata = $_.Exception.Message }
    Dogrula 'uygulama katında ekip motoru çalışmaz' ($hata -match 'ekip katı değil') $hata

    Write-Host ''
    Write-Host '2) KARAR: KAT ile iş başka kata (Comms brifi, hedefte görev, yazışma)'
    . $KataGec ''
    Model-Yanit 'sahte-yonetici' "KARAR: KAT`nKAT: veri`n`n## Gerekçe`nSAP raporu veri katının işi.`n`n## İş`nHaftalık satış raporunu hazırla.`n`n## Kabul`n- rapor var"
    Model-Yanit 'sahte-comms' $BRIF
    $null = Is '0001-rapor' 'genel' 'yeni'
    $g = Adim '0001-rapor'
    $ref = [string](@($g.yardim_bekleyen)[0])
    Dogrula 'görev kat_bekliyor, bekleyen "@yazışma"' ($g.asama -eq 'kat_bekliyor' -and $ref.StartsWith('@') -and $g.yonlendirme_karari -eq 'KAT' -and @($g.kat_yazismalari).Count -eq 1) "$($g.asama) $ref"
    $y = Yazisma-Oku ($ref.TrimStart('@'))
    Dogrula 'yazışma kaydı: gönderildi, hedef veri, Comms brifi' ($y -and $y.durum -eq 'gonderildi' -and $y.hedef_kat -eq 'veri' -and $y.comms_brif -and $y.brif -match 'bölgeye göre' -and $y.gonderen -eq 'Communications Coordinator' -and $y.alan -eq 'Data Comms')
    $hg = Kat-Gorevi $veriK ([string]$y.hedef_gorev)
    Dogrula 'hedef katta genel görev: kaynak, yazışma, Comms başlığı' ($hg.tip -eq 'genel' -and $hg.asama -eq 'yeni' -and $hg.kaynak_kat -eq 'ana' -and $hg.kaynak_gorev -eq '0001-rapor' -and $hg.yazisma -eq $y.id -and $hg.baslik -eq 'Satış raporu (ana kattan)' -and [int]$hg.kat_derinligi -eq 1 -and [int]$hg.max_tur -eq 2) "$($hg.id)"
    $gmd = [IO.File]::ReadAllText((Join-Path $veriK "gorevler\$($hg.id)\gorev.md"), $utf8)
    Dogrula 'hedef gorev.md: brif, kabul, hedef yöneticisi ve Comms adları' ($gmd -match 'bölgeye göre' -and $gmd -match '- rapor dosyası var' -and $gmd -match 'Data Lead yönlendirecek' -and $gmd -match 'teslim alan: Data Comms')
    Dogrula 'hedef katın duyurularına ve günlüğüne yazıldı' (([IO.File]::ReadAllText((Join-Path $veriK 'durum\duyurular.jsonl'))) -match 'kat_yazisma' -and @(Get-ChildItem (Join-Path $veriK 'gunluk') -File).Count -ge 1)
    Dogrula 'Comms (iletisim) gerçekten çağrıldı; brif kaydı görevde' ((Cagrilar) -match 'sahte-comms' -and (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru '0001-rapor') "kat-yazisma-$($y.id).md")))

    Write-Host ''
    Write-Host '3) Hedef katın gözünden: geri gönderme yasağı'
    . $KataGec 'veri'
    $hgV = Gorev-Oku ([string]$y.hedef_gorev)
    Dogrula 'ana kattan gelen iş ana kata geri gönderilemez' ((Kat-Gonderilebilir $hgV 'ana') -match 'geri gönderilemez')
    Dogrula 'bu görev için KAT seçeneğinde ana kat yok' ((Kat-Secenegi-Metni 'yonlendirme' $hgV) -notmatch '- ana:')
    $r = Kat-Talebi-Gonder $hgV 'ana' 'is' 'x' ''
    Dogrula 'geri gönderme denemesi hata metni döner' ($r -is [string])

    Write-Host ''
    Write-Host '4) İzleme ve dönüş: Comms raporu, görev tamamlanır'
    . $KataGec ''
    $hg.asama = 'gelistirme'; Kat-Gorevi-Yaz $veriK $hg
    Kat-Yazismalari-Senkron
    Dogrula 'hedef çalışınca yazışma "calisiyor"' ((Yazisma-Oku $y.id).durum -eq 'calisiyor')
    Yardim-Bekleyenleri-Kontrol
    Dogrula 'hedef bitmeden kaynak görev bekler' ((Gorev-Oku '0001-rapor').asama -eq 'kat_bekliyor')
    $hg.asama = 'tamam'; $hg | Add-Member -Force -NotePropertyName ozet -NotePropertyValue 'Rapor hazır'; Kat-Gorevi-Yaz $veriK $hg
    [IO.File]::WriteAllText((Join-Path $veriK "gorevler\$($hg.id)\sonuc.md"), "rapor.xlsx teslim edildi", $utf8)
    Model-Yanit 'sahte-comms' "DURUM: TAMAMLANDI`n`n## Özet`nVeri katı raporu teslim etti.`n`n## Teslimler`n- rapor.xlsx`n`n## Ekibe notlar`nyok"
    Kat-Yazismalari-Senkron
    $y2 = Yazisma-Oku $y.id
    Dogrula 'yazışma tamamlandı; Comms raporu ve hedef kayıtları saklandı' ($y2.durum -eq 'tamamlandi' -and $y2.sonuc.rapor -match 'raporu teslim etti' -and $y2.sonuc.ham -match 'rapor.xlsx' -and (Test-Path -LiteralPath (Join-Path (Yazisma-Klasoru) "$($y.id)-rapor.md")))
    Yardim-Bekleyenleri-Kontrol
    $g = Gorev-Oku '0001-rapor'
    $smd = Metin-Oku (Join-Path (Gorev-Klasoru '0001-rapor') 'sonuc.md')
    Dogrula 'kaynak görev tamam: sonuç ve özet Comms raporundan' ($g.asama -eq 'tamam' -and $smd -match 'raporu teslim etti' -and [string]$g.ozet -match '^Veri Katı tamamladı' -and @($g.yardim_bekleyen).Count -eq 0) "$($g.asama)"

    Write-Host ''
    Write-Host '5) Yardım isteğini başka kat karşılar (başarısız dönüş)'
    $null = Is '0002-yardim' 'uzman' 'yardim' @{ yardim_sayisi = 1; yardim_isteyen = 'gelistirici'; yardim_istek = 'IQ bağlantısı'; yardim_donus_asama = 'gelistirme'; sorumlu = 'gelistirici' }
    Metin-Yaz (Join-Path (Gorev-Klasoru '0002-yardim') 'yardim-istek-1.md') "IQ bağlantı bilgisini doğrulayamıyorum."
    Model-Yanit 'sahte-yonetici' "KARAR: KAT`nKAT: veri`n`n## İş`nIQ bağlantısını doğrula.`n`n## Kabul`n- bağlantı test edildi"
    Model-Yanit 'sahte-comms' "BASLIK: IQ bağlantı kontrolü`n`n## Brif`nAna kat IQ bağlantısının doğrulanmasını istiyor.`n`n## Kabul`n- bağlantı test edildi"
    $g = Adim '0002-yardim'
    $ref2 = [string](@($g.yardim_bekleyen)[0])
    Dogrula 'yardım kararı KAT: görev yardim_bekliyor, dönüş gelistirme' ($g.asama -eq 'yardim_bekliyor' -and $ref2.StartsWith('@') -and $g.yardim_donus_asama -eq 'gelistirme') "$($g.asama)"
    $yy = Yazisma-Oku ($ref2.TrimStart('@'))
    Dogrula 'yazışma türü yardım' ($yy.tur -eq 'yardim')
    $hy = Kat-Gorevi $veriK ([string]$yy.hedef_gorev); $hy.asama = 'iptal'; Kat-Gorevi-Yaz $veriK $hy
    Model-Yanit 'sahte-comms' "DURUM: BASARISIZ`n`n## Özet`nVeri katı işi iptal etti."
    Kat-Yazismalari-Senkron
    Yardim-Bekleyenleri-Kontrol
    $g = Gorev-Oku '0002-yardim'
    $ys = Metin-Oku (Join-Path (Gorev-Klasoru '0002-yardim') 'yardim-sonuclari.md')
    Dogrula 'başarısız yardım dönüşünde iş kaldığı aşamadan sürer, sonuç yazılır' ($g.asama -eq 'gelistirme' -and $ys -match 'tamamlanamadı' -and $ys -match 'iptal etti') "$($g.asama)"

    Write-Host ''
    Write-Host '6) Uygulama katı (API kapalıyken bekler, sonra iş ve durum)'
    Model-Yanit 'sahte-yonetici' "KARAR: KAT`nKAT: app`n`n## İş`nTavşan masalı videosu üret."
    Model-Yanit 'sahte-comms' "BASLIK: Tavşan masalı`nKONU: Cesur tavşanın orman macerası`n`n## Brif`nKısa masal videosu."
    $null = Is '0003-masal' 'genel' 'yeni'
    $g = Adim '0003-masal'
    $y3 = Yazisma-Oku ([string](@($g.yardim_bekleyen)[0])).TrimStart('@')
    Dogrula 'uygulama yanıt vermiyor: yazışma beklemede, görev kat_bekliyor' ($g.asama -eq 'kat_bekliyor' -and $y3.durum -eq 'beklemede' -and $y3.hedef_tur -eq 'uygulama' -and $y3.konu -eq 'Cesur tavşanın orman macerası')
    $script:SahteKonu = ''; $script:SahteDurum = 'running'
    function Uygulama-Isi-Ac($K, [string]$Konu) { $script:SahteKonu = $Konu; return 'job-1' }
    function Uygulama-Isi-Oku($K, [string]$Id) { return [pscustomobject]@{ id = $Id; status = $script:SahteDurum; title = 'Cesur Tavşan'; video_url = '/media/job-1/video.mp4'; duration = 54.2 } }
    Kat-Yazismalari-Senkron
    $y3 = Yazisma-Oku $y3.id
    Dogrula 'uygulama açılınca Comms işi teslim eder (konu cümlesi)' ($y3.durum -eq 'gonderildi' -and $y3.hedef_gorev -eq 'job-1' -and $script:SahteKonu -eq 'Cesur tavşanın orman macerası')
    Kat-Yazismalari-Senkron
    Dogrula 'uygulama çalışıyor: calisiyor' ((Yazisma-Oku $y3.id).durum -eq 'calisiyor')
    $script:SahteDurum = 'awaiting_approval'
    Model-Yanit 'sahte-comms' "DURUM: TAMAMLANDI`n`n## Özet`nMasal videosu hazır; yayın kararı kullanıcıda."
    Kat-Yazismalari-Senkron
    $y3 = Yazisma-Oku $y3.id
    Dogrula 'onay bekleyen video tamamlandı sayılır; ham sonuçta video ve yükleme notu' ($y3.durum -eq 'tamamlandi' -and $y3.sonuc.ham -match 'video.mp4' -and $y3.sonuc.ham -match 'kullanıcının kararıdır')
    Yardim-Bekleyenleri-Kontrol
    Dogrula 'kaynak görev tamamlandı' ((Gorev-Oku '0003-masal').asama -eq 'tamam')

    Write-Host ''
    Write-Host '7) Gönderen iptal edince hedefteki başlamamış iş geri çekilir'
    Model-Yanit 'sahte-yonetici' "KARAR: KAT`nKAT: veri`n`n## İş`nBir rapor daha."
    Model-Yanit 'sahte-comms' "BASLIK: İkinci rapor`n`n## Brif`nBir rapor daha."
    $null = Is '0004-iptal' 'genel' 'yeni'
    $g = Adim '0004-iptal'
    $y4 = Yazisma-Oku ([string](@($g.yardim_bekleyen)[0])).TrimStart('@')
    $g.asama = 'iptal'; Gorev-Kaydet $g
    Kat-Yazismalari-Senkron
    Dogrula 'yazışma iptal; hedef görev iptal edildi' ((Yazisma-Oku $y4.id).durum -eq 'iptal' -and (Kat-Gorevi $veriK ([string]$y4.hedef_gorev)).asama -eq 'iptal')

    Write-Host ''
    Write-Host '8) Bina bekçisi ve kat açık / kapalı'
    [IO.File]::WriteAllText((Join-Path $fikirK 'DURDUR'), "Ofis kapatıldı (panelden), test.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $veriK 'DURDUR'), "Duraklatıldı (test)`n", $utf8)
    Dogrula 'Ofis kapatıldı = kapalı; duraklatma kapalı değil' ((Kat-Kapali-mi $fikirK) -and -not (Kat-Kapali-mi $veriK))
    Remove-Item -LiteralPath (Join-Path $veriK 'DURDUR')
    $script:Baslatilan = @()
    function Kat-Dongusu-Baslat([string]$Id) { $script:Baslatilan += $Id }
    Bina-Bekcisi
    Dogrula 'bekçi yalnız açık ekip katının döngüsünü başlatır (kapalı ve uygulama katı değil)' (($script:Baslatilan -join ',') -eq 'veri') ($script:Baslatilan -join ',')

    . $KataGec 'veri'
    [IO.File]::WriteAllText((Join-Path $veriK 'DURDUR'), "Ofis kapatıldı (panelden), test.`n", $utf8)
    $sonuc = Ekip-Dongusu -BosBitir
    Dogrula 'alt kat kapatılınca döngüsü çıkar (kapandi)' ($sonuc -eq 'kapandi') "$sonuc"
    Remove-Item -LiteralPath (Join-Path $veriK 'DURDUR')
    . $KataGec ''

    Write-Host ''
    Write-Host '9) Fikir hattı katı: POC ana kata (köprü ana katın ortamında) + Comms kaydı'
    . $KataGec 'fikir'
    Dogrula 'fikir katında fikir hattı var; ana ofis yolu boşsa ana kat' ((Yaratici-Katta-mi) -and (Yaratici-Ayari).ana_ofis_yolu -eq $kum)
    $paket = [pscustomobject]@{ baslik = 'Kelime oyunu POC'; aciklama = 'Küçük bir kelime oyunu'; proje = 'test'; anahtar = ([guid]::NewGuid().ToString('N')); kabul = @('oyun açılır') }
    $ana = Gorevi-Gonder $paket $kum (Join-Path $YolDurum 'teslim-test.json')
    Dogrula 'POC görevi ana katta açıldı (fikir katında değil), ortam geri alındı' ($ana -and (Test-Path -LiteralPath (Join-Path $kum "gorevler\$($ana.id)\durum.json")) -and -not (Test-Path -LiteralPath (Join-Path $fikirK "gorevler\$($ana.id)")) -and $env:AIEKIP_KAT -eq 'fikir') "$($ana.id)"
    $fg = Is '0001-fikir' 'yaratici' 'teslim'
    $yp = Kat-Yazisma-Kaydi $fg 'ana' ([string]$ana.id) 'poc' 'Kelime oyunu POC' 'Küçük bir kelime oyunu' @('oyun açılır')
    Dogrula 'POC yazışması: tür poc, ana katın duyurusunda' ($yp.tur -eq 'poc' -and $yp.hedef_gorev -eq $ana.id -and ([IO.File]::ReadAllText((Join-Path $kum 'durum\duyurular.jsonl'))) -match 'kat_yazisma')
    Dogrula 'fikir katından görülen kat kökü' ((Kok-Kat-Kimligi $kum) -eq 'ana' -and (Kok-Kat-Kimligi $veriK) -eq 'veri')
    . $KataGec ''
    Dogrula 'ana katta fikir hattı yok' (-not (Yaratici-Katta-mi))
    $l = @(Yazismalar-Listele)
    Dogrula 'tüm yazışmalar şirket klasöründe (5)' ($l.Count -eq 5) "$($l.Count)"
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    $env:AIEKIP_KAT = ''
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) {
        try { Get-ChildItem -LiteralPath (Join-Path $kum 'calisma') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Git-T -C $repo worktree remove --force $_.FullName | Out-Null } } catch {}
        Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host "Kum havuzu korundu: $kum" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
