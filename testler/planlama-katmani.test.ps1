<#
planlama-katmani.test.ps1 - İşi alma ve planlama katmanını (Product Manager, Codebase Explorer), iş dağılımını (Full-Stack /
Backend + Frontend Developer), QA testini ve onay kapısını sınar. Çevrimdışıdır: gerçek Claude / Codex çağrılmaz, gerçek
gorevler\ klasörüne, bildirimlere ve e-postaya dokunulmaz. Sahte ajan --model değerine göre cikti-<model>.txt dosyasını basar.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\planlama-katmani.test.ps1 [-Kaynak <betik klasörü>] [-Koru]

  U  uçtan uca: "İş ver" -> analiz (Product Manager soru sorar, kullanıcı yanıtlar, gereksinimler) -> Engineering Manager yönlendirir
     -> kesif (Codebase Explorer) -> plan (iş dağılımı backend + frontend, QA testi, ek güvenlik incelemesi) -> backend -> frontend
     -> kontrol -> test (QA hata bulur, test dosyası dala alınır, kalan değişiklik geri alınır) -> yalnızca frontend yeniden
     -> kontrol -> test (onay) -> denetim (QA raporu istemde) -> ek inceleme -> kabul -> commit (onaylar mesajda) -> tamam
  P  plan kararları: geçersiz IS satırları, tek Full-Stack parçası, QA_TESTI: hayır, güvenli / güvensiz DOGRULAMA_EKLE
  A  analiz: soru hakkı dolunca varsayımlarla sürer; katman kapalıysa ya da rolün modeli yoksa atlanır; boş depoda keşif atlanır
  O  onay kapısı: onaysız commit yok (denetime / teste döner), kullanıcı panoda tamamlattıysa not düşülerek commit
  R  rol eşlemesi ve komut: Adim-Rolu yeni aşamalar ve parça sahibi; parçayı devralma; eski kayıtlarda QA aşaması yok
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-planlama-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    denetci = @(& $s 'sahte-denetci'); sistem = @(& $s 'sahte-sistem'); ag = @(& $s 'sahte-ag'); urun = @(& $s 'sahte-urun'); kasif = @(& $s 'sahte-kasif')
    frontend = @(& $s 'sahte-frontend'); backend = @(& $s 'sahte-backend') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ.gorev.lider_kabul = $true
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $false; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName yardimlasma -NotePropertyValue ([pscustomobject]@{ etkin = $true; gorev_basina_en_fazla = 4; derinlik = 2 })
$ayarJ | Add-Member -Force -NotePropertyName paralel -NotePropertyValue ([pscustomobject]@{ etkin = $true; en_fazla = 2; adim_siniri = 12 })
$ayarJ | Add-Member -Force -NotePropertyName puanlama -NotePropertyValue ([pscustomobject]@{ etkin = $true })
$ayarJ | Add-Member -Force -NotePropertyName planlama -NotePropertyValue ([pscustomobject]@{ analiz = $true; kesif = $true; qa_testi = $true; urun_soru_hakki = 2; en_fazla_parca = 3; onay_kapisi = $true })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $uzman, $yetki, $model) $o = [ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = (-not $uzman); uzman_isi = $uzman; yetki = $yetki; uzmanlik = "$ad işleri" }
    if ($model) { $o.araclar = @(& $s $model) }; [pscustomobject]$o }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @(
    (& $uye 'lider' 'Engineering Manager' $false 'oku' ''), (& $uye 'urun' 'Product Manager' $false 'oku' ''), (& $uye 'kasif' 'Codebase Explorer' $false 'oku' ''),
    (& $uye 'sorun-giderici' 'Incident Manager' $false 'oku' ''), (& $uye 'gelistirici' 'Full-Stack Developer' $false 'yaz' ''),
    (& $uye 'frontend' 'Frontend Developer' $false 'yaz' ''), (& $uye 'backend' 'Backend Developer' $false 'yaz' ''),
    (& $uye 'denetci' 'Code Reviewer' $false 'oku' ''), (& $uye 'sistem' 'System Administrator' $false 'tam' ''), (& $uye 'ag' 'Network Engineer' $false 'tam' ''),
    (& $uye 'tester' 'QA Engineer' $true 'tam' 'sahte-tester'), (& $uye 'guvenlik' 'Security Engineer' $true 'tam' 'sahte-guvenlik'),
    (& $uye 'tasarimci-ui' 'UI/UX Designer' $true 'yaz' 'sahte-ui'), (& $uye 'ik' 'HR Specialist' $true 'oku' '')) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
function Depo-Kur([string]$Ad, [hashtable]$Dosyalar) {
    $r = Join-Path $kum $Ad
    New-Item -ItemType Directory -Force $r | Out-Null
    Git-T -C $r init -q -b main
    foreach ($k in $Dosyalar.Keys) { $f = Join-Path $r $k; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; [IO.File]::WriteAllText($f, $Dosyalar[$k], $ascii) }
    Git-T -C $r add -A
    Git-T -C $r -c user.name=t -c user.email=t@t commit -q -m ilk
    return $r
}
$repo = Depo-Kur 'depo' @{ 'README.md' = "# test`n"; 'src\app.py' = "def f():`n    return 1`n"; 'src\ui.js' = "export const a = 1;`n"; 'tests\test_app.py' = "def test_f():`n    assert True`n" }
$bosDepo = Depo-Kur 'bos-depo' @{ 'README.md' = "# bos`n" }
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @(
    [pscustomobject]@{ ad = 'test'; klasor = $repo; temel_dal = ''; dogrulama = @() }, [pscustomobject]@{ ad = 'bos'; klasor = $bosDepo; temel_dal = ''; dogrulama = @() }) }) | ConvertTo-Json -Depth 5), $bom)
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo %*', 'set MODEL=',
    ':dongu', 'if "%~1"=="" goto bitti', 'if "%~1"=="--model" set MODEL=%~2', 'shift', 'goto dongu', ':bitti',
    'if defined MODEL if exist "%D%kanca-%MODEL%.cmd" call "%D%kanca-%MODEL%.cmd" >nul 2>&1',
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
# Ajan çalışırken (çalışma klasöründe) dosya yazsın: kanca-<model>.cmd sahte ajan içinden çağrılır
function Kanca([string]$Model, [string[]]$Satirlar) { [IO.File]::WriteAllText((Join-Path $kum "kanca-$Model.cmd"), ((@('@echo off') + $Satirlar) -join "`r`n") + "`r`n", $ascii) }
function Kancalari-Sil { Get-ChildItem -LiteralPath $kum -Filter 'kanca-*.cmd' | Remove-Item -Force }
Yanit 'YANLIS: beklenmeyen ajan çağrısı'

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
function Yeni-Is([string]$Id, [string]$Tip, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# Test $Id`n`n## Açıklama`n`nKullanıcı listesine arama ekle.`n`n## Kabul ölçütleri`n`n- arama çalışır`n`n## Notlar ve yanıtlar`n"
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; tip = $Tip; proje = 'test'; klasor = $repo; ipucu = ''; oncelik = 2; asama = $Asama; tur = 1; max_tur = 3
        deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @() }
    if ($Tip -eq 'genel') { $d.proje = 'Engineering Manager'; $d.klasor = '' }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Adim([string]$Id) { $g = Gorev-Oku $Id; Gorev-Ilerlet $g; return (Gorev-Oku $Id) }
function Olaylar($G) { return @($G.gecmis | ForEach-Object { [string]$_.olay }) }
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File -Recurse | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return (Metin-Oku $f.FullName) }; return '' }
function Cagrilar { return (Metin-Oku (Join-Path $kum 'cagrilar.log')) }
function Cagrilari-Sil { Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue }
function Yaz-Wt([string]$Wt, [string]$Yol, [string]$Metin) { $f = Join-Path $Wt $Yol; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; [IO.File]::WriteAllText($f, $Metin, $ascii) }

try {
    # ------------------------------------------------------------ U: uçtan uca
    $id = '9601-uctan-uca'
    Write-Host ''; Write-Host 'U1: "İş ver" ile gelen iş önce Product Managerʼa gider'
    Cagrilari-Sil
    $d = Yeni-Is $id 'genel' 'yeni'
    $d = Adim $id
    Dogrula 'aşama analiz, ajan çağrılmadı' ($d.asama -eq 'analiz' -and -not (Cagrilar)) $d.asama
    Dogrula 'Adim-Rolu: analiz -> urun' ((Adim-Rolu $d) -eq 'urun')

    Write-Host ''; Write-Host 'U2: Product Manager soru sorar; kullanıcı yanıtlar; yeniden analiz'
    Model-Yanit 'sahte-urun' "KARAR: SORU_VAR`nKAPSAM: orta`n`n## Talep özeti`nArama.`n`n## Sorular`n1. Arama büyük/küçük harfe duyarlı mı olsun?"
    $d = Adim $id
    Dogrula 'bekliyor_kullanici, soru_donus_asama analiz, soran urun, sayaç 1' ($d.asama -eq 'bekliyor_kullanici' -and $d.soru_donus_asama -eq 'analiz' -and $d.soru_soran -eq 'urun' -and [int]$d.urun_soru_sayisi -eq 1) "$($d.asama)"
    Dogrula 'sorular.md yazıldı, gereksinimler henüz yok' ((Metin-Oku (Join-Path (Gorev-Klasoru $id) 'sorular.md')) -match 'büyük/küçük harfe' -and -not (Test-Path (Join-Path (Gorev-Klasoru $id) 'gereksinimler.md')))
    Dogrula 'PM çağrısı salt okunur (yazma aracı yok)' ((Cagrilar) -match 'sahte-urun' -and (Cagrilar) -match '--tools Read,Glob,Grep ' -and (Cagrilar) -notmatch 'bypassPermissions')
    Start-Sleep -Milliseconds 1100
    $gm = Join-Path (Gorev-Klasoru $id) 'gorev.md'
    Metin-Yaz $gm ((Metin-Oku $gm) + "`n### Yanıt`n`nDuyarsız olsun.`n")
    Bekleyenleri-Kontrol
    $d = Gorev-Oku $id
    Dogrula 'yanıt gelince analiz aşamasına döndü; yardım sonucu yazılmadı' ($d.asama -eq 'analiz' -and -not (Test-Path (Join-Path (Gorev-Klasoru $id) 'yardim-sonuclari.md'))) $d.asama
    Model-Yanit 'sahte-urun' "KARAR: HAZIR`nKAPSAM: buyuk`n`n## Talep özeti`nKullanıcı listesinde arama.`n`n## Kabul ölçütleri (Definition of Done)`n1. Arama büyük/küçük harfe duyarsızdır.`n2. Boş sorgu tüm listeyi gösterir.`n`n## Kapsam dışı`n- sıralama"
    $d = Adim $id
    $gr = Metin-Oku (Join-Path (Gorev-Klasoru $id) 'gereksinimler.md')
    Dogrula 'gereksinimler.md yazıldı, KARAR / KAPSAM satırı yok' ($gr -match 'Definition of Done' -and $gr -notmatch '(?m)^KARAR' -and $gr -notmatch '(?m)^KAPSAM') (Kisalt $gr 80)
    Dogrula 'gereksinim hazır, kapsam buyuk, genel iş yönlendirmeye (plan) geçti' ($d.gereksinim_durumu -eq 'hazir' -and $d.kapsam -eq 'buyuk' -and $d.asama -eq 'plan') "$($d.asama) / $($d.kapsam)"
    $ist = Son-Istem (Gorev-Klasoru $id) 'analiz-*.istem.md'
    Dogrula 'ikinci analiz isteminde önceki taslak (sorular) ve kullanıcının yanıtı var' ($ist -match 'büyük/küçük harfe' -and $ist -match 'Duyarsız olsun')
    Dogrula 'Gorev-Metni gereksinimleri ekler' ((Gorev-Metni $d) -match '# GEREKSİNİMLER' -and (Gorev-Metni $d) -match 'Boş sorgu tüm listeyi')

    Write-Host ''; Write-Host 'U3: Engineering Manager gereksinimlerle yönlendirir; yazılım akışında keşif'
    Model-Yanit 'sahte-yonetici' "KARAR: YAZILIM`nPROJE: test`n`n## Gerekçe`nKod işi."
    $d = Adim $id
    Dogrula 'yazılım ekibine verildi, aşama yeni' ($d.tip -eq 'yazilim' -and $d.asama -eq 'yeni' -and $d.proje -eq 'test') "$($d.tip) / $($d.asama)"
    Dogrula 'yönlendirme isteminde gereksinimler var' ((Son-Istem (Gorev-Klasoru $id) 'yonlendirme-*.istem.md') -match '# GEREKSİNİMLER')
    Cagrilari-Sil
    $d = Adim $id
    Dogrula 'çalışma dalı kuruldu, analiz atlanıp keşfe geçti, ajan çağrılmadı' ($d.asama -eq 'kesif' -and (Test-Path (Join-Path $d.calisma_klasoru '.git')) -and -not (Cagrilar)) $d.asama
    Model-Yanit 'sahte-kasif' "KARAR: HAZIR`nGELISTIRME_ONERISI: onyuz+arkauc`nGUVENLIK_HASSAS: evet`nTEST_KOMUTU: python -m pytest`n`n## Teknoloji yığını`nPython + JS`n`n## Etkilenecek dosyalar`n- src/app.py: liste`n- src/ui.js: arama kutusu"
    $d = Adim $id
    $ks = Metin-Oku (Join-Path (Gorev-Klasoru $id) 'kesif.md')
    Dogrula 'kesif.md: öneri maddeleri, KARAR satırı yok' ($ks -match 'Geliştirme önerisi: onyuz\+arkauc' -and $ks -match 'Projenin test komutu: python -m pytest' -and $ks -match 'src/ui.js' -and $ks -notmatch '(?m)^KARAR') (Kisalt $ks 80)
    Dogrula 'keşif hazır, güvenlik hassas, aşama plan' ($d.kesif_durumu -eq 'hazir' -and $d.guvenlik_hassas -eq $true -and $d.asama -eq 'plan') $d.asama
    $ist = Son-Istem (Gorev-Klasoru $id) 'kesif-*.istem.md'
    Dogrula 'keşif isteminde depo özeti ve gereksinimler var; çağrı salt okunur' ($ist -match 'İzlenen dosya: 4' -and $ist -match '# GEREKSİNİMLER' -and (Cagrilar) -match 'sahte-kasif' -and (Cagrilar) -match '--tools Read,Glob,Grep ')

    Write-Host ''; Write-Host 'U4: Engineering Manager planlar ve işi dağıtır'
    Model-Yanit 'sahte-yonetici' "KARAR: PLAN_HAZIR`nEK_INCELEME: guvenlik, tester`nQA_TESTI: evet`nIS: backend | src/app.py içine arama fonksiyonu`nIS: frontend | src/ui.js arama kutusu`nPUAN: 5`n`n## Özet`nArama."
    $d = Adim $id
    $isler = @($d.gelistirme_isleri)
    Dogrula 'iş dağılımı backend -> frontend, ikisi de bekliyor' ($isler.Count -eq 2 -and $isler[0].rol -eq 'backend' -and $isler[1].rol -eq 'frontend' -and @($isler | Where-Object { $_.durum -eq 'bekliyor' }).Count -eq 2) (($isler | ForEach-Object { $_.rol }) -join ',')
    Dogrula 'QA testi açık; ek inceleme yalnızca guvenlik (tester QA aşamasına katıldı)' ($d.qa_testi -eq $true -and @($d.ek_inceleme).Count -eq 1 -and $d.ek_inceleme[0] -eq 'guvenlik') (@($d.ek_inceleme) -join ',')
    Dogrula 'aşama gelistirme, EM puanı' ($d.asama -eq 'gelistirme' -and $d.puan_yonetici.puan -eq 5) $d.asama
    $ist = Son-Istem (Gorev-Klasoru $id) 'plan-*.istem.md'
    Dogrula 'plan isteminde keşif raporu, geliştiriciler ve gereksinimler var' ($ist -match '# KOD TABANI KEŞFİ' -and $ist -match 'src/ui.js: arama kutusu' -and $ist -match 'frontend \(Frontend Developer\)' -and $ist -match 'backend \(Backend Developer\)' -and $ist -match '# GEREKSİNİMLER')
    Dogrula 'Adim-Rolu: gelistirme -> backend (ilk parça)' ((Adim-Rolu $d) -eq 'backend')

    Write-Host ''; Write-Host 'U5: parçalar sırayla: önce Backend, sonra Frontend Developer'
    Cagrilari-Sil
    Model-Yanit 'sahte-backend' "## Yapılanlar`nara() yazıldı.`n## Arayüz / sözleşme`nara(sorgu) -> liste`nPUAN: 3"
    $d = Adim $id
    Dogrula 'yalnızca backend çağrıldı; parça 1 bitti, aşama hâlâ gelistirme' ((Cagrilar) -match 'sahte-backend' -and (Cagrilar) -notmatch 'sahte-frontend' -and $d.gelistirme_isleri[0].durum -eq 'tamam' -and $d.gelistirme_isleri[1].durum -eq 'bekliyor' -and $d.asama -eq 'gelistirme') $d.asama
    $ist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur1') 'gelistirme-*sahte-backend.istem.md'
    Dogrula 'backend isteminde payı, SENDE işareti, keşif ve puanlama var' ($ist -match 'Senin payın:\*\* src/app.py içine arama' -and $ist -match '\[SENDE\]' -and $ist -match 'KOD TABANI KEŞFİ' -and $ist -match '# PUANLAMA' -and $ist -match 'Backend Developer olarak')
    Dogrula 'puan_ajan backend 3; Adim-Rolu şimdi frontend' ($d.puan_ajan.rol -eq 'backend' -and $d.puan_ajan.puan -eq 3 -and (Adim-Rolu $d) -eq 'frontend') "$($d.puan_ajan.rol)"
    Yaz-Wt $d.calisma_klasoru 'src\app.py' "def f():`n    return 1`n`ndef ara(s):`n    return [s.lower()]`n"
    Cagrilari-Sil
    Model-Yanit 'sahte-frontend' "## Yapılanlar`nArama kutusu eklendi."
    $d = Adim $id
    $ist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur1') 'gelistirme-*sahte-frontend.istem.md'
    Dogrula 'frontend isteminde backendʼin özeti ve sözleşmesi var, puanlama yok' ($ist -match 'Biten parçaların özetleri' -and $ist -match 'ara\(sorgu\) -> liste' -and $ist -notmatch '# PUANLAMA') ''
    $oz = Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur1') 'gelistirici-ozet.md')
    Dogrula 'iki parça bitti, aşama kontrol; birleşik özet' ($d.asama -eq 'kontrol' -and $oz -match '1\. parça: Backend Developer' -and $oz -match '2\. parça: Frontend Developer' -and $oz -match 'Arama kutusu eklendi') $d.asama
    Yaz-Wt $d.calisma_klasoru 'src\ui.js' "export const a = 1;`nexport function ara() {}`n"

    Write-Host ''; Write-Host 'U6: kontrol -> QA testi; QA hata bulur, test dosyası dala alınır, kalan değişiklik geri alınır'
    $d = Adim $id
    Dogrula 'kontrol geçti, aşama test; Adim-Rolu tester' ($d.asama -eq 'test' -and (Adim-Rolu $d) -eq 'tester') $d.asama
    $wt = $d.calisma_klasoru
    Kanca 'sahte-tester' @('mkdir tests', '> tests\test_ara.py echo def test_ara(): pass', 'mkdir build', '> build\cikti.bin echo xx', '> src\app.py echo BOZULDU')
    Model-Yanit 'sahte-tester' "KARAR: DUZELT`nDUZELTECEK: frontend`nTEST_DOSYASI: tests/test_ara.py`nTEST_DOSYASI: src/app.py`nTEST_DOSYASI: ../disari_test.py`n`n## Bulgular`n- Arama kutusu boş sorguda hata veriyor."
    Cagrilari-Sil
    $d = Adim $id
    Kancalari-Sil
    $index = Git-T -C $wt diff --cached --name-only
    Dogrula 'QA çağrısı tam yetkiyle' ((Cagrilar) -match 'sahte-tester' -and (Cagrilar) -match 'bypassPermissions')
    Dogrula 'tests/test_ara.py dala (index) alındı; src/app.py test dosyası sayılmadı' ((@($index) -contains 'tests/test_ara.py') -and ([IO.File]::ReadAllText((Join-Path $wt 'src\app.py')) -match 'def ara')) (@($index) -join ',')
    Dogrula 'QAʼnın kalan değişiklikleri geri alındı (build/cikti.bin yok)' (-not (Test-Path (Join-Path $wt 'build\cikti.bin')))
    Dogrula 'yeni tur (2), aşama gelistirme; test.md ve tur 2 geri bildirimi' ($d.tur -eq 2 -and $d.asama -eq 'gelistirme' -and (Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur1') 'test.md')) -match 'Dala eklenen test dosyaları \(1\)' -and (Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur2') 'geri-bildirim.md')) -match 'QA Engineer hata buldu') "tur $($d.tur) / $($d.asama)"
    Dogrula 'qa_test_dosyalari kaydı' (@($d.qa_test_dosyalari) -contains 'tests/test_ara.py')

    Write-Host ''; Write-Host 'U7: hata yalnızca ilgili geliştiriciye döner (DUZELTECEK: frontend)'
    Cagrilari-Sil
    Model-Yanit 'sahte-frontend' "## Yapılanlar`nBoş sorgu düzeltildi."
    $d = Adim $id
    Dogrula 'yalnızca frontend çalıştı, backend çağrılmadı; aşama kontrol' ((Cagrilar) -match 'sahte-frontend' -and (Cagrilar) -notmatch 'sahte-backend' -and $d.asama -eq 'kontrol') $d.asama
    $oz = Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur2') 'gelistirici-ozet.md')
    Dogrula 'tur 2 özetinde backend için "bu turda değişiklik gerekmedi"' ($oz -match 'Bu turda değişiklik gerekmedi; 1\. turdaki özeti' -and $oz -match 'Boş sorgu düzeltildi')
    $ist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur2') 'gelistirme-*sahte-frontend.istem.md'
    Dogrula 'frontend isteminde QAʼnın geri bildirimi var' ($ist -match 'Arama kutusu boş sorguda hata')
    Yaz-Wt $d.calisma_klasoru 'src\ui.js' "export const a = 1;`nexport function ara(s) { return s || ''; }`n"

    Write-Host ''; Write-Host 'U8: QA onaylar -> Code Reviewer (QA raporu istemde) -> güvenlik -> kabul -> onay kapısı -> commit'
    $d = Adim $id
    Dogrula 'kontrol -> test' ($d.asama -eq 'test') $d.asama
    Model-Yanit 'sahte-tester' "KARAR: ONAY`nTEST_DOSYASI: tests/test_ara.py`n`n## Test özeti`n3 test, 3 geçti."
    $d = Adim $id
    Dogrula 'QA onayladı, aşama denetim' ($d.asama -eq 'denetim' -and ((Olaylar $d) -contains 'QA testleri geçti')) $d.asama
    Model-Yanit 'sahte-denetci' "KARAR: ONAY`n`n## Bulgular`nYok."
    Model-Yanit 'sahte-guvenlik' "KARAR: ONAY`n`n## Bulgular`nYok."
    $d = Adim $id
    $ist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur2') 'denetim-*.istem.md'
    Dogrula 'Code Reviewer isteminde QA test raporu ve güvenlik denetimi var' ($ist -match '# QA ENGINEER TEST RAPORU' -and $ist -match '3 test, 3 geçti' -and $ist -match 'güvenlik kapısı' -and $ist -match 'DUZELTECEK')
    Dogrula 'denetim + ek güvenlik incelemesi onayladı, aşama kabul' ($d.asama -eq 'kabul' -and (Test-Path (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur2') 'inceleme-guvenlik.md'))) $d.asama
    Model-Yanit 'sahte-yonetici' "KARAR: KABUL`nCOMMIT: Kullanıcı listesine arama eklendi`nOZET: Arama eklendi."
    $d = Adim $id
    Dogrula 'kabul isteminde QA raporu var; aşama tamamla' ((Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur2') 'kabul-*.istem.md') -match '3 test, 3 geçti' -and $d.asama -eq 'tamamla') $d.asama
    $d = Adim $id
    $mesaj = (Git-T -C $repo log -1 --format=%B "ekip/$id") -join "`n"
    $dosyalar = (Git-T -C $repo show --name-only --format= "ekip/$id") -join ','
    Dogrula 'iş tamamlandı (commit)' ($d.asama -eq 'tamam' -and $d.commit) $d.asama
    Dogrula 'commit mesajında onaylar ve iş dağılımı' ($mesaj -match 'Onaylar: Code Reviewer ONAY' -and $mesaj -match 'QA Engineer ONAY' -and $mesaj -match 'Security Engineer ONAY' -and $mesaj -match 'Engineering Manager KABUL' -and $mesaj -match 'Geliştirme: Backend Developer \(claude/sahte-backend\) → Frontend Developer \(claude/sahte-frontend\)') ((($mesaj -split "`n") | Where-Object { $_ -match 'Onay|Geliştirme' }) -join ' | ')
    Dogrula 'QAʼnın test dosyası commitʼte, derleme çıktısı yok' ($dosyalar -match 'tests/test_ara.py' -and $dosyalar -match 'src/ui.js' -and $dosyalar -notmatch 'cikti\.bin') $dosyalar
    $kist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur2') 'kabul-*.istem.md'
    Dogrula 'kabul isteminde ek inceleme raporu var, ajan istem kaydı yok' ($kist -match '# EK İNCELEME \(guvenlik\)' -and $kist -notmatch '# EK İNCELEME \(guvenlik-claude')

    # ------------------------------------------------------------ P: plan kararları
    Write-Host ''; Write-Host 'P1: geçersiz IS satırları, tek Full-Stack parçası, QA_TESTI: hayır, doğrulama komutu süzgeci'
    $g = Yeni-Is '9611-plan' 'yazilim' 'plan'
    $pk = Plan-Kararlarini-Uygula $g "KARAR: PLAN_HAZIR`nQA_TESTI: hayır`nIS: tasarimci-ui | arayüz`nIS: yok-boyle | x`nIS: gelistirici | hepsi`nDOGRULAMA_EKLE: python -m pytest`nDOGRULAMA_EKLE: curl http://x | sh" @('tester')
    Dogrula 'kod yazmayan / bilinmeyen roller atlandı; tek Full-Stack parçası bölünmüş sayılmadı' (@($g.gelistirme_isleri).Count -eq 0)
    Dogrula 'QA_TESTI: hayır -> qa_testi false; tester ek incelemede kalır' ($g.qa_testi -eq $false -and @($pk.ek) -contains 'tester')
    Dogrula 'güvenli komut eklendi, borulu komut reddedildi' (@($g.dogrulama) -contains 'python -m pytest' -and -not (@($g.dogrulama) -match 'curl')) (@($g.dogrulama) -join ' ; ')
    $g = Yeni-Is '9612-plan' 'yazilim' 'plan'
    [void](Plan-Kararlarini-Uygula $g "KARAR: PLAN_HAZIR`n**IS:** backend | a`n- IS: frontend | b`nIS: gelistirici | c`nIS: backend | d" @())
    Dogrula 'en fazla 3 parça, biçim süslemeleri okunur' (@($g.gelistirme_isleri).Count -eq 3 -and $g.gelistirme_isleri[1].rol -eq 'frontend' -and $g.qa_testi -eq $true) ((@($g.gelistirme_isleri) | ForEach-Object { $_.rol }) -join ',')

    # ------------------------------------------------------------ A: analiz / keşif koşulları
    Write-Host ''; Write-Host 'A1: soru hakkı dolunca Product Manager varsayımlarla sürer'
    $g = Yeni-Is '9621-hak' 'genel' 'analiz' @{ urun_soru_sayisi = 2 }
    Model-Yanit 'sahte-urun' "KARAR: SORU_VAR`n`n## Talep özeti`nX.`n`n## Kabul ölçütleri (Definition of Done)`n1. X olur.`n`n## Sorular`n1. ?"
    $d = Adim $g.id
    Dogrula 'soru sorulmadı; gereksinim hazır, aşama plan' ($d.asama -eq 'plan' -and $d.gereksinim_durumu -eq 'hazir' -and ((Olaylar $d) -match 'varsayımlarla').Count -eq 1) $d.asama
    Write-Host ''; Write-Host 'A2: katman kapalıysa ya da rolün modeli yoksa atlanır'
    $Ayar.planlama.analiz = $false
    $g = Yeni-Is '9622-kapali' 'yazilim' 'yeni'
    $d = Adim $g.id
    Dogrula 'analiz kapalı: yazılım işi doğrudan keşfe' ($d.asama -eq 'kesif') $d.asama
    $Ayar.planlama.analiz = $true
    $yedek = $Ayar.roller.urun
    $Ayar.roller.PSObject.Properties.Remove('urun')
    Dogrula 'Product Managerʼın modeli yok: Analiz-Gerekli false' (-not (Analiz-Gerekli ([pscustomobject]@{ tip = 'genel'; gereksinim_durumu = '' })))
    $Ayar.roller | Add-Member -NotePropertyName urun -NotePropertyValue $yedek
    $g = Yeni-Is '9623-dogrudan' 'yazilim' 'yeni'
    $d = Adim $g.id
    Dogrula 'gorev-ekle ile gelen yazılım işi (gereksinimsiz) önce analize' ($d.asama -eq 'analiz' -and (Adim-Rolu $d) -eq 'urun') $d.asama
    Write-Host ''; Write-Host 'A3: yeni / boş depoda keşif atlanır'
    $g = Yeni-Is '9624-bos' 'yazilim' 'yeni' @{ proje = 'bos'; klasor = $bosDepo; gereksinim_durumu = 'hazir' }
    $d = Adim $g.id
    Dogrula 'yeni -> kesif' ($d.asama -eq 'kesif') $d.asama
    Cagrilari-Sil
    $d = Adim $g.id
    Dogrula 'keşif atlandı, ajan çağrılmadı, aşama plan' ($d.kesif_durumu -eq 'atlandi' -and $d.asama -eq 'plan' -and -not (Cagrilar)) "$($d.kesif_durumu) / $($d.asama)"

    # ------------------------------------------------------------ O: onay kapısı
    Write-Host ''; Write-Host 'O1: Code Reviewer onayı yoksa commit edilmez'
    $g = Yeni-Is '9631-kapi' 'yazilim' 'tamamla' @{ gereksinim_durumu = 'hazir'; kesif_durumu = 'atlandi' }
    [void](Calisma-Agaci-Kur $g); Gorev-Kaydet $g
    Yaz-Wt $g.calisma_klasoru 'yeni.txt' "x`n"
    $once = (Git-T -C $repo rev-parse "ekip/$($g.id)")
    $d = Adim $g.id
    Dogrula 'aşama denetime döndü, commit yok' ($d.asama -eq 'denetim' -and (Git-T -C $repo rev-parse "ekip/$($g.id)") -eq $once -and ((Olaylar $d) -contains 'onay kapısı: commit edilmedi')) $d.asama
    Write-Host ''; Write-Host 'O2: QA Engineer DUZELT demişse teste döner'
    $tk = Join-Path (Gorev-Klasoru $g.id) 'tur1'
    New-Item -ItemType Directory -Force $tk | Out-Null
    Metin-Yaz (Join-Path $tk 'denetim.md') 'KARAR: ONAY'
    Metin-Yaz (Join-Path $tk 'test.md') 'KARAR: DUZELT'
    $x = Gorev-Oku $g.id; $x.asama = 'tamamla'; Gorev-Kaydet $x
    $d = Adim $g.id
    Dogrula 'aşama test' ($d.asama -eq 'test') $d.asama
    Write-Host ''; Write-Host 'O3: kullanıcı panoda tamamlattıysa not düşülerek commit edilir'
    $x = Gorev-Oku $g.id; $x.asama = 'tamamla'
    Ayarla $x 'elle_tasima' ([pscustomobject]@{ onceki = 'kontrol'; asama = 'tamamla'; zaman = (Get-Date).AddMinutes(-1).ToString('o') }); Gorev-Kaydet $x
    $d = Adim $g.id
    $mesaj = (Git-T -C $repo log -1 --format=%B "ekip/$($g.id)") -join "`n"
    Dogrula 'commit edildi, mesajda kullanıcı notu' ($d.asama -eq 'tamam' -and $mesaj -match 'kullanıcı panodan tamamlattı \(eksik: QA Engineer onayı\)' -and $mesaj -match 'Onaylar: Code Reviewer ONAY') ((($mesaj -split "`n") | Where-Object { $_ -match 'Onay' }) -join ' | ')

    # ------------------------------------------------------------ R: rol eşlemesi, komut, geriye uyum
    Write-Host ''; Write-Host 'R1: bölünmüş işte sıradaki parçayı devralma'
    $isl = @([pscustomobject]@{ rol = 'backend'; is = 'a'; durum = 'tamam'; tur = 1; arac = '' }, [pscustomobject]@{ rol = 'frontend'; is = 'b'; durum = 'bekliyor'; tur = 0; arac = '' })
    $g = Yeni-Is '9641-devral' 'yazilim' 'gelistirme' @{ gelistirme_isleri = $isl; qa_testi = $true; gereksinim_durumu = 'hazir' }
    [void](Calisma-Agaci-Kur $g); Gorev-Kaydet $g
    $s1 = Gorev-Komut-Ver (Gorev-Oku $g.id) 'gelistirici' 'devral'
    $d = Gorev-Oku $g.id
    Dogrula 'devralan: frontend -> gelistirici' ($d.devralan.frontend -eq 'gelistirici') $s1.ozet
    Cagrilari-Sil
    Model-Yanit 'sahte-gelistirici' "## Yapılanlar`nFrontend payı (devralındı)."
    $d = Adim $g.id
    $ist = Son-Istem (Gorev-Klasoru $g.id) 'gelistirme-*.istem.md'
    Dogrula 'parça Full-Stack Developer zinciriyle yapıldı, istemde devralma notu' ((Cagrilar) -match 'sahte-gelistirici' -and (Cagrilar) -notmatch 'sahte-frontend' -and $ist -match '# DEVRALMA' -and $ist -match 'Frontend Developer rolünün işi' -and $d.asama -eq 'kontrol') $d.asama
    Write-Host ''; Write-Host 'R2: eski kayıt (qa_testi yok) kontrolden doğrudan denetime gider'
    $g = Yeni-Is '9642-eski' 'yazilim' 'kontrol'
    [void](Calisma-Agaci-Kur $g); Gorev-Kaydet $g
    Yaz-Wt $g.calisma_klasoru 'eski.txt' "x`n"
    $d = Adim $g.id
    Dogrula 'aşama denetim (QA aşaması yok)' ($d.asama -eq 'denetim') $d.asama
    Write-Host ''; Write-Host 'R3: QA test dosyasında gizli bilgi varsa dala alınmaz'
    $g = Yeni-Is '9643-gizli' 'yazilim' 'test' @{ qa_testi = $true }
    [void](Calisma-Agaci-Kur $g); Gorev-Kaydet $g
    Yaz-Wt $g.calisma_klasoru 'kod.txt' "x`n"
    Kanca 'sahte-tester' @('mkdir tests', "> tests\test_gizli.py echo api_key = 'abcdef123456'")
    Model-Yanit 'sahte-tester' "KARAR: ONAY`nTEST_DOSYASI: tests/test_gizli.py`n`n## Test özeti`nTamam."
    $d = Adim $g.id
    Kancalari-Sil
    $index = Git-T -C $d.calisma_klasoru diff --cached --name-only
    Dogrula 'gizli bilgili test dosyası dala alınmadı ve silindi; iş denetime geçti' (-not (@($index) -contains 'tests/test_gizli.py') -and -not (Test-Path (Join-Path $d.calisma_klasoru 'tests\test_gizli.py')) -and $d.asama -eq 'denetim') (@($index) -join ',')
    Write-Host ''; Write-Host 'R4: Adim-Rolu yeni aşamalar'
    Dogrula 'kesif -> kasif, test -> tester, kontrol (QA açık) -> tester, kontrol (QA yok) -> denetci' (
        (Adim-Rolu ([pscustomobject]@{ asama = 'kesif'; tip = 'yazilim' })) -eq 'kasif' -and (Adim-Rolu ([pscustomobject]@{ asama = 'test'; tip = 'yazilim' })) -eq 'tester' -and
        (Adim-Rolu ([pscustomobject]@{ asama = 'kontrol'; tip = 'yazilim'; qa_testi = $true })) -eq 'tester' -and (Adim-Rolu ([pscustomobject]@{ asama = 'kontrol'; tip = 'yazilim' })) -eq 'denetci')
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
