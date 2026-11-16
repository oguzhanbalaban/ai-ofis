<#
ofis.ps1 - AI Ekip "görsel ofis" paneli: yalnızca 127.0.0.1'e bağlanan küçük yerel web sunucusu.

  Masaüstü kısayolu bunu çağırır (pencere görünmez):
    conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Ac
  Elle (konsolda günlükle):
    powershell -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Ac -Konsol

  * Tek kopya çalışır (mutex). İkinci çağrı yalnızca paneli tarayıcıda açar.
  * Okuma: gorevler\*\durum.json, durum\*.json, bildirimler.jsonl, günlük doğrudan okunur.
    Dosyalar FileShare.ReadWrite|Delete ile açılır; döngünün atomik yazmalarını engellemez.
  * Eylemler mevcut betikleri çağırır: gorev-ekle.ps1, durum.ps1 (-Duraklat/-Surdur/-Devam/-Iptal).
    Soru yanıtı görevin gorev.md dosyasına eklenir (BENIOKU'daki akış; döngü değişikliği görüp yeniden planlar).
  * BosKapanDk dakika boyunca hiç istek gelmezse kendini kapatır (kısayol yeniden başlatır).
  * Güvenlik: yalnızca 127.0.0.1; Host başlığı denetimi (DNS rebinding'e karşı); tüm /api isteklerinde
    sunucu her açılışta ürettiği oturum anahtarı + Origin/Sec-Fetch-Site denetimi. Dışarıya hiçbir veri gitmez.
  * Bu dosya ofis\ alt klasöründe durur: kök klasördeki .ps1 değişiklikleri döngüyü yeniden yükletir, bu yüklemez.
#>
param(
    [ValidateRange(1024, 65000)][int]$Port = 8765,
    [switch]$Ac,
    [switch]$Konsol,
    [ValidateRange(0, 1440)][int]$BosKapanDk = 60
)
$ErrorActionPreference = 'Stop'
$script:OfisKok = $PSScriptRoot
$script:Kok = Split-Path -Parent $PSScriptRoot
. (Join-Path $Kok 'yapilandirma.ps1')
$script:Utf8 = New-Object Text.UTF8Encoding $false
$script:Latin1 = [Text.Encoding]::GetEncoding(28591)
$script:YolGorev = Join-Path $Kok 'gorevler'
$script:YolDurum = Join-Path $Kok 'durum'
$script:YolGunluk = Join-Path $Kok 'gunluk'
$script:SunucuDosyasi = Join-Path $OfisKok 'sunucu.json'
$script:KayitDosyasi = Join-Path $OfisKok 'ofis.log'
$script:PanelDosyasi = Join-Path $OfisKok 'panel.html'
$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Konsolda = [bool]$Konsol

# Claude masaüstü uygulamasından devralınmış olabilecek değişkenler alt süreçlere geçmesin
$adlar = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } | ForEach-Object { $_.Name })
foreach ($a in $adlar) { Remove-Item -LiteralPath "env:$a" -ErrorAction SilentlyContinue }
# Panelin git okumaları dizin kilidi almasın (döngünün "git add" adımıyla çakışmasın)
$env:GIT_OPTIONAL_LOCKS = '0'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$script:AktifAsamalar = @('yeni', 'plan', 'gelistirme', 'kontrol', 'denetim', 'kabul', 'tamamla')
$script:AsamaAdlari = @{
    yeni = 'Sırada'; plan = 'Planlanıyor'; gelistirme = 'Geliştiriliyor'; kontrol = 'Kontrol ediliyor'
    denetim = 'Denetleniyor'; kabul = 'Lider onayında'; tamamla = 'Commit ediliyor'; tamam = 'Tamamlandı'
    takildi = 'Takıldı'; bekliyor_kullanici = 'Senden yanıt bekliyor'; iptal = 'İptal'
}
# kadro.json yoksa ya da bozuksa kullanılacak en küçük kadro
$script:VarsayilanKadro = @(
    [pscustomobject]@{ anahtar = 'lider'; ad = 'Lider'; departman = 'Yönetim'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'gelistirici'; ad = 'Geliştirici'; departman = 'Yazılım'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'denetci'; ad = 'Denetçi'; departman = 'Yazılım'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'sistem'; ad = 'Sistem Yöneticisi'; departman = 'Altyapı ve güvenlik'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'ag'; ad = 'Network'; departman = 'Altyapı ve güvenlik'; yerlesik = $true }
)
function Kadro-Listesi {
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    $l = @()
    if ($k) { $l = @($k.uyeler | Where-Object { $_ -and $_.anahtar }) }
    if ($l.Count -eq 0) { $l = $VarsayilanKadro }
    return , $l
}
function Kadro-Bul($Liste, [string]$Anahtar) { foreach ($u in $Liste) { if ([string]$u.anahtar -eq $Anahtar) { return $u } }; return $null }
$script:AsamaRol = @{ yeni = 'lider'; plan = 'lider'; gelistirme = 'gelistirici'; kontrol = 'denetci'; denetim = 'denetci'; kabul = 'lider'; tamamla = 'lider' }
$script:AsamaFaaliyet = @{ yeni = 'plan'; plan = 'plan'; gelistirme = 'gelistirme'; kontrol = 'kontrol'; denetim = 'denetim'; kabul = 'kabul'; tamamla = 'kabul' }
$script:AsamaMetni = @{
    yeni = 'Çalışma dalını hazırlıyor'; plan = 'Plan yazıyor'; gelistirme = 'Kodu yazıyor'
    kontrol = 'Testleri ve taramaları çalıştırıyor'; denetim = 'Kodu inceliyor'; kabul = 'Son kararı veriyor'; tamamla = 'Commit ediyor'
}
# Sunucu / kurulum talepleri (tip = altyapi): aynı aşama adları, farklı roller ve metinler (bkz. altyapi.ps1)
$script:AltyapiFaaliyet = @{ yeni = 'kesif'; plan = 'plan'; gelistirme = 'uygulama'; kontrol = 'kontrol'; denetim = 'dogrulama'; kabul = 'kabul'; tamamla = 'kabul' }
$script:AltyapiMetni = @{
    yeni = 'VM ve ağ durumunu tarıyor'; plan = 'Talebi planlıyor'; gelistirme = 'Sunucuda çalışıyor'
    kontrol = 'Doğrulama komutlarını çalıştırıyor'; denetim = 'Bağımsız doğruluyor'; kabul = 'Son kararı veriyor'; tamamla = 'Talebi kapatıyor'
}
$script:AltyapiAsamaAdlari = @{ yeni = 'Sırada'; gelistirme = 'Uygulanıyor'; denetim = 'Doğrulanıyor'; tamamla = 'Kapatılıyor' }
# Uzman işleri (tip = uzman; bkz. uzman.ps1): sorumlu ve inceleyen kadrodan seçilir
$script:UzmanFaaliyet = @{ yeni = 'plan'; plan = 'plan'; gelistirme = 'calisma'; kontrol = 'kontrol'; denetim = 'inceleme'; kabul = 'kabul'; tamamla = 'kabul' }
$script:UzmanMetni = @{
    yeni = 'İşi hazırlıyor'; plan = 'İşi planlıyor'; gelistirme = 'Çalışıyor'
    kontrol = 'Teslimleri kontrol ediyor'; denetim = 'İnceliyor'; kabul = 'Son kararı veriyor'; tamamla = 'İşi kapatıyor'
}
$script:UzmanAsamaAdlari = @{ gelistirme = 'Çalışılıyor'; denetim = 'İnceleniyor'; tamamla = 'Kapatılıyor' }
# Kalp atışındaki adım etiketi -> görev aşaması
$script:EtiketAsama = @{ uygulama = 'gelistirme'; dogrulama = 'denetim'; calisma = 'gelistirme'; inceleme = 'denetim'; ise_alim = 'plan' }
function Gorev-Tipi($G) {
    $t = [string](Ozellik $G 'tip')
    if ($t -eq 'altyapi' -or $t -eq 'uzman') { return $t }
    return 'yazilim'
}
function Altyapi-Mi($G) { return ((Gorev-Tipi $G) -eq 'altyapi') }
function Gorev-Rolu($G, [string]$Etiket = '') {
    # Görevin şu anki aşamasını hangi rol yürütüyor (kalp atışındaki etiket önceliklidir: işe alım, ek inceleme)
    if ($Etiket -eq 'ise_alim') { return 'ik' }
    if ($Etiket -match '^inceleme-(.+)$') { return $Matches[1] }
    $asama = [string]$G.asama
    $tip = Gorev-Tipi $G
    if ($tip -eq 'altyapi') {
        $sorumlu = [string](Ozellik $G 'sorumlu'); if ($sorumlu -ne 'ag') { $sorumlu = 'sistem' }
        $destek = [string](Ozellik $G 'destek'); if ($destek -ne 'ag' -and $destek -ne 'sistem') { $destek = '' }
        if ($asama -eq 'gelistirme') { return $sorumlu }
        if ($asama -eq 'denetim' -or $asama -eq 'kontrol') { if ($destek) { return $destek }; return $sorumlu }
        return 'lider'
    }
    if ($tip -eq 'uzman') {
        $sorumlu = [string](Ozellik $G 'sorumlu'); if (-not $sorumlu) { $sorumlu = 'lider' }
        $inceleyen = [string](Ozellik $G 'inceleyen'); if ($inceleyen -eq 'yok') { $inceleyen = '' }
        if ($asama -eq 'gelistirme') { return $sorumlu }
        if ($asama -eq 'denetim') { if ($inceleyen) { return $inceleyen }; return 'lider' }
        if ($asama -eq 'kontrol') { if ($inceleyen) { return $inceleyen }; return $sorumlu }
        return 'lider'
    }
    return $AsamaRol[$asama]
}
function Asama-Adi-Bul($G) {
    $asama = [string]$G.asama
    $tip = Gorev-Tipi $G
    if ($tip -eq 'altyapi' -and $AltyapiAsamaAdlari.ContainsKey($asama)) { return $AltyapiAsamaAdlari[$asama] }
    if ($tip -eq 'uzman' -and $UzmanAsamaAdlari.ContainsKey($asama)) { return $UzmanAsamaAdlari[$asama] }
    if ($AsamaAdlari.ContainsKey($asama)) { return $AsamaAdlari[$asama] }
    return $asama
}

# ---------------------------------------------------------------- günlük
function Ofis-Kayit([string]$Mesaj, [string]$Seviye = 'BILGI') {
    $satir = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Seviye, $Mesaj
    try {
        if ([IO.File]::Exists($KayitDosyasi) -and (New-Object IO.FileInfo $KayitDosyasi).Length -gt 1MB) {
            Move-Item -LiteralPath $KayitDosyasi "$KayitDosyasi.eski" -Force
        }
        [IO.File]::AppendAllText($KayitDosyasi, $satir + "`r`n", $Utf8)
    } catch {}
    if ($Konsolda) { Write-Host $satir }
}

# ---------------------------------------------------------------- okuma (döngünün yazmalarını engellemeden)
function Paylasimli-Ac([string]$Yol) {
    return [IO.FileStream]::new($Yol, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
}
function Metin-Oku([string]$Yol, [int]$EnFazla = 0) {
    if (-not $Yol -or -not [IO.File]::Exists($Yol)) { return '' }
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $fs = Paylasimli-Ac $Yol
            try {
                $sr = [IO.StreamReader]::new($fs, $Utf8, $true)
                if ($EnFazla -le 0) { return $sr.ReadToEnd() }
                $tampon = New-Object char[] ($EnFazla + 1)
                $n = $sr.ReadBlock($tampon, 0, $tampon.Length)
                $m = [string]::new($tampon, 0, [Math]::Min($n, $EnFazla))
                if ($n -gt $EnFazla) { $m += "`n`n… (dosya uzun; ilk $EnFazla karakter gösteriliyor)" }
                return $m
            } finally { $fs.Dispose() }
        } catch {
            if (-not [IO.File]::Exists($Yol)) { return '' }
            Start-Sleep -Milliseconds 40
        }
    }
    return ''
}
function Json-Oku([string]$Yol) {
    $Yol = Yapilandirma-Yolu $Yol
    foreach ($aday in @($Yol, "$Yol.bak")) {
        $t = Metin-Oku $aday
        if ($t -and $t.Trim()) { try { return ($t | ConvertFrom-Json) } catch {} }
    }
    return $null
}
function Kuyruk-Oku([string]$Yol, [int]$Satir = 20, [int]$Bayt = 65536) {
    $sonuc = New-Object Collections.Generic.List[string]
    if (-not $Yol -or -not [IO.File]::Exists($Yol)) { return , $sonuc }
    try {
        $fs = Paylasimli-Ac $Yol
        try {
            $bas = [Math]::Max([long]0, $fs.Length - $Bayt)
            [void]$fs.Seek($bas, [IO.SeekOrigin]::Begin)
            $t = ([IO.StreamReader]::new($fs, $Utf8, $false)).ReadToEnd()
        } finally { $fs.Dispose() }
        $s = @($t -split "`r?`n" | Where-Object { $_.Trim() })
        if ($bas -gt 0 -and $s.Count -gt 0) { $s = @($s | Select-Object -Skip 1) }
        foreach ($x in @($s | Select-Object -Last $Satir)) { $sonuc.Add([string]$x) }
    } catch {}
    return , $sonuc
}
function Tarih($Deger) {
    if (-not $Deger) { return $null }
    try { return [datetime]$Deger } catch { return $null }
}
function Ozellik($Nesne, [string]$Ad) {
    if ($null -eq $Nesne) { return $null }
    $p = $Nesne.PSObject.Properties[$Ad]
    if ($p) { return $p.Value }
    return $null
}

# ---------------------------------------------------------------- görevler (değişmeyen dosyalar önbellekten)
$script:Onbellek = @{}
function Gorevleri-Oku {
    $liste = New-Object Collections.Generic.List[object]
    if (-not [IO.Directory]::Exists($YolGorev)) { return , $liste }
    $gorulen = @{}
    foreach ($d in [IO.Directory]::GetDirectories($YolGorev)) {
        $ad = [IO.Path]::GetFileName($d)
        $f = Join-Path $d 'durum.json'
        $fi = New-Object IO.FileInfo $f
        $g = $null
        if ($fi.Exists) {
            $damga = '{0}-{1}' -f $fi.LastWriteTimeUtc.Ticks, $fi.Length
            $o = $Onbellek[$ad]
            if ($o -and $o.damga -eq $damga) { $g = $o.nesne }
            else {
                $g = Json-Oku $f
                if ($g) { $Onbellek[$ad] = @{ damga = $damga; nesne = $g } }
            }
        } else { $g = Json-Oku $f }
        if ($g -and (Ozellik $g 'id')) { $liste.Add($g); $gorulen[$ad] = $true }
    }
    foreach ($k in @($Onbellek.Keys)) { if (-not $gorulen.ContainsKey($k)) { $Onbellek.Remove($k) } }
    $sirali = New-Object Collections.Generic.List[object]
    foreach ($g in @($liste | Sort-Object { [string]$_.id })) { $sirali.Add($g) }
    return , $sirali
}
function Gorev-Klasoru-Bul([string]$Id) {
    if ($Id -notmatch '^\d{4}-[A-Za-z0-9-]{1,60}$') { throw 'HTTP:400:Geçersiz görev numarası' }
    $gk = Join-Path $YolGorev $Id
    if (-not [IO.Directory]::Exists($gk)) { throw 'HTTP:404:Görev bulunamadı' }
    return $gk
}

# ---------------------------------------------------------------- araç uygunluğu (ortak.ps1 > Arac-Uygun'un hafif, salt okunur eşi)
function Sayac-Bugun {
    $s = Json-Oku (Join-Path $YolDurum 'sayaclar.json')
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    if (-not $s -or (Ozellik $s 'tarih') -ne $bugun) {
        $s = [pscustomobject]@{ tarih = $bugun; claude = 0; codex = 0; gemini = 0; tamamlanan = 0; takilan = 0 }
    }
    return $s
}
function Arac-Engeli($Giris, $Sayac, $Kilitler, $Ayar, $ClaudeKullanim, [datetime]$Simdi) {
    $arac = [string]$Giris.arac
    $sinir = [int](Ozellik $Ayar.gunluk_sinir $arac)
    $kul = [int](Ozellik $Sayac $arac)
    if ($sinir -gt 0 -and $kul -ge $sinir) { return "günlük sınır doldu ($kul/$sinir)" }
    foreach ($anahtar in @($arac, ('{0}:{1}' -f $arac, $Giris.model))) {
        $v = Ozellik $Kilitler $anahtar
        if ($v) {
            $b = Tarih $v.bitis
            if ($b -and $b -gt $Simdi) { return ('{0} ({1}''e kadar)' -f $v.neden, $b.ToString('HH:mm')) }
        }
    }
    if ($arac -eq 'claude' -and $ClaudeKullanim -and (Ozellik $ClaudeKullanim 'guncelleme_zamani')) {
        $gz = Tarih $ClaudeKullanim.guncelleme_zamani
        if ($gz) {
            $yas = ($Simdi - $gz).TotalHours
            if ($yas -lt [double]$Ayar.claude.kullanim_dosyasi_gecerlilik_saat -and [int]$ClaudeKullanim.kalan_yuzde -lt [int]$Ayar.claude.min_kalan_yuzde) {
                return "Claude kullanım hakkı az (kalan %$($ClaudeKullanim.kalan_yuzde))"
            }
        }
    }
    return ''
}

# ---------------------------------------------------------------- anlık durum (panel birkaç saniyede bir ister)
function Durum-Uret {
    $simdi = Get-Date
    $ayar = Json-Oku (Join-Path $Kok 'ayarlar.json')
    $kalp = Json-Oku (Join-Path $YolDurum 'kalp.json')
    $kilitler = Json-Oku (Join-Path $YolDurum 'kilitler.json')
    $sayac = Sayac-Bugun
    $claudeKullanim = $null
    if ($ayar -and $ayar.claude -and $ayar.claude.kullanim_dosyasi) { $claudeKullanim = Json-Oku ([string]$ayar.claude.kullanim_dosyasi) }
    $durdurYolu = Join-Path $Kok 'DURDUR'
    $duraklatildi = [IO.File]::Exists($durdurYolu)
    $bekciDk = 12.0
    if ($ayar -and $ayar.dongu -and $ayar.dongu.bekci_dk) { $bekciDk = [double]$ayar.dongu.bekci_dk }

    # ---- döngü sağlığı
    $kalpZaman = Tarih (Ozellik $kalp 'zaman')
    $yasSn = $null
    if ($kalpZaman) { $yasSn = [int][Math]::Round(($simdi - $kalpZaman).TotalSeconds) }
    $pidCanli = $false
    $kalpPid = [int](Ozellik $kalp 'pid')
    if ($kalpPid -gt 0) {
        $pr = Get-Process -Id $kalpPid -ErrorAction SilentlyContinue
        $pidCanli = [bool]($pr -and $pr.ProcessName -eq 'powershell')
    }
    $kalpDurum = [string](Ozellik $kalp 'durum')
    $saglik = 'saglikli'
    if (-not $kalp) { $saglik = 'bilinmiyor' }
    elseif (-not $pidCanli -or $kalpDurum -eq 'durdu') { $saglik = 'calismiyor' }
    elseif ($null -ne $yasSn -and $yasSn -gt ($bekciDk * 60)) { $saglik = 'donmus' }

    $gorevler = Gorevleri-Oku
    $aktif = $null
    $kalpGorev = [string](Ozellik $kalp 'gorev')
    if ($kalpGorev) { foreach ($g in $gorevler) { if ($g.id -eq $kalpGorev) { $aktif = $g; break } } }
    if ($aktif -and ($AktifAsamalar -notcontains [string]$aktif.asama)) { $aktif = $null }
    $bostaDurumlari = @('boşta', 'durduruldu', 'mesai dışı', 'durdu', '')
    $calisiyor = ($saglik -eq 'saglikli') -and ($bostaDurumlari -notcontains $kalpDurum) -and ($null -ne $aktif)

    $anlikArac = ''
    $kalpEtiket = ''
    $kalpAdim = [string](Ozellik $kalp 'adim')
    if ($calisiyor -and $kalpAdim -match '^(\S+) \((.+)\)$') {
        $kalpEtiket = $Matches[1]; $kimlikAnlik = $Matches[2]
        $etiket = $kalpEtiket
        if ($etiket -match '^inceleme-') { $etiket = 'denetim' }
        if ($EtiketAsama.ContainsKey($etiket)) { $etiket = $EtiketAsama[$etiket] }
        if ($etiket -eq [string]$aktif.asama) { $anlikArac = $kimlikAnlik } else { $kalpEtiket = '' }
    }
    $epostaKurulu = [IO.File]::Exists((Join-Path $YolDurum 'eposta.json'))

    # ---- roller (kadro.json sırasıyla)
    $kadro = Kadro-Listesi
    $roller = New-Object Collections.Generic.List[object]
    foreach ($uye in $kadro) {
        $rol = [string]$uye.anahtar
        $aktifTip = ''; if ($aktif) { $aktifTip = Gorev-Tipi $aktif }
        $haric = @()
        if ($aktifTip -eq 'yazilim' -and ($rol -eq 'denetci' -or $kalpEtiket -eq "inceleme-$rol") -and (Ozellik $aktif 'gelistirici')) { $haric = @([string]$aktif.gelistirici) }
        if ($aktifTip -eq 'altyapi' -and $rol -eq [string](Ozellik $aktif 'destek') -and (Ozellik $aktif 'uygulayan')) { $haric = @([string]$aktif.uygulayan) }
        if ($aktifTip -eq 'uzman' -and $rol -eq [string](Ozellik $aktif 'inceleyen') -and (Ozellik $aktif 'uygulayan')) { $haric = @([string]$aktif.uygulayan) }
        $zincir = New-Object Collections.Generic.List[object]
        $siradaki = ''
        $girisler = @()
        $ayarZinciri = $null; if ($ayar -and $ayar.roller) { $ayarZinciri = Ozellik $ayar.roller $rol }
        if ($ayarZinciri) { $girisler = @($ayarZinciri) } elseif ($uye.araclar) { $girisler = @($uye.araclar) }
        foreach ($gi in $girisler) {
            if (-not $gi) { continue }
            $kimlik = '{0}/{1}' -f $gi.arac, $gi.model
            $neden = ''
            if ($haric -contains $kimlik) { $neden = 'işi yapanla aynı model; incelemede atlanır' }
            else { $neden = Arac-Engeli $gi $sayac $kilitler $ayar $claudeKullanim $simdi }
            if (-not $neden -and -not $siradaki) { $siradaki = $kimlik }
            $zincir.Add([ordered]@{ kimlik = $kimlik; arac = [string]$gi.arac; model = [string]$gi.model; neden = $neden })
        }
        $isbasinda = $calisiyor -and ((Gorev-Rolu $aktif $kalpEtiket) -eq $rol)
        $faaliyet = 'bosta'; $metin = 'Boşta'; $gorevBilgi = $null; $baslangic = $null
        $arac = $siradaki; $aracKaynak = 'sıradaki'; $not = ''
        if ($isbasinda) {
            $asama = [string]$aktif.asama
            $altyapi = ($aktifTip -eq 'altyapi')
            if ($kalpEtiket -eq 'ise_alim') { $faaliyet = 'ise_alim'; $metin = 'İşe alım yapıyor' }
            elseif ($kalpEtiket -match '^inceleme-') { $faaliyet = 'inceleme'; $metin = 'Kodu kendi alanından inceliyor' }
            elseif ($altyapi) {
                $faaliyet = $AltyapiFaaliyet[$asama]; $metin = $AltyapiMetni[$asama]
                if ($asama -eq 'gelistirme' -and $rol -eq 'ag') { $metin = 'Ağ işini yapıyor' }
            } elseif ($aktifTip -eq 'uzman') {
                $faaliyet = $UzmanFaaliyet[$asama]; $metin = $UzmanMetni[$asama]
                if ($asama -eq 'gelistirme' -and $uye.faaliyet_metni) { $metin = [string]$uye.faaliyet_metni }
            } else { $faaliyet = $AsamaFaaliyet[$asama]; $metin = $AsamaMetni[$asama] }
            $gorevBilgi = [ordered]@{ id = $aktif.id; baslik = $aktif.baslik; tur = $aktif.tur; max_tur = $aktif.max_tur }
            $baslangic = Ozellik $aktif 'olusturma'
            $gecmis = @(Ozellik $aktif 'gecmis')
            if ($gecmis.Count -gt 0 -and $gecmis[-1]) { $baslangic = $gecmis[-1].zaman }
            if ($anlikArac) { $arac = $anlikArac; $aracKaynak = 'şu an' }
            elseif ($asama -eq 'kontrol') { $arac = $(if ($aktifTip -eq 'yazilim') { 'betik · otomatik kontrol' } else { 'betik · doğrulama komutları' }); $aracKaynak = 'şu an' }
            elseif ($asama -eq 'yeni' -or $asama -eq 'tamamla') { $arac = $(if ($altyapi) { 'betik · keşif' } elseif ($aktifTip -eq 'uzman') { 'betik' } else { 'git' }); $aracKaynak = 'şu an' }
        } else {
            foreach ($g in $gorevler) {
                $sd = Tarih (Ozellik $g 'sonraki_deneme')
                if (($AktifAsamalar -contains [string]$g.asama) -and (Gorev-Rolu $g) -eq $rol -and $sd -and $sd -gt $simdi) {
                    $faaliyet = 'bekliyor'; $metin = 'Yeniden denemeyi bekliyor'
                    $gorevBilgi = [ordered]@{ id = $g.id; baslik = $g.baslik; tur = $g.tur; max_tur = $g.max_tur }
                    $not = 'Son deneme başarısız; {0} civarı yeniden denenecek.' -f $sd.ToString('HH:mm')
                    break
                }
            }
            if ($rol -eq 'lider') {
                foreach ($g in $gorevler) {
                    if ([string]$g.asama -eq 'bekliyor_kullanici') {
                        $faaliyet = 'soru'; $metin = 'Senden yanıt bekliyor'
                        $gorevBilgi = [ordered]@{ id = $g.id; baslik = $g.baslik; tur = $g.tur; max_tur = $g.max_tur }
                        $baslangic = Ozellik $g 'soru_zamani'
                        break
                    }
                }
            }
        }
        if (-not $not -and $rol -eq 'iletisim' -and -not $epostaKurulu) { $not = 'E-posta hesabı kurulmadı (eposta-kur.ps1); bildirimler çalışır.' }
        $sonKullanilan = ''
        foreach ($g in @($gorevler | Sort-Object { [string](Ozellik $_ 'guncelleme') } -Descending)) {
            $v = [string](Ozellik $g $rol)
            if ($v -and $v -match '/') { $sonKullanilan = $v; break }
        }
        $iseAlinma = Tarih (Ozellik $uye 'ise_alinma')
        $roller.Add([ordered]@{
            anahtar = $rol; ad = [string]$uye.ad; departman = [string]$uye.departman; renk = [string](Ozellik $uye 'renk'); renk_koyu = [string](Ozellik $uye 'renk_koyu')
            uzmanlik = [string](Ozellik $uye 'uzmanlik'); yetki = [string](Ozellik $uye 'yetki'); yerlesik = [bool](Ozellik $uye 'yerlesik')
            uzman_isi = [bool](Ozellik $uye 'uzman_isi'); tanisma = [string](Ozellik $uye 'tanisma'); ise_alan = [string](Ozellik $uye 'ise_alan')
            yeni = [bool]($iseAlinma -and ($simdi - $iseAlinma).TotalDays -lt 7)
            faaliyet = $faaliyet; metin = $metin; calisiyor = [bool]$isbasinda
            gorev = $gorevBilgi; baslangic = $baslangic; arac = $arac; arac_kaynak = $aracKaynak; zincir = $zincir
            not = $not; son_kullanilan = $sonKullanilan
            sohbette = [bool](Sohbet-Isleniyor $rol); sohbet_son = (Sohbet-Son $rol)
        })
    }

    # ---- görev kartları
    $kartlar = New-Object Collections.Generic.List[object]
    foreach ($g in $gorevler) {
        $son = $null
        $gecmis = @(Ozellik $g 'gecmis')
        if ($gecmis.Count -gt 0) { $son = $gecmis[-1] }
        $asama = [string]$g.asama
        $ad = Asama-Adi-Bul $g
        $kartlar.Add([ordered]@{
            id = $g.id; baslik = $g.baslik; proje = $g.proje; asama = $asama; asama_adi = $ad
            tip = (Gorev-Tipi $g); hedef = @(Ozellik $g 'hedef' | Where-Object { $_ })
            sorumlu = (Ozellik $g 'sorumlu'); destek = (Ozellik $g 'destek'); inceleyen = (Ozellik $g 'inceleyen'); hedef_rol = (Ozellik $g 'hedef_rol')
            tur = $g.tur; max_tur = $g.max_tur; dal = (Ozellik $g 'dal'); oncelik = $g.oncelik
            son_olay = (Ozellik $son 'olay'); son_zaman = (Ozellik $son 'zaman')
            son_hata = (Ozellik $g 'son_hata'); ozet = (Ozellik $g 'ozet'); commit = (Ozellik $g 'commit')
            sonraki_deneme = (Ozellik $g 'sonraki_deneme'); guncelleme = (Ozellik $g 'guncelleme'); olusturma = (Ozellik $g 'olusturma')
            lider = (Ozellik $g 'lider'); gelistirici = (Ozellik $g 'gelistirici'); denetci = (Ozellik $g 'denetci')
            aktif = [bool]($calisiyor -and $aktif.id -eq $g.id)
        })
    }

    # ---- bildirimler, günlük, kilitler, projeler
    $bildirimler = New-Object Collections.Generic.List[object]
    $satirlar = Kuyruk-Oku (Join-Path $YolDurum 'bildirimler.jsonl') 15
    for ($i = $satirlar.Count - 1; $i -ge 0; $i--) {
        try {
            $b = $satirlar[$i] | ConvertFrom-Json
            $bildirimler.Add([ordered]@{ zaman = $b.zaman; baslik = $b.baslik; metin = $b.metin; onem = $b.onem })
        } catch {}
    }
    $gunluk = Kuyruk-Oku (Join-Path $YolGunluk ('ekip-{0}.log' -f $simdi.ToString('yyyyMMdd'))) 40
    $aktifKilitler = New-Object Collections.Generic.List[object]
    if ($kilitler) {
        foreach ($p in $kilitler.PSObject.Properties) {
            $b = Tarih (Ozellik $p.Value 'bitis')
            if ($b -and $b -gt $simdi) { $aktifKilitler.Add([ordered]@{ anahtar = $p.Name; neden = $p.Value.neden; bitis = $p.Value.bitis }) }
        }
    }
    $projeler = New-Object Collections.Generic.List[object]
    $pj = Json-Oku (Join-Path $Kok 'projeler.json')
    if ($pj) { foreach ($x in @($pj.projeler)) { if ($x) { $projeler.Add([ordered]@{ ad = $x.ad; klasor = $x.klasor }) } } }

    $makineler = New-Object Collections.Generic.List[object]
    if ($ayar -and $ayar.altyapi) { foreach ($m in @($ayar.altyapi.makineler)) { if ($m) { $makineler.Add([ordered]@{ ad = $m.ad; ip = $m.ip; aciklama = $m.aciklama }) } } }
    $sinir = [ordered]@{ claude = 0; codex = 0; gemini = 0 }
    if ($ayar -and $ayar.gunluk_sinir) { foreach ($k in @('claude', 'codex', 'gemini')) { $sinir[$k] = [int](Ozellik $ayar.gunluk_sinir $k) } }
    $duyurular = New-Object Collections.Generic.List[object]
    $dsat = Kuyruk-Oku (Join-Path $YolDurum 'duyurular.jsonl') 10
    for ($i = $dsat.Count - 1; $i -ge 0; $i--) { try { $duyurular.Add(($dsat[$i] | ConvertFrom-Json)) } catch {} }

    return [ordered]@{
        zaman = $simdi.ToString('o')
        kok = $Kok
        dongu = [ordered]@{
            saglik = $saglik; calisiyor = [bool]$calisiyor; duraklatildi = $duraklatildi
            durdur_metni = $(if ($duraklatildi) { (Metin-Oku $durdurYolu 500).Trim() } else { '' })
            kalp_durum = $kalpDurum; kalp_zaman = (Ozellik $kalp 'zaman'); kalp_gorev = $kalpGorev; kalp_adim = $kalpAdim
            yas_sn = $yasSn; pid = $kalpPid; pid_canli = $pidCanli; bekci_dk = $bekciDk
            aktif_gorev = $(if ($aktif) { $aktif.id } else { '' })
        }
        roller = $roller
        gorevler = $kartlar
        sayaclar = [ordered]@{
            tarih = $sayac.tarih; tamamlanan = [int](Ozellik $sayac 'tamamlanan'); takilan = [int](Ozellik $sayac 'takilan')
            claude = [int](Ozellik $sayac 'claude'); codex = [int](Ozellik $sayac 'codex'); gemini = [int](Ozellik $sayac 'gemini')
            sinir = $sinir
        }
        kilitler = $aktifKilitler
        bildirimler = $bildirimler
        gunluk = $gunluk
        projeler = $projeler
        makineler = $makineler
        duyurular = $duyurular
        eposta_kurulu = $epostaKurulu
    }
}
# Görevin çalışma klasöründeki dosyalar (uzman ve altyapı işlerinin teslimleri; önizleme /onizle üzerinden)
function Cikti-Listesi([string]$Id) {
    $l = New-Object Collections.Generic.List[object]
    $wt = Join-Path (Join-Path $Kok 'calisma') $Id
    if (-not [IO.Directory]::Exists($wt) -or [IO.File]::Exists((Join-Path $wt '.git'))) { return , $l }
    $tum = @(Get-ChildItem -LiteralPath $wt -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|__pycache__)\\' })
    $sirali = @($tum | Sort-Object @{ e = { if ($_.FullName -like "$wt\cikti\*") { 0 } else { 1 } } }, FullName | Select-Object -First 400)
    foreach ($f in $sirali) {
        $l.Add([ordered]@{ yol = ($f.FullName.Substring($wt.Length + 1) -replace '\\', '/'); boyut = $f.Length; zaman = $f.LastWriteTime.ToString('o'); uzanti = $f.Extension.ToLowerInvariant() })
    }
    return , $l
}

# ---------------------------------------------------------------- görev ayrıntısı ve dosyaları
function Dosya-Listesi([string]$Klasor, [string]$Onek) {
    $l = New-Object Collections.Generic.List[object]
    if (-not [IO.Directory]::Exists($Klasor)) { return , $l }
    foreach ($f in @(Get-ChildItem -LiteralPath $Klasor -File | Where-Object { $_.Extension -in @('.md', '.txt', '.diff') } | Sort-Object Name)) {
        $l.Add([ordered]@{ ad = $f.Name; yol = ($Onek + $f.Name); boyut = $f.Length; zaman = $f.LastWriteTime.ToString('o') })
    }
    return , $l
}
function Gorev-Ayrinti([string]$Id) {
    $gk = Gorev-Klasoru-Bul $Id
    $g = Json-Oku (Join-Path $gk 'durum.json')
    $turlar = New-Object Collections.Generic.List[object]
    $turKlasorleri = @(Get-ChildItem -LiteralPath $gk -Directory | Where-Object { $_.Name -match '^tur\d+$' } | Sort-Object { [int]$_.Name.Substring(3) })
    foreach ($td in $turKlasorleri) {
        $turlar.Add([ordered]@{ no = [int]$td.Name.Substring(3); dosyalar = (Dosya-Listesi $td.FullName "$($td.Name)/") })
    }
    $sorular = Join-Path $gk 'sorular.md'
    return [ordered]@{
        durum = $g
        asama_adi = $(if ($g) { Asama-Adi-Bul $g } else { '' })
        tip = $(if ($g) { Gorev-Tipi $g } else { 'yazilim' })
        ciktilar = (Cikti-Listesi $Id)
        sonuc_md = (Metin-Oku (Join-Path $gk 'sonuc.md') 100000)
        kesif_md = (Metin-Oku (Join-Path $gk 'kesif.md') 50000)
        gorev_md = (Metin-Oku (Join-Path $gk 'gorev.md') 200000)
        plan_md = (Metin-Oku (Join-Path $gk 'plan.md') 200000)
        plan_gecersiz_md = (Metin-Oku (Join-Path $gk 'plan-gecersiz.md') 100000)
        sorular_md = (Metin-Oku $sorular 100000)
        sorular_zaman = $(if ([IO.File]::Exists($sorular)) { (New-Object IO.FileInfo $sorular).LastWriteTime.ToString('o') } else { $null })
        bekleyen_geri_bildirim = (Metin-Oku (Join-Path $gk 'bekleyen-geri-bildirim.md') 100000)
        turlar = $turlar
        kayitlar = (Dosya-Listesi (Join-Path $gk 'kayitlar') 'kayitlar/')
        ust_dosyalar = (Dosya-Listesi $gk '')
    }
}
function Gorev-Dosyasi-Oku([string]$Id, [string]$Yol) {
    $gk = Gorev-Klasoru-Bul $Id
    if ($Yol -notmatch '^((tur\d{1,3}|kayitlar)/)?[A-Za-z0-9][A-Za-z0-9._-]{0,150}$' -or $Yol -match '\.\.') { throw 'HTTP:400:Geçersiz dosya yolu' }
    if ($Yol -notmatch '\.(md|txt|diff|err)$') { throw 'HTTP:400:Bu dosya türü gösterilmiyor' }
    $tam = Join-Path $gk ($Yol -replace '/', '\')
    if (-not [IO.File]::Exists($tam)) { throw 'HTTP:404:Dosya bulunamadı' }
    return (Metin-Oku $tam 400000)
}

# ---------------------------------------------------------------- dış süreçler
function Surec-Cikti([string]$Exe, [string]$Argumanlar, [string]$Klasor, [int]$ZamanAsimiSn = 60) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Argumanlar
    $psi.WorkingDirectory = $Klasor
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8
    $psi.StandardErrorEncoding = $Utf8
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($ZamanAsimiSn * 1000)) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $p.Id 2>&1 | Out-Null } catch {} finally { $ErrorActionPreference = $eap }
        [void]$p.WaitForExit(5000)
        return [pscustomobject]@{ kod = -1; cikti = ''; hata = "zaman aşımı ($ZamanAsimiSn sn)" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ kod = $p.ExitCode; cikti = $o.Result; hata = $e.Result }
}
function Ps-Tirnak([string]$Metin) {
    # PowerShell tek tırnak dizesi; Unicode tek tırnaklar (‘ ’ ‚ ‛) da dizeyi kapatabildiği için ikilenir
    $temiz = $Metin -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    return "'" + ($temiz -replace '([‘’‚‛''])', '$1$1') + "'"
}
function Betik-Calistir([string]$Betik, [string]$ArgMetni, [int]$ZamanAsimiSn = 120) {
    $yol = Join-Path $Kok $Betik
    if (-not [IO.File]::Exists($yol)) { throw "HTTP:500:Betik bulunamadı: $Betik" }
    $komut = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {
    & $(Ps-Tirnak $yol) $ArgMetni
    exit 0
} catch {
    [Console]::Out.WriteLine('HATA: ' + `$_.Exception.Message)
    exit 1
}
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($komut))
    Ofis-Kayit "Çalıştırılıyor: $Betik $(if ($ArgMetni.Length -gt 160) { $ArgMetni.Substring(0, 160) + '…' } else { $ArgMetni })"
    $s = Surec-Cikti $PsExe "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $b64" $Kok $ZamanAsimiSn
    $cikti = (([string]$s.cikti) -replace "`r", '').Trim()
    $hata = (([string]$s.hata) -replace "`r", '').Trim()
    if ($hata -match '^#< CLIXML') { $hata = '' }
    $basarili = ($s.kod -eq 0)
    $mesaj = ''
    if (-not $basarili) {
        $m = [regex]::Match($cikti, '(?m)^HATA: (.+)$')
        if ($m.Success) { $mesaj = $m.Groups[1].Value } elseif ($hata) { $mesaj = $hata } else { $mesaj = "çıkış kodu $($s.kod)" }
    }
    Ofis-Kayit ("Bitti: {0} (kod {1}) {2}" -f $Betik, $s.kod, $mesaj)
    return [ordered]@{ basarili = $basarili; cikti = $cikti; hata = $mesaj }
}
function Git-Cikti([string]$Klasor, [string]$ArgMetni) {
    $s = Surec-Cikti 'git' ("-c core.quotepath=off --no-pager -C `"$Klasor`" $ArgMetni") $Klasor 30
    return $s
}
function Diff-Uret([string]$Id) {
    $gk = Gorev-Klasoru-Bul $Id
    $g = Json-Oku (Join-Path $gk 'durum.json')
    if (-not $g) { throw 'HTTP:404:Görev durumu okunamadı' }
    if (Altyapi-Mi $g) { return '# Bu bir sunucu / kurulum talebi; git diff yok. Yapılanlar için Turlar sekmesindeki uygulama ve doğrulama raporlarına bak.' }
    if ((Gorev-Tipi $g) -eq 'uzman') { return '# Bu bir uzman işi; git diff yok. Teslimler için Çıktılar sekmesine bak.' }
    $temel = [string](Ozellik $g 'temel_commit')
    $dal = [string](Ozellik $g 'dal')
    $wt = [string](Ozellik $g 'calisma_klasoru')
    $proje = [string](Ozellik $g 'klasor')
    if (-not $temel) { return 'Bu görev henüz bir çalışma dalı açmadı; gösterilecek diff yok.' }
    if ($temel -notmatch '^[0-9a-f]{7,40}$') { throw 'HTTP:400:Geçersiz temel commit' }
    if ($dal -and $dal -notmatch '^[A-Za-z0-9._/-]+$') { throw 'HTTP:400:Geçersiz dal adı' }
    $baslik = ''; $s = $null; $ek = ''
    if ($wt -and [IO.Directory]::Exists($wt) -and -not (Ozellik $g 'calisma_klasoru_kaldirildi')) {
        $baslik = "# Çalışma klasöründeki güncel değişiklikler ($temel..çalışma ağacı)"
        $s = Git-Cikti $wt "diff --no-color $temel"
        $yeni = Git-Cikti $wt 'ls-files --others --exclude-standard'
        $yeniler = @(([string]$yeni.cikti) -split "`r?`n" | Where-Object { $_.Trim() })
        if ($yeniler.Count -gt 0) { $ek = "`n# Henüz git'e eklenmemiş yeni dosyalar:`n" + (($yeniler | ForEach-Object { "#   $_" }) -join "`n") }
    } elseif ($dal -and $proje -and [IO.Directory]::Exists($proje)) {
        $baslik = "# $dal dalı ($temel..$dal)"
        $s = Git-Cikti $proje "diff --no-color $temel $dal"
    } else {
        return 'Çalışma klasörü ya da dal bulunamadı.'
    }
    if ($s.kod -ne 0) { return "$baslik`n# git hata verdi: $($s.hata)" }
    $metin = [string]$s.cikti
    if (-not $metin.Trim()) { $metin = '# (değişiklik yok)' }
    $sinir = 600000
    if ($metin.Length -gt $sinir) { $metin = $metin.Substring(0, $sinir) + "`n# … diff $sinir karakterde kesildi" }
    return "$baslik$ek`n$metin"
}

# ---------------------------------------------------------------- eylemler
function Govde-Coz([string]$Govde) {
    if (-not $Govde -or -not $Govde.Trim()) { return [pscustomobject]@{} }
    try { return ($Govde | ConvertFrom-Json) } catch { throw 'HTTP:400:İstek gövdesi JSON değil' }
}
function Metin-Alani($Nesne, [string]$Ad, [int]$EnFazla, [switch]$Zorunlu) {
    $v = [string](Ozellik $Nesne $Ad)
    $v = $v.Trim()
    if ($Zorunlu -and -not $v) { throw "HTTP:400:'$Ad' alanı boş olamaz" }
    if ($v.Length -gt $EnFazla) { throw "HTTP:400:'$Ad' çok uzun (en fazla $EnFazla karakter)" }
    return $v
}
function Liste-Alani($Nesne, [string]$Ad, [int]$Adet, [int]$EnFazla) {
    $l = @()
    foreach ($x in @(Ozellik $Nesne $Ad)) {
        $s = ([string]$x).Trim()
        if (-not $s) { continue }
        if ($s.Length -gt $EnFazla) { throw "HTTP:400:'$Ad' içinde çok uzun satır var (en fazla $EnFazla karakter)" }
        $l += $s
    }
    if ($l.Count -gt $Adet) { throw "HTTP:400:'$Ad' en fazla $Adet satır olabilir" }
    return , $l
}
function Eylem-GorevEkle($Veri) {
    $proje = Metin-Alani $Veri 'proje' 400 -Zorunlu
    $baslik = Metin-Alani $Veri 'baslik' 120 -Zorunlu
    $aciklama = Metin-Alani $Veri 'aciklama' 8000 -Zorunlu
    $kabul = Liste-Alani $Veri 'kabul' 20 500
    $dogrulama = Liste-Alani $Veri 'dogrulama' 10 300
    $oncelik = [int](Ozellik $Veri 'oncelik')
    if ($oncelik -lt 1 -or $oncelik -gt 3) { $oncelik = 2 }
    $a = @('-Proje', (Ps-Tirnak $proje), '-Baslik', (Ps-Tirnak $baslik), '-Aciklama', (Ps-Tirnak $aciklama))
    if ($kabul.Count -gt 0) { $a += '-Kabul'; $a += ('@(' + (($kabul | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    if ($dogrulama.Count -gt 0) { $a += '-Dogrulama'; $a += ('@(' + (($dogrulama | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    $a += '-Oncelik'; $a += [string]$oncelik
    $r = Betik-Calistir 'gorev-ekle.ps1' ($a -join ' ')
    $m = [regex]::Match([string]$r.cikti, 'Görev eklendi: (\S+)')
    if ($m.Success) { $r['id'] = $m.Groups[1].Value }
    return $r
}
function Eylem-TalepEkle($Veri) {
    $baslik = Metin-Alani $Veri 'baslik' 120 -Zorunlu
    $aciklama = Metin-Alani $Veri 'aciklama' 8000 -Zorunlu
    $hedef = Liste-Alani $Veri 'hedef' 20 80
    $kabul = Liste-Alani $Veri 'kabul' 20 500
    $dogrulama = Liste-Alani $Veri 'dogrulama' 10 300
    $oncelik = [int](Ozellik $Veri 'oncelik')
    if ($oncelik -lt 1 -or $oncelik -gt 3) { $oncelik = 2 }
    $a = @('-Baslik', (Ps-Tirnak $baslik), '-Aciklama', (Ps-Tirnak $aciklama))
    if ($hedef.Count -gt 0) { $a += '-Hedef'; $a += ('@(' + (($hedef | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    if ($kabul.Count -gt 0) { $a += '-Kabul'; $a += ('@(' + (($kabul | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    if ($dogrulama.Count -gt 0) { $a += '-Dogrulama'; $a += ('@(' + (($dogrulama | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    $a += '-Oncelik'; $a += [string]$oncelik
    $r = Betik-Calistir 'talep-ekle.ps1' ($a -join ' ')
    $m = [regex]::Match([string]$r.cikti, 'Talep eklendi: (\S+)')
    if ($m.Success) { $r['id'] = $m.Groups[1].Value }
    return $r
}
function Eylem-UzmanEkle($Veri) {
    $baslik = Metin-Alani $Veri 'baslik' 120 -Zorunlu
    $aciklama = Metin-Alani $Veri 'aciklama' 8000 -Zorunlu
    $rol = Metin-Alani $Veri 'rol' 40
    $klasor = Metin-Alani $Veri 'klasor' 400
    $kabul = Liste-Alani $Veri 'kabul' 20 500
    $dogrulama = Liste-Alani $Veri 'dogrulama' 10 300
    $oncelik = [int](Ozellik $Veri 'oncelik')
    if ($oncelik -lt 1 -or $oncelik -gt 3) { $oncelik = 2 }
    if ($rol -and $rol -notmatch '^[a-z][a-z0-9-]{1,39}$') { throw 'HTTP:400:Geçersiz çalışan anahtarı' }
    $a = @('-Baslik', (Ps-Tirnak $baslik), '-Aciklama', (Ps-Tirnak $aciklama))
    if ($rol) { $a += '-Rol'; $a += (Ps-Tirnak $rol) }
    if ($klasor) { $a += '-Klasor'; $a += (Ps-Tirnak $klasor) }
    if ($kabul.Count -gt 0) { $a += '-Kabul'; $a += ('@(' + (($kabul | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    if ($dogrulama.Count -gt 0) { $a += '-Dogrulama'; $a += ('@(' + (($dogrulama | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    $a += '-Oncelik'; $a += [string]$oncelik
    $r = Betik-Calistir 'uzman-ekle.ps1' ($a -join ' ')
    $m = [regex]::Match([string]$r.cikti, 'İş eklendi: (\S+)')
    if ($m.Success) { $r['id'] = $m.Groups[1].Value }
    return $r
}
# /onizle/<önizleme anahtarı>/<görev no>/<göreli yol> : görevin çalışma klasöründeki teslimleri gösterir (salt okunur).
# Anahtar URL'de olduğundan <img>, <iframe> ve göreli bağlantılar çalışır; HTML/SVG belgeleri CSP sandbox ile
# kökeni olmayan bir ortamda açılır (panel API'sine erişemez).
$script:IcerikTurleri = @{
    '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.svg' = 'image/svg+xml'
    '.ico' = 'image/x-icon'; '.bmp' = 'image/bmp'; '.html' = 'text/html; charset=utf-8'; '.htm' = 'text/html; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
    '.md' = 'text/plain; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'; '.csv' = 'text/plain; charset=utf-8'; '.log' = 'text/plain; charset=utf-8'
    '.xml' = 'text/plain; charset=utf-8'; '.yaml' = 'text/plain; charset=utf-8'; '.yml' = 'text/plain; charset=utf-8'; '.ps1' = 'text/plain; charset=utf-8'
    '.py' = 'text/plain; charset=utf-8'; '.sql' = 'text/plain; charset=utf-8'; '.pdf' = 'application/pdf'; '.mp3' = 'audio/mpeg'; '.wav' = 'audio/wav'
    '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.woff2' = 'font/woff2'; '.ttf' = 'font/ttf'
}
function Onizleme-Gonder($Akis, [string]$Yol) {
    $m = [regex]::Match($Yol, '^/onizle/([0-9a-f]{32,64})/(\d{4}-[A-Za-z0-9-]{1,60})/(.+)$')
    if (-not $m.Success -or $m.Groups[1].Value -cne $OnizlemeAnahtari) { Yanit-Metin $Akis 404 'Bulunamadı'; return }
    $wt = [IO.Path]::GetFullPath((Join-Path (Join-Path $Kok 'calisma') $m.Groups[2].Value))
    $parcalar = @($m.Groups[3].Value.Split('/') | ForEach-Object { [Uri]::UnescapeDataString($_) })
    foreach ($p in $parcalar) { if (-not $p -or $p -eq '.' -or $p -eq '..' -or $p -match '[\\:*?"<>|]') { Yanit-Metin $Akis 400 'Geçersiz yol'; return } }
    $tam = [IO.Path]::GetFullPath((Join-Path $wt ($parcalar -join '\')))
    if (-not $tam.StartsWith($wt + '\', [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($tam)) { Yanit-Metin $Akis 404 'Bulunamadı'; return }
    $fi = New-Object IO.FileInfo $tam
    if ($fi.Length -gt 40MB) { Yanit-Metin $Akis 413 'Dosya önizleme için çok büyük'; return }
    $uz = $fi.Extension.ToLowerInvariant()
    $tur = 'application/octet-stream'; if ($IcerikTurleri.ContainsKey($uz)) { $tur = $IcerikTurleri[$uz] }
    $baytlar = $null
    $fs = Paylasimli-Ac $tam
    try { $baytlar = New-Object byte[] $fs.Length; [void]$fs.Read($baytlar, 0, $baytlar.Length) } finally { $fs.Dispose() }
    $ek = @{ 'Content-Security-Policy' = "sandbox allow-scripts; frame-ancestors 'self'" }
    if ($tur -eq 'application/octet-stream') { $ek['Content-Disposition'] = 'attachment' }
    Yanit-Gonder $Akis 200 $tur $baytlar $ek
}
function Eylem-Yanit($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    $yanit = Metin-Alani $Veri 'yanit' 8000 -Zorunlu
    $gk = Gorev-Klasoru-Bul $id
    $g = Json-Oku (Join-Path $gk 'durum.json')
    $f = Join-Path $gk 'gorev.md'
    if (-not [IO.File]::Exists($f)) { throw 'HTTP:404:gorev.md bulunamadı' }
    $mevcut = Metin-Oku $f
    $ek = "`n`n### Yanıt ({0})`n`n{1}`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm'), (($yanit -replace "`r`n", "`n").Trim())
    # ortak.ps1 > Metin-Yaz ile aynı biçim: UTF-8 (BOM'suz), geçici dosya + yedekli değiştirme
    $tmp = "$f.tmp"
    [IO.File]::WriteAllText($tmp, $mevcut.TrimEnd() + $ek, $Utf8)
    [IO.File]::Replace($tmp, $f, "$f.bak")
    Ofis-Kayit "Yanıt gorev.md'ye eklendi: $id"
    $not = 'Yanıt gorev.md dosyasına eklendi.'
    if ($g -and [string]$g.asama -eq 'bekliyor_kullanici') { $not += ' Ekip değişikliği görüp görevi yeniden planlayacak (genellikle 1 dakika içinde).' }
    return [ordered]@{ basarili = $true; cikti = $not; hata = '' }
}
function Eylem-Devam($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    $not = Metin-Alani $Veri 'not' 4000
    [void](Gorev-Klasoru-Bul $id)
    $a = '-Devam ' + (Ps-Tirnak $id)
    if ($not) { $a += ' -Not ' + (Ps-Tirnak $not) }
    return (Betik-Calistir 'durum.ps1' $a)
}
function Eylem-Iptal($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    [void](Gorev-Klasoru-Bul $id)
    return (Betik-Calistir 'durum.ps1' ('-Iptal ' + (Ps-Tirnak $id)))
}
# ---------------------------------------------------------------- sohbet (çalışanlarla yazışma)
# Her mesaj durum\sohbet\<rol>.jsonl'a eklenir; yanıtı arka planda sohbet.ps1 yazar (salt okunur, rolün araç zinciriyle).
$script:YolSohbet = Join-Path $YolDurum 'sohbet'
function Sohbet-Rolu([string]$Rol) {
    if ($Rol -notmatch '^[a-z0-9-]{1,40}$') { throw 'HTTP:400:Geçersiz çalışan' }
    if (-not (Kadro-Bul (Kadro-Listesi) $Rol)) { throw 'HTTP:404:Kadroda böyle bir çalışan yok' }
    return $Rol
}
function Sohbet-Isleniyor([string]$Rol) {
    $f = Join-Path $YolSohbet "$Rol.isleniyor"
    if (-not [IO.File]::Exists($f)) { return $null }
    $t = Json-Oku $f
    $pidNo = [int](Ozellik $t 'pid')
    if ($pidNo -gt 0 -and (Get-Process -Id $pidNo -ErrorAction SilentlyContinue)) { return $t }
    if ($t -and (Tarih (Ozellik $t 'zaman')) -and ((Get-Date) - (Tarih (Ozellik $t 'zaman'))).TotalSeconds -lt 15) { return $t }   # süreç yeni başlıyor
    try { [IO.File]::Delete($f) } catch {}   # süreç ölmüş; işareti kaldır
    return $null
}
function Sohbet-Son([string]$Rol) {
    $l = Kuyruk-Oku (Join-Path $YolSohbet "$Rol.jsonl") 1 65536
    if ($l.Count -eq 0) { return $null }
    try { $m = $l[$l.Count - 1] | ConvertFrom-Json; return [ordered]@{ zaman = $m.zaman; kim = $m.kim } } catch { return $null }
}
function Sohbet-Oku([string]$Rol) {
    $Rol = Sohbet-Rolu $Rol
    $l = New-Object Collections.Generic.List[object]
    foreach ($s in (Kuyruk-Oku (Join-Path $YolSohbet "$Rol.jsonl") 80 262144)) { try { $l.Add(($s | ConvertFrom-Json)) } catch {} }
    $i = Sohbet-Isleniyor $Rol
    return [ordered]@{ rol = $Rol; mesajlar = $l; dusunuyor = [bool]$i; baslangic = (Ozellik $i 'zaman') }
}
function Eylem-Sohbet($Veri) {
    $rol = Sohbet-Rolu (Metin-Alani $Veri 'rol' 40 -Zorunlu)
    $mesaj = Metin-Alani $Veri 'mesaj' 4000 -Zorunlu
    if (Sohbet-Isleniyor $rol) { return [ordered]@{ basarili = $false; hata = 'Hâlâ önceki mesajına yanıt yazıyor; biraz bekle.' } }
    if (-not [IO.Directory]::Exists($YolSohbet)) { [void][IO.Directory]::CreateDirectory($YolSohbet) }
    $suren = @([IO.Directory]::GetFiles($YolSohbet, '*.isleniyor') | Where-Object { Sohbet-Isleniyor ([IO.Path]::GetFileNameWithoutExtension($_)) })
    if ($suren.Count -ge 3) { return [ordered]@{ basarili = $false; hata = 'Aynı anda en fazla 3 çalışan yanıt yazabilir; biri bitince yeniden dene.' } }
    $kayit = [ordered]@{ zaman = (Get-Date).ToString('o'); kim = 'sen'; metin = $mesaj } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText((Join-Path $YolSohbet "$rol.jsonl"), $kayit + "`n", $Utf8)
    $isaret = Join-Path $YolSohbet "$rol.isleniyor"
    [IO.File]::WriteAllText($isaret, (([ordered]@{ pid = 0; zaman = (Get-Date).ToString('o') }) | ConvertTo-Json -Compress), $Utf8)
    $betik = Join-Path $OfisKok 'sohbet.ps1'
    $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -Rol {2}' -f $PsExe, $betik, $rol
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg -WindowStyle Hidden -PassThru
    if ([IO.File]::Exists($isaret)) { [IO.File]::WriteAllText($isaret, (([ordered]@{ pid = $p.Id; zaman = (Get-Date).ToString('o') }) | ConvertTo-Json -Compress), $Utf8) }
    Ofis-Kayit "Sohbet: $rol yanıt yazıyor (PID $($p.Id))"
    return [ordered]@{ basarili = $true }
}
function Eylem-SohbetTemizle($Veri) {
    $rol = Sohbet-Rolu (Metin-Alani $Veri 'rol' 40 -Zorunlu)
    if (Sohbet-Isleniyor $rol) { return [ordered]@{ basarili = $false; hata = 'Yanıt yazılırken temizlenemez; biraz bekle.' } }
    $f = Join-Path $YolSohbet "$rol.jsonl"
    if ([IO.File]::Exists($f)) { Move-Item -LiteralPath $f "$f.eski" -Force }
    return [ordered]@{ basarili = $true }
}

# Ofisi kapat: ekibi durum.ps1 ile duraklatır, DURDUR dosyasına "Ofis kapatıldı" yazar (panel bunu "herkes evde" diye gösterir).
# Döngü yalnızca DURDUR dosyasının varlığına bakar; açmak için /api/surdur (durum.ps1 -Surdur) yeterli.
function Eylem-OfisKapat {
    $r = Betik-Calistir 'durum.ps1' '-Duraklat'
    if ($r.basarili) {
        $metin = "Ofis kapatıldı (panelden), {0}. Ekip yeni iş almaz; açmak için panelde 'Ofisi aç' ya da durum.ps1 -Surdur.`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm')
        [IO.File]::WriteAllText((Join-Path $Kok 'DURDUR'), $metin, (New-Object Text.UTF8Encoding($false)))
        Ofis-Kayit 'Ofis kapatıldı (DURDUR yazıldı).'
    }
    return $r
}

# ---------------------------------------------------------------- HTTP
$script:DurumMetinleri = @{ 200 = 'OK'; 204 = 'No Content'; 400 = 'Bad Request'; 401 = 'Unauthorized'; 403 = 'Forbidden'; 404 = 'Not Found'; 405 = 'Method Not Allowed'; 413 = 'Payload Too Large'; 500 = 'Internal Server Error' }
function Yanit-Gonder($Akis, [int]$Kod, [string]$Tur, [byte[]]$Govde, [hashtable]$Ek = @{}) {
    if ($null -eq $Govde) { $Govde = [byte[]]@() }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $Kod $($DurumMetinleri[$Kod])`r`n")
    if ($Tur) { [void]$sb.Append("Content-Type: $Tur`r`n") }
    [void]$sb.Append("Content-Length: $($Govde.Length)`r`n")
    $cerceve = 'DENY'; if ($Ek.ContainsKey('Content-Security-Policy') -and $Ek['Content-Security-Policy'] -match "frame-ancestors 'self'") { $cerceve = 'SAMEORIGIN' }
    [void]$sb.Append("Cache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nX-Frame-Options: $cerceve`r`nConnection: close`r`n")
    foreach ($k in $Ek.Keys) { [void]$sb.Append("${k}: $($Ek[$k])`r`n") }
    [void]$sb.Append("`r`n")
    $bas = [Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $Akis.Write($bas, 0, $bas.Length)
    if ($Govde.Length -gt 0) { $Akis.Write($Govde, 0, $Govde.Length) }
    $Akis.Flush()
}
function Yanit-Json($Akis, [int]$Kod, $Nesne) {
    $j = ConvertTo-Json -InputObject $Nesne -Depth 12 -Compress
    Yanit-Gonder $Akis $Kod 'application/json; charset=utf-8' ($Utf8.GetBytes($j))
}
function Yanit-Metin($Akis, [int]$Kod, [string]$Metin) {
    Yanit-Gonder $Akis $Kod 'text/plain; charset=utf-8' ($Utf8.GetBytes($Metin))
}
function Sorgu-Coz([string]$Sorgu) {
    $h = @{}
    foreach ($parca in $Sorgu.Split('&')) {
        if (-not $parca) { continue }
        $kv = $parca.Split([char[]]@('='), 2)
        $k = [Uri]::UnescapeDataString($kv[0].Replace('+', ' '))
        $v = ''
        if ($kv.Count -gt 1) { $v = [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) }
        $h[$k] = $v
    }
    return $h
}
function Istek-Coz([IO.MemoryStream]$Tampon) {
    $baytlar = $Tampon.ToArray()
    $metin = $Latin1.GetString($baytlar)
    $son = $metin.IndexOf("`r`n`r`n")
    if ($son -lt 0) {
        if ($baytlar.Length -gt 65536) { return 'buyuk' }
        return $null
    }
    $satirlar = $metin.Substring(0, $son).Split([string[]]@("`r`n"), [StringSplitOptions]::None)
    $ilk = $satirlar[0].Split(' ')
    if ($ilk.Count -lt 2) { return 'bozuk' }
    $basliklar = @{}
    for ($i = 1; $i -lt $satirlar.Count; $i++) {
        $j = $satirlar[$i].IndexOf(':')
        if ($j -gt 0) { $basliklar[$satirlar[$i].Substring(0, $j).Trim().ToLowerInvariant()] = $satirlar[$i].Substring($j + 1).Trim() }
    }
    $uzunluk = 0
    if ($basliklar.ContainsKey('content-length')) { [void][int]::TryParse($basliklar['content-length'], [ref]$uzunluk) }
    if ($uzunluk -gt 1MB) { return 'buyuk' }
    $govdeBas = $son + 4
    if ($baytlar.Length - $govdeBas -lt $uzunluk) { return $null }
    $govde = ''
    if ($uzunluk -gt 0) { $govde = $Utf8.GetString($baytlar, $govdeBas, $uzunluk) }
    $hedef = $ilk[1]; $yol = $hedef; $sorgu = ''
    $q = $hedef.IndexOf('?')
    if ($q -ge 0) { $yol = $hedef.Substring(0, $q); $sorgu = $hedef.Substring($q + 1) }
    return [pscustomobject]@{ yontem = $ilk[0].ToUpperInvariant(); yol = $yol; sorgu = (Sorgu-Coz $sorgu); basliklar = $basliklar; govde = $govde }
}
# Telefona uygulama olarak eklenebilsin (PWA): manifest ve simgeler; simgeler ofis\simge-*.png (telefon-kur.ps1 üretir)
function Manifest-Gonder($Akis) {
    $m = [ordered]@{
        name = 'AI Ekip Ofisi'; short_name = 'AI Ofis'; lang = 'tr'; start_url = '/'; scope = '/'; display = 'standalone'
        background_color = '#161a23'; theme_color = '#161a23'
        icons = @([ordered]@{ src = '/simge-192.png'; sizes = '192x192'; type = 'image/png' }, [ordered]@{ src = '/simge-512.png'; sizes = '512x512'; type = 'image/png'; purpose = 'any maskable' })
    }
    Yanit-Gonder $Akis 200 'application/manifest+json; charset=utf-8' ($Utf8.GetBytes((ConvertTo-Json -InputObject $m -Depth 5 -Compress))) @{ 'Cache-Control' = 'no-cache' }
}
function Simge-Gonder($Akis, [string]$Boyut) {
    $f = Join-Path $OfisKok "simge-$Boyut.png"
    if (-not [IO.File]::Exists($f)) { Yanit-Metin $Akis 404 'Simge yok'; return }
    Yanit-Gonder $Akis 200 'image/png' ([IO.File]::ReadAllBytes($f)) @{ 'Cache-Control' = 'max-age=86400' }
}
function Panel-Gonder($Akis) {
    $html = Metin-Oku $PanelDosyasi
    if (-not $html) { Yanit-Metin $Akis 500 'panel.html bulunamadı'; return }
    $nonce = [Guid]::NewGuid().ToString('N')
    $html = $html.Replace('__OFIS_ANAHTARI__', $Anahtar).Replace('__ONIZLEME_ANAHTARI__', $OnizlemeAnahtari).Replace('__NONCE__', $nonce)
    $csp = "default-src 'none'; script-src 'nonce-$nonce'; style-src 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self'; frame-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    Yanit-Gonder $Akis 200 'text/html; charset=utf-8' ($Utf8.GetBytes($html)) @{ 'Content-Security-Policy' = $csp }
}
function Istek-Isle($Akis, $I) {
    try {
        $hostBasligi = ([string]$I.basliklar['host']).ToLowerInvariant()
        if ($IzinliHostlar -notcontains $hostBasligi) { Yanit-Metin $Akis 403 'Yalnızca yerel erişime izin verilir.'; return }
        # Telefondan (Tailscale serve üzerinden) gelen istek: yalnızca uzak.json'daki Tailscale hesaplarına izin ver
        $tsKim = ([string]$I.basliklar['tailscale-user-login']).Trim().ToLowerInvariant()
        if (($UzakHostlar -contains $hostBasligi) -or $tsKim) {
            if (-not $tsKim -or ($UzakKullanicilar.Count -gt 0 -and $UzakKullanicilar -notcontains $tsKim)) { Yanit-Metin $Akis 403 'Bu hesaba izin verilmiyor.'; return }
        }
        $yol = [string]$I.yol
        $yontem = [string]$I.yontem
        if ($yontem -eq 'GET' -and ($yol -eq '/' -or $yol -eq '/index.html')) { Panel-Gonder $Akis; return }
        if ($yontem -eq 'GET' -and $yol -eq '/manifest.webmanifest') { Manifest-Gonder $Akis; return }
        if ($yontem -eq 'GET' -and $yol -match '^/simge-(180|192|512)\.png$') { Simge-Gonder $Akis $Matches[1]; return }
        if ($yontem -eq 'GET' -and $yol.StartsWith('/onizle/')) { Onizleme-Gonder $Akis $yol; return }
        if (-not $yol.StartsWith('/api/')) { Yanit-Metin $Akis 404 'Bulunamadı'; return }

        if ([string]$I.basliklar['x-ofis-anahtar'] -cne $Anahtar) { Yanit-Json $Akis 401 @{ hata = 'Oturum anahtarı geçersiz; sayfayı yenile.' }; return }
        $koken = [string]$I.basliklar['origin']
        if ($koken -and $IzinliKokenler -notcontains $koken.ToLowerInvariant()) { Yanit-Json $Akis 403 @{ hata = 'Bu kaynaktan istek kabul edilmiyor.' }; return }
        $sfs = [string]$I.basliklar['sec-fetch-site']
        if ($sfs -and $sfs -ne 'same-origin' -and $sfs -ne 'none') { Yanit-Json $Akis 403 @{ hata = 'Siteler arası istek kabul edilmiyor.' }; return }

        if ($yontem -eq 'GET') {
            switch ($yol) {
                '/api/durum' { Yanit-Json $Akis 200 (Durum-Uret); return }
                '/api/gorev' { Yanit-Json $Akis 200 (Gorev-Ayrinti ([string]$I.sorgu['id'])); return }
                '/api/dosya' { Yanit-Metin $Akis 200 (Gorev-Dosyasi-Oku ([string]$I.sorgu['id']) ([string]$I.sorgu['yol'])); return }
                '/api/diff' { Yanit-Metin $Akis 200 (Diff-Uret ([string]$I.sorgu['id'])); return }
                '/api/sohbet' { Yanit-Json $Akis 200 (Sohbet-Oku ([string]$I.sorgu['rol'])); return }
            }
            Yanit-Json $Akis 404 @{ hata = 'Bulunamadı' }; return
        }
        if ($yontem -eq 'POST') {
            if (-not ([string]$I.basliklar['content-type']).StartsWith('application/json')) { Yanit-Json $Akis 400 @{ hata = 'JSON bekleniyor' }; return }
            $v = Govde-Coz $I.govde
            $r = $null
            switch ($yol) {
                '/api/gorev-ekle' { $r = Eylem-GorevEkle $v }
                '/api/talep-ekle' { $r = Eylem-TalepEkle $v }
                '/api/uzman-ekle' { $r = Eylem-UzmanEkle $v }
                '/api/duraklat' { $r = Betik-Calistir 'durum.ps1' '-Duraklat' }
                '/api/surdur' { $r = Betik-Calistir 'durum.ps1' '-Surdur' }
                '/api/ofis-kapat' { $r = Eylem-OfisKapat }
                '/api/sohbet' { $r = Eylem-Sohbet $v }
                '/api/sohbet-temizle' { $r = Eylem-SohbetTemizle $v }
                '/api/devam' { $r = Eylem-Devam $v }
                '/api/iptal' { $r = Eylem-Iptal $v }
                '/api/yanit' { $r = Eylem-Yanit $v }
            }
            if ($null -eq $r) { Yanit-Json $Akis 404 @{ hata = 'Bulunamadı' }; return }
            $kod = 200; if (-not $r.basarili) { $kod = 400 }
            Yanit-Json $Akis $kod $r
            return
        }
        Yanit-Json $Akis 405 @{ hata = 'Yöntem desteklenmiyor' }
    } catch {
        $m = $_.Exception.Message
        if ($m -match '^HTTP:(\d{3}):(.*)$') { Yanit-Json $Akis ([int]$Matches[1]) @{ hata = $Matches[2] }; return }
        Ofis-Kayit ("İstek hatası {0} {1}: {2} @ {3}" -f $I.yontem, $I.yol, $m, ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) 'HATA'
        try { Yanit-Json $Akis 500 @{ hata = $m } } catch {}
    }
}

# ---------------------------------------------------------------- başlatma
function Panel-Ac([int]$P) {
    try { Start-Process "http://127.0.0.1:$P/" } catch { Ofis-Kayit "Tarayıcı açılamadı: $($_.Exception.Message)" 'UYARI' }
}

$mutex = New-Object Threading.Mutex($false, 'Local\AIEkipOfis')
$sahip = $false
try { $sahip = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sahip = $true }
if (-not $sahip) {
    # Sunucu zaten çalışıyor: yalnızca paneli aç
    $calisan = Json-Oku $SunucuDosyasi
    $p = $Port
    if ($calisan -and $calisan.port) { $p = [int]$calisan.port }
    if ($Ac) { Panel-Ac $p }
    if ($Konsolda) { Write-Host "Ofis paneli zaten çalışıyor: http://127.0.0.1:$p/" }
    exit 0
}

$dinleyici = $null
$secilenPort = 0
foreach ($aday in ($Port..($Port + 9))) {
    try {
        $d = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $aday)
        $d.ExclusiveAddressUse = $true
        $d.Start()
        $dinleyici = $d; $secilenPort = $aday
        break
    } catch { Ofis-Kayit "Port $aday kullanılamadı: $($_.Exception.Message)" 'UYARI' }
}
if (-not $dinleyici) {
    Ofis-Kayit "Boş port bulunamadı ($Port-$($Port + 9)); çıkılıyor" 'HATA'
    $mutex.ReleaseMutex(); $mutex.Dispose()
    exit 1
}

$rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
$ab = New-Object byte[] 24
$rng.GetBytes($ab)
$script:Anahtar = (($ab | ForEach-Object { $_.ToString('x2') }) -join '')
$ob = New-Object byte[] 20
$rng.GetBytes($ob)
$script:OnizlemeAnahtari = (($ob | ForEach-Object { $_.ToString('x2') }) -join '')
# Uzaktan erişim (telefon): ofis\uzak.json  { "hostlar": ["bilgisayar.tailXXXX.ts.net"], "kullanicilar": ["hesap@ornek.com"] }
# telefon-kur.ps1 yazar. Panel yine yalnızca 127.0.0.1'i dinler; telefondan gelen istekleri Tailscale serve buraya iletir.
$script:UzakHostlar = @(); $script:UzakKullanicilar = @()
$uzak = Json-Oku (Join-Path $OfisKok 'uzak.json')
if ($uzak) {
    $script:UzakHostlar = @(@($uzak.hostlar) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().TrimEnd('.').ToLowerInvariant() })
    $script:UzakKullanicilar = @(@($uzak.kullanicilar) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
}
$script:IzinliHostlar = @("127.0.0.1:$secilenPort", "localhost:$secilenPort") + $UzakHostlar
$script:IzinliKokenler = @("http://127.0.0.1:$secilenPort", "http://localhost:$secilenPort") + @($UzakHostlar | ForEach-Object { "https://$_" })
if ($UzakHostlar.Count -gt 0 -and $BosKapanDk -gt 0) { $BosKapanDk = 0; Ofis-Kayit "Uzaktan erişim açık ($($UzakHostlar -join ', ')); panel boşta kapanmaz" }
[IO.File]::WriteAllText($SunucuDosyasi, (ConvertTo-Json -InputObject ([ordered]@{ pid = $PID; port = $secilenPort; adres = "http://127.0.0.1:$secilenPort/"; baslangic = (Get-Date).ToString('o') })), $Utf8)
Ofis-Kayit "Ofis paneli başladı: http://127.0.0.1:$secilenPort/ (PID $PID, boşta kapanma: $BosKapanDk dk)"
if ($Ac) { Panel-Ac $secilenPort }

$baglantilar = New-Object Collections.Generic.List[object]
$sonIstek = Get-Date
try {
    while ($true) {
        $is = $false
        while ($dinleyici.Pending()) {
            $c = $dinleyici.AcceptTcpClient()
            $c.NoDelay = $true
            $baglantilar.Add([pscustomobject]@{ c = $c; s = $c.GetStream(); tampon = (New-Object IO.MemoryStream); bas = (Get-Date) })
            $is = $true
        }
        for ($i = $baglantilar.Count - 1; $i -ge 0; $i--) {
            $b = $baglantilar[$i]
            $bitti = $false
            try {
                if ($b.c.Available -gt 0) {
                    $buf = New-Object byte[] ([Math]::Min($b.c.Available, 65536))
                    $n = $b.s.Read($buf, 0, $buf.Length)
                    if ($n -gt 0) { $b.tampon.Write($buf, 0, $n) }
                    $is = $true
                    $istek = Istek-Coz $b.tampon
                    if ($istek -is [string]) {
                        if ($istek -eq 'buyuk') { Yanit-Metin $b.s 413 'İstek çok büyük' } else { Yanit-Metin $b.s 400 'Bozuk istek' }
                        $bitti = $true
                    } elseif ($istek) {
                        $sonIstek = Get-Date
                        Istek-Isle $b.s $istek
                        $bitti = $true
                    }
                } elseif ($b.c.Client.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and $b.c.Available -eq 0) {
                    $bitti = $true      # karşı taraf bağlantıyı kapattı
                } elseif (((Get-Date) - $b.bas).TotalSeconds -gt 15) {
                    $bitti = $true      # boş bekleyen bağlantı (ör. tarayıcının ön bağlantısı)
                }
            } catch {
                Ofis-Kayit "Bağlantı hatası: $($_.Exception.Message)" 'UYARI'
                $bitti = $true
            }
            if ($bitti) {
                try { $b.c.Client.Shutdown([Net.Sockets.SocketShutdown]::Send) } catch {}
                try { $b.c.Close() } catch {}
                $baglantilar.RemoveAt($i)
            }
        }
        if (-not $is) {
            if ($BosKapanDk -gt 0 -and $baglantilar.Count -eq 0 -and ((Get-Date) - $sonIstek).TotalMinutes -ge $BosKapanDk) {
                Ofis-Kayit "$BosKapanDk dakikadır istek gelmedi; panel sunucusu kapanıyor"
                break
            }
            Start-Sleep -Milliseconds 25
        }
    }
} catch {
    Ofis-Kayit "Sunucu çöktü: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage -replace '\s+', ' ')" 'HATA'
} finally {
    foreach ($b in $baglantilar) { try { $b.c.Close() } catch {} }
    try { $dinleyici.Stop() } catch {}
    try { if ([IO.File]::Exists($SunucuDosyasi)) { Remove-Item -LiteralPath $SunucuDosyasi -Force } } catch {}
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
    Ofis-Kayit 'Ofis paneli durdu'
}
