<#
ofis.ps1 - AI Ekip "görsel ofis" paneli: yalnızca 127.0.0.1'e bağlanan küçük yerel web sunucusu.

  Masaüstü kısayolu bunu çağırır (pencere görünmez):
    conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Ac
  Elle (konsolda günlükle):
    powershell -NoProfile -ExecutionPolicy Bypass -File ofis\ofis.ps1 -Ac -Konsol

  * Tek kopya çalışır (mutex). İkinci çağrı yalnızca paneli tarayıcıda açar.
  * Okuma: gorevler\*\durum.json, durum\*.json, bildirimler.jsonl, günlük doğrudan okunur.
    Dosyalar FileShare.ReadWrite|Delete ile açılır; döngünün atomik yazmalarını engellemez.
  * Eylemler mevcut betikleri çağırır: gorev-ekle.ps1, durum.ps1 (-Duraklat/-Surdur/-Devam/-Iptal/-Tasi/-Komut).
    Çalışana doğrudan komutta (/api/komut) iş hemen ilerleyecekse paralel hattı (paralel.ps1) bu sunucu başlatır.
    Soru yanıtı görevin gorev.md dosyasına eklenir (BENIOKU'daki akış; döngü değişikliği görüp yeniden planlar).
  * BosKapanDk dakika boyunca hiç istek gelmezse kendini kapatır (kısayol yeniden başlatır).
  * Güvenlik: yalnızca 127.0.0.1; Host başlığı denetimi (DNS rebinding'e karşı); tüm /api isteklerinde
    sunucu her açılışta ürettiği oturum anahtarı + Origin/Sec-Fetch-Site denetimi. Dışarıya hiçbir veri gitmez.
  * Bu dosya ofis\ alt klasöründe durur: kök klasördeki .ps1 değişiklikleri döngüyü yeniden yükletir, bu yüklemez.
#>
param(
    [ValidateRange(1024, 65000)][int]$Port = 8765,
    [switch]$Ac,
    [ValidatePattern('^$|^[a-z0-9][a-z0-9-]{0,30}$')][string]$AcilacakKat = '',   # -Ac ile binayı bu katta aç (kısayollar)
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

# ---------------------------------------------------------------- şirket binası (katlar)
# Tek panel sunucusu bütün katlara hizmet eder. Kat panelleri isteklerine X-Ofis-Kat başlığı (önizlemelerde yol, sayfada /kat/<id>/)
# ekler; istek hangi kata aitse $Kok o katın veri klasörü olur (sunucu tek iş parçacıklıdır). Kod her zaman $KodKok'tadır.
$script:KodKok = $Kok
$script:AktifKatId = 'ana'
$script:AktifKat = $null
$script:KatlarOnbellek = $null; $script:KatlarDamga = -1
function Katlar-Listesi {
    $y = Join-Path $KodKok 'katlar.json'
    $damga = 0; try { $fi = New-Object IO.FileInfo $y; if ($fi.Exists) { $damga = $fi.LastWriteTimeUtc.Ticks } } catch {}
    if ($null -ne $script:KatlarOnbellek -and $damga -eq $script:KatlarDamga) { return , $script:KatlarOnbellek }
    $l = @()
    if ($damga) { $j = Json-Oku $y; if ($j) { $l = @($j.katlar | Where-Object { $_ -and ([string]$_.id) -match '^[a-z0-9][a-z0-9-]{0,30}$' }) } }
    if (-not @($l | Where-Object { [string]$_.id -eq 'ana' }).Count) { $l = @([pscustomobject]@{ id = 'ana'; ad = 'AI Ekip Ofisi'; kisa_ad = 'AI Ekip'; kat_no = 0; tur = 'ekip'; kok = '' }) + $l }
    $script:KatlarOnbellek = $l; $script:KatlarDamga = $damga
    return , $l
}
function Bina-Bilgisi { $j = Json-Oku (Join-Path $KodKok 'katlar.json'); $ad = 'AI Ekip Şirketi'; if ($j -and $j.sirket) { $ad = [string]$j.sirket }; return $ad }
function Kat-Bul-P([string]$Id) { foreach ($k in (Katlar-Listesi)) { if ([string]$k.id -eq $Id) { return $k } }; return $null }
function Kat-Koku-P($K) {
    if (-not $K -or [string]$K.id -eq 'ana' -or -not ([string]$K.kok).Trim()) { return $KodKok }
    $y = ([string]$K.kok).Trim()
    if (-not [IO.Path]::IsPathRooted($y)) { $y = Join-Path $KodKok $y }
    return [IO.Path]::GetFullPath($y)
}
function Kat-Sec([string]$Id) {
    $Id = ([string]$Id).Trim().ToLowerInvariant(); if (-not $Id) { $Id = 'ana' }
    $k = Kat-Bul-P $Id
    if (-not $k) { throw 'HTTP:404:Bilinmeyen kat' }
    $script:AktifKat = $k; $script:AktifKatId = $Id
    $script:Kok = Kat-Koku-P $k
    $script:YolGorev = Join-Path $Kok 'gorevler'; $script:YolDurum = Join-Path $Kok 'durum'; $script:YolGunluk = Join-Path $Kok 'gunluk'
    $script:YolKullanim = Join-Path $YolDurum 'kullanim'
    $script:YolSohbet = Join-Path $YolDurum 'sohbet'
    # Panelin başlattığı betikler (durum.ps1, is-ver.ps1, paralel.ps1...) bu katın verisinde çalışsın (ortak.ps1 AIEKIP_KAT okur)
    if ($Id -eq 'ana') { Remove-Item -LiteralPath env:AIEKIP_KAT -ErrorAction SilentlyContinue } else { $env:AIEKIP_KAT = $Id }
}
function Kat-Ekip-mi($K) { if (-not $K) { $K = $AktifKat }; return ([string]$K.tur -ne 'uygulama') }
# Alt katlar ana katın ayarlarını miras alır (ortak.ps1 > Ayarlari-Yukle ile aynı kural: katta olmayan üst düzey bloklar)
function Kat-Ayar-Oku {
    $a = Json-Oku (Join-Path $Kok 'ayarlar.json')
    if ($a -and $Kok -ne $KodKok) {
        $ana = Json-Oku (Join-Path $KodKok 'ayarlar.json')
        if ($ana) { foreach ($p in $ana.PSObject.Properties) { if (-not $a.PSObject.Properties[$p.Name]) { $a | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value } } }
    }
    return $a
}
function Kok-Dosyasi-P([string]$Goreli) {
    $k = Join-Path $Kok $Goreli
    if ($Kok -ne $KodKok -and -not [IO.File]::Exists($k)) { return (Join-Path $KodKok $Goreli) }
    return $k
}
function Kat-Kapali-P([string]$KatKoku) {
    $d = Join-Path $KatKoku 'DURDUR'
    if (-not [IO.File]::Exists($d)) { return $false }
    return ((Metin-Oku $d 200).TrimStart([char]0xFEFF).StartsWith('Ofis kapatıldı'))
}
function Kat-Dongu-Kilidi-P([string]$Id) { if ($Id -eq 'ana') { return 'Local\AIEkipDongusu' }; return 'Local\AIEkipDongusu_' + ($Id -replace '[^a-z0-9]', '_') }
function Kat-Dongusu-Calisiyor-P([string]$Id) {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting((Kat-Dongu-Kilidi-P $Id), [ref]$m)) { $m.Dispose(); return $true }
    return $false
}
function Gizli-Baslat([string]$Betik, [string]$ArgMetni, [string]$KatId) {
    $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" {2}' -f $PsExe, $Betik, $ArgMetni
    $eski = $env:AIEKIP_KAT
    if ($KatId -and $KatId -ne 'ana') { $env:AIEKIP_KAT = $KatId } else { Remove-Item -LiteralPath env:AIEKIP_KAT -ErrorAction SilentlyContinue }
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg.TrimEnd() -WorkingDirectory (Split-Path -Parent $Betik) -WindowStyle Hidden | Out-Null }
    finally { if ($null -ne $eski) { $env:AIEKIP_KAT = $eski } else { Remove-Item -LiteralPath env:AIEKIP_KAT -ErrorAction SilentlyContinue } }
}
function Kat-Dongusu-Baslat-P([string]$Id) { Gizli-Baslat (Join-Path $KodKok 'baslat.ps1') '' $Id; Ofis-Kayit "Kat döngüsü başlatıldı: $Id" }
# Uygulama katı (kendi sunucusu olan uygulama, ör. Creative Studio): API adresinin portu açık mı (kısa TCP denemesi)
function Uygulama-Calisiyor($K) {
    try {
        $u = [Uri]([string]$K.uygulama.api)
        $c = New-Object Net.Sockets.TcpClient
        try { $t = $c.ConnectAsync($u.Host, $u.Port); return ($t.Wait(400) -and $c.Connected) } finally { $c.Close() }
    } catch { return $false }
}
function Uygulama-Koku($K) {
    $y = ([string]$K.kok).Trim(); if (-not $y) { return '' }
    if (-not [IO.Path]::IsPathRooted($y)) { $y = Join-Path $KodKok $y }
    return [IO.Path]::GetFullPath($y)
}
function Kat-Ozeti($K) {
    $id = [string]$K.id
    $o = [ordered]@{ id = $id; ad = [string]$K.ad; kisa_ad = [string]$K.kisa_ad; kat_no = $K.kat_no; tur = $(if ([string]$K.tur) { [string]$K.tur } else { 'ekip' })
        renk = [string]$K.renk; simge = [string]$K.simge; alan = [string]$K.alan; aciklama = [string]$K.aciklama
        kurulu = $false; acik = $false; durum = 'kapali'; dongu = $false; aktif = 0; bekleyen_soru = 0; takilan = 0; bekleyen_kat = 0; kisi = 0; adres = '' }
    if ($o.tur -eq 'uygulama') {
        $kk = Uygulama-Koku $K
        $o.kurulu = [bool]($kk -and [IO.Directory]::Exists($kk))
        $o.acik = Uygulama-Calisiyor $K
        $o.durum = $(if ($o.acik) { 'acik' } else { 'kapali' })
        $o.adres = [string]$K.uygulama.adres
        $o.kisi = [int]$K.uygulama.kisi
        return $o
    }
    $kk = Kat-Koku-P $K
    $o.kurulu = [IO.File]::Exists((Join-Path $kk 'kadro.json'))
    if (-not $o.kurulu) { $o.durum = 'kurulmadi'; return $o }
    $kapali = Kat-Kapali-P $kk
    $durdur = [IO.File]::Exists((Join-Path $kk 'DURDUR'))
    $o.dongu = Kat-Dongusu-Calisiyor-P $id
    $o.acik = -not $kapali
    $o.durum = $(if ($kapali) { 'kapali' } elseif ($durdur) { 'duraklatildi' } elseif ($o.dongu) { 'acik' } else { 'calismiyor' })
    $kd = Json-Oku (Join-Path $kk 'kadro.json'); $o.kisi = @($kd.uyeler | Where-Object { $_ -and $_.anahtar }).Count
    $yg = Join-Path $kk 'gorevler'
    if ([IO.Directory]::Exists($yg)) {
        foreach ($d in [IO.Directory]::GetDirectories($yg)) {
            $f = Join-Path $d 'durum.json'
            $fi = New-Object IO.FileInfo $f
            if (-not $fi.Exists) { continue }
            $damga = '{0}-{1}' -f $fi.LastWriteTimeUtc.Ticks, $fi.Length
            $c = $KatOzetOnbellek[$f]
            if (-not $c -or $c.damga -ne $damga) { $g = Json-Oku $f; $c = @{ damga = $damga; asama = [string](Ozellik $g 'asama') }; $KatOzetOnbellek[$f] = $c }
            switch ($c.asama) {
                'bekliyor_kullanici' { $o.bekleyen_soru++ }
                'takildi' { $o.takilan++ }
                'kat_bekliyor' { $o.bekleyen_kat++ }
                default { if ($AktifAsamalar -contains $c.asama -or @('fikir', 'elestiri', 'poc_plan', 'maliyet', 'karar', 'teslim', 'puanlama') -contains $c.asama) { $o.aktif++ } }
            }
        }
    }
    return $o
}
$script:KatOzetOnbellek = @{}
function Yazisma-Listesi([string]$Kat = '', [int]$Adet = 30) {
    $kl = Join-Path (Join-Path $KodKok 'sirket') 'yazismalar'
    $l = New-Object Collections.Generic.List[object]
    if (-not [IO.Directory]::Exists($kl)) { return , $l }
    foreach ($f in @([IO.Directory]::GetFiles($kl, '*.json') | Sort-Object -Descending)) {
        if ($l.Count -ge $Adet) { break }
        $y = Json-Oku $f
        if (-not $y -or -not $y.id) { continue }
        if ($Kat -and [string]$y.kaynak_kat -ne $Kat -and [string]$y.hedef_kat -ne $Kat) { continue }
        $son = @($y.gecmis | Where-Object { $_ }) | Select-Object -Last 1
        $l.Add([ordered]@{ id = [string]$y.id; tur = [string]$y.tur; durum = [string]$y.durum; baslik = [string]$y.baslik
            kaynak_kat = [string]$y.kaynak_kat; kaynak_ofis = [string]$y.kaynak_ofis; kaynak_gorev = [string]$y.kaynak_gorev
            hedef_kat = [string]$y.hedef_kat; hedef_ofis = [string]$y.hedef_ofis; hedef_gorev = [string]$y.hedef_gorev; hedef_asama = [string]$y.hedef_asama
            gonderen = [string]$y.gonderen; alan = [string]$y.alan; olusturma = $y.olusturma; guncelleme = $y.guncelleme
            son_olay = $(if ($son) { [string]$son.olay } else { '' }); ozet = $(if ($y.sonuc) { [string]$y.sonuc.ozet } else { '' }) })
    }
    return , $l
}
function Yazisma-Ayrinti([string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{5,90}$') { throw 'HTTP:400:Geçersiz yazışma' }
    $kl = Join-Path (Join-Path $KodKok 'sirket') 'yazismalar'
    $y = Json-Oku (Join-Path $kl "$Id.json")
    if (-not $y) { throw 'HTTP:404:Yazışma bulunamadı' }
    return $y
}
function Katlar-Bilgisi {
    $l = New-Object Collections.Generic.List[object]
    foreach ($k in (Katlar-Listesi)) { $l.Add((Kat-Ozeti $k)) }
    return [ordered]@{ sirket = (Bina-Bilgisi); zaman = (Get-Date).ToString('o'); uzak = [bool]$script:IstekUzak; katlar = $l; yazismalar = (Yazisma-Listesi '' 20) }
}
# Katı aç: ekip katında DURDUR kaldırılır, döngü çalışmıyorsa başlatılır; uygulama katında kendi başlatıcısı (gizli) çalışır
function Eylem-KatAc($Veri) {
    $id = [string](Ozellik $Veri 'kat'); if (-not $id) { $id = $AktifKatId }
    $k = Kat-Bul-P $id; if (-not $k) { throw 'HTTP:404:Bilinmeyen kat' }
    if (-not (Kat-Ekip-mi $k)) {
        $kk = Uygulama-Koku $k; $b = [string]$k.uygulama.baslat
        if (-not $kk -or -not $b -or -not [IO.File]::Exists((Join-Path $kk $b))) { throw 'HTTP:400:Bu katın başlatıcısı yok' }
        if (Uygulama-Calisiyor $k) { return [ordered]@{ basarili = $true; cikti = "$($k.ad) zaten açık."; hata = '' } }
        Gizli-Baslat (Join-Path $kk $b) ([string]$k.uygulama.baslat_arg) ''
        Ofis-Kayit "Uygulama katı açılıyor: $id"
        return [ordered]@{ basarili = $true; cikti = "$($k.ad) açılıyor (sunucuların hazır olması birkaç saniye sürer)."; hata = '' }
    }
    $kk = Kat-Koku-P $k
    if (-not [IO.File]::Exists((Join-Path $kk 'kadro.json'))) { throw 'HTTP:400:Bu kat kurulmamış' }
    $durdur = Join-Path $kk 'DURDUR'
    if ([IO.File]::Exists($durdur)) { Remove-Item -LiteralPath $durdur -Force }
    if (-not (Kat-Dongusu-Calisiyor-P $id)) { Kat-Dongusu-Baslat-P $id }
    Ofis-Kayit "Kat açıldı: $id"
    return [ordered]@{ basarili = $true; cikti = "$($k.ad) açıldı; ekip geliyor."; hata = '' }
}
function Eylem-KatKapat($Veri) {
    $id = [string](Ozellik $Veri 'kat'); if (-not $id) { $id = $AktifKatId }
    $k = Kat-Bul-P $id; if (-not $k) { throw 'HTTP:404:Bilinmeyen kat' }
    if (-not (Kat-Ekip-mi $k)) {
        $kk = Uygulama-Koku $k; $b = [string]$k.uygulama.durdur
        if (-not $kk -or -not $b -or -not [IO.File]::Exists((Join-Path $kk $b))) { throw 'HTTP:400:Bu katın durdurucusu yok' }
        Gizli-Baslat (Join-Path $kk $b) ([string]$k.uygulama.durdur_arg) ''
        Ofis-Kayit "Uygulama katı kapatılıyor: $id"
        return [ordered]@{ basarili = $true; cikti = "$($k.ad) kapatılıyor."; hata = '' }
    }
    if ($id -eq 'ana') { $eski = $AktifKatId; Kat-Sec 'ana'; try { return (Eylem-OfisKapat) } finally { Kat-Sec $eski } }
    $kk = Kat-Koku-P $k
    $metin = "Ofis kapatıldı (panelden), {0}. Kat yeni iş almaz; açmak için panelde katı aç.`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm')
    [IO.File]::WriteAllText((Join-Path $kk 'DURDUR'), $metin, (New-Object Text.UTF8Encoding($false)))
    Ofis-Kayit "Kat kapatıldı: $id"
    return [ordered]@{ basarili = $true; cikti = "$($k.ad) kapanıyor: çalışan adımını bitiren çıkar."; hata = '' }
}
$script:SonBinaBekcisi = Get-Date
# Panel açıkken açık katların döngüsü düşerse yeniden başlatır (ana katın zamanlanmış görevi de 10 dakikada bir bakar)
function Bina-Bekcisi-P {
    if (((Get-Date) - $script:SonBinaBekcisi).TotalSeconds -lt 120) { return }
    $script:SonBinaBekcisi = Get-Date
    foreach ($k in (Katlar-Listesi)) {
        $id = [string]$k.id
        if ($id -eq 'ana' -or -not (Kat-Ekip-mi $k)) { continue }
        $kk = Kat-Koku-P $k
        if (-not [IO.File]::Exists((Join-Path $kk 'ayarlar.json')) -or (Kat-Kapali-P $kk)) { continue }
        if (-not (Kat-Dongusu-Calisiyor-P $id)) { try { Kat-Dongusu-Baslat-P $id } catch { Ofis-Kayit "Bina bekçisi: $id başlatılamadı: $($_.Exception.Message)" 'UYARI' } }
    }
}
# ---------------------------------------------------------------- fikir hattı (Creativity Office katı; tip = yaratici, yaratici.ps1)
$script:YaraticiAsamaRol = @{ yeni = 'fikirci'; fikir = 'fikirci'; elestiri = 'elestirmen'; poc_plan = 'planlamaci'; maliyet = 'maliyet'; karar = 'karar-verici'; teslim = 'karar-verici'; bekleme = 'karar-verici'; puanlama = 'puanlayici' }
$script:YaraticiAsamaAdlari = @{
    yeni = 'Sırada'; fikir = 'Fikir üretiliyor'; elestiri = 'Eleştiriliyor'; poc_plan = 'POC planlanıyor'; maliyet = 'Maliyet hesaplanıyor'
    karar = 'Karar bekliyor'; teslim = 'Teslim hazırlanıyor'; bekleme = 'Ana ofiste uygulanıyor'; puanlama = 'Puanlanıyor'; tamam = 'Puanlandı'; reddedildi = 'Reddedildi'
}
$script:YaraticiMetni = @{
    yeni = 'Konuyu fikir hattına alıyor'; fikir = 'Fikir üretiyor'; elestiri = 'Fikirleri eleştiriyor'; poc_plan = 'POC planı yazıyor'; maliyet = 'Maliyet hesaplıyor'
    karar = 'Karar veriyor'; teslim = 'Teslim paketi hazırlıyor'; bekleme = 'Ana ofisi izliyor'; puanlama = 'Çıktıyı puanlıyor'
}
$script:YaraticiFaaliyet = @{ yeni = 'fikir'; fikir = 'fikir'; elestiri = 'elestiri'; poc_plan = 'poc_plan'; maliyet = 'maliyet'; karar = 'karar'; teslim = 'teslim'; bekleme = 'bekleme'; puanlama = 'puanlama' }
function Yaratici-Katinda-mi($Kadro) { return [bool](Kadro-Bul $Kadro 'fikirci') }
function Yaratici-Ayar-Oku($A) {
    $s = [ordered]@{ revizyon_siniri = 3; ana_ofis_yolu = ''; varsayilan_proje = '' }
    if ($A) {
        foreach ($ad in @('revizyon_siniri', 'ana_ofis_yolu', 'varsayilan_proje')) { $v = Ozellik $A $ad; if ($null -ne $v) { $s[$ad] = $v } }
        $y = Ozellik $A 'yaratici'
        if ($y) { foreach ($ad in @('revizyon_siniri', 'ana_ofis_yolu', 'varsayilan_proje')) { $v = Ozellik $y $ad; if ($null -ne $v) { $s[$ad] = $v } } }
    }
    $s.revizyon_siniri = [Math]::Max(0, [Math]::Min(3, [int]$s.revizyon_siniri))
    $s.ana_ofis_yolu = ([string]$s.ana_ofis_yolu).Trim()
    if (-not $s.ana_ofis_yolu -and $AktifKatId -ne 'ana') { $s.ana_ofis_yolu = $KodKok }
    return [pscustomobject]$s
}
function Ana-Kok($A, $G) {
    $yol = ''
    if ($G -and (Ozellik $G 'ana_ofis')) { $yol = [string](Ozellik $G 'ana_ofis') }
    else { $yol = (Yaratici-Ayar-Oku $A).ana_ofis_yolu }
    if (-not $yol) { return '' }
    if (-not [IO.Path]::IsPathRooted($yol)) { $yol = Join-Path $Kok $yol }
    return $yol
}
$script:AnaAsamaOnbellek = @{}
function Yaratici-Ana-Asama($G) {
    $a = [string](Ozellik $G 'ana_asama')
    $id = [string](Ozellik $G 'ana_gorev_id')
    if (-not $id -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$' -or @('bekleme', 'puanlama') -notcontains [string]$G.asama) { return $a }
    $kok = Ana-Kok $null $G
    if (-not $kok) { return $a }
    $f = Join-Path (Join-Path (Join-Path $kok 'gorevler') $id) 'durum.json'
    try {
        $fi = New-Object IO.FileInfo $f
        if (-not $fi.Exists) { return $a }
        $o = $AnaAsamaOnbellek[$f]
        if ($o -and $o.damga -eq $fi.LastWriteTimeUtc.Ticks) { return $o.asama }
        $j = Json-Oku $f
        if ($j -and $j.asama) { $AnaAsamaOnbellek[$f] = @{ damga = $fi.LastWriteTimeUtc.Ticks; asama = [string]$j.asama }; return [string]$j.asama }
    } catch {}
    return $a
}
function Ana-Ofis($A) {
    $s = [ordered]@{ yapilandirildi = $false; bagli = $false; canli = $false; kapali = $false; durum = ''; panel = '' }
    $kok = Ana-Kok $A $null
    if (-not $kok) { return $s }
    $s.yapilandirildi = $true
    if (-not [IO.File]::Exists((Join-Path $kok 'gorev-ekle.ps1'))) { return $s }
    $s.bagli = $true
    $k = Json-Oku (Join-Path $kok 'durum\kalp.json')
    if ($k) { try { $s.canli = (((Get-Date) - [datetime]$k.zaman).TotalMinutes -lt 15) -and [string]$k.durum -ne 'durdu'; $s.durum = [string]$k.durum } catch {} }
    $s.kapali = [IO.File]::Exists((Join-Path $kok 'DURDUR'))
    $s.panel = '/#kat=ana'
    return $s
}
function Ofis-Durumu($A, [bool]$Durdur) {
    $kapali = Kat-Kapali-P $Kok
    return [ordered]@{ acik = (-not $kapali -and -not $Durdur); niyet = (-not $kapali); mesai = $true; calisma_saatleri = [string]$A.dongu.calisma_saatleri }
}
function Eylem-KonuEkle($Veri) {
    $konu = Metin-Alani $Veri 'konu' 500 -Zorunlu
    $alan = Metin-Alani $Veri 'alan' 60
    $proje = Metin-Alani $Veri 'proje' 400
    $oncelik = [int](Ozellik $Veri 'oncelik')
    if ($oncelik -lt 1 -or $oncelik -gt 3) { $oncelik = 2 }
    $a = @('-Konu', (Ps-Tirnak $konu))
    if ($alan) { $a += '-Alan'; $a += (Ps-Tirnak $alan) }
    if ($proje) { $a += '-Proje'; $a += (Ps-Tirnak $proje) }
    $a += '-Oncelik'; $a += [string]$oncelik
    $r = Betik-Calistir 'proje-ekle.ps1' ($a -join ' ')
    $m = [regex]::Match([string]$r.cikti, 'Konu eklendi: (\S+)')
    if ($m.Success) { $r['id'] = $m.Groups[1].Value; $r['cikti'] = "Konu fikir hattına eklendi: #$(($m.Groups[1].Value -split '-')[0])" }
    if ($r.basarili -and [bool](Ozellik $Veri 'ofisi_ac') -and (Kat-Kapali-P $Kok)) { [void](Eylem-KatAc ([pscustomobject]@{ kat = $AktifKatId })) }
    return $r
}
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

$script:AktifAsamalar = @('yeni', 'analiz', 'kesif', 'plan', 'gelistirme', 'kontrol', 'test', 'denetim', 'kabul', 'tamamla', 'yardim', 'canliya_al')
$script:AsamaAdlari = @{
    yeni = 'Sırada'; analiz = 'Gereksinimler netleşiyor'; kesif = 'Kod tabanı taranıyor'; plan = 'Planlanıyor'; gelistirme = 'Geliştiriliyor'
    kontrol = 'Kontrol ediliyor'; test = 'Test ediliyor'; denetim = 'Denetleniyor'; kabul = 'Engineering Manager onayında'; tamamla = 'Commit ediliyor'; tamam = 'Tamamlandı'
    takildi = 'Takıldı'; bekliyor_kullanici = 'Senden yanıt bekliyor'; iptal = 'İptal'
    yardim = 'Engineering Managerʼda (yardım isteği)'; yardim_bekliyor = 'Ekipten yardım bekliyor'
    kat_bekliyor = 'Başka katta yapılıyor (Comms)'; reddedildi = 'Reddedildi'; canliya_al = 'Canlıya alınıyor'
}
# "İş ver" ile gelen, Engineering Managerʼın henüz yönlendirmediği işler (tip = genel; bkz. yonlendirme.ps1)
$script:GenelAsamaAdlari = @{ yeni = 'Engineering Managerʼda'; plan = 'Engineering Managerʼda' }
# kadro.json yoksa ya da bozuksa kullanılacak en küçük kadro (rol anahtarı "lider" = Engineering Manager)
$script:VarsayilanKadro = @(
    [pscustomobject]@{ anahtar = 'lider'; ad = 'Engineering Manager'; departman = 'Teknik koordinasyon'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'gelistirici'; ad = 'Full-Stack Developer'; departman = 'Yazılım'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'denetci'; ad = 'Code Reviewer'; departman = 'Yazılım'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'sistem'; ad = 'System Administrator'; departman = 'Altyapı ve güvenlik'; yerlesik = $true }
    [pscustomobject]@{ anahtar = 'ag'; ad = 'Network Engineer'; departman = 'Altyapı ve güvenlik'; yerlesik = $true }
)
function Kadro-Listesi {
    $k = Json-Oku (Join-Path $Kok 'kadro.json')
    $l = @()
    if ($k) { $l = @($k.uyeler | Where-Object { $_ -and $_.anahtar }) }
    if ($l.Count -eq 0) { $l = $VarsayilanKadro }
    return , $l
}
function Kadro-Bul($Liste, [string]$Anahtar) { foreach ($u in $Liste) { if ([string]$u.anahtar -eq $Anahtar) { return $u } }; return $null }
# Yazılım akışı (planlama.ps1): analiz = Product Manager, kesif = Codebase Explorer, test = QA Engineer
$script:AsamaRol = @{ canliya_al = 'lider'; yeni = 'lider'; analiz = 'urun'; kesif = 'kasif'; plan = 'lider'; gelistirme = 'gelistirici'; kontrol = 'denetci'; test = 'tester'; denetim = 'denetci'; kabul = 'lider'; tamamla = 'lider' }
$script:AsamaFaaliyet = @{ canliya_al = 'kabul'; yeni = 'plan'; analiz = 'analiz'; kesif = 'kesif'; plan = 'plan'; gelistirme = 'gelistirme'; kontrol = 'kontrol'; test = 'test'; denetim = 'denetim'; kabul = 'kabul'; tamamla = 'kabul' }
$script:AsamaMetni = @{
    yeni = 'Çalışma dalını hazırlıyor'; analiz = 'Talebi netleştiriyor, kabul ölçütlerini yazıyor'; kesif = 'Kod tabanını tarıyor'
    plan = 'Plan yazıyor, işi dağıtıyor'; gelistirme = 'Kodu yazıyor'
    kontrol = 'Testleri ve taramaları çalıştırıyor'; test = 'Birim / entegrasyon testi yazıp koşturuyor'; denetim = 'Kodu inceliyor'
    kabul = 'Son kararı veriyor'; tamamla = 'Onayları denetleyip commit ediyor'; canliya_al = 'Değişikliği ofise uygulayıp doğruluyor'
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
$script:EtiketAsama = @{ uygulama = 'gelistirme'; dogrulama = 'denetim'; calisma = 'gelistirme'; inceleme = 'denetim'; ise_alim = 'plan'; danisman = 'gelistirme'
    fikirci = 'fikir'; elestirmen = 'elestiri'; planlamaci = 'poc_plan'; maliyet = 'maliyet'; 'karar-verici' = 'karar'; teslim = 'teslim'; puanlayici = 'puanlama' }
# Outsource Consultant işleri (tip = danisman; danisman.ps1): her aşama danışmanda
$script:DanismanAsamaAdlari = @{ yeni = 'Danışmana veriliyor'; gelistirme = 'Danışmanda'; kontrol = 'Kontrol ediliyor'; tamamla = 'Kapatılıyor' }
$script:DanismanMetni = @{ yeni = 'Çalışma klasörünü hazırlıyor'; gelistirme = 'Terminalde işi baştan sona yapıyor'; kontrol = 'Sonucu otomatik kontrolden geçiriyor'; tamamla = 'Sonucu teslim ediyor' }
function Gorev-Tipi($G) {
    $t = [string](Ozellik $G 'tip')
    if ($t -eq 'altyapi' -or $t -eq 'uzman' -or $t -eq 'genel' -or $t -eq 'danisman' -or $t -eq 'yaratici') { return $t }
    return 'yazilim'
}
function Altyapi-Mi($G) { return ((Gorev-Tipi $G) -eq 'altyapi') }
# Kullanıcının "Devral" komutu: bu işte o rolün işini başka bir çalışan yapar (görevde devralan = { rol: çalışan }; komut.ps1)
function Gorev-Rolu($G, [string]$Etiket = '') {
    $r = Gorev-Rolu-Ham $G $Etiket
    if (-not $r -or $Etiket -eq 'ise_alim' -or $Etiket -match '^(inceleme|birlikte)-') { return $r }
    $d = Ozellik $G 'devralan'
    if ($d) { $k = [string](Ozellik $d $r); if ($k) { return $k } }
    return $r
}
# Kalp atışındaki "etiket (araç/model)" -> o anki ajan adımının etiketi ve aracı (adım görevin aşamasına uymuyorsa boş)
function Kalp-Etiketi([string]$Adim, $G) {
    $e = ''; $arac = ''
    if ($G -and $Adim -match '^(\S+) \((.+)\)$') {
        $e = $Matches[1]; $kimlik = $Matches[2]
        $x = $e
        if ($x -match '^inceleme-') { $x = 'denetim' }
        if ($x -match '^birlikte-') { $x = 'yardim' }   # yardımcı, yardım isteyen işin içinde hemen çalışıyor
        if ($x -match '^kat-') { $x = [string]$G.asama }   # Comms başka kata yazışıyor (iletisim.ps1)
        if ($x -eq 'yonlendirme') { $x = [string]$G.asama }   # Engineering Managerʼın "İş ver" yönlendirmesi (yeni ya da plan)
        if ($EtiketAsama.ContainsKey($x)) { $x = $EtiketAsama[$x] }
        if ($x -eq [string]$G.asama) { $arac = $kimlik } else { $e = '' }
    }
    return @{ etiket = $e; arac = $arac }
}
# Panelden komutla açılan paralel hatlar (paralel.ps1 > durum\paralel\<no>.json); süreci ölmüş kayıtlar atlanır
function Paralel-Hatlari-Oku($Gorevler, $BostaDurumlari) {
    $l = New-Object Collections.Generic.List[object]
    $kl = Join-Path $YolDurum 'paralel'
    if (-not [IO.Directory]::Exists($kl)) { return , $l }
    foreach ($f in [IO.Directory]::GetFiles($kl, '*.json')) {
        $h = Json-Oku $f
        if (-not $h) { continue }
        $pidNo = [int](Ozellik $h 'pid')
        $canli = $false
        if ($pidNo -gt 0) { $canli = [bool](Get-Process -Id $pidNo -ErrorAction SilentlyContinue) }
        $z = Tarih (Ozellik $h 'zaman')
        if (-not $canli -and -not ($z -and ((Get-Date) - $z).TotalSeconds -lt 20)) { continue }
        $g = $null; $hid = [string](Ozellik $h 'gorev')
        foreach ($x in $Gorevler) { if ([string]$x.id -eq $hid) { $g = $x; break } }
        if (-not $g) { continue }
        $durum = [string](Ozellik $h 'durum')
        $hCalisiyor = ($AktifAsamalar -contains [string]$g.asama) -and ($BostaDurumlari -notcontains $durum)
        $ke = @{ etiket = ''; arac = '' }; if ($hCalisiyor) { $ke = Kalp-Etiketi ([string](Ozellik $h 'adim')) $g }
        $l.Add([ordered]@{ gorev = $hid; kim = [string](Ozellik $h 'kim'); emir = [string](Ozellik $h 'emir'); baslangic = (Ozellik $h 'baslangic')
            zaman = (Ozellik $h 'zaman'); durum = $durum; adim_sayisi = [int](Ozellik $h 'adim_sayisi'); pid = $pidNo
            g = $g; etiket = $ke.etiket; arac = $ke.arac; calisiyor = [bool]$hCalisiyor; paralel = $true })
    }
    return , $l
}
function Gorev-Rolu-Ham($G, [string]$Etiket = '') {
    # Görevin şu anki aşamasını hangi rol yürütüyor (kalp atışındaki etiket önceliklidir: işe alım, ek inceleme)
    if ($Etiket -eq 'ise_alim') { return 'ik' }
    if ($Etiket -match '^inceleme-(.+)$') { return $Matches[1] }
    if ($Etiket -match '^birlikte-(.+)$') { return $Matches[1] }
    if ($Etiket -match '^kat-') { return 'iletisim' }   # katlar arası yazışma (Comms)
    $asama = [string]$G.asama
    $tip = Gorev-Tipi $G
    if ($asama -eq 'kat_bekliyor') { return 'iletisim' }
    if ($tip -eq 'yaratici') { if ($YaraticiAsamaRol.ContainsKey($asama)) { return $YaraticiAsamaRol[$asama] }; return 'lider' }
    if ($asama -eq 'analiz') { return 'urun' }   # Product Manager ("İş ver" ve yazılım işleri)
    if ($tip -eq 'danisman') { return 'danisman' }   # Outsource Consultant
    if ($tip -eq 'genel' -or $asama -eq 'yardim') { return 'lider' }
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
    if ($asama -eq 'gelistirme') {
        # Bölünmüş geliştirmede sıradaki parçanın geliştiricisi (Backend / Frontend Developer…)
        foreach ($p in @(Ozellik $G 'gelistirme_isleri')) { if ($p -and [string](Ozellik $p 'rol') -and [string](Ozellik $p 'durum') -ne 'tamam') { return [string]$p.rol } }
    }
    if ($asama -eq 'kontrol' -and (Ozellik $G 'qa_testi') -eq $true) { return 'tester' }
    return $AsamaRol[$asama]
}
function Asama-Adi-Bul($G) {
    $asama = [string]$G.asama
    $tip = Gorev-Tipi $G
    if ($tip -eq 'altyapi' -and $AltyapiAsamaAdlari.ContainsKey($asama)) { return $AltyapiAsamaAdlari[$asama] }
    if ($tip -eq 'uzman' -and $UzmanAsamaAdlari.ContainsKey($asama)) { return $UzmanAsamaAdlari[$asama] }
    if ($tip -eq 'danisman' -and $DanismanAsamaAdlari.ContainsKey($asama)) { return $DanismanAsamaAdlari[$asama] }
    if ($tip -eq 'yaratici' -and $YaraticiAsamaAdlari.ContainsKey($asama)) {
        if ($asama -eq 'bekleme' -and [string](Ozellik $G 'teslim_turu') -eq 'yerel') { return 'Uygulama çıktısı bekleniyor (yerel teslim)' }
        if ($asama -eq 'bekleme' -and (Ozellik $G 'ana_takildi')) { return 'Ana ofiste takıldı (bekleniyor)' }
        return $YaraticiAsamaAdlari[$asama]
    }
    if ($tip -eq 'genel' -and $GenelAsamaAdlari.ContainsKey($asama)) { return $GenelAsamaAdlari[$asama] }
    if ($AsamaAdlari.ContainsKey($asama)) { return $AsamaAdlari[$asama] }
    return $asama
}

# ---------------------------------------------------------------- token / bağlam kullanımı
# Döngü (ortak.ps1 > Kullanim-Kaydet) her ajan çağrısını durum\kullanim\kullanim-yyyyMM.jsonl'a ekler. Panel dosyaları
# artımlı okur (yalnızca yeni eklenen satırlar çözülür) ve özetler: rol, araç, gün/saat, görev.
$script:YolKullanim = Join-Path $YolDurum 'kullanim'
$script:KullanimOnbellek = @{}
Add-Type -AssemblyName System.Web.Extensions
$script:JsCozucu = New-Object Web.Script.Serialization.JavaScriptSerializer
$script:JsCozucu.MaxJsonLength = 16MB
function Kullanim-Dosyasi-Oku([string]$Yol) {
    $fi = New-Object IO.FileInfo $Yol
    if (-not $fi.Exists) { return , (New-Object Collections.Generic.List[object]) }
    $o = $KullanimOnbellek[$Yol]
    if (-not $o -or $fi.Length -lt $o.uzunluk) { $o = @{ uzunluk = [long]0; kayitlar = (New-Object Collections.Generic.List[object]) }; $KullanimOnbellek[$Yol] = $o }
    if ($fi.Length -gt $o.uzunluk) {
        $fs = Paylasimli-Ac $Yol
        try {
            [void]$fs.Seek($o.uzunluk, [IO.SeekOrigin]::Begin)
            $b = New-Object byte[] ([int]($fs.Length - $o.uzunluk))
            $n = $fs.Read($b, 0, $b.Length)
        } finally { $fs.Dispose() }
        $metin = $Utf8.GetString($b, 0, $n)
        $son = $metin.LastIndexOf("`n")
        if ($son -ge 0) {
            $tam = $metin.Substring(0, $son + 1)
            foreach ($s in $tam.Split("`n")) {
                $t = $s.Trim(); if (-not $t) { continue }
                try {
                    $r = $JsCozucu.DeserializeObject($t)
                    $r['_z'] = [datetime]$r['zaman']
                    $o.kayitlar.Add($r)
                } catch {}
            }
            $o.uzunluk += $Utf8.GetByteCount($tam)
        }
    }
    return , $o.kayitlar
}
function Kullanim-Kayitlari([datetime]$Bas) {
    $l = New-Object Collections.Generic.List[object]
    $simdi = Get-Date
    $ay = New-Object DateTime ($Bas.Year, $Bas.Month, 1)
    while ($ay -le $simdi) {
        $kayitlar = Kullanim-Dosyasi-Oku (Join-Path $YolKullanim ('kullanim-{0}.jsonl' -f $ay.ToString('yyyyMM')))
        # Kayıtlar kabaca zaman sırasında: sondan başa tara, başlangıçtan bir gün öncesine inince dur
        $sinir = $Bas.AddDays(-1)
        for ($i = $kayitlar.Count - 1; $i -ge 0; $i--) {
            $r = $kayitlar[$i]
            if ($r['_z'] -ge $Bas) { $l.Add($r) } elseif ($r['_z'] -lt $sinir) { break }
        }
        $ay = $ay.AddMonths(1)
    }
    $l.Reverse()
    return , $l
}
function Sayi-Al($R, [string]$Ad) { $v = $R[$Ad]; if ($null -eq $v) { return [long]0 }; try { return [long]$v } catch { return [long]0 } }
function Kullanim-Bugun-Rol {
    $h = @{}
    foreach ($r in (Kullanim-Kayitlari (Get-Date).Date)) {
        $rol = [string]$r['rol']
        if (-not $h.ContainsKey($rol)) { $h[$rol] = @{ cagri = 0; toplam = [long]0 } }
        $h[$rol].cagri++; $h[$rol].toplam += (Sayi-Al $r 'toplam')
    }
    return $h
}
function Kullanim-Ozeti([int]$Gun) {
    if (@(1, 7, 30) -notcontains $Gun) { $Gun = 7 }
    $simdi = Get-Date
    $bas = $simdi.Date.AddDays(1 - $Gun)
    $kayitlar = Kullanim-Kayitlari $bas
    $kadro = Kadro-Listesi
    $ozet = [ordered]@{ cagri = 0; basarisiz = 0; toplam = [long]0; giris = [long]0; onbellek_okuma = [long]0; onbellek_yazma = [long]0; cikis = [long]0
        sure_sn = [long]0; maliyet_usd = [double]0; tepe_yuzde = [double]0; tepe_rol = ''; olcumsuz = 0; gecmis = 0 }
    $araclar = @{}
    $roller = @{}
    $seri = [ordered]@{}
    if ($Gun -eq 1) { for ($h = 0; $h -lt 24; $h++) { $seri['{0:D2}' -f $h] = @{ claude = [long]0; codex = [long]0; diger = [long]0; cagri = 0 } } }
    else { for ($d = 0; $d -lt $Gun; $d++) { $seri[$bas.AddDays($d).ToString('yyyy-MM-dd')] = @{ claude = [long]0; codex = [long]0; diger = [long]0; cagri = 0 } } }
    $gorevler = @{}
    foreach ($r in $kayitlar) {
        $arac = [string]$r['arac']; $ak = 'diger'; if ($arac -eq 'claude' -or $arac -eq 'codex') { $ak = $arac }
        $tok = Sayi-Al $r 'toplam'
        $ok = [bool]$r['basarili']
        $sure = Sayi-Al $r 'sure_sn'
        $tepe = Sayi-Al $r 'baglam_tepe'; $pencere = Sayi-Al $r 'baglam_pencere'
        $yuzde = -1.0; if ($tepe -gt 0 -and $pencere -gt 0) { $yuzde = [Math]::Round(100.0 * $tepe / $pencere, 1) }
        $ozet.cagri++; if (-not $ok) { $ozet.basarisiz++ }
        $ozet.toplam += $tok; $ozet.giris += (Sayi-Al $r 'giris'); $ozet.onbellek_okuma += (Sayi-Al $r 'onbellek_okuma')
        $ozet.onbellek_yazma += (Sayi-Al $r 'onbellek_yazma'); $ozet.cikis += (Sayi-Al $r 'cikis'); $ozet.sure_sn += $sure
        if ($r['maliyet_usd']) { $ozet.maliyet_usd += [double]$r['maliyet_usd'] }
        if ($tok -le 0) { $ozet.olcumsuz++ }
        if ([string]$r['kaynak'] -eq 'gecmis') { $ozet.gecmis++ }
        if (-not $araclar.ContainsKey($ak)) { $araclar[$ak] = @{ cagri = 0; toplam = [long]0 } }
        $araclar[$ak].cagri++; $araclar[$ak].toplam += $tok
        $rol = [string]$r['rol']; if (-not $rol) { $rol = '?' }
        if (-not $roller.ContainsKey($rol)) {
            $roller[$rol] = @{ cagri = 0; basarisiz = 0; sohbet = 0; sure_sn = [long]0; giris = [long]0; onbellek_okuma = [long]0; onbellek_yazma = [long]0; cikis = [long]0
                toplam = [long]0; claude = [long]0; codex = [long]0; diger = [long]0; tepe_yuzde = [double]-1; yuzde_top = [double]0; yuzde_adet = 0; tepe_token = [long]0
                son = $null; modeller = @{} }
        }
        $o = $roller[$rol]
        $o.cagri++; if (-not $ok) { $o.basarisiz++ }; if ([string]$r['etiket'] -like 'sohbet*') { $o.sohbet++ }
        $o.sure_sn += $sure; $o.giris += (Sayi-Al $r 'giris'); $o.onbellek_okuma += (Sayi-Al $r 'onbellek_okuma'); $o.onbellek_yazma += (Sayi-Al $r 'onbellek_yazma')
        $o.cikis += (Sayi-Al $r 'cikis'); $o.toplam += $tok; $o[$ak] += $tok
        if ($yuzde -ge 0) { $o.yuzde_top += $yuzde; $o.yuzde_adet++; if ($yuzde -gt $o.tepe_yuzde) { $o.tepe_yuzde = $yuzde } }
        if ($tepe -gt $o.tepe_token) { $o.tepe_token = $tepe }
        if ($yuzde -gt $ozet.tepe_yuzde) { $ozet.tepe_yuzde = $yuzde; $ozet.tepe_rol = $rol }
        $o.son = $r['_z']
        $o.modeller[('{0}/{1}' -f $arac, $r['model'])] = $true
        $k = $(if ($Gun -eq 1) { $r['_z'].ToString('HH') } else { $r['_z'].ToString('yyyy-MM-dd') })
        if ($seri.Contains($k)) { $seri[$k][$ak] += $tok; $seri[$k].cagri++ }
        $gid = [string]$r['gorev']
        if ($gid) { if (-not $gorevler.ContainsKey($gid)) { $gorevler[$gid] = @{ toplam = [long]0; cagri = 0 } }; $gorevler[$gid].toplam += $tok; $gorevler[$gid].cagri++ }
    }
    $rolListe = New-Object Collections.Generic.List[object]
    foreach ($a in $roller.Keys) {
        $o = $roller[$a]
        $uye = Kadro-Bul $kadro $a
        $ad = $a; if ($uye) { $ad = [string]$uye.ad } elseif ($a -eq 'lider') { $ad = 'Engineering Manager' }
        $rolListe.Add([ordered]@{
            anahtar = $a; ad = $ad; renk = [string](Ozellik $uye 'renk'); renk_koyu = [string](Ozellik $uye 'renk_koyu')
            cagri = $o.cagri; basarisiz = $o.basarisiz; sohbet = $o.sohbet; sure_sn = $o.sure_sn
            giris = $o.giris; onbellek_okuma = $o.onbellek_okuma; onbellek_yazma = $o.onbellek_yazma; cikis = $o.cikis; toplam = $o.toplam
            claude = $o.claude; codex = $o.codex; diger = $o.diger
            tepe_yuzde = $(if ($o.tepe_yuzde -ge 0) { $o.tepe_yuzde } else { $null })
            ort_yuzde = $(if ($o.yuzde_adet) { [Math]::Round($o.yuzde_top / $o.yuzde_adet, 1) } else { $null })
            tepe_token = $o.tepe_token; son = $(if ($o.son) { $o.son.ToString('o') } else { $null }); modeller = @($o.modeller.Keys | Sort-Object)
        })
    }
    $rolSirali = @($rolListe | Sort-Object { [long]$_.toplam } -Descending)
    $seriListe = New-Object Collections.Generic.List[object]
    foreach ($k in $seri.Keys) { $seriListe.Add([ordered]@{ anahtar = $k; claude = $seri[$k].claude; codex = $seri[$k].codex; diger = $seri[$k].diger; cagri = $seri[$k].cagri }) }
    $basliklar = @{}; foreach ($g in (Gorevleri-Oku)) { $basliklar[[string]$g.id] = [string]$g.baslik }
    $gorevListe = @($gorevler.Keys | Sort-Object { [long]$gorevler[$_].toplam } -Descending | Select-Object -First 8 | ForEach-Object {
        [ordered]@{ id = $_; baslik = $basliklar[$_]; toplam = $gorevler[$_].toplam; cagri = $gorevler[$_].cagri } })
    $son = New-Object Collections.Generic.List[object]
    for ($i = $kayitlar.Count - 1; $i -ge 0 -and $son.Count -lt 12; $i--) {
        $r = $kayitlar[$i]
        $p = Sayi-Al $r 'baglam_pencere'; $t = Sayi-Al $r 'baglam_tepe'
        $son.Add([ordered]@{ zaman = $r['_z'].ToString('o'); rol = [string]$r['rol']; etiket = [string]$r['etiket']; gorev = [string]$r['gorev']
            arac = ('{0}/{1}' -f $r['arac'], $r['model']); toplam = (Sayi-Al $r 'toplam'); sure_sn = (Sayi-Al $r 'sure_sn'); basarili = [bool]$r['basarili']
            yuzde = $(if ($t -gt 0 -and $p -gt 0) { [Math]::Round(100.0 * $t / $p, 1) } else { $null }); hata = [string]$r['hata'] })
    }
    # Araç hakları: Claude için günlük çağrı sınırı + (varsa güncel) kullanım kartı; Codex için oturum dosyasındaki yüzdeler
    $ayar = Kat-Ayar-Oku
    $sayac = Sayac-Bugun
    $claude = [ordered]@{ bugun = [int](Ozellik $sayac 'claude'); sinir = [int](Ozellik $ayar.gunluk_sinir 'claude'); kalan_yuzde = $null; guncelleme = $null }
    if ($ayar -and $ayar.claude -and $ayar.claude.kullanim_dosyasi) {
        $ck = Json-Oku ([string]$ayar.claude.kullanim_dosyasi)
        $gz = Tarih (Ozellik $ck 'guncelleme_zamani')
        if ($gz) { $claude.guncelleme = $gz.ToString('o'); if (($simdi - $gz).TotalHours -lt [double]$ayar.claude.kullanim_dosyasi_gecerlilik_saat) { $claude.kalan_yuzde = [int]$ck.kalan_yuzde } }
    }
    $codex = [ordered]@{ bugun = [int](Ozellik $sayac 'codex'); sinir = [int](Ozellik $ayar.gunluk_sinir 'codex'); bes_saat = $null; haftalik = $null; guncelleme = $null }
    $hk = Json-Oku (Join-Path $YolDurum 'arac-haklari.json')
    if ($hk -and $hk.codex) { $codex.bes_saat = $hk.codex.bes_saat; $codex.haftalik = $hk.codex.haftalik; $codex.guncelleme = $hk.codex.guncelleme }
    $ilk = $null
    $dosyalar = @(Get-ChildItem -LiteralPath $YolKullanim -Filter 'kullanim-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($dosyalar.Count) { $l = Kullanim-Dosyasi-Oku $dosyalar[0].FullName; if ($l.Count) { $ilk = $l[0]['_z'].ToString('o') } }
    $aracListe = @($araclar.Keys | Sort-Object | ForEach-Object { [ordered]@{ arac = $_; cagri = $araclar[$_].cagri; toplam = $araclar[$_].toplam } })
    # Hesap limitleri (Claude: AI Ekip'in son Claude çağrısındaki oran; Codex: bu bilgisayardaki en yeni Codex oturumu) ve ofis dışı tüketim
    $gorevsiz = [long]0; $gorevsizCagri = 0
    foreach ($r in $kayitlar) { if (-not [string]$r['gorev']) { $gorevsiz += (Sayi-Al $r 'toplam'); $gorevsizCagri++ } }
    $disClaude = $null; $disCodex = $null
    try { $disClaude = Claude-Oturum-Tuketimi $bas } catch {}
    try { $disCodex = Codex-Oturum-Tuketimi $bas } catch {}
    if ($hk -and $hk.claude) { $claude.bes_saat = $hk.claude.bes_saat; $claude.haftalik = $hk.claude.haftalik; $claude.oran_guncelleme = $hk.claude.guncelleme }
    if ($disCodex -and $disCodex.haklar -and (-not $codex.guncelleme -or (Tarih $disCodex.haklar.guncelleme) -gt (Tarih $codex.guncelleme))) {
        $codex.bes_saat = $disCodex.haklar.bes_saat; $codex.haftalik = $disCodex.haklar.haftalik; $codex.guncelleme = $disCodex.haklar.guncelleme
    }
    # Ekip performansı (bu dönem): çağrılar kayıtlardan; başarısız adım ve takılmalar görev geçmişinden, olduğu aşamanın rolüne yazılır
    $perf = @{}
    $pfAl = { param([string]$k) if (-not $perf.ContainsKey($k)) { $perf[$k] = @{ cagri = 0; basarisiz = 0; hata = 0; takilma = 0; biten = 0; yardim = 0; birlikte = 0 } }; return $perf[$k] }
    foreach ($r in $kayitlar) {
        $rol = [string]$r['rol']; if (-not $rol -or [string]$r['etiket'] -like 'sohbet*') { continue }
        $o = & $pfAl $rol; $o.cagri++; if (-not [bool]$r['basarili']) { $o.basarisiz++ }
    }
    $adAnahtar = @{}; foreach ($u in $kadro) { if ($u) { $adAnahtar[[string]$u.ad] = [string]$u.anahtar } }
    foreach ($g in (Gorevleri-Oku)) {
        foreach ($e in @(Ozellik $g 'gecmis')) {
            if (-not $e) { continue }
            $z = Tarih (Ozellik $e 'zaman'); if (-not $z -or $z -lt $bas) { continue }
            $olay = [string]$e.olay
            if ($olay -match '^(.+) yardım istedi$' -and $adAnahtar.ContainsKey($Matches[1])) { $o = & $pfAl $adAnahtar[$Matches[1]]; $o.yardim++; continue }
            $tur = ''; if ($olay -eq 'takıldı') { $tur = 'takilma' } elseif ($olay -eq 'deneme başarısız') { $tur = 'hata' }
            if (-not $tur -or -not [string]$e.asama) { continue }
            $kopya = $g.PSObject.Copy(); $kopya.asama = [string]$e.asama
            $rol = [string](Gorev-Rolu $kopya)
            if ($rol) { $o = & $pfAl $rol; $o[$tur] = [int]$o[$tur] + 1 }
        }
        foreach ($b in @(Ozellik $g 'birlikte')) { if ($b -and $b.rol) { $bz = Tarih (Ozellik $b 'zaman'); if ($bz -and $bz -ge $bas) { $o = & $pfAl ([string]$b.rol); $o.birlikte++ } } }
        if ([string]$g.asama -eq 'tamam') {
            $gz = Tarih (Ozellik $g 'guncelleme')
            if ($gz -and $gz -ge $bas) {
                foreach ($u in $kadro) {
                    $a = [string]$u.anahtar; if (-not $a) { continue }
                    if (([string](Ozellik $g $a) -match '/') -or [bool](@('sorumlu', 'inceleyen', 'destek') | Where-Object { [string](Ozellik $g $_) -eq $a })) { $o = & $pfAl $a; $o.biten++ }
                }
            }
        }
    }
    $perfListe = @()
    foreach ($k in @($perf.Keys)) {
        $o = $perf[$k]; $u = Kadro-Bul $kadro $k
        $ad = $k; if ($u) { $ad = [string]$u.ad } elseif ($k -eq 'lider') { $ad = 'Engineering Manager' }
        $oran = $null; if ($o.cagri -gt 0) { $oran = [Math]::Round(100.0 * ($o.cagri - $o.basarisiz) / $o.cagri, 1) }
        $perfListe += [pscustomobject][ordered]@{ anahtar = $k; ad = $ad; renk = [string](Ozellik $u 'renk'); renk_koyu = [string](Ozellik $u 'renk_koyu')
            cagri = $o.cagri; basarisiz = $o.basarisiz; oran = $oran; hata = $o.hata; takilma = $o.takilma; biten = $o.biten; yardim = $o.yardim; birlikte = $o.birlikte
            sorun = ($o.basarisiz + $o.hata + 2 * $o.takilma) }
    }
    $enBasarili = @($perfListe | Where-Object { $_.cagri -ge 2 -and $null -ne $_.oran } |
        Sort-Object @{ e = { [double]$_.oran }; Descending = $true }, @{ e = { $_.biten }; Descending = $true }, @{ e = { $_.sorun }; Descending = $false }, @{ e = { $_.cagri }; Descending = $true } | Select-Object -First 3)
    $enSorunlu = @($perfListe | Where-Object { $_.sorun -gt 0 } |
        Sort-Object @{ e = { $_.sorun }; Descending = $true }, @{ e = { $_.takilma }; Descending = $true } | Select-Object -First 3)
    return [ordered]@{
        performans = [ordered]@{ basarili = $enBasarili; sorunlu = $enSorunlu }
        gun = $Gun; bas = $bas.ToString('o'); zaman = $simdi.ToString('o'); ozet = $ozet; araclar = $aracListe; roller = $rolSirali
        seri = $seriListe; gorevler = $gorevListe; son = $son; haklar = [ordered]@{ claude = $claude; codex = $codex }; ilk_kayit = $ilk
        bosta = [ordered]@{
            ekip_gorevsiz = $gorevsiz; ekip_gorevsiz_cagri = $gorevsizCagri
            claude_dis = $(if ($disClaude) { $disClaude.toplam } else { $null }); claude_dis_mesaj = $(if ($disClaude) { $disClaude.mesaj } else { 0 }); claude_dis_oturum = $(if ($disClaude) { $disClaude.oturum } else { 0 })
            codex_dis = $(if ($disCodex) { $disCodex.dis } else { $null }); codex_dis_oturum = $(if ($disCodex) { $disCodex.dis_oturum } else { 0 })
        }
        nedenler = (Kok-Neden-Ozeti)
    }
}

# ---------------------------------------------------------------- görev başına token (pano kartları; dosyalar değişmedikçe önbellekten)
$script:GorevTokenOnbellek = @{ imza = '-'; veri = @{} }
function Gorev-Token-Toplamlari {
    $imza = (@(Get-ChildItem -LiteralPath $YolKullanim -Filter 'kullanim-*.jsonl' -File -ErrorAction SilentlyContinue | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Length }) -join '|')
    if ($imza -eq $GorevTokenOnbellek.imza) { return $GorevTokenOnbellek.veri }
    $h = @{}
    foreach ($r in (Kullanim-Kayitlari ((Get-Date).Date.AddDays(-60)))) { $gid = [string]$r['gorev']; if ($gid) { $h[$gid] = [long]$h[$gid] + (Sayi-Al $r 'toplam') } }
    $script:GorevTokenOnbellek = @{ imza = $imza; veri = $h }
    return $h
}

# ---------------------------------------------------------------- ofis dışı tüketim (bu bilgisayardaki diğer Claude Code / Codex oturumları)
# AI Ekip'in Claude çağrıları --no-session-persistence ile çalışır; ~\.claude\projects altındaki dökümler başka oturumlarındır.
# Codex oturumlarından çalışma klasörü ai-ekip altında olanlar ekibe aittir. Dosyalar artımlı okunur (yalnızca eklenen satırlar).
$script:DisOnbellek = @{}
function Dosya-Ekini-Oku($O, [string]$Yol, [long]$Uzunluk) {
    $fs = Paylasimli-Ac $Yol
    try {
        [void]$fs.Seek($O.uzunluk, [IO.SeekOrigin]::Begin)
        $b = New-Object byte[] ([int][Math]::Min([long]64MB, $Uzunluk - $O.uzunluk))
        $n = $fs.Read($b, 0, $b.Length)
    } finally { $fs.Dispose() }
    $metin = $Utf8.GetString($b, 0, $n)
    $son = $metin.LastIndexOf("`n")
    if ($son -lt 0) { return @() }
    $tam = $metin.Substring(0, $son + 1)
    $O.uzunluk += $Utf8.GetByteCount($tam)
    return $tam.Split("`n")
}
function Claude-Oturum-Tuketimi([datetime]$Bas) {
    $kok = Join-Path $env:USERPROFILE '.claude\projects'
    $sonuc = [ordered]@{ toplam = [long]0; mesaj = 0; oturum = 0 }
    if (-not [IO.Directory]::Exists($kok)) { return $sonuc }
    foreach ($f in [IO.Directory]::GetFiles($kok, '*.jsonl', [IO.SearchOption]::AllDirectories)) {
        $fi = New-Object IO.FileInfo $f
        if ($fi.LastWriteTime -lt $Bas) { continue }
        $o = $DisOnbellek[$f]
        if (-not $o -or $fi.Length -lt $o.uzunluk) { $o = @{ uzunluk = [long]0; gunler = @{}; idler = (New-Object 'Collections.Generic.HashSet[string]') }; $DisOnbellek[$f] = $o }
        if ($fi.Length -gt $o.uzunluk) {
            foreach ($s in (Dosya-Ekini-Oku $o $f $fi.Length)) {
                if ($s.IndexOf('"type":"assistant"') -lt 0 -or $s.IndexOf('"usage"') -lt 0) { continue }
                try {
                    $j = $JsCozucu.DeserializeObject($s)
                    $m = $j['message']; if (-not $m) { continue }
                    $id = [string]$m['id']; if ($id -and -not $o.idler.Add($id)) { continue }
                    $u = $m['usage']; if (-not $u) { continue }
                    $t = (Sayi-Al $u 'input_tokens') + (Sayi-Al $u 'cache_read_input_tokens') + (Sayi-Al $u 'cache_creation_input_tokens') + (Sayi-Al $u 'output_tokens')
                    $gun = ([datetime]$j['timestamp']).ToString('yyyy-MM-dd')
                    if (-not $o.gunler.ContainsKey($gun)) { $o.gunler[$gun] = @{ toplam = [long]0; mesaj = 0 } }
                    $o.gunler[$gun].toplam += $t; $o.gunler[$gun].mesaj++
                } catch {}
            }
        }
        $var = $false
        foreach ($g in $o.gunler.Keys) { if ([datetime]$g -ge $Bas.Date) { $sonuc.toplam += $o.gunler[$g].toplam; $sonuc.mesaj += $o.gunler[$g].mesaj; $var = $true } }
        if ($var) { $sonuc.oturum++ }
    }
    return $sonuc
}
function Codex-Oturum-Tuketimi([datetime]$Bas) {
    $ev = $env:CODEX_HOME; if (-not $ev) { $ev = Join-Path $env:USERPROFILE '.codex' }
    $sonuc = [ordered]@{ dis = [long]0; dis_oturum = 0; ekip = [long]0; haklar = $null }
    $enYeni = $null
    for ($d = $Bas.Date; $d -le (Get-Date).Date; $d = $d.AddDays(1)) {
        $kl = Join-Path (Join-Path $ev 'sessions') ('{0:yyyy}\{0:MM}\{0:dd}' -f $d)
        if (-not [IO.Directory]::Exists($kl)) { continue }
        foreach ($f in [IO.Directory]::GetFiles($kl, 'rollout-*.jsonl')) {
            $fi = New-Object IO.FileInfo $f
            $o = $DisOnbellek[$f]
            if (-not $o -or $fi.Length -lt $o.uzunluk) { $o = @{ uzunluk = [long]0; cwd = ''; toplam = [long]0; haklar = $null; haklar_zaman = $null }; $DisOnbellek[$f] = $o }
            if ($fi.Length -gt $o.uzunluk) {
                foreach ($s in (Dosya-Ekini-Oku $o $f $fi.Length)) {
                    if (-not $o.cwd -and $s.IndexOf('"session_meta"') -ge 0) { try { $o.cwd = [string]($JsCozucu.DeserializeObject($s))['payload']['cwd'] } catch {} ; continue }
                    if ($s.IndexOf('"token_count"') -lt 0) { continue }
                    try {
                        $j = $JsCozucu.DeserializeObject($s); $p = $j['payload']
                        if ($p['info']) { $o.toplam = Sayi-Al $p['info']['total_token_usage'] 'total_tokens' }
                        if ($p['rate_limits']) { $o.haklar = $p['rate_limits']; $o.haklar_zaman = [datetime]$j['timestamp'] }
                    } catch {}
                }
            }
            $ekipten = ($o.cwd -and $o.cwd.StartsWith($KodKok, [StringComparison]::OrdinalIgnoreCase))
            if ($ekipten) { $sonuc.ekip += $o.toplam } elseif ($o.toplam -gt 0) { $sonuc.dis += $o.toplam; $sonuc.dis_oturum++ }
            if ($o.haklar -and (-not $enYeni -or $o.haklar_zaman -gt $enYeni.haklar_zaman)) { $enYeni = $o }
        }
    }
    if ($enYeni) {
        $cevir = { param($x) if (-not $x) { return $null }; $s = $null; if ($x['resets_at']) { $s = [DateTimeOffset]::FromUnixTimeSeconds([int64]$x['resets_at']).LocalDateTime.ToString('o') }; return [ordered]@{ yuzde = [double]$x['used_percent']; sifirlanma = $s } }
        $sonuc.haklar = [ordered]@{ bes_saat = (& $cevir $enYeni.haklar['primary']); haftalik = (& $cevir $enYeni.haklar['secondary']); guncelleme = $enYeni.haklar_zaman.ToString('o') }
    }
    return $sonuc
}

# ---------------------------------------------------------------- kök nedenler (Incident Manager'ın kategorileri; cozucu.ps1)
function Kok-Neden-Ozeti {
    $gruplar = [ordered]@{}
    $bekleyen = 0
    foreach ($g in (Gorevleri-Oku)) {
        $a = [string]$g.asama
        $kn = Ozellik $g 'kok_neden'
        if (-not $kn) { if ($a -eq 'iptal' -or $a -eq 'takildi') { $bekleyen++ }; continue }
        $k = [string]$kn.kategori
        if (-not $gruplar.Contains($k)) { $gruplar[$k] = [ordered]@{ kategori = $k; ad = [string]$kn.ad; adet = 0; gorevler = (New-Object Collections.Generic.List[object]) } }
        $gruplar[$k].adet++
        $gruplar[$k].gorevler.Add([ordered]@{ id = $g.id; baslik = $g.baslik; asama = $a; alt = [string]$kn.alt; ozet = [string]$kn.ozet; onlem = [string]$kn.onlem; zaman = [string]$kn.zaman })
    }
    return [ordered]@{ kategoriler = @($gruplar.Values | Sort-Object { $_.adet } -Descending); bekleyen = $bekleyen }
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
            $o = $Onbellek[$d]
            if ($o -and $o.damga -eq $damga) { $g = $o.nesne }
            else {
                $g = Json-Oku $f
                if ($g) { $Onbellek[$d] = @{ damga = $damga; nesne = $g } }
            }
        } else { $g = Json-Oku $f }
        if ($g -and (Ozellik $g 'id')) { $liste.Add($g); $gorulen[$d] = $true }
    }
    $onEk = $YolGorev.TrimEnd('\') + '\'
    foreach ($k in @($Onbellek.Keys)) { if ($k.StartsWith($onEk, [StringComparison]::OrdinalIgnoreCase) -and -not $gorulen.ContainsKey($k)) { $Onbellek.Remove($k) } }
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
    $ayar = Kat-Ayar-Oku
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
    if ($calisiyor) { $ke = Kalp-Etiketi $kalpAdim $aktif; $kalpEtiket = $ke.etiket; $anlikArac = $ke.arac }
    # Panelden komutla açılan paralel hatlar: ana döngüden bağımsız yürüyen işler
    $paralelHatlar = Paralel-Hatlari-Oku $gorevler $bostaDurumlari
    $paralelGorev = @{}; foreach ($h in $paralelHatlar) { $paralelGorev[[string]$h.gorev] = $h }
    $anaHat = [ordered]@{ g = $aktif; etiket = $kalpEtiket; arac = $anlikArac; calisiyor = $calisiyor; paralel = $false }
    # Incident Manager takılan bir işi inceliyor (görev aşaması 'takildi' olduğundan yukarıdaki "aktif" görev değildir)
    $cozumGorev = $null; $cozumArac = ''
    $cozumTur = ''
    if ($saglik -eq 'saglikli' -and $kalpGorev -and ($bostaDurumlari -notcontains $kalpDurum) -and $kalpAdim -match '^(cozum|kategori)(?: \((.+)\))?$') {
        $cozumTur = [string]$Matches[1]; $cozumArac = [string]$Matches[2]
        foreach ($g in $gorevler) { if ($g.id -eq $kalpGorev) { $cozumGorev = $g; break } }
    }
    # CTO yönetim değerlendirmesi yapıyor (yonetim.ps1: görev yok, kalp adımı "yonetim" ya da "yonetim (araç/model)")
    $ctoCalisiyor = $false; $ctoArac = ''
    if ($saglik -eq 'saglikli' -and ($bostaDurumlari -notcontains $kalpDurum) -and $kalpAdim -match '^yonetim(?: \((.+)\))?$') { $ctoCalisiyor = $true; $ctoArac = [string]$Matches[1] }
    $yardimBekleyen = $null
    foreach ($g in $gorevler) { if ([string]$g.asama -eq 'takildi' -and [string](Ozellik $g 'cozum_durumu') -eq 'yardim_bekleniyor') { $yardimBekleyen = $g; break } }
    $bugunRol = @{}
    try { $bugunRol = Kullanim-Bugun-Rol } catch {}
    $epostaKurulu = [IO.File]::Exists((Join-Path $YolDurum 'eposta.json'))

    # ---- roller (kadro.json sırasıyla)
    $kadro = Kadro-Listesi
    $roller = New-Object Collections.Generic.List[object]
    $anaAktif = $aktif; $anaEtiket = $kalpEtiket
    foreach ($uye in $kadro) {
        $rol = [string]$uye.anahtar
        # Bu çalışan hangi hatta iş başında: ana döngü ya da panelden komutla açılan paralel hat
        $hat = $null
        if ($calisiyor -and ((Gorev-Rolu $anaAktif $anaEtiket) -eq $rol)) { $hat = $anaHat }
        else { foreach ($h in $paralelHatlar) { if ($h.calisiyor -and ((Gorev-Rolu $h.g $h.etiket) -eq $rol)) { $hat = $h; break } } }
        if ($hat) { $aktif = $hat.g; $kalpEtiket = $hat.etiket; $anlikArac = $hat.arac }
        else { $aktif = $anaAktif; $kalpEtiket = $anaEtiket; $anlikArac = '' }
        $aktifTip = ''; if ($aktif) { $aktifTip = Gorev-Tipi $aktif }
        $haric = @()
        if ($aktifTip -eq 'yazilim' -and ($rol -eq 'denetci' -or $kalpEtiket -eq "inceleme-$rol") -and (Ozellik $aktif 'gelistirici')) { $haric = @([string]$aktif.gelistirici) }
        if ($aktifTip -eq 'altyapi' -and $rol -eq [string](Ozellik $aktif 'destek') -and (Ozellik $aktif 'uygulayan')) { $haric = @([string]$aktif.uygulayan) }
        if ($aktifTip -eq 'uzman' -and $rol -eq [string](Ozellik $aktif 'inceleyen') -and (Ozellik $aktif 'uygulayan')) { $haric = @([string]$aktif.uygulayan) }
        $zincir = New-Object Collections.Generic.List[object]
        $siradaki = ''
        $girisler = @()
        $ayarZinciri = $null; if ($ayar -and $ayar.roller) { $ayarZinciri = Ozellik $ayar.roller $rol }
        $zincirKaynak = ''
        if ($ayarZinciri) { $girisler = @($ayarZinciri); $zincirKaynak = 'ayarlar' } elseif ($uye.araclar) { $girisler = @($uye.araclar); $zincirKaynak = 'kadro' }
        foreach ($gi in $girisler) {
            if (-not $gi) { continue }
            $kimlik = '{0}/{1}' -f $gi.arac, $gi.model
            $neden = ''
            if ($haric -contains $kimlik) { $neden = 'işi yapanla aynı model; incelemede atlanır' }
            else { $neden = Arac-Engeli $gi $sayac $kilitler $ayar $claudeKullanim $simdi }
            if (-not $neden -and -not $siradaki) { $siradaki = $kimlik }
            $zincir.Add([ordered]@{ kimlik = $kimlik; arac = [string]$gi.arac; model = [string]$gi.model; efor = [string](Ozellik $gi 'efor'); neden = $neden })
        }
        $isbasinda = [bool]$hat
        $faaliyet = 'bosta'; $metin = 'Boşta'; $gorevBilgi = $null; $baslangic = $null
        $arac = $siradaki; $aracKaynak = 'sıradaki'; $not = ''
        if ($rol -eq 'sorun-giderici' -and $cozumGorev) {
            $isbasinda = $true
            $faaliyet = 'cozum'; $metin = $(if ($cozumTur -eq 'kategori') { 'Başarısızlığın kök nedenini inceliyor' } else { 'Takılan işi inceliyor' })
            $gorevBilgi = [ordered]@{ id = $cozumGorev.id; baslik = $cozumGorev.baslik; tur = $cozumGorev.tur; max_tur = $cozumGorev.max_tur }
            $baslangic = Ozellik $kalp 'zaman'
            if ($cozumArac) { $arac = $cozumArac; $aracKaynak = 'şu an' }
        } elseif ($rol -eq 'cto' -and $ctoCalisiyor) {
            $isbasinda = $true
            $faaliyet = 'yonetim'; $metin = 'Yönetim değerlendirmesi yapıyor'
            $baslangic = Ozellik $kalp 'zaman'
            if ($ctoArac) { $arac = $ctoArac; $aracKaynak = 'şu an' }
        } elseif ($isbasinda) {
            $asama = [string]$aktif.asama
            $altyapi = ($aktifTip -eq 'altyapi')
            if ($kalpEtiket -eq 'ise_alim') { $faaliyet = 'ise_alim'; $metin = 'İşe alım yapıyor' }
            elseif ($kalpEtiket -match '^birlikte-') { $faaliyet = 'calisma'; $metin = 'Ekip arkadaşıyla birlikte çalışıyor (anlık yardım)' }
            elseif ($kalpEtiket -eq 'kat-gonder') { $faaliyet = 'calisma'; $metin = 'İşi başka kata brif olarak yazıyor (katlar arası iletişim)' }
            elseif ($kalpEtiket -eq 'kat-rapor') { $faaliyet = 'calisma'; $metin = 'Başka kattan gelen sonucu ekibe raporluyor' }
            elseif ($aktifTip -eq 'yaratici' -and $YaraticiFaaliyet.ContainsKey($asama)) { $faaliyet = $YaraticiFaaliyet[$asama]; $metin = $YaraticiMetni[$asama] }
            elseif ($asama -eq 'yardim') { $faaliyet = 'plan'; $metin = 'Ekip içi yardım isteğini değerlendiriyor' }
            elseif ($asama -eq 'analiz') { $faaliyet = 'analiz'; $metin = $AsamaMetni['analiz'] }
            elseif ($aktifTip -eq 'genel') { $faaliyet = 'plan'; $metin = 'Yeni işi okuyup kime vereceğine karar veriyor' }
            elseif ($rol -eq 'tester' -and $asama -eq 'test') { $faaliyet = 'test'; $metin = $AsamaMetni['test'] }
            elseif ($rol -eq 'tester') { $faaliyet = 'inceleme'; $metin = 'Uygulamayı test ediyor' }
            elseif ($kalpEtiket -match '^inceleme-') { $faaliyet = 'inceleme'; $metin = 'Kodu kendi alanından inceliyor' }
            elseif ($altyapi) {
                $faaliyet = $AltyapiFaaliyet[$asama]; $metin = $AltyapiMetni[$asama]
                if ($asama -eq 'gelistirme' -and $rol -eq 'ag') { $metin = 'Ağ işini yapıyor' }
            } elseif ($aktifTip -eq 'danisman') {
                $faaliyet = $(if ($asama -eq 'kontrol') { 'kontrol' } else { 'calisma' }); $metin = $DanismanMetni[$asama]
                if (-not $metin) { $metin = 'Terminalde çalışıyor' }
            } elseif ($aktifTip -eq 'uzman') {
                $faaliyet = $UzmanFaaliyet[$asama]; $metin = $UzmanMetni[$asama]
                if ($asama -eq 'gelistirme' -and $uye.faaliyet_metni) { $metin = [string]$uye.faaliyet_metni }
            } else {
                $faaliyet = $AsamaFaaliyet[$asama]; $metin = $AsamaMetni[$asama]
                if ($asama -eq 'gelistirme' -and $uye.faaliyet_metni) { $metin = [string]$uye.faaliyet_metni }
            }
            $gorevBilgi = [ordered]@{ id = $aktif.id; baslik = $aktif.baslik; tur = $aktif.tur; max_tur = $aktif.max_tur }
            $baslangic = Ozellik $aktif 'olusturma'
            $gecmis = @(Ozellik $aktif 'gecmis')
            if ($gecmis.Count -gt 0 -and $gecmis[-1]) { $baslangic = $gecmis[-1].zaman }
            if ($anlikArac) { $arac = $anlikArac; $aracKaynak = 'şu an' }
            elseif ($asama -eq 'kontrol') { $arac = $(if ($aktifTip -eq 'yazilim') { 'betik · otomatik kontrol' } else { 'betik · doğrulama komutları' }); $aracKaynak = 'şu an' }
            elseif ($aktifTip -eq 'yaratici' -and ($asama -eq 'yeni' -or $asama -eq 'bekleme')) { $arac = $(if ($asama -eq 'bekleme') { 'betik · ana kata köprü' } else { 'betik' }); $aracKaynak = 'şu an' }
            elseif (($asama -eq 'yeni' -or $asama -eq 'tamamla') -and $aktifTip -ne 'genel') { $arac = $(if ($altyapi) { 'betik · keşif' } elseif ($aktifTip -eq 'uzman') { 'betik' } else { 'git' }); $aracKaynak = 'şu an' }
        } else {
            foreach ($g in $gorevler) {
                $sd = Tarih (Ozellik $g 'sonraki_deneme')
                # Fikir hattında "bekleme" ana katı izleme aralığıdır, yeniden deneme değil
                if ((Gorev-Tipi $g) -eq 'yaratici' -and [string]$g.asama -eq 'bekleme') { continue }
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
            # Ekip içi yardım isteyen çalışan, yardım gelene kadar bekler
            foreach ($g in $gorevler) {
                if ($faaliyet -ne 'bosta') { break }
                $ga = [string]$g.asama
                if (($ga -eq 'yardim' -or $ga -eq 'yardim_bekliyor') -and [string](Ozellik $g 'yardim_isteyen') -eq $rol) {
                    $faaliyet = 'bekliyor'; $metin = $(if ($ga -eq 'yardim') { 'Engineering Managerʼdan yardım istedi' } else { 'Ekipten yardım bekliyor' })
                    $gorevBilgi = [ordered]@{ id = $g.id; baslik = $g.baslik; tur = $g.tur; max_tur = $g.max_tur }
                    $yb = @(Ozellik $g 'yardim_bekleyen' | Where-Object { $_ })
                    $not = 'İstek: {0}{1}' -f [string](Ozellik $g 'yardim_istek'), $(if ($yb.Count) { ' · yardım işi: ' + (($yb | ForEach-Object { '#' + ([string]$_ -split '-')[0] }) -join ', ') } else { '' })
                }
            }
            if ($rol -eq 'sorun-giderici' -and $yardimBekleyen) {
                $faaliyet = 'bekliyor'; $metin = 'Yardım işinin bitmesini bekliyor'
                $gorevBilgi = [ordered]@{ id = $yardimBekleyen.id; baslik = $yardimBekleyen.baslik; tur = $yardimBekleyen.tur; max_tur = $yardimBekleyen.max_tur }
                $not = 'Yardım işi: #{0}' -f ([string](Ozellik $yardimBekleyen 'yardim_gorevi'))
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
            uzman_isi = [bool](Ozellik $uye 'uzman_isi'); dogrudan_is = [bool](Ozellik $uye 'dogrudan_is'); tanisma = [string](Ozellik $uye 'tanisma'); ise_alan = [string](Ozellik $uye 'ise_alan')
            kisa_ad = [string](Ozellik $uye 'kisa_ad')
            yeni = [bool]($iseAlinma -and ($simdi - $iseAlinma).TotalDays -lt 7)
            faaliyet = $faaliyet; metin = $metin; calisiyor = [bool]$isbasinda
            gorev = $gorevBilgi; baslangic = $baslangic; arac = $arac; arac_kaynak = $aracKaynak; zincir = $zincir
            not = $not; son_kullanilan = $sonKullanilan
            sohbette = [bool](Sohbet-Isleniyor $rol); sohbet_son = (Sohbet-Son $rol)
            bugun = $(if ($bugunRol.ContainsKey($rol)) { [ordered]@{ cagri = $bugunRol[$rol].cagri; toplam = $bugunRol[$rol].toplam } } else { [ordered]@{ cagri = 0; toplam = 0 } })
            zincir_kaynak = $zincirKaynak; rol_tr = [string](Ozellik $uye 'rol_tr')
            hat = $(if ($hat -and $hat.paralel) { 'paralel' } elseif ($hat) { 'ana' } else { '' })
        })
    }
    $aktif = $anaAktif; $kalpEtiket = $anaEtiket; $anlikArac = $anaHat.arac

    # ---- görev kartları (son 60 günün token toplamlarıyla)
    $gorevToken = @{}
    try { $gorevToken = Gorev-Token-Toplamlari } catch {}
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
            canliya_alim = (Ozellik $g 'canliya_alim')
            kaynak_kat = (Ozellik $g 'kaynak_kat'); kaynak_gorev = (Ozellik $g 'kaynak_gorev'); yazisma = (Ozellik $g 'yazisma'); kat_yazismalari = @(Ozellik $g 'kat_yazismalari' | Where-Object { $_ })
            alan = (Ozellik $g 'alan'); revizyon = (Ozellik $g 'revizyon'); karar = (Ozellik $g 'karar'); puan = (Ozellik $g 'puan')
            ana_gorev_id = (Ozellik $g 'ana_gorev_id'); ana_asama = $(if ((Gorev-Tipi $g) -eq 'yaratici') { Yaratici-Ana-Asama $g } else { '' }); teslim_turu = (Ozellik $g 'teslim_turu')
            ana_takildi = [bool](Ozellik $g 'ana_takildi'); takildi_asama = (Ozellik $g 'takildi_asama')
            sonraki_deneme = (Ozellik $g 'sonraki_deneme'); guncelleme = (Ozellik $g 'guncelleme'); olusturma = (Ozellik $g 'olusturma')
            lider = (Ozellik $g 'lider'); gelistirici = (Ozellik $g 'gelistirici'); denetci = (Ozellik $g 'denetci')
            aktif = [bool](($calisiyor -and $aktif.id -eq $g.id) -or ($paralelGorev.ContainsKey([string]$g.id) -and $paralelGorev[[string]$g.id].calisiyor))
            cozuluyor = [bool]($cozumGorev -and $cozumGorev.id -eq $g.id)
            cozum_durumu = (Ozellik $g 'cozum_durumu'); cozum_son_karar = (Ozellik $g 'cozum_son_karar'); cozum_teshis = (Ozellik $g 'cozum_teshis')
            cozum_kullaniciya = (Ozellik $g 'cozum_kullaniciya'); cozum_sayisi = (Ozellik $g 'cozum_sayisi')
            yardim_gorevi = (Ozellik $g 'yardim_gorevi'); ana_gorev = (Ozellik $g 'ana_gorev'); yonlendirme_karari = (Ozellik $g 'yonlendirme_karari')
            yardim_bekleyen = @(Ozellik $g 'yardim_bekleyen' | Where-Object { $_ }); yardim_isteyen = (Ozellik $g 'yardim_isteyen')
            yardim_istek = (Ozellik $g 'yardim_istek'); yardim_donus_asama = (Ozellik $g 'yardim_donus_asama'); yardim_sayisi = (Ozellik $g 'yardim_sayisi')
            kok_neden = (Ozellik $g 'kok_neden'); tur_sayisi = $g.tur
            puan_yonetici = (Ozellik $g 'puan_yonetici'); puan_ajan = (Ozellik $g 'puan_ajan')
            birlikte_sayisi = @(Ozellik $g 'birlikte' | Where-Object { $_ }).Count
            devralan = (Ozellik $g 'devralan'); one_al = [bool](Ozellik $g 'one_al'); komut_sayisi = @(Ozellik $g 'komutlar' | Where-Object { $_ }).Count
            gelistirme_isleri = @(Ozellik $g 'gelistirme_isleri' | Where-Object { $_ } | ForEach-Object { [ordered]@{ rol = [string](Ozellik $_ 'rol'); is = [string](Ozellik $_ 'is'); durum = [string](Ozellik $_ 'durum'); tur = (Ozellik $_ 'tur') } })
            qa_testi = (Ozellik $g 'qa_testi'); gereksinim_durumu = (Ozellik $g 'gereksinim_durumu'); kesif_durumu = (Ozellik $g 'kesif_durumu')
            kapsam = (Ozellik $g 'kapsam'); soru_soran = (Ozellik $g 'soru_soran'); urun = (Ozellik $g 'urun'); kasif = (Ozellik $g 'kasif'); tester = (Ozellik $g 'tester')
            paralel = $(if ($paralelGorev.ContainsKey([string]$g.id)) { $ph = $paralelGorev[[string]$g.id]; [ordered]@{ kim = $ph.kim; emir = $ph.emir; baslangic = $ph.baslangic; adim_sayisi = $ph.adim_sayisi; durum = $ph.durum } } else { $null })
            sahip = $(if ($AktifAsamalar -contains $asama) { Gorev-Rolu $g }
                elseif ($asama -eq 'yardim_bekliyor') {
                    $yi = [string](Ozellik $g 'yardim_isteyen')
                    if (-not $yi -and (Ozellik $g 'yardim_donus_asama')) { $kopya = $g.PSObject.Copy(); $kopya.asama = [string](Ozellik $g 'yardim_donus_asama'); $yi = Gorev-Rolu $kopya }
                    $yi
                } elseif ($asama -eq 'takildi') { 'sorun-giderici' } else { '' })
            donus_asama = $(if ($asama -eq 'takildi') { Ozellik $g 'takildi_asama' } elseif ($asama -like 'yardim*') { Ozellik $g 'yardim_donus_asama' } else { $null })
            token = $(if ($gorevToken.ContainsKey([string]$g.id)) { $gorevToken[[string]$g.id] } else { 0 })
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
            saglik = $saglik; calisiyor = [bool]($calisiyor -or $cozumGorev -or $ctoCalisiyor -or @($paralelHatlar | Where-Object { $_.calisiyor }).Count); duraklatildi = $duraklatildi
            durdur_metni = $(if ($duraklatildi) { (Metin-Oku $durdurYolu 500).Trim() } else { '' })
            kalp_durum = $kalpDurum; kalp_zaman = (Ozellik $kalp 'zaman'); kalp_gorev = $kalpGorev; kalp_adim = $kalpAdim
            yas_sn = $yasSn; pid = $kalpPid; pid_canli = $pidCanli; bekci_dk = $bekciDk
            aktif_gorev = $(if ($aktif) { $aktif.id } else { '' })
            paralel = @($paralelHatlar | ForEach-Object { [ordered]@{ gorev = $_.gorev; kim = $_.kim; emir = $_.emir; baslangic = $_.baslangic; adim_sayisi = $_.adim_sayisi; durum = $_.durum; calisiyor = $_.calisiyor } })
            paralel_etkin = [bool](-not ($ayar -and $ayar.paralel -and $ayar.paralel.etkin -eq $false))
            paralel_en_fazla = $(if ($ayar -and $ayar.paralel -and $ayar.paralel.en_fazla) { [int]$ayar.paralel.en_fazla } else { 2 })
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
        model_katalogu = $(if ($ayar -and $ayar.model_katalogu) { $mk = [ordered]@{}; foreach ($mkArac in @('claude', 'codex', 'gemini')) { if ($ayar.model_katalogu.PSObject.Properties[$mkArac]) { $mk[$mkArac] = @($ayar.model_katalogu.$mkArac | Where-Object { $_ }) } }; $mk } else { $null })
        yonetim = (Yonetim-Ozeti $ayar $ctoCalisiyor)
        kat = [ordered]@{ id = $AktifKatId; ad = [string]$AktifKat.ad; kisa_ad = [string]$AktifKat.kisa_ad; renk = [string]$AktifKat.renk; simge = [string]$AktifKat.simge; kat_no = $AktifKat.kat_no; sirket = (Bina-Bilgisi); kat_sayisi = @(Katlar-Listesi).Count }
        yazismalar = (Yazisma-Listesi $AktifKatId 12)
        ofis = (Ofis-Durumu $ayar $duraklatildi)
        ana_ofis = $(if ($AktifKatId -ne 'ana') { Ana-Ofis $ayar } else { $null })
        yaratici = $(if (Yaratici-Katinda-mi $kadro) { $ya = Yaratici-Ayar-Oku $ayar; [ordered]@{ revizyon_siniri = $ya.revizyon_siniri; varsayilan_proje = $ya.varsayilan_proje; kopru = [bool]$ya.ana_ofis_yolu } } else { $null })
        uzak = [bool]$script:IstekUzak
        sorun_giderici = [ordered]@{
            etkin = [bool]($ayar -and $ayar.roller -and (Ozellik $ayar.roller 'sorun-giderici') -and -not ($ayar.sorun_giderici -and $ayar.sorun_giderici.etkin -eq $false))
            en_fazla = $(if ($ayar -and $ayar.sorun_giderici -and $ayar.sorun_giderici.gorev_basina_en_fazla) { [int]$ayar.sorun_giderici.gorev_basina_en_fazla } else { 2 })
        }
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
    $cozumler = New-Object Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $gk -Filter 'cozum-*.md' -File -ErrorAction SilentlyContinue | Sort-Object { [int]($_.BaseName -replace '\D', '') })) {
        $cozumler.Add([ordered]@{ ad = $f.Name; zaman = $f.LastWriteTime.ToString('o'); md = (Metin-Oku $f.FullName 60000) })
    }
    # Ekip içi yardım: istekler, Engineering Managerʼın kararları ve gelen yardımlar (yardim.ps1)
    $yardimlar = New-Object Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $gk -Filter 'yardim-*.md' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
        $yardimlar.Add([ordered]@{ ad = $f.Name; zaman = $f.LastWriteTime.ToString('o'); md = (Metin-Oku $f.FullName 60000) })
    }
    $katYazismalari = New-Object Collections.Generic.List[object]
    $yids = @(); if ($g) { $yids = @(Ozellik $g 'kat_yazismalari' | Where-Object { $_ }); $yz = [string](Ozellik $g 'yazisma'); if ($yz) { $yids += $yz } }
    foreach ($yid in $yids) { try { $katYazismalari.Add((Yazisma-Ayrinti ([string]$yid))) } catch {} }
    $yaratici = $null
    if ($g -and (Gorev-Tipi $g) -eq 'yaratici') {
        $belgeler = [ordered]@{}
        foreach ($ad in @('gorev.md', 'fikir.md', 'elestiri.md', 'poc-plan.md', 'maliyet.md', 'karar.md', 'teslim.json', 'teslim.md', 'ana-ofis-ciktisi.md', 'uygulama-ciktisi.md', 'puanlama.md', 'sonuc.md')) {
            $belgeler[$ad] = Metin-Oku (Join-Path $gk $ad) 200000
        }
        $kayit = New-Object Collections.Generic.List[object]
        $kd = Join-Path $gk 'kayitlar'
        if ([IO.Directory]::Exists($kd)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $kd -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.md', '.txt') } | Sort-Object FullName | Select-Object -First 400)) {
                $kayit.Add([ordered]@{ ad = $f.Name; yol = ($f.FullName.Substring($gk.Length + 1) -replace '\\', '/'); boyut = $f.Length; zaman = $f.LastWriteTime.ToString('o') })
            }
        }
        $ayarY = Kat-Ayar-Oku
        $yaratici = [ordered]@{
            belgeler = $belgeler; geri_bildirimler = @(Ozellik $g 'geri_bildirimler' | Where-Object { $_ }); revizyon_siniri = (Yaratici-Ayar-Oku $ayarY).revizyon_siniri
            ana_asama = (Yaratici-Ana-Asama $g); ana_panel = (Ana-Ofis $ayarY).panel; ana_kok = (Ana-Kok $ayarY $g); kayitlar = $kayit
            onceki_teslimler = @(Ozellik $g 'onceki_teslimler' | Where-Object { $_ })
        }
    }
    return [ordered]@{
        kat_yazismalari = $katYazismalari
        canliya_alim_md = (Metin-Oku (Join-Path $gk 'canliya-alim.md') 60000)
        yaratici = $yaratici
        yardimlar = $yardimlar
        yonlendirme_md = (Metin-Oku (Join-Path $gk 'yonlendirme.md') 60000)
        cozumler = $cozumler
        durum = $g
        asama_adi = $(if ($g) { Asama-Adi-Bul $g } else { '' })
        tip = $(if ($g) { Gorev-Tipi $g } else { 'yazilim' })
        ciktilar = (Cikti-Listesi $Id)
        sonuc_md = (Metin-Oku (Join-Path $gk 'sonuc.md') 100000)
        kesif_md = (Metin-Oku (Join-Path $gk 'kesif.md') 50000)
        gereksinimler_md = (Metin-Oku (Join-Path $gk 'gereksinimler.md') 100000)
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
    if ($Yol -notmatch '^((tur\d{1,3}|kayitlar(/revizyon-\d{1,2}/[a-z-]{2,40}-deneme-\d{1,2})?)/)?[A-Za-z0-9][A-Za-z0-9._-]{0,150}$' -or $Yol -match '\.\.') { throw 'HTTP:400:Geçersiz dosya yolu' }
    if ($Yol -notmatch '\.(md|txt|diff|err|json)$') { throw 'HTTP:400:Bu dosya türü gösterilmiyor' }
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
    $yol = Join-Path $KodKok $Betik
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
# "İş ver": türü seçilmemiş iş; Engineering Manager okur ve kime vereceğine kendisi karar verir (is-ver.ps1, yonlendirme.ps1)
function Eylem-IsVer($Veri) {
    $baslik = Metin-Alani $Veri 'baslik' 120 -Zorunlu
    $aciklama = Metin-Alani $Veri 'aciklama' 8000 -Zorunlu
    $ipucu = Metin-Alani $Veri 'ipucu' 400
    $rol = Metin-Alani $Veri 'rol' 40
    $kabul = Liste-Alani $Veri 'kabul' 20 500
    $dogrulama = Liste-Alani $Veri 'dogrulama' 10 300
    $oncelik = [int](Ozellik $Veri 'oncelik')
    if ($oncelik -lt 1 -or $oncelik -gt 3) { $oncelik = 2 }
    if ($rol -and $rol -notmatch '^[a-z][a-z0-9-]{1,39}$') { throw 'HTTP:400:Geçersiz çalışan anahtarı' }
    $a = @('-Baslik', (Ps-Tirnak $baslik), '-Aciklama', (Ps-Tirnak $aciklama))
    if ($ipucu) { $a += '-Ipucu'; $a += (Ps-Tirnak $ipucu) }
    if ($rol) { $a += '-Rol'; $a += (Ps-Tirnak $rol) }
    if ($kabul.Count -gt 0) { $a += '-Kabul'; $a += ('@(' + (($kabul | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    if ($dogrulama.Count -gt 0) { $a += '-Dogrulama'; $a += ('@(' + (($dogrulama | ForEach-Object { Ps-Tirnak $_ }) -join ', ') + ')') }
    $a += '-Oncelik'; $a += [string]$oncelik
    $r = Betik-Calistir 'is-ver.ps1' ($a -join ' ')
    $m = [regex]::Match([string]$r.cikti, 'İş eklendi: (\S+)')
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
    $m = [regex]::Match($Yol, '^/onizle/([0-9a-f]{32,64})/(?:@([a-z0-9][a-z0-9-]{0,30})/)?(\d{4}-[A-Za-z0-9-]{1,60})/(.+)$')
    if (-not $m.Success -or $m.Groups[1].Value -cne $OnizlemeAnahtari) { Yanit-Metin $Akis 404 'Bulunamadı'; return }
    $katP = $m.Groups[2].Value; if (-not $katP) { $katP = 'ana' }
    try { Kat-Sec $katP } catch { Yanit-Metin $Akis 404 'Bulunamadı'; return }
    $wt = [IO.Path]::GetFullPath((Join-Path (Join-Path $Kok 'calisma') $m.Groups[3].Value))
    $parcalar = @($m.Groups[4].Value.Split('/') | ForEach-Object { [Uri]::UnescapeDataString($_) })
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
# Panoda sürükle-bırak: görevi başka aşamaya taşır (durum.ps1 -Tasi > cozucu.ps1 Gorev-Asamaya-Tasi)
function Eylem-Tasi($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    $asama = Metin-Alani $Veri 'asama' 20 -Zorunlu
    if (@('yeni', 'plan', 'gelistirme', 'kontrol', 'tamamla') -notcontains $asama) { throw 'HTTP:400:Bu aşamaya taşınamaz' }
    $not = Metin-Alani $Veri 'not' 4000
    [void](Gorev-Klasoru-Bul $id)
    $a = '-Tasi ' + (Ps-Tirnak $id) + ' -Asama ' + $asama
    if ($not) { $a += ' -Not ' + (Ps-Tirnak $not) }
    return (Betik-Calistir 'durum.ps1' $a)
}
# Çalışana doğrudan komut (karakter kartı / görev ayrıntısı): durum.ps1 -Komut kaydeder (komut.ps1); iş hemen ilerleyecekse
# paralel hattı (paralel.ps1) bu sunucu görünmez pencerede başlatır
function Eylem-Komut($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    $kim = Sohbet-Rolu (Metin-Alani $Veri 'kim' 40 -Zorunlu)
    $emir = Metin-Alani $Veri 'emir' 10 -Zorunlu
    if (@('devam', 'devral') -notcontains $emir) { throw 'HTTP:400:Bilinmeyen komut (devam | devral)' }
    $not = Metin-Alani $Veri 'not' 4000
    [void](Gorev-Klasoru-Bul $id)
    $a = '-Komut ' + (Ps-Tirnak $id) + ' -Kim ' + (Ps-Tirnak $kim) + ' -Emir ' + $emir + ' -Baslatma'
    if ($not) { $a += ' -Not ' + (Ps-Tirnak $not) }
    $r = Betik-Calistir 'durum.ps1' $a
    if ($r.basarili -and ([string]$r.cikti -match '(?m)^PARALEL: (\d{4}-[A-Za-z0-9-]{1,60})\s*$')) {
        $gid = $Matches[1]
        $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -Gorev {2} -Kim {3} -Komut {4}' -f $PsExe, (Join-Path $KodKok 'paralel.ps1'), $gid, $kim, $emir
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg -WindowStyle Hidden -PassThru
        # Hat kendi kaydını yazana kadar panel "başlıyor" göstersin (paralel.ps1 aynı dosyayı günceller)
        $kl = Join-Path $YolDurum 'paralel'
        if (-not [IO.Directory]::Exists($kl)) { [void][IO.Directory]::CreateDirectory($kl) }
        $kf = Join-Path $kl "$gid.json"
        if (-not [IO.File]::Exists($kf)) {
            $on = [ordered]@{ pid = $p.Id; gorev = $gid; kim = $kim; emir = $emir; baslangic = (Get-Date).ToString('o'); zaman = (Get-Date).ToString('o'); durum = 'başlıyor'; adim = ''; asama = ''; adim_sayisi = 0 }
            try { [IO.File]::WriteAllText($kf, ($on | ConvertTo-Json -Compress), $Utf8) } catch {}
        }
        Ofis-Kayit "Paralel hat başlatıldı: $gid, $kim ($emir), PID $($p.Id)"
        $r.cikti = ([string]$r.cikti -replace '(?m)^PARALEL: .*$', 'Paralel hat başladı: iş ana sırayı beklemeden ilerliyor.').Trim()
        $r['paralel'] = $true
    }
    return $r
}
# ---------------------------------------------------------------- yönetim (CTO; yonetim.ps1 > durum\yonetim\)
function Yonetim-Ozeti($Ayar, [bool]$Calisiyor) {
    $kl = Join-Path $YolDurum 'yonetim'
    $son = $null; if ([IO.Directory]::Exists($kl)) { $son = Json-Oku (Join-Path $kl 'son.json') }
    $y = $null; if ($Ayar) { $y = Ozellik $Ayar 'yonetim' }
    $etkin = [bool]($Ayar -and $Ayar.roller -and (Ozellik $Ayar.roller 'cto') -and -not ($y -and $y.etkin -eq $false))
    return [ordered]@{
        etkin = $etkin; aralik_saat = $(if ($y -and $y.aralik_saat) { [int]$y.aralik_saat } else { 24 }); calisiyor = $Calisiyor
        istek = [IO.File]::Exists((Join-Path $kl 'istek'))
        zaman = (Ozellik $son 'zaman'); durum = (Ozellik $son 'durum'); ozet = (Ozellik $son 'ozet'); hata = (Ozellik $son 'hata')
        oneriler = @(Ozellik $son 'oneriler' | Where-Object { $_ }); ilke_sayisi = [int](Ozellik $son 'ilke_sayisi')
        oncelik_degisiklikleri = @(Ozellik $son 'oncelik_degisiklikleri' | Where-Object { $_ })
    }
}
function Yonetim-Bilgisi {
    $kl = Join-Path $YolDurum 'yonetim'
    $rapor = ''; $ad = ''; $ilkeler = ''; $sayi = 0
    if ([IO.Directory]::Exists($kl)) {
        $ilkeler = Metin-Oku (Join-Path $kl 'ekip-ilkeleri.md') 20000
        $raporlar = @([IO.Directory]::GetFiles($kl, 'degerlendirme-*.md') | Sort-Object -Descending)
        $sayi = $raporlar.Count
        if ($sayi) { $ad = [IO.Path]::GetFileName($raporlar[0]); $rapor = Metin-Oku $raporlar[0] 100000 }
    }
    return [ordered]@{ rapor_md = $rapor; rapor_adi = $ad; rapor_sayisi = $sayi; ilkeler_md = $ilkeler }
}
function Eylem-YonetimIste {
    $kl = Join-Path $YolDurum 'yonetim'
    if (-not [IO.Directory]::Exists($kl)) { [void][IO.Directory]::CreateDirectory($kl) }
    [IO.File]::WriteAllText((Join-Path $kl 'istek'), ("Panelden {0}ʼde istendi.`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm')), $Utf8)
    Ofis-Kayit 'CTO değerlendirmesi istendi.'
    return [ordered]@{ basarili = $true; cikti = 'CTO değerlendirmesi istendi: ofis boşalınca (sırada iş yokken) birkaç dakika içinde yapılır.'; hata = '' }
}
function Eylem-ParalelDurdur($Veri) {
    $id = Metin-Alani $Veri 'id' 80 -Zorunlu
    [void](Gorev-Klasoru-Bul $id)
    return (Betik-Calistir 'durum.ps1' ('-ParalelDurdur ' + (Ps-Tirnak $id)))
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

# ---------------------------------------------------------------- karakter kartı (/api/karakter?rol=)
$script:RolIstemleri = @{
    lider = @('yonetici-yonlendirme.md', 'lider-plan.md', 'lider-kabul.md', 'lider-uzman-plan.md', 'lider-uzman-kabul.md', 'lider-altyapi-plan.md', 'lider-altyapi-kabul.md', 'yonetici-yardim.md')
    'sorun-giderici' = @('sorun-giderici.md', 'sorun-kategori.md'); gelistirici = @('gelistirici.md'); denetci = @('denetci.md')
    sistem = @('altyapi-uygulama.md', 'altyapi-dogrulama.md'); ag = @('altyapi-uygulama.md', 'altyapi-dogrulama.md')
    tester = @('qa-test.md', 'tester-inceleme.md', 'uzman-calisma.md'); ik = @('ik-ise-alim.md')
    urun = @('urun-analiz.md'); kasif = @('kasif-kesif.md'); frontend = @('gelistirici.md'); backend = @('gelistirici.md'); cto = @('cto-degerlendirme.md')
    danisman = @('danisman-gorev.md', 'danisman-claude.md'); iletisim = @('iletisim-gonder.md', 'iletisim-rapor.md', 'uzman-calisma.md')
    fikirci = @('fikirci.md'); elestirmen = @('elestirmen.md'); planlamaci = @('planlamaci.md'); maliyet = @('maliyet.md')
    'karar-verici' = @('karar-verici.md', 'teslim.md'); puanlayici = @('puanlayici.md')
}
$script:RolAdimlari = @{
    lider = @('İş ver yönlendirmesi', 'Plan ve iş dağılımı', 'Kabul / ret', 'Ekip içi yardım kararı'); 'sorun-giderici' = @('Takılan işi inceleme', 'Kök neden kategorisi')
    gelistirici = @('Geliştirme (tek başına ya da bir parça)'); denetci = @('Kod ve güvenlik denetimi (onay kapısı)'); sistem = @('Sunucu / kurulum uygulama', 'Doğrulama'); ag = @('Ağ uygulama', 'Doğrulama')
    tester = @('Yazılım işinde test (birim / entegrasyon)', 'Ek inceleme (test)', 'Uzman işi inceleme', 'Test işi'); ik = @('İşe alım')
    urun = @('Gereksinim analizi (kabul ölçütleri)'); kasif = @('Kod tabanı keşfi'); frontend = @('Önyüz geliştirme parçası'); backend = @('Arka uç geliştirme parçası')
    cto = @('Yönetim değerlendirmesi (ofis boştayken)', 'Ekip ilkeleri', 'Önceliklendirme', 'İş önerisi')
    danisman = @('Tek parça iş: terminal ajanı (Claude Code / Codex / Gemini, masadaki kural dosyası)', 'Sonucu ve özeti ofise / sohbete raporlama')
    iletisim = @('Katlar arası iletişim: başka kata brif (KARAR: KAT)', 'Başka kattan dönen sonucu ekibe raporlama', 'Uzman işi (yazışma, rapor, bildirim)')
    fikirci = @('1 · Fikir'); elestirmen = @('2 · Eleştiri'); planlamaci = @('3 · POC planı'); maliyet = @('4 · Maliyet')
    'karar-verici' = @('5 · Karar (ONAYLA / REVIZE / REDDET)', 'Teslim paketi (ana kat)'); puanlayici = @('6 · Puan (1-10)')
}
function Karakter-Bilgisi([string]$Rol) {
    $Rol = Sohbet-Rolu $Rol
    $uye = Kadro-Bul (Kadro-Listesi) $Rol
    $istemler = New-Object Collections.Generic.List[object]
    $talimatYolu = [string](Ozellik $uye 'istem')
    if ($talimatYolu -and $talimatYolu -match '^istemler\\kadro\\[a-z0-9-]+\.md$') { $istemler.Add([ordered]@{ ad = ($talimatYolu -replace '\\', '/'); tur = 'rol talimatı' }) }
    $adimIstemleri = @(); if ($RolIstemleri.ContainsKey($Rol)) { $adimIstemleri = $RolIstemleri[$Rol] } elseif ([bool](Ozellik $uye 'uzman_isi')) { $adimIstemleri = @('uzman-calisma.md', 'uzman-inceleme.md', 'ek-inceleme.md') }
    foreach ($a in $adimIstemleri) { $istemler.Add([ordered]@{ ad = "istemler/$a"; tur = 'adım istemi' }) }
    $talimat = ''; if ($istemler.Count -and $istemler[0].tur -eq 'rol talimatı') { $talimat = Metin-Oku (Kok-Dosyasi-P ($istemler[0].ad -replace '/', '\')) 30000 }
    # İstatistik (son 30 gün)
    $st = [ordered]@{ cagri = 0; basarisiz = 0; toplam = [long]0; sure_sn = [long]0; tepe_yuzde = $null; ort_yuzde = $null; modeller = [ordered]@{}; adimlar = [ordered]@{}; son = $null; gun = 30 }
    $yt = 0.0; $ya = 0
    foreach ($r in (Kullanim-Kayitlari ((Get-Date).Date.AddDays(-29)))) {
        if ([string]$r['rol'] -ne $Rol) { continue }
        $st.cagri++; if (-not [bool]$r['basarili']) { $st.basarisiz++ }
        $st.toplam += (Sayi-Al $r 'toplam'); $st.sure_sn += (Sayi-Al $r 'sure_sn')
        $p = Sayi-Al $r 'baglam_pencere'; $t = Sayi-Al $r 'baglam_tepe'
        if ($p -gt 0 -and $t -gt 0) { $y = [Math]::Round(100.0 * $t / $p, 1); $yt += $y; $ya++; if ($null -eq $st.tepe_yuzde -or $y -gt $st.tepe_yuzde) { $st.tepe_yuzde = $y } }
        $m = [string]$r['model_gercek']; if (-not $m) { $m = '{0}/{1}' -f $r['arac'], $r['model'] }
        $st.modeller[$m] = [int]$st.modeller[$m] + 1
        $e = [string]$r['etiket']; if ($e -like 'sohbet*') { $e = 'sohbet' }; if ($e -like 'inceleme-*') { $e = 'ek inceleme' }; if ($e -like 'birlikte-*') { $e = 'birlikte çalışma' }
        $st.adimlar[$e] = [int]$st.adimlar[$e] + 1
        $st.son = $r['_z'].ToString('o')
    }
    if ($ya) { $st.ort_yuzde = [Math]::Round($yt / $ya, 1) }
    # Katıldığı işler
    $isler = New-Object Collections.Generic.List[object]
    $yardimIstedi = 0; $yardimEtti = 0
    $tumGorevler = Gorevleri-Oku   # liste tek nesne olarak döner; değişkenden borulayınca öğelerine açılır
    foreach ($g in @($tumGorevler | Sort-Object { [string](Ozellik $_ 'guncelleme') } -Descending)) {
        $birlikte = @(Ozellik $g 'birlikte' | Where-Object { $_ -and [string]$_.rol -eq $Rol }).Count
        $yardimEtti += $birlikte
        $katildi = ($birlikte -gt 0) -or ([string](Ozellik $g $Rol) -match '/') -or [bool](@('sorumlu', 'inceleyen', 'destek', 'hedef_rol', 'istenen_sorumlu') | Where-Object { [string](Ozellik $g $_) -eq $Rol })
        if ([string](Ozellik $g 'yardim_isteyen') -eq $Rol) { $yardimIstedi++ }
        if ((Ozellik $g 'ana_gorev') -and ([string](Ozellik $g 'hedef_rol') -eq $Rol -or [string](Ozellik $g 'istenen_sorumlu') -eq $Rol)) { $yardimEtti++ }
        if ($katildi -and $isler.Count -lt 12) { $isler.Add([ordered]@{ id = $g.id; baslik = $g.baslik; asama = [string]$g.asama; asama_adi = (Asama-Adi-Bul $g); tip = (Gorev-Tipi $g); guncelleme = (Ozellik $g 'guncelleme') }) }
    }
    $adimlar = @(); if ($RolAdimlari.ContainsKey($Rol)) { $adimlar = $RolAdimlari[$Rol] } elseif ([bool](Ozellik $uye 'uzman_isi')) { $adimlar = @('Uzman işi (sorumlu)', 'İnceleyen', 'Ek inceleme') }
    return [ordered]@{
        anahtar = $Rol; ad = [string]$uye.ad; rol_tr = [string](Ozellik $uye 'rol_tr'); departman = [string](Ozellik $uye 'departman')
        yetki = [string](Ozellik $uye 'yetki'); uzmanlik = [string](Ozellik $uye 'uzmanlik'); uzman_isi = [bool](Ozellik $uye 'uzman_isi'); dogrudan_is = [bool](Ozellik $uye 'dogrudan_is'); yerlesik = [bool](Ozellik $uye 'yerlesik')
        tanisma = [string](Ozellik $uye 'tanisma'); ise_alan = [string](Ozellik $uye 'ise_alan'); ise_alinma = [string](Ozellik $uye 'ise_alinma')
        faaliyet_metni = [string](Ozellik $uye 'faaliyet_metni'); kadro_zinciri = @(Ozellik $uye 'araclar' | Where-Object { $_ })
        adimlar = $adimlar; istemler = $istemler; talimat = $talimat; istatistik = $st; isler = $isler; yardim_istedi = $yardimIstedi; yardim_etti = $yardimEtti
    }
}

# ---------------------------------------------------------------- model zinciri (panelden seçilir; ayarlar.json > roller)
function Roller-Blogu-Metni($Roller) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("{`r`n")
    $adlar = @($Roller.PSObject.Properties | ForEach-Object { $_.Name })
    for ($i = 0; $i -lt $adlar.Count; $i++) {
        $ad = $adlar[$i]
        [void]$sb.Append(('    "{0}": [' -f $ad) + "`r`n")
        $girisler = @($Roller.$ad | Where-Object { $_ })
        for ($j = 0; $j -lt $girisler.Count; $j++) {
            $g = $girisler[$j]
            $ek = ''; if ($g.efor) { $ek = ', "efor": "{0}"' -f $g.efor }
            [void]$sb.Append(('      {{ "arac": "{0}", "model": "{1}"{2} }}' -f $g.arac, $g.model, $ek) + $(if ($j -lt $girisler.Count - 1) { ',' } else { '' }) + "`r`n")
        }
        [void]$sb.Append('    ]' + $(if ($i -lt $adlar.Count - 1) { ',' } else { '' }) + "`r`n")
    }
    [void]$sb.Append('  }')
    return $sb.ToString()
}
function Roller-Blogu-Degistir([string]$Metin, [string]$Blok) {
    $m = [regex]::Match($Metin, '"roller"\s*:\s*\{')
    if (-not $m.Success) { throw 'HTTP:500:ayarlar.json içinde "roller" bulunamadı' }
    $bas = $m.Index + $m.Length - 1
    $derinlik = 0; $tirnak = $false; $son = -1
    for ($i = $bas; $i -lt $Metin.Length; $i++) {
        $c = $Metin[$i]
        if ($tirnak) { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $tirnak = $false }; continue }
        if ($c -eq '"') { $tirnak = $true } elseif ($c -eq '{') { $derinlik++ } elseif ($c -eq '}') { $derinlik--; if ($derinlik -eq 0) { $son = $i; break } }
    }
    if ($son -lt 0) { throw 'HTTP:500:ayarlar.json "roller" bloğu kapanmıyor' }
    return $Metin.Substring(0, $bas) + $Blok + $Metin.Substring($son + 1)
}
function Eylem-ModelZinciri($Veri) {
    $rol = Sohbet-Rolu (Metin-Alani $Veri 'rol' 40 -Zorunlu)
    # Kişisel ayarlar ayarlar.yerel.json'dadır (yoksa şablon okunur); kayıt her zaman yerel dosyaya yazılır, şablon değişmez
    $sablon = Join-Path $Kok 'ayarlar.json'
    $yol = Yapilandirma-Yolu $sablon
    $metin = Metin-Oku $yol
    $ayar = $metin | ConvertFrom-Json
    $uye = Kadro-Bul (Kadro-Listesi) $rol
    $kat = $ayar.model_katalogu
    if ([bool](Ozellik $Veri 'sifirla')) {
        if (-not (Ozellik $uye 'araclar')) { throw 'HTTP:400:Bu rolün kadroda varsayılan zinciri yok; sıfırlanamaz' }
        $ayar.roller.PSObject.Properties.Remove($rol)
        $ozet = 'kadro varsayılanı'
    } else {
        $liste = @()
        $gorulen = @{}
        foreach ($x in @(Ozellik $Veri 'zincir')) {
            if (-not $x) { continue }
            $arac = ([string](Ozellik $x 'arac')).Trim().ToLowerInvariant()
            $model = ([string](Ozellik $x 'model')).Trim()
            if (@('claude', 'codex', 'gemini') -notcontains $arac) { throw "HTTP:400:Bilinmeyen araç: $arac" }
            if ($model -notmatch '^[A-Za-z0-9._-]{1,60}$') { throw "HTTP:400:Geçersiz model adı: $model" }
            $katListe = @(); if ($kat -and $kat.PSObject.Properties[$arac]) { $katListe = @($kat.$arac | ForEach-Object { [string]$_.model }) }
            if ($katListe.Count -and $katListe -notcontains $model) { throw "HTTP:400:$arac/$model model kataloğunda yok (ayarlar.json > model_katalogu)" }
            $k = "$arac/$model"; if ($gorulen.ContainsKey($k)) { continue }; $gorulen[$k] = $true
            $o = [ordered]@{ arac = $arac; model = $model }
            if ($arac -eq 'codex') { $e = ([string](Ozellik $x 'efor')).Trim().ToLowerInvariant(); if (@('low', 'medium', 'high', 'xhigh') -notcontains $e) { $e = 'high' }; $o.efor = $e }
            $liste += [pscustomobject]$o
        }
        if ($liste.Count -lt 1 -or $liste.Count -gt 6) { throw 'HTTP:400:Zincirde 1 ile 6 arasında model olmalı' }
        if ($ayar.roller.PSObject.Properties[$rol]) { $ayar.roller.$rol = $liste } else { $ayar.roller | Add-Member -NotePropertyName $rol -NotePropertyValue $liste }
        $ozet = ($liste | ForEach-Object { '{0}/{1}' -f $_.arac, $_.model }) -join ' > '
    }
    $yeni = Roller-Blogu-Degistir $metin (Roller-Blogu-Metni $ayar.roller)
    $kontrol = $yeni | ConvertFrom-Json   # bozuk JSON yazma
    if (-not $kontrol.roller) { throw 'HTTP:500:Yeni ayarlar doğrulanamadı' }
    $hedef = Yapilandirma-Yolu $sablon -Yaz
    $tmp = "$hedef.tmp"
    [IO.File]::WriteAllText($tmp, $yeni, $Utf8)
    if ([IO.File]::Exists($hedef)) { [IO.File]::Replace($tmp, $hedef, "$hedef.bak") } else { [IO.File]::Move($tmp, $hedef) }
    Ofis-Kayit "Model zinciri değişti: $rol -> $ozet"
    return [ordered]@{ basarili = $true; cikti = "Kaydedildi: $ozet. Ekip bir sonraki adımda bu sırayı kullanır."; hata = '' }
}

# ---------------------------------------------------------------- arka plan: kod, istemler, ayarlar (salt okunur; /api/kaynak)
function Kaynak-Listesi {
    $gruplar = @(
        @('Döngü betikleri', '*.ps1', ''), @('Panel', '*.ps1', 'ofis'), @('Panel', 'panel.html', 'ofis'),
        @('Adım istemleri', '*.md', 'istemler'), @('Rol talimatları (yetenekler)', '*.md', 'istemler\kadro'),
        @('Ayarlar', 'ayarlar.json', ''), @('Ayarlar', 'ayarlar.yerel.json', ''), @('Ayarlar', 'kadro.json', ''), @('Ayarlar', 'kadro.yerel.json', ''),
        @('Ayarlar', 'projeler.json', ''), @('Ayarlar', 'projeler.yerel.json', ''),
        @('Araçlar', '*.ps1', 'araclar'), @('Araçlar', '*.py', 'araclar'), @('Testler', '*.ps1', 'testler'), @('Outsource Consultant masası', '*.md', 'danisman'), @('Belgeler', 'README.md', ''),
        @('Şirket binası', 'katlar.json', ''), @('Panel', 'bina.html', 'ofis')
    )
    # Alt katta: ayarlar / kadro / projeler katın kendi dosyaları; katın istem ve bilgi dosyaları ayrı grup (yol öneki @kat/)
    $katGruplari = @()
    if ($Kok -ne $KodKok) {
        $gruplar = @($gruplar | Where-Object { $_[0] -ne 'Ayarlar' })
        $katGruplari = @(@('Kat ayarları', 'ayarlar.json', ''), @('Kat ayarları', 'ayarlar.yerel.json', ''), @('Kat ayarları', 'kadro.json', ''), @('Kat ayarları', 'kadro.yerel.json', ''),
            @('Kat ayarları', 'projeler.json', ''), @('Kat ayarları', 'projeler.yerel.json', ''),
            @('Kat istemleri', '*.md', 'istemler'), @('Kat istemleri', '*.md', 'istemler\kadro'), @('Kat bilgisi', '*.md', 'bilgi'))
    }
    $l = New-Object Collections.Generic.List[object]
    foreach ($kume in @(@{ kok = $KodKok; onek = ''; liste = $gruplar }, @{ kok = $Kok; onek = '@kat/'; liste = $katGruplari })) {
        foreach ($g in $kume.liste) {
            $kl = $kume.kok; if ($g[2]) { $kl = Join-Path $kume.kok $g[2] }
            if (-not [IO.Directory]::Exists($kl)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $kl -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $g[1] } | Sort-Object Name)) {
                $l.Add([ordered]@{ grup = $g[0]; yol = ($kume.onek + ($f.FullName.Substring($kume.kok.Length + 1) -replace '\\', '/')); boyut = $f.Length; zaman = $f.LastWriteTime.ToString('o') })
            }
        }
    }
    return , $l
}
function Kaynak-Oku([string]$Yol) {
    $liste = Kaynak-Listesi
    $k = $null; foreach ($x in $liste) { if ($x.yol -ceq $Yol) { $k = $x; break } }
    if (-not $k) { throw 'HTTP:404:Bu dosya listede yok' }
    $taban = $KodKok; $goreli = $Yol
    if ($Yol.StartsWith('@kat/')) { $taban = $Kok; $goreli = $Yol.Substring(5) }
    $metin = Metin-Oku (Join-Path $taban ($goreli -replace '/', '\')) 800000
    if ($goreli -like 'ayarlar*.json') {
        # Gizli değerler panelde gösterilmez
        $metin = [regex]::Replace($metin, '("(ntfy_konu|parola|sifre|password|token|api_key|anahtar)"\s*:\s*")[^"]*(")', '$1***$3')
    }
    return $metin
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
# Bina kabuğu (/): solda kat seçici, sağda seçilen katın paneli (aynı sunucudan /kat/<id>/) ya da uygulama katının kendi paneli
function Bina-Gonder($Akis) {
    $html = Metin-Oku (Join-Path $OfisKok 'bina.html')
    if (-not $html) { Panel-Gonder $Akis 'ana'; return }
    $nonce = [Guid]::NewGuid().ToString('N')
    $html = $html.Replace('__OFIS_ANAHTARI__', $Anahtar).Replace('__NONCE__', $nonce)
    # Uygulama katlarının panelleri yalnız bu bilgisayardan (yerel adres) çerçevelenebilir
    $kaynaklar = @("'self'")
    if (-not $script:IstekUzak) { foreach ($k in (Katlar-Listesi)) { if ([string]$k.tur -eq 'uygulama' -and [string]$k.uygulama.adres -match '^(https?://(127\.0\.0\.1|localhost)(:\d{1,5})?)(/|$)') { $kaynaklar += $Matches[1] } } }
    $csp = "default-src 'none'; script-src 'nonce-$nonce'; style-src 'unsafe-inline'; img-src 'self' data:; frame-src $($kaynaklar -join ' '); connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    Yanit-Gonder $Akis 200 'text/html; charset=utf-8' ($Utf8.GetBytes($html)) @{ 'Content-Security-Policy' = $csp }
}
function Panel-Gonder($Akis, [string]$KatId = 'ana') {
    $k = Kat-Bul-P $KatId
    if (-not $k -or -not (Kat-Ekip-mi $k)) { Yanit-Metin $Akis 404 'Bulunamadı'; return }
    # Katın kendi paneli olabilir (katlar.json > panel, ofis\ altında; ör. Creativity Office'in stüdyo paneli)
    $dosya = $PanelDosyasi
    $ozel = [string]$k.panel
    if ($ozel -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.html$' -and [IO.File]::Exists((Join-Path $OfisKok $ozel))) { $dosya = Join-Path $OfisKok $ozel }
    $html = Metin-Oku $dosya
    if (-not $html) { Yanit-Metin $Akis 500 'panel.html bulunamadı'; return }
    $nonce = [Guid]::NewGuid().ToString('N')
    $html = $html.Replace('__OFIS_ANAHTARI__', $Anahtar).Replace('__ONIZLEME_ANAHTARI__', $OnizlemeAnahtari).Replace('__NONCE__', $nonce).Replace('__OFIS_KATI__', $KatId)
    $csp = "default-src 'none'; script-src 'nonce-$nonce'; style-src 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self'; frame-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    $csp = $csp -replace "frame-ancestors 'none'", "frame-ancestors 'self'"   # bina kabuğunun çerçevesinde açılır
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
        $script:IstekUzak = [bool](($UzakHostlar -contains $hostBasligi) -or $tsKim)
        $yol = [string]$I.yol
        $yontem = [string]$I.yontem
        if ($yontem -eq 'GET' -and ($yol -eq '/' -or $yol -eq '/index.html')) { Bina-Gonder $Akis; return }
        if ($yontem -eq 'GET' -and $yol -match '^/kat/([a-z0-9][a-z0-9-]{0,30})/?$') { Panel-Gonder $Akis $Matches[1]; return }
        if ($yontem -eq 'GET' -and $yol -eq '/manifest.webmanifest') { Manifest-Gonder $Akis; return }
        if ($yontem -eq 'GET' -and $yol -match '^/simge-(180|192|512)\.png$') { Simge-Gonder $Akis $Matches[1]; return }
        if ($yontem -eq 'GET' -and $yol.StartsWith('/onizle/')) { Onizleme-Gonder $Akis $yol; return }
        if (-not $yol.StartsWith('/api/')) { Yanit-Metin $Akis 404 'Bulunamadı'; return }

        if ([string]$I.basliklar['x-ofis-anahtar'] -cne $Anahtar) { Yanit-Json $Akis 401 @{ hata = 'Oturum anahtarı geçersiz; sayfayı yenile.' }; return }
        $koken = [string]$I.basliklar['origin']
        if ($koken -and $IzinliKokenler -notcontains $koken.ToLowerInvariant()) { Yanit-Json $Akis 403 @{ hata = 'Bu kaynaktan istek kabul edilmiyor.' }; return }
        $sfs = [string]$I.basliklar['sec-fetch-site']
        if ($sfs -and $sfs -ne 'same-origin' -and $sfs -ne 'none') { Yanit-Json $Akis 403 @{ hata = 'Siteler arası istek kabul edilmiyor.' }; return }
        # Şirket binası: istek hangi katın paneli için (kat panelleri X-Ofis-Kat başlığı gönderir; yoksa ana kat)
        $katIstek = [string]$I.basliklar['x-ofis-kat']; if (-not $katIstek) { $katIstek = [string]$I.sorgu['kat'] }
        Kat-Sec $katIstek
        if ($yol -eq '/api/katlar') { Yanit-Json $Akis 200 (Katlar-Bilgisi); return }
        if ($yol -eq '/api/yazismalar') { Yanit-Json $Akis 200 ([ordered]@{ yazismalar = (Yazisma-Listesi ([string]$I.sorgu['filtre']) 60) }); return }
        if ($yol -eq '/api/yazisma') { Yanit-Json $Akis 200 (Yazisma-Ayrinti ([string]$I.sorgu['id'])); return }
        if (-not (Kat-Ekip-mi $AktifKat) -and $yol -notmatch '^/api/kat-(ac|kapat)$') { Yanit-Json $Akis 400 @{ hata = 'Bu kat bir uygulama katı; kendi paneli kullanılır.' }; return }

        if ($yontem -eq 'GET') {
            switch ($yol) {
                '/api/durum' { Yanit-Json $Akis 200 (Durum-Uret); return }
                '/api/gorev' { Yanit-Json $Akis 200 (Gorev-Ayrinti ([string]$I.sorgu['id'])); return }
                '/api/dosya' { Yanit-Metin $Akis 200 (Gorev-Dosyasi-Oku ([string]$I.sorgu['id']) ([string]$I.sorgu['yol'])); return }
                '/api/diff' { Yanit-Metin $Akis 200 (Diff-Uret ([string]$I.sorgu['id'])); return }
                '/api/sohbet' { Yanit-Json $Akis 200 (Sohbet-Oku ([string]$I.sorgu['rol'])); return }
                '/api/kullanim' { $gn = 7; [void][int]::TryParse([string]$I.sorgu['gun'], [ref]$gn); Yanit-Json $Akis 200 (Kullanim-Ozeti $gn); return }
                '/api/karakter' { Yanit-Json $Akis 200 (Karakter-Bilgisi ([string]$I.sorgu['rol'])); return }
                '/api/yonetim' { Yanit-Json $Akis 200 (Yonetim-Bilgisi); return }
                '/api/kaynak' {
                    $ky = [string]$I.sorgu['yol']
                    if ($ky) { Yanit-Metin $Akis 200 (Kaynak-Oku $ky) } else { Yanit-Json $Akis 200 ([ordered]@{ kok = $KodKok; kat_kok = $Kok; dosyalar = (Kaynak-Listesi) }) }
                    return
                }
            }
            Yanit-Json $Akis 404 @{ hata = 'Bulunamadı' }; return
        }
        if ($yontem -eq 'POST') {
            if (-not ([string]$I.basliklar['content-type']).StartsWith('application/json')) { Yanit-Json $Akis 400 @{ hata = 'JSON bekleniyor' }; return }
            $v = Govde-Coz $I.govde
            $r = $null
            switch ($yol) {
                '/api/is-ver' { $r = Eylem-IsVer $v }
                '/api/model-zinciri' { $r = Eylem-ModelZinciri $v }
                '/api/gorev-ekle' { $r = Eylem-GorevEkle $v }
                '/api/talep-ekle' { $r = Eylem-TalepEkle $v }
                '/api/uzman-ekle' { $r = Eylem-UzmanEkle $v }
                '/api/duraklat' { $r = Betik-Calistir 'durum.ps1' '-Duraklat' }
                '/api/surdur' {
                    $r = Betik-Calistir 'durum.ps1' '-Surdur'
                    # Alt katların döngüsü kapalıyken çıkar: sürdürünce döngü yoksa başlat
                    if ($r.basarili -and $AktifKatId -ne 'ana' -and -not (Kat-Kapali-P $Kok) -and -not (Kat-Dongusu-Calisiyor-P $AktifKatId)) { Kat-Dongusu-Baslat-P $AktifKatId }
                }
                '/api/ofis-kapat' { if ($AktifKatId -eq 'ana') { $r = Eylem-OfisKapat } else { $r = Eylem-KatKapat ([pscustomobject]@{ kat = $AktifKatId }) } }
                '/api/ofis-ac' { $r = Eylem-KatAc ([pscustomobject]@{ kat = $AktifKatId }) }
                '/api/kat-ac' { $r = Eylem-KatAc $v }
                '/api/kat-kapat' { $r = Eylem-KatKapat $v }
                '/api/konu-ekle' { $r = Eylem-KonuEkle $v }
                '/api/geri-al' { $gid = Metin-Alani $v 'id' 80 -Zorunlu; if ($gid -notmatch '^\d{4}(-[A-Za-z0-9-]{1,60})?$') { throw 'HTTP:400:Geçersiz görev' }; $r = Betik-Calistir 'durum.ps1' "-GeriAl $gid" }
                '/api/canliya-al' { $gid = Metin-Alani $v 'id' 80 -Zorunlu; if ($gid -notmatch '^\d{4}(-[A-Za-z0-9-]{1,60})?$') { throw 'HTTP:400:Geçersiz görev' }; $r = Betik-Calistir 'durum.ps1' "-CanliyaAl $gid" }
                '/api/sohbet' { $r = Eylem-Sohbet $v }
                '/api/sohbet-temizle' { $r = Eylem-SohbetTemizle $v }
                '/api/devam' { $r = Eylem-Devam $v }
                '/api/iptal' { $r = Eylem-Iptal $v }
                '/api/tasi' { $r = Eylem-Tasi $v }
                '/api/komut' { $r = Eylem-Komut $v }
                '/api/paralel-durdur' { $r = Eylem-ParalelDurdur $v }
                '/api/yonetim-iste' { $r = Eylem-YonetimIste }
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
    $ek = ''; if ($AcilacakKat) { $ek = "#kat=$AcilacakKat" }
    try { Start-Process "http://127.0.0.1:$P/$ek" } catch { Ofis-Kayit "Tarayıcı açılamadı: $($_.Exception.Message)" 'UYARI' }
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
            try { Bina-Bekcisi-P } catch {}
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
