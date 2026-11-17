<#
birlikte-puan-tasima.test.ps1 - Birlikte çalışma (anlık yardım), Fibonacci puanlama ve panoda taşımayı sınar. Çevrimdışıdır:
gerçek Claude / Codex çağrılmaz, gerçek gorevler\ klasörüne, bildirimlere ve e-postaya dokunulmaz. Sahte ajan --model değerine
göre cikti-<model>.txt dosyasını (yoksa sahte-cikti.txt) stream-json biçiminde basar.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\birlikte-puan-tasima.test.ps1 [-Kaynak <betik klasörü>] [-Koru]

  B  birlikte çalışma: Software Developer paket / test için yardım ister -> Engineering Manager BIRLIKTE -> System Administrator
     aynı adımda, isteyenin çalışma klasöründe tam yetkiyle çalışır; sonuç istemde; .ekip-yardim git dışında; geçersiz / başarısız durum
  P  puanlama: Puan-Coz / Puan-Yuvarla; Engineering Manager planda, çalışan ilk üstlenişte puanlar; ikinci kez sorulmaz; ayar kapalıysa yok
  T  panoda taşıma: geri taşıma yeni tur; ileri taşıma; kurallar; takılan / tamamlanmış iş; adım sürerken taşıma; durum.ps1 -Tasi
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-birlikte-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    denetci = @(& $s 'sahte-denetci'); sistem = @(& $s 'sahte-sistem'); ag = @(& $s 'sahte-ag') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $true; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName yardimlasma -NotePropertyValue ([pscustomobject]@{ etkin = $true; gorev_basina_en_fazla = 4; derinlik = 2 })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $uzman, $yetki, $model) $o = [ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = (-not $uzman); uzman_isi = $uzman; yetki = $yetki; uzmanlik = "$ad işleri" }
    if ($model) { $o.araclar = @(& $s $model) }; if ($a -eq 'tester') { $o.istem = 'istemler\kadro\tester.md' }; [pscustomobject]$o }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @(
    (& $uye 'lider' 'Engineering Manager' $false 'oku' ''), (& $uye 'sorun-giderici' 'Incident Manager' $false 'oku' ''), (& $uye 'gelistirici' 'Software Developer' $false 'yaz' ''),
    (& $uye 'denetci' 'Code Reviewer' $false 'oku' ''), (& $uye 'sistem' 'System Administrator' $false 'tam' ''), (& $uye 'ag' 'Network Engineer' $false 'tam' ''),
    (& $uye 'tester' 'QA Engineer' $true 'tam' 'sahte-tester'), (& $uye 'tasarimci-ui' 'UI/UX Designer' $true 'yaz' 'sahte-tasarimci'), (& $uye 'ik' 'HR Specialist' $true 'oku' 'sahte-ik')) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
# git'in uyarıları (LF/CRLF) Stop kipinde hata sayılmasın
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
# Test için git deposu (Software Developerʼın işi index'te)
$repo = Join-Path $kum 'depo'
New-Item -ItemType Directory -Force $repo | Out-Null
Git-T -C $repo init -q -b main
[IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "a`n", $ascii)
Git-T -C $repo add -A
Git-T -C $repo -c user.name=t -c user.email=t@t commit -q -m ilk
$temel = (Git-T -C $repo rev-parse HEAD).Trim()
# Sahte ajan: --model değerine göre çıktı seçer (SHIFT %0'ı da kaydırdığından klasör baştan saklanır)
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo %*', 'set MODEL=',
    ':dongu', 'if "%~1"=="" goto bitti', 'if "%~1"=="--model" set MODEL=%~2', 'shift', 'goto dongu', ':bitti',
    'if defined MODEL if exist "%D%cikti-%MODEL%.txt" goto ozel', 'type "%D%sahte-cikti.txt"', 'exit /b 0',
    ':ozel', 'type "%D%cikti-%MODEL%.txt"', 'exit /b 0'
) -join "`r`n") + "`r`n", $ascii)
function Akis([string]$Metin) {
    $satirlar = @(
        ([ordered]@{ type = 'system'; subtype = 'init' } | ConvertTo-Json -Compress),
        ([ordered]@{ type = 'assistant'; message = [ordered]@{ id = 'm1'; usage = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 10; cache_creation_input_tokens = 0; output_tokens = 5 } } } | ConvertTo-Json -Compress -Depth 5),
        ([ordered]@{ type = 'result'; subtype = 'success'; is_error = $false; num_turns = 1; result = $Metin; usage = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 10; cache_creation_input_tokens = 0; output_tokens = 5 } } | ConvertTo-Json -Compress -Depth 5))
    return (($satirlar -join "`n") + "`n")
}
function Yanit([string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), (Akis $Metin), $utf8) }
function Model-Yanit([string]$Model, [string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum "cikti-$Model.txt"), (Akis $Metin), $utf8) }
function Model-Yanitlari-Sil { Get-ChildItem -LiteralPath $kum -Filter 'cikti-*.txt' | Remove-Item -Force }
$BT = '```'
function Yardim-Blogu([string]$Ne, [string]$Kim = '') { return "`n`n${BT}yardim`n" + ([ordered]@{ ne = $Ne; neden = 'test nedeni'; kim = $Kim; kabul = @('ölçüt 1') } | ConvertTo-Json -Compress) + "`n$BT`n" }
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
function Test-Gorevi([string]$Id, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    $wt = Join-Path $YolCalisma $Id
    New-Item -ItemType Directory -Force $wt | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# Test $Id`n`nUygulama yaz. Kabul: 5 kullanıcıdan 4'ü beğenmeli."
    Metin-Yaz (Join-Path $gk 'plan.md') "KARAR: PLAN_HAZIR`n`n## Plan`n1. yaz"
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; proje = 'test'; klasor = $repo; oncelik = 2; asama = $Asama; tur = 1; max_tur = 3
        deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); calisma_klasoru = $wt }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Olaylar($G) { return @($G.gecmis | ForEach-Object { [string]$_.olay }) }
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return (Metin-Oku $f.FullName) }; return '' }
function Bildirimler { $f = Join-Path $YolDurum 'bildirimler.jsonl'; if (-not (Test-Path $f)) { return @() }; return @(Get-Content $f -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
function Gorev-Sayisi { return @(Get-ChildItem -LiteralPath $YolGorev -Directory).Count }

try {
    # ------------------------------------------------------------ B: birlikte çalışma
    Write-Host ''; Write-Host 'B1: Software Developer paket kurulumu ve test için yardım ister; talimat kapsamı'
    $g = Test-Gorevi '9401-birlikte' 'gelistirme'
    $wt = Join-Path $YolCalisma $g.id
    Remove-Item -LiteralPath $wt -Recurse -Force
    Git-T -C $repo worktree add -q -b ekip/9401 $wt | Out-Null
    $g.calisma_klasoru = $wt; Gorev-Kaydet $g
    $script:AktifGorev = $g.id
    $kk = Join-Path $kum 'kayit-b1'
    Yanit 'tamam'
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-GELISTIRICI' -Klasor $kum -KayitKlasoru $kk -Etiket 'gelistirme')
    $i = Son-Istem $kk 'gelistirme-*.istem.md'
    Dogrula 'yardım talimatı paket, internet ve test çalıştırmayı kapsıyor' ($i -match 'kütüphane / paket indirip kurmak' -and $i -match 'internet sitesine' -and $i -match 'küçük deneme koşturmaları' -and $i -match '"hemen"')
    [void](Ajan-Cagir -Rol 'sistem' -Istem 'ISTEM-BIRLIKTE' -Klasor $kum -KayitKlasoru $kk -Etiket 'birlikte-sistem')
    Dogrula 'birlikte çalışan yardımcıya yardım talimatı eklenmez' (-not ((Son-Istem $kk 'birlikte-sistem-*.istem.md') -match 'EKİPTEN YARDIM İSTEME'))
    $script:AktifGorev = ''

    Yanit ("Kodu yazdım; axios gerekiyor ve testleri çalıştıramıyorum." + (Yardim-Blogu 'npm install axios ve npm test çalıştır' 'sistem'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama yardim, dönüş gelistirme' ($d.asama -eq 'yardim' -and $d.yardim_donus_asama -eq 'gelistirme') "$($d.asama)"
    $istek = Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-istek-1.md')
    Dogrula 'istek dosyasında çalışma klasörü yazılı' ($istek -match [regex]::Escape($wt))

    Write-Host ''; Write-Host 'B2: Engineering Manager BIRLIKTE -> System Administrator hemen, aynı adımda, isteyenin klasöründe çalışır'
    $once = Gorev-Sayisi
    Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue
    Yanit "KARAR: BIRLIKTE`nKIM: sistem`n`n## Gerekçe`nKısa kurulum ve test.`n`n## İş`nnpm install axios; npm test`n`n## Kabul`n- test sonucu raporda"
    Model-Yanit 'sahte-sistem' "## Yapılanlar`nnpm install axios@1.7.9`n`n## Sonuç`naxios 1.7.9 kuruldu; npm test: 12 geçti, 0 kaldı.`n`n## Açık kalanlar`nyok"
    Gorev-Ilerlet $d
    Model-Yanitlari-Sil
    $d = Gorev-Oku $g.id
    $log = Metin-Oku (Join-Path $kum 'cagrilar.log')
    $ys = Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')
    Dogrula 'yeni görev açılmadı, iş gelistirmeye döndü' ((Gorev-Sayisi) -eq $once -and $d.asama -eq 'gelistirme') "$($d.asama)"
    Dogrula 'yardımcı tam yetkiyle çağrıldı' ($log -match 'sahte-sistem' -and $log -match 'bypassPermissions')
    Dogrula 'sonuç yardim-sonuclari.md ve yardim-birlikte-1.md dosyasında' ($ys -match 'axios 1.7.9 kuruldu' -and $ys -match 'birlikte çalışıldı' -and (Test-Path (Join-Path (Gorev-Klasoru $g.id) 'yardim-birlikte-1.md')))
    Dogrula 'birlikte kaydı ve geçmiş olayları' (@($d.birlikte).Count -eq 1 -and $d.birlikte[0].rol -eq 'sistem' -and $d.birlikte[0].basarili -and ((Olaylar $d) -match 'birlikte çalıştı').Count -ge 1)
    $ex = Join-Path $repo '.git\info\exclude'
    Dogrula '.ekip-yardim klasörü açıldı ve git dışında tutuluyor' ((Test-Path (Join-Path $wt '.ekip-yardim')) -and ((Metin-Oku $ex) -match '\.ekip-yardim/'))
    [IO.File]::WriteAllText((Join-Path $wt '.ekip-yardim\belge.txt'), 'x', $ascii)
    $durum = (Git-T -C $wt status --porcelain) -join "`n"
    Dogrula 'indirilen dosyalar git durumunda görünmüyor' ($durum -notmatch 'ekip-yardim') $durum
    $script:AktifGorev = $g.id
    $kk2 = Join-Path $kum 'kayit-b2'
    Yanit 'tamam'
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-SONRA' -Klasor $wt -KayitKlasoru $kk2 -Etiket 'gelistirme')
    Dogrula 'sonraki geliştirme isteminde yardım sonucu var' ((Son-Istem $kk2 'gelistirme-*.istem.md') -match 'axios 1.7.9 kuruldu')
    $script:AktifGorev = ''

    Write-Host ''; Write-Host 'B3: geçersiz BIRLIKTE (isteyenin kendisi) yanıta döner; yardımcı çalışamazsa iş yine sürer'
    $g = Test-Gorevi '9402-birlikte' 'gelistirme'
    Yanit ("Kurulum gerekiyor." + (Yardim-Blogu 'pip install requests' ''))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Yanit "KARAR: BIRLIKTE`nKIM: gelistirici`n`n## İş`nkendin kur"
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    Dogrula 'isteyene BIRLIKTE verilemez: Engineering Manager yanıtı olarak döner' ($d.asama -eq 'gelistirme' -and ((Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')) -match 'yanıtı')) "$($d.asama)"
    Yanit ("Yine kurulum gerekiyor." + (Yardim-Blogu 'pip install requests' 'sistem'))
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    $ayarRol = $Ayar.roller.sistem
    $Ayar.roller.sistem = @()
    Yanit "KARAR: BIRLIKTE`nKIM: sistem`n`n## İş`npip install requests"
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    $Ayar.roller.sistem = $ayarRol
    $ys = Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')
    Dogrula 'yardımcı çalışamadı: iş geliştirmeye döner, sonuçta "çalışamadı" yazar' ($d.asama -eq 'gelistirme' -and $ys -match 'birlikte çalışamadı' -and -not $d.birlikte[0].basarili) "$($d.asama)"

    # ------------------------------------------------------------ P: Fibonacci puanlama
    Write-Host ''; Write-Host 'P1: puan çözümü ve yuvarlama'
    Dogrula 'PUAN: 5 -> 5, gerekçe' ((Puan-Coz "KARAR: PLAN_HAZIR`nPUAN: 5`nPUAN_GEREKCE: iki ekran").puan -eq 5 -and (Puan-Coz "PUAN: 5`nPUAN_GEREKCE: iki ekran").gerekce -eq 'iki ekran')
    Dogrula '4 -> 5, 6 -> 5, 10 -> 8, 40 -> 21, **PUAN:** 3 -> 3' ((Puan-Yuvarla 4) -eq 5 -and (Puan-Yuvarla 6) -eq 5 -and (Puan-Yuvarla 10) -eq 8 -and (Puan-Yuvarla 40) -eq 21 -and (Puan-Coz '**PUAN:** 3').puan -eq 3)
    Dogrula 'puan yoksa ya da şablon kaldıysa boş' ($null -eq (Puan-Coz 'KARAR: ONAY') -and $null -eq (Puan-Coz 'PUAN: <1|2|3|5|8|13|21>'))

    Write-Host ''; Write-Host 'P2: Engineering Manager planda puanlar; ikinci kez sorulmaz'
    $g = Test-Gorevi '9411-puan' 'plan'
    Remove-Item -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'plan.md') -Force
    Yanit "KARAR: PLAN_HAZIR`nPUAN: 4`nPUAN_GEREKCE: iki ekran ve bir API`n`n## Plan`n1. yaz"
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    $ip = Son-Istem (Kayit-Klasoru $d) 'plan-*.istem.md'
    Dogrula 'plan isteminde puanlama talimatı var' ($ip -match 'PUANLAMA \(Fibonacci' -and $ip -match 'KADRO|yetenek')
    Dogrula 'puan_yonetici = 5 (4 yuvarlandı), gerekçe ve araç kayıtlı' ($d.puan_yonetici.puan -eq 5 -and $d.puan_yonetici.rol -eq 'lider' -and $d.puan_yonetici.gerekce -eq 'iki ekran ve bir API' -and $d.puan_yonetici.arac -match 'claude/') "$($d.puan_yonetici | ConvertTo-Json -Compress)"
    Dogrula 'plan PUAN satırıyla bozulmadı (geliştirmeye geçti)' ($d.asama -eq 'gelistirme') "$($d.asama)"
    $script:AktifGorev = $d.id
    $kk = Join-Path $kum 'kayit-p2'
    Yanit 'tamam'
    [void](Ajan-Cagir -Rol 'lider' -Istem 'ISTEM-PLAN2' -Klasor $kum -KayitKlasoru $kk -Etiket 'plan')
    Dogrula 'puanı varken Engineering Managerʼa yeniden sorulmaz' (-not ((Son-Istem $kk 'plan-*.istem.md') -match 'PUANLAMA'))
    $script:AktifGorev = ''

    Write-Host ''; Write-Host 'P3: işi yapan çalışan kendi puanını verir'
    Yanit "## Yapılanlar`nyazdım`n`nPUAN: 8`nPUAN_GEREKCE: beklenenden çok dosya"
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    $ig = Son-Istem (Tur-Klasoru $d) 'gelistirme-*.istem.md'
    Dogrula 'geliştirme isteminde çalışan puanlama talimatı var' ($ig -match 'kendi açından puanla')
    Dogrula 'puan_ajan = Software Developer 8; Engineering Manager puanı korunur' ($d.puan_ajan.rol -eq 'gelistirici' -and $d.puan_ajan.puan -eq 8 -and $d.puan_yonetici.puan -eq 5) "$($d.puan_ajan | ConvertTo-Json -Compress)"
    $script:AktifGorev = $d.id
    $kk = Join-Path $kum 'kayit-p3'
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-GEL2' -Klasor $kum -KayitKlasoru $kk -Etiket 'gelistirme')
    Dogrula 'aynı çalışana ikinci turda yeniden sorulmaz' (-not ((Son-Istem $kk 'gelistirme-*.istem.md') -match 'PUANLAMA'))
    [void](Ajan-Cagir -Rol 'denetci' -Istem 'ISTEM-DEN' -Klasor $kum -KayitKlasoru $kk -Etiket 'denetim')
    Dogrula 'Code Reviewerʼa puan sorulmaz' (-not ((Son-Istem $kk 'denetim-*.istem.md') -match 'PUANLAMA'))
    $Ayar | Add-Member -Force -NotePropertyName puanlama -NotePropertyValue ([pscustomobject]@{ etkin = $false })
    $g5 = Test-Gorevi '9412-puan-kapali' 'plan'
    $script:AktifGorev = $g5.id
    [void](Ajan-Cagir -Rol 'lider' -Istem 'ISTEM-PLAN3' -Klasor $kum -KayitKlasoru $kk -Etiket 'plan')
    Dogrula 'puanlama kapalıyken sorulmaz' (-not ((Son-Istem $kk 'plan-*.istem.md') -match 'PUANLAMA'))
    $Ayar.puanlama.etkin = $true
    $script:AktifGorev = ''

    # ------------------------------------------------------------ T: panoda taşıma
    Write-Host ''; Write-Host 'T1: geri taşıma yeni tur açar, not geri bildirime yazılır'
    $g = Test-Gorevi '9421-tasi' 'denetim' @{ tur = 2; max_tur = 2 }
    $m = Gorev-Asamaya-Tasi $g 'gelistirme' 'Butonu da sola al'
    Gorev-Kaydet $g
    $d = Gorev-Oku $g.id
    $gb = Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'tur3\geri-bildirim.md')
    Dogrula 'aşama gelistirme, tur 3, max_tur 3' ($d.asama -eq 'gelistirme' -and [int]$d.tur -eq 3 -and [int]$d.max_tur -eq 3) "$($d.asama) $($d.tur)/$($d.max_tur)"
    Dogrula 'geri bildirimde taşıma ve not var' ($gb -match 'panoda geri aldı' -and $gb -match 'Butonu da sola al' -and $gb -match 'tur2')
    Dogrula 'elle_tasima kaydı ve geçmiş' ($d.elle_tasima.onceki -eq 'denetim' -and $d.elle_tasima.asama -eq 'gelistirme' -and ((Olaylar $d) -match 'panoda taşıdı').Count -eq 1) $m

    Write-Host ''; Write-Host 'T2: ileri taşıma ve kurallar'
    $g = Test-Gorevi '9422-tasi' 'gelistirme'
    [void](Gorev-Asamaya-Tasi $g 'kontrol'); Gorev-Kaydet $g
    $d = Gorev-Oku $g.id
    Dogrula 'Yapılıyor -> İnceleme: kontrol, tur değişmez' ($d.asama -eq 'kontrol' -and [int]$d.tur -eq 1)
    $hata = ''; try { [void](Gorev-Asamaya-Tasi $d 'kontrol') } catch { $hata = $_.Exception.Message }
    Dogrula 'aynı aşamaya taşınamaz' ($hata -match 'zaten') $hata
    $d.asama = 'denetim'
    [void](Gorev-Asamaya-Tasi $d 'tamamla')
    Dogrula 'İnceleme -> Tamamlandı: tamamla' ($d.asama -eq 'tamamla')
    $g = Test-Gorevi '9423-tasi' 'gelistirme'
    $hata = ''; try { [void](Gorev-Asamaya-Tasi $g 'tamamla') } catch { $hata = $_.Exception.Message }
    Dogrula 'incelemede olmayan iş tamamlanamaz' ($hata -match 'incelemedeki') $hata
    Remove-Item -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'plan.md') -Force
    $g.asama = 'plan'
    $hata = ''; try { [void](Gorev-Asamaya-Tasi $g 'gelistirme') } catch { $hata = $_.Exception.Message }
    Dogrula 'planı olmayan iş Yapılıyorʼa taşınamaz' ($hata -match 'planı yok') $hata
    $g = Test-Gorevi '9424-genel' 'bekliyor_kullanici' @{ tip = 'genel' }
    $hata = ''; try { [void](Gorev-Asamaya-Tasi $g 'plan') } catch { $hata = $_.Exception.Message }
    Dogrula 'yönlendirilmemiş iş yalnızca Sıradaʼya' ($hata -match 'yalnızca Sıra') $hata
    [void](Gorev-Asamaya-Tasi $g 'yeni')
    Dogrula 'genel iş Sıradaʼya taşınır, soru dönüşü temizlenir' ($g.asama -eq 'yeni' -and -not $g.soru_donus_asama)

    Write-Host ''; Write-Host 'T3: takılan iş taşınınca sorun giderme alanları sıfırlanır'
    $g = Test-Gorevi '9425-takili' 'takildi' @{ takildi_asama = 'denetim'; cozum_durumu = 'kullanici'; cozum_sayisi = 2; son_hata = 'x'; deneme = 3 }
    [void](Gorev-Asamaya-Tasi $g 'kontrol')
    Dogrula 'takılan iş incelemeye alındı, sayaçlar sıfır' ($g.asama -eq 'kontrol' -and -not $g.cozum_durumu -and [int]$g.cozum_sayisi -eq 0 -and [int]$g.deneme -eq 0 -and -not $g.son_hata)

    Write-Host ''; Write-Host 'T4: tamamlanmış yazılım işi yeniden açılır: çalışma ağacı dal üzerinde yeniden kurulur'
    $g = Test-Gorevi '9426-acik' 'tamam' @{ tip = 'yazilim'; dal = 'ekip/9426-acik' }
    Git-T -C $repo branch 'ekip/9426-acik' | Out-Null
    Remove-Item -LiteralPath (Join-Path $YolCalisma $g.id) -Recurse -Force
    [void](Gorev-Asamaya-Tasi $g 'gelistirme')
    Dogrula 'çalışma ağacı yeniden kuruldu, tur 2' ((Test-Path (Join-Path $g.calisma_klasoru '.git')) -and $g.asama -eq 'gelistirme' -and [int]$g.tur -eq 2) "$($g.calisma_klasoru)"

    Write-Host ''; Write-Host 'T5: adım sürerken taşınırsa adımın sonucu taşımayı ezmez'
    $g = Test-Gorevi '9427-yaris' 'gelistirme'
    $orijinalGelistirme = ${function:Adim-Gelistirme}
    ${function:Adim-Gelistirme} = {
        param($G)
        Start-Sleep -Milliseconds 30
        $disk = Gorev-Oku $G.id
        [void](Gorev-Asamaya-Tasi $disk 'plan' 'yarış testi')
        Gorev-Kaydet $disk
        Dogrula 'adım sürerken taşınan görev iptal sayılır (ajan durdurulur)' (Gorev-Iptal-mi $G.id)
        Asama-Gec $G 'kontrol' 'geliştirme bitti'
    }
    Gorev-Ilerlet $g
    ${function:Adim-Gelistirme} = $orijinalGelistirme
    $d = Gorev-Oku $g.id
    Dogrula 'diskteki taşıma korundu (plan), adım sonucu yok sayıldı' ($d.asama -eq 'plan' -and ((Olaylar $d) -contains 'taşıma sonrası adım sonucu yok sayıldı')) "$($d.asama)"
    Dogrula 'adım bitince taşıma artık "iptal" sayılmaz' (-not (Gorev-Iptal-mi $g.id))

    Write-Host ''; Write-Host 'T6: durum.ps1 -Tasi'
    $g = Test-Gorevi '9428-komut' 'denetim'
    $c = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kum 'durum.ps1') -Tasi '9428' -Asama 'gelistirme' -Not 'komuttan' 2>&1 | Out-String
    $d = Gorev-Oku $g.id
    Dogrula 'durum.ps1 -Tasi görevi taşır (not geri bildirimde)' ($d.asama -eq 'gelistirme' -and [int]$d.tur -eq 2 -and ((Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'tur2\geri-bildirim.md')) -match 'komuttan')) ($c.Trim() -split "`n")[0]
} catch {
    $script:Kalan++
    Write-Host ("  [HATA] Test çöktü: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
}

Write-Host ''
Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
if ($script:Kalan -eq 0 -and -not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "Kum havuzu korundu: $kum (günlük: $(Join-Path $kum 'gunluk'))" }
exit $script:Kalan
