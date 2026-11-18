<#
kendini.ps1 - Ofisin kendi kendini geliştirmesi. ekip.ps1 dot-source eder. Yalnızca fonksiyon tanımları.

Yol (ayna + denetimli canlıya alma):
  * Ofisin kodu (bütün katlar: motor, panel, istemler, testler, katların istem / bilgi / araçları) bir AYNA git deposunda tutulur
    (varsayılan: ofis klasörünün yanında "ai-ekip-kaynak"). Canlı klasör git değildir; ayna canlının kopyasıdır.
  * Ayna projeler.json'da "ai-ekip-ofis" adıyla (kendi: true) kayıtlıdır. Ofisle ilgili işleri Engineering Manager bu projeye verir;
    ekip olağan yazılım akışıyla çalışır: görev dalı ekip/<no>, çalışma ağacı calisma\<no> (canlıya dokunulmaz), kontrol aşamasında
    testler kum havuzlarında koşar, QA / Code Reviewer / onay kapısı.
  * Görev başlamadan ayna canlıyla eşitlenir (Ofis-Kaynagi-Esitle): kullanıcının ya da başka bir yolun canlıda yaptığı değişiklik
    önce aynaya commit edilir, iş güncel kod üzerinde yapılır.
  * Commit'ten sonra aşama "canliya_al" (Adim-CanliyaAl): dal aynanın main'ine birleştirilir; değişen dosyalar (yalnızca canlıya alma
    kapsamı: ayarlar / kadro / projeler JSON'ları hariç, onlar çalışırken değişir) yedeklenip canlıya kopyalanır; doğrulama: bütün
    betikler ayrıştırılır, her kat ayrı süreçte yüklenir, panel değiştiyse sunucu yeniden başlatılıp yanıt ve sayfa betikleri denetlenir.
    Doğrulama geçmezse canlı yedekten geri yüklenir, ayna eski haline döner, görev takılır. Döngü yeni kodu bir sonraki turda yükler.
  * Güvenlik ağı: canlıya almadan sonraki 60 dakika içinde döngü üst üste 3 kez hata verirse son canlıya alma kendiliğinden geri alınır.
    Kullanıcı son canlıya almayı panelden ya da durum.ps1 -GeriAl <no> ile geri alabilir.
Ayar: ayarlar.json > kendini_gelistirme { etkin, otomatik, kaynak_deposu, proje_adi, dogrulama }.
#>

function Kendini-Ayari {
    $s = [ordered]@{ etkin = $true; otomatik = $true; kaynak_deposu = ''; proje_adi = 'ai-ekip-ofis'; guvenlik_agi_dk = 60
        dogrulama = @('powershell -NoProfile -ExecutionPolicy Bypass -File testler\ofis-duman.test.ps1', 'powershell -NoProfile -ExecutionPolicy Bypass -File testler\katlar.test.ps1',
            'powershell -NoProfile -ExecutionPolicy Bypass -File testler\planlama-katmani.test.ps1', 'powershell -NoProfile -ExecutionPolicy Bypass -File testler\yardimlasma.test.ps1') }
    if ($Ayar -and $Ayar.kendini_gelistirme) { foreach ($p in $Ayar.kendini_gelistirme.PSObject.Properties) { if ($s.Contains($p.Name) -and $null -ne $p.Value) { $s[$p.Name] = $p.Value } } }
    if (-not ([string]$s.kaynak_deposu).Trim()) { $s.kaynak_deposu = Join-Path (Split-Path -Parent $KodKok) ((Split-Path -Leaf $KodKok) + '-kaynak') }
    return [pscustomobject]$s
}
function Kendi-Projesi-mi($G) {
    if (-not $G -or -not $G.proje) { return $false }
    $p = Proje-Bul ([string]$G.proje)
    return [bool]($p -and $p.kendi)
}

# ---------------------------------------------------------------- kapsam
# Aynada tutulan dosyalar (testler ayarlara da ihtiyaç duyduğu için JSON'lar dahil) ve canlıya alınanlar (JSON'lar hariç)
$script:AynaJsonlari = @('ayarlar.json', 'kadro.json', 'projeler.json')
function Kapsam-Dosyalari([string]$Taban) {
    $l = New-Object Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Taban)) { return , $l }
    $ekle = { param($klasor, $desen, $alt)
        $k = $Taban; if ($klasor) { $k = Join-Path $Taban $klasor }
        if (-not (Test-Path -LiteralPath $k)) { return }
        $ff = @(Get-ChildItem -LiteralPath $k -File -Filter $desen -Recurse:$alt -ErrorAction SilentlyContinue)
        foreach ($f in $ff) {
            $g = $f.FullName.Substring($Taban.TrimEnd('\').Length + 1)
            if ($g -match '(^|\\)(__pycache__|node_modules|\.venv[^\\]*)(\\|$)' -or $f.Name -match '\.(bak|tmp|pyc|log)$') { continue }
            $l.Add($g)
        }
    }
    foreach ($d in @(@('', '*.ps1', $false), @('', 'katlar.json', $false), @('', 'BENIOKU.md', $false), @('ofis', '*.ps1', $false), @('ofis', '*.html', $false),
            @('istemler', '*.md', $true), @('testler', '*.ps1', $false), @('araclar', '*.ps1', $true), @('araclar', '*.py', $true), @('danisman', 'CLAUDE.md', $false))) { & $ekle $d[0] $d[1] $d[2] }
    foreach ($j in $AynaJsonlari) { if (Test-Path -LiteralPath (Join-Path $Taban $j)) { $l.Add($j) } }
    $katlar = Join-Path $Taban 'katlar'
    if (Test-Path -LiteralPath $katlar) {
        foreach ($kd in @(Get-ChildItem -LiteralPath $katlar -Directory -ErrorAction SilentlyContinue)) {
            $r = "katlar\$($kd.Name)"
            foreach ($d in @(@("$r\istemler", '*.md'), @("$r\bilgi", '*'), @("$r\araclar", '*'))) { & $ekle $d[0] $d[1] $true }
            foreach ($j in $AynaJsonlari) { if (Test-Path -LiteralPath (Join-Path $kd.FullName $j)) { $l.Add("$r\$j") } }
        }
    }
    return , $l
}
function Canliya-Alinir-mi([string]$Goreli) {
    $g = $Goreli -replace '/', '\'
    if ($AynaJsonlari -contains (Split-Path -Leaf $g) -and ($g -notmatch '\\' -or $g -match '^katlar\\[^\\]+\\[^\\]+$')) { return $false }
    if ($g -match '^(CLAUDE|AGENTS|GEMINI)\.md$' -or $g -eq '.gitignore') { return $false }
    if ($g -match '^(ofis|istemler|testler|araclar|danisman)\\' -or $g -match '^[^\\]+\.(ps1)$' -or $g -in @('katlar.json', 'BENIOKU.md')) { return $true }
    return ($g -match '^katlar\\[^\\]+\\(istemler|bilgi|araclar)\\')
}
function Dosya-Ozeti([string]$Yol) {
    $fs = [IO.File]::OpenRead($Yol)
    try { return ([BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash($fs))) } finally { $fs.Dispose() }
}

# ---------------------------------------------------------------- ayna deposu
function Ayna-Git([string[]]$Arg, [switch]$Sessiz) { $k = (Kendini-Ayari).kaynak_deposu; return (Git-Calistir $k (@('-c', 'user.name=AI Ekip', '-c', 'user.email=ai-ekip@localhost') + $Arg) -Sessiz:$Sessiz) }
function Ayna-Rehberi-Yaz([string]$Ayna) {
    $r = Metin-Oku (Join-Path $YolIstem 'ofis-gelistirme.md')
    if (-not $r) { return }
    $r = $r.Replace('{AYNA}', $Ayna).Replace('{CANLI}', $KodKok)
    foreach ($ad in @('CLAUDE.md', 'AGENTS.md', 'GEMINI.md')) {
        $y = Join-Path $Ayna $ad
        if ((Metin-Oku $y) -cne $r) { [IO.File]::WriteAllText($y, $r, $Utf8) }
    }
}
# Canlıdaki kapsam dosyalarını aynanın main'ine yansıtır ve commit eder. Döner: '' ya da hata metni
function Ofis-Kaynagi-Esitle([string]$Neden = 'canlıdan eşitleme') {
    $a = Kendini-Ayari
    $ayna = $a.kaynak_deposu
    if (-not (Test-Path -LiteralPath (Join-Path $ayna '.git'))) { return "Ofisin kaynak deposu yok: $ayna" }
    $dal = (Git-Calistir $ayna @('symbolic-ref', '--short', 'HEAD') -Sessiz)
    if ([string]$dal -ne 'main') { return "Kaynak deposu main dalında değil ($dal)" }
    $canli = Kapsam-Dosyalari $KodKok
    $aynadaki = Kapsam-Dosyalari $ayna
    $set = @{}; foreach ($g in $canli) { $set[$g.ToLowerInvariant()] = $true }
    $n = 0
    foreach ($g in $canli) {
        $k = Join-Path $KodKok $g; $h = Join-Path $ayna $g
        if ((Test-Path -LiteralPath $h) -and (Dosya-Ozeti $k) -eq (Dosya-Ozeti $h)) { continue }
        New-Item -ItemType Directory -Force (Split-Path -Parent $h) | Out-Null
        Copy-Item -LiteralPath $k -Destination $h -Force; $n++
    }
    foreach ($g in $aynadaki) { if (-not $set.ContainsKey($g.ToLowerInvariant())) { Remove-Item -LiteralPath (Join-Path $ayna $g) -Force; $n++ } }
    Ayna-Rehberi-Yaz $ayna
    $durum = Git-Calistir $ayna @('status', '--porcelain') -Sessiz
    if ($durum) {
        Ayna-Git @('add', '-A') | Out-Null
        # Yalnızca gerçekten sahnelenmiş fark varsa (satır sonu dönüşümü yüzünden "değişmiş" görünen dosyalar boş commit açmasın)
        Git-Calistir $ayna @('diff', '--cached', '--quiet') -Sessiz | Out-Null
        if ($script:GitKod -ne 0) {
            Ayna-Git @('commit', '-q', '-m', "Canlıdan eşitleme ($Neden)") | Out-Null
            Gunluk "Ofis kaynak deposu canlıyla eşitlendi ($n dosya; $Neden)"
        }
    }
    return ''
}
# Ayna yoksa oluşturur (git init, .gitignore, rehber, ilk commit) ve projeler.json'a "ai-ekip-ofis" olarak kaydeder (yalnızca ana kat)
function Kendi-Projesi-Hazirla {
    $a = Kendini-Ayari
    if (-not $a.etkin -or $KatKimligi -ne 'ana') { return }
    $ayna = $a.kaynak_deposu
    if (-not (Test-Path -LiteralPath (Join-Path $ayna '.git'))) {
        New-Item -ItemType Directory -Force $ayna | Out-Null
        Git-Calistir $ayna @('init', '-q', '-b', 'main') | Out-Null
        if ($script:GitKod -ne 0) { Gunluk "Ofis kaynak deposu oluşturulamadı: $ayna" 'UYARI'; return }
        # Dosyalar canlıyla bayt bayt aynı kalsın (satır sonu dönüşümü yok); canlıya kopya birebir
        Git-Calistir $ayna @('config', 'core.autocrlf', 'false') | Out-Null
        [IO.File]::WriteAllText((Join-Path $ayna '.gitignore'), "# Testlerin ve döngünün çalışma klasörleri (kaynak değil)`ngorevler/`ndurum/`ngunluk/`nraporlar/`ncalisma/`nsirket/`nyedek/`n*.bak`n*.tmp`nDURDUR`n.test-calisma/`n__pycache__/`n", $Utf8)
        $h = Ofis-Kaynagi-Esitle 'ilk kopya'
        if ($h) { Gunluk "Ofis kaynak deposu ilk kopya: $h" 'UYARI' }
        Gunluk "Ofis kaynak deposu oluşturuldu: $ayna"
    }
    $pj = Projeleri-Yukle
    if (-not @($pj.projeler | Where-Object { $_ -and $_.kendi }).Count) {
        $p = [pscustomobject][ordered]@{ ad = [string]$a.proje_adi; klasor = $ayna; temel_dal = 'main'; dogrulama = @($a.dogrulama); kendi = $true
            aciklama = 'AI Ekip Ofisinin kendi kodu: bütün katlar (motor, panel, istemler, testler, katların istemleri). Değişiklik testlerden ve incelemeden geçince otomatik canlıya alınır.' }
        Ayarla $pj 'projeler' (@($pj.projeler | Where-Object { $_ }) + $p)
        Json-Yaz $pj (Join-Path $Kok 'projeler.json')
        Gunluk "Ofisin kendi projesi kaydedildi: $($p.ad) ($ayna)"
    }
}

# ---------------------------------------------------------------- canlıya alma
function Canli-Kayit-Yolu { Join-Path (Join-Path $KodKok 'durum') 'son-canliya-alim.json' }
function Panel-Bilgisi { $sj = Json-Oku (Join-Path $KodKok 'ofis\sunucu.json'); if ($sj -and $sj.port) { return $sj }; return $null }
function Panel-Yeniden-Baslat([switch]$Gecikmeli) {
    if ($Gecikmeli) {
        # Panelin kendi isteği içinden çağrıldıysa (geri al düğmesi) yanıt gitsin diye ayrı süreçte, birkaç saniye sonra
        $b = Join-Path (Join-Path $KodKok 'durum') 'panel-yeniden.ps1'
        [IO.File]::WriteAllText($b, "Start-Sleep -Seconds 3`r`n`$env:AIEKIP_KAT = ''`r`n. (Join-Path '$KodKok' 'ortak.ps1')`r`n. (Join-Path '$KodKok' 'kendini.ps1')`r`nPanel-Yeniden-Baslat`r`n", (New-Object Text.UTF8Encoding $true))
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList ('--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f $ps, $b) -WorkingDirectory $KodKok -WindowStyle Hidden | Out-Null
        return
    }
    $sj = Panel-Bilgisi
    if ($sj -and $sj.pid) { try { Stop-Process -Id ([int]$sj.pid) -Force -ErrorAction Stop } catch {} ; Start-Sleep -Seconds 2 }
    $gorev = $null; try { $gorev = Get-ScheduledTask -TaskPath '\AI-Ekip\' -TaskName 'Ofis' -ErrorAction Stop } catch {}
    if ($gorev) { Start-ScheduledTask -TaskPath '\AI-Ekip\' -TaskName 'Ofis' }
    else {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f $ps, (Join-Path $KodKok 'ofis\ofis.ps1')
        $eski = $env:AIEKIP_KAT; Remove-Item env:AIEKIP_KAT -ErrorAction SilentlyContinue
        try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg -WorkingDirectory $KodKok -WindowStyle Hidden | Out-Null } finally { if ($eski) { $env:AIEKIP_KAT = $eski } }
    }
}
function Http-Al([string]$Url, [hashtable]$Baslik = @{}) {
    try { $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers $Baslik -TimeoutSec 10; return [pscustomobject]@{ kod = [int]$r.StatusCode; metin = [string]$r.Content } }
    catch { $kod = 0; try { $kod = [int]$_.Exception.Response.StatusCode } catch {}; return [pscustomobject]@{ kod = $kod; metin = $_.Exception.Message } }
}
# Canlı kodu denetler: ayrıştırma, her ekip katının ayrı süreçte yüklenmesi, panel (değiştiyse yeniden başlatıp). Döner: @{ gecti; rapor }
function Canli-Dogrula([string[]]$Degisen) {
    $r = New-Object Collections.Generic.List[string]; $gecti = $true
    $betikler = @(Get-ChildItem -LiteralPath $KodKok -Filter '*.ps1' -File) + @(Get-ChildItem -LiteralPath (Join-Path $KodKok 'ofis') -Filter '*.ps1' -File)
    foreach ($f in $betikler) {
        $tok = $null; $hata = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$hata)
        if (@($hata).Count) { $gecti = $false; $r.Add("Ayrıştırma hatası: $($f.Name): $(@($hata)[0].Message) (satır $(@($hata)[0].Extent.StartLineNumber))") }
    }
    if ($gecti) { $r.Add("$($betikler.Count) betik ayrıştırıldı") }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $deneme = Join-Path (Join-Path $KodKok 'durum') 'canli-deneme.ps1'
    [IO.File]::WriteAllText($deneme, "`$ErrorActionPreference = 'Stop'`r`n. (Join-Path '$KodKok' 'ortak.ps1')`r`n. (Join-Path '$KodKok' 'rapor.ps1')`r`n. (Join-Path '$KodKok' 'ekip.ps1')`r`nAyarlari-Yukle`r`nKadro-Rolleri-Yukle`r`n'YUKLENDI ' + `$KatKimligi`r`n", (New-Object Text.UTF8Encoding $true))
    foreach ($k in @(Katlar-Oku | Where-Object { [string]$_.tur -ne 'uygulama' })) {
        if (-not $gecti) { break }   # betik ayrışmıyorsa yükleme denemesi anlamsız
        $kk = Kat-Koku $k
        if (-not (Test-Path -LiteralPath (Join-Path $kk 'kadro.json'))) { continue }
        $eski = $env:AIEKIP_KAT; $env:AIEKIP_KAT = $(if ([string]$k.id -eq 'ana') { '' } else { [string]$k.id })
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $cikti = & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $deneme 2>&1 | Out-String } finally { $env:AIEKIP_KAT = $eski; $ErrorActionPreference = $eap }
        if ($cikti -match "YUKLENDI $([regex]::Escape([string]$k.id))") { $r.Add("Kat yüklendi: $($k.id)") } else { $gecti = $false; $r.Add("Kat yüklenemedi: $($k.id): $(Kisalt $cikti 600)") }
    }
    Remove-Item -LiteralPath $deneme -Force -ErrorAction SilentlyContinue
    $panelPs = @($Degisen | Where-Object { $_ -match '^ofis\\[^\\]+\.ps1$' }).Count -gt 0
    $panelHtml = @($Degisen | Where-Object { $_ -match '^ofis\\[^\\]+\.html$' })
    if ($panelPs -and $gecti) {
        Panel-Yeniden-Baslat
        $sj = $null; for ($i = 0; $i -lt 30 -and -not $sj; $i++) { Start-Sleep -Seconds 1; $s2 = Panel-Bilgisi; if ($s2 -and (Http-Al "http://127.0.0.1:$($s2.port)/").kod -eq 200) { $sj = $s2 } }
        if (-not $sj) { $gecti = $false; $r.Add('Panel sunucusu yeniden başlatıldıktan sonra yanıt vermedi') } else { $r.Add("Panel yeniden başladı (:$($sj.port))") }
    }
    $sj = Panel-Bilgisi
    if ($gecti -and $sj -and ($panelPs -or $panelHtml.Count)) {
        $kabuk = Http-Al "http://127.0.0.1:$($sj.port)/"
        $m = [regex]::Match($kabuk.metin, "const ANAHTAR = '([^']+)'")
        $sayfalar = @('/kat/ana/'); foreach ($k in @(Katlar-Oku | Where-Object { [string]$_.panel })) { $sayfalar += "/kat/$($k.id)/" }
        foreach ($s in $sayfalar) { $y = Http-Al "http://127.0.0.1:$($sj.port)$s"; if ($y.kod -ne 200 -or $y.metin -notmatch '<script') { $gecti = $false; $r.Add("Panel sayfası açılmadı: $s ($($y.kod))") } }
        if ($m.Success) {
            $d = Http-Al "http://127.0.0.1:$($sj.port)/api/durum" @{ 'X-Ofis-Anahtar' = $m.Groups[1].Value }
            if ($d.kod -ne 200) { $gecti = $false; $r.Add("Panel /api/durum yanıt vermedi ($($d.kod))") } else { $r.Add('Panel API yanıt veriyor') }
        }
        # Sayfa betiklerinin sözdizimi (node varsa)
        $node = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($node) {
            foreach ($h in $panelHtml) {
                $html = Metin-Oku (Join-Path $KodKok $h); $i = 0
                foreach ($sm in [regex]::Matches($html, '(?s)<script[^>]*>(.*?)</script>')) {
                    $i++; $js = Join-Path $env:TEMP ("ofis-betik-{0}-{1}.js" -f $PID, $i)
                    [IO.File]::WriteAllText($js, $sm.Groups[1].Value, $Utf8)
                    $c = & $node.Source --check $js 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) { $gecti = $false; $r.Add("Sayfa betiği hatalı: $h #$($i): $(Kisalt $c 300)") }
                    Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    return [pscustomobject]@{ gecti = $gecti; rapor = ($r -join "`n") }
}
function Yedekten-Geri-Yukle($Kayit) {
    $yedek = [string]$Kayit.yedek
    foreach ($g in @($Kayit.eklenen)) { if ($g) { Remove-Item -LiteralPath (Join-Path $KodKok $g) -Force -ErrorAction SilentlyContinue } }
    foreach ($g in @($Kayit.degisen + $Kayit.silinen)) {
        if (-not $g) { continue }
        $y = Join-Path $yedek $g
        if (Test-Path -LiteralPath $y) { $h = Join-Path $KodKok $g; New-Item -ItemType Directory -Force (Split-Path -Parent $h) | Out-Null; Copy-Item -LiteralPath $y -Destination $h -Force }
    }
}
# Görevin dalını aynaya birleştirir, değişen dosyaları yedekleyip canlıya kopyalar, doğrular; olmazsa geri alır
function Adim-CanliyaAl($G) {
    $a = Kendini-Ayari
    $ayna = $a.kaynak_deposu
    $gk = Gorev-Klasoru $G.id
    if (-not $a.otomatik -and -not $G.canliya_al_onaylandi) {
        Ayarla $G 'canliya_alim' ([pscustomobject]@{ durum = 'bekliyor'; zaman = (Simdi) })
        Asama-Gec $G 'tamam' 'commit edildi; canlıya alma kullanıcının onayında' "durum.ps1 -CanliyaAl $($G.id) ya da panel"
        Bildir -Baslik "Canlıya almayı bekliyor: $($G.baslik)" -Metin ('#{0} hazır; otomatik canlıya alma kapalı. Panelden ya da durum.ps1 -CanliyaAl ile alınır.' -f (($G.id -split '-')[0])) -Anahtar "canli-$($G.id)"
        return
    }
    $h = Ofis-Kaynagi-Esitle "#$($G.id) öncesi"
    if ($h) { Takildi $G "Canlıya alınamadı: $h"; return }
    $onceki = Git-Calistir $ayna @('rev-parse', 'HEAD')
    Ayna-Git @('merge', '--no-ff', '-m', "Canlıya: #$($G.id) $($G.baslik)", [string]$G.dal) | Out-Null
    if ($script:GitKod -ne 0) {
        Ayna-Git @('merge', '--abort') -Sessiz | Out-Null
        Takildi $G "Görev dalı ($($G.dal)) ofisin güncel koduyla çakıştı; birleştirilemedi. Dal yeniden ele alınmalı (canlı bu arada değişmiş)."
        return
    }
    $sonraki = Git-Calistir $ayna @('rev-parse', 'HEAD')
    $satirlar = @(((Git-Calistir $ayna @('-c', 'core.quotepath=false', 'diff', '--name-status', '--no-renames', $onceki, $sonraki)) -split "`r?`n") | Where-Object { $_ })
    $degisen = @(); $eklenen = @(); $silinen = @(); $atlanan = @()
    foreach ($s in $satirlar) {
        $p = $s -split "`t"; if ($p.Count -lt 2) { continue }
        $dy = $p[1] -replace '/', '\'
        if (-not (Canliya-Alinir-mi $dy)) { $atlanan += $dy; continue }
        if ($p[0] -eq 'D') { $silinen += $dy } elseif (Test-Path -LiteralPath (Join-Path $KodKok $dy)) { $degisen += $dy } else { $eklenen += $dy }
    }
    $zaman = Get-Date
    $yedek = Join-Path $KodKok ('yedek\{0}-{1}' -f $zaman.ToString('yyyyMMdd-HHmmss'), (($G.id -split '-')[0]))
    $kayit = [pscustomobject][ordered]@{ gorev = [string]$G.id; baslik = [string]$G.baslik; zaman = $zaman.ToString('o'); yedek = $yedek; onceki = $onceki; birlestirme = $sonraki
        degisen = @($degisen); eklenen = @($eklenen); silinen = @($silinen); atlanan = @($atlanan); geri_alindi = $false; dogrulama = '' }
    if (-not ($degisen.Count + $eklenen.Count + $silinen.Count)) {
        Ayarla $G 'canliya_alim' ([pscustomobject]@{ durum = 'degisiklik_yok'; zaman = (Simdi); atlanan = @($atlanan) })
        Asama-Gec $G 'tamam' 'canlıya alınacak kod değişikliği yok' ($atlanan -join ', ')
        Sayac-Artir 'tamamlanan'
        return
    }
    foreach ($dy in @($degisen + $silinen)) { $y = Join-Path $yedek $dy; New-Item -ItemType Directory -Force (Split-Path -Parent $y) | Out-Null; Copy-Item -LiteralPath (Join-Path $KodKok $dy) -Destination $y -Force }
    New-Item -ItemType Directory -Force $yedek | Out-Null
    Json-Yaz $kayit (Join-Path $yedek 'canliya-alim.json')
    foreach ($dy in @($degisen + $eklenen)) { $h2 = Join-Path $KodKok $dy; New-Item -ItemType Directory -Force (Split-Path -Parent $h2) | Out-Null; Copy-Item -LiteralPath (Join-Path $ayna $dy) -Destination $h2 -Force }
    foreach ($dy in $silinen) { Remove-Item -LiteralPath (Join-Path $KodKok $dy) -Force -ErrorAction SilentlyContinue }
    Gunluk "Görev $($G.id): canlıya kopyalandı ($($degisen.Count) değişen, $($eklenen.Count) yeni, $($silinen.Count) silinen); doğrulanıyor"
    $d = Canli-Dogrula (@($degisen + $eklenen + $silinen))
    $kayit.dogrulama = $d.rapor
    $rapor = @("# Canlıya alma · #$($G.id)", '', "- Zaman: $($zaman.ToString('dd.MM.yyyy HH:mm'))", "- Dal: $($G.dal) → ayna main ($($sonraki.Substring(0, 8)))", "- Yedek: $yedek",
        "- Değişen: $($degisen -join ', ')", "- Yeni: $($eklenen -join ', ')", "- Silinen: $($silinen -join ', ')", "- Canlıya alınmayan (ayar dosyaları): $($atlanan -join ', ')", '', '## Doğrulama', '', $d.rapor)
    if (-not $d.gecti) {
        Yedekten-Geri-Yukle $kayit
        Ayna-Git @('reset', '-q', '--hard', $onceki) | Out-Null
        if (@($degisen + $eklenen + $silinen | Where-Object { $_ -match '^ofis\\[^\\]+\.ps1$' }).Count) { Panel-Yeniden-Baslat }
        $kayit.geri_alindi = $true
        Json-Yaz $kayit (Join-Path $yedek 'canliya-alim.json')
        Metin-Yaz (Join-Path $gk 'canliya-alim.md') (($rapor + @('', '## Sonuç', '', 'Doğrulama geçmedi; canlı yedekten geri yüklendi, ayna eski haline döndü.')) -join "`n")
        Ayarla $G 'canliya_alim' ([pscustomobject]@{ durum = 'geri_alindi'; zaman = (Simdi); yedek = $yedek; neden = (Kisalt $d.rapor 600) })
        Takildi $G "Canlıya alma doğrulamadan geçmedi; geri alındı. $(Kisalt $d.rapor 300)"
        return
    }
    Json-Yaz $kayit (Join-Path $yedek 'canliya-alim.json')
    Json-Yaz $kayit (Canli-Kayit-Yolu)
    Metin-Yaz (Join-Path $gk 'canliya-alim.md') (($rapor + @('', '## Sonuç', '', 'Canlıya alındı. Döngü yeni kodu bir sonraki turda yükler; panel sayfaları ve istemler hemen geçerli.')) -join "`n")
    Ayarla $G 'canliya_alim' ([pscustomobject]@{ durum = 'canlida'; zaman = (Simdi); yedek = $yedek; dosya_sayisi = ($degisen.Count + $eklenen.Count + $silinen.Count); birlestirme = $sonraki.Substring(0, 8) })
    Asama-Gec $G 'tamam' 'canlıya alındı' ('{0} dosya · yedek {1}' -f ($degisen.Count + $eklenen.Count + $silinen.Count), (Split-Path -Leaf $yedek))
    Sayac-Artir 'tamamlanan'
    Bildir -Baslik "Canlıya alındı: $($G.baslik)" -Metin ('#{0}: {1} dosya ofise uygulandı ve doğrulandı. Geri almak için panel ya da durum.ps1 -GeriAl {0}' -f (($G.id -split '-')[0]), ($degisen.Count + $eklenen.Count + $silinen.Count)) -Anahtar "canli-$($G.id)"
}
# Son canlıya almayı geri alır (yalnız en sonuncusu: sonrakiler aynı dosyaları değiştirmiş olabilir). Döner: '' ya da hata metni
function Canliya-Alimi-Geri-Al([string]$Id = '', [string]$Neden = 'kullanıcı istedi') {
    $k = Json-Oku (Canli-Kayit-Yolu)
    if (-not $k -or $k.geri_alindi) { return 'Geri alınacak bir canlıya alma yok.' }
    if ($Id -and [string]$k.gorev -ne $Id -and -not ([string]$k.gorev).StartsWith("$Id-")) { return "Son canlıya alma #$((([string]$k.gorev) -split '-')[0]); yalnızca en sonuncusu geri alınabilir." }
    Yedekten-Geri-Yukle $k
    $ayna = (Kendini-Ayari).kaynak_deposu
    if (Test-Path -LiteralPath (Join-Path $ayna '.git')) { Ayna-Git @('revert', '--no-edit', '-m', '1', [string]$k.birlestirme) | Out-Null; if ($script:GitKod -ne 0) { Ayna-Git @('revert', '--abort') -Sessiz | Out-Null; [void](Ofis-Kaynagi-Esitle 'geri alma') } }
    if (@($k.degisen + $k.eklenen + $k.silinen | Where-Object { $_ -match '^ofis\\[^\\]+\.ps1$' }).Count) { Panel-Yeniden-Baslat -Gecikmeli }
    $k.geri_alindi = $true
    Json-Yaz $k (Canli-Kayit-Yolu)
    Json-Yaz $k (Join-Path ([string]$k.yedek) 'canliya-alim.json')
    $g = Gorev-Oku ([string]$k.gorev)
    if ($g) {
        Ayarla $g 'canliya_alim' ([pscustomobject]@{ durum = 'geri_alindi'; zaman = (Simdi); yedek = [string]$k.yedek; neden = $Neden })
        Gecmis-Ekle $g 'canlıya alma geri alındı' $Neden
        Gorev-Kaydet $g
    }
    Gunluk "Canlıya alma geri alındı: $($k.gorev) ($Neden)" 'UYARI'
    Bildir -Baslik "Canlıya alma geri alındı: $($k.baslik)" -Metin ("#{0}: {1}" -f ((([string]$k.gorev) -split '-')[0]), $Neden) -Anahtar "geri-al-$($k.gorev)" -Onem 'yuksek'
    return ''
}
# Güvenlik ağı: canlıya almadan sonra döngü üst üste hata veriyorsa (ekip.ps1 > Ekip-Dongusu) son canlıya almayı geri al
function Canliya-Alim-Guvenlik-Agi([int]$HataSayisi) {
    if ($HataSayisi -lt 3) { return $false }
    $k = Json-Oku (Canli-Kayit-Yolu)
    if (-not $k -or $k.geri_alindi) { return $false }
    try { if (((Get-Date) - [datetime][string]$k.zaman).TotalMinutes -gt [double](Kendini-Ayari).guvenlik_agi_dk) { return $false } } catch { return $false }
    return ((Canliya-Alimi-Geri-Al '' "döngü canlıya almadan sonra üst üste $HataSayisi kez hata verdi") -eq '')
}
