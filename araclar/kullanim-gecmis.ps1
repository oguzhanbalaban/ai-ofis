<#
kullanim-gecmis.ps1 - Token / bağlam kaydı başlamadan önceki ajan çağrılarını (gorevler\*\ ve durum\sohbet\kayit\ altındaki
günlükler) bir kez durum\kullanim\kullanim-yyyyMM.jsonl dosyalarına aktarır; panelin Kullanım panosu geçmişi de gösterir.

  powershell -NoProfile -ExecutionPolicy Bypass -File araclar\kullanim-gecmis.ps1 [-Dene]

  Claude: *.out.txt (JSON sonuç: token toplamları; en büyük bağlam eski biçimde bilinmez)
  Codex : *.err.txt başlığındaki oturum kimliği -> %USERPROFILE%\.codex\sessions\...\rollout-*.jsonl (tam ölçüm)
  Kayıtlar "kaynak": "gecmis" alır. Canlı kayıtlardan eski günlükler aktarılır; dosya yeniden zaman sırasına dizilir.
  İkinci kez çalışmaz (durum\kullanim\gecmis-aktarildi.txt); -Dene yalnızca sayar, yazmaz.
#>
param([switch]$Dene)
$ErrorActionPreference = 'Stop'
$kokKlasor = Split-Path -Parent $PSScriptRoot
. (Join-Path $kokKlasor 'ortak.ps1')
Ayarlari-Yukle
if (-not (Test-Path -LiteralPath $YolKullanim)) { New-Item -ItemType Directory -Force $YolKullanim | Out-Null }
$isaret = Join-Path $YolKullanim 'gecmis-aktarildi.txt'
if ((Test-Path -LiteralPath $isaret) -and -not $Dene) { Write-Host "Geçmiş daha önce aktarılmış: $(Metin-Oku $isaret)"; exit 0 }

# Canlı kayıtların başladığı an: bundan eski günlükler aktarılır
$canliBas = Get-Date
foreach ($f in @(Get-ChildItem -LiteralPath $YolKullanim -Filter 'kullanim-*.jsonl' -File -ErrorAction SilentlyContinue)) {
    foreach ($s in [IO.File]::ReadAllLines($f.FullName, $Utf8)) { if ($s.Trim()) { try { $z = [datetime]($s | ConvertFrom-Json).zaman; if ($z -lt $canliBas) { $canliBas = $z } } catch {} } }
}
Write-Host "Canlı kayıt başlangıcı: $($canliBas.ToString('dd.MM.yyyy HH:mm:ss'))"

# Codex oturum dosyaları: kimlik -> yol
$ev = $env:CODEX_HOME; if (-not $ev) { $ev = Join-Path $env:USERPROFILE '.codex' }
$oturumlar = @{}
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $ev 'sessions') -Recurse -Filter 'rollout-*.jsonl' -File -ErrorAction SilentlyContinue)) {
    $m = [regex]::Match($f.Name, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$')
    if ($m.Success) { $oturumlar[$m.Groups[1].Value.ToLowerInvariant()] = $f.FullName }
}
Write-Host "Codex oturum dosyası: $($oturumlar.Count)"

function Rol-Bul([string]$Etiket, $G, [string]$Arac) {
    if ($Etiket -match '^inceleme-(.+)$') { return $Matches[1] }
    switch ($Etiket) {
        'plan' { return 'lider' } 'kabul' { return 'lider' } 'yonlendirme' { return 'lider' }
        'gelistirme' { return 'gelistirici' } 'denetim' { return 'denetci' } 'ise_alim' { return 'ik' } 'cozum' { return 'sorun-giderici' }
        'calisma' { if ($G -and $G.sorumlu) { return [string]$G.sorumlu }; return 'uzman' }
        'inceleme' { if ($G -and $G.inceleyen -and $G.inceleyen -ne 'yok') { return [string]$G.inceleyen }; return 'uzman' }
        'uygulama' { if ($G -and @('sistem', 'ag') -contains [string]$G.sorumlu) { return [string]$G.sorumlu }; return 'sistem' }
        'dogrulama' { if ($G -and @('sistem', 'ag') -contains [string]$G.destek) { return [string]$G.destek }; return 'ag' }
    }
    return $Etiket
}

$kayitlar = New-Object Collections.Generic.List[object]
$atlanan = 0
$kaynaklar = @()
foreach ($d in @(Get-ChildItem -LiteralPath $YolGorev -Directory -ErrorAction SilentlyContinue)) { $kaynaklar += [pscustomobject]@{ klasor = $d.FullName; gorev = $d.Name; rol = '' } }
$sk = Join-Path $YolDurum 'sohbet\kayit'
foreach ($d in @(Get-ChildItem -LiteralPath $sk -Directory -ErrorAction SilentlyContinue)) { $kaynaklar += [pscustomobject]@{ klasor = $d.FullName; gorev = ''; rol = $d.Name } }
foreach ($k in $kaynaklar) {
    $G = $null; if ($k.gorev) { $G = Json-Oku (Join-Path $k.klasor 'durum.json') }
    foreach ($f in @(Get-ChildItem -LiteralPath $k.klasor -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*-claude-*.out.txt' -or $_.Name -like '*-codex-*.err.txt' })) {
        if ($f.LastWriteTime -ge $canliBas) { $atlanan++; continue }
        $m = [regex]::Match($f.Name, '^(.+?)-(claude|codex)-(.+)\.(out|err)\.txt$')
        if (-not $m.Success) { continue }
        $etiket = $m.Groups[1].Value; $arac = $m.Groups[2].Value; $model = $m.Groups[3].Value
        $rol = $k.rol; if (-not $rol) { $rol = Rol-Bul $etiket $G $arac }
        $kul = $null; $basarili = $false; $sure = 0
        if ($arac -eq 'claude') {
            $c = Claude-Cikti-Coz (Metin-Oku $f.FullName)
            $kul = $c.kullanim
            if ($c.sonuc) { $basarili = (-not $c.sonuc.is_error -and $c.sonuc.subtype -eq 'success'); $sure = [int]([double]$c.sonuc.duration_ms / 1000) }
        } else {
            $sid = [regex]::Match((Bas-Oku $f.FullName 6144), '(?m)^session id:\s*([0-9a-fA-F-]{36})')
            $od = ''; if ($sid.Success) { $od = [string]$oturumlar[$sid.Groups[1].Value.ToLowerInvariant()] }
            $kul = Codex-Kullanim $f.FullName $od -Gecmis
            $son = $f.FullName -replace '\.err\.txt$', '.son.md'
            $basarili = (Test-Path -LiteralPath $son) -and ((Metin-Oku $son).Trim().Length -gt 0)
            $sure = [int]($f.LastWriteTime - $f.CreationTime).TotalSeconds
            if ($sure -lt 0 -or $sure -gt 86400) { $sure = 0 }
        }
        $kayit = [ordered]@{ zaman = $f.LastWriteTime.ToString('o'); gorev = $k.gorev; rol = $rol; etiket = $etiket; arac = $arac; model = $model; basarili = $basarili; sure_sn = $sure; istem_karakter = 0 }
        foreach ($a in @('giris', 'onbellek_okuma', 'onbellek_yazma', 'cikis', 'baglam_tepe', 'baglam_pencere', 'istek')) {
            $v = [long]0; if ($kul -and $kul.Contains($a)) { $v = Sayi $kul[$a] }
            $kayit[$a] = $v
        }
        $kayit.toplam = $kayit.giris + $kayit.onbellek_okuma + $kayit.onbellek_yazma + $kayit.cikis
        if ($kul -and $kul.Contains('toplam') -and (Sayi $kul['toplam']) -gt $kayit.toplam) { $kayit.toplam = Sayi $kul['toplam'] }
        if ($kul -and $kul.Contains('maliyet_usd') -and [double]$kul['maliyet_usd'] -gt 0) { $kayit.maliyet_usd = [Math]::Round([double]$kul['maliyet_usd'], 4) }
        $kayit.olcum = 'yok'; if ($kul -and $kul.Contains('olcum')) { $kayit.olcum = [string]$kul['olcum'] }
        $kayit.kaynak = 'gecmis'
        $kayitlar.Add([pscustomobject]$kayit)
    }
}
$olcumlu = @($kayitlar | Where-Object { $_.toplam -gt 0 }).Count
$toplam = ($kayitlar | Measure-Object -Property toplam -Sum).Sum
Write-Host ("Bulunan geçmiş çağrı: {0} (token ölçülen {1}, toplam {2:N0} token); canlı kayıttan yeni olduğu için atlanan: {3}" -f $kayitlar.Count, $olcumlu, $toplam, $atlanan)
foreach ($gr in ($kayitlar | Group-Object rol | Sort-Object Count -Descending)) { Write-Host ("  {0,-18} {1,4} çağrı  {2,14:N0} token" -f $gr.Name, $gr.Count, ($gr.Group | Measure-Object -Property toplam -Sum).Sum) }
if ($Dene) { Write-Host '(-Dene: hiçbir şey yazılmadı)'; exit 0 }

# Ay dosyalarına mevcut canlı kayıtlarla birlikte zaman sırasında yaz
foreach ($ay in ($kayitlar | Group-Object { ([datetime]$_.zaman).ToString('yyyyMM') })) {
    $yol = Join-Path $YolKullanim ('kullanim-{0}.jsonl' -f $ay.Name)
    $satirlar = New-Object Collections.Generic.List[object]
    if (Test-Path -LiteralPath $yol) { foreach ($s in [IO.File]::ReadAllLines($yol, $Utf8)) { if ($s.Trim()) { $satirlar.Add([pscustomobject]@{ z = [datetime]($s | ConvertFrom-Json).zaman; s = $s.Trim() }) } } }
    foreach ($r in $ay.Group) { $satirlar.Add([pscustomobject]@{ z = [datetime]$r.zaman; s = ($r | ConvertTo-Json -Compress) }) }
    $metin = (($satirlar | Sort-Object z | ForEach-Object { $_.s }) -join "`n") + "`n"
    Metin-Yaz $yol $metin
    Write-Host "Yazıldı: $yol ($($satirlar.Count) satır)"
}
Metin-Yaz $isaret ("{0}: {1} geçmiş çağrı aktarıldı (canlı kayıt başlangıcı {2})`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm'), $kayitlar.Count, $canliBas.ToString('dd.MM.yyyy HH:mm:ss'))
