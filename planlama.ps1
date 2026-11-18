<#
planlama.ps1 - İşi alma ve planlama katmanı, bölünmüş geliştirme, QA testi ve onay kapısı (ekip.ps1 dot-source eder).

Süreç (ayarlar.json > planlama; bir katman ayarla kapatılmışsa ya da rolün kadroda / model zinciri yoksa atlanır):
  1. Analiz    analiz      Product Manager (urun) talebi netleştirir: talep özeti, kullanıcı hikâyeleri, test edilebilir kabul
                           ölçütleri (Definition of Done), kapsam dışı, varsayımlar. Yalnızca kullanıcının verebileceği bir bilgi
                           eksikse soru sorar (bekliyor_kullanici -> yanıt gelince yeniden analiz). Çıktı gorevler\<no>\gereksinimler.md;
                           ekip.ps1 > Gorev-Metni bunu her istemdeki görev metnine ekler. "İş ver" işlerinde yönlendirmeden önce çalışır.
  2. Keşif     kesif       Codebase Explorer (kasif) görevin çalışma dalını salt okunur tarar: teknoloji yığını, klasör yapısı,
                           etkilenecek dosyalar, testler, önyüz / arka uç ayrımı -> gorevler\<no>\kesif.md. Boş (yeni) depoda atlanır.
  3. Planlama  plan        Engineering Manager gereksinimleri ve keşfi birleştirip planı yazar, işi geliştiricilere dağıtır
                           ("IS: backend | ...", "IS: frontend | ..."; satır yoksa Full-Stack Developer işin tamamını yapar),
                           QA testini açar / kapatır (QA_TESTI), projenin test komutunu doğrulamaya ekletebilir (DOGRULAMA_EKLE).
  4. Kodlama   gelistirme  Parçalar planlanan sırayla aynı çalışma dalında, her adımda bir parça yapılır.
  5. Doğrulama kontrol (betik) -> test (QA Engineer birim / entegrasyon testi yazar, tüm testleri koşturur, kullanıcıya dönük işte
                           uygulamayı dener; yazdığı test dosyaları dala eklenir) -> denetim (Code Reviewer, gerekirse Security
                           Engineer / Solution Architect) -> kabul (Engineering Manager). Hata bulunursa iş yeni turla ilgili
                           geliştiriciye döner ("DUZELTECEK: backend"; yazılmazsa bütün parçalar yeniden açılır).
  Onay kapısı: Code Reviewerʼın bu turdaki onayı (QA testi yapıldıysa QA Engineerʼın da) olmadan değişiklik commit edilmez;
  kullanıcı işi panoda kendisi "Tamamlandı"ya taşıdıysa bu onun kararıdır, commit mesajına not düşülür.
#>

# Kod yazan roller: yerleşik geliştiriciler + kadroda "kod_yazar": true olanlar (ör. İKʼnın işe aldığı ikinci geliştirici)
$script:KodYazanlar = @('gelistirici', 'frontend', 'backend')

function Planlama-Ayari {
    $o = [ordered]@{ analiz = $true; kesif = $true; qa_testi = $true; urun_soru_hakki = 2; en_fazla_parca = 3; onay_kapisi = $true }
    $p = $Ayar.planlama
    if ($p) { foreach ($k in @($o.Keys)) { if ($p.PSObject.Properties[$k] -and $null -ne $p.$k) { $o[$k] = $p.$k } } }
    $o.urun_soru_hakki = [int]$o.urun_soru_hakki
    $o.en_fazla_parca = [Math]::Max(1, [int]$o.en_fazla_parca)
    foreach ($k in @('analiz', 'kesif', 'qa_testi', 'onay_kapisi')) { $o[$k] = [bool]$o[$k] }
    return [pscustomobject]$o
}
# Rol kadroda ve en az bir modeli varsa çalışabilir (kadrodaki uzmanların araçları Kadro-Rolleri-Yukle ile yüklenir)
function Rol-Hazir-mi([string]$Rol) {
    if (-not $Rol -or -not (Kadro-Uye $Rol)) { return $false }
    Kadro-Rolleri-Yukle
    return (@($Ayar.roller.$Rol | Where-Object { $_ }).Count -gt 0)
}
function Kod-Yazar-mi([string]$Rol) {
    $u = Kadro-Uye $Rol
    if (-not $u) { return $false }
    return ($KodYazanlar -contains $Rol -or [bool]$u.kod_yazar)
}
function Karar-Satirini-At([string]$Metin) {
    # Çıktının makine satırları (KARAR, KAPSAM, öneri alanları) başka istemlere girince taklit edilmesin
    return ((([string]$Metin) -split "`r?`n" | Where-Object { $_ -notmatch '^\W{0,4}(KARAR|KAPSAM|ATAMA|PROJE|GELISTIRME_ONERISI|GUVENLIK_HASSAS|TEST_KOMUTU|PUAN|PUAN_GEREKCE)\W{0,4}\s*[:=]' }) -join "`n").Trim()
}

# ---------------------------------------------------------------- hangi hazırlık adımı gerekli
function Analiz-Gerekli($G) {
    if ([string]$G.gereksinim_durumu) { return $false }
    $tip = [string]$G.tip; if ($tip -and @('yazilim', 'genel') -notcontains $tip) { return $false }
    if (-not (Planlama-Ayari).analiz) { return $false }
    return (Rol-Hazir-mi 'urun')
}
function Kesif-Gerekli($G) {
    if ([string]$G.kesif_durumu) { return $false }
    $tip = [string]$G.tip; if ($tip -and $tip -ne 'yazilim') { return $false }
    if (-not (Planlama-Ayari).kesif) { return $false }
    return (Rol-Hazir-mi 'kasif')
}
# Çalışma dalı hazırlandıktan, gereksinimler ya da keşif bittikten sonra yazılım işinin geçeceği aşama
function Hazirlik-Sonraki($G) {
    if (Analiz-Gerekli $G) { return 'analiz' }
    if (Kesif-Gerekli $G) { return 'kesif' }
    return 'plan'
}
function Gereksinim-Metni($G) { Metin-Oku (Join-Path (Gorev-Klasoru $G.id) 'gereksinimler.md') }
function Kesif-Metni($G, [int]$Uzunluk = 6000) {
    if ([string]$G.kesif_durumu -ne 'hazir') { return '(Bu işte kod tabanı keşfi yapılmadı.)' }
    $k = Metin-Oku (Join-Path (Gorev-Klasoru $G.id) 'kesif.md')
    if (-not $k.Trim()) { return '(Keşif raporu bulunamadı.)' }
    return (Kirp $k.Trim() $Uzunluk)
}

# ---------------------------------------------------------------- 1. Analiz: Product Manager
function Adim-Analiz($G) {
    $gk = Gorev-Klasoru $G.id
    $ay = Planlama-Ayari
    $sorulan = [int]$G.urun_soru_sayisi
    $hak = $ay.urun_soru_hakki
    $soruNotu = 'Soru hakkın kalmadı: SORU_VAR verme; belirsizlikleri "Varsayımlar" bölümünde makul varsayımlarla kapat.'
    if ($sorulan -lt $hak) { $soruNotu = "Bu iş için kullanıcıya en fazla $($hak - $sorulan) kez daha soru sorabilirsin; her soru işi kullanıcı yanıtlayana kadar durdurur." }
    $onceki = Metin-Oku (Join-Path $gk 'sorular.md')
    if (-not $onceki.Trim()) { $onceki = Gereksinim-Metni $G }
    if (-not $onceki.Trim()) { $onceki = '(Yok; bu ilk analiz.)' }
    $klasor = $gk
    $proje = '(Henüz belli değil: işi hangi ekibin, hangi projede yapacağına Engineering Manager karar verecek.)'
    $wt = [string]$G.calisma_klasoru
    if ($wt -and (Test-Path -LiteralPath $wt)) {
        $klasor = $wt
        $proje = "Proje: $($G.proje). Çalışma klasörün bu projenin görev dalı; README ve genel yapıya bakabilirsin (kodu ayrıntılı taramak Codebase Explorerʼın işi)."
    } elseif ([string]$G.ipucu) { $proje = "Kullanıcının ipucu (ilgili proje / klasör): $($G.ipucu)" }
    # Karşılama kararı: tek parça iş Outsource Consultantʼa (danisman.ps1); kullanıcı doğrudan ona verdiyse zorunlu
    $zorunluDanisman = ([string]$G.istenen_rol -eq 'danisman')
    $danismanUygun = (Danisman-Hazir-mi) -and ([string]$G.tip -eq 'genel' -or $zorunluDanisman)
    $dNot = 'Outsource Consultant bu iş için seçenek değil: ATAMA: ekip yaz.'
    if ($danismanUygun) {
        $dNot = 'Outsource Consultant kullanılabilir; işin yapısına göre karar ver.'
        if ($zorunluDanisman) { $dNot = 'Kullanıcı bu işi doğrudan Outsource Consultantʼa verdi: ATAMA: danisman yaz ve "## Danışman brifi" bölümünü hazırla.' }
    }
    $istem = Sablon-Doldur 'urun-analiz.md' @{ GOREV = (Gorev-Ham-Metni $G); ONCEKI = $onceki; SORU_HAKKI = $soruNotu; PROJE = $proje; DANISMAN = $dNot }
    $r = Ajan-Cagir -Rol 'urun' -Istem $istem -Klasor $klasor -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'analiz'
    if (-not $r.basarili) { Adim-Basarisiz $G "Product Manager talebi analiz edemedi: $($r.hata)"; return }
    Ayarla $G 'urun' ('{0}/{1}' -f $r.arac, $r.model)
    $karar = Karar-Oku $r.metin
    if ($karar -eq 'SORU_VAR' -and $sorulan -lt $hak) {
        Metin-Yaz (Join-Path $gk 'sorular.md') $r.metin
        Ayarla $G 'urun_soru_sayisi' ($sorulan + 1)
        Ayarla $G 'soru_soran' 'urun'
        Ayarla $G 'soru_donus_asama' 'analiz'
        Gecmis-Ekle $G 'Product Manager soru sordu' '' $r
        $G.asama = 'bekliyor_kullanici'
        $G.deneme = 0
        Ayarla $G 'soru_zamani' (Simdi)
        Gunluk "Görev $($G.id): Product Manager kullanıcıya soru sordu"
        Bildir -Baslik "Product Manager soru soruyor: $($G.baslik)" -Metin ("#{0}: panelde Soru sekmesini oku, yanıtla (ya da gorev.md'deki 'Notlar ve yanıtlar' bölümüne yaz); ekip kendiliğinden devam eder." -f (No-Kisa $G.id)) -Anahtar "soru-$($G.id)" -Onem 'yuksek'
        return
    }
    if (@('HAZIR', 'SORU_VAR') -notcontains $karar) {
        Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin
        Adim-Basarisiz $G "Gereksinim çıktısında geçerli bir KARAR satırı yok ($($r.arac))"
        return
    }
    $ek = ''; if ($karar -eq 'SORU_VAR') { $ek = ' (soru hakkı dolu; varsayımlarla)' }
    Metin-Yaz (Join-Path $gk 'gereksinimler.md') ([regex]::Replace((Karar-Satirini-At $r.metin), '(?ms)^#{1,3}\s*Danışman brifi\s*$.*?(?=^#{1,3}\s|\z)', '').Trim())
    Ayarla $G 'gereksinim_durumu' 'hazir'
    $kapsam = (Alan-Oku $r.metin 'KAPSAM').ToLowerInvariant()
    if (@('kucuk', 'küçük', 'orta', 'buyuk', 'büyük') -contains $kapsam) { Ayarla $G 'kapsam' ($kapsam -replace 'ü', 'u' -replace 'ç', 'c') }
    if ($danismanUygun) {
        $atama = (Alan-Oku $r.metin 'ATAMA').ToLowerInvariant()
        if ($zorunluDanisman -or $atama -match '^\W*danisman') { Danismana-Aktar $G $r.metin $r 'Product Manager'; return }
    }
    $sonraki = 'plan'
    if ([string]$G.tip -ne 'genel') { $sonraki = Hazirlik-Sonraki $G }
    Asama-Gec $G $sonraki ("gereksinimler hazır$ek") (Kisalt (Bolum-Oku $r.metin 'Talep özeti') 300) $r
}

# ---------------------------------------------------------------- 2. Keşif: Codebase Explorer
function Depo-Ozeti([string]$Wt, [string[]]$Dosyalar) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("- Çalışma klasörü: $Wt")
    [void]$sb.AppendLine("- İzlenen dosya: $($Dosyalar.Count)")
    $uzanti = @{}
    $ust = New-Object Collections.Generic.List[string]
    foreach ($f in $Dosyalar) {
        $p = $f -split '/'
        $u = $p[0]; if ($p.Count -gt 1) { $u += '/' }
        if (-not $ust.Contains($u)) { $ust.Add($u) }
        $e = [IO.Path]::GetExtension($f).ToLowerInvariant(); if (-not $e) { $e = '(uzantısız)' }
        $uzanti[$e] = 1 + [int]$uzanti[$e]
    }
    $enCok = @($uzanti.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 | ForEach-Object { '{0} ({1})' -f $_.Key, $_.Value })
    [void]$sb.AppendLine("- Dosya türleri: $($enCok -join ', ')")
    [void]$sb.AppendLine("- Kök: $(($ust | Select-Object -First 40) -join '  ')")
    $bildirim = @('package.json', 'pubspec.yaml', 'requirements.txt', 'pyproject.toml', 'setup.py', 'go.mod', 'Cargo.toml', 'pom.xml', 'build.gradle',
        'build.gradle.kts', 'composer.json', 'Gemfile', 'Makefile', 'CMakeLists.txt', 'tsconfig.json', 'vite.config.ts', 'vite.config.js', 'angular.json', 'next.config.js', 'Dockerfile')
    $bulunan = @($Dosyalar | Where-Object { $bildirim -contains ($_ -split '/')[-1] -or $_ -match '\.(csproj|sln|fsproj)$' } | Select-Object -First 25)
    if ($bulunan.Count) { [void]$sb.AppendLine("- Yapı / bağımlılık dosyaları: $($bulunan -join ', ')") }
    $testler = @($Dosyalar | Where-Object { $_ -match '(?i)(^|/)(tests?|specs?|__tests__|integration_test)(/|$)|(?i)[._-](test|spec)s?\.[a-z0-9]+$|(?i)(^|/)test_[^/]+$' })
    [void]$sb.AppendLine("- Test görünümlü dosya: $($testler.Count)$(if ($testler.Count) { ' (ör. ' + (($testler | Select-Object -First 6) -join ', ') + ')' })")
    return $sb.ToString()
}
function Adim-Kesif($G) {
    $gk = Gorev-Klasoru $G.id
    $wt = [string]$G.calisma_klasoru
    if (-not $wt -or -not (Test-Path -LiteralPath $wt)) {
        $h = Calisma-Agaci-Kur $G
        if ($h) { Takildi $G $h; return }
        $wt = [string]$G.calisma_klasoru
    }
    $dosyalar = @((Git-Calistir $wt @('ls-files') -Sessiz) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(warning|hint|error|fatal):' })
    if ($dosyalar.Count -le 2) {
        Ayarla $G 'kesif_durumu' 'atlandi'
        Asama-Gec $G 'plan' 'keşif gerekmedi' ("depoda {0} dosya var (yeni proje)" -f $dosyalar.Count)
        return
    }
    $istem = Sablon-Doldur 'kasif-kesif.md' @{ GOREV = (Gorev-Metni $G); DEPO = (Depo-Ozeti $wt $dosyalar); CALISMA = $wt }
    $r = Ajan-Cagir -Rol 'kasif' -Istem $istem -Klasor $wt -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'kesif'
    if (-not $r.basarili) { Adim-Basarisiz $G "Codebase Explorer depoyu tarayamadı: $($r.hata)"; return }
    $temiz = Karar-Satirini-At $r.metin
    if ($temiz.Length -lt 80) { Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin; Adim-Basarisiz $G "Keşif raporu boş ya da çok kısa ($($r.arac))"; return }
    $oneri = (Alan-Oku $r.metin 'GELISTIRME_ONERISI').ToLowerInvariant()
    $hassas = (Alan-Oku $r.metin 'GUVENLIK_HASSAS').ToLowerInvariant()
    $komut = Alan-Oku $r.metin 'TEST_KOMUTU'
    $bas = New-Object Text.StringBuilder
    if ($oneri) { [void]$bas.AppendLine("- Geliştirme önerisi: $oneri") }
    if ($hassas) { [void]$bas.AppendLine("- Güvenlik açısından hassas: $hassas") }
    if ($komut) { [void]$bas.AppendLine("- Projenin test komutu: $komut") }
    $rapor = "# Kod tabanı keşfi (Codebase Explorer)`n`n"
    if ($bas.Length) { $rapor += $bas.ToString() + "`n" }
    Metin-Yaz (Join-Path $gk 'kesif.md') ($rapor + $temiz)
    Ayarla $G 'kesif_durumu' 'hazir'
    Ayarla $G 'kasif' ('{0}/{1}' -f $r.arac, $r.model)
    if ($hassas -match '^(evet|yes|true)') { Ayarla $G 'guvenlik_hassas' $true }
    Asama-Gec $G 'plan' 'keşif raporu hazır' (Kisalt (Bolum-Oku $temiz 'Teknoloji yığını') 200) $r
}

# ---------------------------------------------------------------- 3. Planlama: iş dağılımı
function Gelistiriciler-Metni {
    $l = @()
    foreach ($u in (Kadro-Uyeleri)) {
        $a = [string]$u.anahtar
        if (-not (Kod-Yazar-mi $a) -or -not (Rol-Hazir-mi $a)) { continue }
        $l += ('- {0} ({1}): {2}' -f $a, $u.ad, (Kisalt ([string]$u.uzmanlik) 160))
    }
    if (-not $l.Count) { return '- gelistirici (Full-Stack Developer)' }
    return ($l -join "`n")
}
# Plandaki iş dağılımı: "IS: <geliştirici anahtarı> | <iş>" satırları, yazıldıkları sırayla (en fazla planlama.en_fazla_parca)
function Plan-Isleri-Coz([string]$Metin) {
    $l = @()
    $en = (Planlama-Ayari).en_fazla_parca
    foreach ($m in [regex]::Matches([string]$Metin, '(?m)^[\s\-\*>#]*IS\**\s*:\s*\**\s*([A-Za-z0-9-]+)\s*\**\s*\|\s*(.+?)\s*$')) {
        $rol = Kadro-Anahtar-Coz $m.Groups[1].Value
        $is = $m.Groups[2].Value.Trim().Trim('`', '*', ' ')
        if (-not (Kod-Yazar-mi $rol) -or -not (Rol-Hazir-mi $rol) -or -not $is -or $is.StartsWith('<')) { Gunluk "Plan iş satırı atlandı: $($m.Value.Trim())" 'UYARI'; continue }
        $l += [pscustomobject][ordered]@{ rol = $rol; is = (Kisalt $is 600); durum = 'bekliyor'; tur = 0; arac = '' }
        if ($l.Count -ge $en) { break }
    }
    # Tek parça ve o da Full-Stack Developer ise bölünmüş sayma
    if ($l.Count -eq 1 -and [string]$l[0].rol -eq 'gelistirici') { $l = @() }
    return , $l
}
function QA-Testi-Var($G) { return (($G.qa_testi -eq $true) -and (Rol-Hazir-mi 'tester')) }
# Plan kararından sonra: iş dağılımı, QA testi, doğrulama komutu. Planın EK_INCELEME listesini (QA testi varsa tester'sız) döndürür.
function Plan-Kararlarini-Uygula($G, [string]$Metin, $Ek) {
    $isler = Plan-Isleri-Coz $Metin
    Ayarla $G 'gelistirme_isleri' @($isler)
    $ay = Planlama-Ayari
    $qa = ($ay.qa_testi -and (Rol-Hazir-mi 'tester'))
    if ((Alan-Oku $Metin 'QA_TESTI') -match '^(?i)\W*(hay[ıi]r|no|yok|gereksiz|false|kapal[ıi])') { $qa = $false }
    Ayarla $G 'qa_testi' ([bool]$qa)
    $sonuc = @($Ek)
    if ($qa) { $sonuc = @($Ek | Where-Object { $_ -ne 'tester' }) }
    $d = Dogrulama-Ekle $G $Metin   # cozucu.ps1: yalnızca güvenli test / derleme komutları
    $notlar = @()
    if ($isler.Count) { $notlar += 'iş dağılımı: ' + (($isler | ForEach-Object { Calisan-Adi $_.rol }) -join ' → ') }
    if ($qa) { $notlar += 'QA testi: evet' } else { $notlar += 'QA testi: hayır' }
    if (@($d.eklenen).Count) { $notlar += 'doğrulamaya eklendi: ' + ($d.eklenen -join '; ') }
    if (@($d.reddedilen).Count) { Gunluk ("Görev {0}: planın doğrulama komutu reddedildi (güvenli değil): {1}" -f $G.id, ($d.reddedilen -join '; ')) 'UYARI' }
    return [pscustomobject]@{ ek = @($sonuc); not = ($notlar -join '; ') }
}

# ---------------------------------------------------------------- 4. Kodlama: parçalar
function Gelistirme-Isleri($G) { return , @($G.gelistirme_isleri | Where-Object { $_ -and $_.rol }) }
# Sıradaki (bitmemiş) parçanın 1'den başlayan numarası; hepsi bittiyse ya da iş bölünmemişse 0
function Gelistirme-Sira-No($G) {
    $n = 0
    foreach ($p in (Gelistirme-Isleri $G)) { $n++; if ([string]$p.durum -ne 'tamam') { return $n } }
    return 0
}
function Gelistirme-Sirasi($G) {
    $n = Gelistirme-Sira-No $G
    if ($n -le 0) { return $null }
    return (Gelistirme-Isleri $G)[$n - 1]
}
function Parca-Ozet-Adi([int]$No, [string]$Rol) { return ('gelistirici-ozet-{0}-{1}.md' -f $No, $Rol) }
# Parçanın en son turdaki özeti (bu turda yeniden yapılmadıysa önceki turunki)
function Parca-Son-Ozeti($G, [int]$No, [string]$Rol) {
    for ($t = [int]$G.tur; $t -ge 1; $t--) {
        $f = Join-Path (Join-Path (Gorev-Klasoru $G.id) "tur$t") (Parca-Ozet-Adi $No $Rol)
        if (Test-Path -LiteralPath $f) { return [pscustomobject]@{ tur = $t; metin = (Metin-Oku $f) } }
    }
    return $null
}
# Geri bildirimdeki "DUZELTECEK: backend, frontend" satırları; tanınan rol yoksa boş (bütün parçalar açılır)
function Duzeltecek-Coz([string]$Metin, [string[]]$Roller) {
    $l = @()
    foreach ($m in [regex]::Matches([string]$Metin, '(?m)^\W{0,4}DUZELTECEK\W{0,4}\s*[:=]?\s*(.+?)\s*$')) {
        foreach ($p in ($m.Groups[1].Value -split '[,;/\s]+')) {
            $a = Kadro-Anahtar-Coz $p
            if ($Roller -contains $a -and $l -notcontains $a) { $l += $a }
        }
    }
    return , $l
}
# Yeni turda (ya da iş geri alınınca) hiçbir parça bu turda yapılmamışsa geri bildirimin istediği parçaları yeniden aç
function Gelistirme-Turunu-Hazirla($G, [string]$GeriBildirim) {
    $isler = Gelistirme-Isleri $G
    if (-not $isler.Count) { return }
    if (Gelistirme-Sirasi $G) { return }
    if (@($isler | Where-Object { [int]$_.tur -eq [int]$G.tur }).Count) { return }
    $hedef = Duzeltecek-Coz $GeriBildirim @($isler | ForEach-Object { [string]$_.rol })
    $acilan = @()
    foreach ($p in $isler) {
        if ($hedef.Count -eq 0 -or $hedef -contains [string]$p.rol) { $p.durum = 'bekliyor'; $acilan += (Calisan-Adi $p.rol) }
    }
    Ayarla $G 'gelistirme_isleri' @($isler)
    Gunluk ("Görev {0}: {1}. tur geliştirme parçaları açıldı: {2}{3}" -f $G.id, $G.tur, ($acilan -join ', '), $(if ($hedef.Count) { ' (geri bildirimin DUZELTECEK satırına göre)' } else { '' }))
}
function Gelistirme-Payi-Metni($G, [int]$No, $Isler) {
    if ($No -le 0 -or -not $Isler.Count) {
        return 'Bu işte geliştirmenin tamamı sende (tek geliştirici): önyüz, arka uç, yapılandırma ve planın gerektirdiği her şey.'
    }
    $parca = $Isler[$No - 1]
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine(('Engineering Manager geliştirmeyi {0} parçaya böldü; parçalar sırayla, aynı çalışma dalında yapılır. Sen {1}. parçayı yapıyorsun.' -f $Isler.Count, $No))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Senin payın:** $($parca.is)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Bütün parçalar:')
    $n = 0
    foreach ($p in $Isler) {
        $n++
        $d = 'sırada'
        if ($n -eq $No) { $d = 'SENDE' } elseif ([string]$p.durum -eq 'tamam') { $d = "bitti ($($p.tur). tur)" }
        [void]$sb.AppendLine(('{0}. {1}: {2} [{3}]' -f $n, (Calisan-Adi $p.rol), $p.is, $d))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Kurallar: yalnızca kendi payını yap. Başka parçanın dosyalarına ancak payın gerektiriyorsa ve en az ölçüde dokun; önceki parçaların yaptığını bozma. Parçalar arasındaki sözleşmeye (API uçları, veri biçimleri, bileşen arayüzleri) uy; planda tanımlı değilse sen tanımla ve son mesajında "## Arayüz / sözleşme" başlığıyla yaz ki sonraki parça kullanabilsin.')
    $onceki = New-Object Text.StringBuilder
    $n = 0
    foreach ($p in $Isler) {
        $n++
        if ($n -eq $No -or [string]$p.durum -ne 'tamam') { continue }
        $o = Parca-Son-Ozeti $G $n ([string]$p.rol)
        if ($o) { [void]$onceki.AppendLine(("### {0} ({1}. tur)`n`n{2}`n" -f (Calisan-Adi $p.rol), $o.tur, (Kirp $o.metin.Trim() 3000))) }
    }
    if ($onceki.Length) { [void]$sb.AppendLine(''); [void]$sb.AppendLine('Biten parçaların özetleri:'); [void]$sb.AppendLine(''); [void]$sb.Append($onceki.ToString()) }
    return $sb.ToString()
}
function Gelistirme-Ozetleri($G, $Isler) {
    $sb = New-Object Text.StringBuilder
    $n = 0
    foreach ($p in $Isler) {
        $n++
        $o = Parca-Son-Ozeti $G $n ([string]$p.rol)
        [void]$sb.AppendLine(('# {0}. parça: {1}' -f $n, (Calisan-Adi $p.rol)))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("Payı: $($p.is)")
        [void]$sb.AppendLine('')
        if (-not $o) { [void]$sb.AppendLine('(henüz yapılmadı)') }
        elseif ($o.tur -ne [int]$G.tur) { [void]$sb.AppendLine("(Bu turda değişiklik gerekmedi; $($o.tur). turdaki özeti:)"); [void]$sb.AppendLine(''); [void]$sb.AppendLine($o.metin.Trim()) }
        else { [void]$sb.AppendLine($o.metin.Trim()) }
        [void]$sb.AppendLine('')
    }
    return $sb.ToString()
}

# ---------------------------------------------------------------- 5. Doğrulama: QA Engineer testi
# QA Engineerʼın çıktısındaki "TEST_DOSYASI: <yol>" satırları: çalışma ağacında var olan, test klasöründe ya da adı test / spec
# içeren, korunan desenlere uymayan dosyalar dala alınır (git add); gizli bilgi şüphesi varsa hiçbiri alınmaz.
function QA-Test-Dosyalarini-Al([string]$Wt, [string]$Metin) {
    $alinan = @()
    foreach ($m in [regex]::Matches([string]$Metin, '(?m)^\W{0,4}TEST_DOSYASI\W{0,4}\s*[:=]?\s*`?([^`\r\n]+?)`?\s*$')) {
        $yol = ($m.Groups[1].Value.Trim().Trim('"', '''', '*', ' ') -replace '\\', '/')
        if ($yol.StartsWith('./')) { $yol = $yol.Substring(2) }
        if (-not $yol -or $yol.StartsWith('<') -or $yol.StartsWith('/') -or $yol -match '^[A-Za-z]:' -or $yol -match '(^|/)\.\.?(/|$)' -or $yol -match '(^|/)\.git(/|$)') { continue }
        if ($yol -notmatch '(?i)(^|/)(tests?|specs?|__tests__|testing|integration_test|e2e)(/|$)' -and ($yol -split '/')[-1] -notmatch '(?i)(test|spec)') { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $Wt ($yol -replace '/', '\')) -PathType Leaf)) { continue }
        $ad = ($yol -split '/')[-1]
        $korunan = $false
        foreach ($d in @($Ayar.korunan_desenler)) { if ($ad -like $d) { $korunan = $true; break } }
        if ($korunan -or $alinan -contains $yol) { continue }
        $alinan += $yol
        if ($alinan.Count -ge 40) { break }
    }
    if (-not $alinan.Count) { return , $alinan }
    Git-Calistir $Wt (@('add', '--') + $alinan) | Out-Null
    $u0 = Git-Calistir $Wt (@('diff', '--cached', '-U0', '--no-color', '--') + $alinan) -Sessiz
    if ((Gizli-Satir-Sayisi $u0) -gt 0) {
        Git-Calistir $Wt (@('reset', '-q', '--') + $alinan) -Sessiz | Out-Null
        Gunluk "QA test dosyalarında olası gizli bilgi (parola / anahtar) var; dala alınmadı: $($alinan -join ', ')" 'UYARI'
        return , @()
    }
    return , $alinan
}
function Adim-Test($G) {
    Kadro-Rolleri-Yukle
    $uye = Kadro-Uye 'tester'
    if (-not $uye -or -not (Rol-Hazir-mi 'tester')) { Asama-Gec $G 'denetim' 'QA testi atlandı' 'QA Engineer kadroda yok ya da modeli seçili değil'; return }
    $tk = Tur-Klasoru $G
    $wt = [string]$G.calisma_klasoru
    $d = Diff-Hazirla $G   # geliştiricinin değişikliği index'e alınır; test sonrası temizlik index'tekini korur
    $testKl = Join-Path $YolCalisma ('{0}-test' -f $G.id)
    if (-not (Test-Path -LiteralPath $testKl)) { New-Item -ItemType Directory -Force $testKl | Out-Null }
    $talimat = Rol-Talimati $uye
    if ([string]$uye.yetki -eq 'tam' -and $Ayar.altyapi) { $talimat += "`n`n## Ortam`n`n" + (Altyapi-Ortam) }
    $onceki = '(Yok; bu işin ilk QA testi.)'
    if ([int]$G.tur -gt 1) {
        $o = Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $G.id) ('tur{0}' -f ([int]$G.tur - 1))) 'test.md')
        if ($o.Trim()) { $onceki = Kirp $o.Trim() 6000 }
    }
    $istem = Sablon-Doldur 'qa-test.md' @{
        ROL_ADI = [string]$uye.ad; ROL_TALIMATI = $talimat; CALISMA = $wt; TEST_KLASORU = $testKl; TUR = [string]$G.tur
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G); KESIF = (Kesif-Metni $G 3000)
        GELISTIRICI_OZET = (Kirp (Metin-Oku (Join-Path $tk 'gelistirici-ozet.md')) 12000); KONTROL = (Metin-Oku (Join-Path $tk 'kontrol.md'))
        DIFF_OZET = $d.stat; DIFF = (Kirp $d.diff 40000); ONCEKI = $onceki
    }
    $p = @{ Rol = 'tester'; Istem = $istem; Klasor = $wt; KayitKlasoru = $tk; Etiket = 'test' }
    if ([string]$uye.yetki -eq 'tam') { $p.TamYetki = $true } elseif ([string]$uye.yetki -eq 'yaz') { $p.Yazabilir = $true }
    $r = Ajan-Cagir @p
    $alinan = @()
    if ($r.basarili -and $wt -and (Test-Path -LiteralPath (Join-Path $wt '.git'))) { $alinan = QA-Test-Dosyalarini-Al $wt $r.metin }
    if ($wt -and (Test-Path -LiteralPath (Join-Path $wt '.git'))) { [void](Test-Sonrasi-Agaci-Temizle $wt) }   # derleme çıktıları, kopyalar
    if (-not $r.basarili) { Adim-Basarisiz $G "QA Engineer test edemedi: $($r.hata)"; return }
    $rapor = $r.metin.TrimEnd()
    if ($alinan.Count) { $rapor += "`n`n## Dala eklenen test dosyaları ($($alinan.Count))`n`n" + (($alinan | ForEach-Object { "- $_" }) -join "`n") }
    Metin-Yaz (Join-Path $tk 'test.md') $rapor
    Ayarla $G 'tester' ('{0}/{1}' -f $r.arac, $r.model)
    if ($alinan.Count) { Ayarla $G 'qa_test_dosyalari' @(@($G.qa_test_dosyalari | Where-Object { $_ -and $alinan -notcontains $_ }) + $alinan) }
    switch (Karar-Oku $r.metin) {
        'ONAY' { Asama-Gec $G 'denetim' 'QA testleri geçti' ('{0} test dosyası dala eklendi' -f $alinan.Count) $r }
        'DUZELT' {
            Gecmis-Ekle $G 'QA Engineer hata buldu' '' $r
            Yeni-Tur $G ("## QA Engineer hata buldu`n`n" + $rapor) 'QA Engineer hata buldu'
        }
        default { Adim-Basarisiz $G "Test çıktısında KARAR satırı yok ($($r.arac))" }
    }
}
function Test-Raporu-Metni($G) {
    $t = Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $G.id) ('tur{0}' -f $G.tur)) 'test.md')
    if ($t.Trim()) { return (Kirp $t.Trim() 15000) }
    if ($G.qa_testi -eq $false) { return '(Engineering Manager bu işte QA testini gerekli görmedi.)' }
    return '(Bu işte QA Engineer testi yapılmadı.)'
}

# ---------------------------------------------------------------- onay kapısı (commit öncesi)
function Onay-Durumu($G) {
    $tk = Join-Path (Gorev-Klasoru $G.id) ('tur{0}' -f $G.tur)
    $onay = @(); $eksik = @()
    $den = Metin-Oku (Join-Path $tk 'denetim.md')
    if ((Karar-Oku $den) -eq 'ONAY') { $onay += "Code Reviewer ONAY ($($G.denetci))" } else { $eksik += 'Code Reviewer onayı' }
    $t = Metin-Oku (Join-Path $tk 'test.md')
    if ($t.Trim()) { if ((Karar-Oku $t) -eq 'ONAY') { $onay += "QA Engineer ONAY ($($G.tester))" } else { $eksik += 'QA Engineer onayı' } }
    # Yalnızca rapor dosyaları (inceleme-<rol>.md); ajan kayıtları (inceleme-<rol>-<araç>-<model>.istem.md / .son.md) sayılmaz
    foreach ($f in @(Get-ChildItem -LiteralPath $tk -Filter 'inceleme-*.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^inceleme-[a-z0-9-]+\.md$' -and (Kadro-Uye $_.BaseName.Substring(9)) })) {
        $rol = $f.BaseName.Substring(9)
        if ((Karar-Oku (Metin-Oku $f.FullName)) -eq 'DUZELT') { $eksik += "$(Calisan-Adi $rol) onayı" } else { $onay += "$(Calisan-Adi $rol) ONAY" }
    }
    if ((Karar-Oku (Metin-Oku (Join-Path $tk 'kabul.md'))) -eq 'KABUL') { $onay += 'Engineering Manager KABUL' }
    $kullanici = ($G.elle_tasima -and [string]$G.elle_tasima.asama -eq 'tamamla')
    return [pscustomobject]@{ onay = @($onay); eksik = @($eksik); kullanici = [bool]$kullanici }
}
