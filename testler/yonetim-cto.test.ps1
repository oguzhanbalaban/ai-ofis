<#
yonetim-cto.test.ps1 - Yönetim katmanını (CTO) sınar: değerlendirme zamanlaması, girdiler, rapor, ekip ilkeleri, öncelik değişikliği,
iş önerileri, hata durumu ve ilkelerin iş istemlerine eklenmesi. Çevrimdışıdır: gerçek Claude / Codex çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\yonetim-cto.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-cto-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$sahteAjan = Join-Path $kum 'sahte-ajan.cmd'
$ayarJ.claude.exe = $sahteAjan
$ayarJ.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayarJ.zaman_asimi_dk.claude = 5
$ayarJ.gunluk_sinir.claude = 1000
$s = { param($m) [pscustomobject]@{ arac = 'claude'; model = $m } }
$ayarJ.roller = [pscustomobject]@{ lider = @(& $s 'sahte-yonetici'); 'sorun-giderici' = @(& $s 'sahte-cozucu'); gelistirici = @(& $s 'sahte-gelistirici')
    denetci = @(& $s 'sahte-denetci'); sistem = @(& $s 'sahte-sistem'); ag = @(& $s 'sahte-ag'); cto = @(& $s 'sahte-cto') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $false; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName planlama -NotePropertyValue ([pscustomobject]@{ analiz = $false; kesif = $false; qa_testi = $false })
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $true; aralik_saat = 24; en_az_biten = 1; ilke_siniri = 3 })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $dep) [pscustomobject][ordered]@{ anahtar = $a; ad = $ad; departman = $dep; yerlesik = $true; uzman_isi = $false; yetki = 'oku'; uzmanlik = "$ad işleri" } }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @((& $uye 'cto' 'Chief Technology Officer' 'Yönetim'), (& $uye 'lider' 'Engineering Manager' 'Teknik koordinasyon'),
    (& $uye 'sorun-giderici' 'Incident Manager' 'Teknik koordinasyon'), (& $uye 'gelistirici' 'Full-Stack Developer' 'Yazılım'), (& $uye 'denetci' 'Code Reviewer' 'Yazılım')) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
$repo = Join-Path $kum 'depo'
New-Item -ItemType Directory -Force $repo | Out-Null
Git-T -C $repo init -q -b main
[IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "a`n", $ascii)
Git-T -C $repo add -A
Git-T -C $repo -c user.name=t -c user.email=t@t commit -q -m ilk
Git-T -C $repo branch 'ekip/0700-bekleyen'
Git-T -C $repo checkout -q 'ekip/0700-bekleyen'
[IO.File]::WriteAllText((Join-Path $repo 'b.txt'), "b`n", $ascii)
Git-T -C $repo add -A
Git-T -C $repo -c user.name=t -c user.email=t@t commit -q -m dal
Git-T -C $repo checkout -q main
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @([pscustomobject]@{ ad = 'test'; klasor = $repo; temel_dal = ''; dogrulama = @() }) }) | ConvertTo-Json -Depth 5), $bom)
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo %*', 'set MODEL=',
    ':dongu', 'if "%~1"=="" goto bitti', 'if "%~1"=="--model" set MODEL=%~2', 'shift', 'goto dongu', ':bitti',
    'if defined MODEL if exist "%D%cikti-%MODEL%.txt" goto ozel', 'type "%D%sahte-cikti.txt"', 'exit /b 0',
    ':ozel', 'type "%D%cikti-%MODEL%.txt"', 'exit /b 0'
) -join "`r`n") + "`r`n", $ascii)
function Akis([string]$Metin, [bool]$Hata = $false) {
    $st = 'success'; if ($Hata) { $st = 'error_during_execution' }
    $satirlar = @(
        ([ordered]@{ type = 'system'; subtype = 'init' } | ConvertTo-Json -Compress),
        ([ordered]@{ type = 'result'; subtype = $st; is_error = $Hata; num_turns = 1; result = $Metin; usage = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 10; cache_creation_input_tokens = 0; output_tokens = 5 } } | ConvertTo-Json -Compress -Depth 5))
    return (($satirlar -join "`n") + "`n")
}
function Yanit([string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), (Akis $Metin), $utf8) }
function Model-Yanit([string]$Model, [string]$Metin, [bool]$Hata = $false) { [IO.File]::WriteAllText((Join-Path $kum "cikti-$Model.txt"), (Akis $Metin $Hata), $utf8) }
Yanit 'KARAR: ONAY'

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
function Is([string]$Id, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# $Id`n`nİş."
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; tip = 'yazilim'; proje = 'test'; klasor = $repo; oncelik = 2; asama = $Asama; tur = 1; max_tur = 3
        deneme = 0; dogrulama = @(); olusturma = (Get-Date).AddHours(-5).ToString('o'); guncelleme = (Simdi); gecmis = @() }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return (Metin-Oku $f.FullName) }; return '' }
$yk = Join-Path $YolDurum 'yonetim'

try {
    Write-Host ''; Write-Host 'Y1: değerlendirme zamanlaması'
    Dogrula 'iş yokken gerekmez' (-not (Yonetim-Degerlendirmesi-Gerekli))
    $g1 = Is '0701-biten' 'tamam' @{ gecmis = @([pscustomobject]@{ zaman = (Simdi); asama = 'denetim'; tur = 1; olay = 'yeni tura dönüldü'; ayrinti = 'Code Reviewer düzeltme istedi: null kontrolü eksik' }) }
    Dogrula 'biten iş var, önceki değerlendirme yok: gerekir' (Yonetim-Degerlendirmesi-Gerekli)
    [void](Yonetim-Klasoru)
    Json-Yaz ([pscustomobject]@{ zaman = (Simdi); durum = 'tamam'; ozet = 'önceki' }) (Join-Path $yk 'son.json')
    Dogrula 'aralık dolmadıysa gerekmez' (-not (Yonetim-Degerlendirmesi-Gerekli))
    Metin-Yaz (Yonetim-Istek-Yolu) 'istek'
    Dogrula 'panelden istendiyse aralığa bakmadan gerekir' (Yonetim-Degerlendirmesi-Gerekli)
    $Ayar.yonetim.etkin = $false
    Dogrula 'yonetim.etkin false: gerekmez' (-not (Yonetim-Degerlendirmesi-Gerekli))
    $Ayar.yonetim.etkin = $true
    Json-Yaz ([pscustomobject]@{ zaman = (Get-Date).AddHours(-30).ToString('o'); durum = 'tamam'; ozet = 'Ekip iyi; bir iş iki turda bitti.' }) (Join-Path $yk 'son.json')

    Write-Host ''; Write-Host 'Y2: değerlendirme: girdiler, rapor, ilkeler, öncelik, öneriler'
    $g2 = Is '0702-sirada' 'yeni' @{ oncelik = 3 }
    $g3 = Is '0703-suren' 'gelistirme' @{ oncelik = 2 }
    Model-Yanit 'sahte-cto' ("KARAR: HAZIR`nONCELIK: 0702 | 1`nONCELIK: 0703 | 1`nONCELIK: 0999 | 1`n`n## Özet`nEkip işleri bitiriyor ama düzeltme turları fazla.`n`n## Ne iyi gitti`n- iş bitti`n`n## Sorunlar ve kök nedenler`n- null kontrolü`n`n## Kararlar`n- #0702 öne alındı: #0703'ün önünü açıyor.`n`n## Öneriler`n- test`n`n## Ekip ilkeleri`n- Null kontrollerini Code Reviewer'dan önce geliştirici yazsın.`n- Flutter işlerinde önce flutter doctor doğrulansın.`n- Üçüncü ilke.`n- Dördüncü ilke sınırı aşar.`n`n" +
        '```is' + "`n" + '{"baslik": "Release Manager işe al", "aciklama": "Birleştirilmemiş dalları hazırlayacak çalışan", "rol": "", "kabul": ["dallar listelenir"], "oncelik": 1}' + "`n" + '```' + "`n" +
        '```is' + "`n" + '{"baslik": "kısa başlık", "aciklama": "şablon"}' + "`n" + '```')
    Yonetim-Degerlendir
    $son = Json-Oku (Join-Path $yk 'son.json')
    $rapor = Metin-Oku (Join-Path $yk ([string]$son.dosya))
    Dogrula 'son.json: tamam, özet, 3 ilke, 1 öneri (şablon örneği sayılmadı)' ($son.durum -eq 'tamam' -and $son.ozet -match 'düzeltme turları fazla' -and $son.ilke_sayisi -eq 3 -and @($son.oneriler).Count -eq 1 -and $son.oneriler[0].baslik -eq 'Release Manager işe al' -and $son.oneriler[0].tur -eq 'genel') (Kisalt ($son | ConvertTo-Json -Compress -Depth 4) 160)
    Dogrula 'rapor yazıldı: KARAR / ONCELIK / öneri bloğu yok, uygulanan öncelik bölümü var' ($rapor -match '# Yönetim değerlendirmesi \(CTO\)' -and $rapor -notmatch '(?m)^KARAR' -and $rapor -notmatch '(?m)^ONCELIK' -and $rapor -notmatch '```is' -and $rapor -match 'Uygulanan öncelik değişiklikleri' -and $rapor -match '#0702: 3 -> 1')
    $il = Metin-Oku (Join-Path $yk 'ekip-ilkeleri.md')
    Dogrula 'ekip ilkeleri: sınır kadar (3) madde' ((@($il -split "`n" | Where-Object { $_ -match '^- ' })).Count -eq 3 -and $il -match 'flutter doctor' -and $il -notmatch 'Dördüncü') $il.Replace("`n", ' | ')
    $d2 = Gorev-Oku $g2.id; $d3 = Gorev-Oku $g3.id
    Dogrula 'yalnızca başlamamış işin önceliği değişti, geçmişe yazıldı' ([int]$d2.oncelik -eq 1 -and [int]$d3.oncelik -eq 2 -and (@($d2.gecmis | ForEach-Object { $_.olay }) -contains 'CTO önceliği değiştirdi')) "0702: $($d2.oncelik), 0703: $($d3.oncelik)"
    Dogrula 'istek dosyası silindi' (-not (Test-Path (Yonetim-Istek-Yolu)))
    $ist = Son-Istem (Join-Path $yk 'kayitlar') 'yonetim-*.istem.md'
    Dogrula 'CTO isteminde metrikler, kuyruk, birleştirilmemiş dal, önceki özet, kadro' ($ist -match 'null kontrolü eksik' -and $ist -match '#0702 Test 0702-sirada .*BAŞLAMADI' -and $ist -match 'ekip/0700-bekleyen' -and $ist -match 'bir iş iki turda bitti' -and $ist -match 'Chief Technology Officer' -and $ist -match 'En fazla 3 madde')
    Dogrula 'CTO istemi karakter sınırını söyler (varsayılan 6000), yer tutucu kalmaz' ($ist -match 'tamamı 6000 karakteri geçmesin' -and $ist -notmatch '\{ILKE_KARAKTER_SINIRI\}')
    Dogrula 'CTO çağrısı salt okunur' ((Metin-Oku (Join-Path $kum 'cagrilar.log')) -match 'sahte-cto' -and (Metin-Oku (Join-Path $kum 'cagrilar.log')) -match '--tools Read,Glob,Grep ')
    Dogrula 'aralık dolmadan yeniden gerekmez' (-not (Yonetim-Degerlendirmesi-Gerekli))

    Write-Host ''; Write-Host 'Y3: ekip ilkeleri iş istemlerine eklenir'
    $g4 = Is '0704-plan' 'plan'
    [void](Calisma-Agaci-Kur $g4); Gorev-Kaydet $g4
    Model-Yanit 'sahte-yonetici' "KARAR: PLAN_HAZIR`nEK_INCELEME: yok`n`n## Özet`nplan"
    Gorev-Ilerlet (Gorev-Oku $g4.id)
    $pist = Son-Istem (Gorev-Klasoru $g4.id) 'plan-*.istem.md'
    Dogrula 'plan isteminde EKİP İLKELERİ var' ($pist -match '# EKİP İLKELERİ \(CTO' -and $pist -match 'flutter doctor')
    $script:AktifGorev = ''
    $a1 = Ilkeler-Istem-Metni 'plan'
    $script:AktifGorev = $g4.id
    $a2 = Ilkeler-Istem-Metni 'yonetim'; $a3 = Ilkeler-Istem-Metni 'sohbet'; $a4 = Ilkeler-Istem-Metni 'plan'
    $script:AktifGorev = ''
    Dogrula 'görevsiz çağrıda ve yönetim / sohbet etiketinde eklenmez, görev adımında eklenir' (-not $a1 -and -not $a2 -and -not $a3 -and $a4)

    Write-Host ''; Write-Host 'Y3b: ilkeler istemlere ayarlı karakter sınırıyla ve madde sınırında girer'
    Dogrula 'karakter sınırı: varsayılan 6000' ((Ilke-Karakter-Siniri) -eq 6000) "$(Ilke-Karakter-Siniri)"
    $Ayar.yonetim | Add-Member -Force -NotePropertyName ilke_karakter_siniri -NotePropertyValue 3000
    $k1 = Ilke-Karakter-Siniri
    $Ayar.yonetim.ilke_karakter_siniri = 100; $k2 = Ilke-Karakter-Siniri
    $Ayar.yonetim.ilke_karakter_siniri = 'abc'; $k3 = Ilke-Karakter-Siniri
    $Ayar.yonetim.ilke_karakter_siniri = 3000
    Dogrula 'ayar okunur; en az 500; geçersiz değer varsayılana düşer' ($k1 -eq 3000 -and $k2 -eq 500 -and $k3 -eq 6000) "$k1 / $k2 / $k3"
    $kisa = Ilkeler-Sigdir "- tek ilke`n" 3000
    Dogrula 'sınırın altındaki liste olduğu gibi kalır' ($kisa.metin -eq '- tek ilke' -and $kisa.kesilen -eq 0)
    # 20 madde: 1-9 290, 10-20 291 karakter; 10 madde 2910 karakter, 11. madde 3000'i aşar
    $uzun = ((1..20 | ForEach-Object { '- İlke {0}: {1}' -f $_, ('x' * 280) }) -join "`n") + "`n"
    $sg = Ilkeler-Sigdir $uzun 3000
    $sgSat = @($sg.metin -split "`n")
    Dogrula 'madde sınırında keser: 10 madde tam, 10 madde sayılır, yarım madde yok' ($sg.kesilen -eq 10 -and $sgSat.Count -eq 10 -and $sg.metin.Length -le 3000 -and $sgSat[-1] -match '^- İlke 10: x{280}$' -and $sg.metin -notmatch '…') "kesilen $($sg.kesilen), satır $($sgSat.Count), uzunluk $($sg.metin.Length)"
    $cok = Ilkeler-Sigdir ("- ilk madde`n  devam satırı`n- ikinci " + ('y' * 50)) 30
    Dogrula 'devam satırı maddesiyle birlikte taşınır' ($cok.metin -eq "- ilk madde`n  devam satırı" -and $cok.kesilen -eq 1) ($cok.metin.Replace("`n", ' | '))
    $tek = Ilkeler-Sigdir ('- ' + ('z' * 700)) 500
    Dogrula 'tek madde bile sığmıyorsa sınırda keser (eski davranış)' ($tek.metin.Length -eq 501 -and $tek.metin.EndsWith('…') -and $tek.kesilen -eq 0)
    $ilEski = Metin-Oku (Join-Path $yk 'ekip-ilkeleri.md')
    Metin-Yaz (Join-Path $yk 'ekip-ilkeleri.md') $uzun
    $script:AktifGorev = $g4.id
    $b1 = Ilkeler-Istem-Metni 'plan'
    $Ayar.yonetim.PSObject.Properties.Remove('ilke_karakter_siniri')
    $b2 = Ilkeler-Istem-Metni 'plan'
    $script:AktifGorev = ''
    Dogrula 'istemde sınır 3000: İlke 10 tam, İlke 11 yok, "10 ilke daha" notu var' ($b1 -match '- İlke 10: x{280}' -and $b1 -notmatch 'İlke 11:' -and $b1 -match '10 ilke daha bu isteme sığmadı' -and $b1 -notmatch '…')
    Dogrula 'varsayılan 6000 ile 20 maddenin hepsi girer, not yok' ($b2 -match '- İlke 20: x{280}' -and $b2 -notmatch 'sığmadı')
    Metin-Yaz (Join-Path $yk 'ekip-ilkeleri.md') $ilEski
    Dogrula 'eski sabit 3000 kesimi kalmadı' ((Metin-Oku (Join-Path $Kaynak 'ortak.ps1')) -notmatch 'Substring\(0, 3000\)')

    Write-Host ''; Write-Host 'Y4: başarısız değerlendirme döngüyü durdurmaz, 2 saat sonra yeniden denenir'
    Metin-Yaz (Yonetim-Istek-Yolu) 'istek'
    Model-Yanit 'sahte-cto' 'hata' $true
    $hata = ''; try { Yonetim-Degerlendir } catch { $hata = $_.Exception.Message }
    $son = Json-Oku (Join-Path $yk 'son.json')
    Dogrula 'hata fırlatmadı; son.json başarısız, önceki özet ve öneriler korundu' (-not $hata -and $son.durum -eq 'basarisiz' -and $son.ozet -match 'düzeltme turları' -and @($son.oneriler).Count -eq 1) "$hata $($son.durum)"
    Dogrula 'istek silindi; hemen yeniden denemez' (-not (Test-Path (Yonetim-Istek-Yolu)) -and -not (Yonetim-Degerlendirmesi-Gerekli))
    $x = Json-Oku (Join-Path $yk 'son.json'); $x.zaman = (Get-Date).AddHours(-3).ToString('o'); Json-Yaz $x (Join-Path $yk 'son.json')
    Dogrula '2 saatten sonra yeniden dener (biten iş varsa)' (Yonetim-Degerlendirmesi-Gerekli)
    Dogrula 'ilkeler hata sonrası korundu' ((Metin-Oku (Join-Path $yk 'ekip-ilkeleri.md')) -match 'flutter doctor')

    Write-Host ''; Write-Host 'Y5: kadro: CTO Yönetimʼde, koordinasyon rolleri Teknik koordinasyonʼda; CTO yardım listesinde yok'
    $kk = [IO.File]::ReadAllText((Join-Path $Kaynak 'kadro.json'), $bom) | ConvertFrom-Json
    $dep = @{}; foreach ($u in $kk.uyeler) { $dep[[string]$u.anahtar] = [string]$u.departman }
    Dogrula 'cto Yönetim; lider, sorun-giderici, mimar Teknik koordinasyon' ($dep['cto'] -eq 'Yönetim' -and $dep['lider'] -eq 'Teknik koordinasyon' -and $dep['sorun-giderici'] -eq 'Teknik koordinasyon' -and $dep['mimar'] -eq 'Teknik koordinasyon') (($dep.GetEnumerator() | Where-Object { $_.Key -in @('cto', 'lider', 'sorun-giderici', 'mimar') } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    Dogrula 'ayarlarda CTO zinciri ve yonetim bloğu' (([IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json).roller.cto.Count -ge 1)
    Dogrula 'yardım talimatında CTO önerilmez' ((Yardim-Talimati-Metni) -notmatch '- cto \(')
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) {
        try { Get-ChildItem -LiteralPath $YolCalisma -Directory -ErrorAction SilentlyContinue | ForEach-Object { Git-T -C $repo worktree remove --force $_.FullName | Out-Null } } catch {}
        Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host "Kum havuzu korundu: $kum" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
