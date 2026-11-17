<#
iptal-yarisi.test.ps1 - Adım (ajan çağrısı) sürerken gelen kullanıcı iptalinin korunduğunu sınar. Çevrimdışıdır:
gerçek Claude / Codex çağrılmaz, gerçek gorevler\ klasörüne, bildirimlere ve e-postaya dokunulmaz.

Betikler geçici bir kum havuzuna kopyalanır; claude.exe yerine uzun süren sahte bir ajan (.cmd) kullanılır ve
iptal, panelin de çağırdığı gerçek yoldan (ayrı bir süreçte "durum.ps1 -Iptal") verilir.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\iptal-yarisi.test.ps1
  ... -Kaynak <betik klasörü>   başka bir kopyayı sına (varsayılan: bu klasörün üstü, yani kurulum klasörü)
  ... -Koru                     kum havuzunu silme (günlüğü incelemek için)

Senaryolar:
  T1  ajan uzun sürerken iptal       -> ajan süreç ağacı ~15 sn içinde öldürülür, yedek araca geçilmez, iptal kalır
  T2  ajan iptalden sonra kendi biter -> ajanın sonucu kullanılmaz (plan.md yazılmaz), iptal kalır
  T3  betik adımı sürerken iptal      -> adım bellekte yeni tura geçse de iptal ezilmez (son savunma: Gorev-Ilerlet)
  T4  uzman doğrulama komutu sürerken iptal -> komut öldürülür, iptal kalır
  T5  iptal yok                        -> normal akış değişmedi (plan hazır -> gelistirme)
Çıkış kodu: kalan denetim sayısı (0 = hepsi geçti).
#>
param([string]$Kaynak = '', [string]$KumKlasoru = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
if (-not $KumKlasoru) { $KumKlasoru = Join-Path $env:TEMP ('ai-ekip-iptal-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$kum = $KumKlasoru
if (Test-Path -LiteralPath (Join-Path $kum 'gorevler')) { throw "Kum havuzu boş değil: $kum" }
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

# ---------------------------------------------------------------- kum havuzunu kur
Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$ascii = New-Object Text.ASCIIEncoding
$kumAyar = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$sahteAjan = Join-Path $kum 'sahte-ajan.cmd'
$kumAyar.claude.exe = $sahteAjan
$kumAyar.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$kumAyar.zaman_asimi_dk.claude = 10
$kumAyar.gunluk_sinir.claude = 1000
# Yalnızca sahte ajana giden iki araçlı lider zinciri: ikinci araç çağrılırsa "yedek zincire geçildi" demektir
$kumAyar.roller = [pscustomobject]@{ lider = @([pscustomobject]@{ arac = 'claude'; model = 'sahte1' }, [pscustomobject]@{ arac = 'claude'; model = 'sahte2' }) }
$kumAyar.bildirim.masaustu = $false
$kumAyar.bildirim.telefon = $null
if ($kumAyar.PSObject.Properties['altyapi']) { $kumAyar.altyapi.makineler = @(); $kumAyar.altyapi.vmrun = '' }
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($kumAyar | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), '{ "surum": 1, "uyeler": [] }', $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
# Sahte ajan: her çağrıyı kaydeder, sahte-sure.txt kadar (ping -n) bekler, başarılı bir Claude JSON çıktısı verir
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off'
    'setlocal'
    '>> "%~dp0cagrilar.log" echo %*'
    'set SURE=3'
    'if exist "%~dp0sahte-sure.txt" set /p SURE=<"%~dp0sahte-sure.txt"'
    'ping -n %SURE% 127.0.0.1 >nul'
    'type "%~dp0sahte-cikti.json"'
) -join "`r`n") + "`r`n", $ascii)
$cikti = [ordered]@{ type = 'result'; subtype = 'success'; is_error = $false; result = "KARAR: PLAN_HAZIR`n`n## Plan`n1. sahte adım" } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.json'), $cikti, $ascii)

. (Join-Path $kum 'ortak.ps1')
. (Join-Path $kum 'rapor.ps1')
. (Join-Path $kum 'ekip.ps1')
if ($Kok -ne $kum) { throw "Betikler kum havuzunu değil $Kok klasörünü kullanıyor; test durduruldu" }
Ayarlari-Yukle

# ---------------------------------------------------------------- yardımcılar
$script:Kalan = 0
$script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'
    if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Test-Gorevi([string]$Id, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    $wt = Join-Path $YolCalisma $Id
    New-Item -ItemType Directory -Force $wt | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# İptal testi $Id`n`nSahte görev."
    $d = [ordered]@{
        id = $Id; baslik = "İptal testi $Id"; proje = 'test'; klasor = $wt; oncelik = 1
        asama = $Asama; tur = 1; max_tur = 3; deneme = 0; dogrulama = @()
        olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); calisma_klasoru = $wt
    }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Sahte-Sure([int]$Ping) { [IO.File]::WriteAllText((Join-Path $kum 'sahte-sure.txt'), "$Ping", $ascii) }
function Cagri-Sayisi {
    $f = Join-Path $kum 'cagrilar.log'
    if (-not (Test-Path -LiteralPath $f)) { return 0 }
    return @(Get-Content -LiteralPath $f | Where-Object { $_.Trim() }).Count
}
function Cagrilari-Sifirla { Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue }
# Panelin "Görevi iptal et" düğmesiyle aynı yol: ayrı süreçte durum.ps1 -Iptal
function Iptal-Zamanla([string]$Id, [int]$Sn) {
    $log = Join-Path $kum "iptal-$Id.log"
    $komut = "Start-Sleep -Seconds $Sn; & '$(Join-Path $kum 'durum.ps1')' -Iptal '$Id' *> '$log'"
    return (Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $komut) -WindowStyle Hidden -PassThru)
}
function Kalan-Ping([int]$N) {
    return @(Get-CimInstance Win32_Process -Filter "Name='PING.EXE'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match " -n $N 127\.0\.0\.1" })
}
function Olaylar($G) { return @($G.gecmis | ForEach-Object { [string]$_.olay }) }
function Gunluk-Metni { return (Metin-Oku (Join-Path $YolGunluk ('ekip-{0}.log' -f (Get-Date).ToString('yyyyMMdd')))) }

# Her senaryoda: iptal disk kaydına geçmiş, yok sayma notu düşülmüş, aşama/tur/deneme ezilmemiş olmalı
function Iptal-Korundu-mu([string]$Id, [int]$BeklenenTur = 1) {
    $d = Gorev-Oku $Id
    $o = Olaylar $d
    Dogrula 'diskteki aşama iptal' ([string]$d.asama -eq 'iptal') "asama=$($d.asama)"
    Dogrula 'geçmişte "kullanıcı iptal etti" duruyor' ($o -contains 'kullanıcı iptal etti')
    Dogrula 'geçmişe "iptal sonrası adım sonucu yok sayıldı" yazıldı' ($o -contains 'iptal sonrası adım sonucu yok sayıldı') ($o -join ' | ')
    Dogrula 'tur ilerlemedi' ([int]$d.tur -eq $BeklenenTur) "tur=$($d.tur)"
    Dogrula 'yeniden deneme planlanmadı' (-not $d.sonraki_deneme -and [int]$d.deneme -eq 0) "deneme=$($d.deneme), sonraki_deneme=$($d.sonraki_deneme)"
    return $d
}

try {
    # ------------------------------------------------------------ T1
    Write-Host ''
    Write-Host 'T1: ajan uzun sürerken iptal (ajan öldürülmeli, yedek araca geçilmemeli)'
    Cagrilari-Sifirla; Sahte-Sure 117
    $g = Test-Gorevi '9001-iptal-ajan-calisirken' 'plan'
    $ip = Iptal-Zamanla $g.id 4
    $sa = [Diagnostics.Stopwatch]::StartNew()
    Gorev-Ilerlet $g
    $sa.Stop(); $null = $ip.WaitForExit(60000)
    Start-Sleep -Seconds 1
    $sn = [int]$sa.Elapsed.TotalSeconds
    $d = Iptal-Korundu-mu $g.id
    Dogrula 'adım ajan bitmeden döndü (ajan ~116 sn sürecekti)' ($sn -lt 45) "$sn sn"
    Dogrula 'sahte ajan süreci kalmadı' ((Kalan-Ping 117).Count -eq 0)
    Dogrula 'yalnızca bir ajan çağrıldı (yedek zincire geçilmedi)' ((Cagri-Sayisi) -eq 1) "çağrı=$(Cagri-Sayisi)"
    Dogrula 'plan.md yazılmadı' (-not (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'plan.md')))
    Dogrula 'günlükte süreç sonlandırma kaydı var' ((Gunluk-Metni) -match [regex]::Escape("Görev $($g.id) iptal edildi; çalışan claude süreç ağacı sonlandırılıyor"))

    # ------------------------------------------------------------ T2
    Write-Host ''
    Write-Host 'T2: ajan iptalden sonra kendiliğinden bitiyor (sonuç kullanılmamalı)'
    Cagrilari-Sifirla; Sahte-Sure 13
    $g = Test-Gorevi '9002-iptal-ajan-bitince' 'plan'
    $ip = Iptal-Zamanla $g.id 1
    Gorev-Ilerlet $g
    $null = $ip.WaitForExit(60000)
    $d = Iptal-Korundu-mu $g.id
    Dogrula 'ajan tamamlandı ve tek çağrı yapıldı' ((Cagri-Sayisi) -eq 1) "çağrı=$(Cagri-Sayisi)"
    Dogrula 'plan.md yazılmadı (sonuç kullanılmadı)' (-not (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'plan.md')))
    Dogrula 'aşama gelistirme''ye geçmedi' (-not ((Olaylar $d) -contains 'plan hazır'))

    # ------------------------------------------------------------ T3
    Write-Host ''
    Write-Host 'T3: betik adımı sürerken iptal, adım bellekte yeni tura geçiyor ("yeni tura dönüldü" olayı)'
    $g = Test-Gorevi '9003-iptal-betik-adimi' 'kontrol'
    # Adim-Kontrol'u taklit et: adım sürerken kullanıcı iptal eder, adım sonra bellekte yeni tura döner
    function Adim-Kontrol($G) {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "& '$(Join-Path $kum 'durum.ps1')' -Iptal '$($G.id)' *> '$(Join-Path $kum "iptal-$($G.id).log")'")
        Yeni-Tur $G '## Otomatik kontrol: KALDI (test)' 'otomatik kontroller kaldı: test'
    }
    Gorev-Ilerlet $g
    $d = Iptal-Korundu-mu $g.id
    Dogrula '"yeni tura dönüldü" diske yazılmadı' (-not ((Olaylar $d) -contains 'yeni tura dönüldü'))
    $not = @($d.gecmis | Where-Object { $_.olay -eq 'iptal sonrası adım sonucu yok sayıldı' } | Select-Object -Last 1)
    Dogrula 'not, adımın ezecek olduğu durumu söylüyor' ($not.Count -eq 1 -and [string]$not[0].ayrinti -match 'tur 2') ([string]$not[0].ayrinti)

    # ------------------------------------------------------------ T4
    Write-Host ''
    Write-Host 'T4: uzman işinde doğrulama komutu sürerken iptal (komut öldürülmeli)'
    $g = Test-Gorevi '9004-iptal-dogrulama-komutu' 'kontrol' @{ tip = 'uzman'; sorumlu = 'test'; inceleyen = 'yok'; dogrulama = @('ping -n 118 127.0.0.1') }
    $ip = Iptal-Zamanla $g.id 4
    $sa = [Diagnostics.Stopwatch]::StartNew()
    Gorev-Ilerlet $g
    $sa.Stop(); $null = $ip.WaitForExit(60000)
    Start-Sleep -Seconds 1
    $sn = [int]$sa.Elapsed.TotalSeconds
    $d = Iptal-Korundu-mu $g.id
    Dogrula 'adım komut bitmeden döndü (komut ~117 sn sürecekti)' ($sn -lt 45) "$sn sn"
    Dogrula 'doğrulama süreci kalmadı' ((Kalan-Ping 118).Count -eq 0)

    # ------------------------------------------------------------ T5
    Write-Host ''
    Write-Host 'T5: iptal yok (normal akış bozulmamalı)'
    Cagrilari-Sifirla; Sahte-Sure 2
    $g = Test-Gorevi '9005-iptalsiz-normal-akis' 'plan'
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama gelistirme' ([string]$d.asama -eq 'gelistirme') "asama=$($d.asama)"
    Dogrula 'plan.md yazıldı' (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $g.id) 'plan.md'))
    Dogrula 'geçmişte "plan hazır" var, yok sayma notu yok' (((Olaylar $d) -contains 'plan hazır') -and -not ((Olaylar $d) -contains 'iptal sonrası adım sonucu yok sayıldı'))
    Dogrula 'tek ajan çağrısı' ((Cagri-Sayisi) -eq 1) "çağrı=$(Cagri-Sayisi)"
} catch {
    $script:Kalan++
    Write-Host ("  [HATA] Test çöktü: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    # Ne olursa olsun bu testin başlattığı sahte süreçleri bırakma
    foreach ($n in 117, 118) { foreach ($p in (Kalan-Ping $n)) { try { Stop-Process -Id $p.ProcessId -Force } catch {} } }
}

Write-Host ''
Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
if ($script:Kalan -eq 0 -and -not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "Kum havuzu korundu: $kum (günlük: $(Join-Path $kum 'gunluk'))" }
exit $script:Kalan
