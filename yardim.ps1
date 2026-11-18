<#
yardim.ps1 - Ekip içi yardımlaşma (ayarlar.json > yardimlasma). ekip.ps1 dot-source eder.

Bir ajan işi sırasında kendi yapamayacağı ama ekipte başkasının yapabileceği bir şeye ihtiyaç duyarsa, çıktısının sonuna
```yardim {json}``` bloğu ekler (talimatı ortak.ps1 > Yardim-Istem-Ekle her uygun istemin sonuna koyar). Adım başarısız sayılmaz:
  1. Yardim-Istegi-Kaydet     görev 'yardim' aşamasına geçer (dönüş aşaması saklanır); istek gorevler\<no>\yardim-istek-N.md
  2. Yardim-Yonlendir         Engineering Manager değerlendirir: BIRLIKTE (bir ekip arkadaşı HEMEN, aynı adımda isteyenin çalışma
                              klasöründe çalışır; Yardim-Birlikte-Calis), ATA (kadrodan birine ayrı yardım işi), YANIT, ISE_ALIM, KULLANICI
  3. Yardim-Bekleyenleri-Kontrol  yardım işleri bitince görev dönüş aşamasından sürer; sonuçlar yardim-sonuclari.md'ye yazılır
     ve bu görevin sonraki her ajan isteminde "EKİPTEN GELEN YARDIM" bölümü olarak yer alır.
Engineering Manager planda ön iş de isteyebilir: "YARDIM: <anahtar> | <iş>" satırları (Plan-Yardimlari) geliştirmeden önce açılır.
QA Engineer (tester) yazılım işlerinde ek inceleme, uzman işlerinde inceleyen ya da sorumlu olarak çalışır (Tester-Calistir).
Sınırlar: görev başına en fazla yardimlasma.gorev_basina_en_fazla istek; yardım zinciri en fazla yardimlasma.derinlik.
#>

function Yardimlasma-Ayari {
    $a = $Ayar.yardimlasma
    $etkin = $false; $enFazla = 4; $derinlik = 2
    if ($a) {
        if ($null -ne $a.etkin) { $etkin = [bool]$a.etkin }
        if ($a.gorev_basina_en_fazla) { $enFazla = [int]$a.gorev_basina_en_fazla }
        if ($a.derinlik) { $derinlik = [int]$a.derinlik }
    }
    return [pscustomobject]@{ etkin = $etkin; en_fazla = $enFazla; derinlik = $derinlik }
}
function Rol-Ad([string]$Rol) {
    $u = Kadro-Uye $Rol
    if ($u) { return [string]$u.ad }
    if ($Rol -eq 'lider') { return 'Engineering Manager' }
    return $Rol
}
# Yardım işi verilebilecekler: sistem / ag (altyapı talebi) ve uzman işi alan herkes (uzman işi)
function Yardim-Atanabilir([string]$Kim) {
    if (-not $Kim -or @('lider', 'sorun-giderici', 'gelistirici', 'denetci', 'yok') -contains $Kim) { return $false }
    if (@('sistem', 'ag') -contains $Kim) { return $true }
    $u = Kadro-Uye $Kim
    return [bool]($u -and $u.uzman_isi)
}
function Yardim-Derinligi($G) {
    $d = 0; $x = $G
    while ($x -and $x.ana_gorev -and $d -lt 6) { $d++; $x = Gorev-Oku ([string]$x.ana_gorev) }
    return $d
}
function Yardim-Sonucu-Ekle($G, [string]$Baslik, [string]$Metin) {
    $f = Join-Path (Gorev-Klasoru $G.id) 'yardim-sonuclari.md'
    $yeni = "## {0} · {1}`n`n{2}`n" -f $Baslik, (Get-Date).ToString('dd.MM HH:mm'), ([string]$Metin).Trim()
    Metin-Yaz $f (((Metin-Oku $f).TrimEnd() + "`n`n" + $yeni).TrimStart())
}
function Yardim-Donus-Asamasi($G) {
    $d = [string]$G.yardim_donus_asama
    if (-not $d -or @('yardim', 'yardim_bekliyor', 'takildi', 'bekliyor_kullanici') -contains $d -or $AktifAsamalar -notcontains $d) { $d = 'gelistirme' }
    return $d
}

# Ajan çıktısındaki yardım isteğini kaydeder (Adim-Basarisiz çağırır). $true: görev yardım akışına alındı; $false: normal başarısızlık
function Yardim-Istegi-Kaydet($G, $Y) {
    $a = Yardimlasma-Ayari
    if (-not $a.etkin) { return $false }
    $n = [int]$G.yardim_sayisi + 1
    if ($n -gt $a.en_fazla) { Gunluk "Görev $($G.id): yardım hakkı doldu ($($a.en_fazla)); istek normal başarısızlık sayıldı" 'UYARI'; return $false }
    $i = $Y.istek
    $kabul = @($i.kabul | Where-Object { $_ } | ForEach-Object { "- $_" }) -join "`n"
    $md = @(
        "# Yardım isteği $n · $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '',
        "- İsteyen: $(Rol-Ad ([string]$Y.rol)) ($($Y.rol)) · adım: $($Y.etiket) · aşama: $(Asama-Adi ([string]$G.asama)) · araç: $($Y.arac)",
        "- Önerdiği kişi: $(if ($i.kim) { [string]$i.kim } else { '(yok)' })",
        "- Aciliyet: $(if ([bool]$i.hemen) { 'hemen (çalışması buna bağlı; birlikte çalışma uygun)' } else { 'belirtilmedi' })",
        "- Çalışma klasörü: $(if ($G.calisma_klasoru) { [string]$G.calisma_klasoru } else { Gorev-Klasoru $G.id })", '',
        '## Ne gerekiyor', '', ([string]$i.ne), '',
        '## Neden', '', $(if ($i.neden) { [string]$i.neden } else { '(belirtilmedi)' }), '',
        '## Kabul', '', $(if ($kabul) { $kabul } else { '(belirtilmedi)' }), '',
        '## İsteyenin çıktısı (kırpılmış)', '', (Kirp (Gizli-Maskele ([string]$Y.metin)) 5000)
    ) -join "`n"
    Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) "yardim-istek-$n.md") $md
    Ayarla $G 'yardim_sayisi' $n
    Ayarla $G 'yardim_donus_asama' ([string]$G.asama)
    Ayarla $G 'yardim_isteyen' ([string]$Y.rol)
    Ayarla $G 'yardim_istek' (Kisalt ([string]$i.ne) 300)
    Gecmis-Ekle $G "$(Rol-Ad ([string]$Y.rol)) yardım istedi" ([string]$i.ne)
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'son_hata' ''
    $kim = Kadro-Anahtar-Coz ([string]$i.kim)
    if ([string]$Y.rol -eq 'lider' -and (Yardim-Atanabilir $kim) -and (Yardim-Derinligi $G) -lt $a.derinlik) {
        # Engineering Manager kendisi istedi ve kimin yapacağını söyledi: ayrıca değerlendirme adımına gerek yok
        $is = [string]$i.ne; if ($i.neden) { $is += "`n`nNeden: $($i.neden)" }
        [void](Yardim-Isleri-Ac $G @([pscustomobject]@{ kim = $kim; baslik = ''; is = $is; kabul = $kabul; neden = [string]$i.neden; aranan = '' }) 'Engineering Manager' ([string]$G.asama))
        return $true
    }
    $G.asama = 'yardim'
    Gunluk "Görev $($G.id): $($Y.rol) yardım istedi; Engineering Manager değerlendirecek ($(Kisalt ([string]$i.ne) 120))"
    return $true
}

# Yardım işlerini açar ve görevi bekletir. $Isler: kim, baslik, is, kabul, neden, aranan (İK işe alımı)
function Yardim-Isleri-Ac($G, $Isler, [string]$Acan, [string]$Donus) {
    $ids = @(); $adlar = @()
    foreach ($i in @($Isler)) {
        $ek = @{}
        $hedef = [string]$i.kim; $uye = $null
        if ($i.aranan) { $hedef = ''; $ek.ise_alim_aranan = [string]$i.aranan; $ek.ise_alim_sayisi = 1 }
        else { $uye = Kadro-Uye $hedef; if (-not $uye) { $uye = [pscustomobject]@{ ad = (Rol-Ad $hedef) } } }
        $id = Yardim-Gorevi-Ac $G $hedef $uye ([string]$i.baslik) ([string]$i.is) ([string]$i.kabul) ([string]$i.neden) $Acan 'Neden gerekli' $ek
        $ids += $id
        $adlar += ('#{0} → {1}' -f (No-Kisa $id), $(if ($i.aranan) { 'İK (işe alım)' } else { Rol-Ad $hedef }))
    }
    Ayarla $G 'yardim_bekleyen' @($ids)
    Ayarla $G 'yardim_donus_asama' $Donus
    $G.asama = 'yardim_bekliyor'
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Gecmis-Ekle $G "$Acan yardım işi açtı" ($adlar -join ', ')
    Gunluk "Görev $($G.id): yardım işleri açıldı: $($adlar -join ', ') (sonra: $Donus)"
    return $ids
}
function Yardim-Yanitla($G, [string]$Yanit, [string]$Donus, $R, [string]$Olay) {
    Yardim-Sonucu-Ekle $G ('Engineering Managerʼın yanıtı (yardım isteği {0}: {1})' -f $G.yardim_sayisi, (Kisalt ([string]$G.yardim_istek) 120)) $Yanit
    Asama-Gec $G $Donus $Olay (Kisalt $Yanit 200) $R
}
function Yardim-Durum-Metni($G) {
    $tip = [string]$G.tip; if (-not $tip) { $tip = 'yazilim' }
    $l = @("- No: $($G.id) | Başlık: $($G.baslik) | Tür: $tip | Tur: $($G.tur)/$($G.max_tur)",
        "- Yardım istenen aşama: $(Asama-Adi (Yardim-Donus-Asamasi $G)) · isteyen: $(Rol-Ad ([string]$G.yardim_isteyen))")
    foreach ($a in @('proje', 'klasor', 'calisma_klasoru', 'dal', 'sorumlu', 'inceleyen', 'kaynak_klasor', 'ana_gorev')) { $v = $G.$a; if ($v) { $l += "- ${a}: $v" } }
    $l += "- Görev klasörü: $(Gorev-Klasoru $G.id)"
    return ($l -join "`n")
}

# Görev 'yardim' aşamasında: Engineering Manager isteği değerlendirir
function Yardim-Yonlendir($G) {
    $a = Yardimlasma-Ayari
    $gk = Gorev-Klasoru $G.id
    $n = [int]$G.yardim_sayisi
    $donus = Yardim-Donus-Asamasi $G
    $istek = Metin-Oku (Join-Path $gk "yardim-istek-$n.md")
    if (-not $istek) { Asama-Gec $G $donus 'yardım isteği bulunamadı; adım yeniden çalışacak'; return }
    $zincirSiniri = ((Yardim-Derinligi $G) -ge $a.derinlik)
    $zincir = 'Gerekirse ATA ya da ISE_ALIM ile yeni yardım işi açabilirsin.'
    if ($zincirSiniri) { $zincir = 'Bu iş zaten bir yardım zincirinin içinde ve zincir sınırı doldu: yeni yardım işi AÇAMAZSIN; BIRLIKTE, YANIT ya da KULLANICI seç.' }
    $onceki = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $gk -Filter 'yardim-karar-*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)) { $onceki += Kirp (Metin-Oku $f.FullName) 1500 }
    $sonuc = Metin-Oku (Join-Path $gk 'yardim-sonuclari.md'); if ($sonuc) { $onceki += "### Gelen yardımlar`n" + (Kirp $sonuc 3000) }
    if (-not $onceki.Count) { $onceki = @('(yok)') }
    Kadro-Rolleri-Yukle
    $istem = Sablon-Doldur 'yonetici-yardim.md' @{
        ISTEK = $istek; KADRO = (Kadro-Metni); ARACLAR = (Arac-Durumu-Metni); DURUM = (Yardim-Durum-Metni $G)
        GOREV = (Kirp (Gorev-Metni $G) 5000); ONCEKI = ($onceki -join "`n`n"); ZINCIR_KURALI = $zincir
    }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor $gk -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'yardim'
    if (-not $r.basarili) { Adim-Basarisiz $G "Engineering Manager yardım isteğini değerlendiremedi: $($r.hata)"; return }
    Metin-Yaz (Join-Path $gk "yardim-karar-$n.md") (("# Engineering Managerʼın kararı · yardım isteği {0} · {1} · {2}/{3}" -f $n, (Get-Date).ToString('dd.MM.yyyy HH:mm'), $r.arac, $r.model) + "`n`n" + $r.metin)
    Ayarla $G 'lider' ('{0}/{1}' -f $r.arac, $r.model)
    $karar = Karar-Oku $r.metin
    if ($zincirSiniri -and ($karar -eq 'ATA' -or $karar -eq 'ISE_ALIM')) { $karar = 'YANIT' }
    $isteyen = Rol-Ad ([string]$G.yardim_isteyen)
    $neden = "$isteyen istedi: $($G.yardim_istek)"
    Ayarla $G 'yardim_karari' $karar
    switch ($karar) {
        'BIRLIKTE' {
            $kim = Kadro-Anahtar-Coz (Alan-Oku $r.metin 'KIM')
            $is = Bolum-Oku $r.metin 'İş'
            if ((Yardim-Birlikte-Uygun $kim ([string]$G.yardim_isteyen)) -and $is) {
                Yardim-Birlikte-Calis $G $kim $is (Bolum-Oku $r.metin 'Kabul') $donus $r
                break
            }
            $y = Bolum-Oku $r.metin 'Yanıt'; if (-not $y) { $y = $is }; if (-not $y) { $y = Bolum-Oku $r.metin 'Gerekçe' }
            Yardim-Yanitla $G $y $donus $r "Engineering Manager yanıtladı (birlikte çalışma geçersizdi: '$kim')"
        }
        'ATA' {
            $kim = Kadro-Anahtar-Coz (Alan-Oku $r.metin 'KIM')
            $is = Bolum-Oku $r.metin 'İş'
            if ((Yardim-Atanabilir $kim) -and $is -and $kim -ne [string]$G.yardim_isteyen) {
                [void](Yardim-Isleri-Ac $G @([pscustomobject]@{ kim = $kim; baslik = (Alan-Oku $r.metin 'BASLIK'); is = $is; kabul = (Bolum-Oku $r.metin 'Kabul'); neden = $neden; aranan = '' }) "Engineering Manager ($isteyen istedi)" $donus)
                break
            }
            $y = Bolum-Oku $r.metin 'Yanıt'; if (-not $y) { $y = $is }; if (-not $y) { $y = Bolum-Oku $r.metin 'Gerekçe' }
            Yardim-Yanitla $G $y $donus $r "Engineering Manager yanıtladı (atama geçersizdi: '$kim')"
        }
        'ISE_ALIM' {
            $aranan = Alan-Oku $r.metin 'ARANAN'
            $is = Bolum-Oku $r.metin 'İş'; if (-not $is) { $is = [string]$G.yardim_istek }
            if (-not $aranan) { Yardim-Yanitla $G ((Bolum-Oku $r.metin 'Gerekçe') + "`n`n" + $is).Trim() $donus $r 'Engineering Manager yanıtladı'; break }
            [void](Yardim-Isleri-Ac $G @([pscustomobject]@{ kim = ''; baslik = (Alan-Oku $r.metin 'BASLIK'); is = $is; kabul = (Bolum-Oku $r.metin 'Kabul'); neden = $neden; aranan = $aranan }) "Engineering Manager ($isteyen istedi)" $donus)
        }
        'KULLANICI' {
            $k = Bolum-Oku $r.metin 'Kullanıcıya'; if (-not $k) { $k = Kirp $r.metin 1500 }
            Metin-Yaz (Join-Path $gk 'sorular.md') ("## $isteyen ekip içinde yardım istedi; Engineering Manager bunu sana soruyor`n`n**İstek:** $($G.yardim_istek)`n`n" + $k)
            Gecmis-Ekle $G 'Engineering Manager yardım isteğini sana sordu' '' $r
            Ayarla $G 'soru_donus_asama' $donus
            $G.asama = 'bekliyor_kullanici'
            $G.deneme = 0
            Ayarla $G 'soru_zamani' (Simdi)
            Bildir -Baslik "Engineering Manager soru soruyor: $($G.baslik)" -Metin (Gizli-Maskele ('#{0}: {1} Yanıtını panelden ver; iş kaldığı yerden sürer.' -f (No-Kisa $G.id), (Kisalt $k 140))) -Anahtar "soru-$($G.id)" -Onem 'yuksek'
        }
        'YANIT' {
            $y = Bolum-Oku $r.metin 'Yanıt'; if (-not $y) { $y = Bolum-Oku $r.metin 'İş' }; if (-not $y) { $y = Kirp $r.metin 2000 }
            Yardim-Yanitla $G $y $donus $r 'Engineering Manager yanıtladı'
        }
        default {
            Metin-Yaz (Join-Path $gk 'yardim-karar-gecersiz.md') $r.metin
            Adim-Basarisiz $G "Yardım kararında geçerli bir KARAR satırı yok ($($r.arac))"
        }
    }
}

# ---------------------------------------------------------------- birlikte çalışma (anlık yardım)
# Engineering Manager kısa bir isteği (paket kurma, internetten belge indirme, kodu çalıştırma / test, servis kontrolü, kısa görüş)
# bir ekip arkadaşına verir: o kişi HEMEN, bu adımın içinde, isteyenin çalışma klasöründe ve kendi yetkisiyle çalışır.
# Ayrı iş açılmaz; sonuç yardim-sonuclari.md'ye yazılır ve görev dönüş aşamasından (isteyenle) sürer.
function Yardim-Birlikte-Uygun([string]$Kim, [string]$Isteyen) {
    if (-not $Kim -or $Kim -eq $Isteyen -or @('lider', 'sorun-giderici', 'ik', 'yok') -contains $Kim) { return $false }
    return [bool](Kadro-Uye $Kim)
}
# İndirilen dosyalar .ekip-yardim\ altına konur; yazılım işinde git bunu görmesin (commit'e, kontrol adımına girmesin)
function Yardim-Klasorunu-Gizle([string]$Wt) {
    if (-not (Test-Path -LiteralPath (Join-Path $Wt '.git'))) { return }
    $ortak = ([string](Git-Calistir $Wt @('rev-parse', '--git-common-dir') -Sessiz)).Trim()
    if (-not $ortak -or $script:GitKod -ne 0) { return }
    if (-not [IO.Path]::IsPathRooted($ortak)) { $ortak = Join-Path $Wt $ortak }
    $info = Join-Path $ortak 'info'
    if (-not (Test-Path -LiteralPath $info)) { New-Item -ItemType Directory -Force $info | Out-Null }
    $ex = Join-Path $info 'exclude'
    $m = Metin-Oku $ex
    if ($m -notmatch '(?m)^/?\.ekip-yardim/?\s*$') { [IO.File]::AppendAllText($ex, "`n.ekip-yardim/`n", $Utf8) }
}
function Yardim-Birlikte-Calis($G, [string]$Kim, [string]$Is, [string]$Kabul, [string]$Donus, $R) {
    $gk = Gorev-Klasoru $G.id
    $n = [int]$G.yardim_sayisi
    $uye = Kadro-Uye $Kim
    $isteyen = Rol-Ad ([string]$G.yardim_isteyen)
    $wt = [string]$G.calisma_klasoru
    if (-not $wt -or -not (Test-Path -LiteralPath $wt)) { $wt = $gk }
    $yk = Join-Path $wt '.ekip-yardim'
    if (-not (Test-Path -LiteralPath $yk)) { New-Item -ItemType Directory -Force $yk | Out-Null }
    try { Yardim-Klasorunu-Gizle $wt } catch { Gunluk "Yardım klasörü git'ten gizlenemedi: $($_.Exception.Message)" 'UYARI' }
    $yetki = [string]$uye.yetki; if (-not $YetkiMetinleri.ContainsKey($yetki)) { $yetki = 'oku' }
    $talimat = Rol-Talimati $uye
    if ($yetki -eq 'tam' -and $Ayar.altyapi) { $talimat += "`n`n## Ortam`n`n" + (Altyapi-Ortam) }
    if (-not $Kabul) { $Kabul = '(belirtilmedi: istenen iş yapılmış ve sonucu raporda açıkça yazılı olmalı)' }
    $istem = Sablon-Doldur 'yardim-birlikte.md' @{
        ROL_ADI = [string]$uye.ad; ROL_TALIMATI = $talimat; YETKI = $YetkiMetinleri[$yetki]; ISTEYEN = $isteyen
        CALISMA = $wt; YARDIM_KLASORU = $yk; IS = $Is; KABUL = $Kabul
        ISTEK = (Metin-Oku (Join-Path $gk "yardim-istek-$n.md")); DURUM = (Yardim-Durum-Metni $G); GOREV = (Kirp (Gorev-Metni $G) 4000)
    }
    Gecmis-Ekle $G "Engineering Manager $($uye.ad) ile birlikte çalışmayı başlattı" (Kisalt $Is 300) $R
    $p = @{ Rol = $Kim; Istem = $istem; Klasor = $wt; KayitKlasoru = (Kayit-Klasoru $G); Etiket = "birlikte-$Kim" }
    if ($yetki -eq 'tam') { $p.TamYetki = $true } elseif ($yetki -eq 'yaz') { $p.Yazabilir = $true }
    Gunluk "Görev $($G.id): $($uye.ad) birlikte çalışıyor ($isteyen istedi): $(Kisalt $Is 120)"
    $y = Ajan-Cagir @p
    if ($y.iptal) { return }   # görev iptal edildi ya da panoda taşındı; Gorev-Ilerlet diskteki kaydı korur
    $liste = @(); if ($G.birlikte) { $liste = @($G.birlikte) }
    $liste += [pscustomobject][ordered]@{ rol = $Kim; isteyen = [string]$G.yardim_isteyen; zaman = (Simdi); basarili = [bool]$y.basarili; arac = ('{0}/{1}' -f $y.arac, $y.model) }
    Ayarla $G 'birlikte' @($liste)
    if (-not $y.basarili) {
        $h = Kisalt ([string]$y.hata) 300
        Yardim-Sonucu-Ekle $G ('{0} birlikte çalışamadı (yardım isteği {1})' -f $uye.ad, $n) "Yardım yapılamadı: $h`n`nElinden gelen kısmı yap ya da başka bir yol dene; gerekiyorsa yeniden yardım iste."
        Asama-Gec $G $Donus "$($uye.ad) birlikte çalışamadı" $h
        return
    }
    Metin-Yaz (Join-Path $gk "yardim-birlikte-$n.md") (("# Birlikte çalışma · yardım isteği {0} · {1} · {2} · {3}/{4}" -f $n, $uye.ad, (Get-Date).ToString('dd.MM.yyyy HH:mm'), $y.arac, $y.model) + "`n`n" + $y.metin)
    Yardim-Sonucu-Ekle $G ('{0} ile birlikte çalışıldı (yardım isteği {1}: {2})' -f $uye.ad, $n, (Kisalt ([string]$G.yardim_istek) 120)) ((Kirp (Gizli-Maskele $y.metin) 6000) + "`n`nİndirilen / üretilen dosyalar: $yk")
    $ozet = Bolum-Oku $y.metin 'Sonuç'; if (-not $ozet) { $ozet = $y.metin }
    Asama-Gec $G $Donus "$($uye.ad) birlikte çalıştı; $isteyen sürüyor" (Kisalt $ozet 200) $y
}

# Yardım işleri biten görevleri dönüş aşamasından sürdürür (döngü her turda çağırır)
function Yardim-Bekleyenleri-Kontrol {
    $liste = @(Gorevleri-Listele)
    $dizin = @{}; foreach ($x in $liste) { $dizin[[string]$x.id] = $x }
    foreach ($g in $liste) {
        if ([string]$g.asama -ne 'yardim_bekliyor') { continue }
        $bitti = $true
        $sonuclar = @()
        foreach ($id in @($g.yardim_bekleyen | Where-Object { $_ })) {
            $y = $dizin[[string]$id]
            if (-not $y) { $sonuclar += [pscustomobject]@{ id = [string]$id; baslik = ''; durum = 'bulunamadı'; metin = 'Yardım işi bulunamadı.' }; continue }
            switch ([string]$y.asama) {
                'tamam' {
                    $s = Metin-Oku (Join-Path (Gorev-Klasoru $y.id) 'sonuc.md')
                    $metin = ([string]$y.ozet + "`n`n" + (Kirp (Gizli-Maskele $s) 3500)).Trim()
                    if (-not $metin) { $metin = 'Yardım işi tamamlandı.' }
                    $sonuclar += [pscustomobject]@{ id = $y.id; baslik = $y.baslik; durum = 'tamamlandı'; metin = "$metin`n`nAyrıntılar: gorevler\$($y.id) ve çalışma klasörü calisma\$($y.id)" }
                }
                'iptal' { $sonuclar += [pscustomobject]@{ id = $y.id; baslik = $y.baslik; durum = 'iptal edildi'; metin = 'Bu yardım işi iptal edildi; yardım gelmedi. Elinden gelen kısmı yap ya da başka bir yol dene.' } }
                default { $bitti = $false }
            }
        }
        if (-not $bitti) { continue }
        foreach ($s in $sonuclar) { Yardim-Sonucu-Ekle $g ('Yardım işi #{0} {1}: {2}' -f (No-Kisa $s.id), $s.durum, $s.baslik) $s.metin }
        $donus = Yardim-Donus-Asamasi $g
        Ayarla $g 'yardim_bekleyen' @()
        Asama-Gec $g $donus 'yardım geldi' (($sonuclar | ForEach-Object { '#{0} {1}' -f (No-Kisa $_.id), $_.durum }) -join ', ')
        Gorev-Kaydet $g
        Gunluk "Görev $($g.id): yardım işleri bitti; '$donus' aşamasından sürüyor"
    }
}

# Engineering Managerʼın planındaki ön işler: "YARDIM: <anahtar> | <iş>"
function Plan-Yardimlari($G, [string]$Metin) {
    $l = @()
    $a = Yardimlasma-Ayari
    if (-not $a.etkin) { return , $l }
    if ((Yardim-Derinligi $G) -ge $a.derinlik) { return , $l }
    foreach ($m in [regex]::Matches([string]$Metin, '(?m)^\W{0,4}YARDIM\W{0,4}\s*([A-Za-z0-9-]+)\s*[|:]\s*(.+?)\s*$')) {
        $kim = Kadro-Anahtar-Coz $m.Groups[1].Value
        $is = $m.Groups[2].Value.Trim().Trim('`', '*', ' ')
        if (-not (Yardim-Atanabilir $kim) -or -not $is -or $is.StartsWith('<')) { Gunluk "Plan yardım satırı atlandı: $($m.Value.Trim())" 'UYARI'; continue }
        $l += [pscustomobject]@{ kim = $kim; baslik = (Kisalt $is 90); is = $is; kabul = ''; neden = 'Engineering Manager planında, iş başlamadan önce gereken ön iş olarak istedi.'; aranan = '' }
        if ($l.Count -ge 3) { break }
    }
    return , $l
}

# ---------------------------------------------------------------- QA Engineer
# Testçi test edilen git ağacında değişiklik bıraktıysa geri alır: Full-Stack Developerʼın işi index'tedir (kontrol / diff adımları
# "git add -A" yaptı); index'e eklenmemiş değişiklikler ve izlenmeyen (yok sayılmayan) dosyalar testçinindir.
function Test-Sonrasi-Agaci-Temizle([string]$Wt) {
    $degisen = Git-Calistir $Wt @('diff', '--name-only') -Sessiz                         # index'e göre değişen izlenen dosyalar
    $yeni = Git-Calistir $Wt @('ls-files', '--others', '--exclude-standard') -Sessiz     # izlenmeyen, yok sayılmayan dosyalar
    $kirli = @((([string]$degisen + "`n" + [string]$yeni) -split "`n") | Where-Object { $_.Trim() -and $_ -notmatch '^(warning|hint|error|fatal):' })   # git uyarıları (LF/CRLF) sayılmaz
    if (-not $kirli.Count) { return 0 }
    Git-Calistir $Wt @('checkout', '--', '.') -Sessiz | Out-Null
    Git-Calistir $Wt @('clean', '-fdq') -Sessiz | Out-Null
    Gunluk "Test sonrası çalışma ağacı temizlendi ($($kirli.Count) değişiklik geri alındı): $Wt" 'UYARI'
    return $kirli.Count
}
function Tester-Calistir($G, $Uye, [string]$Tk, [string]$Calisma, [string]$Icerik, [string]$Onceki, [string]$Etiket, [string[]]$Haric = @()) {
    $testKl = Join-Path $YolCalisma ('{0}-test' -f $G.id)
    if (-not (Test-Path -LiteralPath $testKl)) { New-Item -ItemType Directory -Force $testKl | Out-Null }
    $talimat = Rol-Talimati $Uye
    $yetki = [string]$Uye.yetki
    if ($yetki -eq 'tam' -and $Ayar.altyapi) { $talimat += "`n`n## Ortam`n`n" + (Altyapi-Ortam) }
    $istem = Sablon-Doldur 'tester-inceleme.md' @{
        ROL_ADI = [string]$Uye.ad; ROL_TALIMATI = $talimat; CALISMA = $Calisma; TEST_KLASORU = $testKl
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G); ICERIK = $Icerik; ONCEKI = $Onceki
    }
    $p = @{ Rol = [string]$Uye.anahtar; Istem = $istem; Klasor = $testKl; KayitKlasoru = $Tk; Etiket = $Etiket; Haric = $Haric }
    if ($yetki -eq 'tam') { $p.TamYetki = $true } elseif ($yetki -eq 'yaz') { $p.Yazabilir = $true }
    $wt = [string]$G.calisma_klasoru
    $r = Ajan-Cagir @p
    if ($wt -and (Test-Path -LiteralPath (Join-Path $wt '.git'))) { [void](Test-Sonrasi-Agaci-Temizle $wt) }
    if ($r.basarili) { Metin-Yaz (Join-Path $Tk 'test-raporu.md') $r.metin }
    return $r
}
