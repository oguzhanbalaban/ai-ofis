<#
komut.ps1 - Kullanıcının çalışanlara doğrudan komutu ve paralel çalışma hatları. ekip.ps1 dot-source eder.

Panelde karakter kartından ya da görev ayrıntısından (durum.ps1 -Komut <no> -Kim <anahtar> -Emir devam|devral [-Not "..."]):
  devam    İş hemen ilerler: ana döngünün sırasını beklemeden ayrı bir süreçte (paralel.ps1) yürür; adımları her zamanki
           sahipleri yapar. Takılan, soru bekleyen ya da yardım bekleyen iş önce sürdürülür (Gorev-Surdur).
  devral   Komut verilen çalışan bu işte şu anki adımın sahibinin (ör. Full-Stack Developer) rolünü üstlenir: görevde
           devralan = { <rol>: <çalışan> }; Ajan-Cagir o rolün çağrılarında devralanın model zincirini kullanır ve istemine
           devralma notu ekler. İş de hemen ilerler. Rolün asıl sahibi "Devral" derse rol kendisine döner.
  Not      İsteğe bağlı talimat gorevler\<no>\kullanici-talimatlari.md dosyasına eklenir; bu işteki her ajan isteminde yer alır.

Paralel hat sayısı ayarlar.json > paralel.en_fazla (varsayılan 2), hat başına adım sınırı paralel.adim_siniri. Hatlar doluysa
ya da paralel çalışma kapalıysa komut kaydedilir ve iş ana döngünün sırasında öne alınır (one_al). Aynı işi iki süreç aynı anda
yürütmez (ortak.ps1 > görev kilidi); iş o an yürütülüyorsa devralma bir sonraki adımdan geçerli olur.
Hattın durumu durum\paralel\<no>.json (panel okur); hattı durdurmak için gorevler\<no>\paralel-durdur (durum.ps1 -ParalelDurdur).
#>
$script:YolParalel = Join-Path $YolDurum 'paralel'
$script:KomutEmirleri = @('devam', 'devral')
$script:ParalelBilgi = $null

function Paralel-Ayari {
    $p = $Ayar.paralel
    $etkin = $true; $enFazla = 2; $adim = 12
    if ($p) {
        if ($null -ne $p.etkin) { $etkin = [bool]$p.etkin }
        if ($p.en_fazla) { $enFazla = [Math]::Max(1, [int]$p.en_fazla) }
        if ($p.adim_siniri) { $adim = [Math]::Max(1, [int]$p.adim_siniri) }
    }
    return [pscustomobject]@{ etkin = $etkin; en_fazla = $enFazla; adim_siniri = $adim }
}
function Paralel-Kayit-Yolu([string]$Id) { Join-Path $YolParalel "$Id.json" }
function Paralel-Durdur-Dosyasi([string]$Id) { Join-Path (Gorev-Klasoru $Id) 'paralel-durdur' }
function Paralel-Kaydi-Sil([string]$Id) {
    $y = Paralel-Kayit-Yolu $Id
    foreach ($f in @($y, "$y.bak")) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
}
# Süren paralel hatlar; süreci ölmüş kayıtlar (20 sn'den eski) silinir
function Paralel-Hatlari {
    $l = @()
    if (-not (Test-Path -LiteralPath $YolParalel)) { return $l }
    foreach ($f in @(Get-ChildItem -LiteralPath $YolParalel -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $h = Json-Oku $f.FullName
        if (-not $h) { continue }
        $canli = $false
        if ([int]$h.pid -gt 0) { $canli = [bool](Get-Process -Id ([int]$h.pid) -ErrorAction SilentlyContinue) }
        if (-not $canli -and $h.zaman) { try { $canli = (((Get-Date) - [datetime][string]$h.zaman).TotalSeconds -lt 20) } catch {} }
        if ($canli) { $l += $h } else { Paralel-Kaydi-Sil ([string]$h.gorev) }
    }
    return $l
}
# paralel.ps1 içinde Kalp bunu çağırır: döngünün kalp.json dosyasına (bekçi izler) değil, hattın kendi kaydına yazar
function Paralel-Kalp([string]$Durum) {
    $b = $script:ParalelBilgi
    if (-not $b) { return }
    try {
        $b.zaman = (Simdi); $b.durum = $Durum; $b.adim = [string]$script:AktifAdim
        if (-not (Test-Path -LiteralPath $YolParalel)) { New-Item -ItemType Directory -Force $YolParalel | Out-Null }
        Json-Yaz $b (Paralel-Kayit-Yolu ([string]$b.gorev))
    } catch {}
}
# Paralel hattı başlatır (görünmez pencerede paralel.ps1). Panel sunucusu kendi başlatır; bu, komut satırı (durum.ps1) içindir.
function Paralel-Baslat([string]$Id, [string]$Kim, [string]$Emir) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -Gorev {2} -Kim {3} -Komut {4}' -f $ps, (Join-Path $Kok 'paralel.ps1'), $Id, $Kim, $Emir
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList $arg -WindowStyle Hidden -PassThru
    return $p.Id
}
function Paralel-Durdur($G) {
    $h = $null
    foreach ($x in (Paralel-Hatlari)) { if ([string]$x.gorev -eq [string]$G.id) { $h = $x; break } }
    if (-not $h) { return "#$(No-Kisa $G.id) için süren paralel hat yok." }
    Metin-Yaz (Paralel-Durdur-Dosyasi $G.id) ("Kullanıcı {0} tarihinde durdurdu.`n" -f (Get-Date).ToString('dd.MM.yyyy HH:mm'))
    Gunluk "Görev $($G.id): paralel hattı durdurma isteği (PID $($h.pid))"
    return "#$(No-Kisa $G.id) paralel hattı durduruluyor: süren ajan sonlandırılır, iş bulunduğu aşamada ana sıraya döner."
}

# ---------------------------------------------------------------- adımın sahibi ve devralma
# İşin şu anki (ya da sıradaki ajan) adımını yürüten rol; betik adımları (yeni, kontrol, tamamla) sonraki ajan adımına sayılır
function Adim-Rolu($G) {
    $a = [string]$G.asama
    if ($a -eq 'takildi') { $a = [string]$G.takildi_asama }
    $tip = [string]$G.tip; if (-not $tip) { $tip = 'yazilim' }
    if ($a -eq 'analiz') { return 'urun' }   # Product Manager (planlama.ps1)
    if ($a -eq 'yardim' -or $tip -eq 'genel') { return 'lider' }
    if ($tip -eq 'altyapi') {
        $s = [string]$G.sorumlu; if ($s -ne 'ag') { $s = 'sistem' }
        $d = [string]$G.destek; if ($d -ne 'ag' -and $d -ne 'sistem') { $d = $s }
        if ($a -eq 'gelistirme') { return $s }
        if ($a -eq 'kontrol' -or $a -eq 'denetim') { return $d }
        return 'lider'
    }
    if ($tip -eq 'uzman') {
        $s = [string]$G.sorumlu
        $i = [string]$G.inceleyen; if ($i -eq 'yok') { $i = '' }
        if ($a -eq 'gelistirme' -and $s) { return $s }
        if (($a -eq 'kontrol' -or $a -eq 'denetim') -and $i) { return $i }
        return 'lider'
    }
    switch ($a) {
        'kesif'      { return 'kasif' }
        'gelistirme' {
            # Bölünmüş geliştirmede sıradaki parçanın geliştiricisi (Backend / Frontend Developer…)
            $p = $null; if (Get-Command Gelistirme-Sirasi -ErrorAction SilentlyContinue) { $p = Gelistirme-Sirasi $G }
            if ($p) { return [string]$p.rol }
            return 'gelistirici'
        }
        'kontrol'    { if ($G.qa_testi -eq $true) { return 'tester' }; return 'denetci' }
        'test'       { return 'tester' }
        'denetim'    { return 'denetci' }
        default      { return 'lider' }
    }
}
function Devralan($G, [string]$Rol) {
    $d = $G.devralan
    if ($d -and $Rol -and $d.PSObject.Properties[$Rol] -and [string]$d.$Rol) { return [string]$d.$Rol }
    return ''
}
function Adim-Sahibi($G) {
    $r = Adim-Rolu $G
    $k = Devralan $G $r
    if ($k) { return $k }
    return $r
}
# Gorev-Ilerlet her adımda kurar: Ajan-Cagir devralınan rolün çağrılarını devralanın zinciriyle yapar
function Rol-Degisimi-Kur($G) {
    $script:RolDegisimi = $null
    $d = $G.devralan
    if (-not $d) { return }
    $h = @{}
    foreach ($p in $d.PSObject.Properties) { if ([string]$p.Value -and [string]$p.Value -ne $p.Name) { $h[$p.Name] = [string]$p.Value } }
    if ($h.Count -eq 0) { return }
    Kadro-Rolleri-Yukle
    $script:RolDegisimi = $h
}
function Talimat-Ekle($G, [string]$Not, [string]$Kim, [string]$Emir) {
    $f = Join-Path (Gorev-Klasoru $G.id) 'kullanici-talimatlari.md'
    $ne = 'devam et'; if ($Emir -eq 'devral') { $ne = 'devral' }
    $baslik = '### {0} · {1} için ({2})' -f (Get-Date).ToString('dd.MM.yyyy HH:mm'), (Calisan-Adi $Kim), $ne
    $eski = (Metin-Oku $f).TrimEnd()
    $yeni = "$baslik`n`n$($Not.Trim())`n"
    if ($eski) { $yeni = "$eski`n`n$yeni" }
    Metin-Yaz $f $yeni
}

# Ana döngü (başka süreç) şu an bu iş üzerinde mi: kalp atışına bakar. Görev kilidinin kapsamadığı adımlar için (Incident Manager
# incelemesi, kök neden) ve döngü yeni sürüme geçerken eski kodun kilit almadığı son adım için.
function Dongu-Bu-Iste-mi([string]$Id) {
    $k = Json-Oku (Join-Path $YolDurum 'kalp.json')
    if (-not $k -or [string]$k.gorev -ne $Id -or [int]$k.pid -eq $PID) { return $false }
    if (@('boşta', 'durduruldu', 'mesai dışı', 'durdu', 'döngü', '') -contains [string]$k.durum) { return $false }
    $dk = 12.0; if ($Ayar.dongu -and $Ayar.dongu.bekci_dk) { $dk = [double]$Ayar.dongu.bekci_dk }
    try { if (((Get-Date) - [datetime][string]$k.zaman).TotalMinutes -gt $dk) { return $false } } catch { return $false }
    return [bool](Get-Process -Id ([int]$k.pid) -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- komut
# Döner: karar = paralel (hemen ayrı hatta başlat) | sira (ana sırada öne alındı) | surer (iş şu an yürütülüyor)
function Gorev-Komut-Ver($G, [string]$Kim, [string]$Emir = 'devam', [string]$Not = '') {
    if ($KomutEmirleri -notcontains $Emir) { throw "Bilinmeyen komut: $Emir (devam | devral)" }
    Kadro-Rolleri-Yukle
    $uye = Kadro-Uye $Kim
    if (-not $uye) { throw "Kadroda böyle bir çalışan yok: $Kim" }
    $kimAd = [string]$uye.ad
    if (-not @($Ayar.roller.$Kim | Where-Object { $_ }).Count) { throw "$kimAd için model zinciri yok; karakter kartından model seç" }
    $a = [string]$G.asama
    if ($a -eq 'tamam' -or $a -eq 'iptal') { throw "İş kapanmış ($(Asama-Adi $a)); yeniden açmak için panoda başka aşamaya taşı" }
    $kilit = Gorev-Kilidi-Al $G.id
    $mesgul = (-not $kilit) -or (Dongu-Bu-Iste-mi $G.id)
    $surduruldu = ''; $ozet = ''
    try {
        # Kilidi aldıktan (ya da alamadıktan) sonra en güncel kayıtla çalış
        $taze0 = Gorev-Diskten $G.id
        if ($taze0) { $G = $taze0; $a = [string]$G.asama }
        if ($a -eq 'tamam' -or $a -eq 'iptal') { throw "İş kapanmış ($(Asama-Adi $a))" }
        # Takılan / soru bekleyen / yardım bekleyen iş önce sürdürülür (görev ayrıntısındaki "Devam ettir" ile aynı)
        if (-not $mesgul -and $AktifAsamalar -notcontains $a) {
            Gorev-Surdur $G '' 'kullanıcı'
            $surduruldu = $a
        }
        if ($Emir -eq 'devral') {
            $rol = Adim-Rolu $G
            $eski = Devralan $G $rol
            $d = [ordered]@{}
            if ($G.devralan) { foreach ($p in $G.devralan.PSObject.Properties) { if ([string]$p.Value) { $d[$p.Name] = [string]$p.Value } } }
            if ($Kim -eq $rol) {
                if ($d.Contains($rol)) { $d.Remove($rol); $ozet = "$kimAd işi geri aldı ($(Calisan-Adi $eski) bıraktı)" }
                else { $ozet = "$kimAd zaten bu adımın sahibi; iş ilerletiliyor" }
            } elseif ($eski -eq $Kim) {
                $ozet = "$kimAd bu işte $(Calisan-Adi $rol) rolünü zaten üstlenmişti; iş ilerletiliyor"
            } else {
                $d[$rol] = $Kim
                $ozet = "$kimAd devraldı ($(Calisan-Adi $rol) yerine)"
            }
            Ayarla $G 'devralan' ([pscustomobject]$d)
        } else {
            $ozet = "$kimAd devam ettirdi (şu anki adım: $(Asama-Adi $G.asama), yapan: $(Calisan-Adi (Adim-Sahibi $G)))"
        }
        if ($Not.Trim()) { Talimat-Ekle $G $Not $Kim $Emir }
        $kayit = [pscustomobject][ordered]@{ zaman = (Simdi); kim = $Kim; emir = $Emir; not = (Kisalt $Not 300); asama = [string]$G.asama }
        Ayarla $G 'komutlar' @(@(@($G.komutlar | Where-Object { $_ }) + $kayit) | Select-Object -Last 20)
        $p = Paralel-Ayari
        $karar = 'paralel'; $neden = ''
        if ($mesgul) { $karar = 'surer'; $neden = 'iş şu an yürütülüyor; komut sonraki adımdan geçerli' }
        elseif (-not $p.etkin) { $karar = 'sira'; $neden = 'paralel çalışma kapalı (ayarlar.json > paralel.etkin)' }
        elseif (@(Paralel-Hatlari).Count -ge $p.en_fazla) { $karar = 'sira'; $neden = "aynı anda en fazla $($p.en_fazla) paralel iş yürüyebilir" }
        if ($mesgul) {
            # İşi başka bir süreç yürütüyor ve kaydı onun elinde: yalnızca komut alanlarını diskteki güncel kayda işle
            # (o süreç adım sonunda bu alanları diskten alır; ekip.ps1 > Gorev-Ilerlet)
            $taze = Gorev-Diskten $G.id
            if (-not $taze) { throw 'Görev kaydı okunamadı; biraz sonra yeniden dene' }
            if ($Emir -eq 'devral') { Ayarla $taze 'devralan' $G.devralan }
            Ayarla $taze 'komutlar' @(@(@($taze.komutlar | Where-Object { $_ }) + $kayit) | Select-Object -Last 20)
            Gorev-Kaydet $taze
        } else {
            # Kullanıcı şimdi istiyor: yeniden deneme beklemesini kaldır
            Ayarla $G 'sonraki_deneme' $null
            if ($karar -eq 'sira') { Ayarla $G 'one_al' $true }
            Gecmis-Ekle $G "kullanıcı komut verdi: $ozet" (Kisalt $Not 300)
            Gorev-Kaydet $G
        }
    } finally { Gorev-Kilidi-Birak $kilit }
    Gunluk "Görev $($G.id): komut ($Emir) -> $Kim; $ozet; $karar $neden"
    return [pscustomobject]@{ karar = $karar; ozet = $ozet; neden = $neden; surduruldu = $surduruldu }
}
