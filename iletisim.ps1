<#
iletisim.ps1 - Şirket binası: katlar (ofisler) arası iletişim. ekip.ps1 dot-source eder. Yalnızca fonksiyon tanımları.

Katlar katlar.json'dadır (ana kat = AI Ekip Ofisi). Bir katın işi başka bir katın uzmanlık alanındaysa ya da bir çalışan başka bir
kattan yardım istiyorsa iletişimi katların Communications Coordinator'ı (Comms, kadro anahtarı "iletisim") yürütür:

  gönderen kat   Engineering Manager (ya da katın yöneticisi) KARAR: KAT verir (yönlendirme ya da yardım kararı)
                 -> Comms isteği hedef kat için kendi başına anlaşılır bir brife çevirir (iletisim-gonder.md)
                 -> hedef katta görev açılır (tip genel; hedefin yöneticisi yönlendirir) ya da uygulama katının API'sine iş verilir
                 -> yazışma kaydı sirket\yazismalar\<no>.json; gönderen görev bekler (kat_bekliyor / yardim_bekliyor, "@<no>")
  hedef kat      kendi akışıyla işi yapar; görev kaydında kaynak_kat / kaynak_gorev / yazisma alanları vardır
  gönderen kat   döngü yazışmayı izler (Kat-Yazismalari-Senkron); iş bitince Comms sonucu ekibine raporlar (iletisim-rapor.md)
                 -> yönlendirilen iş tamamlanır ya da yardım bekleyen çalışan kaldığı aşamadan sürer

Yazışmanın tek yazarı gönderen katın döngüsüdür. Hedefte takılan iş beklenir (o katın Incident Managerʼı ilgilenir); yalnızca
iptal / başarısızlık gönderene başarısız olarak döner. Ayar: ayarlar.json > kat_iletisimi.
#>

$script:YolSirket = Join-Path $KodKok 'sirket'
$script:YazismaSon = @('tamamlandi', 'basarisiz', 'iptal')

function Kat-Iletisimi-Ayari {
    $s = [ordered]@{ etkin = $true; comms_brif = $true; comms_rapor = $true; en_fazla_derinlik = 2; uygulama_zaman_asimi_sn = 15 }
    if ($Ayar -and $Ayar.kat_iletisimi) { foreach ($p in $Ayar.kat_iletisimi.PSObject.Properties) { if ($s.Contains($p.Name) -and $null -ne $p.Value) { $s[$p.Name] = $p.Value } } }
    return [pscustomobject]$s
}
function Kat-Kullanilabilir($K) {
    if (-not $K) { return $false }
    if ([string]$K.tur -eq 'uygulama') { return [bool]($K.uygulama -and ([string]$K.uygulama.api).Trim()) }
    return (Test-Path -LiteralPath (Join-Path (Kat-Koku $K) 'kadro.json'))
}
function Diger-Katlar { return @(Katlar-Oku | Where-Object { [string]$_.id -ne $KatKimligi -and (Kat-Kullanilabilir $_) }) }
function Kat-Iletisimi-Acik { return ([bool](Kat-Iletisimi-Ayari).etkin -and @(Diger-Katlar).Count -gt 0) }
function Kat-Adi([string]$Id) { $k = Kat-Bul $Id; if ($k -and $k.ad) { return [string]$k.ad }; return $Id }

# Hedef bir kat görevinin kaynak katı ve zinciri: aynı işi geri göndermek ya da sonsuz zincir kurmak yasak
function Kat-Gonderilebilir($G, [string]$Hedef) {
    if ($Hedef -eq $KatKimligi) { return 'Hedef kat bu katın kendisi.' }
    if ([string]$G.kaynak_kat -and [string]$G.kaynak_kat -eq $Hedef) { return "Bu iş zaten $(Kat-Adi $Hedef) katından geldi; geri gönderilemez." }
    if ([int]$G.kat_derinligi -ge [int](Kat-Iletisimi-Ayari).en_fazla_derinlik) { return 'Katlar arası iletişim zinciri sınırı doldu.' }
    return ''
}
function Katlar-Metni($G = $null) {
    $l = @()
    foreach ($k in @(Diger-Katlar)) {
        if ($G -and (Kat-Gonderilebilir $G ([string]$k.id))) { continue }
        $durum = 'açık'
        if ([string]$k.tur -eq 'uygulama') { $durum = 'uygulama katı: kendi üretim hattı, tek seferde bir konu alır' }
        elseif (Kat-Kapali-mi (Kat-Koku $k)) { $durum = 'şu an kapalı; iş sıraya girer, kat açılınca başlar' }
        $l += ('- {0}: {1} · {2} ({3})' -f $k.id, $k.ad, ([string]$k.alan), $durum)
    }
    return ($l -join "`n")
}
# Yönlendirme / yardım istemlerinin sonuna eklenen KAT seçeneği (katın kendi istem şablonundan bağımsız)
function Kat-Secenegi-Metni([string]$Tur, $G = $null) {
    if (-not (Kat-Iletisimi-Acik)) { return '' }
    $liste = Katlar-Metni $G
    if (-not $liste) { return '' }
    $comms = Calisan-Adi 'iletisim'; if ($comms -eq 'iletisim') { $comms = 'Communications Coordinator' }
    if ($Tur -eq 'yardim') {
        $secenek = @"
- KARAR: KAT  İstenen yardımı bu ofisin ekibi değil, şirketin başka bir katı karşılayabilir (o katın uzmanlık alanı). "KAT: <kimlik>" yaz,
  "## İş" (o katın ekibinden ne isteniyor, bağlam) ve "## Kabul" bölümlerini ekle. $comms isteği o kata brif olarak iletir, sonucu
  getirir; isteyen çalışan sonuç gelene kadar bekler, sonra kaldığı yerden sürer. Bu ofisten biri yapabiliyorsa KAT seçme.
"@
    } else {
        $secenek = @"
- KARAR: KAT  İş baştan sona şirketin başka bir katının uzmanlık alanında ve bu ofiste onu yapacak ekip yok. "KAT: <kimlik>" yaz,
  "## İş" (o katın ekibi ne yapacak, bağlam, sınırlar) ve "## Kabul" (ölçütler) bölümlerini ekle. $comms işi o kata brif olarak
  teslim eder, sonucu bu göreve geri getirir; görev o sırada bekler. Bu ofisin ekibi yapabiliyorsa KAT seçme.
"@
    }
    return @"


---

# ŞİRKETİN DİĞER KATLARI (katlar arası iletişim)
Bu ofis ($(Ofis-Adi)) çok katlı bir şirketin bir katıdır. Yukarıdaki seçeneklere ek olarak şu karar da geçerlidir:
$secenek
Katlar (kimlik: ad · uzmanlık alanı):
$liste
"@
}

# ---------------------------------------------------------------- yazışma kayıtları (sirket\yazismalar)
function Yazisma-Klasoru {
    $d = Join-Path $YolSirket 'yazismalar'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
    return $d
}
function Yazisma-Yolu([string]$Id) { Join-Path (Yazisma-Klasoru) "$Id.json" }
function Yazisma-Oku([string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{5,90}$') { return $null }
    return (Json-Oku (Yazisma-Yolu $Id))
}
function Yazisma-Kaydet($Y) { Ayarla $Y 'guncelleme' (Simdi); Json-Yaz $Y (Yazisma-Yolu ([string]$Y.id)) }
function Yazisma-Olay($Y, [string]$Olay, [string]$Kim = '') {
    Ayarla $Y 'gecmis' @(@($Y.gecmis | Where-Object { $_ }) + [pscustomobject]@{ zaman = (Simdi); olay = $Olay; kim = $Kim })
}
function Yazismalar-Listele {
    $l = @()
    foreach ($f in @(Get-ChildItem -LiteralPath (Yazisma-Klasoru) -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $y = Json-Oku $f.FullName
        if ($y -and $y.id) { $l += $y }
    }
    return $l
}

# ---------------------------------------------------------------- başka bir katın verisine dokunma (genel durum değişmez)
function Kat-Kadro-Uye($K, [string]$Anahtar) {
    $k = Json-Oku (Join-Path (Kat-Koku $K) 'kadro.json')
    foreach ($u in @($k.uyeler)) { if ($u -and [string]$u.anahtar -eq $Anahtar) { return $u } }
    return $null
}
function Kat-Comms-Adi($K) {
    if ($K -and [string]$K.tur -eq 'uygulama') { return "$(Calisan-Adi 'iletisim') ($(Ofis-Adi))" }
    $u = Kat-Kadro-Uye $K 'iletisim'; if ($u -and $u.ad) { return [string]$u.ad }
    return 'Communications Coordinator'
}
function Kat-Gorev-Oku($K, [string]$Id) {
    if (-not $K -or $Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$') { return $null }
    return (Json-Oku (Join-Path (Join-Path (Join-Path (Kat-Koku $K) 'gorevler') $Id) 'durum.json'))
}
function Kat-Duyuru($K, $Duyuru) {
    $d = Join-Path (Kat-Koku $K) 'durum'
    try {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
        [IO.File]::AppendAllText((Join-Path $d 'duyurular.jsonl'), (($Duyuru | ConvertTo-Json -Compress) + "`n"), $Utf8)
    } catch {}
}
function Kat-Gunluk($K, [string]$Mesaj) {
    $d = Join-Path (Kat-Koku $K) 'gunluk'
    try {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
        $satir = '{0} [BILGI] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Mesaj
        [IO.File]::AppendAllText((Join-Path $d ('ekip-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))), $satir + "`r`n", $Utf8)
    } catch {}
}
# Hedef katta "İş ver" ile aynı biçimde genel görev açar (hedefin yöneticisi yönlendirir); görev kaydı kaynağı taşır
function Kat-Gorevi-Ac($K, [string]$Baslik, [string]$Aciklama, [string[]]$Kabul, [hashtable]$Ek) {
    $kk = Kat-Koku $K
    $yg = Join-Path $kk 'gorevler'
    if (-not (Test-Path -LiteralPath $yg)) { New-Item -ItemType Directory -Force $yg | Out-Null }
    $kilit = New-Object Threading.Mutex($false, ('Local\AIEkipGorevNo_' + ([string]$K.id -replace '[^a-z0-9]', '_')))
    try { [void]$kilit.WaitOne(10000) } catch [Threading.AbandonedMutexException] {}
    try {
        $numaralar = @(Get-ChildItem -LiteralPath $yg -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
        $no = 1; if ($numaralar.Count) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 }
        $id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
        $gk = Join-Path $yg $id
        New-Item -ItemType Directory -Force $gk | Out-Null
        $yonetici = 'Engineering Manager'; $u = Kat-Kadro-Uye $K 'lider'; if ($u -and $u.ad) { $yonetici = [string]$u.ad }
        $kabulMetni = "- (belirtilmedi; $yonetici planda test edilebilir ölçütler belirlesin)"
        $kl = @($Kabul | Where-Object { $_ -and ([string]$_).Trim() })
        if ($kl.Count) { $kabulMetni = ($kl | ForEach-Object { "- $_" }) -join "`n" }
        $satirlar = @("# $Baslik", '', "- Tür: $yonetici yönlendirecek",
            ('- Gönderen: {0} (görev #{1}) · ileten: {2} · teslim alan: {3}' -f $Ek.gonderen_ofis, (([string]$Ek.kaynak_gorev -split '-')[0]), $Ek.gonderen_comms, (Kat-Comms-Adi $K)),
            '- Öncelik: 2', "- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '',
            '## Açıklama', '', $Aciklama, '', '## Kabul ölçütleri', '', $kabulMetni, '',
            '## Notlar ve yanıtlar', '', "(Bu iş başka bir kattan Comms aracılığıyla geldi. $yonetici soru sorarsa yanıtlarını buraya yazıp dosyayı kaydet.)")
        Metin-Yaz (Join-Path $gk 'gorev.md') ($satirlar -join "`n")
        $ayar = Json-Oku (Join-Path $kk 'ayarlar.json')
        $maxTur = 3; try { if ($ayar.gorev.max_tur) { $maxTur = [int]$ayar.gorev.max_tur } elseif ($Ayar.gorev.max_tur) { $maxTur = [int]$Ayar.gorev.max_tur } } catch {}
        $durum = [pscustomobject]@{
            id = $id; baslik = $Baslik; tip = 'genel'; proje = $yonetici; klasor = ''; ipucu = ''; istenen_rol = ''; oncelik = 2
            asama = 'yeni'; tur = 1; max_tur = $maxTur; deneme = 0; dogrulama = @()
            olusturma = (Simdi); guncelleme = (Simdi)
            gecmis = @([pscustomobject]@{ zaman = (Simdi); olay = "Comms teslim aldı: $($Ek.gonderen_ofis) katından iş"; ayrinti = "$($Ek.gonderen_comms) → $(Kat-Comms-Adi $K)"; asama = 'yeni' })
            kaynak_kat = [string]$Ek.kaynak_kat; kaynak_gorev = [string]$Ek.kaynak_gorev; yazisma = [string]$Ek.yazisma; kat_derinligi = [int]$Ek.kat_derinligi
        }
        Json-Yaz $durum (Join-Path $gk 'durum.json')
    } finally { try { $kilit.ReleaseMutex() } catch {}; $kilit.Dispose() }
    return $durum
}
function Kat-Gorevi-Iptal($K, [string]$Id, [string]$Neden) {
    $yol = Join-Path (Join-Path (Join-Path (Kat-Koku $K) 'gorevler') $Id) 'durum.json'
    $g = Json-Oku $yol
    if (-not $g -or [string]$g.asama -ne 'yeni') { return $false }
    $g.asama = 'iptal'
    Ayarla $g 'gecmis' @(@($g.gecmis | Where-Object { $_ }) + [pscustomobject]@{ zaman = (Simdi); olay = 'Comms iptal etti'; ayrinti = $Neden; asama = 'iptal' })
    Ayarla $g 'guncelleme' (Simdi)
    Json-Yaz $g $yol
    return $true
}

# ---------------------------------------------------------------- uygulama katları (kendi API'si olan uygulamalar, ör. Creative Studio)
function Uygulama-Api($K) { return ([string]$K.uygulama.api).TrimEnd('/') }
function Uygulama-Isi-Ac($K, [string]$Konu) {
    $govde = [ordered]@{ topic = (Kisalt $Konu 118) } | ConvertTo-Json -Compress
    $sn = [int](Kat-Iletisimi-Ayari).uygulama_zaman_asimi_sn
    $r = Invoke-RestMethod -Method Post -Uri ((Uygulama-Api $K) + '/jobs') -Body ([Text.Encoding]::UTF8.GetBytes($govde)) -ContentType 'application/json; charset=utf-8' -TimeoutSec $sn -UseBasicParsing
    if (-not $r -or -not $r.id) { throw 'Uygulama iş kimliği döndürmedi.' }
    return [string]$r.id
}
function Uygulama-Isi-Oku($K, [string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$') { throw "Geçersiz uygulama işi: $Id" }
    $sn = [int](Kat-Iletisimi-Ayari).uygulama_zaman_asimi_sn
    return (Invoke-RestMethod -Method Get -Uri ((Uygulama-Api $K) + '/jobs/' + $Id) -TimeoutSec $sn -UseBasicParsing)
}
# Uygulama işinin durumu yazışma durumuna: yayın / yükleme kararı her zaman uygulamanın kendi panelinde kullanıcıdadır
function Uygulama-Durumu([string]$S) {
    switch ($S) {
        { @('awaiting_approval', 'approved', 'uploaded', 'uploading') -contains $_ } { return 'tamamlandi' }
        { @('failed', 'interrupted') -contains $_ } { return 'basarisiz' }
        'running' { return 'calisiyor' }
        default { return 'gonderildi' }
    }
}

# ---------------------------------------------------------------- gönderme
function Comms-Hazir-mi { return [bool]((Kadro-Uye 'iletisim') -and (Rol-Hazir-mi 'iletisim')) }
function Kabul-Listesi([string]$Metin) {
    return @(([string]$Metin -split "`r?`n") | ForEach-Object { ($_ -replace '^\s*([-*•]|\d+[.)])\s*', '').Trim() } | Where-Object { $_ -and $_ -notmatch '^\(' })
}
# Gönderen görevden hedef kata iş / yardım isteği. Döner: yazışma (başarılı) ya da hata metni (string)
function Kat-Talebi-Gonder($G, [string]$HedefId, [string]$Tur, [string]$Istek, [string]$Kabul) {
    $HedefId = ([string]$HedefId).Trim().ToLowerInvariant()
    $K = Kat-Bul $HedefId
    if (-not $K -or -not (Kat-Kullanilabilir $K)) { return "Böyle bir kat yok ya da kullanılamıyor: '$HedefId'" }
    $engel = Kat-Gonderilebilir $G $HedefId
    if ($engel) { return $engel }
    $a = Kat-Iletisimi-Ayari
    $kaynakAd = Ofis-Adi
    $commsAd = Calisan-Adi 'iletisim'; if ($commsAd -eq 'iletisim') { $commsAd = 'Communications Coordinator' }
    $uygulama = ([string]$K.tur -eq 'uygulama')
    if (-not ([string]$Istek).Trim()) { $Istek = Gorev-Metni $G }
    $baslik = Kisalt ([string]$G.baslik) 80
    $brif = $Istek
    $kabulL = Kabul-Listesi $Kabul
    $konu = Kisalt ([string]$G.baslik) 110
    $commsCalisti = $false
    if ($a.comms_brif -and (Comms-Hazir-mi)) {
        $istem = Sablon-Doldur 'iletisim-gonder.md' @{
            KAYNAK = $kaynakAd; HEDEF = "$($K.ad) ($HedefId)"; HEDEF_ALAN = [string]$K.alan; TUR = $(if ($Tur -eq 'yardim') { 'yardım isteği (gönderen çalışan sonucu bekliyor)' } else { 'iş devri (görev sonucu bekliyor)' })
            UYGULAMA = $(if ($uygulama) { 'Hedef bir uygulama katı: yalnızca KONU satırındaki tek cümle iletilir (en fazla 110 karakter).' } else { 'Hedef bir ekip katı: brif ve kabul ölçütleri o katta yeni bir görev olur.' })
            ISTEK = (Kirp $Istek 6000); KABUL = $(if ($kabulL.Count) { ($kabulL | ForEach-Object { "- $_" }) -join "`n" } else { '(belirtilmedi)' }); GOREV = (Kirp (Gorev-Metni $G) 6000)
        }
        $r = Ajan-Cagir -Rol 'iletisim' -Istem $istem -Klasor (Gorev-Klasoru $G.id) -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'kat-gonder'
        if ($r.basarili -and $r.metin) {
            $commsCalisti = $true
            $b = Alan-Oku $r.metin 'BASLIK'; if ($b) { $baslik = Kisalt (Deger-Temizle $b) 80 }
            $kn = Alan-Oku $r.metin 'KONU'; if ($kn) { $konu = Kisalt (Deger-Temizle $kn) 110 }
            $bb = Bolum-Oku $r.metin 'Brif'; if ($bb) { $brif = $bb }
            $kb = Kabul-Listesi (Bolum-Oku $r.metin 'Kabul'); if ($kb.Count) { $kabulL = $kb }
        }
    }
    $yid = '{0}-{1}-{2}-{3}' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), ($KatKimligi -replace '[^a-z0-9]', ''), ($HedefId -replace '[^a-z0-9]', ''), ([guid]::NewGuid().ToString('N').Substring(0, 4))
    $y = [pscustomobject][ordered]@{
        id = $yid; tur = $Tur; olusturma = (Simdi); guncelleme = (Simdi)
        kaynak_kat = $KatKimligi; kaynak_ofis = $kaynakAd; kaynak_gorev = [string]$G.id; kaynak_baslik = [string]$G.baslik
        hedef_kat = $HedefId; hedef_ofis = [string]$K.ad; hedef_tur = $(if ($uygulama) { 'uygulama' } else { 'ekip' }); hedef_gorev = ''
        baslik = $baslik; brif = (Kirp $brif 8000); kabul = @($kabulL); konu = $konu
        gonderen = $commsAd; alan = (Kat-Comms-Adi $K); comms_brif = $commsCalisti
        durum = 'gonderildi'; hedef_asama = ''; sonuc = $null; gecmis = @()
    }
    Yazisma-Olay $y "$commsAd isteği yazdı ($kaynakAd → $($K.ad))" $commsAd
    if ($uygulama) {
        try { $y.hedef_gorev = Uygulama-Isi-Ac $K $konu; Yazisma-Olay $y "$($K.ad) işi aldı: $($y.hedef_gorev)" $commsAd }
        catch { $y.durum = 'beklemede'; Yazisma-Olay $y "$($K.ad) şu an yanıt vermiyor; kat açılınca Comms işi teslim edecek ($($_.Exception.Message))" $commsAd }
    } else {
        $hg = Kat-Gorevi-Ac $K $baslik $brif $kabulL @{ gonderen_ofis = $kaynakAd; gonderen_comms = $commsAd; kaynak_kat = $KatKimligi; kaynak_gorev = [string]$G.id; yazisma = $yid; kat_derinligi = ([int]$G.kat_derinligi + 1) }
        $y.hedef_gorev = [string]$hg.id
        Yazisma-Olay $y "$($y.alan) teslim aldı: #$(($hg.id -split '-')[0])" $y.alan
        Kat-Duyuru $K ([ordered]@{ zaman = (Simdi); tur = 'kat_yazisma'; anahtar = 'iletisim'; ad = $y.alan; kaynak = $kaynakAd; gorev = $hg.id; baslik = $baslik; yazisma = $yid })
        Kat-Gunluk $K "Comms: $kaynakAd katından iş geldi: $($hg.id) ($baslik) [yazışma $yid]"
        if (Kat-Kapali-mi (Kat-Koku $K)) { Yazisma-Olay $y "$($K.ad) şu an kapalı; iş sırada, kat açılınca başlar" $y.alan }
    }
    Yazisma-Kaydet $y
    Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) "kat-yazisma-$yid.md") ("# Katlar arası yazışma $yid`n`n- Gönderen: $kaynakAd ($commsAd)`n- Hedef: $($K.ad) ($($y.alan))`n- Hedef görev / iş: $($y.hedef_gorev)`n`n## Brif`n`n$brif`n`n## Kabul`n`n" + (($kabulL | ForEach-Object { "- $_" }) -join "`n"))
    Ayarla $G 'kat_yazismalari' @(@($G.kat_yazismalari | Where-Object { $_ }) + $yid)
    Sayac-Artir 'kat_yazisma'
    Gunluk "Görev $($G.id): Comms $($K.ad) katına $(if ($Tur -eq 'yardim') { 'yardım isteği' } else { 'iş' }) gönderdi ($yid → $($y.hedef_gorev))"
    return $y
}
# Bir klasörün hangi katın kökü olduğu (bulunamazsa 'ana')
function Kok-Kat-Kimligi([string]$Klasor) {
    $a = ([string]$Klasor).TrimEnd('\')
    foreach ($k in @(Katlar-Oku)) { if ([string]$k.tur -ne 'uygulama' -and (Kat-Koku $k).TrimEnd('\') -ieq $a) { return [string]$k.id } }
    return 'ana'
}
# Görevi başka bir yoldan (ör. fikir hattının POC köprüsü) açılmış iş için yazışma kaydı: izleme ve panel için
function Kat-Yazisma-Kaydi($G, [string]$HedefId, [string]$HedefGorev, [string]$Tur, [string]$Baslik, [string]$Brif, $Kabul) {
    $K = Kat-Bul $HedefId
    if (-not $K -or $HedefId -eq $KatKimligi) { return $null }
    $commsAd = Calisan-Adi 'iletisim'; if ($commsAd -eq 'iletisim') { $commsAd = 'Communications Coordinator' }
    $yid = '{0}-{1}-{2}-{3}' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), ($KatKimligi -replace '[^a-z0-9]', ''), ($HedefId -replace '[^a-z0-9]', ''), ([guid]::NewGuid().ToString('N').Substring(0, 4))
    $y = [pscustomobject][ordered]@{
        id = $yid; tur = $Tur; olusturma = (Simdi); guncelleme = (Simdi)
        kaynak_kat = $KatKimligi; kaynak_ofis = (Ofis-Adi); kaynak_gorev = [string]$G.id; kaynak_baslik = [string]$G.baslik
        hedef_kat = $HedefId; hedef_ofis = [string]$K.ad; hedef_tur = 'ekip'; hedef_gorev = $HedefGorev
        baslik = (Kisalt $Baslik 80); brif = (Kirp $Brif 8000); kabul = @($Kabul | Where-Object { $_ }); konu = (Kisalt $Baslik 110)
        gonderen = $commsAd; alan = (Kat-Comms-Adi $K); comms_brif = $false
        durum = 'gonderildi'; hedef_asama = 'yeni'; sonuc = $null; gecmis = @()
    }
    Yazisma-Olay $y "$commsAd POC teslim paketini $($K.ad) katına iletti" $commsAd
    Yazisma-Olay $y "$($y.alan) teslim aldı: #$(($HedefGorev -split '-')[0])" $y.alan
    Yazisma-Kaydet $y
    Kat-Duyuru $K ([ordered]@{ zaman = (Simdi); tur = 'kat_yazisma'; anahtar = 'iletisim'; ad = $y.alan; kaynak = (Ofis-Adi); gorev = $HedefGorev; baslik = $y.baslik; yazisma = $yid })
    Kat-Gunluk $K "Comms: $(Ofis-Adi) katından POC geldi: $HedefGorev [yazışma $yid]"
    Ayarla $G 'kat_yazismalari' @(@($G.kat_yazismalari | Where-Object { $_ }) + $yid)
    return $y
}
# Engineering Managerʼın KAT kararı (yönlendirme ya da yardım): görev yazışma sonucunu bekler
function Kat-Kararini-Uygula($G, $R, [string]$Tur, [string]$Donus = '') {
    $hedef = (Deger-Temizle (Alan-Oku $R.metin 'KAT')).ToLowerInvariant() -replace '\s.*$', ''
    $is = Bolum-Oku $R.metin 'İş'; if (-not $is) { $is = Bolum-Oku $R.metin 'Is' }
    $kabul = Bolum-Oku $R.metin 'Kabul'
    $y = Kat-Talebi-Gonder $G $hedef $Tur $is $kabul
    if ($y -is [string]) { return $y }
    $kim = Calisan-Adi 'lider'
    Ayarla $G 'yardim_bekleyen' @('@' + $y.id)
    if ($Tur -eq 'yardim') {
        Ayarla $G 'yardim_donus_asama' $Donus
        $G.asama = 'yardim_bekliyor'
    } else {
        Ayarla $G 'yonlendiren' ('{0}/{1}' -f $R.arac, $R.model)
        Ayarla $G 'yonlendirme_karari' 'KAT'
        $G.asama = 'kat_bekliyor'
    }
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    $durumNotu = ''; if ($y.durum -eq 'beklemede') { $durumNotu = ' (kat şu an yanıt vermiyor; açılınca teslim edilecek)' }
    Gecmis-Ekle $G "$kim işi $($y.hedef_ofis) katına verdi; Comms iletti" ("yazışma {0} → {1}{2}" -f $y.id, $y.hedef_gorev, $durumNotu) $R
    Bildir -Baslik "Katlar arası: $($y.hedef_ofis) katına iş gitti" -Metin ("#{0} {1} → {2} ({3})" -f (($G.id -split '-')[0]), (Kisalt $y.baslik 80), $y.hedef_ofis, $y.alan) -Anahtar "kat-$($y.id)"
    return ''
}

# ---------------------------------------------------------------- izleme ve dönüş (gönderen katın döngüsü)
function Kat-Sonuc-Metni($K, $Y, $Uzak) {
    if ([string]$Y.hedef_tur -eq 'uygulama') {
        $s = $Uzak
        $l = @("Uygulama işi: $($Y.hedef_gorev) · durum: $($s.status)")
        if ($s.title) { $l += "Başlık: $($s.title)" }
        if ($s.story -and $s.story.text) { $l += "Hikâye: " + (Kisalt ([string]$s.story.text) 1500) }
        if ($s.video_url) { $l += "Video: " + ((Uygulama-Api $K) -replace '/api$', '') + [string]$s.video_url }
        if ($s.duration) { $l += "Süre: $([math]::Round([double]$s.duration, 1)) sn" }
        if ($s.error) { $l += "Hata: $($s.error)" }
        $l += 'Yayın / YouTube yüklemesi kullanıcının kararıdır; uygulamanın kendi panelindeki önizlemeden onaylanır.'
        return ($l -join "`n")
    }
    $g = $Uzak
    $gk = Join-Path (Join-Path (Kat-Koku $K) 'gorevler') ([string]$g.id)
    $l = @("Hedef görev: #$($g.id) · aşama: $($g.asama)")
    foreach ($a in @('ozet', 'dal', 'commit', 'calisma_klasoru', 'proje', 'klasor')) { $v = [string]$g.$a; if ($v) { $l += "- ${a}: $v" } }
    foreach ($ad in @('sonuc.md', 'kabul.md', 'calisma-ozet.md', 'danisman-rapor.md', 'inceleme.md', 'uygulama-ozet.md', 'dogrulama.md')) {
        $f = @(Get-ChildItem -LiteralPath $gk -Recurse -File -Filter $ad -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        if ($f.Count) { $l += "`n## $ad`n" + (Kirp (Gizli-Maskele (Metin-Oku $f[0].FullName)) 3000) }
    }
    $cikti = Join-Path (Join-Path (Join-Path (Kat-Koku $K) 'calisma') ([string]$g.id)) 'cikti'
    if (Test-Path -LiteralPath $cikti) { $l += "`nTeslim klasörü: $cikti"; $l += (@(Get-ChildItem -LiteralPath $cikti -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { '- ' + $_.FullName.Substring($cikti.Length + 1) }) -join "`n") }
    return ($l -join "`n")
}
function Kat-Raporu-Yaz($Y, [string]$Sonuc) {
    $a = Kat-Iletisimi-Ayari
    $rapor = ''
    $g = $null; if ([string]$Y.tur -ne 'poc') { $g = Gorev-Oku ([string]$Y.kaynak_gorev) }
    if ($a.comms_rapor -and $g -and (Comms-Hazir-mi)) {
        $eskiG = $script:AktifGorev; $eskiA = $script:AktifAdim
        $script:AktifGorev = [string]$g.id; $script:AktifAdim = 'kat-rapor'
        try {
            $istem = Sablon-Doldur 'iletisim-rapor.md' @{ KAYNAK = (Ofis-Adi); HEDEF = [string]$Y.hedef_ofis; DURUM = [string]$Y.durum; BRIF = (Kirp ([string]$Y.brif) 4000); SONUC = (Kirp $Sonuc 9000) }
            $r = Ajan-Cagir -Rol 'iletisim' -Istem $istem -Klasor (Gorev-Klasoru $g.id) -KayitKlasoru (Kayit-Klasoru $g) -Etiket 'kat-rapor'
            if ($r.basarili -and $r.metin) { $rapor = $r.metin }
        } finally { $script:AktifGorev = $eskiG; $script:AktifAdim = $eskiA }
    }
    if (-not $rapor) { $rapor = "## $($Y.hedef_ofis) katının sonucu`n`n$Sonuc" }
    Metin-Yaz (Join-Path (Yazisma-Klasoru) "$($Y.id)-rapor.md") $rapor
    return $rapor
}
# Gönderen katın açık yazışmalarını hedefle eşitler; her döngü turunda çağrılır (hafif: yalnızca bu katın açık yazışmaları)
function Kat-Yazismalari-Senkron {
    if (-not (Test-Path -LiteralPath (Join-Path $YolSirket 'yazismalar'))) { return }
    foreach ($y in @(Yazismalar-Listele)) {
        if ([string]$y.kaynak_kat -ne $KatKimligi -or $YazismaSon -contains [string]$y.durum) { continue }
        $K = Kat-Bul ([string]$y.hedef_kat)
        try {
            $eski = [string]$y.durum
            $kg = $null; if ([string]$y.tur -ne 'poc') { $kg = Gorev-Oku ([string]$y.kaynak_gorev) }
            # Gönderen görev iptal edildiyse: hedefte başlamadıysa geri çek, başladıysa not düş
            if ($kg -and [string]$kg.asama -eq 'iptal') {
                $geri = $false; if ($K -and [string]$y.hedef_tur -eq 'ekip' -and $y.hedef_gorev) { $geri = Kat-Gorevi-Iptal $K ([string]$y.hedef_gorev) "Gönderen görev ($($y.kaynak_ofis) #$($y.kaynak_gorev)) iptal edildi" }
                $y.durum = 'iptal'
                Yazisma-Olay $y $(if ($geri) { 'Gönderen görev iptal edildi; Comms hedefteki işi geri çekti' } else { 'Gönderen görev iptal edildi (hedefteki iş sürüyorsa o katta tamamlanır ya da iptal edilir)' }) ([string]$y.gonderen)
                Yazisma-Kaydet $y; continue
            }
            if (-not $K) { $y.durum = 'basarisiz'; Yazisma-Olay $y "Hedef kat bulunamadı: $($y.hedef_kat)"; Yazisma-Kaydet $y; continue }
            $uzak = $null
            if ([string]$y.hedef_tur -eq 'uygulama') {
                if ([string]$y.durum -eq 'beklemede') {
                    try { $y.hedef_gorev = Uygulama-Isi-Ac $K ([string]$y.konu); $y.durum = 'gonderildi'; Yazisma-Olay $y "$($K.ad) açıldı; Comms işi teslim etti: $($y.hedef_gorev)" ([string]$y.gonderen); Yazisma-Kaydet $y } catch {}
                    continue
                }
                try { $uzak = Uygulama-Isi-Oku $K ([string]$y.hedef_gorev) } catch { continue }   # uygulama kapalı: sonra yine bakılır
                $yeni = Uygulama-Durumu ([string]$uzak.status)
                $y.hedef_asama = [string]$uzak.status
            } else {
                $uzak = Kat-Gorev-Oku $K ([string]$y.hedef_gorev)
                if (-not $uzak) { $y.durum = 'basarisiz'; Yazisma-Olay $y "Hedef görev bulunamadı: $($y.hedef_gorev)"; Yazisma-Kaydet $y; continue }
                $y.hedef_asama = [string]$uzak.asama
                switch ([string]$uzak.asama) {
                    'tamam' { $yeni = 'tamamlandi' }
                    'reddedildi' { $yeni = 'basarisiz' }
                    'iptal' { $yeni = 'basarisiz' }
                    'takildi' { $yeni = 'takildi' }
                    'yeni' { $yeni = 'gonderildi' }
                    default { $yeni = 'calisiyor' }
                }
            }
            if ($yeni -eq $eski) { continue }
            $y.durum = $yeni
            $olay = @{ calisiyor = "$($K.ad) ekibi işe başladı"; takildi = "$($K.ad) katında takıldı (o katın Incident Managerʼı ilgileniyor)"; tamamlandi = "$($K.ad) işi tamamladı"; basarisiz = "$($K.ad) işi tamamlayamadı ($($y.hedef_asama))"; gonderildi = "$($K.ad) katında sırada" }[$yeni]
            Yazisma-Olay $y $olay ([string]$y.alan)
            if ($YazismaSon -contains $yeni) {
                $sonucMetni = Kat-Sonuc-Metni $K $y $uzak
                $rapor = ''
                if ([string]$y.tur -ne 'poc') { $rapor = Kat-Raporu-Yaz $y $sonucMetni; Yazisma-Olay $y "$($y.gonderen) sonucu ekibine raporladı" ([string]$y.gonderen) }
                Ayarla $y 'sonuc' ([pscustomobject]@{ zaman = (Simdi); hedef_asama = [string]$y.hedef_asama; ozet = (Kisalt $(if ($uzak.ozet) { [string]$uzak.ozet } elseif ($uzak.title) { [string]$uzak.title } else { $olay }) 400); rapor = (Kirp $rapor 12000); ham = (Kirp $sonucMetni 6000) })
                Kat-Gunluk $K "Comms: $($y.kaynak_ofis) katına giden iş sonuçlandı ($yeni): $($y.hedef_gorev) [yazışma $($y.id)]"
            }
            Yazisma-Kaydet $y
            Gunluk "Yazışma $($y.id): $eski → $yeni ($($K.ad) / $($y.hedef_gorev))"
        } catch { Gunluk "Yazışma $($y.id) izlenemedi: $($_.Exception.Message)" 'UYARI' }
    }
}
# Yardım / kat bekleyen görevin "@<yazışma>" kaydı: bittiyse sonuç nesnesi, sürüyorsa $null (yardim.ps1 > Yardim-Bekleyenleri-Kontrol)
function Kat-Bekleyen-Sonucu([string]$Ref) {
    $y = Yazisma-Oku ($Ref.TrimStart('@'))
    if (-not $y) { return [pscustomobject]@{ id = $Ref; baslik = ''; durum = 'bulunamadı'; metin = 'Katlar arası yazışma kaydı bulunamadı.'; basarili = $false } }
    if ($YazismaSon -notcontains [string]$y.durum) { return $null }
    $ok = ([string]$y.durum -eq 'tamamlandi')
    $metin = ''; if ($y.sonuc) { $metin = [string]$y.sonuc.rapor; if (-not $metin) { $metin = [string]$y.sonuc.ham } }
    if (-not $metin) { $metin = "$($y.hedef_ofis): $($y.durum)" }
    $d = @{ tamamlandi = 'tamamlandı'; basarisiz = 'tamamlanamadı'; iptal = 'iptal edildi' }[[string]$y.durum]
    return [pscustomobject]@{ id = $Ref; baslik = "$($y.hedef_ofis) katı · $($y.baslik)"; durum = $d; metin = "$metin`n`nYazışma: sirket\yazismalar\$($y.id).json · hedef: $($y.hedef_ofis) $($y.hedef_gorev)"; basarili = $ok; yazisma = $y }
}
# kat_bekliyor görevini sonuçlandırır (yönlendirilen iş başka katta bitti)
function Kat-Isi-Sonuclandir($G, $Sonuclar) {
    $s = @($Sonuclar)[0]
    $gk = Gorev-Klasoru $G.id
    Metin-Yaz (Join-Path $gk 'sonuc.md') ("# $($G.baslik)`n`n$($s.baslik) · $($s.durum)`n`n$($s.metin)")
    Ayarla $G 'yardim_bekleyen' @()
    if ($s.basarili) {
        $oz = $s.metin; if ($s.yazisma -and $s.yazisma.sonuc -and $s.yazisma.sonuc.ozet) { $oz = [string]$s.yazisma.sonuc.ozet }
        Ayarla $G 'ozet' (Kisalt ("$($s.yazisma.hedef_ofis) tamamladı: $oz") 400)
        Asama-Gec $G 'tamam' "$($s.yazisma.hedef_ofis) işi tamamladı; Comms raporladı" ([string]$s.yazisma.hedef_gorev)
        Sayac-Artir 'tamam'
        Gorev-Kaydet $G
        Bildir -Baslik "Tamamlandı (başka katta): $($G.baslik)" -Metin ("#{0}: {1}" -f (($G.id -split '-')[0]), (Kisalt $oz 200)) -Anahtar "tamam-$($G.id)"
    } else {
        Takildi $G ("Başka kata verilen iş $($s.durum): $(Kisalt $s.metin 300)")
        Gorev-Kaydet $G
    }
}
