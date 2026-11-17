<#
ortak.ps1 - AI Ekip ortak işlevleri (diğer betikler dot-source eder: . "$PSScriptRoot\ortak.ps1")
Windows PowerShell 5.1 uyumludur. Dosya UTF-8 BOM ile kaydedilmelidir (Türkçe karakterler için).
#>
$ErrorActionPreference = 'Stop'
$script:Kok        = $PSScriptRoot
. (Join-Path $PSScriptRoot 'yapilandirma.ps1')
$script:Utf8       = New-Object Text.UTF8Encoding $false
$script:YolGorev   = Join-Path $Kok 'gorevler'
$script:YolDurum   = Join-Path $Kok 'durum'
$script:YolGunluk  = Join-Path $Kok 'gunluk'
$script:YolRapor   = Join-Path $Kok 'raporlar'
$script:YolCalisma = Join-Path $Kok 'calisma'
$script:YolIstem   = Join-Path $Kok 'istemler'
foreach ($d in @($YolGorev, $YolDurum, $YolGunluk, $YolRapor, $YolCalisma)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
}
if (-not (Test-Path variable:script:Konsol)) { $script:Konsol = $false }
$script:AktifGorev = ''
$script:AktifAdim  = ''
# Kök neden analizi iptal edilmiş görevler üzerinde çalışır: o sırada iptal izlemesi kapatılır (cozucu.ps1 > Kok-Neden-Belirle)
$script:IptalIzleme = $true
$script:YardimIstegi = $null   # son ajan çağrısının ekip içi yardım isteği (yardim.ps1 > Yardim-Istegi-Kaydet işler)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ---------------------------------------------------------------- dosya / json
function Metin-Oku([string]$Yol) {
    if ($Yol -and (Test-Path -LiteralPath $Yol)) { return [IO.File]::ReadAllText($Yol, $Utf8) }
    return ''
}
function Metin-Yaz([string]$Yol, [string]$Metin) {
    $tmp = "$Yol.tmp"
    [IO.File]::WriteAllText($tmp, $Metin, $Utf8)
    if (Test-Path -LiteralPath $Yol) { [IO.File]::Replace($tmp, $Yol, "$Yol.bak") }
    else { [IO.File]::Move($tmp, $Yol) }
}
function Json-Oku([string]$Yol) {
    $Yol = Yapilandirma-Yolu $Yol
    foreach ($aday in @($Yol, "$Yol.bak")) {
        $t = Metin-Oku $aday
        if ($t.Trim()) { try { return ($t | ConvertFrom-Json) } catch {} }
    }
    return $null
}
function Json-Yaz($Nesne, [string]$Yol) { Metin-Yaz (Yapilandirma-Yolu $Yol -Yaz) ($Nesne | ConvertTo-Json -Depth 10) }
function Ayarla($Nesne, [string]$Ad, $Deger) {
    if ($Nesne.PSObject.Properties[$Ad]) { $Nesne.$Ad = $Deger }
    else { $Nesne | Add-Member -NotePropertyName $Ad -NotePropertyValue $Deger }
}
function Kisalt([string]$Metin, [int]$Uzunluk = 300) {
    if (-not $Metin) { return '' }
    $m = ($Metin -replace '\s+', ' ').Trim()
    if ($m.Length -le $Uzunluk) { return $m }
    return $m.Substring(0, $Uzunluk) + '...'
}
function Son-Satirlar([string]$Metin, [int]$Adet = 10) {
    if (-not $Metin) { return '' }
    $s = $Metin -split "`r?`n" | Where-Object { $_.Trim() }
    return (@($s) | Select-Object -Last $Adet) -join "`n"
}
function Simdi { (Get-Date).ToString('o') }
function Slug([string]$s) {
    $t = $s.Replace('İ', 'i').Replace('I', 'i').ToLowerInvariant()
    foreach ($c in @(@('ç', 'c'), @('ğ', 'g'), @('ı', 'i'), @('ö', 'o'), @('ş', 's'), @('ü', 'u'), @('â', 'a'), @('î', 'i'), @('û', 'u'))) { $t = $t.Replace($c[0], $c[1]) }
    $t = ($t -replace '[^a-z0-9]+', '-').Trim('-')
    if ($t.Length -gt 40) { $t = $t.Substring(0, 40).Trim('-') }
    if (-not $t) { $t = 'gorev' }
    return $t
}
function Q([string]$s) { '"' + $s + '"' }

# ---------------------------------------------------------------- günlük
function Gunluk([string]$Mesaj, [string]$Seviye = 'BILGI') {
    $satir = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Seviye, $Mesaj
    $yol = Join-Path $YolGunluk ('ekip-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    try { [IO.File]::AppendAllText($yol, $satir + "`r`n", $Utf8) } catch {}
    if ($script:Konsol) { Write-Host $satir }
}

# ---------------------------------------------------------------- ayarlar
function Ayarlari-Yukle {
    $a = Json-Oku (Join-Path $Kok 'ayarlar.json')
    if (-not $a) { throw 'ayarlar.json okunamadı' }
    $script:Ayar = $a
}
function Projeleri-Yukle {
    $p = Json-Oku (Join-Path $Kok 'projeler.json')
    if (-not $p) { $p = [pscustomobject]@{ projeler = @() } }
    return $p
}
function Proje-Bul([string]$AdVeyaKlasor) {
    $p = Projeleri-Yukle
    foreach ($x in @($p.projeler)) {
        if ($x.ad -eq $AdVeyaKlasor) { return $x }
        if ($AdVeyaKlasor -and (Test-Path -LiteralPath $AdVeyaKlasor) -and
            ((Resolve-Path -LiteralPath $AdVeyaKlasor).Path.TrimEnd('\') -eq ([string]$x.klasor).TrimEnd('\'))) { return $x }
    }
    return $null
}

# ---------------------------------------------------------------- kalp atışı (bekçi bunu izler)
function Kalp([string]$Durum) {
    try {
        Json-Yaz ([ordered]@{ pid = $PID; zaman = (Simdi); durum = $Durum; gorev = $script:AktifGorev; adim = $script:AktifAdim }) (Join-Path $YolDurum 'kalp.json')
    } catch {}
}

# ---------------------------------------------------------------- günlük sayaçlar
function Sayac-Oku {
    $s = Json-Oku (Join-Path $YolDurum 'sayaclar.json')
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    if (-not $s -or $s.tarih -ne $bugun) {
        $s = [pscustomobject]@{ tarih = $bugun; claude = 0; codex = 0; gemini = 0; tamamlanan = 0; takilan = 0; ozet_gonderilen = @() }
    }
    return $s
}
function Sayac-Artir([string]$Ad, [int]$Miktar = 1) {
    $s = Sayac-Oku
    $eski = 0; if ($s.PSObject.Properties[$Ad]) { $eski = [int]$s.$Ad }
    Ayarla $s $Ad ($eski + $Miktar)
    Json-Yaz $s (Join-Path $YolDurum 'sayaclar.json')
}

# ---------------------------------------------------------------- kilitler (limit / giriş sorunu olan araçlar)
function Kilit-Oku {
    $k = Json-Oku (Join-Path $YolDurum 'kilitler.json')
    if (-not $k) { $k = New-Object psobject }
    return $k
}
function Kilit-Koy([string]$Anahtar, [datetime]$Bitis, [string]$Neden) {
    $k = Kilit-Oku
    Ayarla $k $Anahtar ([pscustomobject]@{ bitis = $Bitis.ToString('o'); neden = $Neden })
    Json-Yaz $k (Join-Path $YolDurum 'kilitler.json')
    Gunluk ("Kilit: {0} -> {1} ({2})" -f $Anahtar, $Bitis.ToString('dd.MM HH:mm'), $Neden) 'UYARI'
}
function Kilitli([string]$Anahtar) {
    $k = Kilit-Oku
    if (-not $k.PSObject.Properties[$Anahtar]) { return $null }
    $v = $k.$Anahtar
    if ($v -and ([datetime]$v.bitis) -gt (Get-Date)) { return $v }
    return $null
}

# ---------------------------------------------------------------- araç yolları
function Codex-Exe {
    if ($Ayar.codex.exe -and (Test-Path -LiteralPath $Ayar.codex.exe -PathType Leaf)) { return [string]$Ayar.codex.exe }
    if ($script:CodexYolu -and (Test-Path -LiteralPath $script:CodexYolu)) { return $script:CodexYolu }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg) {
        $a = Join-Path $pkg.InstallLocation 'app\resources\codex.exe'
        if (Test-Path -LiteralPath $a) { $script:CodexYolu = $a; return $a }
    }
    $c = Get-Command codex -ErrorAction SilentlyContinue
    if ($c) { $script:CodexYolu = $c.Source; return $c.Source }
    return $null
}
function Gemini-Exe {
    if ($Ayar.gemini.exe -and (Test-Path -LiteralPath $Ayar.gemini.exe -PathType Leaf)) { return [string]$Ayar.gemini.exe }
    $c = Get-Command gemini.cmd -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# ---------------------------------------------------------------- süreç çalıştırma (zaman aşımı + kalp atışı)
function Surec-Calistir {
    param(
        [Parameter(Mandatory)][string]$Komut,   # cmd.exe içinde çalışacak komut (yönlendirmeler hariç)
        [string]$Girdi = '',
        [Parameter(Mandatory)][string]$Cikti,
        [string]$Hata = '',                     # boşsa stderr çıktıya eklenir
        [Parameter(Mandatory)][string]$Klasor,
        [int]$ZamanAsimiDk = 30,
        [string]$Etiket = 'surec'
    )
    $ic = $Komut
    if ($Girdi) { $ic += ' < ' + (Q $Girdi) }
    $ic += ' > ' + (Q $Cikti)
    if ($Hata) { $ic += ' 2> ' + (Q $Hata) } else { $ic += ' 2>&1' }
    $bas = Get-Date
    $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList ('/d /s /c "' + $ic + '"') `
        -WorkingDirectory $Klasor -WindowStyle Hidden -PassThru
    $null = $p.Handle
    $asim = $false
    $iptal = $false
    $gorevId = [string]$script:AktifGorev
    while (-not $p.WaitForExit(15000)) {
        Kalp "$Etiket çalışıyor"
        # Kullanıcı görevi bu süreç çalışırken iptal ettiyse (panel / durum.ps1 -Iptal) işi bitirmesini bekleme
        if ($script:IptalIzleme -and $gorevId -and (Gorev-Iptal-mi $gorevId)) {
            $iptal = $true
            Gunluk "Görev $gorevId iptal edildi; çalışan $Etiket süreç ağacı sonlandırılıyor (PID $($p.Id))" 'UYARI'
            $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $p.Id 2>&1 | Out-Null } catch {} finally { $ErrorActionPreference = $eap }
            $null = $p.WaitForExit(20000)
            break
        }
        if (((Get-Date) - $bas).TotalMinutes -ge $ZamanAsimiDk) {
            $asim = $true
            Gunluk "$Etiket zaman aşımına uğradı ($ZamanAsimiDk dk), süreç ağacı sonlandırılıyor" 'UYARI'
            & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $p.Id 2>$null | Out-Null
            $null = $p.WaitForExit(20000)
            break
        }
    }
    $kod = -1
    if (-not $asim -and -not $iptal) { $kod = $p.ExitCode }
    return [pscustomobject]@{ kod = $kod; zaman_asimi = $asim; iptal = $iptal; sure_sn = [int]((Get-Date) - $bas).TotalSeconds }
}

# ---------------------------------------------------------------- git
function Git-Calistir([string]$Klasor, [string[]]$Arg, [switch]$Sessiz) {
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $o = & git -c core.quotepath=off -C $Klasor @Arg 2>&1 | ForEach-Object { "$_" }
        $script:GitKod = $LASTEXITCODE
    } finally { $ErrorActionPreference = $eap }
    $metin = (@($o) -join "`n").Trim()
    if ($script:GitKod -ne 0 -and -not $Sessiz) { throw ("git {0} başarısız ({1}): {2}" -f ($Arg -join ' '), $script:GitKod, (Kisalt $metin 400)) }
    return $metin
}
# Büyük çıktıları (diff) UTF-8 bozulmadan dosyaya alır
function Git-Dosyaya([string]$Klasor, [string]$ArgMetni, [string]$Dosya) {
    $s = Surec-Calistir -Komut ('git -c core.quotepath=off --no-pager ' + $ArgMetni) -Cikti $Dosya -Hata "$Dosya.err" -Klasor $Klasor -ZamanAsimiDk 5 -Etiket 'git'
    return (Metin-Oku $Dosya)
}

# ---------------------------------------------------------------- şablon doldurma
function Sablon-Doldur([string]$SablonAdi, [hashtable]$Degerler) {
    $s = Metin-Oku (Join-Path $YolIstem $SablonAdi)
    if (-not $s) { throw "İstem şablonu bulunamadı: $SablonAdi" }
    $d = $Degerler
    $deg = [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $ad = $m.Groups[1].Value
        if ($d.ContainsKey($ad)) { return [string]$d[$ad] }
        return $m.Value
    }.GetNewClosure()
    return [regex]::Replace($s, '\{([A-Z_]+)\}', $deg)
}
function Karar-Oku([string]$Metin) {
    $m = [regex]::Match($Metin, '(?m)^\W{0,4}KARAR\W{0,4}\s*([A-ZÇĞİÖŞÜ_]+)')
    if ($m.Success) { return $m.Groups[1].Value.ToUpperInvariant() }
    return ''
}
function Alan-Oku([string]$Metin, [string]$Ad) {
    $m = [regex]::Match($Metin, '(?m)^\W{0,4}' + $Ad + '\W{0,4}\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.Trim('*', ' ', '`') }
    return ''
}

# ---------------------------------------------------------------- araç uygunluğu
function Arac-Uygun($Giris) {
    $arac = [string]$Giris.arac
    $sinir = 0
    if ($Ayar.gunluk_sinir.PSObject.Properties[$arac]) { $sinir = [int]$Ayar.gunluk_sinir.$arac }
    $s = Sayac-Oku
    $kullanilan = 0; if ($s.PSObject.Properties[$arac]) { $kullanilan = [int]$s.$arac }
    if ($sinir -gt 0 -and $kullanilan -ge $sinir) { return "günlük sınır doldu ($kullanilan/$sinir)" }
    $kl = Kilitli $arac
    if ($kl) { return "$($kl.neden) ($(([datetime]$kl.bitis).ToString('HH:mm'))'e kadar)" }
    $kl = Kilitli ("{0}:{1}" -f $arac, $Giris.model)
    if ($kl) { return "$($kl.neden) ($(([datetime]$kl.bitis).ToString('HH:mm'))'e kadar)" }
    switch ($arac) {
        'claude' {
            if (-not (Test-Path -LiteralPath $Ayar.claude.exe -ErrorAction SilentlyContinue)) { return 'claude.exe bulunamadı' }
            # İsteğe bağlı kullanım dosyası ile kullanıcının kalan hakkını koru
            $kd = Json-Oku $Ayar.claude.kullanim_dosyasi
            if ($kd -and $kd.guncelleme_zamani) {
                $yas = ((Get-Date) - [datetime]$kd.guncelleme_zamani).TotalHours
                if ($yas -lt [double]$Ayar.claude.kullanim_dosyasi_gecerlilik_saat -and [int]$kd.kalan_yuzde -lt [int]$Ayar.claude.min_kalan_yuzde) {
                    return "Claude kullanım hakkı az (kalan %$($kd.kalan_yuzde))"
                }
            }
        }
        'codex'  { if (-not (Codex-Exe)) { return 'codex.exe bulunamadı' } }
        'gemini' { if (-not (Gemini-Exe)) { return 'gemini CLI bulunamadı' } }
        default  { return "bilinmeyen araç: $arac" }
    }
    return $null
}

function Sonuc([bool]$Basarili, [string]$Metin, [string]$Hata, $Surec, $Kullanim = $null) {
    $sure = 0; if ($Surec) { $sure = $Surec.sure_sn }
    return [pscustomobject]@{ basarili = $Basarili; metin = $Metin; hata = $Hata; sure_sn = $sure; arac = ''; model = ''; kullanim = $Kullanim }
}

# ---------------------------------------------------------------- token / bağlam kullanımı (panelde "Kullanım" panosu)
# Her ajan çağrısı durum\kullanim\kullanim-yyyyMM.jsonl dosyasına bir satır ekler (başarısız ve iptal edilen çağrılar dahil).
#   giris          önbellekten gelmeyen istem tokenleri      onbellek_okuma / onbellek_yazma  istem önbelleği
#   cikis          üretilen tokenler (akıl yürütme dahil)    toplam   hepsinin toplamı
#   baglam_tepe    çağrıdaki en büyük tek istek (istem + önbellek + çıktı); baglam_pencere modelin bağlam penceresi
$script:YolKullanim = Join-Path $YolDurum 'kullanim'
function Sayi($Deger) {
    if ($null -eq $Deger -or $Deger -eq '') { return [long]0 }
    try { return [long]$Deger } catch { return [long]0 }
}
function Bas-Oku([string]$Yol, [int]$Bayt = 4096) {
    if (-not $Yol -or -not (Test-Path -LiteralPath $Yol)) { return '' }
    try {
        $fs = [IO.FileStream]::new($Yol, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $b = New-Object byte[] ([Math]::Min([long]$Bayt, $fs.Length)); [void]$fs.Read($b, 0, $b.Length); return $Utf8.GetString($b) } finally { $fs.Dispose() }
    } catch { return '' }
}
function Satir-Ekle([string]$Yol, [string]$Satir) {
    for ($i = 0; $i -lt 6; $i++) {
        try { [IO.File]::AppendAllText($Yol, $Satir + "`n", $Utf8); return $true } catch { Start-Sleep -Milliseconds (80 * ($i + 1)) }
    }
    return $false
}
# Claude: --output-format stream-json --verbose çıktısı (eski tek JSON biçimini de okur)
function Claude-Cikti-Coz([string]$Ham) {
    $sonuc = $null; $tepe = [long]0
    $gorulen = @{}
    $top = [ordered]@{ giris = [long]0; onbellek_okuma = [long]0; onbellek_yazma = [long]0; cikis = [long]0 }
    $haklar = $null
    foreach ($satir in ($Ham -split "`r?`n")) {
        # Araç sonuçlarını (type=user, büyük dosya içerikleri) hiç çözme. Alan sırası CLI sürümüne göre değişir
        # (2.1.3xx'te sonuç satırı "duration_api_ms" ile başlar), bu yüzden "type" alanı satırın herhangi bir yerinde aranır.
        if (-not $satir.StartsWith('{') -or $satir.StartsWith('{"type":"user"')) { continue }
        if ($satir -notmatch '"type":"(assistant|result|rate_limit_event)"') { continue }
        $j = $null
        try { $j = $satir | ConvertFrom-Json } catch { continue }
        if ($j.type -eq 'result') { $sonuc = $j; continue }
        if ($j.type -eq 'rate_limit_event') { if ($j.rate_limit_info) { $haklar = $j.rate_limit_info }; continue }
        if ($j.type -ne 'assistant') { continue }
        $m = $j.message
        if (-not $m -or -not $m.usage) { continue }
        $u = $m.usage
        $b = (Sayi $u.input_tokens) + (Sayi $u.cache_read_input_tokens) + (Sayi $u.cache_creation_input_tokens) + (Sayi $u.output_tokens)
        if ($b -gt $tepe) { $tepe = $b }
        $kimlik = [string]$m.id
        if ($kimlik -and $gorulen.ContainsKey($kimlik)) { continue }   # aynı yanıtın içerik blokları ayrı satırlarda tekrar eder
        if ($kimlik) { $gorulen[$kimlik] = $true }
        $top.giris += (Sayi $u.input_tokens); $top.onbellek_okuma += (Sayi $u.cache_read_input_tokens)
        $top.onbellek_yazma += (Sayi $u.cache_creation_input_tokens); $top.cikis += (Sayi $u.output_tokens)
    }
    if (-not $sonuc -and $Ham.TrimStart().StartsWith('{')) {
        try { $j = $Ham | ConvertFrom-Json; if ($j.type -eq 'result') { $sonuc = $j } } catch {}
    }
    if ($haklar) { try { Claude-Haklari-Kaydet $haklar } catch {} }
    $kul = $null
    if ($sonuc -and $sonuc.usage) {
        $u = $sonuc.usage
        $pencere = [long]0
        if ($sonuc.modelUsage) { foreach ($p in $sonuc.modelUsage.PSObject.Properties) { $w = Sayi $p.Value.contextWindow; if ($w -gt $pencere) { $pencere = $w } } }
        $istek = $gorulen.Count; if ($istek -eq 0) { $istek = Sayi $sonuc.num_turns }
        # Gerçekte çalışan model ("opus" gibi kısaltmalar CLI sürümüne göre farklı modele gider): en çok harcayan
        $gercek = ''; $enCok = -1.0
        if ($sonuc.modelUsage) { foreach ($p in $sonuc.modelUsage.PSObject.Properties) { $c2 = [double]$p.Value.costUSD; if ($c2 -gt $enCok) { $enCok = $c2; $gercek = $p.Name } } }
        $kul = [ordered]@{
            giris = (Sayi $u.input_tokens); onbellek_okuma = (Sayi $u.cache_read_input_tokens); onbellek_yazma = (Sayi $u.cache_creation_input_tokens)
            cikis = (Sayi $u.output_tokens); baglam_tepe = $tepe; baglam_pencere = $pencere; istek = [long]$istek
            maliyet_usd = [double]$sonuc.total_cost_usd; olcum = $(if ($tepe -gt 0) { 'tam' } else { 'toplam' }); model_gercek = $gercek
        }
    } elseif ($gorulen.Count -gt 0) {
        # Zaman aşımı / iptal: sonuç satırı yok, yarıda kalan yanıtların kullanımı
        $kul = [ordered]@{ giris = $top.giris; onbellek_okuma = $top.onbellek_okuma; onbellek_yazma = $top.onbellek_yazma; cikis = $top.cikis
            baglam_tepe = $tepe; baglam_pencere = [long]0; istek = [long]$gorulen.Count; maliyet_usd = [double]0; olcum = 'yarim' }
    }
    return [pscustomobject]@{ sonuc = $sonuc; kullanim = $kul }
}
# Codex: stderr başlığındaki "session id" ile ~\.codex\sessions altındaki oturum dosyasını bulup token_count olaylarını okur
function Codex-Oturum-Dosyasi([string]$ErrYolu) {
    $m = [regex]::Match((Bas-Oku $ErrYolu 6144), '(?m)^session id:\s*([0-9a-fA-F-]{36})')
    if (-not $m.Success) { return '' }
    $id = $m.Groups[1].Value
    $ev = $env:CODEX_HOME; if (-not $ev) { $ev = Join-Path $env:USERPROFILE '.codex' }
    foreach ($gun in @((Get-Date), (Get-Date).AddDays(-1), (Get-Date).AddDays(-2))) {
        $d = Join-Path (Join-Path $ev 'sessions') ('{0:yyyy}\{0:MM}\{0:dd}' -f $gun)
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $f = Get-ChildItem -LiteralPath $d -Filter "*$id.jsonl" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return ''
}
function Codex-Kullanim([string]$ErrYolu, [string]$OturumDosyasi = '', [switch]$Gecmis) {
    $kul = $null
    $dosya = $OturumDosyasi; if (-not $dosya) { $dosya = Codex-Oturum-Dosyasi $ErrYolu }
    if ($dosya) {
        $toplam = $null; $tepe = [long]0; $pencere = [long]0; $istek = 0; $haklar = $null
        foreach ($satir in [IO.File]::ReadAllLines($dosya, $Utf8)) {
            if ($satir -notmatch '"token_count"') { continue }
            $j = $null
            try { $j = $satir | ConvertFrom-Json } catch { continue }
            $p = $j.payload
            if (-not $p -or $p.type -ne 'token_count') { continue }
            if ($p.rate_limits) { $haklar = $p.rate_limits }
            if (-not $p.info) { continue }
            $istek++
            $toplam = $p.info.total_token_usage
            $son = $p.info.last_token_usage
            if ($son) { $t = Sayi $son.total_tokens; if ($t -le 0) { $t = (Sayi $son.input_tokens) + (Sayi $son.output_tokens) }; if ($t -gt $tepe) { $tepe = $t } }
            if ($p.info.model_context_window) { $pencere = Sayi $p.info.model_context_window }
        }
        if ($toplam) {
            $girisTum = Sayi $toplam.input_tokens; $okuma = Sayi $toplam.cached_input_tokens
            $kul = [ordered]@{
                giris = [Math]::Max([long]0, $girisTum - $okuma); onbellek_okuma = $okuma; onbellek_yazma = (Sayi $toplam.cache_write_input_tokens)
                cikis = (Sayi $toplam.output_tokens); baglam_tepe = $tepe; baglam_pencere = $pencere; istek = [long]$istek; maliyet_usd = [double]0; olcum = 'tam'
            }
        }
        if ($haklar -and -not $Gecmis) { try { Codex-Haklari-Kaydet $haklar } catch {} }
    }
    if (-not $kul) {
        # Oturum dosyası yoksa yalnızca codex'in yazdığı toplam
        $m = [regex]::Match((Son-Satirlar (Metin-Oku $ErrYolu) 40), '(?ms)tokens used\s*\r?\n\s*([\d.,]+)')
        if ($m.Success) {
            $t = Sayi ($m.Groups[1].Value -replace '[.,]', '')
            $kul = [ordered]@{ giris = [long]0; onbellek_okuma = [long]0; onbellek_yazma = [long]0; cikis = [long]0; toplam = $t
                baglam_tepe = [long]0; baglam_pencere = [long]0; istek = [long]0; maliyet_usd = [double]0; olcum = 'toplam' }
        }
    }
    return $kul
}
# Codex hesabının 5 saatlik / haftalık kullanım yüzdeleri (oturum dosyasından); panel gösterir
function Codex-Haklari-Kaydet($H) {
    $cevir = { param($x) if (-not $x) { return $null }; $s = $null; if ($x.resets_at) { $s = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.resets_at).LocalDateTime.ToString('o') }; return [ordered]@{ yuzde = [double]$x.used_percent; pencere_dk = [int]$x.window_minutes; sifirlanma = $s } }
    $yol = Join-Path $YolDurum 'arac-haklari.json'
    $d = Json-Oku $yol
    if (-not $d) { $d = New-Object psobject }
    Ayarla $d 'codex' ([pscustomobject][ordered]@{ guncelleme = (Simdi); plan = [string]$H.plan_type; bes_saat = (& $cevir $H.primary); haftalik = (& $cevir $H.secondary) })
    Json-Yaz $d $yol
}
# Claude hesabının 5 saatlik / haftalık kullanım oranları (CLI 2.1.3xx stream-json "rate_limit_event"); panel KPI olarak gösterir
function Claude-Haklari-Kaydet($H) {
    $cevir = { param($x) if (-not $x) { return $null }; $s = $null; if ($x.resetsAt) { $s = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x.resetsAt).LocalDateTime.ToString('o') }; return [ordered]@{ yuzde = [Math]::Round(100 * [double]$x.utilization, 1); sifirlanma = $s; durum = [string]$x.status } }
    $w = $H.unifiedWindows
    if (-not $w) { return }
    $yol = Join-Path $YolDurum 'arac-haklari.json'
    $d = Json-Oku $yol
    if (-not $d) { $d = New-Object psobject }
    Ayarla $d 'claude' ([pscustomobject][ordered]@{ guncelleme = (Simdi); bes_saat = (& $cevir $w.five_hour); haftalik = (& $cevir $w.seven_day); asim = [string]$H.overageStatus })
    Json-Yaz $d $yol
}
function Kullanim-Kaydet([string]$Rol, [string]$Etiket, $Giris, $R, [int]$IstemKarakter) {
    try {
        if (-not (Test-Path -LiteralPath $YolKullanim)) { New-Item -ItemType Directory -Force $YolKullanim | Out-Null }
        $k = $R.kullanim
        $kayit = [ordered]@{
            zaman = (Simdi); gorev = [string]$script:AktifGorev; rol = $Rol; etiket = $Etiket
            arac = [string]$Giris.arac; model = [string]$Giris.model; basarili = [bool]$R.basarili; sure_sn = [int]$R.sure_sn; istem_karakter = $IstemKarakter
        }
        foreach ($a in @('giris', 'onbellek_okuma', 'onbellek_yazma', 'cikis', 'baglam_tepe', 'baglam_pencere', 'istek')) {
            $v = [long]0; if ($k -and $k.Contains($a)) { $v = Sayi $k[$a] }
            $kayit[$a] = $v
        }
        if ($k -and $k.Contains('model_gercek') -and $k['model_gercek']) { $kayit.model_gercek = [string]$k['model_gercek'] }
        $kayit.toplam = $kayit.giris + $kayit.onbellek_okuma + $kayit.onbellek_yazma + $kayit.cikis
        if ($k -and $k.Contains('toplam') -and (Sayi $k['toplam']) -gt $kayit.toplam) { $kayit.toplam = Sayi $k['toplam'] }
        if ($k -and $k.Contains('maliyet_usd') -and [double]$k['maliyet_usd'] -gt 0) { $kayit.maliyet_usd = [Math]::Round([double]$k['maliyet_usd'], 4) }
        $kayit.olcum = 'yok'; if ($k -and $k.Contains('olcum')) { $kayit.olcum = [string]$k['olcum'] }
        if (-not $R.basarili -and $R.hata) { $kayit.hata = Kisalt ([string]$R.hata) 160 }
        $yol = Join-Path $YolKullanim ('kullanim-{0}.jsonl' -f (Get-Date).ToString('yyyyMM'))
        [void](Satir-Ekle $yol ($kayit | ConvertTo-Json -Compress))
    } catch { Gunluk "Kullanım kaydı yazılamadı: $($_.Exception.Message)" 'UYARI' }
}

# ---------------------------------------------------------------- Claude
function Claude-Hata-Isle([string]$Hata, [string]$Model = '') {
    if ($Hata -match '(?i)does not support this model|claude_code_version_too_old|model.{0,40}(not found|not available|does not exist|invalid)|not_found_error') {
        # CLI bu modeli çalıştıramıyor: yalnızca bu modeli kilitle, zincirdeki sonraki model denensin
        Kilit-Koy ("claude:{0}" -f $Model) (Get-Date).AddHours(6) 'model bu Claude CLI sürümünde kullanılamıyor'
        Bildir -Baslik "Claude modeli kullanılamıyor: $Model" -Metin ("Claude CLI bu modeli çalıştıramıyor; 6 saat atlanacak. CLI'yi güncellemek gerekebilir (claude update). Ayrıntı: {0}" -f (Kisalt $Hata 120)) -Anahtar "claude-model-$Model" -AralikDk 720
    } elseif ($Hata -match '(?i)\b401\b|authenticat|oauth|not logged in|invalid api key') {
        Kilit-Koy 'claude' (Get-Date).AddHours(2) 'Claude CLI girişi geçersiz'
        Bildir -Baslik 'Claude girişi gerekli' -Metin 'Arka plandaki Claude CLI oturumu geçersiz. Bir terminalde "claude auth login" çalıştır. O zamana kadar Claude''un işlerini Codex yapıyor.' -Anahtar 'claude-giris' -Onem 'yuksek' -AralikDk 720
    } elseif ($Hata -match '(?i)usage limit|limit reached|hit your limit|rate.?limit|\b429\b|quota|overloaded|\b529\b') {
        $bitis = (Get-Date).AddMinutes(60)
        $m = [regex]::Match($Hata, '\|(\d{10})')
        if ($m.Success) { $bitis = [DateTimeOffset]::FromUnixTimeSeconds([int64]$m.Groups[1].Value).LocalDateTime.AddMinutes(2) }
        Kilit-Koy 'claude' $bitis 'Claude kullanım sınırı'
        Bildir -Baslik 'Claude limiti doldu' -Metin ("Claude {0}'e kadar dinleniyor; işi Codex devraldı." -f $bitis.ToString('HH:mm')) -Anahtar 'claude-limit' -AralikDk 180
    }
}
function Claude-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false) {
    $araclar = 'Read,Glob,Grep'; $mod = 'dontAsk'
    if ($Yazabilir) { $araclar = 'Read,Glob,Grep,Edit,Write'; $mod = 'acceptEdits' }
    $zaman = [int]$Ayar.zaman_asimi_dk.claude
    # stream-json: her yanıtın token kullanımı ayrı satırda gelir (istek başına bağlam doluluğu için); son satır sonuçtur
    $komut = (Q $Ayar.claude.exe) + " -p --output-format stream-json --verbose --no-session-persistence --model $($G.model)"
    if ($TamYetki) {
        # Altyapı rolleri (altyapi.ps1): kullanıcı tam yetki verdi; tüm araçlar, izin sorulmaz
        $komut += ' --permission-mode bypassPermissions'
        if ($Ayar.zaman_asimi_dk.altyapi) { $zaman = [int]$Ayar.zaman_asimi_dk.altyapi }
    } else { $komut += " --tools $araclar --allowedTools $araclar --permission-mode $mod" }
    if ($G.efor) { $komut += " --effort $($G.efor)" }
    $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'claude'
    $ham = Metin-Oku $Out
    $c = $null
    try { $c = Claude-Cikti-Coz $ham } catch { $c = [pscustomobject]@{ sonuc = $null; kullanim = $null } }
    if ($s.iptal) { return (Sonuc $false '' 'görev iptal edildi; ajan durduruldu' $s $c.kullanim) }
    if ($s.zaman_asimi) { return (Sonuc $false '' "zaman aşımı ($zaman dk)" $s $c.kullanim) }
    $j = $c.sonuc
    if (-not $j) {
        $h = "çıktı çözülemedi (kod $($s.kod)): " + (Kisalt ((Son-Satirlar (Metin-Oku $Err) 6) + ' ' + (Son-Satirlar $ham 3)) 300)
        Claude-Hata-Isle $h ([string]$G.model)
        return (Sonuc $false '' $h $s $c.kullanim)
    }
    if ($j.is_error -or $j.subtype -ne 'success') {
        $h = Kisalt ("{0} {1}" -f $j.subtype, $j.result) 300
        Claude-Hata-Isle $h ([string]$G.model)
        return (Sonuc $false '' $h $s $c.kullanim)
    }
    return (Sonuc $true ([string]$j.result) '' $s $c.kullanim)
}

# ---------------------------------------------------------------- Codex (ChatGPT)
function Codex-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$SonMesaj, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false) {
    $exe = Codex-Exe
    $kum = 'read-only'; if ($Yazabilir) { $kum = 'workspace-write' }
    $zaman = [int]$Ayar.zaman_asimi_dk.codex
    if ($TamYetki) {
        # Altyapı rolleri (altyapi.ps1): sandbox yok, ağ açık
        $kum = 'danger-full-access'
        if ($Ayar.zaman_asimi_dk.altyapi) { $zaman = [int]$Ayar.zaman_asimi_dk.altyapi }
    }
    $efor = 'high'; if ($G.efor) { $efor = $G.efor }
    if (Test-Path -LiteralPath $SonMesaj) { Remove-Item -LiteralPath $SonMesaj -Force }
    $komut = (Q $exe) + " exec --skip-git-repo-check -s $kum -C $(Q $Klasor) -o $(Q $SonMesaj) -m $($G.model) -c model_reasoning_effort=$efor -"
    $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'codex'
    $kul = $null
    try { $kul = Codex-Kullanim $Err } catch {}
    if ($s.iptal) { return (Sonuc $false '' 'görev iptal edildi; ajan durduruldu' $s $kul) }
    if ($s.zaman_asimi) { return (Sonuc $false '' "zaman aşımı ($zaman dk)" $s $kul) }
    $metin = Metin-Oku $SonMesaj
    if ($s.kod -ne 0 -or -not $metin.Trim()) {
        # stderr tüm oturumu (istem dahil) içerir; sınıflandırma için yalnızca kuyruğa bak
        $kuyruk = Son-Satirlar ((Metin-Oku $Err) + "`n" + (Metin-Oku $Out)) 25
        if ($kuyruk -match '(?i)usage limit|rate.?limit|\b429\b|quota|exceeded your') {
            Kilit-Koy ("codex:{0}" -f $G.model) (Get-Date).AddMinutes(60) 'Codex kullanım sınırı'
        } elseif ($kuyruk -match '(?i)model.{0,40}(not found|does not exist|not supported|unsupported|invalid)') {
            Kilit-Koy ("codex:{0}" -f $G.model) (Get-Date).AddHours(6) 'model kullanılamıyor'
        } elseif ($kuyruk -match '(?i)\b401\b|unauthorized|not logged in|please log ?in') {
            Kilit-Koy 'codex' (Get-Date).AddHours(2) 'Codex girişi geçersiz'
            Bildir -Baslik 'Codex girişi gerekli' -Metin 'Codex/ChatGPT oturumu geçersiz görünüyor. Codex uygulamasını açıp giriş yap.' -Anahtar 'codex-giris' -Onem 'yuksek' -AralikDk 720
        }
        return (Sonuc $false '' ("kod {0}: {1}" -f $s.kod, (Kisalt (Son-Satirlar $kuyruk 4) 300)) $s $kul)
    }
    return (Sonuc $true $metin '' $s $kul)
}

# ---------------------------------------------------------------- Gemini (isteğe bağlı; GEMINI_API_KEY gerektirir)
function Gemini-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false) {
    $mod = 'plan'; if ($Yazabilir) { $mod = 'auto_edit' }
    if ($TamYetki) { $mod = 'yolo' }
    $komut = (Q (Gemini-Exe)) + " -p `"`" --approval-mode $mod --skip-trust -o json"
    if ($G.model) { $komut += " -m $($G.model)" }
    $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk ([int]$Ayar.zaman_asimi_dk.gemini) -Etiket 'gemini'
    if ($s.iptal) { return (Sonuc $false '' 'görev iptal edildi; ajan durduruldu' $s) }
    if ($s.zaman_asimi) { return (Sonuc $false '' 'zaman aşımı' $s) }
    $j = $null
    try { $j = (Metin-Oku $Out) | ConvertFrom-Json } catch {}
    if ($s.kod -ne 0 -or -not $j -or -not $j.response) {
        $kuyruk = Son-Satirlar (Metin-Oku $Err) 6
        if ($kuyruk -match '(?i)IneligibleTier|authenticat|\b401\b|api key') { Kilit-Koy 'gemini' (Get-Date).AddHours(12) 'Gemini girişi/katmanı uygun değil' }
        elseif ($kuyruk -match '(?i)\b429\b|quota|rate.?limit') { Kilit-Koy ("gemini:{0}" -f $G.model) (Get-Date).AddMinutes(60) 'Gemini kota sınırı' }
        return (Sonuc $false '' ("kod {0}: {1}" -f $s.kod, (Kisalt $kuyruk 300)) $s)
    }
    return (Sonuc $true ([string]$j.response) '' $s)
}

# ---------------------------------------------------------------- ekip içi yardımlaşma (ayarlar.json > yardimlasma; akış yardim.ps1)
# Görev adımlarında çalışan ajan, kendi yapamayacağı ama ekipte başkasının yapabileceği bir şeye ihtiyaç duyarsa
# çıktısının sonuna ```yardim {json}``` bloğu ekler; adım başarısız sayılmaz, Engineering Manager isteği uygun çalışana verir.
function Yardim-Uygun-mu([string]$Rol, [string]$Etiket) {
    if (-not $script:AktifGorev) { return $false }
    $a = $Ayar.yardimlasma
    if (-not $a -or -not $a.etkin) { return $false }
    if ($Rol -eq 'sorun-giderici') { return $false }
    if (@('yardim', 'cozum', 'yonlendirme', 'ise_alim') -contains $Etiket -or $Etiket -like 'sohbet*') { return $false }
    if ($Rol -eq 'lider' -and $Etiket -ne 'kabul') { return $false }   # Engineering Manager planda ön işleri "YARDIM:" satırlarıyla ister
    return $true
}
function Yardim-Talimati-Metni {
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    $satirlar = @()
    foreach ($u in @($k.uyeler)) {
        if ($u -and $u.anahtar -and @('lider', 'sorun-giderici') -notcontains [string]$u.anahtar) { $satirlar += ('- {0} ({1}): {2}' -f $u.anahtar, $u.ad, (Kisalt ([string]$u.uzmanlik) 120)) }
    }
    $metin = @'


---

# EKİPTEN YARDIM İSTEME

Bu işi yaparken senin yapamayacağın ama ekipte başka birinin yapabileceği bir şeye ihtiyaç duyarsan işi yarım bırakıp
başarısız sayma, reddetme: Engineering Managerʼdan yardım iste. Örnekler: yazılım / SDK / araç kurulumu, emülatör ya da sunucu hazırlığı,
ağ / port ayarı (sistem, ag); uygulamayı gerçekten çalıştırıp test etmek ya da kullanıcı testi (tester); tasarım ya da görsel
varlık; güvenlik ya da mimari görüşü; yalnızca kullanıcının verebileceği bir bilgi ya da karar.
Özellikle DUZELT / RET vermeden önce düşün: eksik olan şey işi yapanın değil başka birinin uzmanlığıysa yardım iste.
Engineering Manager isteğini uygun kişiye verir; yardım gelince bu adım, gelen sonuçla ("EKİPTEN GELEN YARDIM") yeniden çalışır.
Yapabildiğin kısmı yine yap. Yardım istemek için çıktının EN SONUNA şu bloğu ekle (gerekmiyorsa ekleme):

```yardim
{"ne": "tam olarak ne yapılmalı", "neden": "neden sen yapamıyorsun, neden gerekli", "kim": "önerdiğin kadro anahtarı ya da boş", "kabul": ["yardımın tamam sayılma ölçütü"]}
```

Bu ekipte "kullanıcı testi", "gerçek kullanıcı", "N kullanıcıdan M'i" gibi kabul ölçütlerini Test
Uzmanının (tester) simüle kullanıcı testi karşılar: bu yüzden işi reddetme, test raporu yoksa tester'dan yardım iste.

Ekip:
'@
    return $metin + ($satirlar -join "`n")
}
# Görev adımlarında istemin sonuna: bu görevde daha önce gelen yardımlar + (uygunsa) yardım isteme talimatı
function Yardim-Istem-Ekle([string]$Rol, [string]$Etiket, [string]$Istem) {
    if (-not $script:AktifGorev) { return $Istem }
    $a = $Ayar.yardimlasma
    if (-not $a -or -not $a.etkin) { return $Istem }
    if ($Etiket -like 'sohbet*' -or $Etiket -eq 'yonlendirme') { return $Istem }
    $ek = ''
    $s = Metin-Oku (Join-Path (Join-Path $YolGorev $script:AktifGorev) 'yardim-sonuclari.md')
    if ($s.Trim()) {
        if ($s.Length -gt 8000) { $s = '…' + $s.Substring($s.Length - 8000) }
        $ek += "`n`n---`n`n# EKİPTEN GELEN YARDIM (bu işte daha önce istenen yardımların sonuçları; bunları kullan)`n`n" + $s.Trim()
    }
    if (Yardim-Uygun-mu $Rol $Etiket) { $ek += (Yardim-Talimati-Metni) }
    return ($Istem + $ek)
}
function Yardim-Blogu-Oku([string]$Metin) {
    $m = [regex]::Match([string]$Metin, '```yardim[ \t]*\r?\n\s*(\{[\s\S]*?\})\s*```')
    if (-not $m.Success) { return $null }
    $j = $null
    try { $j = $m.Groups[1].Value | ConvertFrom-Json } catch { return $null }
    $ne = ([string]$j.ne).Trim()
    if (-not $ne -or $ne -eq 'tam olarak ne yapılmalı') { return $null }
    return $j
}

# ---------------------------------------------------------------- rol çağırma (yedek zinciriyle)
function Ajan-Cagir {
    param(
        [Parameter(Mandatory)][string]$Rol,
        [Parameter(Mandatory)][string]$Istem,
        [Parameter(Mandatory)][string]$Klasor,
        [Parameter(Mandatory)][string]$KayitKlasoru,
        [Parameter(Mandatory)][string]$Etiket,
        [switch]$Yazabilir,
        [string[]]$Haric = @(),     # bu araçları atla (ör. Code Reviewer Software Developerʼla aynı model olmasın)
        [switch]$TamYetki           # altyapı rolleri: sandbox'sız, izin sormadan (altyapı görev kapsamı)
    )
    if (-not (Test-Path -LiteralPath $KayitKlasoru)) { New-Item -ItemType Directory -Force $KayitKlasoru | Out-Null }
    $Istem = Yardim-Istem-Ekle $Rol $Etiket $Istem
    $notlar = @()
    $gorevId = [string]$script:AktifGorev
    $iptalHata = 'görev kullanıcı tarafından iptal edildi'
    foreach ($g in @($Ayar.roller.$Rol)) {
        # İptal edilen görevde yedek zincirdeki sonraki araca geçme
        if ($script:IptalIzleme -and $gorevId -and (Gorev-Iptal-mi $gorevId)) {
            Gunluk "$Rol çağrısı yapılmadı: görev $gorevId iptal edildi [$Etiket]" 'UYARI'
            return [pscustomobject]@{ basarili = $false; metin = ''; hata = $iptalHata; sure_sn = 0; arac = ''; model = ''; iptal = $true }
        }
        $kimlik = "{0}/{1}" -f $g.arac, $g.model
        if ($Haric -contains $kimlik) { $notlar += "${kimlik}: atlandı"; continue }
        $neden = Arac-Uygun $g
        if ($neden) { $notlar += "${kimlik}: $neden"; continue }
        $ad = '{0}-{1}-{2}' -f $Etiket, $g.arac, ([string]$g.model -replace '[^A-Za-z0-9._-]', '_')
        $istemYolu = Join-Path $KayitKlasoru "$ad.istem.md"
        $out = Join-Path $KayitKlasoru "$ad.out.txt"
        $err = Join-Path $KayitKlasoru "$ad.err.txt"
        $son = Join-Path $KayitKlasoru "$ad.son.md"
        Metin-Yaz $istemYolu $Istem
        Sayac-Artir ([string]$g.arac)
        $script:AktifAdim = "$Etiket ($kimlik)"
        Kalp 'ajan'
        Gunluk "$Rol -> $kimlik başlıyor [$($script:AktifGorev) / $Etiket]"
        switch ($g.arac) {
            'claude' { $r = Claude-Calistir $g $istemYolu $out $err $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) }
            'codex'  { $r = Codex-Calistir  $g $istemYolu $out $err $son $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) }
            'gemini' { $r = Gemini-Calistir $g $istemYolu $out $err $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) }
        }
        Kullanim-Kaydet $Rol $Etiket $g $r $Istem.Length
        if ($r.basarili) {
            $r.arac = [string]$g.arac; $r.model = [string]$g.model
            Gunluk "$Rol -> $kimlik bitti ($($r.sure_sn) sn)"
            if ($script:IptalIzleme -and $gorevId -and (Gorev-Iptal-mi $gorevId)) {
                # Ajan iptalden sonra bitti: adım bu sonuçla ilerlemesin (soru, aktarma, e-posta, yeni tur...)
                Gunluk "$Rol -> $kimlik sonucu kullanılmadı: görev $gorevId ajan çalışırken iptal edildi" 'UYARI'
                return [pscustomobject]@{ basarili = $false; metin = ''; hata = $iptalHata; sure_sn = $r.sure_sn; arac = $r.arac; model = $r.model; iptal = $true }
            }
            # Ekip içi yardım isteği: adım ilerlemesin; Adim-Basarisiz bunu başarısızlık saymaz, Engineering Managerʼa iletir (yardim.ps1)
            if (Yardim-Uygun-mu $Rol $Etiket) {
                $y = Yardim-Blogu-Oku $r.metin
                if ($y) {
                    $script:YardimIstegi = [pscustomobject]@{ gorev = $gorevId; rol = $Rol; etiket = $Etiket; arac = $kimlik; istek = $y; metin = $r.metin }
                    Gunluk "$Rol ekip içi yardım istedi [$gorevId / $Etiket]: $(Kisalt ([string]$y.ne) 160)"
                    return [pscustomobject]@{ basarili = $false; metin = $r.metin; hata = "yardım istendi: $(Kisalt ([string]$y.ne) 200)"; sure_sn = $r.sure_sn; arac = $r.arac; model = $r.model; yardim = $y }
                }
            }
            return $r
        }
        Gunluk "$Rol -> $kimlik başarısız: $($r.hata)" 'UYARI'
        $notlar += "${kimlik}: $($r.hata)"
    }
    return [pscustomobject]@{ basarili = $false; metin = ''; hata = ($notlar -join ' | '); sure_sn = 0; arac = ''; model = '' }
}

# ---------------------------------------------------------------- bildirimler
function Toast-Goster([string]$Baslik, [string]$Metin) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $rapor = 'file:///' + ((Join-Path $YolRapor 'son-rapor.html') -replace '\\', '/')
        $e = { param($x) [Security.SecurityElement]::Escape([string]$x) }
        $xml = '<toast activationType="protocol" launch="{0}"><visual><binding template="ToastGeneric"><text>{1}</text><text>{2}</text></binding></visual></toast>' -f (& $e $rapor), (& $e $Baslik), (& $e $Metin)
        $d = New-Object Windows.Data.Xml.Dom.XmlDocument
        $d.LoadXml($xml)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($d))
    } catch { Gunluk "Masaüstü bildirimi gösterilemedi: $($_.Exception.Message)" 'UYARI' }
}
function Ntfy-Gonder([string]$Baslik, [string]$Metin, [string]$Onem) {
    try {
        $tel = $Ayar.bildirim.telefon
        $oncelik = 3; if ($Onem -eq 'yuksek') { $oncelik = 4 }
        $govde = [ordered]@{ topic = [string]$tel.ntfy_konu; title = $Baslik; message = $Metin; tags = @('robot'); priority = $oncelik } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri ([string]$tel.ntfy_sunucu).TrimEnd('/') -Body ([Text.Encoding]::UTF8.GetBytes($govde)) `
            -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 -UseBasicParsing | Out-Null
    } catch { Gunluk "Telefon bildirimi gönderilemedi: $($_.Exception.Message)" 'UYARI' }
}
function Bildir {
    param(
        [Parameter(Mandatory)][string]$Baslik,
        [Parameter(Mandatory)][string]$Metin,
        [string]$Anahtar = '',
        [ValidateSet('normal', 'yuksek')][string]$Onem = 'normal',
        [int]$AralikDk = -1
    )
    if ($AralikDk -lt 0) { $AralikDk = [int]$Ayar.bildirim.ayni_bildirim_arasi_dk }
    if ($Anahtar) {
        $zy = Join-Path $YolDurum 'bildirim_zamanlari.json'
        $z = Json-Oku $zy
        if (-not $z) { $z = New-Object psobject }
        if ($z.PSObject.Properties[$Anahtar] -and ((Get-Date) - [datetime]$z.$Anahtar).TotalMinutes -lt $AralikDk) {
            Gunluk "Bildirim bastırıldı (aynı konu, $AralikDk dk içinde): $Baslik"
            return
        }
        Ayarla $z $Anahtar (Simdi)
        Json-Yaz $z $zy
    }
    Gunluk "BİLDİRİM: $Baslik | $Metin"
    try {
        $satir = [ordered]@{ zaman = (Simdi); baslik = $Baslik; metin = $Metin; onem = $Onem } | ConvertTo-Json -Compress
        [IO.File]::AppendAllText((Join-Path $YolDurum 'bildirimler.jsonl'), $satir + "`n", $Utf8)
    } catch {}
    if ($Ayar.bildirim.masaustu) { Toast-Goster $Baslik $Metin }
    $tel = $Ayar.bildirim.telefon
    if ($tel -and $tel.kanal -eq 'ntfy' -and $tel.ntfy_konu) { Ntfy-Gonder $Baslik $Metin $Onem }
}

# ---------------------------------------------------------------- görev kayıtları
function Gorev-Klasoru([string]$Id) { Join-Path $YolGorev $Id }
function Gorev-Oku([string]$Id) { Json-Oku (Join-Path (Gorev-Klasoru $Id) 'durum.json') }
function Gorev-Kaydet($G) {
    Ayarla $G 'guncelleme' (Simdi)
    Json-Yaz $G (Join-Path (Gorev-Klasoru $G.id) 'durum.json')
}
# Görevin diskteki güncel kaydı: adım sürerken kullanıcı panelden / durum.ps1 ile değiştirmiş olabilir.
# Dosya o an yazılıyorsa kısa aralıklarla yeniden dener; okunamazsa $null döner (hata fırlatmaz).
function Gorev-Diskten([string]$Id) {
    if (-not $Id) { return $null }
    $yol = Join-Path (Gorev-Klasoru $Id) 'durum.json'
    for ($i = 0; $i -lt 5; $i++) {
        try { return (Json-Oku $yol) } catch { Start-Sleep -Milliseconds 200 }
    }
    return $null
}
function Gorev-Iptal-mi([string]$Id) {
    $d = Gorev-Diskten $Id
    return [bool]($d -and [string]$d.asama -eq 'iptal')
}
function Gorevleri-Listele {
    $liste = @()
    foreach ($d in (Get-ChildItem -LiteralPath $YolGorev -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $g = Json-Oku (Join-Path $d.FullName 'durum.json')
        if ($g) { $liste += $g }
    }
    return $liste
}
$script:AsamaAdlari = @{
    yeni = 'Sırada'; plan = 'Planlanıyor'; gelistirme = 'Geliştiriliyor'; kontrol = 'Kontrol ediliyor'
    denetim = 'Denetleniyor'; kabul = 'Engineering Manager onayında'; tamamla = 'Commit ediliyor'; tamam = 'Tamamlandı'
    takildi = 'Takıldı'; bekliyor_kullanici = 'Senden yanıt bekliyor'; iptal = 'İptal'
    yardim = 'Engineering Managerʼda (yardım isteği)'; yardim_bekliyor = 'Ekipten yardım bekliyor'
}
function Asama-Adi([string]$A) { if ($AsamaAdlari.ContainsKey($A)) { return $AsamaAdlari[$A] }; return $A }
