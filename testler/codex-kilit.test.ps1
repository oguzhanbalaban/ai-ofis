<#
codex-kilit.test.ps1 - Codex kullanım sınırı kilidini sınar: hata metnindeki "try again at …" / "try again in …" açılış saati okunur
(Codex-Limit-Bitis), kilit o saate (+2 dk) kadar sürer; saat yoksa, geçmişteyse ya da 8 günden uzaksa eski davranış (60 dk) kalır.
Çevrimdışıdır: gerçek Codex çağrılmaz, sahte codex hata yazıp çıkar.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\codex-kilit.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-codex-kilit-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"
Remove-Item env:AIEKIP_KAT -ErrorAction SilentlyContinue

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
Copy-Item -LiteralPath (Join-Path $Kaynak 'kadro.json') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$ayarJ.gunluk_sinir = [pscustomobject]@{ claude = 100; codex = 100; gemini = 40 }
$ayarJ.zaman_asimi_dk.codex = 2
$ayarJ.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @() }) | ConvertTo-Json -Depth 5), $bom)
# Sahte codex: codex-hata.txt'yi stderr'e yazar, kod 1 ile çıkar (son mesaj dosyası yazılmaz)
$sahteCodex = Join-Path $kum 'sahte-codex.cmd'
[IO.File]::WriteAllText($sahteCodex, (@('@echo off', 'set D=%~dp0', 'type "%D%codex-hata.txt" 1>&2', 'exit /b 1') -join "`r`n") + "`r`n", $ascii)

. (Join-Path $kum 'ortak.ps1')
if ($Kok -ne $kum) { throw "Betikler kum havuzunu değil $Kok klasörünü kullanıyor; test durduruldu" }
Ayarlari-Yukle
$script:CodexYolu = $sahteCodex

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Goster($T) { if ($null -eq $T) { return 'null' }; return ([datetime]$T).ToString('yyyy-MM-dd HH:mm') }
# Codex'in yazdığı biçim: "Nov 21st, 2026 2:36 AM" (İngilizce ay, sıra eki, 12 saat)
function Codex-Saati([datetime]$T) {
    $ek = 'th'; if ($T.Day % 100 -lt 11 -or $T.Day % 100 -gt 13) { switch ($T.Day % 10) { 1 { $ek = 'st' } 2 { $ek = 'nd' } 3 { $ek = 'rd' } } }
    $ci = [Globalization.CultureInfo]::InvariantCulture
    return ('{0} {1}{2}, {3} {4}' -f $T.ToString('MMM', $ci), $T.Day, $ek, $T.Year, $T.ToString('h:mm tt', $ci))
}
function Codex-Hata([string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum 'codex-hata.txt'), $Metin + "`r`n", $utf8) }
function Codex-Dene {
    $istY = Join-Path $kum 'istem.txt'; [IO.File]::WriteAllText($istY, 'x', $utf8)
    return (Codex-Calistir ([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }) $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $kum $false $false)
}
function Kilit-Al { $k = Kilit-Oku; if ($k.PSObject.Properties['codex:sahte-codex']) { return $k.'codex:sahte-codex' }; return $null }
function Kilit-Temizle { Json-Yaz (New-Object psobject) (Join-Path $YolDurum 'kilitler.json') }
function Dakika-Farki([datetime]$A, [datetime]$B) { return [Math]::Abs(($A - $B).TotalMinutes) }

try {
    Write-Host 'C1: Codex-Limit-Bitis (hata metninden açılış saati, 2 dk pay)'
    $an = [datetime]::new(2026, 11, 20, 23, 45, 51)
    $gercek = "ERROR: You" + [char]0x2019 + "ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/settings/usage to purchase more credits or try again at Nov 21st, 2026 2:36 AM. 2026-11-20T20:45:50.251267Z ERROR codex_core::session: failed to record rollout items: thread 01a1faa7"
    $durumlar = @(
        @('günlükteki gerçek hata (20.11 23:45)', $gercek, '2026-11-21 02:38'),
        @('tarihli, AM', 'try again at Nov 21st, 2026 2:36 AM.', '2026-11-21 02:38'),
        @('yalnız saat, geçmişte kaldıysa ertesi gün', 'or try again at 2:36 AM.', '2026-11-21 02:38'),
        @('yalnız saat, bugün ileride', 'try again at 11:50 PM', '2026-11-20 23:52'),
        @('öğlen 12 PM', 'try again at Nov 25th, 2026 12:05 PM', '2026-11-25 12:07'),
        @('gece yarısı 12 AM', 'try again at Nov 22nd, 2026 12:30 AM', '2026-11-22 00:32'),
        @('a.m. yazımı', 'try again at Nov 23rd, 2026 9:15 a.m.', '2026-11-23 09:17'),
        @('24 saat', 'try again at 14:36', '2026-11-21 14:38'),
        @('yılsız tarih', 'try again at Nov 24th 1:00 AM', '2026-11-24 01:02'),
        @('"try again in" saat + dakika', 'Try again in 2 hours 5 minutes.', '2026-11-21 01:52'),
        @('"try again in" gün + saat', 'try again in 3 days 4 hours', '2026-11-24 03:47'),
        @('"try again in ~45 min"', 'Rate limit reached; try again in ~45 min', '2026-11-21 00:32'),
        @('geçmiş tarih yok sayılır', 'try again at Nov 20th, 2026 1:00 AM', 'null'),
        @('8 günden uzak tarih yok sayılır', 'try again at Jan 5th, 2027 1:00 AM', 'null'),
        @('geçersiz tarih (30 Şubat) hata vermez', 'try again at Feb 30th, 2027 1:00 AM', 'null'),
        @('saat yoksa null', 'ERROR: You have hit your usage limit.', 'null'),
        @('boş metin null', '', 'null')
    )
    foreach ($d in $durumlar) {
        $s = $null; $h = ''
        try { $s = Codex-Limit-Bitis $d[1] $an } catch { $h = $_.Exception.Message }
        Dogrula $d[0] ((-not $h) -and (Goster $s) -eq $d[2]) ("beklenen $($d[2]), çıkan $(Goster $s)$(if ($h) { "; hata: $h" })")
    }

    Write-Host 'C2: Codex-Calistir kilidi hatadaki saate göre koyar'
    Kilit-Temizle
    $hedef = (Get-Date).AddHours(3).AddMinutes(17); $hedef = $hedef.AddSeconds(-$hedef.Second).AddMilliseconds(-$hedef.Millisecond)
    Codex-Hata ("ERROR: You've hit your usage limit. Upgrade to Pro, or try again at {0}." -f (Codex-Saati $hedef))
    $r = Codex-Dene
    Dogrula 'çağrı başarısız döner' (-not $r.basarili) $r.hata
    $k = Kilit-Al
    Dogrula 'kilit konuldu, neden "Codex kullanım sınırı"' ($k -and [string]$k.neden -eq 'Codex kullanım sınırı') ([string]$k.neden)
    $beklenen = $hedef.AddMinutes(2)
    Dogrula 'kilit hatadaki saat + 2 dk' ($k -and (Dakika-Farki ([datetime]$k.bitis) $beklenen) -lt 0.1) ("beklenen $(Goster $beklenen), kilit $(Goster $k.bitis)")
    $u = Arac-Uygun ([pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' })
    Dogrula 'Arac-Uygun kilidin saatini gösterir' ([string]$u -eq ("Codex kullanım sınırı ({0}'e kadar)" -f $beklenen.ToString('HH:mm'))) ([string]$u)

    Write-Host 'C3: saat yoksa eski davranış (60 dk)'
    Kilit-Temizle
    Codex-Hata 'ERROR: You have hit your usage limit. Upgrade to Pro.'
    $once = Get-Date
    [void](Codex-Dene)
    $k = Kilit-Al
    Dogrula 'kilit yaklaşık 60 dk' ($k -and (Dakika-Farki ([datetime]$k.bitis) $once.AddMinutes(60)) -lt 2) ("kilit $(Goster $k.bitis)")

    Write-Host 'C4: sınır dışı hatalar kilit koymaz'
    Kilit-Temizle
    Codex-Hata 'ERROR: something else went wrong; try again at 2:36 AM'
    [void](Codex-Dene)
    Dogrula 'kullanım sınırı olmayan hatada kilit yok (saat yazsa da)' (-not (Kilit-Al))

    Write-Host 'C5: kaynak'
    $metin = [IO.File]::ReadAllText((Join-Path $Kaynak 'ortak.ps1'), $bom)
    Dogrula 'sabit "AddMinutes(60) ''Codex kullanım sınırı''" kalmadı' (-not $metin.Contains("(Get-Date).AddMinutes(60) 'Codex kullanım sınırı'"))
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
