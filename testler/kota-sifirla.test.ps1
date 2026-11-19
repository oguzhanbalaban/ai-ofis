<#
kota-sifirla.test.ps1 - Günlük hak sıfırlamayı sınar (panel ↺ düğmesi > /api/kota-sifirla > durum.ps1 -KotaSifirla): ofisin günlük
çağrı sayacı ve aracın kullanım / kota sınırı kilitleri sıfırlanır; giriş ve model kilitleri, öbür araçların sayaçları kalır; sınır
yüzünden takılan işler takıldığı aşamadan sürer, yeniden denemeyi bekleyenler beklemez; başka nedenle takılan ve biten işlere
dokunulmaz; panel ucu yalnızca bilinen araç adını kabul eder. Çevrimdışıdır: hiçbir ajan çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\kota-sifirla.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-kota-sifirla-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
Copy-Item -LiteralPath (Join-Path $Kaynak 'kadro.json') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$ayarJ.gunluk_sinir = [pscustomobject]@{ claude = 100; codex = 60; gemini = 40 }
$ayarJ.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @() }) | ConvertTo-Json -Depth 5), $bom)

$durum = Join-Path $kum 'durum'; New-Item -ItemType Directory -Force $durum | Out-Null
$simdi = Get-Date
function Json-Dosya([string]$Yol, $Nesne) { New-Item -ItemType Directory -Force (Split-Path -Parent $Yol) | Out-Null; [IO.File]::WriteAllText($Yol, ($Nesne | ConvertTo-Json -Depth 10), $bom) }
function Json-Al([string]$Yol) { return ([IO.File]::ReadAllText($Yol, $bom) | ConvertFrom-Json) }
Json-Dosya (Join-Path $durum 'sayaclar.json') ([ordered]@{ tarih = $simdi.ToString('yyyy-MM-dd'); claude = 100; codex = 47; gemini = 3; tamamlanan = 12; takilan = 2; ozet_gonderilen = @('12:30') })
$kilit = { param([double]$Saat, [string]$Neden) [ordered]@{ bitis = $simdi.AddHours($Saat).ToString('o'); neden = $Neden } }
Json-Dosya (Join-Path $durum 'kilitler.json') ([ordered]@{
    'claude' = (& $kilit 1 'Claude kullanım sınırı')
    'claude:sahte-model' = (& $kilit 6 'model bu Claude CLI sürümünde kullanılamıyor')
    'codex:sahte-codex' = (& $kilit 1 'Codex kullanım sınırı')
    'gemini' = (& $kilit 12 'Gemini girişi/katmanı uygun değil')
})
$sinirHatasi = "'Test ediliyor' aşaması 4 denemede tamamlanamadı: QA Engineer test edemedi: claude/sahte-sonnet: günlük sınır doldu (100/100) | codex/sahte-codex: Codex kullanım sınırı (20:30'e kadar)"
$eskiZaman = $simdi.AddHours(-2).ToString('o')
function Gorev-Yaz([string]$Id, [hashtable]$Alanlar) {
    $g = [ordered]@{ id = $Id; baslik = "Deneme $Id"; tip = 'yazilim'; proje = 'deneme'; oncelik = 2; asama = 'gelistirme'; tur = 1; max_tur = 3; deneme = 0
        olusturma = $eskiZaman; guncelleme = $eskiZaman; son_hata = ''; sonraki_deneme = $null; gecmis = @() }
    foreach ($k in $Alanlar.Keys) { $g[$k] = $Alanlar[$k] }
    Json-Dosya (Join-Path $kum "gorevler\$Id\durum.json") $g
}
$olay = { param([string]$Olay, [string]$Ayrinti) [ordered]@{ zaman = $eskiZaman; asama = 'test'; tur = 2; olay = $Olay; ayrinti = $Ayrinti } }
Gorev-Yaz '0901-claude-sinirdan-takildi' @{ asama = 'takildi'; takildi_asama = 'test'; tur = 2; deneme = 4; son_hata = $sinirHatasi; cozum_sayisi = 3; cozum_durumu = 'vazgecti'
    gecmis = @((& $olay 'takıldı' $sinirHatasi), (& $olay 'Incident Manager inceleyemedi' 'claude/sahte-opus: günlük sınır doldu (100/100)')) }
Gorev-Yaz '0902-codex-sinirdan-bekliyor' @{ asama = 'gelistirme'; deneme = 1; sonraki_deneme = $simdi.AddMinutes(30).ToString('o'); son_hata = "Full-Stack Developer çalışamadı: codex/sahte-codex: Codex kullanım sınırı (21:32'e kadar)" }
Gorev-Yaz '0903-baska-nedenle-takildi' @{ asama = 'takildi'; takildi_asama = 'kontrol'; deneme = 4; son_hata = "'Kontrol ediliyor' aşaması 4 denemede tamamlanamadı: derleme hatası"
    gecmis = @((& $olay 'takıldı' "'Kontrol ediliyor' aşaması 4 denemede tamamlanamadı: derleme hatası"), (& $olay 'Incident Manager inceleyemedi' 'claude/sahte-opus: günlük sınır doldu (100/100)')) }
Gorev-Yaz '0904-claude-sinirdan-bekliyor' @{ asama = 'plan'; deneme = 1; sonraki_deneme = $simdi.AddMinutes(30).ToString('o'); son_hata = 'Engineering Manager çalışamadı: claude/sahte-opus: günlük sınır doldu (100/100)' }
Gorev-Yaz '0905-bitmis' @{ asama = 'tamam'; son_hata = 'claude/sahte-opus: günlük sınır doldu (100/100)' }

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
# durum.ps1 ayrı süreçte, kum havuzunun kendi kopyasıyla (ana kat) çalışır
function Durum([string]$ArgMetni) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $komut = "try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}; & '" + (Join-Path $kum 'durum.ps1') + "' $ArgMetni"
    $eskiKat = $env:AIEKIP_KAT; Remove-Item env:AIEKIP_KAT -ErrorAction SilentlyContinue
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $c = (& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $komut 2>&1 | Out-String); $kod = $LASTEXITCODE }
    finally { $ErrorActionPreference = $eap; if ($eskiKat) { $env:AIEKIP_KAT = $eskiKat } }
    return [pscustomobject]@{ kod = $kod; cikti = [string]$c }
}
function Gorev-Al([string]$Id) { return (Json-Al (Join-Path $kum "gorevler\$Id\durum.json")) }
function Kilit-Adlari { return @((Json-Al (Join-Path $durum 'kilitler.json')).PSObject.Properties | ForEach-Object { $_.Name }) }

try {
    Write-Host 'K1: -KotaSifirla claude'
    $r = Durum '-KotaSifirla claude'
    Dogrula 'komut başarılı' ($r.kod -eq 0) ("kod $($r.kod)")
    Dogrula 'çıktı: sayaç ve sınır bilgisi' ($r.cikti -match 'Claude günlük hakkı sıfırlandı: bugün 100 çağrı yapılmıştı, şimdi 0/100\.') ((($r.cikti -split "`n") | Select-Object -First 2) -join ' / ')
    $s = Json-Al (Join-Path $durum 'sayaclar.json')
    Dogrula 'Claude sayacı 0, Codex ve Gemini sayaçları yerinde' ([int]$s.claude -eq 0 -and [int]$s.codex -eq 47 -and [int]$s.gemini -eq 3) ("claude $($s.claude), codex $($s.codex), gemini $($s.gemini)")
    Dogrula 'öbür sayaçlar ve özet zamanları korunur' ([int]$s.tamamlanan -eq 12 -and [int]$s.takilan -eq 2 -and @($s.ozet_gonderilen) -contains '12:30')
    $kl = Kilit-Adlari
    Dogrula 'Claude sınır kilidi kalktı' ($kl -notcontains 'claude') ($kl -join ', ')
    Dogrula 'model kilidi, Codex sınır kilidi ve Gemini giriş kilidi kaldı' ($kl -contains 'claude:sahte-model' -and $kl -contains 'codex:sahte-codex' -and $kl -contains 'gemini') ($kl -join ', ')
    Dogrula 'çıktı: kaldırılan kilit' ($r.cikti -match 'Kaldırılan sınır kilitleri: claude\s')
    $g1 = Gorev-Al '0901-claude-sinirdan-takildi'
    Dogrula 'sınırdan takılan iş takıldığı aşamadan sürüyor' ([string]$g1.asama -eq 'test' -and [int]$g1.deneme -eq 0 -and -not [string]$g1.son_hata) ("$($g1.asama), deneme $($g1.deneme)")
    Dogrula 'Incident Manager hakkı sıfırlandı' ([int]$g1.cozum_sayisi -eq 0 -and -not [string]$g1.cozum_durumu)
    $o1 = @($g1.gecmis | ForEach-Object { [string]$_.olay })
    Dogrula 'geçmişte "günlük hak sıfırlandı" ve "kullanıcı devam ettirdi"' ($o1 -contains 'günlük hak sıfırlandı' -and $o1 -contains 'kullanıcı devam ettirdi') ($o1 -join ' > ')
    $g4 = Gorev-Al '0904-claude-sinirdan-bekliyor'
    Dogrula 'sınırdan yeniden denemeyi bekleyen iş beklemez, aşaması aynı' (-not $g4.sonraki_deneme -and [string]$g4.asama -eq 'plan' -and @($g4.gecmis | Where-Object { $_.olay -eq 'günlük hak sıfırlandı' }).Count -eq 1)
    $g2 = Gorev-Al '0902-codex-sinirdan-bekliyor'
    Dogrula 'Codex sınırından bekleyen iş Claude sıfırlanınca beklemeye devam eder' ([bool]$g2.sonraki_deneme)
    $g3 = Gorev-Al '0903-baska-nedenle-takildi'
    Dogrula 'başka nedenle takılan iş takılı kalır (Incident Manager sınıra takılmış olsa da)' ([string]$g3.asama -eq 'takildi')
    $g5 = Gorev-Al '0905-bitmis'
    Dogrula 'biten işe dokunulmaz' ([string]$g5.asama -eq 'tamam' -and [string]$g5.guncelleme -eq [string]$eskiZaman)
    Dogrula 'çıktı: sürdürülen ve beklemeyen işler, öbürleri yok' ($r.cikti -match 'Sürdürülüyor: #0901 ' -and $r.cikti -match 'Beklemeden yeniden denenecek: #0904 ' -and $r.cikti -notmatch '#0902|#0903|#0905')
    $gl = Get-ChildItem -LiteralPath (Join-Path $kum 'gunluk') -Filter '*.log' -File -ErrorAction SilentlyContinue | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }
    Dogrula 'günlüğe yazıldı' (($gl -join "`n") -match 'Günlük hak sıfırlandı \(kullanıcı\): claude 100 -> 0; kaldırılan kilitler: claude')

    Write-Host 'K2: -KotaSifirla hepsi'
    $r = Durum '-KotaSifirla hepsi'
    $s = Json-Al (Join-Path $durum 'sayaclar.json')
    Dogrula 'komut başarılı, bütün sayaçlar 0' ($r.kod -eq 0 -and [int]$s.claude -eq 0 -and [int]$s.codex -eq 0 -and [int]$s.gemini -eq 0) ("kod $($r.kod), codex $($s.codex), gemini $($s.gemini)")
    $kl = Kilit-Adlari
    Dogrula 'Codex sınır kilidi kalktı; giriş ve model kilitleri kaldı' ($kl -notcontains 'codex:sahte-codex' -and $kl -contains 'gemini' -and $kl -contains 'claude:sahte-model') ($kl -join ', ')
    Dogrula 'Codex sınırından bekleyen iş artık beklemez' (-not (Gorev-Al '0902-codex-sinirdan-bekliyor').sonraki_deneme)
    Dogrula 'çıktı: üç aracın satırı' (([regex]::Matches($r.cikti, 'günlük hakkı sıfırlandı')).Count -eq 3 -and $r.cikti -match 'Beklemeden yeniden denenecek: #0902 ')

    Write-Host 'K3: yineleme ve hatalı araç'
    $r = Durum '-KotaSifirla hepsi'
    Dogrula 'ikinci kez çalışınca da başarılı; duran iş yok' ($r.kod -eq 0 -and $r.cikti -match 'Sınır yüzünden duran iş yok\.')
    $r = Durum '-KotaSifirla yanlis'
    Dogrula 'bilinmeyen araç reddedilir' ($r.kod -ne 0 -and $r.cikti -match 'Bilinmeyen araç') ("kod $($r.kod)")

    Write-Host 'K4: panel ucu (ofis\ofis.ps1 > Eylem-KotaSifirla)'
    $ofisYol = Join-Path $Kaynak 'ofis\ofis.ps1'
    $ofisMetni = [IO.File]::ReadAllText($ofisYol, $bom)
    Dogrula 'POST /api/kota-sifirla yolu tanımlı' ($ofisMetni.Contains('''/api/kota-sifirla'' { $r = Eylem-KotaSifirla $v }'))
    $hata = $null; $agac = $null
    $agac = [System.Management.Automation.Language.Parser]::ParseFile($ofisYol, [ref]$null, [ref]$hata)
    foreach ($ad in @('Eylem-KotaSifirla', 'Metin-Alani', 'Ozellik')) {
        $f = $agac.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $ad }.GetNewClosure(), $true)
        if (-not $f) { throw "ofis.ps1 içinde $ad bulunamadı" }
        . ([scriptblock]::Create($f.Extent.Text))
    }
    function Betik-Calistir([string]$Betik, [string]$ArgMetni) { return [ordered]@{ basarili = $true; cikti = "$Betik $ArgMetni"; hata = '' } }
    $u = Eylem-KotaSifirla ([pscustomobject]@{ arac = ' Claude ' })
    Dogrula 'araç adı küçük harfe çevrilip durum.ps1 -KotaSifirla çağrılır' ($u.cikti -eq 'durum.ps1 -KotaSifirla claude') $u.cikti
    foreach ($kotu in @('yanlis', 'claude;x', '', 'claude codex')) {
        $m = ''; try { [void](Eylem-KotaSifirla ([pscustomobject]@{ arac = $kotu })) } catch { $m = $_.Exception.Message }
        Dogrula "geçersiz araç reddedilir: '$kotu'" ($m -match '^HTTP:400:') $m
    }
    $panel = [IO.File]::ReadAllText((Join-Path $Kaynak 'ofis\panel.html'), $bom)
    Dogrula 'panel: "Günlük hak" çubuklarında ve "Bugün" kartında ↺ düğmesi' ($panel -match "kotaDugmesi\(arac, 'enerji-sifirla'" -and $panel -match "kotaDugmesi\(arac, 's-sifirla'" -and $panel -match "api\('/api/kota-sifirla'")
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "Kum havuzu korundu: $kum" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
