<#
yonlendirme.ps1 - Türü seçilmeden verilen işler (durum.json > tip = "genel"; panelde "İş ver", is-ver.ps1). ekip.ps1 dot-source eder.

Önce Product Manager talebi netleştirir (aşama analiz; gereksinimler.md, planlama.ps1 > Adim-Analiz; ayarlar.json > planlama.analiz).
Sonra iş Engineering Managerʼa gelir (rol anahtarı: lider). Engineering Manager işi ve gereksinimleri okur, kimin yapacağına karar verir:
  YAZILIM   yazılım akışı: kayıtlı bir proje seçer ya da YENI_PROJE ile boş bir git deposu açtırır
  ALTYAPI   System Administrator + Network Engineer (HEDEF: makineler)
  UZMAN     kadrodan SORUMLU (uzman akışı; Engineering Manager orada brifi yazar ve inceleyeni seçer)
  ISE_ALIM  İK önce işe alır, iş uzman akışında yeni çalışana verilir
  SORU_VAR  kullanıcıya soru; yanıt gelince (aşama plan) yeniden yönlendirir
Karardan sonra görev seçilen akışın 'yeni' aşamasına geçer; Engineering Managerʼın gerekçesi gorev.md'ye eklenir.
#>

function Bolum-Oku([string]$Metin, [string]$Baslik) {
    $m = [regex]::Match([string]$Metin, '(?ms)^#{1,3}\s*' + [regex]::Escape($Baslik) + '\s*$\r?\n(.*?)(?=^#{1,3}\s|\z)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
function Kirp([string]$Metin, [int]$Uzunluk = 3000) {
    if (-not $Metin) { return '' }
    if ($Metin.Length -le $Uzunluk) { return $Metin }
    return $Metin.Substring(0, $Uzunluk) + "`n… (kırpıldı)"
}
function No-Kisa([string]$Id) { return ([string]$Id -split '-')[0] }
function Deger-Temizle([string]$Metin) { return ([string]$Metin).Trim().Trim('`', '"', '''', '*', '<', '>', ' ') }

function Projeler-Metni {
    $p = Projeleri-Yukle
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('| Ad | Klasör |')
    [void]$sb.AppendLine('|---|---|')
    $n = 0
    foreach ($x in @($p.projeler)) { if ($x -and $x.ad) { $n++; [void]$sb.AppendLine(('| {0} | {1} |' -f $x.ad, $x.klasor)) } }
    if ($n -eq 0) { [void]$sb.AppendLine('| (kayıtlı proje yok) | |') }
    return $sb.ToString()
}
function Makineler-Metni {
    $l = @()
    if ($Ayar.altyapi) { foreach ($m in @($Ayar.altyapi.makineler)) { if ($m) { $l += ('- {0} ({1}): {2}' -f $m.ad, $m.ip, (Kisalt ([string]$m.aciklama) 140)) } } }
    if (-not $l.Count) { return '(tanımlı makine yok)' }
    return ($l -join "`n")
}
function Hedef-Coz([string]$Metin) {
    $bilinen = @(); if ($Ayar.altyapi) { $bilinen = @($Ayar.altyapi.makineler | Where-Object { $_ } | ForEach-Object { [string]$_.ad }) }
    $l = @()
    foreach ($p in (([string]$Metin) -split '[,;/]+')) {
        $t = Deger-Temizle $p
        foreach ($b in $bilinen) { if ($b -ieq $t -and $l -notcontains $b) { $l += $b } }
    }
    return , $l
}
# Ad, kayıtlı bir proje ya da var olan bir git deposu klasörü olabilir (klasör yeni ise projeler.json'a kaydedilir; gorev-ekle.ps1 gibi)
function Proje-Coz([string]$Deger) {
    $d = Deger-Temizle $Deger
    if (-not $d) { return $null }
    $p = Proje-Bul $d
    if ($p) { return $p }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $null }
    $klasor = (Resolve-Path -LiteralPath $d).Path.TrimEnd('\')
    Git-Calistir $klasor @('rev-parse', '--show-toplevel') -Sessiz | Out-Null
    if ($script:GitKod -ne 0) { return $null }
    $pj = Projeleri-Yukle
    $p = [pscustomobject]@{ ad = (Split-Path $klasor -Leaf); klasor = $klasor; temel_dal = ''; dogrulama = @() }
    $pj.projeler = @($pj.projeler | Where-Object { $_ }) + $p
    Json-Yaz $pj (Join-Path $Kok 'projeler.json')
    Gunluk "Proje kaydedildi (Engineering Manager seçti): $($p.ad) ($klasor)"
    return $p
}
# Engineering Manager yeni bir depo istediğinde: ayarlar.json > gorev.yeni_proje_kok altında boş bir git deposu (AI Ekip kimliğiyle ilk commit)
function Yeni-Proje-Olustur([string]$Ad) {
    $slug = Slug (Deger-Temizle $Ad)
    $var = Proje-Bul $slug
    if ($var) { return $var }
    # Not: "$kok" adı betiğin $Kok değişkeniyle aynıdır (PowerShell büyük/küçük harf ayırmaz); başka ad kullan
    $projeKoku = [string]$Ayar.gorev.yeni_proje_kok
    if (-not $projeKoku) { $projeKoku = Join-Path $env:USERPROFILE 'ai-ekip-projeler' }
    $klasor = Join-Path $projeKoku $slug
    if (-not (Test-Path -LiteralPath $klasor)) { New-Item -ItemType Directory -Force $klasor | Out-Null }
    $ust = Git-Calistir $klasor @('rev-parse', '--show-toplevel') -Sessiz
    $kendiDeposu = ($script:GitKod -eq 0) -and ((([string]$ust) -replace '/', '\').TrimEnd('\') -ieq $klasor.TrimEnd('\'))
    if (-not $kendiDeposu) {
        if (@(Get-ChildItem -LiteralPath $klasor -Force -ErrorAction SilentlyContinue).Count -gt 0) { throw "Yeni proje klasörü boş değil ve bir git deposu değil: $klasor" }
        Git-Calistir $klasor @('init', '-q', '-b', 'main') | Out-Null
        Metin-Yaz (Join-Path $klasor 'README.md') ("# $slug`n`nAI Ekip bu depoyu {0} tarihinde açtı.`n" -f (Get-Date).ToString('dd.MM.yyyy'))
        Git-Calistir $klasor @('add', '-A') | Out-Null
        Git-Calistir $klasor @('-c', 'user.name=AI Ekip', '-c', 'user.email=ai-ekip@localhost', 'commit', '-q', '-m', 'Proje açıldı') | Out-Null
    }
    $pj = Projeleri-Yukle
    $p = [pscustomobject]@{ ad = $slug; klasor = $klasor; temel_dal = ''; dogrulama = @() }
    $pj.projeler = @($pj.projeler | Where-Object { $_ }) + $p
    Json-Yaz $pj (Join-Path $Kok 'projeler.json')
    Gunluk "Yeni proje açıldı: $slug ($klasor)"
    return $p
}
function Gorev-Notu-Ekle($G, [string]$Baslik, [string]$Metin) {
    $f = Join-Path (Gorev-Klasoru $G.id) 'gorev.md'
    Metin-Yaz $f ((Metin-Oku $f).TrimEnd() + "`n`n## $Baslik`n`n" + $Metin.Trim() + "`n")
}
function Yonlendirme-Bitir($G, [string]$Olay, [string]$Ayrinti, $Sonuc, [string]$Not) {
    Ayarla $G 'yonlendiren' ('{0}/{1}' -f $Sonuc.arac, $Sonuc.model)
    Ayarla $G 'yonlendirme_karari' (Karar-Oku $Sonuc.metin)
    if ($Not) { Gorev-Notu-Ekle $G 'Engineering Managerʼın yönlendirmesi' $Not }
    Asama-Gec $G 'yeni' $Olay $Ayrinti $Sonuc
}

function Yonetici-Yonlendir($G) {
    $gk = Gorev-Klasoru $G.id
    $istem = Sablon-Doldur 'yonetici-yonlendirme.md' @{ KADRO = (Kadro-Metni); PROJELER = (Projeler-Metni); MAKINELER = (Makineler-Metni); GOREV = (Gorev-Metni $G) }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor $gk -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'yonlendirme'
    if (-not $r.basarili) { Adim-Basarisiz $G "Engineering Manager işi yönlendiremedi: $($r.hata)"; return }
    Ayarla $G 'lider' ('{0}/{1}' -f $r.arac, $r.model)
    Metin-Yaz (Join-Path $gk 'yonlendirme.md') $r.metin
    $gerekce = Kirp (Bolum-Oku $r.metin 'Gerekçe') 1200
    switch (Karar-Oku $r.metin) {
        'YAZILIM' {
            $p = $null
            $ad = Alan-Oku $r.metin 'PROJE'
            if ($ad) { $p = Proje-Coz $ad }
            if (-not $p -and $G.ipucu) { $p = Proje-Coz ([string]$G.ipucu) }
            if (-not $p) {
                $yeni = Alan-Oku $r.metin 'YENI_PROJE'
                if (-not $yeni) {
                    Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin
                    Adim-Basarisiz $G "Engineering Manager yazılım işi dedi ama geçerli bir proje vermedi (PROJE: '$ad')"
                    return
                }
                $p = Yeni-Proje-Olustur $yeni
            }
            Ayarla $G 'tip' 'yazilim'
            $G.proje = [string]$p.ad
            $G.klasor = [string]$p.klasor
            Yonlendirme-Bitir $G 'Engineering Manager yazılım ekibine verdi' "proje: $($p.ad)" $r ("Yazılım ekibine verildi; proje: $($p.ad) (``$($p.klasor)``).`n`n$gerekce")
        }
        'ALTYAPI' {
            $hedef = Hedef-Coz (Alan-Oku $r.metin 'HEDEF')
            Ayarla $G 'tip' 'altyapi'
            $G.proje = 'altyapı'
            $G.klasor = ''
            Ayarla $G 'hedef' @($hedef)
            $h = '(Engineering Manager planda belirleyecek)'; if ($hedef.Count) { $h = $hedef -join ', ' }
            Yonlendirme-Bitir $G 'Engineering Manager altyapı ekibine verdi' "hedef: $h" $r ("System Administrator + Network Engineer ekibine verildi; hedef makineler: $h.`n`n$gerekce")
        }
        'UZMAN' {
            $sorumlu = Kadro-Anahtar-Coz (Alan-Oku $r.metin 'SORUMLU')
            $u = Kadro-Uye $sorumlu
            if (-not $u -or -not $u.uzman_isi) { $sorumlu = '' }
            Ayarla $G 'tip' 'uzman'
            $G.proje = 'uzman'
            $G.klasor = ''
            Ayarla $G 'hedef_rol' $sorumlu
            $pa = Alan-Oku $r.metin 'PROJE'
            $pp = $null; if ($pa) { $pp = Proje-Bul (Deger-Temizle $pa) }
            if ($pp) { Ayarla $G 'kaynak_klasor' ([string]$pp.klasor) }
            elseif ($G.ipucu -and (Test-Path -LiteralPath ([string]$G.ipucu) -PathType Container)) { Ayarla $G 'kaynak_klasor' ((Resolve-Path -LiteralPath ([string]$G.ipucu)).Path) }
            $kim = '(Engineering Manager uzman akışında seçecek)'; if ($u -and $sorumlu) { $kim = "$($u.ad) ($sorumlu)" }
            Yonlendirme-Bitir $G 'Engineering Manager uzmana verdi' "sorumlu: $kim" $r ("Uzman işi olarak verildi; sorumlu: $kim.`n`n$gerekce")
        }
        'ISE_ALIM' {
            $aranan = Alan-Oku $r.metin 'ARANAN'
            if (-not $aranan) { $aranan = Kisalt $r.metin 500 }
            Ayarla $G 'tip' 'uzman'
            $G.proje = 'uzman'
            $G.klasor = ''
            Ayarla $G 'ise_alim_aranan' $aranan
            Ayarla $G 'ise_alim_sayisi' 1
            Yonlendirme-Bitir $G 'Engineering Manager İK''dan işe alım istedi' $aranan $r ("Kadroda bu işi yapabilecek kimse yok; HR Specialist işe alım yapacak. Aranan: $aranan`n`n$gerekce")
        }
        'SORU_VAR' { Altyapi-Soru $G $r.metin $r 'Engineering Manager soru sordu' }
        default {
            Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin
            Adim-Basarisiz $G "Yönlendirme çıktısında geçerli bir KARAR satırı yok ($($r.arac))"
        }
    }
}

function Genel-Adim($G) {
    # Gereksinimler henüz netleşmediyse önce Product Manager (planlama.ps1); 'analiz' aşamasını ekip.ps1 > Gorev-Ilerlet-Adim yürütür
    if (Analiz-Gerekli $G) { Asama-Gec $G 'analiz' 'Product Manager talebi netleştirecek'; return }
    # 'yeni' ilk yönlendirme; 'plan' gereksinimler hazır ya da kullanıcı soruyu yanıtladıktan sonra (Bekleyenleri-Kontrol) yönlendirme
    Yonetici-Yonlendir $G
}
