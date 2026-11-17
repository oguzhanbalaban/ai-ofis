<#
yardimlasma.test.ps1 - Ekip içi yardımlaşma (yardim.ps1) ve Test Uzmanı akışını sınar. Çevrimdışıdır: gerçek Claude / Codex
çağrılmaz, gerçek gorevler\ klasörüne, bildirimlere ve e-postaya dokunulmaz. Sahte ajan --model değerine göre
cikti-<model>.txt dosyasını (yoksa sahte-cikti.txt) stream-json biçiminde basar.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\yardimlasma.test.ps1 [-Kaynak <betik klasörü>] [-Koru]

  I  istem: yardım talimatı ve gelen yardımlar doğru adımlara eklenir
  A  akış: geliştirici yardım ister -> Yönetici ATA -> yardım işi -> bitince geliştirme sürer (sonuç istemde)
  K  kararlar: YANIT, KULLANICI (yanıttan sonra kaldığı aşama), ISE_ALIM, geçersiz atama, hak sınırı, zincir sınırı
  P  plan ön işleri (YARDIM: satırları), Yöneticinin kabulde doğrudan yardım istemesi
  T  Test Uzmanı: ek incelemede tam yetkiyle çalışır, raporu yazılır, ağaçta bıraktığı değişiklikler geri alınır,
     ek incelemede yardım isterse görev yardım akışına geçer
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-yardim-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    (& $uye 'lider' 'Yönetici' $false 'oku' ''), (& $uye 'sorun-giderici' 'Sorun Giderici' $false 'oku' ''), (& $uye 'gelistirici' 'Geliştirici' $false 'yaz' ''),
    (& $uye 'denetci' 'Denetçi' $false 'oku' ''), (& $uye 'sistem' 'Sistem Yöneticisi' $false 'tam' ''), (& $uye 'ag' 'Network' $false 'tam' ''),
    (& $uye 'tester' 'Test Uzmanı' $true 'tam' 'sahte-tester'), (& $uye 'tasarimci-ui' 'UI/UX Tasarımcısı' $true 'yaz' 'sahte-tasarimci'), (& $uye 'ik' 'İnsan Kaynakları' $true 'oku' 'sahte-ik')) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
# git'in uyarıları (LF/CRLF) Stop kipinde hata sayılmasın
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
# Test için git deposu (geliştiricinin işi index'te)
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
    # ------------------------------------------------------------ I
    Write-Host ''; Write-Host 'I1: yardım talimatı yalnızca uygun adımlara eklenir'
    $g = Test-Gorevi '9301-istem' 'gelistirme'
    $script:AktifGorev = $g.id
    $kk = Join-Path $kum 'kayit-i1'
    Yanit 'tamam'
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-GELISTIRICI' -Klasor $kum -KayitKlasoru $kk -Etiket 'gelistirme')
    $i1 = Son-Istem $kk 'gelistirme-*.istem.md'
    Dogrula 'geliştirici isteminde yardım talimatı ve ekip listesi var' ($i1 -match 'EKİPTEN YARDIM İSTEME' -and $i1 -match 'tester \(Test Uzmanı\)' -and $i1 -match '```yardim')
    Dogrula 'talimatta kullanıcı testi kuralı var' ($i1 -match 'simüle kullanıcı testi')
    [void](Ajan-Cagir -Rol 'lider' -Istem 'ISTEM-PLAN' -Klasor $kum -KayitKlasoru $kk -Etiket 'plan')
    Dogrula 'Yöneticinin plan isteminde yok (plan "YARDIM:" satırlarını kullanır)' (-not ((Son-Istem $kk 'plan-*.istem.md') -match 'EKİPTEN YARDIM İSTEME'))
    [void](Ajan-Cagir -Rol 'lider' -Istem 'ISTEM-KABUL' -Klasor $kum -KayitKlasoru $kk -Etiket 'kabul')
    Dogrula 'Yöneticinin kabul isteminde var' ((Son-Istem $kk 'kabul-*.istem.md') -match 'EKİPTEN YARDIM İSTEME')
    [void](Ajan-Cagir -Rol 'sorun-giderici' -Istem 'ISTEM-COZUM' -Klasor $kum -KayitKlasoru $kk -Etiket 'cozum')
    Dogrula 'Sorun Gidericinin isteminde yok' (-not ((Son-Istem $kk 'cozum-*.istem.md') -match 'EKİPTEN YARDIM İSTEME'))
    $script:AktifGorev = ''
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-SOHBET' -Klasor $kum -KayitKlasoru $kk -Etiket 'sohbet')
    Dogrula 'görevsiz (sohbet) çağrıda yok' (-not ((Son-Istem $kk 'sohbet-*.istem.md') -match 'EKİPTEN YARDIM'))
    $script:AktifGorev = $g.id; $Ayar.yardimlasma.etkin = $false
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'ISTEM-KAPALI' -Klasor $kum -KayitKlasoru (Join-Path $kum 'kayit-i1b') -Etiket 'gelistirme')
    Dogrula 'ayar kapalıyken eklenmez' (-not ((Son-Istem (Join-Path $kum 'kayit-i1b') 'gelistirme-*.istem.md') -match 'EKİPTEN YARDIM'))
    $Ayar.yardimlasma.etkin = $true; $script:AktifGorev = ''

    # ------------------------------------------------------------ A
    Write-Host ''; Write-Host 'A1: geliştirici iş sırasında yardım istiyor (adım başarısız sayılmaz)'
    $g = Test-Gorevi '9302-akis' 'gelistirme'
    Yanit ("Ekran kodunu yazdım ama test edemiyorum." + (Yardim-Blogu 'Flutter SDK kur ve flutter test çalışsın' 'sistem'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama yardim, dönüş gelistirme, deneme 0' ($d.asama -eq 'yardim' -and $d.yardim_donus_asama -eq 'gelistirme' -and [int]$d.deneme -eq 0 -and -not $d.sonraki_deneme) "$($d.asama)/$($d.yardim_donus_asama)/$($d.deneme)"
    Dogrula 'yardim-istek-1.md yazıldı; geçmişte "Geliştirici yardım istedi", "deneme başarısız" yok' ((Test-Path (Join-Path (Gorev-Klasoru $g.id) 'yardim-istek-1.md')) -and ((Olaylar $d) -contains 'Geliştirici yardım istedi') -and -not ((Olaylar $d) -contains 'deneme başarısız'))
    Dogrula 'isteğin içeriği kaydedildi' ($d.yardim_isteyen -eq 'gelistirici' -and $d.yardim_istek -match 'Flutter SDK' -and [int]$d.yardim_sayisi -eq 1)
    Dogrula 'yardim etkin aşama (döngü seçebilir)' ($AktifAsamalar -contains $d.asama)

    Write-Host ''; Write-Host 'A2: Yönetici ATA -> sistem yöneticisine yardım işi'
    $once = Gorev-Sayisi
    Yanit "KARAR: ATA`nKIM: sistem`nBASLIK: Flutter SDK kurulumu`n`n## Gerekçe`nKurulum sistemin işi.`n`n## İş`nFlutter SDK'yı kur ve PATH'e ekle.`n`n## Kabul`n- flutter --version çalışır"
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    $yid = @($d.yardim_bekleyen)[0]
    $y = $null; if ($yid) { $y = Gorev-Oku $yid }
    Dogrula 'görev yardım bekliyor, bir yardım işi açıldı' ($d.asama -eq 'yardim_bekliyor' -and @($d.yardim_bekleyen).Count -eq 1 -and (Gorev-Sayisi) -eq ($once + 1)) "$($d.asama)"
    Dogrula 'yardım işi: altyapı, öncelik 1, ana_gorev bağlı, başlık' ($y -and $y.tip -eq 'altyapi' -and [int]$y.oncelik -eq 1 -and $y.ana_gorev -eq $g.id -and $y.baslik -eq 'Flutter SDK kurulumu')
    Dogrula 'yardım işinin tanımında açan ve iş var' ((Gorev-Metni $y) -match 'Yönetici \(Geliştirici istedi\) açtı' -and (Gorev-Metni $y) -match "Flutter SDK'yı kur")
    Dogrula 'yardim-karar-1.md yazıldı' (Test-Path (Join-Path (Gorev-Klasoru $g.id) 'yardim-karar-1.md'))
    Dogrula 'beklerken seçilmez' (-not ((Siradaki-Gorev) -and (Siradaki-Gorev).id -eq $g.id))

    Write-Host ''; Write-Host 'A3: yardım işi bitince görev geliştirmeden sürer, sonuç sonraki istemde'
    Yardim-Bekleyenleri-Kontrol
    Dogrula 'yardım bitmeden sürmez' ((Gorev-Oku $g.id).asama -eq 'yardim_bekliyor')
    $y.asama = 'tamam'; Ayarla $y 'ozet' 'Flutter 3.38 kuruldu; flutter test çalışıyor.'; Gorev-Kaydet $y
    Metin-Yaz (Join-Path (Gorev-Klasoru $yid) 'sonuc.md') "# Sonuç`n`nflutter --version: 3.38"
    Yardim-Bekleyenleri-Kontrol
    $d = Gorev-Oku $g.id
    $ys = Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')
    Dogrula 'aşama gelistirme, geçmişte "yardım geldi"' ($d.asama -eq 'gelistirme' -and ((Olaylar $d) -contains 'yardım geldi')) "$($d.asama)"
    Dogrula 'yardim-sonuclari.md özet ve sonucu içeriyor' ($ys -match 'Flutter 3.38 kuruldu' -and $ys -match 'flutter --version: 3.38')
    Yanit 'Kod tamam.'
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    $ist = Son-Istem (Tur-Klasoru $d) 'gelistirme-*.istem.md'
    Dogrula 'geliştirici yeniden çalıştı, isteminde EKİPTEN GELEN YARDIM ve sonuç var' ($ist -match 'EKİPTEN GELEN YARDIM' -and $ist -match 'Flutter 3.38 kuruldu')
    Dogrula 'adım normal ilerledi (kontrol)' ($d.asama -eq 'kontrol') "$($d.asama)"

    # ------------------------------------------------------------ K
    Write-Host ''; Write-Host 'K1: denetçi yardım istiyor, Yönetici YANIT veriyor -> denetim yeniden'
    $g = Test-Gorevi '9303-yanit' 'denetim' @{ dal = 'ekip/9303'; temel_commit = $temel; calisma_klasoru = $repo; gelistirici = 'claude/sahte-gelistirici' }
    Model-Yanit 'sahte-denetci' ("KARAR: DUZELT`n`nTest sonucu görmeden onaylayamam." + (Yardim-Blogu 'flutter test sonucunu kim üretecek?'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'denetçinin isteği: aşama yardim, dönüş denetim, yeni tur açılmadı' ($d.asama -eq 'yardim' -and $d.yardim_donus_asama -eq 'denetim' -and [int]$d.tur -eq 1 -and $d.yardim_isteyen -eq 'denetci') "$($d.asama) tur=$($d.tur)"
    Model-Yanitlari-Sil
    Yanit "KARAR: YANIT`n`n## Gerekçe`nx`n`n## Yanıt`nTest sonucu kontrol.md içinde; onu kullan."
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    Dogrula 'aşama denetim, yanıt yardım sonuçlarında' ($d.asama -eq 'denetim' -and (Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')) -match 'kontrol.md içinde') "$($d.asama)"
    Dogrula 'geçmişte "Yönetici yanıtladı"' ((Olaylar $d) -contains 'Yönetici yanıtladı')

    Write-Host ''; Write-Host 'K2: KULLANICI -> soru; kullanıcı yanıtlayınca kaldığı aşamadan (plan değil)'
    $g = Test-Gorevi '9304-kullanici' 'gelistirme'
    Yanit ("Kod hazır." + (Yardim-Blogu 'GitHub erişim izni gerekiyor'))
    Gorev-Ilerlet $g
    Yanit "KARAR: KULLANICI`n`n## Kullanıcıya`nDepoya yazma izni verir misin?"
    Gorev-Ilerlet (Gorev-Oku $g.id)
    $d = Gorev-Oku $g.id
    Dogrula 'bekliyor_kullanici, soru_donus_asama gelistirme, sorular.md' ($d.asama -eq 'bekliyor_kullanici' -and $d.soru_donus_asama -eq 'gelistirme' -and (Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'sorular.md')) -match 'yazma izni')
    Dogrula 'bildirim "Yönetici soru soruyor"' (@(Bildirimler | Where-Object { $_.baslik -like 'Yönetici soru soruyor*' -and $_.metin -match '9304' }).Count -eq 1)
    Start-Sleep -Milliseconds 1100
    $f = Join-Path (Gorev-Klasoru $g.id) 'gorev.md'; Metin-Yaz $f ((Metin-Oku $f) + "`n### Yanıt`nİzin verdim.")
    Bekleyenleri-Kontrol
    $d = Gorev-Oku $g.id
    Dogrula 'yanıttan sonra aşama gelistirme' ($d.asama -eq 'gelistirme' -and -not $d.soru_donus_asama) "$($d.asama)"

    Write-Host ''; Write-Host 'K3: ISE_ALIM -> İK işe alım yardım işi'
    $g = Test-Gorevi '9305-isealim' 'gelistirme'
    Yanit ("x" + (Yardim-Blogu 'Seslendirme gerekiyor'))
    Gorev-Ilerlet $g
    Yanit "KARAR: ISE_ALIM`nARANAN: Türkçe seslendirme sanatçısı`nBASLIK: Seslendirme`n`n## İş`nAna menü için 3 cümle seslendir.`n`n## Kabul`n- 3 WAV"
    Gorev-Ilerlet (Gorev-Oku $g.id)
    $d = Gorev-Oku $g.id; $y = Gorev-Oku (@($d.yardim_bekleyen)[0])
    Dogrula 'yardım işi uzman, ise_alim_aranan dolu, hedef boş' ($d.asama -eq 'yardim_bekliyor' -and $y.tip -eq 'uzman' -and $y.ise_alim_aranan -eq 'Türkçe seslendirme sanatçısı' -and -not $y.hedef_rol)

    Write-Host ''; Write-Host 'K4: geçersiz atama (geliştiriciye) -> yanıt olarak iletilir'
    $g = Test-Gorevi '9306-gecersiz' 'gelistirme'
    Yanit ("x" + (Yardim-Blogu 'şu fonksiyonu yaz'))
    Gorev-Ilerlet $g
    $once = Gorev-Sayisi
    Yanit "KARAR: ATA`nKIM: gelistirici`n`n## İş`nBunu kendin yaz: hesapla() fonksiyonunu ekle."
    Gorev-Ilerlet (Gorev-Oku $g.id)
    $d = Gorev-Oku $g.id
    Dogrula 'yeni görev açılmadı, aşama gelistirme, iş metni yanıt olarak geldi' ((Gorev-Sayisi) -eq $once -and $d.asama -eq 'gelistirme' -and (Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'yardim-sonuclari.md')) -match 'hesapla\(\)')

    Write-Host ''; Write-Host 'K5: yardım hakkı dolunca istek normal başarısızlık sayılır'
    $g = Test-Gorevi '9307-hak' 'gelistirme' @{ yardim_sayisi = 4 }
    Yanit ("x" + (Yardim-Blogu 'yine yardım'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama gelistirme, deneme 1' ($d.asama -eq 'gelistirme' -and [int]$d.deneme -eq 1 -and [string]$d.son_hata -match 'yardım hakkı doldu') "$($d.asama)/$($d.deneme)"

    Write-Host ''; Write-Host 'K6: zincir sınırında Yönetici yeni yardım işi açamaz'
    $p1 = Test-Gorevi '9308-ana' 'yardim_bekliyor'
    $p2 = Test-Gorevi '9309-yardim1' 'gelistirme' @{ tip = 'uzman'; ana_gorev = '9308-ana' }
    $p3 = Test-Gorevi '9310-yardim2' 'gelistirme' @{ tip = 'uzman'; ana_gorev = '9309-yardim1'; sorumlu = 'tasarimci-ui' }
    Model-Yanit 'sahte-tasarimci' ("x" + (Yardim-Blogu 'kurulum lazım' 'sistem'))
    Gorev-Ilerlet $p3
    Model-Yanitlari-Sil
    $once = Gorev-Sayisi
    Yanit "KARAR: ATA`nKIM: sistem`n`n## İş`nKur.`n`n## Yanıt`nZincir sınırı; elindekiyle bitir."
    Gorev-Ilerlet (Gorev-Oku $p3.id)
    $d = Gorev-Oku $p3.id
    Dogrula 'yeni görev yok, yanıtla geri döndü' ((Gorev-Sayisi) -eq $once -and $d.asama -eq 'gelistirme') "$($d.asama)"

    # ------------------------------------------------------------ P
    Write-Host ''; Write-Host 'P1: plan ön işleri (YARDIM: satırları) -> geliştirmeden önce açılır'
    $g = Test-Gorevi '9311-plan' 'plan'
    $once = Gorev-Sayisi
    Yanit "KARAR: PLAN_HAZIR`nEK_INCELEME: tester`nYARDIM: sistem | Flutter SDK kur`nYARDIM: tester | test senaryolarını hazırla`nYARDIM: gelistirici | geçersiz satır`n`n## Özet`nplan"
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'plan.md yazıldı, ek inceleme tester' ((Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'plan.md')) -match 'YARDIM: sistem' -and @($d.ek_inceleme) -contains 'tester')
    Dogrula 'iki ön iş açıldı (geçersiz satır atlandı), dönüş gelistirme' ($d.asama -eq 'yardim_bekliyor' -and @($d.yardim_bekleyen).Count -eq 2 -and (Gorev-Sayisi) -eq ($once + 2) -and $d.yardim_donus_asama -eq 'gelistirme')
    $tipler = @($d.yardim_bekleyen | ForEach-Object { (Gorev-Oku $_).tip }) -join ','
    Dogrula 'sistem -> altyapı, tester -> uzman' ($tipler -eq 'altyapi,uzman') $tipler
    foreach ($i in @($d.yardim_bekleyen)) { $x = Gorev-Oku $i; $x.asama = 'tamam'; Ayarla $x 'ozet' "bitti $i"; Gorev-Kaydet $x }
    Yardim-Bekleyenleri-Kontrol
    Dogrula 'ikisi de bitince geliştirme başlar' ((Gorev-Oku $g.id).asama -eq 'gelistirme')

    Write-Host ''; Write-Host 'P2: Yönetici kabulde tester istiyor -> değerlendirme adımı olmadan doğrudan yardım işi'
    Git-T -C $repo checkout -q -b ekip/9312
    [IO.File]::WriteAllText((Join-Path $repo 'b.txt'), "b`n", $ascii)
    $g = Test-Gorevi '9312-kabul' 'kabul' @{ dal = 'ekip/9312'; temel_commit = $temel; calisma_klasoru = $repo }
    Yanit ("KARAR: KABUL`nCOMMIT: x`nOZET: y" + (Yardim-Blogu 'uygulamayı 5 kullanıcıyla test et' 'tester'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id; $y = Gorev-Oku (@($d.yardim_bekleyen)[0])
    Dogrula 'doğrudan yardım işi (tester), dönüş kabul' ($d.asama -eq 'yardim_bekliyor' -and $d.yardim_donus_asama -eq 'kabul' -and $y.hedef_rol -eq 'tester' -and $y.kaynak_klasor -eq $repo) "$($d.asama) $($y.hedef_rol)"

    # ------------------------------------------------------------ T
    Write-Host ''; Write-Host 'T1: test sonrası ağaç temizliği (index korunur)'
    Git-T -C $repo add -A    # geliştiricinin işi index'te (b.txt)
    [IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "testçi bozdu`n", $ascii)
    [IO.File]::WriteAllText((Join-Path $repo 'tester-kalinti.txt'), "x`n", $ascii)
    $n = Test-Sonrasi-Agaci-Temizle $repo
    $durum = (Git-T -C $repo status --porcelain) -join ' | '
    Dogrula '2 değişiklik geri alındı, b.txt index''te kaldı' ($n -eq 2 -and (Test-Path (Join-Path $repo 'b.txt')) -and -not (Test-Path (Join-Path $repo 'tester-kalinti.txt')) -and ((Get-Content (Join-Path $repo 'a.txt')) -eq 'a') -and $durum -match '^A  b.txt') $durum

    Write-Host ''; Write-Host 'T2: denetçi onaylar, Test Uzmanı ek incelemede tam yetkiyle çalışır ve düzeltme ister'
    $g = Test-Gorevi '9313-tester' 'denetim' @{ dal = 'ekip/9312'; temel_commit = $temel; calisma_klasoru = $repo; gelistirici = 'claude/sahte-gelistirici'; ek_inceleme = @('tester') }
    Model-Yanit 'sahte-denetci' "KARAR: ONAY`n`n## Bulgular`nyok"
    Model-Yanit 'sahte-tester' "KARAR: DUZELT`n`n## Test özeti`nKayıt ekranı çöküyor.`n`n## Simüle kullanıcı testi`n5 personadan 2'si tamamladı."
    Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    $tk = Join-Path (Gorev-Klasoru $g.id) 'tur1'
    $cagri = @(Get-Content (Join-Path $kum 'cagrilar.log') | Where-Object { $_ -match 'sahte-tester' })
    Dogrula 'tester tam yetkiyle çağrıldı' ($cagri.Count -eq 1 -and $cagri[0] -match 'bypassPermissions')
    Dogrula 'tester raporu test-raporu.md ve inceleme-tester.md' ((Test-Path (Join-Path $tk 'test-raporu.md')) -and (Test-Path (Join-Path $tk 'inceleme-tester.md')))
    Dogrula 'tester isteminde test klasörü (calisma\<no>-test) ve talimat var' ((Son-Istem $tk 'inceleme-tester-*.istem.md') -match '9313-tester-test' -and (Son-Istem $tk 'inceleme-tester-*.istem.md') -match 'simüle kullanıcı testi')
    Dogrula 'düzeltme istendi: yeni tur' ([int]$d.tur -eq 2 -and $d.asama -eq 'gelistirme' -and (Metin-Oku (Join-Path (Tur-Klasoru $d) 'geri-bildirim.md')) -match 'Kayıt ekranı çöküyor') "$($d.asama) tur=$($d.tur)"

    Write-Host ''; Write-Host 'T3: Test Uzmanı ek incelemede yardım isterse görev yardım akışına geçer'
    $g = Test-Gorevi '9314-tester-yardim' 'denetim' @{ dal = 'ekip/9312'; temel_commit = $temel; calisma_klasoru = $repo; gelistirici = 'claude/sahte-gelistirici'; ek_inceleme = @('tester') }
    Model-Yanit 'sahte-tester' ("Uygulamayı çalıştıramadım." + (Yardim-Blogu 'Android emülatörü kur' 'sistem'))
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama yardim, isteyen tester, dönüş denetim' ($d.asama -eq 'yardim' -and $d.yardim_isteyen -eq 'tester' -and $d.yardim_donus_asama -eq 'denetim') "$($d.asama) $($d.yardim_isteyen)"
    Model-Yanitlari-Sil
} catch {
    $script:Kalan++
    Write-Host ("  [HATA] Test çöktü: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
}

Write-Host ''
Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
if ($script:Kalan -eq 0 -and -not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "Kum havuzu korundu: $kum (günlük: $(Join-Path $kum 'gunluk'))" }
exit $script:Kalan
