<#
komut-paralel.test.ps1 - Çalışana doğrudan komutu (Devam et / Devral, talimat) ve paralel çalışma hatlarını sınar. Çevrimdışıdır:
gerçek Claude / Codex çağrılmaz, gerçek gorevler\ klasörüne, bildirimlere ve e-postaya dokunulmaz. Sahte ajan --model değerine
göre cikti-<model>.txt dosyasını (yoksa sahte-cikti.txt) stream-json biçiminde basar.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\komut-paralel.test.ps1 [-Kaynak <betik klasörü>] [-Koru]

  K  komut: devral (rol devralanın zinciriyle, istemde devralma notu ve talimat, kullanım kaydı), geri alma, takılan / soru bekleyen
     işi sürdürme, kapanmış iş, paralel hat sınırı (öne alma), durum.ps1 -Komut
  L  görev kilidi: başka süreç işi tutarken döngü almaz, adım yürütmez; komut yalnızca komut alanlarını işler; adım sürerken gelen
     komut adım sonucunda korunur; sıra seçildikten sonra değişen kayıt tazelenir
  P  paralel hat (paralel.ps1, ayrı süreç): iş adım adım tamamlanır, devralan zinciriyle çalışır, kalp.json'a yazmaz, kaydı silinir;
     paralel-durdur; eşzamanlı dosya yazımı (Metin-Yaz)
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-komut-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
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
$ayarJ.gorev.lider_kabul = $true
$ayarJ.sorun_giderici = [pscustomobject]@{ etkin = $false; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
$ayarJ | Add-Member -Force -NotePropertyName yardimlasma -NotePropertyValue ([pscustomobject]@{ etkin = $true; gorev_basina_en_fazla = 4; derinlik = 2 })
$ayarJ | Add-Member -Force -NotePropertyName paralel -NotePropertyValue ([pscustomobject]@{ etkin = $true; en_fazla = 2; adim_siniri = 12 })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $uzman, $yetki, $model) $o = [ordered]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = (-not $uzman); uzman_isi = $uzman; yetki = $yetki; uzmanlik = "$ad işleri" }
    if ($model) { $o.araclar = @(& $s $model) }; [pscustomobject]$o }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @(
    (& $uye 'lider' 'Engineering Manager' $false 'oku' ''), (& $uye 'sorun-giderici' 'Incident Manager' $false 'oku' ''), (& $uye 'gelistirici' 'Software Developer' $false 'yaz' ''),
    (& $uye 'denetci' 'Code Reviewer' $false 'oku' ''), (& $uye 'sistem' 'System Administrator' $false 'tam' ''), (& $uye 'ag' 'Network Engineer' $false 'tam' ''),
    (& $uye 'tester' 'QA Engineer' $true 'tam' 'sahte-tester'), (& $uye 'ik' 'HR Specialist' $true 'oku' '')) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
function Git-T { $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { return (& git @args 2>$null) } finally { $ErrorActionPreference = $eap } }
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
    Metin-Yaz (Join-Path $gk 'gorev.md') "# Test $Id`n`nUygulama yaz."
    Metin-Yaz (Join-Path $gk 'plan.md') "KARAR: PLAN_HAZIR`n`n## Plan`n1. yaz"
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; proje = 'test'; klasor = $repo; oncelik = 2; asama = $Asama; tur = 1; max_tur = 3
        deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); calisma_klasoru = $wt }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Olaylar($G) { return @($G.gecmis | ForEach-Object { [string]$_.olay }) }
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File -Recurse | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return (Metin-Oku $f.FullName) }; return '' }
function Cagrilar { return (Metin-Oku (Join-Path $kum 'cagrilar.log')) }
function Cagrilari-Sil { Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue }
function Son-Kullanim {
    $f = Get-ChildItem -LiteralPath (Join-Path $YolDurum 'kullanim') -Filter '*.jsonl' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { return $null }
    return ((Get-Content -LiteralPath $f.FullName -Encoding UTF8 | Where-Object { $_ } | Select-Object -Last 1) | ConvertFrom-Json)
}
# Başka bir süreç (paralel hat yerine) görev kilidini tutar; hazır olunca döner
function Kilit-Tutan-Surec([string]$Id) {
    $hazir = Join-Path $kum "kilit-$Id.hazir"
    $ad = Gorev-Kilit-Adi $Id
    $kod = "`$m = New-Object Threading.Mutex(`$false, '$ad'); [void]`$m.WaitOne(); [IO.File]::WriteAllText('$hazir', 'x'); Start-Sleep -Seconds 120"
    $p = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-Command', $kod) -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 100 -and -not (Test-Path $hazir); $i++) { Start-Sleep -Milliseconds 100 }
    return $p
}
function Sureci-Bitir($P) { if ($P -and -not $P.HasExited) { & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $P.Id 2>$null | Out-Null; [void]$P.WaitForExit(10000) } }

try {
    # ------------------------------------------------------------ K: komut
    Write-Host ''; Write-Host 'K1: Engineering Manager, Software Developerʼın adımını devralır (talimatla)'
    $g = Test-Gorevi '9501-devral' 'gelistirme'
    $s1 = Gorev-Komut-Ver $g 'lider' 'devral' 'Önce testleri yaz, sonra kodu.'
    $d = Gorev-Oku $g.id
    Dogrula 'devralan: gelistirici -> lider' ($d.devralan.gelistirici -eq 'lider') ($d.devralan | ConvertTo-Json -Compress)
    Dogrula 'karar paralel (hat boş), komut kaydı ve geçmiş' ($s1.karar -eq 'paralel' -and @($d.komutlar).Count -eq 1 -and $d.komutlar[0].emir -eq 'devral' -and ((Olaylar $d) -match 'kullanıcı komut verdi').Count -eq 1) $s1.ozet
    Dogrula 'talimat dosyaya yazıldı' ((Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'kullanici-talimatlari.md')) -match 'Önce testleri yaz')
    Dogrula 'Adim-Sahibi devralanı döndürür, Adim-Rolu asıl rolü' ((Adim-Sahibi $d) -eq 'lider' -and (Adim-Rolu $d) -eq 'gelistirici')

    Write-Host ''; Write-Host 'K2: devralınan adım devralanın model zinciriyle çalışır'
    Cagrilari-Sil
    Model-Yanit 'sahte-yonetici' 'Kodu yazdım (Engineering Manager devraldı).'
    Model-Yanit 'sahte-gelistirici' 'YANLIS: gelistirici çağrıldı'
    Gorev-Ilerlet $d
    Model-Yanitlari-Sil
    $d2 = Gorev-Oku $g.id
    $log = Cagrilar
    Dogrula 'adım sahte-yonetici ile çalıştı, gelistirici çağrılmadı' ($log -match 'sahte-yonetici' -and $log -notmatch 'sahte-gelistirici') ((($log -split "`n") | Select-Object -Last 1))
    Dogrula 'iş kontrole geçti' ($d2.asama -eq 'kontrol') $d2.asama
    $ist = Son-Istem (Gorev-Klasoru $g.id) 'gelistirme-*.istem.md'
    Dogrula 'istemde devralma notu ve kullanıcı talimatı var' ($ist -match '# DEVRALMA' -and $ist -match 'Software Developer rolünün işi' -and $ist -match 'KULLANICININ TALİMATLARI' -and $ist -match 'Önce testleri yaz')
    $k = Son-Kullanim
    Dogrula 'kullanım kaydı devralana yazıldı (yerine: gelistirici)' ($k -and $k.rol -eq 'lider' -and $k.yerine -eq 'gelistirici') ($k | ConvertTo-Json -Compress)
    Dogrula 'adım sonrası rol değişimi temizlendi' ($null -eq $script:RolDegisimi)

    Write-Host ''; Write-Host 'K3: rolün asıl sahibi "Devral" derse rol ona döner'
    $g = Test-Gorevi '9502-geri' 'gelistirme' @{ devralan = [pscustomobject]@{ gelistirici = 'lider' } }
    $s3 = Gorev-Komut-Ver $g 'gelistirici' 'devral'
    $d = Gorev-Oku $g.id
    Dogrula 'devralan kaldırıldı' (-not ($d.devralan.PSObject.Properties | Where-Object { $_.Value })) $s3.ozet
    Cagrilari-Sil
    Model-Yanit 'sahte-gelistirici' 'Kodu yazdım.'
    Gorev-Ilerlet $d
    Model-Yanitlari-Sil
    Dogrula 'adım yine Software Developer zinciriyle' ((Cagrilar) -match 'sahte-gelistirici' -and (Cagrilar) -notmatch 'sahte-yonetici')

    Write-Host ''; Write-Host 'K4: takılan / soru bekleyen iş sürdürülür; kapanmış işe komut verilmez; bilinmeyen çalışan'
    $g = Test-Gorevi '9503-takili' 'takildi' @{ takildi_asama = 'denetim'; son_hata = 'eski hata'; sonraki_deneme = (Get-Date).AddHours(2).ToString('o') }
    $s4 = Gorev-Komut-Ver $g 'denetci' 'devam'
    $d = Gorev-Oku $g.id
    Dogrula 'takılan iş takıldığı aşamadan sürer, bekleme kalkar' ($d.asama -eq 'denetim' -and -not $d.sonraki_deneme -and $s4.surduruldu -eq 'takildi') "$($d.asama)"
    $g = Test-Gorevi '9504-soru' 'bekliyor_kullanici' @{ soru_zamani = (Simdi) }
    [void](Gorev-Komut-Ver $g 'lider' 'devam')
    Dogrula 'soru bekleyen iş plana döner' ((Gorev-Oku $g.id).asama -eq 'plan')
    $g = Test-Gorevi '9505-tamam' 'tamam'
    $hata = ''; try { [void](Gorev-Komut-Ver $g 'lider' 'devam') } catch { $hata = $_.Exception.Message }
    Dogrula 'tamamlanmış işe komut verilmez' ($hata -match 'kapanmış') $hata
    $hata = ''; try { [void](Gorev-Komut-Ver (Test-Gorevi '9506-kim' 'plan') 'yok-boyle' 'devam') } catch { $hata = $_.Exception.Message }
    Dogrula 'kadroda olmayan çalışana komut verilmez' ($hata -match 'Kadroda') $hata

    Write-Host ''; Write-Host 'K5: paralel hatlar doluysa iş ana sırada öne alınır; ölü hat kaydı temizlenir'
    New-Item -ItemType Directory -Force $YolParalel | Out-Null
    foreach ($n in 1, 2) { Json-Yaz ([ordered]@{ pid = $PID; gorev = "990$n-sahte"; kim = 'lider'; emir = 'devam'; zaman = (Simdi); durum = 'çalışıyor' }) (Join-Path $YolParalel "990$n-sahte.json") }
    Json-Yaz ([ordered]@{ pid = 999999; gorev = '9909-olu'; kim = 'lider'; emir = 'devam'; zaman = (Get-Date).AddMinutes(-5).ToString('o'); durum = 'çalışıyor' }) (Join-Path $YolParalel '9909-olu.json')
    Dogrula 'iki canlı hat sayılır, ölü hat silinir' (@(Paralel-Hatlari).Count -eq 2 -and -not (Test-Path (Join-Path $YolParalel '9909-olu.json')))
    $g = Test-Gorevi '9507-sira' 'yeni' @{ tip = 'genel'; oncelik = 3 }
    $s5 = Gorev-Komut-Ver $g 'lider' 'devam'
    $d = Gorev-Oku $g.id
    Dogrula 'karar sira, one_al işaretlendi' ($s5.karar -eq 'sira' -and $d.one_al -eq $true) "$($s5.karar) / $($s5.neden)"
    $sec = Siradaki-Gorev
    Dogrula 'Siradaki-Gorev öne alınan işi başlamış işlerden önce seçer' ($sec -and $sec.id -eq $g.id) "$($sec.id)"
    Get-ChildItem -LiteralPath $YolParalel -File | Remove-Item -Force
    foreach ($x in @(Gorevleri-Listele)) { if ($x.asama -notin @('tamam', 'iptal')) { $x.asama = 'iptal'; Gorev-Kaydet $x } }   # sonraki denemeler sırayı karıştırmasın

    Write-Host ''; Write-Host 'K6: durum.ps1 -Komut -Baslatma (panelin çağırdığı biçim)'
    $g = Test-Gorevi '9508-cli' 'denetim'
    $c = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kum 'durum.ps1') -Komut '9508' -Kim 'tester' -Emir 'devral' -Not 'arayüzü de dene' -Baslatma 2>&1 | Out-String
    $d = Gorev-Oku $g.id
    Dogrula 'çıktıda komut özeti ve PARALEL satırı' ($c -match 'Komut: #9508 QA Engineer devraldı' -and $c -match '(?m)^PARALEL: 9508-cli') (((($c.Trim() -split "`n") | Select-Object -First 2)) -join ' | ')
    Dogrula 'denetci -> tester devralındı, talimat yazıldı' ($d.devralan.denetci -eq 'tester' -and (Metin-Oku (Join-Path (Gorev-Klasoru $g.id) 'kullanici-talimatlari.md')) -match 'arayüzü de dene')
    $d.asama = 'iptal'; Gorev-Kaydet $d

    # ------------------------------------------------------------ L: görev kilidi
    Write-Host ''; Write-Host 'L1: başka süreç işi tutarken döngü almaz, adım yürütmez'
    $g = Test-Gorevi '9511-kilit' 'gelistirme'
    $tutan = Kilit-Tutan-Surec $g.id
    try {
        Dogrula 'Gorev-Kilitli-mi: evet' (Gorev-Kilitli-mi $g.id)
        Dogrula 'Siradaki-Gorev kilitli işi seçmez' ($null -eq (Siradaki-Gorev))
        Cagrilari-Sil
        Gorev-Ilerlet $g
        Dogrula 'Gorev-Ilerlet hiçbir şey yapmaz (atlandı, ajan çağrılmadı)' ($script:IlerletmeAtlandi -and -not (Cagrilar) -and (Gorev-Oku $g.id).asama -eq 'gelistirme')

        Write-Host ''; Write-Host 'L2: iş yürütülürken verilen komut yalnızca komut alanlarını işler'
        $eski = Gorev-Oku $g.id
        $disk = Gorev-Oku $g.id; $disk.asama = 'kontrol'; Gecmis-Ekle $disk 'paralel hat ilerletti'; Gorev-Kaydet $disk   # o süreç bu arada ilerletti
        $s6 = Gorev-Komut-Ver $eski 'lider' 'devral'
        $d = Gorev-Oku $g.id
        Dogrula 'karar surer; disk aşaması ezilmedi; devralan işlendi' ($s6.karar -eq 'surer' -and $d.asama -eq 'kontrol' -and $d.devralan.denetci -eq 'lider' -and ((Olaylar $d) -contains 'paralel hat ilerletti')) "$($s6.karar) / $($d.asama) / $($d.devralan | ConvertTo-Json -Compress)"
    } finally { Sureci-Bitir $tutan }
    Dogrula 'süreç bitince kilit kalkar' (-not (Gorev-Kilitli-mi $g.id))

    Write-Host ''; Write-Host 'L3: adım sürerken gelen komut adım sonucunda korunur'
    $g = Test-Gorevi '9512-sirada' 'gelistirme'
    $orijinal = ${function:Adim-Gelistirme}
    ${function:Adim-Gelistirme} = {
        param($G)
        $disk = Gorev-Oku $G.id   # panel bu sırada komut verdi (iş başka süreçte tutulurken yalnızca komut alanları yazılır)
        Ayarla $disk 'devralan' ([pscustomobject]@{ denetci = 'tester' })
        Ayarla $disk 'komutlar' @([pscustomobject]@{ zaman = (Simdi); kim = 'tester'; emir = 'devral' })
        Gorev-Kaydet $disk
        Asama-Gec $G 'kontrol' 'geliştirme bitti'
    }
    Gorev-Ilerlet $g
    ${function:Adim-Gelistirme} = $orijinal
    $d = Gorev-Oku $g.id
    Dogrula 'adım sonucu (kontrol) ve komut (devralan) birlikte kaydedildi' ($d.asama -eq 'kontrol' -and $d.devralan.denetci -eq 'tester' -and @($d.komutlar).Count -eq 1) "$($d.asama)"

    Write-Host ''; Write-Host 'L4: sıra seçildikten sonra değişen kayıt tazelenir (iptal edilen iş yürütülmez)'
    $g = Test-Gorevi '9513-taze' 'plan'
    Start-Sleep -Milliseconds 20
    $disk = Gorev-Oku $g.id; $disk.asama = 'iptal'; Gorev-Kaydet $disk
    Cagrilari-Sil
    Gorev-Ilerlet $g
    Dogrula 'bellekteki kopya iptale tazelendi, ajan çağrılmadı' ($g.asama -eq 'iptal' -and $script:IlerletmeAtlandi -and -not (Cagrilar)) "$($g.asama)"

    Write-Host ''; Write-Host 'L5: ana döngü kalp atışına göre bu işin üzerindeyse (kilitsiz adım: Incident Manager) hat açılmaz'
    $g = Test-Gorevi '9514-kalp' 'takildi' @{ takildi_asama = 'gelistirme' }
    $baska = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -WindowStyle Hidden -PassThru
    $kalpYolu5 = Join-Path $YolDurum 'kalp.json'
    $kalpYedek = Metin-Oku $kalpYolu5
    try {
        Json-Yaz ([ordered]@{ pid = $baska.Id; zaman = (Simdi); durum = 'claude çalışıyor'; gorev = $g.id; adim = 'cozum (claude/sahte-cozucu)' }) $kalpYolu5
        Dogrula 'Dongu-Bu-Iste-mi: evet' (Dongu-Bu-Iste-mi $g.id)
        $s8 = Gorev-Komut-Ver $g 'lider' 'devral'
        $d = Gorev-Oku $g.id
        Dogrula 'karar surer; takılan iş sürdürülmedi, devralan işlendi' ($s8.karar -eq 'surer' -and $d.asama -eq 'takildi' -and $d.devralan.gelistirici -eq 'lider') "$($s8.karar) / $($d.asama)"
        Json-Yaz ([ordered]@{ pid = $baska.Id; zaman = (Simdi); durum = 'döngü'; gorev = $g.id; adim = '' }) $kalpYolu5
        Dogrula 'döngü başka işe geçerken ("döngü") meşgul sayılmaz' (-not (Dongu-Bu-Iste-mi $g.id))
    } finally {
        Sureci-Bitir $baska
        if ($kalpYedek) { Metin-Yaz $kalpYolu5 $kalpYedek } else { Remove-Item -LiteralPath $kalpYolu5 -Force -ErrorAction SilentlyContinue }
    }
    $d = Gorev-Oku $g.id; $d.asama = 'iptal'; Gorev-Kaydet $d

    # ------------------------------------------------------------ P: paralel hat (ayrı süreç)
    Write-Host ''; Write-Host 'P1: paralel.ps1 işi adım adım tamamlar; QA Engineer Code Reviewerʼın adımını devralmış'
    $id = '9521-paralel'
    $wt = Join-Path $YolCalisma $id
    Git-T -C $repo worktree add -q -b "ekip/9521" $wt | Out-Null
    [IO.File]::WriteAllText((Join-Path $wt 'b.txt'), "b`n", $ascii)
    $g = Test-Gorevi $id 'denetim' @{ dal = 'ekip/9521'; temel_commit = $temel; gelistirici = 'claude/sahte-gelistirici' }
    $g.calisma_klasoru = $wt; Gorev-Kaydet $g
    $s7 = Gorev-Komut-Ver $g 'tester' 'devral' 'kenar durumları dene'
    Dogrula 'komut paralel hat ister' ($s7.karar -eq 'paralel') $s7.karar
    Cagrilari-Sil
    Model-Yanit 'sahte-tester' "KARAR: ONAY`n`nTester denetledi."
    Model-Yanit 'sahte-denetci' 'KARAR: DUZELT (yanlış: Code Reviewer çağrıldı)'
    Model-Yanit 'sahte-yonetici' "KARAR: KABUL`nCOMMIT: b dosyası`nOZET: tamam"
    $kalpYolu = Join-Path $YolDurum 'kalp.json'
    $kalpOnce = $(if (Test-Path $kalpYolu) { (Get-Item $kalpYolu).LastWriteTimeUtc.Ticks } else { 0 })
    $p = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $kum 'paralel.ps1'), '-Gorev', '9521', '-Kim', 'tester', '-Komut', 'devral') -WindowStyle Hidden -PassThru
    $hatGoruldu = $false
    for ($i = 0; $i -lt 600 -and -not $p.HasExited; $i++) { if (-not $hatGoruldu -and (Test-Path (Join-Path $YolParalel "$id.json"))) { $hatGoruldu = $true }; Start-Sleep -Milliseconds 200 }
    if (-not $p.HasExited) { Sureci-Bitir $p }
    Model-Yanitlari-Sil
    $d = Gorev-Oku $id
    $log = Cagrilar
    Dogrula 'hat çalışırken durum\paralel kaydı vardı' $hatGoruldu
    Dogrula 'iş tamamlandı (denetim -> kabul -> commit)' ($d.asama -eq 'tamam' -and $d.commit) "$($d.asama)"
    Dogrula 'denetimi QA Engineer yaptı, Code Reviewer çağrılmadı' ($log -match 'sahte-tester' -and $log -notmatch 'sahte-denetci' -and $log -match 'sahte-yonetici')
    Dogrula 'geçmişte paralel çalışma bitti kaydı (3 adım)' (@($d.gecmis | Where-Object { $_.olay -eq 'paralel çalışma bitti' -and $_.ayrinti -match '3 adım' }).Count -eq 1) (@($d.gecmis | Select-Object -Last 1).ayrinti)
    Dogrula 'hat kaydı silindi, kilit bırakıldı' (-not (Test-Path (Join-Path $YolParalel "$id.json")) -and -not (Gorev-Kilitli-mi $id))
    $kalpSonra = $(if (Test-Path $kalpYolu) { (Get-Item $kalpYolu).LastWriteTimeUtc.Ticks } else { 0 })
    Dogrula 'döngünün kalp.json dosyasına yazmadı' ($kalpSonra -eq $kalpOnce)

    Write-Host ''; Write-Host 'P2: paralel-durdur ve hattın dışındaki süreç'
    $g = Test-Gorevi '9522-durdur' 'gelistirme'
    Metin-Yaz (Paralel-Durdur-Dosyasi $g.id) 'durdur'
    Dogrula 'döngü sürecinde paralel-durdur iptal sayılmaz' (-not (Gorev-Iptal-mi $g.id))
    $script:ParalelGorev = $g.id
    Dogrula 'hattın kendi sürecinde iptal sayılır (ajan durdurulur)' (Gorev-Iptal-mi $g.id)
    $script:ParalelGorev = ''
    Remove-Item -LiteralPath (Paralel-Durdur-Dosyasi $g.id) -Force
    $script:ParalelBilgi = $null
    Json-Yaz ([ordered]@{ pid = $PID; gorev = $g.id; kim = 'lider'; emir = 'devam'; zaman = (Simdi); durum = 'çalışıyor' }) (Paralel-Kayit-Yolu $g.id)
    $m = Paralel-Durdur $g
    Dogrula 'Paralel-Durdur dosyayı yazar' ((Test-Path (Paralel-Durdur-Dosyasi $g.id)) -and $m -match 'durduruluyor') $m
    Paralel-Kaydi-Sil $g.id
    $d = Gorev-Oku $g.id; $d.asama = 'iptal'; Gorev-Kaydet $d

    Write-Host ''; Write-Host 'P3: iki süreç aynı dosyaya eşzamanlı yazar (Metin-Yaz)'
    $ortak = Join-Path $kum 'ortak.ps1'
    $hedef = Join-Path $kum 'eszamanli.json'
    $kod = ". '$ortak'; for (`$i = 0; `$i -lt 150; `$i++) { Metin-Yaz '$hedef' ('[' + `$i + ']') }"
    $ps = @(1, 2 | ForEach-Object { Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-Command', $kod) -WindowStyle Hidden -PassThru })
    foreach ($x in $ps) { [void]$x.WaitForExit(90000) }
    $kodlar = @($ps | ForEach-Object { $_.ExitCode })
    $icerik = (Metin-Oku $hedef).Trim()
    Dogrula 'iki süreç de hatasız bitti, dosya bütün (son yazım)' (($kodlar -join ',') -eq '0,0' -and $icerik -match '^\[\d+\]$') "$($kodlar -join ',') / $icerik"
    Dogrula 'geçici dosya kalmadı' (@(Get-ChildItem -LiteralPath $kum -Filter 'eszamanli.json.*.tmp').Count -eq 0)
} catch {
    $script:Kalan++
    Write-Host ("  [HATA] Test çöktü: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
}

Write-Host ''
Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
if ($script:Kalan -eq 0 -and -not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "Kum havuzu korundu: $kum (günlük: $(Join-Path $kum 'gunluk'))" }
exit $script:Kalan
