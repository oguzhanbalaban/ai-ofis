<#
danisman.test.ps1 - Outsource Consultant akışını sınar: Product Manager yönlendirmesi (ATAMA: danisman / ekip, kullanıcının doğrudan
ataması), masa ve CLAUDE.md, Claude Code izin profili (dontAsk, izin / yasak listeleri, --add-dir, çalışma dizini), git ve klasör
modları, kontrol, commit, SORU_VAR / YAPILAMADI, sohbete rapor. Çevrimdışıdır: gerçek Claude / Codex çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\danisman.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-danisman-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    denetci = @(& $s 'sahte-denetci'); sistem = @(& $s 'sahte-sistem'); ag = @(& $s 'sahte-ag'); urun = @(& $s 'sahte-urun'); danisman = @(& $s 'sahte-danisman') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $false; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName planlama -NotePropertyValue ([pscustomobject]@{ analiz = $true; kesif = $false; qa_testi = $false })
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
$ayarJ | Add-Member -Force -NotePropertyName danisman -NotePropertyValue ([pscustomobject]@{ etkin = $true; zaman_asimi_dk = 7
    izinli_araclar = @('Read', 'Edit', 'Bash'); yasak_araclar = @('Bash(git push *)', 'Bash(yuzde %PATH%)') })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $ek) $o = [ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = $true; uzman_isi = $false; yetki = 'oku'; uzmanlik = "$ad işleri" }; foreach ($k in $ek.Keys) { $o[$k] = $ek[$k] }; [pscustomobject]$o }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @((& $uye 'lider' 'Engineering Manager' @{}), (& $uye 'urun' 'Product Manager' @{}), (& $uye 'sorun-giderici' 'Incident Manager' @{}),
    (& $uye 'gelistirici' 'Full-Stack Developer' @{ yetki = 'yaz' }), (& $uye 'denetci' 'Code Reviewer' @{}),
    (& $uye 'danisman' 'Outsource Consultant' @{ dogrudan_is = $true; yetki = 'tam'; departman = 'Dış danışmanlık' })) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
$repo = Join-Path $kum 'depo'
New-Item -ItemType Directory -Force $repo | Out-Null
Git-T -C $repo init -q -b main
[IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "a`n", $ascii)
Git-T -C $repo add -A
Git-T -C $repo -c user.name=t -c user.email=t@t commit -q -m ilk
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @([pscustomobject]@{ ad = 'test'; klasor = $repo; temel_dal = ''; dogrulama = @() }) }) | ConvertTo-Json -Depth 5), $bom)
# Sahte ajan: argümanları ve çalışma dizinini kaydeder; --model değerine göre çıktı seçer
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo CD=%CD% GIT=%GIT_CONFIG_PARAMETERS% ARG=%*', 'set MODEL=',
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
function Yanit([string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), (Akis $Metin), $utf8) }
function Model-Yanit([string]$Model, [string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum "cikti-$Model.txt"), (Akis $Metin), $utf8) }
Yanit 'YANLIS: beklenmeyen ajan'

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
function Is([string]$Id, [string]$Tip, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# $Id`n`n## Açıklama`n`nKüçük bir betik yaz.`n`n## Notlar ve yanıtlar`n"
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; tip = $Tip; proje = 'Engineering Manager'; klasor = ''; ipucu = ''; istenen_rol = ''; oncelik = 2; asama = $Asama
        tur = 1; max_tur = 3; deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @() }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Adim([string]$Id) { Gorev-Ilerlet (Gorev-Oku $Id); return (Gorev-Oku $Id) }
function Olaylar($G) { return @($G.gecmis | ForEach-Object { [string]$_.olay }) }
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return (Metin-Oku $f.FullName) }; return '' }
function Cagrilar { return (Metin-Oku (Join-Path $kum 'cagrilar.log')) }
function Cagrilari-Sil { Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue }
function Sohbet { $f = Join-Path $YolDurum 'sohbet\danisman.jsonl'; if (Test-Path $f) { return (Metin-Oku $f) }; return '' }
$masa = Join-Path $kum 'danisman'
$pmDanisman = "KARAR: HAZIR`nKAPSAM: kucuk`nATAMA: danisman`nPROJE: test`n`n## Talep özeti`nBetik.`n`n## Kabul ölçütleri (Definition of Done)`n1. betik.ps1 çalışır.`n`n## Danışman brifi`nDepoya betik.ps1 ekle; çalıştırıp çıktısını doğrula."

try {
    Write-Host ''; Write-Host 'D1: Product Manager tek parça işi Outsource Consultantʼa devreder'
    $id = '0801-tek-parca'
    [void](Is $id 'genel' 'analiz')
    Model-Yanit 'sahte-urun' $pmDanisman
    $d = Adim $id
    $plan = Metin-Oku (Join-Path (Gorev-Klasoru $id) 'plan.md'); $gr = Metin-Oku (Join-Path (Gorev-Klasoru $id) 'gereksinimler.md')
    Dogrula 'tip danisman, aşama yeni, proje test, karar DANISMAN' ($d.tip -eq 'danisman' -and $d.asama -eq 'yeni' -and $d.proje -eq 'test' -and $d.klasor -eq $repo -and $d.yonlendirme_karari -eq 'DANISMAN') "$($d.tip)/$($d.asama)/$($d.proje)"
    Dogrula 'brif plan.mdʼde; gereksinimlerde brif ve ATAMA / PROJE satırı yok' ($plan -match '# Danışman brifi' -and $plan -match 'betik.ps1 ekle' -and $gr -match 'Definition of Done' -and $gr -notmatch 'Danışman brifi' -and $gr -notmatch '(?m)^(ATAMA|PROJE):')
    Dogrula 'PM isteminde karşılama kararı seçeneği var' ((Son-Istem (Gorev-Klasoru $id) 'analiz-*.istem.md') -match 'Outsource Consultant kullanılabilir')
    Dogrula 'Adim-Rolu danisman' ((Adim-Rolu $d) -eq 'danisman')

    Write-Host ''; Write-Host 'D2: hazırlık: git görev dalı ve danışman masası (CLAUDE.md)'
    Cagrilari-Sil
    $d = Adim $id
    Dogrula 'git modu, görev dalı ve çalışma ağacı, aşama gelistirme; ajan çağrılmadı' ($d.danisman_mod -eq 'git' -and $d.dal -eq "ekip/$id" -and (Test-Path (Join-Path $d.calisma_klasoru '.git')) -and $d.asama -eq 'gelistirme' -and -not (Cagrilar)) "$($d.danisman_mod) $($d.dal)"
    $cm = Metin-Oku (Join-Path $masa 'CLAUDE.md'); $ag = Metin-Oku (Join-Path $masa 'AGENTS.md'); $gm = Metin-Oku (Join-Path $masa 'GEMINI.md')
    Dogrula 'masada CLAUDE.md şablondan oluştu (yol içermez); AGENTS.md ve GEMINI.md onun kopyası' ($cm -match 'Outsource Consultant' -and -not $cm.Contains($kum) -and $ag.Contains($cm.Trim()) -and $gm.Contains($cm.Trim()) -and $ag -match 'kopyasıdır')

    Write-Host ''; Write-Host 'D3: Claude Code izin profili ve çalışma'
    [IO.File]::WriteAllText((Join-Path $d.calisma_klasoru 'betik.ps1'), "Write-Output 'merhaba'`n", $ascii)
    Model-Yanit 'sahte-danisman' "KARAR: TAMAM`nOZET: betik.ps1 eklendi ve çalıştırıldı.`nCOMMIT: Merhaba betiği eklendi`n`n## Yapılanlar`n- betik.ps1`n## Doğrulama`n- çalıştı"
    $d = Adim $id
    $log = Cagrilar
    Dogrula 'çalışma dizini masa (CLAUDE.md yüklenir)' ($log -match [regex]::Escape("CD=$masa")) ((($log -split "`n") | Select-Object -First 1))
    Dogrula 'dontAsk + izin listesi + yasak liste + --add-dir çalışma klasörü' ($log -match '--permission-mode dontAsk' -and $log -match '--allowedTools "Read,Edit,Bash"' -and $log -match '--disallowedTools "Bash\(git push \*\)"' -and $log -match ('--add-dir "' + [regex]::Escape($d.calisma_klasoru) + '"'))
    Dogrula 'yüzde içeren kural komut satırına girmedi; bypass yok' ($log -notmatch 'PATH' -and $log -notmatch 'bypassPermissions')
    Dogrula 'çalışırken git push engeli ortamda, sonra kaldırıldı' ($log -match 'pushinsteadof=https://' -and -not $env:GIT_CONFIG_PARAMETERS)
    Dogrula 'istemin ARAÇLAR bölümünde danışman zinciri' ((Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur1') 'danisman-*.istem.md') -match 'Zincir: claude/sahte-danisman')
    $ist = Son-Istem (Join-Path (Gorev-Klasoru $id) 'tur1') 'danisman-*.istem.md'
    Dogrula 'istemde brif, çalışma klasörü, git kuralı, rapor biçimi; yardım talimatı yok' ($ist -match 'betik.ps1 ekle' -and $ist.Contains($d.calisma_klasoru) -and $ist -match 'commit / push / dal değiştirme YAPMA' -and $ist -match 'KARAR: TAMAM' -and $ist -notmatch 'EKİPTEN YARDIM İSTEME')
    Dogrula 'aşama kontrol; rapor, özet, commit mesajı kaydedildi' ($d.asama -eq 'kontrol' -and (Test-Path (Join-Path (Join-Path (Gorev-Klasoru $id) 'tur1') 'danisman-rapor.md')) -and $d.ozet -match 'betik.ps1 eklendi' -and $d.commit_mesaji -eq 'Merhaba betiği eklendi') $d.asama

    Write-Host ''; Write-Host 'D4: kontrol -> commit -> tamam; ofise ve sohbete rapor'
    $d = Adim $id
    Dogrula 'kontrol geçti, aşama tamamla' ($d.asama -eq 'tamamla' -and $d.son_kontrol -eq 'GEÇTİ') $d.asama
    $d = Adim $id
    $mesaj = (Git-T -C $repo log -1 --format=%B "ekip/$id") -join "`n"
    Dogrula 'tamam; dala commit (mesajda danışman ve iç inceleme yapılmadı notu); çalışma ağacı kaldırıldı' ($d.asama -eq 'tamam' -and $d.commit -and $mesaj -match '^Merhaba betiği eklendi' -and $mesaj -match 'Outsource Consultant \(terminal ajanı, headless\): claude/sahte-danisman' -and $mesaj -match 'iç ekip incelemesi yapılmadı' -and -not (Test-Path $d.calisma_klasoru)) ((($mesaj -split "`n") | Select-Object -First 1))
    Dogrula 'danışmanın sohbetine rapor: işin numarası ve özet' ((Sohbet) -match '#0801' -and (Sohbet) -match 'betik.ps1 eklendi ve çalıştırıldı')

    Write-Host ''; Write-Host 'D5: ATAMA: ekip -> iş iç ekipte kalır'
    $id2 = '0802-ekip'
    [void](Is $id2 'genel' 'analiz')
    Model-Yanit 'sahte-urun' "KARAR: HAZIR`nKAPSAM: buyuk`nATAMA: ekip`n`n## Talep özeti`nBüyük iş."
    $d = Adim $id2
    Dogrula 'genel iş, aşama plan (Engineering Manager yönlendirecek)' ($d.tip -eq 'genel' -and $d.asama -eq 'plan') "$($d.tip)/$($d.asama)"

    Write-Host ''; Write-Host 'D6: kullanıcı doğrudan Outsource Consultantʼa verdi'
    $id3 = '0803-dogrudan'
    [void](Is $id3 'genel' 'analiz' @{ istenen_rol = 'danisman' })
    Model-Yanit 'sahte-urun' "KARAR: HAZIR`nKAPSAM: orta`nATAMA: ekip`n`n## Talep özeti`nRapor yaz."
    $d = Adim $id3
    Dogrula 'PM ekip dese de danışmana geçti; proje yok (klasör modu olacak)' ($d.tip -eq 'danisman' -and -not $d.klasor) "$($d.tip)"
    Dogrula 'PM isteminde doğrudan atama notu' ((Son-Istem (Gorev-Klasoru $id3) 'analiz-*.istem.md') -match 'doğrudan Outsource Consultant')
    $Ayar.planlama.analiz = $false
    $id4 = '0804-pm-kapali'
    [void](Is $id4 'genel' 'yeni' @{ istenen_rol = 'danisman' })
    $d = Adim $id4
    Dogrula 'Product Manager kapalıyken doğrudan atama görev metniyle devredilir' ($d.tip -eq 'danisman' -and $d.yonlendiren -eq 'Kullanıcının doğrudan ataması' -and (Metin-Oku (Join-Path (Gorev-Klasoru $id4) 'plan.md')) -match 'Küçük bir betik yaz') $d.yonlendiren
    $Ayar.planlama.analiz = $true

    Write-Host ''; Write-Host 'D7: klasör modu: teslimler cikti\, sonuc.md'
    $d = Adim $id3
    $wt = $d.calisma_klasoru
    Dogrula 'klasör modu, cikti\ var' ($d.danisman_mod -eq 'klasor' -and (Test-Path (Join-Path $wt 'cikti')) -and $d.asama -eq 'gelistirme') $d.danisman_mod
    [IO.File]::WriteAllText((Join-Path $wt 'cikti\rapor.md'), "# Rapor`n", $utf8)
    Model-Yanit 'sahte-danisman' "KARAR: TAMAM`nOZET: Rapor hazır.`n`n## Teslimler`n- cikti\rapor.md"
    Cagrilari-Sil
    $d = Adim $id3
    Dogrula 'ek klasör --add-dir ile verildi; istemde cikti\ yolu' ((Cagrilar) -match [regex]::Escape('--add-dir "' + $wt + '"') -and (Son-Istem (Join-Path (Gorev-Klasoru $id3) 'tur1') 'danisman-*.istem.md') -match 'Teslim dosyalarını')
    $d = Adim $id3; $d = Adim $id3
    Dogrula 'tamam; sonuc.md teslimi listeliyor' ($d.asama -eq 'tamam' -and (Metin-Oku (Join-Path (Gorev-Klasoru $id3) 'sonuc.md')) -match 'rapor.md') $d.asama

    Write-Host ''; Write-Host 'D8: gizli bilgi -> yeni tur (danışmana geri bildirimle)'
    $id5 = '0805-gizli'
    [void](Is $id5 'danisman' 'yeni' @{ proje = 'test'; klasor = $repo })
    Metin-Yaz (Join-Path (Gorev-Klasoru $id5) 'plan.md') "# Danışman brifi`n`nAyar dosyası yaz."
    $d = Adim $id5
    [IO.File]::WriteAllText((Join-Path $d.calisma_klasoru 'ayar.txt'), "api_key = 'abcdef123456'`n", $ascii)
    Model-Yanit 'sahte-danisman' "KARAR: TAMAM`nOZET: yazıldı."
    $d = Adim $id5; $d = Adim $id5
    Dogrula 'kontrol kaldı: tur 2, aşama gelistirme, geri bildirimde gizli bilgi' ($d.tur -eq 2 -and $d.asama -eq 'gelistirme' -and (Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $id5) 'tur2') 'geri-bildirim.md')) -match 'gizli bilgi') "tur $($d.tur) $($d.asama)"

    Write-Host ''; Write-Host 'D9: SORU_VAR ve YAPILAMADI'
    Model-Yanit 'sahte-danisman' "KARAR: SORU_VAR`nOZET: hesap bilgisi gerekli.`n`n## Sorular`n1. Hangi hesap?"
    $d = Adim $id5
    Dogrula 'soru: bekliyor_kullanici, soran danisman, dönüş gelistirme; sohbete yazıldı' ($d.asama -eq 'bekliyor_kullanici' -and $d.soru_soran -eq 'danisman' -and $d.soru_donus_asama -eq 'gelistirme' -and (Sohbet) -match 'Hangi hesap') $d.asama
    $x = Gorev-Oku $id5; $x.asama = 'gelistirme'; Gorev-Kaydet $x
    Model-Yanit 'sahte-danisman' "KARAR: YAPILAMADI`nOZET: araç yok.`n`n## Açık kalanlar`n- derleyici kurulu değil"
    $d = Adim $id5
    Dogrula 'yapılamadı: takıldı; sohbete yazıldı' ($d.asama -eq 'takildi' -and $d.son_hata -match 'derleyici kurulu değil' -and (Sohbet) -match 'tamamlayamadım') $d.son_hata

    Write-Host ''; Write-Host 'D10: başka roller izin profilini kullanmaz; yardım listesinde danışman yok'
    Cagrilari-Sil
    $g6 = Is '0806-plan' 'genel' 'plan' @{ gereksinim_durumu = 'hazir' }
    Model-Yanit 'sahte-yonetici' "KARAR: UZMAN`nSORUMLU: yok`n`n## Gerekçe`nx"
    [void](Adim $g6.id)
    $log = Cagrilar
    Dogrula 'Engineering Manager çağrısı salt okunur profilde (dontAsk + Read,Glob,Grep; Bash yok)' ($log -match 'sahte-yonetici' -and $log -match '--tools Read,Glob,Grep ' -and $log -notmatch 'Bash')
    Dogrula 'yardım talimatında danışman önerilmez; Yardim-Uygun-mu danisman etiketinde false' ((Yardim-Talimati-Metni) -notmatch '- danisman \(' -and -not (Yardim-Uygun-mu 'danisman' 'danisman'))
    $Ayar.danisman.etkin = $false
    Dogrula 'danisman.etkin false: Danisman-Hazir-mi false' (-not (Danisman-Hazir-mi))
    $Ayar.danisman.etkin = $true

    Write-Host ''; Write-Host 'D11: kurulumda seçilen yapay zeka danışman olur: Codex ve Gemini izin profilleri'
    $zincir = $Ayar.roller.danisman
    $Ayar.roller.danisman = @([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' })
    Dogrula 'yalnız Codex zinciri: danışman hazır' (Danisman-Hazir-mi)
    $script:CodexYolu = $sahteAjan
    $ekk = Join-Path $kum 'ek-klasor'; New-Item -ItemType Directory -Force $ekk | Out-Null
    $istY = Join-Path $kum 'istem.txt'; [IO.File]::WriteAllText($istY, 'x', $utf8)
    Cagrilari-Sil
    [void](Codex-Calistir ([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }) $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $masa $false $false 'danisman' @($ekk))
    $log = Cagrilar
    Dogrula 'Codex: workspace-write, -C masa, --add-dir işin klasörü, ağ açık, push engeli' ($log -match 'exec --skip-git-repo-check -s workspace-write' -and $log -match ('-C "' + [regex]::Escape($masa) + '" --add-dir "' + [regex]::Escape($ekk) + '"') -and $log -match 'network_access=true' -and $log -match 'pushinsteadof') ((($log -split "`n") | Select-Object -First 1))
    Cagrilari-Sil
    [void](Codex-Calistir ([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }) $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $masa $false $false)
    Dogrula 'Codex profilsiz çağrı değişmedi (read-only, ağ / push engeli yok)' ((Cagrilar) -match '-s read-only' -and (Cagrilar) -notmatch 'network_access|--add-dir|pushinsteadof')
    function Gemini-Exe { return $sahteAjan }
    Cagrilari-Sil
    [void](Gemini-Calistir ([pscustomobject]@{ arac = 'gemini'; model = 'sahte-gemini' }) $istY (Join-Path $kum 'g.out') (Join-Path $kum 'g.err') $masa $false $false 'danisman' @($ekk))
    $log = Cagrilar
    Dogrula 'Gemini: yolo (başsızda onay sorulmaz), --include-directories, çalışma dizini masa, push engeli' ($log -match '--approval-mode yolo --skip-trust --include-directories "' -and $log -match [regex]::Escape($ekk) -and $log -match [regex]::Escape("CD=$masa") -and $log -match 'pushinsteadof') ((($log -split "`n") | Select-Object -First 1))
    $Ayar.danisman | Add-Member -Force -NotePropertyName ag_erisimi -NotePropertyValue $false
    $Ayar.danisman | Add-Member -Force -NotePropertyName push_engeli -NotePropertyValue $false
    Cagrilari-Sil
    [void](Codex-Calistir ([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }) $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $masa $false $false 'danisman' @($ekk))
    Dogrula 'ag_erisimi / push_engeli false: ağ bayrağı ve push engeli yok' ((Cagrilar) -notmatch 'network_access|pushinsteadof' -and (Cagrilar) -match 'workspace-write')
    $Ayar.roller.danisman = $zincir

    Write-Host ''; Write-Host 'D12: masa: kullanıcının CLAUDE.md düzenlemesi korunur, AGENTS.md / GEMINI.md onu izler'
    Metin-Yaz (Join-Path $masa 'CLAUDE.md') "# Kendi kurallarım`n`n- Her raporu 'ÖZEL-KURAL' ile başlat.`n"
    [void](Danisman-Masasi)
    Dogrula 'CLAUDE.md değişmedi; aynalar güncellendi' ((Metin-Oku (Join-Path $masa 'CLAUDE.md')) -match 'ÖZEL-KURAL' -and (Metin-Oku (Join-Path $masa 'AGENTS.md')) -match 'ÖZEL-KURAL' -and (Metin-Oku (Join-Path $masa 'GEMINI.md')) -match 'ÖZEL-KURAL')
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
