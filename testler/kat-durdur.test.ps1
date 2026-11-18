<#
kat-durdur.test.ps1 - Bina panelinde her katın iki ayrı düğmesini sınar:
  "Katı kapat / aç" (mesai: ekip eve gider, kat görünür kalır) ve "Durdur / Başlat" (tam durdurma).
  * Uygulama katı (sahte uygulama sunucusu, Creative Studio'nun /api/office'i gibi): kapat / aç yalnız mesai eylemini çağırır,
    sunucular açık kalır; durdur kendi durdurucusunu (-Zorla) çalıştırır; sunucular kapalıyken durum "durduruldu",
    aç ise başlatıcıyı mesaiyi de açan argümanla (-OfisiAc) çalıştırır.
  * Ekip katı (sahte kat döngüsü: kilidi tutan, kalp.json'a PID yazan bir PowerShell): durdur DURDUR'a "Ofis kapatıldı ve
    durduruldu" yazar ve döngüyü sonlandırır; durum "durduruldu"; aç DURDUR'u kaldırır. Ana kat durdurulamaz (400).
Panelin bir kopyası kum havuzunda ayrı kilit adı ve ayrı portla çalışır; canlı panele, canlı katlara ve canlı uygulamalara dokunmaz.
Gerçek ekip döngüsü başlatılmaz (her adımda sahte döngü kilidi tutar), yapay zeka aracı çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\kat-durdur.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru, [int]$Port = 8798, [int]$UygulamaPort = 8799)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-kat-durdur-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"
$utf8 = New-Object Text.UTF8Encoding $false
$bom = New-Object Text.UTF8Encoding $true
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$katId = 'testkat-durdur-' + [guid]::NewGuid().ToString('N').Substring(0, 6)

# --- kum havuzu: kod + ana kat + bir ekip katı + bir uygulama katı
Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
foreach ($j in 'ayarlar.json', 'kadro.json') { Copy-Item -LiteralPath (Join-Path $Kaynak $j) -Destination $kum }
$ay = [IO.File]::ReadAllText((Join-Path $kum 'ayarlar.json'), $utf8) | ConvertFrom-Json
$ay.bildirim.masaustu = $false
if ($ay.bildirim.telefon) { $ay.bildirim.telefon.kanal = 'yok' }
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ay | ConvertTo-Json -Depth 12), $utf8)
New-Item -ItemType Directory -Force (Join-Path $kum 'ofis') | Out-Null
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Kaynak 'ofis') -File | Where-Object { $_.Extension -in '.ps1', '.html', '.png', '.ico' })) {
    $hedef = Join-Path (Join-Path $kum 'ofis') $f.Name
    if ($f.Name -eq 'ofis.ps1') {
        $t = [IO.File]::ReadAllText($f.FullName, $utf8).Replace("'Local\AIEkipOfis'", "'Local\AIEkipOfisKatDurdurTesti'")
        [IO.File]::WriteAllText($hedef, $t, $bom)
    } else { Copy-Item -LiteralPath $f.FullName -Destination $hedef }
}
# Uygulama katı: sahte başlatıcı / durdurucu (aldıkları argümanları dosyaya yazar)
$uk = Join-Path $kum 'uygulama'; New-Item -ItemType Directory -Force $uk | Out-Null
foreach ($ad in 'baslat', 'durdur') {
    [IO.File]::WriteAllText((Join-Path $uk "$ad.ps1"), ('[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''' + $ad + '.isaret''), ($args -join '' ''))'), $bom)
}
$katlar = [ordered]@{ surum = 1; sirket = 'Test Şirketi'; katlar = @(
        [ordered]@{ id = 'ana'; ad = 'Ana'; kat_no = 3; tur = 'ekip'; kok = '' },
        [ordered]@{ id = $katId; ad = 'Ekip Katı'; kat_no = 2; tur = 'ekip'; kok = "katlar\$katId" },
        [ordered]@{ id = 'studyo'; ad = 'Stüdyo'; kat_no = 0; tur = 'uygulama'; kok = $uk
            uygulama = [ordered]@{ api = "http://127.0.0.1:$UygulamaPort/api"; adres = "http://127.0.0.1:$UygulamaPort/"; baslat = 'baslat.ps1'; baslat_arg = '-TarayiciAcma'
                durdur = 'durdur.ps1'; durdur_arg = '-Zorla'; ofis = 'office'; ofis_ac_arg = '-OfisiAc'; kisi = 8 } }) }
[IO.File]::WriteAllText((Join-Path $kum 'katlar.json'), ($katlar | ConvertTo-Json -Depth 6), $utf8)
$kk = Join-Path $kum "katlar\$katId"; New-Item -ItemType Directory -Force (Join-Path $kk 'durum') | Out-Null
Copy-Item -LiteralPath (Join-Path $Kaynak 'kadro.json') -Destination $kk
[IO.File]::WriteAllText((Join-Path $kk 'ayarlar.json'), '{ "surum": 1 }', $utf8)
# Başlangıçta kat kapalı: panelin bina bekçisi (2 dk) gerçek döngü başlatmasın
[IO.File]::WriteAllText((Join-Path $kk 'DURDUR'), 'Ofis kapatıldı (test)', $utf8)

# Sahte kat döngüsü: döngü kilidini tutar, kalp.json'a PID yazar (komut satırında baslat.ps1 geçer), 120 sn bekler
$sahteDongu = Join-Path $kk 'sahte\baslat.ps1'
New-Item -ItemType Directory -Force (Split-Path -Parent $sahteDongu) | Out-Null
$kilitAdi = 'Local\AIEkipDongusu_' + ($katId -replace '[^a-z0-9]', '_')
[IO.File]::WriteAllText($sahteDongu, @"
`$m = New-Object Threading.Mutex(`$true, '$kilitAdi')
[IO.File]::WriteAllText('$kk\durum\kalp.json', ('{"pid": ' + `$PID + ', "zaman": "' + (Get-Date).ToString('o') + '", "durum": "çalışıyor"}'))
Start-Sleep -Seconds 120
"@, $bom)
function Sahte-Dongu-Baslat {
    $p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $sahteDongu) -WindowStyle Hidden -PassThru
    $son = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $son) {
        $m = $null
        if ([Threading.Mutex]::TryOpenExisting($kilitAdi, [ref]$m)) { $m.Dispose(); if (Test-Path -LiteralPath "$kk\durum\kalp.json") { return $p } }
        Start-Sleep -Milliseconds 200
    }
    throw 'sahte döngü başlamadı'
}

# Sahte uygulama sunucusu (Python): GET / POST /api/office; alınan eylemler eylemler.txt'ye yazılır
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
$uygulamaBetigi = Join-Path $kum 'sahte_uygulama.py'
[IO.File]::WriteAllText($uygulamaBetigi, @'
import json, sys, pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
durum = {"durum": "acik"}
kayit = pathlib.Path(sys.argv[2])
class H(BaseHTTPRequestHandler):
    def _yaz(self, kod, nesne):
        b = json.dumps(nesne).encode(); self.send_response(kod); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self._yaz(200, durum) if self.path == "/api/office" else self._yaz(404, {})
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); e = json.loads(self.rfile.read(n) or b"{}").get("eylem")
        with kayit.open("a", encoding="utf-8") as f: f.write(str(e) + "\n")
        durum["durum"] = {"ac": "acik", "surdur": "acik", "kapat": "kapali", "duraklat": "duraklatildi"}.get(e, durum["durum"])
        self._yaz(200, durum)
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
'@, $utf8)
$eylemKaydi = Join-Path $kum 'eylemler.txt'

$gecen = 0; $kalan = 0
function Denetim([string]$Ad, [bool]$Sonuc) {
    if ($Sonuc) { $script:gecen++; Write-Host "  [GEÇTİ] $Ad" -ForegroundColor Green } else { $script:kalan++; Write-Host "  [KALDI] $Ad" -ForegroundColor Red }
}
function Bekle([scriptblock]$Kosul, [int]$Sn = 15) {
    $son = (Get-Date).AddSeconds($Sn)
    while ((Get-Date) -lt $son) { if (& $Kosul) { return $true }; Start-Sleep -Milliseconds 250 }
    return [bool](& $Kosul)
}
$uygulama = $null; $dongu = $null
$surec = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $kum 'ofis\ofis.ps1'), '-Port', $Port, '-BosKapanDk', '0') -WindowStyle Hidden -PassThru
$sunucu = Join-Path $kum 'ofis\sunucu.json'
try {
    if (-not $py) { throw 'python bulunamadı (sahte uygulama sunucusu için gerekli)' }
    $uygulama = Start-Process -FilePath $py -ArgumentList @('-I', $uygulamaBetigi, $UygulamaPort, $eylemKaydi) -WindowStyle Hidden -PassThru
    if (-not (Bekle { Test-Path -LiteralPath $sunucu } 40)) { throw 'test sunucusu başlamadı (ofis\ofis.log)' }
    $p = [int](Get-Content -LiteralPath $sunucu -Raw | ConvertFrom-Json).port
    $taban = "http://127.0.0.1:$p"
    $sayfa = Invoke-WebRequest -Uri "$taban/" -UseBasicParsing -TimeoutSec 20
    $anahtar = [regex]::Match($sayfa.Content, "ANAHTAR\s*=\s*'([^']+)'").Groups[1].Value
    function Api([string]$Yol, $Govde = $null) {
        $rq = [Net.HttpWebRequest]::Create("$taban$Yol"); $rq.Timeout = 30000; $rq.KeepAlive = $false; $rq.Proxy = $null
        $rq.Headers.Add('X-Ofis-Anahtar', $anahtar)
        if ($null -ne $Govde) {
            $rq.Method = 'POST'; $b = [Text.Encoding]::UTF8.GetBytes(($Govde | ConvertTo-Json -Compress))
            $rq.ContentType = 'application/json; charset=utf-8'; $rq.ContentLength = $b.Length
            $s = $rq.GetRequestStream(); $s.Write($b, 0, $b.Length); $s.Close()
        }
        try { $y = $rq.GetResponse() } catch [Net.WebException] { $y = $_.Exception.Response; if (-not $y) { throw } }
        try { $m = (New-Object IO.StreamReader($y.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd(); return [pscustomobject]@{ kod = [int]$y.StatusCode; j = $(try { $m | ConvertFrom-Json } catch { $null }) } } finally { $y.Close() }
    }
    function Kat([string]$Id) { return (@((Api '/api/katlar').j.katlar) | Where-Object { $_.id -eq $Id } | Select-Object -First 1) }
    Denetim 'bina sayfasında her kat için ayrı Durdur düğmesi' ($sayfa.Content -match 'id="katDurdur"' -and $sayfa.Content -match "'/api/kat-' \+ eylem")

    # --- uygulama katı
    Denetim 'uygulama katı: sunucu açık, mesai açık → durum açık' (Bekle { $k = Kat 'studyo'; $k -and $k.acik -and $k.durum -eq 'acik' } 15)
    $r = Api '/api/kat-kapat' @{ kat = 'studyo' }
    Denetim 'uygulama katı: Katı kapat yalnız mesaiyi kapatır (uygulamaya "kapat")' ($r.kod -eq 200 -and (Bekle { (Test-Path -LiteralPath $eylemKaydi) -and ((Get-Content -LiteralPath $eylemKaydi) -contains 'kapat') } 10))
    $k = Kat 'studyo'
    Denetim 'uygulama katı: kapalıyken kat görünür (sunucular açık, durum kapalı)' ($k.acik -and $k.durum -eq 'kapali')
    Denetim 'uygulama katı: Katı kapat durdurucuyu çalıştırmaz' (-not (Test-Path -LiteralPath (Join-Path $uk 'durdur.isaret')))
    $r = Api '/api/kat-ac' @{ kat = 'studyo' }
    Denetim 'uygulama katı: Katı aç mesaiyi açar (uygulamaya "ac", başlatıcı çalışmaz)' ($r.kod -eq 200 -and ((Get-Content -LiteralPath $eylemKaydi) -contains 'ac') -and -not (Test-Path -LiteralPath (Join-Path $uk 'baslat.isaret')) -and (Kat 'studyo').durum -eq 'acik')
    $r = Api '/api/kat-durdur' @{ kat = 'studyo' }
    Denetim 'uygulama katı: Durdur kendi durdurucusunu -Zorla ile çalıştırır' ($r.kod -eq 200 -and (Bekle { Test-Path -LiteralPath (Join-Path $uk 'durdur.isaret') } 20) -and ((Get-Content -LiteralPath (Join-Path $uk 'durdur.isaret') -Raw).Trim() -eq '-Zorla'))
    Stop-Process -Id $uygulama.Id -Force; $uygulama = $null
    Denetim 'uygulama katı: sunucular kapalıyken durum "durduruldu"' (Bekle { $k = Kat 'studyo'; $k -and -not $k.acik -and $k.durum -eq 'durduruldu' } 10)
    $r = Api '/api/kat-ac' @{ kat = 'studyo' }
    Denetim 'uygulama katı: Başlat başlatıcıyı mesaiyi de açarak çalıştırır (-TarayiciAcma -OfisiAc)' ($r.kod -eq 200 -and (Bekle { Test-Path -LiteralPath (Join-Path $uk 'baslat.isaret') } 20) -and ((Get-Content -LiteralPath (Join-Path $uk 'baslat.isaret') -Raw).Trim() -eq '-TarayiciAcma -OfisiAc'))
    $r = Api '/api/kat-kapat' @{ kat = 'studyo' }
    Denetim 'uygulama katı: durdurulmuşken Katı kapat bir şey yapmaz' ($r.kod -eq 200 -and $r.j.cikti -match 'durdurulmuş')

    # --- ekip katı
    Remove-Item -LiteralPath (Join-Path $kk 'DURDUR') -Force
    $dongu = Sahte-Dongu-Baslat
    Denetim 'ekip katı: döngü çalışırken durum açık' ((Kat $katId).durum -eq 'acik')
    $r = Api '/api/kat-durdur' @{ kat = $katId }
    Denetim 'ekip katı: Durdur döngüyü (süren adımıyla) sonlandırır' ($r.kod -eq 200 -and $r.j.cikti -match 'sonland' -and (Bekle { -not (Get-Process -Id $dongu.Id -ErrorAction SilentlyContinue) } 10))
    $durdurMetni = [IO.File]::ReadAllText((Join-Path $kk 'DURDUR'), $utf8)
    Denetim 'ekip katı: DURDUR "Ofis kapatıldı ve durduruldu" ile başlar (bekçi başlatmaz, panel evde gösterir)' ($durdurMetni.StartsWith('Ofis kapatıldı ve durduruldu'))
    Denetim 'ekip katı: durum "durduruldu"' (Bekle { (Kat $katId).durum -eq 'durduruldu' } 10)
    $dongu = Sahte-Dongu-Baslat   # gerçek döngü başlatılmasın: Başlat çalışan döngüyü görür
    $r = Api '/api/kat-ac' @{ kat = $katId }
    Denetim 'ekip katı: Başlat DURDUR dosyasını kaldırır' ($r.kod -eq 200 -and -not (Test-Path -LiteralPath (Join-Path $kk 'DURDUR')) -and (Kat $katId).durum -eq 'acik')
    $r = Api '/api/kat-kapat' @{ kat = $katId }
    $k = Kat $katId
    Denetim 'ekip katı: Katı kapat (mesai) durdurulmuş sayılmaz' ($r.kod -eq 200 -and $k.durum -eq 'kapali')
    Denetim 'ana kat buradan durdurulamaz (400)' ((Api '/api/kat-durdur' @{ kat = 'ana' }).kod -eq 400 -and -not (Test-Path -LiteralPath (Join-Path $kum 'DURDUR')))
} finally {
    foreach ($s in @($surec, $uygulama, $dongu)) { if ($s) { try { Stop-Process -Id $s.Id -Force -ErrorAction SilentlyContinue } catch {} } }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($kum) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
    Start-Sleep -Milliseconds 500
    if (-not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
Write-Host "Sonuç: $gecen/$($gecen + $kalan) denetim geçti"
if ($kalan) { exit 1 }
