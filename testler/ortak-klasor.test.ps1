<#
ortak-klasor.test.ps1 - Ortak yazılabilir klasörleri sınar (ayarlar.json > ortak_klasorler): yazma adımlarında Claude / Codex --add-dir,
Gemini --include-directories; istemde "Ortak klasörler" notu ve işin numarası; okuma adımları, tam yetkili roller ve ayarı olmayan ofis
eskisi gibi çalışır. Çevrimdışıdır: gerçek Claude / Codex / Gemini çağrılmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\ortak-klasor.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-ortak-klasor-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
Copy-Item -LiteralPath (Join-Path $Kaynak 'kadro.json') -Destination $kum
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
$ayarJ.roller = [pscustomobject]@{ lider = @(& $s 'sahte-yonetici'); gelistirici = @(& $s 'sahte-gelistirici'); sistem = @(& $s 'sahte-sistem'); urun = @(& $s 'sahte-urun') }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
$ayarJ.altyapi.makineler = @()
$ayarJ.altyapi.vmrun = ''
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
$ayarJ | Add-Member -Force -NotePropertyName ortak_klasorler -NotePropertyValue ([pscustomobject]@{ yollar = @('programlar', 'olmayan-klasor') })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), (([pscustomobject]@{ projeler = @() }) | ConvertTo-Json -Depth 5), $bom)
# Sahte ajan: argümanları ve çalışma dizinini kaydeder, sabit bir yanıt verir
[IO.File]::WriteAllText($sahteAjan, (@(
    '@echo off', 'set D=%~dp0', '>> "%D%cagrilar.log" echo CD=%CD% ARG=%*', 'type "%D%sahte-cikti.txt"', 'exit /b 0'
) -join "`r`n") + "`r`n", $ascii)
function Akis([string]$Metin) {
    $satirlar = @(
        ([ordered]@{ type = 'system'; subtype = 'init' } | ConvertTo-Json -Compress),
        ([ordered]@{ type = 'result'; subtype = 'success'; is_error = $false; num_turns = 1; result = $Metin; usage = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 10; cache_creation_input_tokens = 0; output_tokens = 5 } } | ConvertTo-Json -Compress -Depth 5))
    return (($satirlar -join "`n") + "`n")
}
[IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), (Akis 'tamam'), $utf8)

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
function Cagrilar { $f = Join-Path $kum 'cagrilar.log'; if (Test-Path -LiteralPath $f) { return [IO.File]::ReadAllText($f) }; return '' }
function Cagrilari-Sil { Remove-Item -LiteralPath (Join-Path $kum 'cagrilar.log') -Force -ErrorAction SilentlyContinue }
function Ilk-Satir([string]$Metin) { return (($Metin -split "`n") | Select-Object -First 1) }
function Son-Istem([string]$Klasor, [string]$Desen) { $f = Get-ChildItem -LiteralPath $Klasor -Filter $Desen -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { return [IO.File]::ReadAllText($f.FullName) }; return '' }

try {
    $prog = Join-Path $kum 'programlar'
    New-Item -ItemType Directory -Force $prog | Out-Null
    $progT = (Resolve-Path -LiteralPath $prog).Path
    $wt = Join-Path $kum 'calisma-0901'; New-Item -ItemType Directory -Force $wt | Out-Null
    $kayit = Join-Path $kum 'kayit-0901'
    $script:AktifGorev = '0901-ortak-test'

    Write-Host ''; Write-Host 'O1: ortak klasörlerin çözülmesi'
    $ok = @(Ortak-Klasorler)
    Dogrula 'göreli yol katın köküne göre çözülür; olmayan klasör atlanır' ($ok.Count -eq 1 -and $ok[0] -eq $progT) ($ok -join ';')
    $mutlak = Join-Path $kum 'mutlak-ortak'; New-Item -ItemType Directory -Force $mutlak | Out-Null
    $Ayar.ortak_klasorler.yollar = @('programlar', $mutlak)
    $ok = @(Ortak-Klasorler)
    Dogrula 'mutlak yol da kabul edilir' ($ok.Count -eq 2 -and $ok -contains (Resolve-Path -LiteralPath $mutlak).Path) ($ok -join ';')
    $Ayar.ortak_klasorler.yollar = @('programlar')

    Write-Host ''; Write-Host 'O2: yazma adımı (Claude) ortak klasörü --add-dir ile alır'
    Cagrilari-Sil
    $r = Ajan-Cagir -Rol 'gelistirici' -Istem 'Bir şey yap.' -Klasor $wt -KayitKlasoru $kayit -Etiket 'gelistirme' -Yazabilir
    $log = Cagrilar
    Dogrula 'çağrı başarılı' ([bool]$r.basarili) ([string]$r.hata)
    Dogrula 'acceptEdits + --add-dir ortak klasör' ($log -match '--permission-mode acceptEdits' -and $log -match ('--add-dir "' + [regex]::Escape($progT) + '"')) (Ilk-Satir $log)
    Dogrula 'çalışma dizini işin klasörü olarak kalır' ($log -match [regex]::Escape("CD=$wt"))
    $ist = Son-Istem $kayit 'gelistirme-*.istem.md'
    Dogrula 'istemde "Ortak klasörler" notu, klasör yolu ve işin numarası' ($ist -match '## Ortak klasörler' -and $ist.Contains($progT) -and $ist -match 'Bu işin numarası: #0901')

    Write-Host ''; Write-Host 'O3: aynı klasör iki kez verilmez'
    Cagrilari-Sil
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'Yap.' -Klasor $wt -KayitKlasoru $kayit -Etiket 'gelistirmeek' -Yazabilir -EkKlasorler @($progT))
    Dogrula 'tek --add-dir' (([regex]::Matches((Cagrilar), '--add-dir')).Count -eq 1) (Ilk-Satir (Cagrilar))

    Write-Host ''; Write-Host 'O4: okuma adımı ve tam yetkili rol değişmez'
    Cagrilari-Sil
    [void](Ajan-Cagir -Rol 'lider' -Istem 'Oku.' -Klasor $wt -KayitKlasoru $kayit -Etiket 'plan')
    Dogrula 'okuma adımı: dontAsk + Read,Glob,Grep, --add-dir yok' ((Cagrilar) -match '--tools Read,Glob,Grep ' -and (Cagrilar) -match '--permission-mode dontAsk' -and (Cagrilar) -notmatch '--add-dir') (Ilk-Satir (Cagrilar))
    Dogrula 'okuma adımı isteminde "Ortak klasörler" notu yok' ((Son-Istem $kayit 'plan-*.istem.md') -notmatch '## Ortak klasörler')
    Cagrilari-Sil
    [void](Ajan-Cagir -Rol 'sistem' -Istem 'Kur.' -Klasor $wt -KayitKlasoru $kayit -Etiket 'altyapi' -TamYetki)
    Dogrula 'tam yetkili rol: bypassPermissions, --add-dir gerekmez' ((Cagrilar) -match 'bypassPermissions' -and (Cagrilar) -notmatch '--add-dir') (Ilk-Satir (Cagrilar))

    Write-Host ''; Write-Host 'O5: Codex ve Gemini'
    $script:CodexYolu = $sahteAjan
    function Gemini-Exe { return $sahteAjan }
    $istY = Join-Path $kum 'istem.txt'; [IO.File]::WriteAllText($istY, 'x', $utf8)
    $cx = [pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }
    $gm = [pscustomobject]@{ arac = 'gemini'; model = 'sahte-gemini' }
    Cagrilari-Sil
    [void](Codex-Calistir $cx $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $wt $true $false '' @($progT))
    Dogrula 'Codex yazma: workspace-write + -C işin klasörü + --add-dir ortak klasör' ((Cagrilar) -match '-s workspace-write' -and (Cagrilar) -match ('-C "' + [regex]::Escape($wt) + '" --add-dir "' + [regex]::Escape($progT) + '"')) (Ilk-Satir (Cagrilar))
    Cagrilari-Sil
    [void](Codex-Calistir $cx $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $wt $false $false '' @($progT))
    Dogrula 'Codex okuma: read-only, --add-dir yok' ((Cagrilar) -match '-s read-only' -and (Cagrilar) -notmatch '--add-dir') (Ilk-Satir (Cagrilar))
    Cagrilari-Sil
    [void](Codex-Calistir $cx $istY (Join-Path $kum 'c.out') (Join-Path $kum 'c.err') (Join-Path $kum 'c.son') $wt $true $true '' @($progT))
    Dogrula 'Codex tam yetki: danger-full-access, --add-dir yok' ((Cagrilar) -match 'danger-full-access' -and (Cagrilar) -notmatch '--add-dir') (Ilk-Satir (Cagrilar))
    Cagrilari-Sil
    [void](Gemini-Calistir $gm $istY (Join-Path $kum 'g.out') (Join-Path $kum 'g.err') $wt $true $false '' @($progT))
    Dogrula 'Gemini yazma: auto_edit + --include-directories ortak klasör' ((Cagrilar) -match '--approval-mode auto_edit' -and (Cagrilar) -match '--include-directories' -and (Cagrilar).Contains($progT)) (Ilk-Satir (Cagrilar))
    Cagrilari-Sil
    [void](Gemini-Calistir $gm $istY (Join-Path $kum 'g.out') (Join-Path $kum 'g.err') $wt $false $false '' @($progT))
    Dogrula 'Gemini okuma: plan, --include-directories yok' ((Cagrilar) -match '--approval-mode plan' -and (Cagrilar) -notmatch '--include-directories') (Ilk-Satir (Cagrilar))

    Write-Host ''; Write-Host 'O6: ayarı olmayan ofis eskisi gibi çalışır'
    $Ayar.PSObject.Properties.Remove('ortak_klasorler')
    Dogrula 'ayar yoksa ortak klasör yok' (@(Ortak-Klasorler).Count -eq 0)
    Cagrilari-Sil
    [void](Ajan-Cagir -Rol 'gelistirici' -Istem 'Yap.' -Klasor $wt -KayitKlasoru $kayit -Etiket 'gelistirmeyok' -Yazabilir)
    Dogrula 'yazma adımı: acceptEdits, --add-dir yok, not yok' ((Cagrilar) -match '--permission-mode acceptEdits' -and (Cagrilar) -notmatch '--add-dir' -and (Son-Istem $kayit 'gelistirmeyok-*.istem.md') -notmatch '## Ortak klasörler') (Ilk-Satir (Cagrilar))
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
