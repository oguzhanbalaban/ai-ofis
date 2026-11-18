<#
ofis-duman.test.ps1 - Ofis kodunun duman testi (kendi üzerinde geliştirmede kontrol aşamasında ilk koşan test): bütün .ps1 dosyaları
ayrışıyor ve UTF-8 BOM'lu mu, JSON'lar geçerli mi, panel sayfalarının satır içi betikleri (node varsa) sözdizimi açısından doğru mu,
motor her ekip katında (kum havuzu kopyasında) yükleniyor mu. Çevrimdışıdır; canlı ofise dokunmaz.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\ofis-duman.test.ps1 [-Kaynak <betik klasörü>]
#>
param([string]$Kaynak = '')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
$kum = Join-Path $env:TEMP ('ai-ekip-duman-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    Write-Host "Kaynak: $Kaynak"
    $betikler = @(Get-ChildItem -LiteralPath $Kaynak -Filter '*.ps1' -File) + @(Get-ChildItem -LiteralPath (Join-Path $Kaynak 'ofis') -Filter '*.ps1' -File -ErrorAction SilentlyContinue) +
        @(Get-ChildItem -LiteralPath (Join-Path $Kaynak 'testler') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
    $hatali = @(); $bomsuz = @()
    foreach ($f in $betikler) {
        $tok = $null; $hata = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$hata)
        if (@($hata).Count) { $hatali += "$($f.Name):$(@($hata)[0].Extent.StartLineNumber) $(@($hata)[0].Message)" }
        $b = [IO.File]::ReadAllBytes($f.FullName)
        if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { $bomsuz += $f.Name }
    }
    Dogrula "$($betikler.Count) betik ayrışıyor" ($hatali.Count -eq 0) ($hatali -join ' | ')
    Dogrula 'bütün betikler UTF-8 BOM ile' ($bomsuz.Count -eq 0) ($bomsuz -join ', ')
    $jsonlar = @('katlar.json', 'ayarlar.json', 'kadro.json', 'projeler.json') | ForEach-Object { Join-Path $Kaynak $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $katKlasoru = Join-Path $Kaynak 'katlar'
    # Katların ayar dosyaları (uygulama katlarının kendi JSON'ları, ör. package-lock, kapsam dışı)
    if (Test-Path -LiteralPath $katKlasoru) { foreach ($kd in @(Get-ChildItem -LiteralPath $katKlasoru -Directory)) { foreach ($ad in @('ayarlar.json', 'kadro.json', 'projeler.json')) { $y = Join-Path $kd.FullName $ad; if (Test-Path -LiteralPath $y) { $jsonlar += $y } } } }
    $bozuk = @(); foreach ($j in $jsonlar) { try { $null = [IO.File]::ReadAllText($j) | ConvertFrom-Json } catch { $bozuk += $j.Substring($Kaynak.Length + 1) } }
    Dogrula "$(@($jsonlar).Count) JSON geçerli" ($bozuk.Count -eq 0) ($bozuk -join ', ')
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $sayfalar = @(Get-ChildItem -LiteralPath (Join-Path $Kaynak 'ofis') -Filter '*.html' -File -ErrorAction SilentlyContinue)
    if ($node) {
        $kotu = @(); $n = 0
        foreach ($h in $sayfalar) {
            $i = 0
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($h.FullName), '(?s)<script[^>]*>(.*?)</script>')) {
                $i++; $n++; $js = Join-Path $env:TEMP ("duman-{0}-{1}-{2}.js" -f $PID, $h.BaseName, $i)
                [IO.File]::WriteAllText($js, $m.Groups[1].Value, (New-Object Text.UTF8Encoding $false))
                $c = & $node.Source --check $js 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { $kotu += "$($h.Name) #$($i): $(($c -split "`n" | Where-Object { $_ -match 'Error' } | Select-Object -First 1))" }
                Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue
            }
        }
        Dogrula "$($sayfalar.Count) panel sayfasının $n satır içi betiği sözdizimi açısından doğru" ($kotu.Count -eq 0) ($kotu -join ' | ')
    } else { Write-Host '  [ATLANDI] node.exe yok: sayfa betikleri denetlenmedi' }
    # Motor her ekip katında yükleniyor mu (kum havuzu kopyası; görev / durum klasörleri oraya açılır)
    New-Item -ItemType Directory -Force $kum | Out-Null
    Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
    Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
    foreach ($f in @('ayarlar.json', 'kadro.json', 'projeler.json', 'katlar.json')) { if (Test-Path -LiteralPath (Join-Path $Kaynak $f)) { Copy-Item -LiteralPath (Join-Path $Kaynak $f) -Destination $kum } }
    $katIdleri = @('ana')
    if (Test-Path -LiteralPath (Join-Path $kum 'katlar.json')) {
        $kj = [IO.File]::ReadAllText((Join-Path $kum 'katlar.json')) | ConvertFrom-Json
        foreach ($k in @($kj.katlar | Where-Object { $_ -and [string]$_.id -ne 'ana' -and [string]$_.tur -ne 'uygulama' -and [string]$_.kok -and [string]$_.kok -notmatch ':' })) {
            $kk = Join-Path $Kaynak ([string]$k.kok)
            if (-not (Test-Path -LiteralPath (Join-Path $kk 'kadro.json'))) { continue }
            $hk = Join-Path $kum ([string]$k.kok); New-Item -ItemType Directory -Force $hk | Out-Null
            foreach ($f in @('ayarlar.json', 'kadro.json', 'projeler.json')) { if (Test-Path -LiteralPath (Join-Path $kk $f)) { Copy-Item -LiteralPath (Join-Path $kk $f) -Destination $hk } }
            if (Test-Path -LiteralPath (Join-Path $kk 'istemler')) { Copy-Item -Recurse -LiteralPath (Join-Path $kk 'istemler') -Destination $hk }
            $katIdleri += [string]$k.id
        }
    }
    # Kum havuzundaki betikler canlı döngünün kilitlerine dokunmasın
    foreach ($f in @(Get-ChildItem -LiteralPath $kum -Filter '*.ps1' -File)) { $t = [IO.File]::ReadAllText($f.FullName); $y = $t.Replace('Local\AIEkip', 'Local\AIEkipDuman'); if ($y -cne $t) { [IO.File]::WriteAllText($f.FullName, $y, (New-Object Text.UTF8Encoding $true)) } }
    $deneme = Join-Path $kum 'yukle.ps1'
    [IO.File]::WriteAllText($deneme, "`$ErrorActionPreference = 'Stop'`r`n. (Join-Path `$PSScriptRoot 'ortak.ps1')`r`n. (Join-Path `$PSScriptRoot 'rapor.ps1')`r`n. (Join-Path `$PSScriptRoot 'ekip.ps1')`r`nAyarlari-Yukle`r`nKadro-Rolleri-Yukle`r`n'YUKLENDI ' + `$KatKimligi`r`n", (New-Object Text.UTF8Encoding $true))
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($id in $katIdleri) {
        $env:AIEKIP_KAT = $(if ($id -eq 'ana') { '' } else { $id })
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $c = & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $deneme 2>&1 | Out-String } finally { $ErrorActionPreference = $eap }
        $env:AIEKIP_KAT = ''
        Dogrula "motor '$id' katında yükleniyor" ($c -match "YUKLENDI $([regex]::Escape($id))") ($(if ($c -notmatch 'YUKLENDI') { ($c.Trim() -split "`n" | Select-Object -First 2) -join ' ' } else { '' }))
    }
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    $env:AIEKIP_KAT = ''
    Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
