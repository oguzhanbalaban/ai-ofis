<#
yonetim.ps1 - Yönetim katmanı: CTO (anahtar cto). ekip.ps1 dot-source eder.

Engineering Manager tek tek işleri yönetir; CTO sistemi yönetir. Ofis boştayken (sırada iş yokken) ayarlar.json > yonetim.aralik_saat
saatte bir ve son değerlendirmeden beri biten / takılan / iptal edilen iş varsa (ya da panelden "Değerlendirme iste" denince)
yönetim değerlendirmesi yapar:
  - Rapor: durum\yonetim\degerlendirme-<yyyyMMdd-HHmm>.md (panelde Yönetim bölümü). Girdi: dönemin iş sonuçları, yeni tura dönme /
    takılma / iptal nedenleri, kök nedenler, kuyruk, token ve limit kullanımı, birleştirilmemiş ekip dalları, kadro.
  - Ekip ilkeleri: durum\yonetim\ekip-ilkeleri.md. Ekibin önceki işlerden öğrendikleri; ortak.ps1 > Ilkeler-Istem-Metni her iş
    isteminde "EKİP İLKELERİ" olarak bütün çalışanlara verir (öğrenen organizasyon).
  - Öncelik: sıradaki, başlamamış işlerin önceliği ("ONCELIK: <no> | <1-3>").
  - Öneriler: ```is {json}``` blokları kendiliğinden iş açmaz; panelde kullanıcı "İş ver"e aktarıp onaylar.
Başarısız değerlendirme 2 saat sonra yeniden denenir; döngüyü hata döngüsüne sokmaz.
#>

$script:YolYonetim = Join-Path $YolDurum 'yonetim'
function Yonetim-Ayari {
    $o = [ordered]@{ etkin = $true; aralik_saat = 24; en_az_biten = 1; ilke_siniri = 15 }
    $a = $Ayar.yonetim
    if ($a) { foreach ($k in @($o.Keys)) { if ($a.PSObject.Properties[$k] -and $null -ne $a.$k) { $o[$k] = $a.$k } } }
    $o.etkin = [bool]$o.etkin
    foreach ($k in @('aralik_saat', 'en_az_biten', 'ilke_siniri')) { $o[$k] = [Math]::Max(1, [int]$o[$k]) }
    return [pscustomobject]$o
}
function Yonetim-Klasoru {
    if (-not (Test-Path -LiteralPath $YolYonetim)) { New-Item -ItemType Directory -Force $YolYonetim | Out-Null }
    return $YolYonetim
}
function Yonetim-Son { Json-Oku (Join-Path $YolYonetim 'son.json') }
function Yonetim-Istek-Yolu { Join-Path $YolYonetim 'istek' }
function Tarih-Oku($Deger) { if (-not $Deger) { return $null }; try { return [datetime][string]$Deger } catch { return $null } }

# Değerlendirme zamanı geldi mi? (istek varsa hemen; yoksa aralık dolmuş ve o zamandan beri iş bitmiş / takılmış / iptal edilmiş olmalı)
function Yonetim-Degerlendirmesi-Gerekli {
    $ay = Yonetim-Ayari
    if (-not $ay.etkin -or -not (Rol-Hazir-mi 'cto')) { return $false }
    if (Test-Path -LiteralPath (Yonetim-Istek-Yolu)) { return $true }
    $son = Yonetim-Son
    $sonZaman = $null; if ($son) { $sonZaman = Tarih-Oku $son.zaman }
    if ($sonZaman) {
        $aralik = [double]$ay.aralik_saat; if ([string]$son.durum -eq 'basarisiz') { $aralik = 2 }
        if (((Get-Date) - $sonZaman).TotalHours -lt $aralik) { return $false }
    }
    $sinir = $sonZaman; if (-not $sinir) { $sinir = (Get-Date).AddDays(-7) }
    $biten = @(Gorevleri-Listele | Where-Object { @('tamam', 'iptal', 'takildi') -contains [string]$_.asama -and (Tarih-Oku $_.guncelleme) -gt $sinir })
    return ($biten.Count -ge $ay.en_az_biten)
}

# ---------------------------------------------------------------- girdiler (betik hesaplar; yapay zeka üretmez)
function Yonetim-Donem-Basi($Son) {
    $bas = (Get-Date).AddDays(-7)
    if ($Son) { $t = Tarih-Oku $Son.zaman; if ($t -and $t -gt (Get-Date).AddDays(-14)) { $bas = $t } }
    return $bas
}
function Yonetim-Metrikleri([datetime]$Bas) {
    $sb = New-Object Text.StringBuilder
    $gorevler = @(Gorevleri-Listele)
    $donem = @($gorevler | Where-Object { (Tarih-Oku $_.guncelleme) -ge $Bas })
    [void]$sb.AppendLine(('Dönem: {0} – {1} ({2} işte hareket var; toplam {3} iş kaydı)' -f $Bas.ToString('dd.MM.yyyy HH:mm'), (Get-Date).ToString('dd.MM.yyyy HH:mm'), $donem.Count, $gorevler.Count))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Durumlara göre (bu dönem)')
    foreach ($grp in @($donem | Group-Object { [string]$_.asama } | Sort-Object Count -Descending)) { [void]$sb.AppendLine(('- {0}: {1}' -f (Asama-Adi $grp.Name), $grp.Count)) }
    $biten = @($donem | Where-Object { $_.asama -eq 'tamam' })
    if ($biten.Count) {
        $ort = [Math]::Round((($biten | Measure-Object -Property tur -Average).Average), 2)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## Tamamlanan işler (ortalama tur: $ort)")
        foreach ($g in ($biten | Sort-Object { [string]$_.guncelleme } | Select-Object -Last 15)) {
            $sure = ''; $a = Tarih-Oku $g.olusturma; $b = Tarih-Oku $g.guncelleme; if ($a -and $b) { $sure = ', {0:N1} saat' -f ($b - $a).TotalHours }
            $puan = ''; if ($g.puan_yonetici) { $puan += " · EM puanı $($g.puan_yonetici.puan)" }; if ($g.puan_ajan) { $puan += " · çalışan puanı $($g.puan_ajan.puan)" }
            $tip = [string]$g.tip; if (-not $tip) { $tip = 'yazilim' }
            [void]$sb.AppendLine(('- #{0} {1} [{2}] {3} tur{4}{5}' -f (No-Kisa $g.id), (Kisalt ([string]$g.baslik) 70), $tip, $g.tur, $sure, $puan))
        }
    }
    $donus = New-Object Collections.Generic.List[string]; $takilma = New-Object Collections.Generic.List[string]
    $yardim = 0; $tasima = 0; $komut = 0
    foreach ($g in $donem) {
        foreach ($e in @($g.gecmis)) {
            if (-not $e -or (Tarih-Oku $e.zaman) -lt $Bas) { continue }
            $o = [string]$e.olay
            if ($o -eq 'yeni tura dönüldü') { $donus.Add(('- #{0}: {1}' -f (No-Kisa $g.id), (Kisalt ([string]$e.ayrinti) 170))) }
            elseif ($o -eq 'takıldı') { $takilma.Add(('- #{0}: {1}' -f (No-Kisa $g.id), (Kisalt ([string]$e.ayrinti) 170))) }
            elseif ($o -match 'yardım istedi') { $yardim++ }
            elseif ($o -match '^kullanıcı panoda taşıdı') { $tasima++ }
            elseif ($o -match '^kullanıcı komut verdi') { $komut++ }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Yeni tura dönüşler ($($donus.Count))")
    if ($donus.Count) { foreach ($s in ($donus | Select-Object -Last 12)) { [void]$sb.AppendLine($s) } } else { [void]$sb.AppendLine('- yok') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Takılmalar ($($takilma.Count))")
    if ($takilma.Count) { foreach ($s in ($takilma | Select-Object -Last 10)) { [void]$sb.AppendLine($s) } } else { [void]$sb.AppendLine('- yok') }
    $iptal = @($donem | Where-Object { $_.asama -eq 'iptal' })
    if ($iptal.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## İptaller ($($iptal.Count))")
        foreach ($g in $iptal) { $k = ''; if ($g.kok_neden) { $k = " — kök neden: $($g.kok_neden.kategori) ($(Kisalt ([string]$g.kok_neden.alt) 100))" }; [void]$sb.AppendLine(('- #{0} {1}{2}' -f (No-Kisa $g.id), (Kisalt ([string]$g.baslik) 70), $k)) }
    }
    $kok = @($donem | Where-Object { $_.kok_neden } | Group-Object { [string]$_.kok_neden.kategori })
    if ($kok.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Kök neden kategorileri (Incident Manager)')
        foreach ($k in ($kok | Sort-Object Count -Descending)) { [void]$sb.AppendLine(('- {0}: {1}' -f $k.Name, $k.Count)) }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('## Ekip içi yardım ve kullanıcı müdahalesi: {0} yardım isteği, {1} panoda elle taşıma, {2} doğrudan komut' -f $yardim, $tasima, $komut))
    return $sb.ToString()
}
function Yonetim-Kuyrugu {
    $l = @(Gorevleri-Listele | Where-Object { ($AktifAsamalar -contains [string]$_.asama) -or @('takildi', 'bekliyor_kullanici', 'yardim_bekliyor') -contains [string]$_.asama })
    if (-not $l.Count) { return '(sırada ya da süren iş yok)' }
    $sb = New-Object Text.StringBuilder
    foreach ($g in ($l | Sort-Object @{ e = { [int]$_.oncelik } }, @{ e = { $_.id } })) {
        $bas = ''; if ([string]$g.asama -eq 'yeni') { $bas = ' · BAŞLAMADI (öncelik değiştirilebilir)' }
        $yas = ''; $a = Tarih-Oku $g.olusturma; if ($a) { $yas = ' · {0:N0} saattir' -f ((Get-Date) - $a).TotalHours }
        $tip = [string]$g.tip; if (-not $tip) { $tip = 'yazilim' }
        [void]$sb.AppendLine(('- #{0} {1} · {2} · öncelik {3} · {4}{5}{6}' -f (No-Kisa $g.id), (Kisalt ([string]$g.baslik) 70), (Asama-Adi $g.asama), $g.oncelik, $tip, $yas, $bas))
    }
    return $sb.ToString()
}
function Yonetim-Kullanim([datetime]$Bas) {
    $sb = New-Object Text.StringBuilder
    $s = Sayac-Oku
    foreach ($a in @('claude', 'codex')) {
        $sinir = 0; if ($Ayar.gunluk_sinir -and $Ayar.gunluk_sinir.PSObject.Properties[$a]) { $sinir = [int]$Ayar.gunluk_sinir.$a }
        $kul = 0; if ($s -and $s.PSObject.Properties[$a]) { $kul = [int]$s.$a }
        [void]$sb.AppendLine(('- {0}: bugün {1}/{2} çağrı' -f $a, $kul, $sinir))
    }
    $roller = @{}
    $kl = Join-Path $YolDurum 'kullanim'
    $basMetin = $Bas.ToString('yyyy-MM-ddTHH:mm')
    foreach ($f in @(Get-ChildItem -LiteralPath $kl -Filter 'kullanim-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 2)) {
        foreach ($satir in ((Metin-Oku $f.FullName) -split "`n")) {
            $m = [regex]::Match($satir, '"zaman":"([^"]{16})')
            if (-not $m.Success -or [string]::CompareOrdinal($m.Groups[1].Value, $basMetin) -lt 0) { continue }
            $k = $null; try { $k = $satir | ConvertFrom-Json } catch { continue }
            $r = [string]$k.rol
            if (-not $roller.ContainsKey($r)) { $roller[$r] = [pscustomobject]@{ cagri = 0; basarisiz = 0; token = [long]0 } }
            $roller[$r].cagri++
            if (-not $k.basarili) { $roller[$r].basarisiz++ }
            $roller[$r].token += [long]$k.toplam
        }
    }
    if ($roller.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Dönemde rol başına ajan çağrısı (çağrı / başarısız / token):')
        foreach ($p in ($roller.GetEnumerator() | Sort-Object { $_.Value.token } -Descending | Select-Object -First 14)) {
            [void]$sb.AppendLine(('- {0}: {1} / {2} / {3:N0}' -f (Calisan-Adi $p.Key), $p.Value.cagri, $p.Value.basarisiz, $p.Value.token))
        }
    }
    return $sb.ToString()
}
function Yonetim-Dallari {
    $sb = New-Object Text.StringBuilder
    $p = Projeleri-Yukle
    foreach ($x in @($p.projeler)) {
        if (-not $x -or -not $x.klasor -or -not (Test-Path -LiteralPath (Join-Path ([string]$x.klasor) '.git'))) { continue }
        $ana = ([string](Git-Calistir ([string]$x.klasor) @('symbolic-ref', '--short', 'HEAD') -Sessiz)).Trim()
        if (-not $ana -or $script:GitKod -ne 0) { continue }
        $dallar = @(([string](Git-Calistir ([string]$x.klasor) @('branch', '--list', 'ekip/*', '--no-merged', $ana) -Sessiz)) -split "`n" |
            ForEach-Object { $_.Trim(' ', '*', '+') } | Where-Object { $_ -like 'ekip/*' })
        if ($dallar.Count) { [void]$sb.AppendLine(('- {0} ({1}): {2} dal birleştirilmeyi bekliyor: {3}' -f $x.ad, $ana, $dallar.Count, (($dallar | Select-Object -First 6) -join ', '))) }
    }
    if (-not $sb.Length) { return '(birleştirilmeyi bekleyen ekip dalı yok)' }
    return ($sb.ToString() + "`nEkip dalları kullanıcı birleştirene kadar ana dala girmez (push / merge kullanıcının kararı).")
}

# ---------------------------------------------------------------- çıktıyı işleme
function Yonetim-Oneri-Dogrula($O) {
    $baslik = ([string]$O.baslik).Trim()
    if (-not $baslik -or $baslik.StartsWith('...') -or $baslik -eq 'kısa başlık') { return $null }   # şablon örneği öneri sayılmaz
    $s = [ordered]@{ baslik = (Kisalt $baslik 120); aciklama = (Kisalt ([string]$O.aciklama).Trim() 4000); oncelik = 2 }
    if (@(1, 2, 3) -contains [int]$O.oncelik) { $s.oncelik = [int]$O.oncelik }
    $rol = ([string]$O.rol).Trim(); if ($rol -and (Kadro-Uye $rol)) { $s.rol = $rol }
    if ($O.proje) { $s.proje = Kisalt ([string]$O.proje).Trim() 200 }
    if ($O.kabul) { $s.kabul = @(@($O.kabul) | ForEach-Object { Kisalt ([string]$_).Trim() 300 } | Where-Object { $_ } | Select-Object -First 10) }
    # Panelde gösterim için (iş "İş ver" ile verilir; türüne yine Engineering Manager karar verir)
    $s.tur = 'genel'; if ($s.Contains('rol')) { $s.tur = 'uzman' } elseif ($s.Contains('proje')) { $s.tur = 'yazilim' }
    return $s
}
function Yonetim-Onerileri([string]$Metin) {
    $l = @()
    foreach ($m in [regex]::Matches([string]$Metin, '(?s)```is\s*(\{.*?\})\s*```')) {
        $o = $null; try { $o = Yonetim-Oneri-Dogrula ($m.Groups[1].Value | ConvertFrom-Json) } catch {}
        if ($o) { $l += [pscustomobject]$o }
        if ($l.Count -ge 2) { break }
    }
    return , $l
}
function Yonetim-Ilkeleri([string]$Metin, [int]$Sinir) {
    $b = Bolum-Oku $Metin 'Ekip ilkeleri'
    $l = @(($b -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^([-*]|\d+[.)])\s+\S' } |
        ForEach-Object { '- ' + (Kisalt (($_ -replace '^([-*]|\d+[.)])\s+', '').Trim()) 300) } | Select-Object -First $Sinir)
    return , $l
}
# "ONCELIK: <no> | <1-3>": yalnızca başlamamış (aşama 'yeni') işlerde ve başka süreç o işi tutmuyorsa
function Yonetim-Oncelikleri([string]$Metin) {
    $degisen = @()
    foreach ($m in [regex]::Matches([string]$Metin, '(?m)^\W{0,4}ONCELIK\W{0,4}\s*[:=]?\s*#?(\d{4})[^\s|]*\s*\|\s*([123])\b')) {
        $no = $m.Groups[1].Value; $yeni = [int]$m.Groups[2].Value
        $kl = Get-ChildItem -LiteralPath $YolGorev -Directory | Where-Object { $_.Name -eq $no -or $_.Name -like "$no-*" } | Select-Object -First 1
        if (-not $kl) { continue }
        $kilit = Gorev-Kilidi-Al $kl.Name
        if (-not $kilit) { continue }
        try {
            $g = Gorev-Diskten $kl.Name
            if (-not $g -or [string]$g.asama -ne 'yeni' -or [int]$g.oncelik -eq $yeni) { continue }
            $eski = [int]$g.oncelik
            $g.oncelik = $yeni
            Gecmis-Ekle $g 'CTO önceliği değiştirdi' ('{0} -> {1}' -f $eski, $yeni)
            Gorev-Kaydet $g
            $degisen += [pscustomobject]@{ gorev = $kl.Name; onceki = $eski; yeni = $yeni }
        } finally { Gorev-Kilidi-Birak $kilit }
    }
    return , $degisen
}

function Yonetim-Degerlendir {
    $ay = Yonetim-Ayari
    $kl = Yonetim-Klasoru
    $son = Yonetim-Son
    $istendi = Test-Path -LiteralPath (Yonetim-Istek-Yolu)
    $script:AktifGorev = ''; $script:AktifAdim = 'yonetim'
    Kalp 'çalışıyor'
    Gunluk "Yönetim değerlendirmesi başlıyor (CTO)$(if ($istendi) { '; panelden istendi' })"
    try {
        Kadro-Rolleri-Yukle
        $bas = Yonetim-Donem-Basi $son
        $ilkeler = Metin-Oku (Join-Path $kl 'ekip-ilkeleri.md'); if (-not $ilkeler.Trim()) { $ilkeler = '(henüz yok; ilk listeyi sen yazacaksın)' }
        $onceki = '(Bu ilk değerlendirme.)'; if ($son -and $son.ozet) { $onceki = '{0}: {1}' -f ([string]$son.zaman), ([string]$son.ozet) }
        $istem = Sablon-Doldur 'cto-degerlendirme.md' @{
            METRIKLER = (Yonetim-Metrikleri $bas); KUYRUK = (Yonetim-Kuyrugu); KULLANIM = (Yonetim-Kullanim $bas); DALLAR = (Yonetim-Dallari)
            ILKELER = $ilkeler; ONCEKI = $onceki; KADRO = (Kadro-Metni); ILKE_SINIRI = [string]$ay.ilke_siniri
            ILKE_KARAKTER_SINIRI = [string](Ilke-Karakter-Siniri)
        }
        $r = Ajan-Cagir -Rol 'cto' -Istem $istem -Klasor $Kok -KayitKlasoru (Join-Path $kl 'kayitlar') -Etiket 'yonetim'
        if (-not $r.basarili -or (Karar-Oku $r.metin) -ne 'HAZIR') {
            $h = [string]$r.hata; if ($r.basarili) { $h = 'çıktıda KARAR: HAZIR satırı yok' }
            Json-Yaz ([pscustomobject][ordered]@{ zaman = (Simdi); durum = 'basarisiz'; hata = (Kisalt $h 300); ozet = $(if ($son) { $son.ozet } else { '' }); dosya = $(if ($son) { $son.dosya } else { '' }); oneriler = @($(if ($son) { $son.oneriler })) }) (Join-Path $kl 'son.json')
            Gunluk "Yönetim değerlendirmesi yapılamadı: $(Kisalt $h 200); 2 saat sonra yeniden denenecek" 'UYARI'
            return
        }
        $zaman = Get-Date
        $ad = 'degerlendirme-{0}.md' -f $zaman.ToString('yyyyMMdd-HHmm')
        $rapor = ([regex]::Replace($r.metin, '(?s)```is\s*\{.*?\}\s*```', '')).Trim()
        $rapor = ((($rapor -split "`r?`n") | Where-Object { $_ -notmatch '^\W{0,4}(KARAR|ONCELIK)\W{0,4}\s*[:=]' }) -join "`n").Trim()
        $degisen = Yonetim-Oncelikleri $r.metin
        $ek = ''
        if ($degisen.Count) { $ek = "`n`n## Uygulanan öncelik değişiklikleri`n`n" + (($degisen | ForEach-Object { '- #{0}: {1} -> {2}' -f (No-Kisa $_.gorev), $_.onceki, $_.yeni }) -join "`n") }
        Metin-Yaz (Join-Path $kl $ad) ("# Yönetim değerlendirmesi (CTO) · $($zaman.ToString('dd.MM.yyyy HH:mm'))`n`n" + $rapor + $ek + "`n")
        $il = Yonetim-Ilkeleri $r.metin $ay.ilke_siniri
        if ($il.Count) {
            $ilMetin = ($il -join "`n") + "`n"
            Metin-Yaz (Join-Path $kl 'ekip-ilkeleri.md') $ilMetin
            # İstemlere sığmayan madde varsa bir kez uyar (Ilkeler-Istem-Metni madde sınırında keser)
            $sg = Ilkeler-Sigdir $ilMetin (Ilke-Karakter-Siniri)
            if ($sg.kesilen -gt 0) { Gunluk ("Ekip ilkeleri {0} karakter, sınır {1}: son {2} ilke iş istemlerine girmeyecek (ayarlar.json > yonetim.ilke_karakter_siniri)" -f $ilMetin.Trim().Length, (Ilke-Karakter-Siniri), $sg.kesilen) 'UYARI' }
        }
        $oneriler = Yonetim-Onerileri $r.metin
        $ozet = Kisalt ((Bolum-Oku $r.metin 'Özet') -replace '\s+', ' ') 600
        Json-Yaz ([pscustomobject][ordered]@{ zaman = $zaman.ToString('o'); durum = 'tamam'; dosya = $ad; ozet = $ozet; ilke_sayisi = $il.Count
            oneriler = @($oneriler); oncelik_degisiklikleri = @($degisen); arac = ('{0}/{1}' -f $r.arac, $r.model); istendi = [bool]$istendi }) (Join-Path $kl 'son.json')
        Gunluk ("Yönetim değerlendirmesi hazır: {0}; {1} ilke, {2} öneri, {3} öncelik değişikliği" -f $ad, $il.Count, $oneriler.Count, $degisen.Count)
        $bm = $ozet; if (-not $bm) { $bm = 'Rapor ofis panelinde (Yönetim bölümü).' }
        if ($oneriler.Count) { $bm = "$(Kisalt $bm 120) $($oneriler.Count) iş önerisi onayını bekliyor." }
        Bildir -Baslik 'CTO değerlendirmesi hazır' -Metin (Kisalt $bm 180) -Anahtar 'yonetim' -AralikDk 600
    } catch {
        Gunluk ("Yönetim değerlendirmesi hata: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) 'HATA'
        try { Json-Yaz ([pscustomobject][ordered]@{ zaman = (Simdi); durum = 'basarisiz'; hata = (Kisalt $_.Exception.Message 300) }) (Join-Path $kl 'son.json') } catch {}
    } finally {
        Remove-Item -LiteralPath (Yonetim-Istek-Yolu) -Force -ErrorAction SilentlyContinue
        $script:AktifAdim = ''
    }
}
