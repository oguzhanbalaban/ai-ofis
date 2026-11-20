<#
ortak.ps1 - AI Ekip ortak işlevleri (diğer betikler dot-source eder: . "$PSScriptRoot\ortak.ps1")
Windows PowerShell 5.1 uyumludur. Dosya UTF-8 BOM ile kaydedilmelidir (Türkçe karakterler için).
#>
$ErrorActionPreference = 'Stop'
$script:Utf8       = New-Object Text.UTF8Encoding $false
# ---------------------------------------------------------------- şirket binası (katlar)
# Kod tek (bu klasör); her kat (ofis) kendi veri klasöründe çalışır: kadro.json, ayarlar.json, projeler.json, gorevler, durum, calisma...
# Kat AIEKIP_KAT ortam değişkeninden okunur (boşsa 'ana' = AI Ekip Ofisi, verisi bu klasörde). Katlar katlar.json'da tanımlıdır.
$script:KodKok = $PSScriptRoot
# Dağıtılan JSON şablonları değişmez; kişisel ayarlar *.yerel.json'da (kod kökü ve katlar için)
. (Join-Path $PSScriptRoot 'yapilandirma.ps1')
function Katlar-Oku {
    $liste = @()
    $y = Join-Path $script:KodKok 'katlar.json'
    if ([IO.File]::Exists($y)) {
        try { $j = [IO.File]::ReadAllText($y, $script:Utf8) | ConvertFrom-Json; $liste = @($j.katlar | Where-Object { $_ -and ([string]$_.id) -match '^[a-z0-9][a-z0-9-]{0,30}$' }) } catch {}
    }
    if (-not @($liste | Where-Object { [string]$_.id -eq 'ana' }).Count) {
        $liste = @([pscustomobject]@{ id = 'ana'; ad = 'AI Ekip Ofisi'; kisa_ad = 'AI Ekip'; kat_no = 0; tur = 'ekip'; kok = '' }) + $liste
    }
    return $liste
}
function Kat-Bul([string]$Id) { foreach ($k in @(Katlar-Oku)) { if ([string]$k.id -eq $Id) { return $k } }; return $null }
function Kat-Koku($K) {
    if (-not $K -or [string]$K.id -eq 'ana' -or -not ([string]$K.kok).Trim()) { return $script:KodKok }
    $y = ([string]$K.kok).Trim()
    if (-not [IO.Path]::IsPathRooted($y)) { $y = Join-Path $script:KodKok $y }
    return [IO.Path]::GetFullPath($y)
}
$script:KatKimligi = ([string]$env:AIEKIP_KAT).Trim().ToLowerInvariant()
if (-not $script:KatKimligi) { $script:KatKimligi = 'ana' }
$script:Kat = Kat-Bul $script:KatKimligi
if (-not $script:Kat) { throw "Bilinmeyen kat: '$($script:KatKimligi)' (katlar.json)" }
if ($script:KatKimligi -ne 'ana' -and [string]$script:Kat.tur -and [string]$script:Kat.tur -ne 'ekip') { throw "'$($script:KatKimligi)' katı bir ekip katı değil (tur: $($script:Kat.tur)); ekip motoru çalışmaz" }
$script:Kok        = Kat-Koku $script:Kat
if (-not [IO.Directory]::Exists($script:Kok)) { [void][IO.Directory]::CreateDirectory($script:Kok) }
$script:YolGorev   = Join-Path $Kok 'gorevler'
$script:YolDurum   = Join-Path $Kok 'durum'
$script:YolGunluk  = Join-Path $Kok 'gunluk'
$script:YolRapor   = Join-Path $Kok 'raporlar'
$script:YolCalisma = Join-Path $Kok 'calisma'
# İstem şablonları kodla gelir (istemler); bir kat aynı adlı dosyayı kendi istemler klasörüne koyarak değiştirebilir
$script:YolIstem   = Join-Path $KodKok 'istemler'
$script:YolKatIstem = Join-Path $Kok 'istemler'
foreach ($d in @($YolGorev, $YolDurum, $YolGunluk, $YolRapor, $YolCalisma)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
}
if (-not (Test-Path variable:script:Konsol)) { $script:Konsol = $false }
$script:AktifGorev = ''
$script:AktifAdim  = ''
# Kök neden analizi iptal edilmiş görevler üzerinde çalışır: o sırada iptal izlemesi kapatılır (cozucu.ps1 > Kok-Neden-Belirle)
$script:IptalIzleme = $true
$script:YardimIstegi = $null   # son ajan çağrısının ekip içi yardım isteği (yardim.ps1 > Yardim-Istegi-Kaydet işler)
# Kullanıcının "Devral" komutu: bu adımda { rol = devralan çalışan } (komut.ps1 > Rol-Degisimi-Kur; Ajan-Cagir uygular)
$script:RolDegisimi = $null
# Bu süreç bir paralel hatsa yürüttüğü görev (paralel.ps1 kurar; Gorev-Iptal-mi "paralel-durdur" dosyasına bakar)
$script:ParalelGorev = ''
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ---------------------------------------------------------------- dosya / json
function Metin-Oku([string]$Yol) {
    if (-not $Yol -or -not (Test-Path -LiteralPath $Yol)) { return '' }
    # Paylaşımlı okuma: dosyayı başka bir süreç yazmak için açık tutsa da okunur. Örn. ajanın err / out kaydının tanıtıcısını
    # devralıp bırakmayan adb sunucusu ([IO.File]::ReadAllText bu durumda "dosya kullanımda" hatası verip döngüyü kilitliyordu)
    $fs = New-Object IO.FileStream($Yol, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $sr = New-Object IO.StreamReader($fs, $Utf8, $true)
        return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
}
function Metin-Yaz([string]$Yol, [string]$Metin) {
    # Süreç başına geçici dosya ve kısa yeniden deneme: ana döngü ile paralel hatlar (paralel.ps1) aynı dosyaya yazabilir
    $tmp = "$Yol.$PID.tmp"
    for ($i = 0; ; $i++) {
        try {
            [IO.File]::WriteAllText($tmp, $Metin, $Utf8)
            if (Test-Path -LiteralPath $Yol) { [IO.File]::Replace($tmp, $Yol, "$Yol.bak") }
            else { [IO.File]::Move($tmp, $Yol) }
            return
        } catch [IO.IOException], [UnauthorizedAccessException] {
            if ($i -ge 6) { try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch {}; throw }
            Start-Sleep -Milliseconds (50 * ($i + 1))
        }
    }
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
# Katın kendi dosyası varsa o, yoksa kodla gelen (ör. kadro istemleri: istemler\kadro\x.md)
function Kok-Dosyasi([string]$Goreli) {
    if (-not $Goreli) { return '' }
    if ([IO.Path]::IsPathRooted($Goreli)) { return $Goreli }
    $k = Join-Path $Kok $Goreli
    if ($Kok -ne $KodKok -and -not (Test-Path -LiteralPath $k)) { return (Join-Path $KodKok $Goreli) }
    return $k
}
# Kodla gelen istemler ana katın unvanlarını kullanır; alt katta kadro unvanları farklıysa ajanın istemi çevrilir (Ajan-Cagir)
$script:VarsayilanUnvanlar = [ordered]@{ lider = 'Engineering Manager'; 'sorun-giderici' = 'Incident Manager'; gelistirici = 'Full-Stack Developer'; denetci = 'Code Reviewer'
    sistem = 'System Administrator'; ag = 'Network Engineer'; tester = 'QA Engineer'; mimar = 'Solution Architect'; guvenlik = 'Security Engineer' }
function Unvan-Uyarla([string]$Metin) {
    if ($KatKimligi -eq 'ana' -or -not $Metin) { return $Metin }
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    $es = New-Object 'Collections.Generic.Dictionary[string,string]'
    foreach ($a in $VarsayilanUnvanlar.Keys) {
        $u = ''; foreach ($x in @($k.uyeler)) { if ($x -and [string]$x.anahtar -eq $a -and $x.ad) { $u = [string]$x.ad } }
        $v = [string]$VarsayilanUnvanlar[$a]
        if (-not $u -or $u -eq $v) { continue }
        $es[$v] = $u; $es[$v.ToUpperInvariant()] = $u.ToUpperInvariant()
        # Katın kendi unvanı (ör. "BI QA Engineer" içinde "QA Engineer") yeniden çevrilmesin: kendisine eşlenir, uzun olan önce denenir
        $es[$u] = $u; $es[$u.ToUpperInvariant()] = $u.ToUpperInvariant()
    }
    if (-not @($es.Keys | Where-Object { $es[$_] -cne $_ }).Count) { return $Metin }
    $desen = (@($es.Keys | Sort-Object { $_.Length } -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|')
    $h = $es
    return [regex]::Replace($Metin, $desen, [Text.RegularExpressions.MatchEvaluator]{ param($m) $h[$m.Value] }.GetNewClosure())
}
function Ofis-Adi { if ($script:Kat -and $script:Kat.ad) { return [string]$script:Kat.ad }; return 'AI Ekip' }
# Adlandırılmış kilitler / görev kimlikleri katlar arasında karışmasın: ana katta boş, diğerlerinde "_<kat>"
function Kat-Soneki { if ($script:KatKimligi -eq 'ana') { return '' }; return '_' + ($script:KatKimligi -replace '[^a-z0-9]', '_') }
# Kat kapalı mı: DURDUR dosyası "Ofis kapatıldı" ile başlıyorsa (panel / Ofis Kontrol böyle yazar). Yalnız duraklatma kapalı sayılmaz.
function Kat-Kapali-mi([string]$KatKoku = '') {
    if (-not $KatKoku) { $KatKoku = $Kok }
    $d = Join-Path $KatKoku 'DURDUR'
    if (-not (Test-Path -LiteralPath $d)) { return $false }
    return ((Metin-Oku $d).TrimStart([char]0xFEFF).StartsWith('Ofis kapatıldı'))
}
function Kat-Dongu-Kilidi([string]$Id) { if ($Id -eq 'ana') { return 'Local\AIEkipDongusu' }; return 'Local\AIEkipDongusu_' + ($Id -replace '[^a-z0-9]', '_') }
function Kat-Dongusu-Calisiyor-mu([string]$Id) {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting((Kat-Dongu-Kilidi $Id), [ref]$m)) { $m.Dispose(); return $true }
    return $false
}
function Kat-Dongusu-Baslat([string]$Id) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f $ps, (Join-Path $KodKok 'baslat.ps1')
    $eski = $env:AIEKIP_KAT; $env:AIEKIP_KAT = $Id
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg -WorkingDirectory $KodKok -WindowStyle Hidden | Out-Null }
    finally { $env:AIEKIP_KAT = $eski }
}
# Bina bekçisi (ana katın baslat.ps1'i her bekçi tetiğinde çağırır): açık alt katların döngüsü yoksa ya da kalbi durmuşsa başlatır;
# donmuş döngüyü o katın baslat.ps1'i (kalp yaşına bakarak) kendisi sonlandırır.
function Bina-Bekcisi {
    foreach ($k in @(Katlar-Oku)) {
        $id = [string]$k.id
        if ($id -eq 'ana' -or ([string]$k.tur -and [string]$k.tur -ne 'ekip')) { continue }
        $kk = Kat-Koku $k
        if (-not (Test-Path -LiteralPath (Join-Path $kk 'ayarlar.json'))) { continue }
        if (Kat-Kapali-mi $kk) { continue }
        $calisiyor = Kat-Dongusu-Calisiyor-mu $id
        if ($calisiyor) {
            $kalp = Json-Oku (Join-Path $kk 'durum\kalp.json')
            $yas = 9999; try { $yas = ((Get-Date) - [datetime]$kalp.zaman).TotalMinutes } catch {}
            if ($yas -lt [double]$Ayar.dongu.bekci_dk) { continue }
        }
        Gunluk "Bina bekçisi: $($k.ad) katının döngüsü başlatılıyor"
        try { Kat-Dongusu-Baslat $id } catch { Gunluk "Bina bekçisi: $id başlatılamadı: $($_.Exception.Message)" 'UYARI' }
    }
}

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
    # Alt katlar ana katın ayarlarını miras alır: katın dosyasında olmayan üst düzey bloklar (ör. paralel, puanlama, model_katalogu)
    # ana kattan gelir. Rol isteyen katmanlar (Product Manager, CTO, Outsource Consultant...) kadroda o çalışan yoksa zaten çalışmaz.
    if ($Kok -ne $KodKok) {
        $ana = Json-Oku (Join-Path $KodKok 'ayarlar.json')
        if ($ana) { foreach ($p in $ana.PSObject.Properties) { if (-not $a.PSObject.Properties[$p.Name]) { $a | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value } } }
    }
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

# Kadro anahtarından görünen ad (kadro.json); bulunamazsa anahtarın kendisi
function Calisan-Adi([string]$Anahtar) {
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    foreach ($u in @($k.uyeler)) { if ($u -and [string]$u.anahtar -eq $Anahtar -and $u.ad) { return [string]$u.ad } }
    if ($Anahtar -eq 'lider') { return 'Engineering Manager' }
    return $Anahtar
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

# ---------------------------------------------------------------- günlük hak sıfırlama (panel ↺ düğmesi, durum.ps1 -KotaSifirla)
# Ofisin kendi günlük çağrı sayacını (ayarlar.json > gunluk_sinir) sıfırlar ve aracın kullanım / kota sınırı kilitlerini kaldırır.
# Hesaptaki gerçek kota (Anthropic, OpenAI, Google) değişmez; giriş ve model kilitleri kalır, onlar sıfırlamayla düzelmez.
$script:KotaAraclari = @('claude', 'codex', 'gemini')
function Kota-Araclari([string]$Arac) {
    $a = ([string]$Arac).Trim().ToLowerInvariant()
    if ($a -eq 'hepsi') { return $KotaAraclari }
    if ($KotaAraclari -contains $a) { return @($a) }
    throw "Bilinmeyen araç: '$Arac' (claude | codex | gemini | hepsi)"
}
function Kota-Sifirla([string]$Arac) {
    $hedef = @(Kota-Araclari $Arac)
    $s = Sayac-Oku
    $onceki = [ordered]@{}
    foreach ($a in $hedef) {
        $v = 0; if ($s.PSObject.Properties[$a]) { $v = [int]$s.$a }
        $onceki[$a] = $v
        Ayarla $s $a 0
    }
    Json-Yaz $s (Join-Path $YolDurum 'sayaclar.json')
    $k = Kilit-Oku
    $kalkan = @(@($k.PSObject.Properties) | Where-Object { ($hedef -contains ([string]$_.Name -split ':')[0]) -and ([string]$_.Value.neden -match '(?i)sınır|kota') } | ForEach-Object { [string]$_.Name })
    foreach ($ad in $kalkan) { $k.PSObject.Properties.Remove($ad) }
    if ($kalkan.Count) { Json-Yaz $k (Join-Path $YolDurum 'kilitler.json') }
    $ozet = @($hedef | ForEach-Object { '{0} {1} -> 0' -f $_, $onceki[$_] }) -join ', '
    $ek = ''; if ($kalkan.Count) { $ek = '; kaldırılan kilitler: ' + ($kalkan -join ', ') }
    Gunluk "Günlük hak sıfırlandı (kullanıcı): $ozet$ek"
    return [pscustomobject]@{ araclar = $hedef; onceki = [pscustomobject]$onceki; kilitler = $kalkan }
}
# Bu araçların günlük sınırı ya da kullanım / kota sınırı yüzünden takılan ya da yeniden denemeyi bekleyen işler
function Sinirdan-Duran-Gorevler([string[]]$Araclar) {
    $desen = '(?i)\b(' + (@($Araclar | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/[^|]*?(günlük sınır doldu|kullanım sınırı|kota sınırı)'
    $l = @()
    foreach ($g in @(Gorevleri-Listele)) {
        $asama = [string]$g.asama
        if ($asama -eq 'takildi') {
            $son = @(@($g.gecmis) | Where-Object { $_ -and [string]$_.olay -eq 'takıldı' } | Select-Object -Last 1)
            $metin = [string]$g.son_hata; if ($son.Count) { $metin += ' | ' + [string]$son[0].ayrinti }
            if ($metin -match $desen) { $l += $g }
        } elseif ((@('tamam', 'iptal', 'bekliyor_kullanici') -notcontains $asama) -and $g.sonraki_deneme -and ([string]$g.son_hata -match $desen)) { $l += $g }
    }
    return $l
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

# ---------------------------------------------------------------- değişen dosya sınırı (otomatik kontrol)
# Kanıt klasörlerindeki dosyalar (ayarlar.json > gorev.kanit_klasorleri; ayar yoksa cikti/) ayrı sayılır. Kapsam taşması sınırı
# (gorev.max_degisen_dosya) yalnızca kod ve öbür dosyalara uygulanır; kanıtlar kendi sınırına (gorev.max_kanit_dosya; ayar yoksa 300,
# 0 = sınırsız) bağlıdır. Klasör yolu depo kökünden başlar: cikti/ kanıttır, host/cikti/ değildir.
function Kanit-Klasorleri {
    $k = @('cikti/')
    if ($Ayar -and $Ayar.gorev -and $Ayar.gorev.PSObject.Properties['kanit_klasorleri']) { $k = @($Ayar.gorev.kanit_klasorleri | Where-Object { $_ }) }
    return @($k | ForEach-Object { ([string]$_).Trim().Replace('\', '/').Trim('/') } | Where-Object { $_ } | ForEach-Object { $_ + '/' })
}
function Kanit-Dosyasi-mi([string]$Yol, [string[]]$Klasorler) {
    $y = $Yol.Trim().Trim('"').Replace('\', '/').TrimStart('/')
    foreach ($k in @($Klasorler | Where-Object { $_ })) { if ($y.StartsWith($k, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}
# Değişen dosyaları kod / kanıt diye ayırır, sınırları denetler; rapor satırları önce kod ve öbür dosyaları gösterir (en çok 40 satır)
function Dosya-Siniri-Denetle([string[]]$Dosyalar) {
    $klasorler = @(Kanit-Klasorleri)
    $kod = New-Object 'Collections.Generic.List[string]'
    $kanit = New-Object 'Collections.Generic.List[string]'
    foreach ($f in @($Dosyalar | Where-Object { $_ -and $_.Trim() })) { if (Kanit-Dosyasi-mi $f $klasorler) { $kanit.Add($f) } else { $kod.Add($f) } }
    $maxKod = [int]$Ayar.gorev.max_degisen_dosya
    $maxKanit = 300; if ($Ayar.gorev.PSObject.Properties['max_kanit_dosya']) { $maxKanit = [int]$Ayar.gorev.max_kanit_dosya }
    $sorunlar = @()
    if ($kod.Count -gt $maxKod) { $sorunlar += "Çok fazla dosya değişmiş ($($kod.Count) kod ve öbür dosya, sınır $maxKod); kapsam taşmış olabilir." }
    if ($maxKanit -gt 0 -and $kanit.Count -gt $maxKanit) { $sorunlar += "Çok fazla kanıt dosyası değişmiş ($($kanit.Count), sınır $maxKanit; $($klasorler -join ', ')); kanıtlar birleştirilmeli ya da azaltılmalı." }
    $toplam = $kod.Count + $kanit.Count
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("### Değişen dosyalar ($toplam)")
    $kanitSiniri = "$maxKanit"; if ($maxKanit -le 0) { $kanitSiniri = 'sınırsız' }
    if ($klasorler.Count) { [void]$sb.AppendLine("Kod ve öbür dosyalar: $($kod.Count) / $maxKod · kanıt ($($klasorler -join ', ')): $($kanit.Count) / $kanitSiniri") }
    else { [void]$sb.AppendLine("Kod ve öbür dosyalar: $($kod.Count) / $maxKod (kanıt klasörü tanımlı değil)") }
    $liste = @($kod) + @($kanit)
    foreach ($f in ($liste | Select-Object -First 40)) { [void]$sb.AppendLine("- $f") }
    if ($liste.Count -gt 40) { [void]$sb.AppendLine("- … ve $($liste.Count - 40) dosya daha") }
    return [pscustomobject]@{ kod = @($kod); kanit = @($kanit); toplam = $toplam; sorunlar = @($sorunlar); rapor = $sb.ToString().TrimEnd() }
}
# İnceleme istemlerindeki diff'te kanıt dosyaları sona alınır: diff karakter sınırında kesilince kod değişiklikleri görünür kalır
function Diff-Kod-Once([string]$Diff) {
    $klasorler = @(Kanit-Klasorleri)
    if (-not $Diff -or -not $klasorler.Count) { return $Diff }
    $kod = New-Object Text.StringBuilder
    $kanit = New-Object Text.StringBuilder
    foreach ($p in [regex]::Split($Diff, '(?m)^(?=diff --git )')) {
        if (-not $p) { continue }
        $bas = ($p -split "`n", 2)[0]
        $yol = $bas -replace '^diff --git "?a/', ''
        if ($bas -ne $yol -and (Kanit-Dosyasi-mi $yol $klasorler)) { [void]$kanit.Append($p) } else { [void]$kod.Append($p) }
    }
    return ($kod.ToString() + $kanit.ToString())
}

# ---------------------------------------------------------------- şablon doldurma
function Sablon-Doldur([string]$SablonAdi, [hashtable]$Degerler) {
    $s = ''
    if ($YolKatIstem -ne $YolIstem) { $s = Metin-Oku (Join-Path $YolKatIstem $SablonAdi) }
    if (-not $s) { $s = Metin-Oku (Join-Path $YolIstem $SablonAdi) }
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
function Kullanim-Kaydet([string]$Rol, [string]$Etiket, $Giris, $R, [int]$IstemKarakter, [string]$Yerine = '') {
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
        if ($Yerine -and $Yerine -ne $Rol) { $kayit.yerine = $Yerine }   # kullanıcının "Devral" komutuyla bu rolün işini yaptı
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
# Outsource Consultant (danisman.ps1) izinleri: ayarlar.json > danisman. İzin listesi dışındaki araçlar --permission-mode dontAsk ile
# sormadan reddedilir (arka planda onay bekleyip kilitlenmez); yasak kurallar izinlerden önce gelir.
$script:DanismanIzinliVarsayilan = @('Read', 'Glob', 'Grep', 'Edit', 'Write', 'NotebookEdit', 'Bash', 'PowerShell', 'WebFetch', 'WebSearch', 'Agent', 'Task', 'TodoWrite')
$script:DanismanYasakVarsayilan = @('Bash(git push *)', 'Bash(git remote *)', 'Bash(git config --global *)', 'Bash(vmrun *)', 'Bash(shutdown *)',
    'Bash(netsh *)', 'Bash(reg add *)', 'Bash(reg delete *)', 'Bash(bcdedit *)', 'Bash(format *)', 'Bash(rm -rf /)', 'Bash(rm -rf /*)', 'Bash(rm -rf ~*)',
    'PowerShell(git push *)', 'PowerShell(vmrun *)', 'PowerShell(Set-MpPreference *)', 'PowerShell(Add-MpPreference *)', 'PowerShell(Set-NetFirewallProfile *)',
    'PowerShell(Set-NetFirewallRule *)', 'PowerShell(New-NetFirewallRule *)', 'PowerShell(Set-ExecutionPolicy *)', 'PowerShell(Stop-Computer *)', 'PowerShell(Restart-Computer *)')
function Danisman-Izinleri {
    $d = $Ayar.danisman
    $izin = $DanismanIzinliVarsayilan; $yasak = $DanismanYasakVarsayilan; $zaman = 120; $ag = $true; $push = $true
    if ($d) {
        if ($d.izinli_araclar) { $izin = @($d.izinli_araclar) }
        if ($d.PSObject.Properties['yasak_araclar'] -and $null -ne $d.yasak_araclar) { $yasak = @($d.yasak_araclar) }
        if ([int]$d.zaman_asimi_dk -gt 0) { $zaman = [int]$d.zaman_asimi_dk }
        if ($d.PSObject.Properties['ag_erisimi'] -and $null -ne $d.ag_erisimi) { $ag = [bool]$d.ag_erisimi }
        if ($d.PSObject.Properties['push_engeli'] -and $null -ne $d.push_engeli) { $push = [bool]$d.push_engeli }
    }
    # cmd.exe komut satırına girer: tırnak, yüzde, satır sonu içeren kural atlanır
    $temiz = { param($l) , @($l | ForEach-Object { [string]$_ } | Where-Object { $_ -and $_ -notmatch '["%\r\n]' }) }
    return [pscustomobject]@{ izinli = (& $temiz $izin); yasak = (& $temiz $yasak); zaman_asimi_dk = $zaman; ag = $ag; push_engeli = $push }
}
# Danışman çalışırken git push adresleri geçersiz bir yardımcıya yönlenir: push başarısız olur, fetch / commit / status etkilenmez.
# Değişken süreç ortamıyla ajana ve onun komutlarına geçer (Claude Code, Codex, Gemini); çağrıdan sonra eski değer geri konur.
$script:PushEngeliDegeri = "'url.ai-ekip-push-engeli://.pushinsteadof=https://' 'url.ai-ekip-push-engeli://.pushinsteadof=http://' 'url.ai-ekip-push-engeli://.pushinsteadof=git@' 'url.ai-ekip-push-engeli://.pushinsteadof=ssh://'"
function Push-Engeli-Ac([string]$Profil) {
    if ($Profil -ne 'danisman' -or -not (Danisman-Izinleri).push_engeli) { return $null }
    $o = [pscustomobject]@{ deger = [string]$env:GIT_CONFIG_PARAMETERS }
    $env:GIT_CONFIG_PARAMETERS = ($o.deger + ' ' + $PushEngeliDegeri).Trim()
    return $o
}
function Push-Engeli-Kapat($O) {
    if ($null -eq $O) { return }
    if ($O.deger) { $env:GIT_CONFIG_PARAMETERS = $O.deger } else { Remove-Item -LiteralPath Env:GIT_CONFIG_PARAMETERS -ErrorAction SilentlyContinue }
}
function Claude-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false, [string]$Profil = '', [string[]]$EkKlasorler = @()) {
    $araclar = 'Read,Glob,Grep'; $mod = 'dontAsk'
    if ($Yazabilir) { $araclar = 'Read,Glob,Grep,Edit,Write'; $mod = 'acceptEdits' }
    $zaman = [int]$Ayar.zaman_asimi_dk.claude
    # stream-json: her yanıtın token kullanımı ayrı satırda gelir (istek başına bağlam doluluğu için); son satır sonuçtur
    $komut = (Q $Ayar.claude.exe) + " -p --output-format stream-json --verbose --no-session-persistence --model $($G.model)"
    if ($Profil -eq 'danisman') {
        # Outsource Consultant: terminal yetkili Claude Code; çalışma dizini masası (CLAUDE.md), işin klasörü --add-dir ile
        $iz = Danisman-Izinleri
        $komut += ' --permission-mode dontAsk --allowedTools ' + (Q ($iz.izinli -join ','))
        if ($iz.yasak.Count) { $komut += ' --disallowedTools ' + (Q ($iz.yasak -join ',')) }
        foreach ($k in @($EkKlasorler | Where-Object { $_ })) { $komut += ' --add-dir ' + (Q $k) }
        $zaman = $iz.zaman_asimi_dk
    } elseif ($TamYetki) {
        # Altyapı rolleri (altyapi.ps1): kullanıcı tam yetki verdi; tüm araçlar, izin sorulmaz
        $komut += ' --permission-mode bypassPermissions'
        if ($Ayar.zaman_asimi_dk.altyapi) { $zaman = [int]$Ayar.zaman_asimi_dk.altyapi }
    } else {
        $komut += " --tools $araclar --allowedTools $araclar --permission-mode $mod"
        # Ortak klasörler (Ajan-Cagir yalnızca yazma adımlarında verir): çalışma klasörüne ek yazılabilir dizin
        foreach ($k in @($EkKlasorler | Where-Object { $_ })) { $komut += ' --add-dir ' + (Q $k) }
    }
    if ($G.efor) { $komut += " --effort $($G.efor)" }
    $pe = Push-Engeli-Ac $Profil
    try { $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'claude' }
    finally { Push-Engeli-Kapat $pe }
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
function Codex-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$SonMesaj, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false, [string]$Profil = '', [string[]]$EkKlasorler = @()) {
    $exe = Codex-Exe
    $kum = 'read-only'; if ($Yazabilir) { $kum = 'workspace-write' }
    $zaman = [int]$Ayar.zaman_asimi_dk.codex
    if ($TamYetki) {
        # Altyapı rolleri (altyapi.ps1): sandbox yok, ağ açık
        $kum = 'danger-full-access'
        if ($Ayar.zaman_asimi_dk.altyapi) { $zaman = [int]$Ayar.zaman_asimi_dk.altyapi }
    }
    $ek = ''
    if ($Profil -eq 'danisman') {
        # Outsource Consultant (danisman.ps1): korumalı alanda (workspace-write) komut çalıştırır; yazma yalnızca masada (-C) ve işin
        # klasöründe (--add-dir); ağ ayarla (danisman.ag_erisimi). exec kipi onay sormaz, arka planda kilitlenmez. Kurallar masadaki AGENTS.md
        $iz = Danisman-Izinleri
        $kum = 'workspace-write'; $zaman = $iz.zaman_asimi_dk
        foreach ($k in @($EkKlasorler | Where-Object { $_ })) { $ek += ' --add-dir ' + (Q $k) }
        if ($iz.ag) { $ek += ' -c sandbox_workspace_write.network_access=true' }
    } elseif ($Yazabilir -and -not $TamYetki) {
        # Ortak klasörler (Ajan-Cagir yazma adımlarında verir): workspace-write için ek yazılabilir dizin
        foreach ($k in @($EkKlasorler | Where-Object { $_ })) { $ek += ' --add-dir ' + (Q $k) }
    }
    $efor = 'high'; if ($G.efor) { $efor = $G.efor }
    if (Test-Path -LiteralPath $SonMesaj) { Remove-Item -LiteralPath $SonMesaj -Force }
    $komut = (Q $exe) + " exec --skip-git-repo-check -s $kum -C $(Q $Klasor)$ek -o $(Q $SonMesaj) -m $($G.model) -c model_reasoning_effort=$efor -"
    $pe = Push-Engeli-Ac $Profil
    try { $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'codex' }
    finally { Push-Engeli-Kapat $pe }
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
function Gemini-Calistir($G, [string]$IstemYolu, [string]$Out, [string]$Err, [string]$Klasor, [bool]$Yazabilir, [bool]$TamYetki = $false, [string]$Profil = '', [string[]]$EkKlasorler = @()) {
    $mod = 'plan'; if ($Yazabilir) { $mod = 'auto_edit' }
    if ($TamYetki) { $mod = 'yolo' }
    $zaman = [int]$Ayar.zaman_asimi_dk.gemini
    $ek = ''
    if ($Profil -eq 'danisman') {
        # Outsource Consultant: başsız kipte onay sorulamaz; araçlar onaysız (yolo), işin klasörü çalışma alanına eklenir. Araç bazında
        # yasak listesi yok: kurallar masadaki GEMINI.md'de, git push ortam düzeyinde engelli
        $mod = 'yolo'; $zaman = (Danisman-Izinleri).zaman_asimi_dk
        $dirs = @($EkKlasorler | Where-Object { $_ })
        if ($dirs.Count) { $ek = ' --include-directories ' + (Q ($dirs -join ',')) }
    } elseif ($Yazabilir -and -not $TamYetki) {
        # Ortak klasörler (Ajan-Cagir yazma adımlarında verir)
        $dirs = @($EkKlasorler | Where-Object { $_ })
        if ($dirs.Count) { $ek = ' --include-directories ' + (Q ($dirs -join ',')) }
    }
    $komut = (Q (Gemini-Exe)) + " -p `"`" --approval-mode $mod --skip-trust$ek -o json"
    if ($G.model) { $komut += " -m $($G.model)" }
    $pe = Push-Engeli-Ac $Profil
    try { $s = Surec-Calistir -Komut $komut -Girdi $IstemYolu -Cikti $Out -Hata $Err -Klasor $Klasor -ZamanAsimiDk $zaman -Etiket 'gemini' }
    finally { Push-Engeli-Kapat $pe }
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

# ---------------------------------------------------------------- Fibonacci puanlama (story point)
# Engineering Manager işi yönlendirirken ya da planlarken, işi yapacak çalışan ilk kez üstlenirken maliyeti Fibonacci ölçeğiyle
# puanlar (ayarlar.json > puanlama.etkin). Ajan-Cagir istemi ekler ve çıktıyı okur; puan görev kaydedilirken yazılır.
$script:FibonacciPuanlari = @(1, 2, 3, 5, 8, 13, 21)
$script:BekleyenPuan = $null
function Puan-Yuvarla([int]$N) {
    if ($N -le 0) { return 0 }
    $en = 1
    foreach ($f in $FibonacciPuanlari) { if ([Math]::Abs($f - $N) -le [Math]::Abs($en - $N)) { $en = $f } }   # eşitlikte büyüğe
    return $en
}
function Puan-Coz([string]$Metin) {
    # "PUAN: 5", "- PUAN = 5", "**PUAN:** 5"; şablonun kendisi ("PUAN: <1|2|...>") puan sayılmaz
    $m = [regex]::Match([string]$Metin, '(?im)^\W{0,4}PUAN\s*[:=]?\s*\**\s*(\d{1,3})\b')
    if (-not $m.Success) { return $null }
    $p = Puan-Yuvarla ([int]$m.Groups[1].Value)
    if ($p -le 0) { return $null }
    return [pscustomobject]@{ puan = $p; gerekce = (Alan-Oku $Metin 'PUAN_GEREKCE') }
}
function Puanlama-Etkin { $p = $Ayar.puanlama; return (-not $p -or $null -eq $p.etkin -or [bool]$p.etkin) }
$script:PuanYoneticiMetni = @'


---

# PUANLAMA (Fibonacci story point)

Bu işin maliyetini Fibonacci ölçeğiyle puanla: 1, 2, 3, 5, 8, 13, 21. Puan emeği, belirsizliği ve riski birlikte yansıtır
(1 = birkaç dakikalık net değişiklik, 3 = küçük ama birkaç parçalı iş, 8 = birden çok bileşen, kurulum ya da ekip içi yardım
gerektiren iş, 21 = bölünmesi gereken çok büyük iş). Ekibin yeteneklerini (KADRO: kim ne yapabilir, hangi yetkiyle; işi yapacak kişinin
kurulum, internet ya da test için yardıma ihtiyacı olacak mı) hesaba kat. Çıktının biçimini bozma: KARAR satırından hemen sonra şu iki
satırı ekle:
PUAN: <1|2|3|5|8|13|21>
PUAN_GEREKCE: <tek cümle>
'@
$script:PuanAjanMetni = @'


---

# PUANLAMA (Fibonacci story point)

Bu işi ilk kez üstleniyorsun: kendi açından puanla (Engineering Managerʼın tahmininden bağımsız). Ölçek 1, 2, 3, 5, 8, 13, 21;
puan emeği, belirsizliği ve riski birlikte yansıtır. Son mesajına (varsa yardım bloğundan önce) ayrı satırlar olarak ekle:
PUAN: <1|2|3|5|8|13|21>
PUAN_GEREKCE: <tek cümle>
'@
function Puan-Istem-Metni([string]$Rol, [string]$Etiket) {
    if (-not $script:AktifGorev -or -not (Puanlama-Etkin)) { return '' }
    $lider = ($Rol -eq 'lider' -and @('yonlendirme', 'plan') -contains $Etiket)
    $ajan = ($Rol -ne 'lider' -and @('gelistirme', 'uygulama', 'calisma') -contains $Etiket)
    if (-not $lider -and -not $ajan) { return '' }
    $g = Gorev-Diskten $script:AktifGorev
    if (-not $g) { return '' }
    if ($lider) { if ($g.puan_yonetici) { return '' }; return $PuanYoneticiMetni }
    if ($g.puan_ajan -and [string]$g.puan_ajan.rol -eq $Rol) { return '' }
    # Bölünmüş geliştirmede yalnızca ilk parçayı üstlenen geliştirici puanlar (planlama.ps1)
    if ($g.puan_ajan -and (Get-Command Kod-Yazar-mi -ErrorAction SilentlyContinue) -and (Kod-Yazar-mi $Rol) -and (Kod-Yazar-mi ([string]$g.puan_ajan.rol))) { return '' }
    return $PuanAjanMetni
}

# ---------------------------------------------------------------- ekip içi yardımlaşma (ayarlar.json > yardimlasma; akış yardim.ps1)
# Görev adımlarında çalışan ajan, kendi yapamayacağı ama ekipte başkasının yapabileceği bir şeye ihtiyaç duyarsa
# çıktısının sonuna ```yardim {json}``` bloğu ekler; adım başarısız sayılmaz, Engineering Manager isteği uygun çalışana verir.
function Yardim-Uygun-mu([string]$Rol, [string]$Etiket) {
    if (-not $script:AktifGorev) { return $false }
    $a = $Ayar.yardimlasma
    if (-not $a -or -not $a.etkin) { return $false }
    if ($Rol -eq 'sorun-giderici') { return $false }
    # Fikir hattı adımları (yaratici.ps1) belge üretir; yardım isteği ancak ayarlar.json > yaratici.yardimlasma açıksa
    if ($YaraticiEtiketler -contains $Etiket -and -not ($Ayar.yaratici -and $Ayar.yaratici.yardimlasma)) { return $false }
    # Product Manager (analiz) ve Codebase Explorer (kesif) salt okunur rapor yazar; yardım istemez
    if (@('yardim', 'cozum', 'yonlendirme', 'ise_alim', 'kategori', 'analiz', 'kesif', 'danisman') -contains $Etiket -or $Etiket -like 'sohbet*' -or $Etiket -like 'birlikte-*') { return $false }
    if ($Rol -eq 'lider' -and $Etiket -ne 'kabul') { return $false }   # Engineering Manager planda ön işleri "YARDIM:" satırlarıyla ister
    return $true
}
function Yardim-Talimati-Metni {
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    $satirlar = @()
    foreach ($u in @($k.uyeler)) {
        if ($u -and $u.anahtar -and @('lider', 'sorun-giderici', 'cto', 'danisman') -notcontains [string]$u.anahtar) { $satirlar += ('- {0} ({1}): {2}' -f $u.anahtar, $u.ad, (Kisalt ([string]$u.uzmanlik) 120)) }
    }
    $metin = @'


---

# EKİPTEN YARDIM İSTEME (Engineering Manager aracılığıyla birlikte çalışma)

Yetkinin ya da aracının yetmediği bir şey işin için gerekiyorsa işi eksik, tahminle ya da hatalı bırakma; başarısız sayma,
reddetme: Engineering Managerʼdan yardım iste. Ekip birlikte çalışır. Yardım isteyebileceğin durumlar:
- kütüphane / paket indirip kurmak (npm, pip, NuGet, Maven, flutter pub…), bir internet sitesine bağlanmak, belge ya da dosya indirmek;
- yazdığın kodu derleyip çalıştırmak, geliştirme sırasında küçük deneme koşturmaları ve testler, emülatörde / tarayıcıda denemek;
- yazılım / SDK / araç kurulumu, sunucu, VM, servis, port, ağ ayarı (sistem, ag);
- uygulamayı gerçekten kullanarak test etmek, kullanıcı testi (tester);
- tasarım ya da görsel varlık, güvenlik ya da mimari görüşü (uzmanlar);
- gizli bilgi (API anahtarı, parola, hesap) ya da yalnızca kullanıcının verebileceği bir karar (Engineering Manager kullanıcıya sorar);
- planda olmayan büyük bir değişiklik gerekiyorsa Engineering Managerʼın onayı.
Kısa işleri Engineering Manager bir ekip arkadaşına HEMEN, senin çalışma klasöründe yaptırır (birlikte çalışma: kurulum, indirme,
çalıştırma ve test sonuçları dakikalar içinde gelir; indirilen dosyalar çalışma klasöründe .ekip-yardim altına konur). Uzun işler ayrı
yardım işi olarak açılır. Yardım gelince bu adım, gelen sonuçla ("EKİPTEN GELEN YARDIM") yeniden çalışır ve kaldığın yerden sürersin.
Özellikle DUZELT / RET vermeden önce düşün: eksik olan şey işi yapanın değil başka birinin uzmanlığı ya da yetkisiyse yardım iste.
Yapabildiğin kısmı yine yap. Yardım istemek için çıktının EN SONUNA şu bloğu ekle (gerekmiyorsa ekleme; "hemen": işin buna bağlıysa true):

```yardim
{"ne": "tam olarak ne yapılmalı (komut, paket, adres, test)", "neden": "neden sen yapamıyorsun, neden gerekli", "kim": "önerdiğin kadro anahtarı ya da boş", "hemen": true, "kabul": ["yardımın tamam sayılma ölçütü"]}
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

# ---------------------------------------------------------------- kullanıcının doğrudan komutları (komut.ps1)
# Kullanıcı panelden bir çalışana komut verirken eklediği talimatlar (gorevler\<no>\kullanici-talimatlari.md): bu işteki her istemde
function Talimat-Istem-Metni([string]$Etiket) {
    if (-not $script:AktifGorev -or $Etiket -like 'sohbet*') { return '' }
    $t = Metin-Oku (Join-Path (Join-Path $YolGorev $script:AktifGorev) 'kullanici-talimatlari.md')
    if (-not $t.Trim()) { return '' }
    if ($t.Length -gt 6000) { $t = '…' + $t.Substring($t.Length - 6000) }
    return "`n`n---`n`n# KULLANICININ TALİMATLARI (panelden doğrudan verdi; işini bunlara göre yap, görev metniyle çelişirse bunlar geçerli)`n`n" + $t.Trim()
}
# CTOʼnun ekip ilkeleri (yonetim.ps1; durum\yonetim\ekip-ilkeleri.md): ekibin önceki işlerden öğrendikleri, her iş isteminde
# İsteme en fazla ayarlar.json > yonetim.ilke_karakter_siniri karakter girer (varsayılan 6000, en az 500); kesim madde sınırında yapılır.
function Ilke-Karakter-Siniri {
    $s = 6000
    if ($Ayar -and $Ayar.yonetim -and $Ayar.yonetim.PSObject.Properties['ilke_karakter_siniri'] -and $null -ne $Ayar.yonetim.ilke_karakter_siniri) {
        try { $s = [int]$Ayar.yonetim.ilke_karakter_siniri } catch { }
    }
    return [Math]::Max(500, $s)
}
# Ilke listesini sınıra sığdırır: yarım madde bırakmaz, sığmayan maddeleri sayar. Döner: { metin; kesilen }
function Ilkeler-Sigdir([string]$Metin, [int]$Sinir) {
    $t = ([string]$Metin).Trim()
    if ($t.Length -le $Sinir) { return [pscustomobject]@{ metin = $t; kesilen = 0 } }
    $maddeler = New-Object System.Collections.Generic.List[string]
    foreach ($sat in @($t -split "`r?`n")) {
        if ($maddeler.Count -eq 0 -or $sat -match '^\s*([-*]|\d+[.)])\s+') { $maddeler.Add($sat) }
        else { $maddeler[$maddeler.Count - 1] = $maddeler[$maddeler.Count - 1] + "`n" + $sat }
    }
    $sb = New-Object Text.StringBuilder; $alinan = 0
    foreach ($md in $maddeler) {
        $ek = $md; if ($sb.Length) { $ek = "`n" + $md }
        if ($sb.Length + $ek.Length -gt $Sinir) { break }
        [void]$sb.Append($ek); $alinan++
    }
    $sonuc = $sb.ToString(); $kesilen = $maddeler.Count - $alinan
    if (-not $sonuc) { $sonuc = $t.Substring(0, $Sinir) + '…'; $kesilen = [Math]::Max(0, $maddeler.Count - 1) }   # tek madde bile sığmıyorsa
    return [pscustomobject]@{ metin = $sonuc; kesilen = $kesilen }
}
function Ilkeler-Istem-Metni([string]$Etiket) {
    if (-not $script:AktifGorev -or $Etiket -like 'sohbet*' -or $Etiket -eq 'yonetim') { return '' }
    $t = Metin-Oku (Join-Path (Join-Path $YolDurum 'yonetim') 'ekip-ilkeleri.md')
    if (-not $t.Trim()) { return '' }
    $sg = Ilkeler-Sigdir $t (Ilke-Karakter-Siniri)
    $not = ''; if ($sg.kesilen -gt 0) { $not = "`n`n(Karakter sınırı nedeniyle $($sg.kesilen) ilke daha bu isteme sığmadı.)" }
    return "`n`n---`n`n# EKİP İLKELERİ (CTO; ekibin önceki işlerden öğrendikleri, işini yaparken bunlara uy)`n`n" + $sg.metin + $not
}
function Devralma-Notu([string]$Rol, [string]$Kisi) {
    return ("`n`n---`n`n# DEVRALMA (kullanıcının komutu)`n`nBu adım normalde {0} rolünün işi; kullanıcı panelden bu işte o rolü sana ({1}) devretti. " +
        'Rolün adım talimatlarına, yetki sınırlarına ve çıktı biçimine aynen uy; kendi uzmanlığını da kat.') -f (Calisan-Adi $Rol), (Calisan-Adi $Kisi)
}

# ---------------------------------------------------------------- ortak klasörler
# ayarlar.json > ortak_klasorler.yollar: bütün ajanların yazma adımlarında çalışma klasörüne ek olarak yazabildiği klasörler
# (Claude / Codex --add-dir, Gemini --include-directories). Göreli yol katın köküne göredir; olmayan klasör atlanır.
# Kullanım: sıralı programların kontrol listeleri (ör. programlar\<ad>\PROGRAM.md); ajan kendi satırının kutusunu işaretler.
function Ortak-Klasorler {
    $o = $Ayar.ortak_klasorler
    if (-not $o) { return @() }
    $l = @()
    foreach ($y in @($o.yollar | Where-Object { $_ })) {
        $t = [Environment]::ExpandEnvironmentVariables([string]$y)
        if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path $Kok $t }
        if (Test-Path -LiteralPath $t -PathType Container) { $l += (Resolve-Path -LiteralPath $t).Path }
    }
    return $l
}
function Ortak-Klasor-Notu([string[]]$Klasorler) {
    $no = ([string]$script:AktifGorev -split '-')[0]
    $s = "`n`n## Ortak klasörler`nÇalışma klasörüne ek olarak şu klasörlere de yazabilirsin: " + (($Klasorler | ForEach-Object { '`' + $_ + '`' }) -join ', ') + ".`n"
    $s += "Buradaki dosyaları (ör. sıralı programların PROGRAM.md kontrol listeleri) yalnızca görev metni ya da o dosyanın kendi kuralları istediğinde ve istediği kadar değiştir; orada başka dosya oluşturma, silme.`n"
    if ($no -match '^\d+$') { $s += "Bu işin numarası: #$no.`n" }
    return $s
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
        [string[]]$Haric = @(),     # bu araçları atla (ör. Code Reviewer Full-Stack Developerʼla aynı model olmasın)
        [string]$IzinProfili = '',  # 'danisman': Outsource Consultant (dontAsk + izin / yasak listeleri, ayarlar.json > danisman)
        [string[]]$EkKlasorler = @(),   # Claude'a --add-dir ile açılacak klasörler (izin profiliyle)
        [switch]$TamYetki           # altyapı rolleri: sandbox'sız, izin sormadan (altyapı görev kapsamı)
    )
    if (-not (Test-Path -LiteralPath $KayitKlasoru)) { New-Item -ItemType Directory -Force $KayitKlasoru | Out-Null }
    $Istem = Yardim-Istem-Ekle $Rol $Etiket $Istem
    $Istem += (Talimat-Istem-Metni $Etiket)
    $Istem += (Ilkeler-Istem-Metni $Etiket)
    # Ortak yazılabilir klasörler (ayarlar.json > ortak_klasorler): yalnızca yazma adımlarında; tam yetkili altyapı rolleri zaten her yere yazar
    if ($Yazabilir -and -not $TamYetki) {
        $ortak = @(Ortak-Klasorler)
        if ($ortak.Count) {
            $EkKlasorler = @(@($EkKlasorler) + $ortak | Where-Object { $_ } | Select-Object -Unique)
            $Istem += (Ortak-Klasor-Notu $ortak)
        }
    }
    # Kullanıcı bu işte rolü başka bir çalışana devrettiyse onun model zinciriyle çalış (komut.ps1)
    $kisi = $Rol
    if ($script:RolDegisimi -and $script:RolDegisimi.ContainsKey($Rol)) {
        $aday = [string]$script:RolDegisimi[$Rol]
        if (@($Ayar.roller.$aday | Where-Object { $_ }).Count) { $kisi = $aday; $Istem += (Devralma-Notu $Rol $aday) }
        else { Gunluk "$Rol rolünü devralan $aday için model zinciri yok; rolün kendi zinciri kullanılıyor" 'UYARI' }
    }
    $kimAdi = $Rol; if ($kisi -ne $Rol) { $kimAdi = "$kisi ($Rol yerine)" }
    $puanIstemi = Puan-Istem-Metni $Rol $Etiket
    if ($puanIstemi) { $Istem += $puanIstemi }
    $Istem = (Unvan-Uyarla $Istem).Replace('{KAT_KOKU}', $Kok).Replace('{OFIS_KOKU}', $KodKok)
    $notlar = @()
    $gorevId = [string]$script:AktifGorev
    $iptalHata = 'görev kullanıcı tarafından iptal edildi'
    foreach ($g in @($Ayar.roller.$kisi)) {
        # İptal edilen görevde yedek zincirdeki sonraki araca geçme
        if ($script:IptalIzleme -and $gorevId -and (Gorev-Iptal-mi $gorevId)) {
            Gunluk "$kimAdi çağrısı yapılmadı: görev $gorevId iptal edildi, panoda taşındı ya da paralel hat durduruldu [$Etiket]" 'UYARI'
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
        Gunluk "$kimAdi -> $kimlik başlıyor [$($script:AktifGorev) / $Etiket]"
        switch ($g.arac) {
            'claude' { $r = Claude-Calistir $g $istemYolu $out $err $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) $IzinProfili $EkKlasorler }
            'codex'  { $r = Codex-Calistir  $g $istemYolu $out $err $son $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) $IzinProfili $EkKlasorler }
            'gemini' { $r = Gemini-Calistir $g $istemYolu $out $err $Klasor ([bool]$Yazabilir) ([bool]$TamYetki) $IzinProfili $EkKlasorler }
        }
        Kullanim-Kaydet $kisi $Etiket $g $r $Istem.Length $Rol
        if ($r.basarili) {
            $r.arac = [string]$g.arac; $r.model = [string]$g.model
            Gunluk "$kimAdi -> $kimlik bitti ($($r.sure_sn) sn)"
            if ($script:IptalIzleme -and $gorevId -and (Gorev-Iptal-mi $gorevId)) {
                # Ajan iptalden sonra bitti: adım bu sonuçla ilerlemesin (soru, aktarma, e-posta, yeni tur...)
                Gunluk "$Rol -> $kimlik sonucu kullanılmadı: görev $gorevId ajan çalışırken iptal edildi ya da panoda taşındı" 'UYARI'
                return [pscustomobject]@{ basarili = $false; metin = ''; hata = $iptalHata; sure_sn = $r.sure_sn; arac = $r.arac; model = $r.model; iptal = $true }
            }
            # Fibonacci puanı: görev kaydedilirken işlenir (Gorev-Kaydet)
            if ($puanIstemi) {
                $pz = Puan-Coz $r.metin
                if ($pz) { $script:BekleyenPuan = [pscustomobject]@{ gorev = $gorevId; rol = $Rol; etiket = $Etiket; puan = $pz.puan; gerekce = $pz.gerekce; arac = $kimlik } }
                else { Gunluk "$Rol puan vermedi [$gorevId / $Etiket]" 'UYARI' }
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
        Gunluk "$kimAdi -> $kimlik başarısız: $($r.hata)" 'UYARI'
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
    # Katlar aynı bildirim kanalını paylaşır: masaüstünde / telefonda hangi kattan geldiği görünsün (bildirim.telefon.baslik_on_eki ya da katın kısa adı)
    $onEk = ''; try { $onEk = [string]$Ayar.bildirim.telefon.baslik_on_eki } catch {}
    if (-not $onEk -and $script:KatKimligi -ne 'ana' -and $script:Kat) { $kisa = [string]$script:Kat.kisa_ad; if (-not $kisa) { $kisa = [string]$script:Kat.ad }; if ($kisa) { $onEk = "$kisa · " } }
    $disBaslik = $Baslik; if ($onEk -and -not $Baslik.StartsWith($onEk)) { $disBaslik = $onEk + $Baslik }
    if ($Ayar.bildirim.masaustu) { Toast-Goster $disBaslik $Metin }
    $tel = $Ayar.bildirim.telefon
    if ($tel -and $tel.kanal -eq 'ntfy' -and $tel.ntfy_konu) { Ntfy-Gonder $disBaslik $Metin $Onem }
}

# ---------------------------------------------------------------- görev kayıtları
function Gorev-Klasoru([string]$Id) { Join-Path $YolGorev $Id }
function Gorev-Oku([string]$Id) { Json-Oku (Join-Path (Gorev-Klasoru $Id) 'durum.json') }
function Gorev-Kaydet($G) {
    $bp = $script:BekleyenPuan
    if ($bp -and [string]$bp.gorev -eq [string]$G.id) {
        $kayit = [pscustomobject][ordered]@{ rol = [string]$bp.rol; puan = [int]$bp.puan; gerekce = (Kisalt ([string]$bp.gerekce) 220); zaman = (Simdi); arac = [string]$bp.arac }
        if ($bp.rol -eq 'lider') { Ayarla $G 'puan_yonetici' $kayit } else { Ayarla $G 'puan_ajan' $kayit }
        $script:BekleyenPuan = $null
        Gunluk "Görev $($G.id): $($bp.rol) $($bp.puan) puan verdi"
    }
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
# Adım sürerken görev iptal edildiyse ya da kullanıcı panoda başka aşamaya taşıdıysa süren ajan durdurulur, sonucu kullanılmaz
function Gorev-Iptal-mi([string]$Id) {
    $d = Gorev-Diskten $Id
    if (-not $d) { return $false }
    if ([string]$d.asama -eq 'iptal') { return $true }
    # Kullanıcı bu süreçteki paralel hattı durdurdu (komut.ps1 > Paralel-Durdur): süren ajan sonlandırılır, adım başarısız sayılmaz
    if ($script:ParalelGorev -and $Id -eq $script:ParalelGorev -and (Test-Path -LiteralPath (Join-Path (Gorev-Klasoru $Id) 'paralel-durdur'))) { return $true }
    return (Gorev-Elle-Tasindi-mi $d)
}
$script:AdimBaslangic = $null
function Gorev-Elle-Tasindi-mi($D) {
    if (-not $script:AdimBaslangic -or -not $D -or -not $D.elle_tasima) { return $false }
    try { return ([datetime][string]$D.elle_tasima.zaman -gt $script:AdimBaslangic) } catch { return $false }
}
# ---------------------------------------------------------------- görev kilidi
# Ana döngü (ekip.ps1 > Gorev-Ilerlet) ve paralel hatlar (paralel.ps1) bir işi yürütürken adlandırılmış mutex tutar; aynı işi iki
# süreç aynı anda yürütmez. Süreç ölürse kilit kendiliğinden bırakılır. Kilit aynı iş parçacığında yeniden alınabilir.
function Gorev-Kilit-Adi([string]$Id) { 'Local\AIEkipGorev' + (Kat-Soneki) + '_' + ($Id -replace '[^A-Za-z0-9-]', '_') }
function Gorev-Kilidi-Al([string]$Id) {
    $m = New-Object Threading.Mutex($false, (Gorev-Kilit-Adi $Id))
    $al = $false
    try { $al = $m.WaitOne(0) } catch [Threading.AbandonedMutexException] { $al = $true }
    if ($al) { return $m }
    $m.Dispose()
    return $null
}
function Gorev-Kilidi-Birak($M) {
    if (-not $M) { return }
    try { $M.ReleaseMutex() } catch {}
    $M.Dispose()
}
# Bu işi şu an başka bir süreç mi yürütüyor
function Gorev-Kilitli-mi([string]$Id) {
    $m = $null
    if (-not [Threading.Mutex]::TryOpenExisting((Gorev-Kilit-Adi $Id), [ref]$m)) { return $false }
    try {
        $al = $false
        try { $al = $m.WaitOne(0) } catch [Threading.AbandonedMutexException] { $al = $true }
        if ($al) { $m.ReleaseMutex(); return $false }
        return $true
    } finally { $m.Dispose() }
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
    yeni = 'Sırada'; analiz = 'Gereksinimler netleşiyor'; kesif = 'Kod tabanı taranıyor'; plan = 'Planlanıyor'; gelistirme = 'Geliştiriliyor'
    kontrol = 'Kontrol ediliyor'; test = 'Test ediliyor'; denetim = 'Denetleniyor'; kabul = 'Engineering Manager onayında'; tamamla = 'Commit ediliyor'; tamam = 'Tamamlandı'
    takildi = 'Takıldı'; bekliyor_kullanici = 'Senden yanıt bekliyor'; iptal = 'İptal'
    yardim = 'Engineering Managerʼda (yardım isteği)'; yardim_bekliyor = 'Ekipten yardım bekliyor'
    kat_bekliyor = 'Başka katta yapılıyor (Comms)'; canliya_al = 'Canlıya alınıyor'
    # Fikir hattı (tip = yaratici; yaratici.ps1)
    fikir = 'Fikir üretiliyor'; elestiri = 'Eleştiriliyor'; poc_plan = 'POC planlanıyor'; maliyet = 'Maliyet hesaplanıyor'
    karar = 'Karar bekliyor'; teslim = 'Teslim hazırlanıyor'; bekleme = 'Ana ofiste uygulanıyor'; puanlama = 'Puanlanıyor'; reddedildi = 'Reddedildi'
}
# Fikir hattı ajan adımlarının etiketleri (Ajan-Cagir -Etiket); panel bunları aşamaya eşler
$script:YaraticiEtiketler = @('fikirci', 'elestirmen', 'planlamaci', 'maliyet', 'karar-verici', 'teslim', 'puanlayici')
function Asama-Adi([string]$A) { if ($AsamaAdlari.ContainsKey($A)) { return $AsamaAdlari[$A] }; return $A }
