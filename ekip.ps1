<#
ekip.ps1 - AI Ekip görev adımları ve ana döngü (baslat.ps1 dot-source eder).

Görev yaşam döngüsü (gorevler\<id>\durum.json -> asama). Engineering Manager = rol anahtarı "lider".
  "İş ver" ile gelen işler (tip = genel): Engineering Manager işi okuyup yazılım / altyapı / uzman akışına yönlendirir (yonlendirme.ps1)
  yeni -> plan (Engineering Manager) -> gelistirme (Software Developer) -> kontrol (betik: testler + taramalar)
       -> denetim (Code Reviewer) -> kabul (Engineering Manager) -> tamamla (commit) -> tamam
  Kontrol/denetim/kabul geçmezse geri bildirimle yeni tura dönülür (en fazla gorev.max_tur).
  Bir adım tekrar tekrar başarısız olursa ya da tur sınırı dolarsa: takildi. Incident Manager (cozucu.ps1) takılmayı
  inceler: kadrodan birine yardım işi açar, yeniden dener, işi doğru ekibe aktarır ya da kullanıcıya ne yapacağını bildirir.
  Engineering Manager soru sorarsa: bekliyor_kullanici (gorev.md güncellenince kendiliğinden plan'a döner).
#>

# 'yardim': ekip içi yardım isteğini Engineering Manager değerlendiriyor (yardim.ps1). 'yardim_bekliyor' etkin değildir (yardım işleri sürüyor).
$script:AktifAsamalar = @('yeni', 'plan', 'gelistirme', 'kontrol', 'denetim', 'kabul', 'tamamla', 'yardim')
# Sunucu / kurulum talepleri (tip = altyapi): System Administrator + Network Engineer rolleri
. (Join-Path $PSScriptRoot 'altyapi.ps1')
# Kadro, uzman işleri (tip = uzman), İK işe alımı, e-posta: uzman.ps1 (+ posta.ps1)
. (Join-Path $PSScriptRoot 'uzman.ps1')
# Türü seçilmeden verilen işler (tip = genel): Engineering Managerʼın yönlendirmesi
. (Join-Path $PSScriptRoot 'yonlendirme.ps1')
# Takılan işler: Incident Manager
. (Join-Path $PSScriptRoot 'cozucu.ps1')
# Ekip içi yardımlaşma (ajan iş sırasında Engineering Managerʼdan yardım ister) ve QA Engineer
. (Join-Path $PSScriptRoot 'yardim.ps1')

# ---------------------------------------------------------------- yardımcılar
function Tur-Klasoru($G) {
    $k = Join-Path (Gorev-Klasoru $G.id) ('tur{0}' -f $G.tur)
    if (-not (Test-Path -LiteralPath $k)) { New-Item -ItemType Directory -Force $k | Out-Null }
    return $k
}
function Gorev-Metni($G) { Metin-Oku (Join-Path (Gorev-Klasoru $G.id) 'gorev.md') }
function Plan-Metni($G)  { Metin-Oku (Join-Path (Gorev-Klasoru $G.id) 'plan.md') }

function Gecmis-Ekle($G, [string]$Olay, [string]$Ayrinti = '', $Sonuc = $null) {
    $k = [ordered]@{ zaman = (Simdi); asama = $G.asama; tur = $G.tur; olay = $Olay; ayrinti = (Kisalt $Ayrinti 400) }
    if ($Sonuc) { $k.arac = '{0}/{1}' -f $Sonuc.arac, $Sonuc.model; $k.sure_sn = $Sonuc.sure_sn }
    $liste = @()
    if ($G.gecmis) { $liste = @($G.gecmis) }
    Ayarla $G 'gecmis' ($liste + ([pscustomobject]$k))
}
function Asama-Gec($G, [string]$Yeni, [string]$Olay, [string]$Ayrinti = '', $Sonuc = $null) {
    Gecmis-Ekle $G $Olay $Ayrinti $Sonuc
    $G.asama = $Yeni
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'son_hata' ''
    Gunluk "Görev $($G.id): -> $Yeni ($Olay)"
}
function Takildi($G, [string]$Neden) {
    Gecmis-Ekle $G 'takıldı' $Neden
    Ayarla $G 'takildi_asama' $G.asama
    $G.asama = 'takildi'
    Ayarla $G 'son_hata' (Kisalt $Neden 500)
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'takildi_zamani' (Simdi)
    if ([string]$G.cozum_durumu -ne 'yardim_bekleniyor') { Ayarla $G 'cozum_durumu' '' }
    Sayac-Artir 'takilan'
    Gunluk "Görev $($G.id) TAKILDI: $Neden" 'UYARI'
    # Incident Manager üstlenecekse kullanıcıyı hemen rahatsız etme; kararına göre o bildirir (cozucu.ps1)
    if (Cozucu-Ustlenir $G) { Gunluk "Görev $($G.id): takılma Incident Managerʼa bırakıldı"; return }
    Bildir -Baslik "Görev takıldı: $($G.baslik)" -Metin ('#{0}: {1} Devam için panelde "Devam" ya da durum.ps1 -Devam {0}' -f $G.id, (Kisalt $Neden 160)) -Anahtar "takildi-$($G.id)" -Onem 'yuksek' -AralikDk 30
}
function Adim-Basarisiz($G, [string]$Hata) {
    # Görev adım sürerken iptal edildiyse başarısızlık sayma: yeniden deneme planlama, "takıldı" bildirimi gönderme
    if (Gorev-Iptal-mi $G.id) { Gunluk "Görev $($G.id): '$($G.asama)' adımı iptal edilmiş görevde sona erdi; başarısız sayılmadı ($(Kisalt $Hata 160))" 'UYARI'; return }
    # Ajan ekip içi yardım istediyse başarısızlık sayma: istek Engineering Managerʼa gider (yardim.ps1)
    if ($script:YardimIstegi -and [string]$script:YardimIstegi.gorev -eq [string]$G.id) {
        $y = $script:YardimIstegi; $script:YardimIstegi = $null
        if (Yardim-Istegi-Kaydet $G $y) { return }
        $Hata = "$Hata (ekip içi yardım hakkı doldu)"
    }
    $G.deneme = [int]$G.deneme + 1
    Ayarla $G 'son_hata' (Kisalt $Hata 500)
    Gecmis-Ekle $G 'deneme başarısız' $Hata
    $max = [int]$Ayar.dongu.max_adim_denemesi
    if ($G.deneme -ge $max) {
        Takildi $G ("'{0}' aşaması {1} denemede tamamlanamadı: {2}" -f (Asama-Adi $G.asama), $G.deneme, (Kisalt $Hata 200))
        return
    }
    $bekle = [int]$Ayar.dongu.hata_bekleme_dk * [int]$G.deneme
    Ayarla $G 'sonraki_deneme' ((Get-Date).AddMinutes($bekle).ToString('o'))
    Gunluk "Görev $($G.id): '$($G.asama)' başarısız ($($G.deneme)/$max), $bekle dk sonra yeniden denenecek" 'UYARI'
}
function Yeni-Tur($G, [string]$GeriBildirim, [string]$Neden) {
    if ([int]$G.tur -ge [int]$G.max_tur) {
        # Kullanıcı "durum.ps1 -Devam" derse bu geri bildirimle yeni tur açılır
        Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) 'bekleyen-geri-bildirim.md') $GeriBildirim
        Takildi $G ('{0} turda tamamlanamadı. Son sorun: {1}' -f $G.tur, (Kisalt $Neden 200))
        return
    }
    Gecmis-Ekle $G 'yeni tura dönüldü' $Neden
    $G.tur = [int]$G.tur + 1
    $tk = Tur-Klasoru $G
    Metin-Yaz (Join-Path $tk 'geri-bildirim.md') $GeriBildirim
    $G.asama = 'gelistirme'
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Gunluk "Görev $($G.id): $($G.tur). tur başlıyor ($Neden)"
}
function Diff-Hazirla($G) {
    $wt = $G.calisma_klasoru
    $tk = Tur-Klasoru $G
    Git-Calistir $wt @('add', '-A') | Out-Null
    $stat = Git-Calistir $wt @('diff', '--cached', '--stat')
    $diff = Git-Dosyaya $wt 'diff --cached --no-color' (Join-Path $tk 'degisiklik.diff')
    $sinir = [int]$Ayar.gorev.diff_karakter_siniri
    if ($diff.Length -gt $sinir) { $diff = $diff.Substring(0, $sinir) + "`n... (diff $sinir karakterde kesildi; tamamı için dosyaları oku)" }
    return @{ stat = $stat; diff = $diff }
}
function Kayit-Klasoru($G) { Join-Path (Gorev-Klasoru $G.id) 'kayitlar' }

# ---------------------------------------------------------------- adımlar
# Görevin git dalını ve çalışma ağacını (calisma\<no>) hazırlar; sorun varsa açıklamasını döndürür, yoksa ''
function Calisma-Agaci-Kur($G) {
    if (-not $G.klasor -or -not (Test-Path -LiteralPath $G.klasor)) { return "Proje klasörü bulunamadı: $($G.klasor)" }
    Git-Calistir $G.klasor @('rev-parse', '--show-toplevel') -Sessiz | Out-Null
    if ($script:GitKod -ne 0) { return "Proje bir git deposu değil: $($G.klasor)" }
    $dal = "ekip/$($G.id)"
    $wt = Join-Path $YolCalisma $G.id
    $gecerli = $false
    if (Test-Path -LiteralPath $wt) {
        Git-Calistir $wt @('rev-parse', '--is-inside-work-tree') -Sessiz | Out-Null
        $gecerli = ($script:GitKod -eq 0)
    }
    if (-not $gecerli) {
        if (Test-Path -LiteralPath $wt) { Remove-Item -LiteralPath $wt -Recurse -Force }
        Git-Calistir $G.klasor @('worktree', 'prune') -Sessiz | Out-Null
        Git-Calistir $G.klasor @('rev-parse', '--verify', '--quiet', "refs/heads/$dal") -Sessiz | Out-Null
        if ($script:GitKod -eq 0) {
            Git-Calistir $G.klasor @('worktree', 'add', $wt, $dal) | Out-Null
        } else {
            $temel = 'HEAD'
            $p = Proje-Bul $G.proje
            if ($p -and $p.temel_dal) { $temel = [string]$p.temel_dal }
            Git-Calistir $G.klasor @('worktree', 'add', '-b', $dal, $wt, $temel) | Out-Null
        }
    }
    Ayarla $G 'dal' $dal
    Ayarla $G 'calisma_klasoru' $wt
    Ayarla $G 'calisma_klasoru_kaldirildi' $false
    Ayarla $G 'temel_commit' (Git-Calistir $wt @('rev-parse', 'HEAD'))
    return ''
}
function Adim-Hazirla($G) {
    $h = Calisma-Agaci-Kur $G
    if ($h) { Takildi $G $h; return }
    Asama-Gec $G 'plan' 'çalışma dalı hazır' ('{0} @ {1}' -f $G.dal, ([string]$G.temel_commit).Substring(0, 8))
}

function Adim-Plan($G) {
    $istem = Sablon-Doldur 'lider-plan.md' @{ GOREV = (Gorev-Metni $G); KADRO = (Kadro-Metni) }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor $G.calisma_klasoru -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'plan'
    if (-not $r.basarili) { Adim-Basarisiz $G "Engineering Manager plan yazamadı: $($r.hata)"; return }
    $gk = Gorev-Klasoru $G.id
    Ayarla $G 'lider' ('{0}/{1}' -f $r.arac, $r.model)
    switch (Karar-Oku $r.metin) {
        'PLAN_HAZIR' {
            Metin-Yaz (Join-Path $gk 'plan.md') $r.metin
            # Engineering Manager güvenlik / mimari gibi ek uzman incelemesi istediyse (uzman.ps1 > Ek-Incelemeler)
            $ek = Ek-Inceleme-Coz (Alan-Oku $r.metin 'EK_INCELEME')
            Ayarla $G 'ek_inceleme' @($ek)
            $ayrinti = ''; if ($ek.Count) { $ayrinti = 'ek inceleme: ' + ($ek -join ', ') }
            # Planda ön işler istendiyse ("YARDIM: <anahtar> | <iş>") önce onlar yapılır, sonra geliştirme başlar
            $isler = Plan-Yardimlari $G $r.metin
            if ($isler.Count) { Gecmis-Ekle $G 'plan hazır' $ayrinti $r; [void](Yardim-Isleri-Ac $G $isler 'Engineering Manager (plan)' 'gelistirme'); return }
            Asama-Gec $G 'gelistirme' 'plan hazır' $ayrinti $r
        }
        'UZMAN' {
            # Kod değil, başka bir uzmanlık işi (tasarım, mimari belge, güvenlik denetimi, iletişim…)
            Metin-Yaz (Join-Path $gk 'yonlendirme.md') $r.metin
            Uzmana-Aktar $G 'Engineering Manager işi uzman çalışana yönlendirdi' $r (Kadro-Anahtar-Coz (Alan-Oku $r.metin 'SORUMLU')) ''
        }
        'ISE_ALIM' {
            # Kadroda bu işi yapabilecek kimse yok: İK işe alır, görev uzman akışında yeniden planlanır
            Metin-Yaz (Join-Path $gk 'yonlendirme.md') $r.metin
            $aranan = Alan-Oku $r.metin 'ARANAN'; if (-not $aranan) { $aranan = Kisalt $r.metin 500 }
            Uzmana-Aktar $G 'Engineering Manager İK''dan işe alım istedi' $r '' $aranan
        }
        'ALTYAPI' {
            # Sunucu / kurulum / ağ işi: System Administrator + Network Engineer ekibine aktar (altyapi.ps1)
            Metin-Yaz (Join-Path $gk 'yonlendirme.md') $r.metin
            Altyapiya-Aktar $G 'Engineering Manager işi altyapı ekibine yönlendirdi' $r
        }
        'SORU_VAR' {
            Metin-Yaz (Join-Path $gk 'sorular.md') $r.metin
            Gecmis-Ekle $G 'Engineering Manager soru sordu' '' $r
            $G.asama = 'bekliyor_kullanici'
            $G.deneme = 0
            Ayarla $G 'soru_zamani' (Simdi)
            Bildir -Baslik "Engineering Manager soru soruyor: $($G.baslik)" -Metin ("#{0}: sorular.md dosyasını oku, yanıtlarını gorev.md'ye ekleyip kaydet; ekip kendiliğinden devam eder." -f $G.id) -Anahtar "soru-$($G.id)" -Onem 'yuksek'
        }
        default {
            Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin
            Adim-Basarisiz $G "Plan çıktısında KARAR satırı yok ($($r.arac))"
        }
    }
}

function Adim-Gelistirme($G) {
    $tk = Tur-Klasoru $G
    $gb = Metin-Oku (Join-Path $tk 'geri-bildirim.md')
    if (-not $gb) { $gb = '(Yok; bu ilk tur.)' }
    $istem = Sablon-Doldur 'gelistirici.md' @{ GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G); GERI_BILDIRIM = $gb; TUR = [string]$G.tur }
    $r = Ajan-Cagir -Rol 'gelistirici' -Istem $istem -Klasor $G.calisma_klasoru -KayitKlasoru $tk -Etiket 'gelistirme' -Yazabilir
    if (-not $r.basarili) { Adim-Basarisiz $G "Software Developer çalışamadı: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'gelistirici-ozet.md') $r.metin
    Ayarla $G 'gelistirici' ('{0}/{1}' -f $r.arac, $r.model)
    Asama-Gec $G 'kontrol' 'geliştirme bitti' '' $r
}

function Adim-Kontrol($G) {
    $wt = $G.calisma_klasoru
    $tk = Tur-Klasoru $G
    $sorunlar = New-Object 'Collections.Generic.List[string]'
    $rapor = New-Object Text.StringBuilder

    Git-Calistir $wt @('add', '-A') | Out-Null
    $dosyalar = @((Git-Calistir $wt @('diff', '--cached', '--name-only')) -split "`n" | Where-Object { $_.Trim() })
    [void]$rapor.AppendLine("### Değişen dosyalar ($($dosyalar.Count))")
    foreach ($f in ($dosyalar | Select-Object -First 40)) { [void]$rapor.AppendLine("- $f") }
    if ($dosyalar.Count -eq 0) { $sorunlar.Add('Hiçbir dosya değişmemiş; görev uygulanmamış görünüyor.') }
    if ($dosyalar.Count -gt [int]$Ayar.gorev.max_degisen_dosya) { $sorunlar.Add("Çok fazla dosya değişmiş ($($dosyalar.Count)); kapsam taşmış olabilir.") }

    foreach ($f in $dosyalar) {
        $ad = Split-Path $f -Leaf
        foreach ($d in @($Ayar.korunan_desenler)) { if ($ad -like $d) { $sorunlar.Add("Korunan dosya değişmiş: $f"); break } }
    }

    # Gizli bilgi taraması: yalnızca eklenen satırlar
    $u0 = Git-Dosyaya $wt 'diff --cached -U0 --no-color' (Join-Path $tk 'degisiklik-u0.diff')
    $desenler = @(
        '-----BEGIN [A-Z ]*PRIVATE KEY-----', 'AKIA[0-9A-Z]{16}', 'gh[pousr]_[A-Za-z0-9]{30,}', 'github_pat_[A-Za-z0-9_]{20,}',
        'ASIA[0-9A-Z]{16}', 'gha_[A-Za-z0-9_-]{30,}', 'ghc_[A-Za-z0-9_-]{30,}',
        'npm_[A-Za-z0-9]{36}', 'sk_(live|test)_[A-Za-z0-9]{24,}',
        'sk-(ant-)?[A-Za-z0-9_-]{20,}', 'xox[baprs]-[A-Za-z0-9-]{10,}', 'AIza[0-9A-Za-z_-]{35}',
        '(?i)(password|passwd|parola|sifre|şifre|secret|api[_-]?key|token)\s*[:=]\s*[''"][^''"\s]{6,}[''"]'
    )
    $supheli = 0
    foreach ($satir in ($u0 -split "`n")) {
        if ($satir -notmatch '^\+' -or $satir -match '^\+\+\+ ') { continue }
        foreach ($d in $desenler) { if ($satir -match $d) { $supheli++; break } }
    }
    if ($supheli -gt 0) { $sorunlar.Add("Eklenen satırlarda $supheli olası gizli bilgi (parola/anahtar) var; kaldırılmalı ya da yapılandırmaya taşınmalı.") }
    $taramaSonuc = 'temiz'
    if ($supheli -gt 0) { $taramaSonuc = "$supheli şüpheli satır" }
    [void]$rapor.AppendLine('')
    [void]$rapor.AppendLine("### Gizli bilgi taraması: $taramaSonuc")

    # Doğrulama komutları (projeler.json ve görev tanımından; yapay zeka üretmez)
    $komutlar = @()
    $p = Proje-Bul $G.proje
    if ($p -and $p.dogrulama) { $komutlar += @($p.dogrulama) }
    if ($G.dogrulama) { $komutlar += @($G.dogrulama) }
    [void]$rapor.AppendLine('')
    [void]$rapor.AppendLine('### Doğrulama komutları')
    if (-not $komutlar) { [void]$rapor.AppendLine('- (bu projede tanımlı doğrulama komutu yok)') }
    $i = 0
    foreach ($k in $komutlar) {
        $i++
        $cik = Join-Path $tk "dogrulama-$i.txt"
        $s = Surec-Calistir -Komut $k -Cikti $cik -Klasor $wt -ZamanAsimiDk ([int]$Ayar.zaman_asimi_dk.dogrulama) -Etiket "doğrulama $i"
        $durum = "KALDI (kod $($s.kod))"
        if ($s.zaman_asimi) { $durum = 'ZAMAN AŞIMI' } elseif ($s.kod -eq 0) { $durum = 'GEÇTİ' }
        [void]$rapor.AppendLine("- ``$k`` -> **$durum** ($($s.sure_sn) sn)")
        [void]$rapor.AppendLine('```')
        [void]$rapor.AppendLine((Son-Satirlar (Metin-Oku $cik) 25))
        [void]$rapor.AppendLine('```')
        if ($s.zaman_asimi -or $s.kod -ne 0) { $sorunlar.Add("Doğrulama başarısız: $k ($durum)") }
    }

    $gecti = ($sorunlar.Count -eq 0)
    $baslik = 'KALDI'; if ($gecti) { $baslik = 'GEÇTİ' }
    $metin = "## Otomatik kontrol: $baslik`n`n"
    if (-not $gecti) { $metin += "### Sorunlar`n" + (($sorunlar | ForEach-Object { "- $_" }) -join "`n") + "`n`n" }
    $metin += $rapor.ToString()
    Metin-Yaz (Join-Path $tk 'kontrol.md') $metin
    Ayarla $G 'son_kontrol' $baslik
    if ($gecti) { Asama-Gec $G 'denetim' 'otomatik kontroller geçti' ('{0} dosya, {1} komut' -f $dosyalar.Count, @($komutlar).Count) }
    else { Yeni-Tur $G $metin ('otomatik kontroller kaldı: ' + ($sorunlar -join '; ')) }
}

function Adim-Denetim($G) {
    $tk = Tur-Klasoru $G
    $d = Diff-Hazirla $G
    $istem = Sablon-Doldur 'denetci.md' @{
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G)
        GELISTIRICI_OZET = (Metin-Oku (Join-Path $tk 'gelistirici-ozet.md'))
        KONTROL = (Metin-Oku (Join-Path $tk 'kontrol.md'))
        DIFF_OZET = $d.stat; DIFF = $d.diff
    }
    # Yazar kendi işini denetlemesin
    $haric = @(); if ($G.gelistirici) { $haric = @([string]$G.gelistirici) }
    $r = Ajan-Cagir -Rol 'denetci' -Istem $istem -Klasor $G.calisma_klasoru -KayitKlasoru $tk -Etiket 'denetim' -Haric $haric
    if (-not $r.basarili) { Adim-Basarisiz $G "Code Reviewer çalışamadı: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'denetim.md') $r.metin
    Ayarla $G 'denetci' ('{0}/{1}' -f $r.arac, $r.model)
    switch (Karar-Oku $r.metin) {
        'ONAY' {
            if (@($G.ek_inceleme | Where-Object { $_ }).Count) {
                # Code Reviewer onayladı; lider güvenlik / mimari ek incelemesi istemişti
                $ek = Ek-Incelemeler $G $tk $d
                if ($ek.yardim) { Adim-Basarisiz $G 'ek inceleme ekip içi yardım istedi'; return }
                if ($ek.duzelt) {
                    Gecmis-Ekle $G 'ek inceleme düzeltme istedi' '' $r
                    Yeni-Tur $G ("## Ek inceleme düzeltme istedi`n`n" + $ek.duzelt_metni) 'ek inceleme düzeltme istedi'
                    return
                }
            }
            $sonraki = 'tamamla'; if ($Ayar.gorev.lider_kabul) { $sonraki = 'kabul' }
            Asama-Gec $G $sonraki 'Code Reviewer onayladı' '' $r
        }
        'DUZELT' {
            Gecmis-Ekle $G 'Code Reviewer düzeltme istedi' '' $r
            Yeni-Tur $G ("## Code Reviewer düzeltme istedi`n`n" + $r.metin) 'Code Reviewer düzeltme istedi'
        }
        default { Adim-Basarisiz $G "Denetim çıktısında KARAR satırı yok ($($r.arac))" }
    }
}

function Adim-Kabul($G) {
    $tk = Tur-Klasoru $G
    $d = Diff-Hazirla $G
    $istem = Sablon-Doldur 'lider-kabul.md' @{
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G)
        GELISTIRICI_OZET = (Metin-Oku (Join-Path $tk 'gelistirici-ozet.md'))
        KONTROL = (Metin-Oku (Join-Path $tk 'kontrol.md'))
        DENETIM = ((Metin-Oku (Join-Path $tk 'denetim.md')) + (Ek-Inceleme-Raporlari $tk))
        DIFF_OZET = $d.stat; DIFF = $d.diff
    }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor $G.calisma_klasoru -KayitKlasoru $tk -Etiket 'kabul'
    if (-not $r.basarili) { Adim-Basarisiz $G "Engineering Manager son kararı veremedi: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'kabul.md') $r.metin
    switch (Karar-Oku $r.metin) {
        'KABUL' {
            Ayarla $G 'commit_mesaji' (Alan-Oku $r.metin 'COMMIT')
            Ayarla $G 'ozet' (Alan-Oku $r.metin 'OZET')
            Asama-Gec $G 'tamamla' 'Engineering Manager kabul etti' '' $r
        }
        'RET' {
            Gecmis-Ekle $G 'Engineering Manager reddetti' '' $r
            Yeni-Tur $G ("## Engineering Manager reddetti`n`n" + $r.metin) 'Engineering Manager reddetti'
        }
        default { Adim-Basarisiz $G "Kabul çıktısında KARAR satırı yok ($($r.arac))" }
    }
}

function Adim-Tamamla($G) {
    $wt = $G.calisma_klasoru
    $gk = Gorev-Klasoru $G.id
    Git-Calistir $wt @('add', '-A') | Out-Null
    Git-Calistir $wt @('diff', '--cached', '--quiet') -Sessiz | Out-Null
    $bekleyenVar = ($script:GitKod -ne 0)
    if ($bekleyenVar) {
        $baslik = [string]$G.commit_mesaji
        if (-not $baslik) { $baslik = [string]$G.baslik }
        if ($baslik.Length -gt 72) { $baslik = $baslik.Substring(0, 72) }
        $govde = @(
            $baslik, '',
            "AI Ekip görevi: $($G.id)",
            "Engineering Manager: $($G.lider) | Software Developer: $($G.gelistirici) | Code Reviewer: $($G.denetci) | Tur: $($G.tur)",
            '', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
        ) -join "`n"
        $mf = Join-Path $gk 'commit-mesaji.txt'
        Metin-Yaz $mf $govde
        $kimlik = @()
        $eposta = Git-Calistir $wt @('config', 'user.email') -Sessiz
        if (-not $eposta) { $kimlik = @('-c', 'user.name=AI Ekip', '-c', 'user.email=ai-ekip@localhost') }
        Git-Calistir $wt ($kimlik + @('commit', '-q', '-F', $mf)) | Out-Null
    }
    $commit = Git-Calistir $wt @('rev-parse', '--short', 'HEAD')
    if ($commit -eq ([string]$G.temel_commit).Substring(0, $commit.Length)) { Takildi $G 'Commit edilecek değişiklik bulunamadı.'; return }
    Ayarla $G 'commit' $commit
    Git-Calistir $G.klasor @('worktree', 'remove', $wt) -Sessiz | Out-Null
    Ayarla $G 'calisma_klasoru_kaldirildi' ($script:GitKod -eq 0)
    Asama-Gec $G 'tamam' 'commit edildi' "$($G.dal) @ $commit"
    Sayac-Artir 'tamamlanan'
    $ozet = [string]$G.ozet
    if (-not $ozet) { $ozet = 'Değişiklik hazır.' }
    $kapanis = ' İnceleyip birleştirebilirsin.'
    if ($ozet -match 'birleştir') { $kapanis = '' }
    Bildir -Baslik "Görev tamamlandı: $($G.baslik)" -Metin ('{0} Dal: {1} ({2} tur).{3}' -f (Kisalt $ozet 140), $G.dal, $G.tur, $kapanis) -Anahtar "tamam-$($G.id)"
}

# ---------------------------------------------------------------- görev seçimi ve ilerletme
function Gorev-Ilerlet($G) {
    $script:AktifGorev = $G.id
    $script:AktifAdim = $G.asama
    $basAsama = [string]$G.asama
    $basTur = $G.tur
    $script:YardimIstegi = $null
    $script:BekleyenPuan = $null
    $script:AdimBaslangic = Get-Date
    Kalp 'çalışıyor'
    Gunluk "Görev $($G.id) [$($G.asama), tur $($G.tur)] ilerletiliyor"
    try {
        if ($G.asama -eq 'yardim') { Yardim-Yonlendir $G }
        elseif ($G.tip -eq 'altyapi') { Altyapi-Adim $G }
        elseif ($G.tip -eq 'uzman') { Uzman-Adim $G }
        elseif ($G.tip -eq 'genel') { Genel-Adim $G }
        else { switch ($G.asama) {
            'yeni'       { Adim-Hazirla $G }
            'plan'       { Adim-Plan $G }
            'gelistirme' { Adim-Gelistirme $G }
            'kontrol'    { Adim-Kontrol $G }
            'denetim'    { Adim-Denetim $G }
            'kabul'      { Adim-Kabul $G }
            'tamamla'    { Adim-Tamamla $G }
        } }
    } catch {
        $h = $_.Exception.Message
        Gunluk ("Görev {0} '{1}' hata: {2} @ {3}" -f $G.id, $G.asama, $h, ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) 'HATA'
        Adim-Basarisiz $G $h
    }
    # Adım (ajan çağrısı) sürerken kullanıcı görevi iptal ettiyse bellekteki eski kopya iptali ezmesin:
    # diskteki kaydı yeniden oku; iptalse adımın sonucunu yazma, yalnızca geçmişe not düş.
    $disk = Gorev-Diskten $G.id
    $tasindi = Gorev-Elle-Tasindi-mi $disk
    $script:AdimBaslangic = $null
    if ($disk -and [string]$disk.asama -ne 'iptal' -and $tasindi) {
        # Kullanıcı adım sürerken işi panoda başka aşamaya taşıdı: adımın sonucu taşımayı ezmesin
        $ne = "'{0}' adımı (tur {1}) panoda taşındıktan sonra bitti; sonucu kaydedilmedi" -f (Asama-Adi $basAsama), $basTur
        Gecmis-Ekle $disk 'taşıma sonrası adım sonucu yok sayıldı' $ne
        $script:BekleyenPuan = $null
        Gorev-Kaydet $disk
        Gunluk "Görev $($G.id) adım sürerken panoda taşınmış ($($disk.elle_tasima.onceki) -> $($disk.asama)); adım sonucu yok sayıldı" 'UYARI'
        return
    }
    if ($disk -and [string]$disk.asama -eq 'iptal') {
        $ne = "'{0}' adımı (tur {1}) iptalden sonra bitti; sonucu kaydedilmedi" -f (Asama-Adi $basAsama), $basTur
        if ([string]$G.asama -ne $basAsama -or [string]$G.tur -ne [string]$basTur) { $ne += " (adım görevi '{0}', tur {1} durumuna taşıyacaktı)" -f (Asama-Adi $G.asama), $G.tur }
        Gecmis-Ekle $disk 'iptal sonrası adım sonucu yok sayıldı' $ne
        Gorev-Kaydet $disk
        Gunluk "Görev $($G.id) adım sürerken iptal edilmiş; adım sonucu yok sayıldı, görev iptalde kaldı" 'UYARI'
        return
    }
    Gorev-Kaydet $G
}
function Siradaki-Gorev {
    $simdi = Get-Date
    $adaylar = @(Gorevleri-Listele | Where-Object {
        ($AktifAsamalar -contains $_.asama) -and (-not $_.sonraki_deneme -or ([datetime]$_.sonraki_deneme) -le $simdi)
    })
    if ($adaylar.Count -eq 0) { return $null }
    # Önce başlamış işleri bitir, sonra öncelik (1 en yüksek), sonra eklenme sırası
    return ($adaylar | Sort-Object @{ e = { if ($_.asama -eq 'yeni') { 1 } else { 0 } } }, @{ e = { [int]$_.oncelik } }, @{ e = { $_.id } } | Select-Object -First 1)
}
function Bekleyenleri-Kontrol {
    foreach ($g in (Gorevleri-Listele)) {
        if ($g.asama -ne 'bekliyor_kullanici' -or -not $g.soru_zamani) { continue }
        $f = Join-Path (Gorev-Klasoru $g.id) 'gorev.md'
        if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).LastWriteTime -gt [datetime]$g.soru_zamani) {
            Gecmis-Ekle $g 'kullanıcı gorev.md dosyasını güncelledi'
            # Ekip içi yardım isteği kullanıcıya sorulduysa iş kaldığı aşamadan sürer; değilse yeniden planlanır
            $hedef = 'plan'
            if ($g.soru_donus_asama -and ($AktifAsamalar -contains [string]$g.soru_donus_asama)) {
                $hedef = [string]$g.soru_donus_asama
                Ayarla $g 'soru_donus_asama' ''
                Yardim-Sonucu-Ekle $g 'Kullanıcının yanıtı' 'Kullanıcı yanıtını görev tanımının "Notlar ve yanıtlar" bölümüne yazdı (GÖREV metnine bak).'
            }
            $g.asama = $hedef; $g.deneme = 0
            Gorev-Kaydet $g
            Gunluk "Görev $($g.id): kullanıcı yanıt verdi, '$hedef' aşamasından sürecek"
        }
    }
}
function Mesaide-mi {
    $s = [string]$Ayar.dongu.calisma_saatleri
    if (-not $s -or $s -eq '00:00-24:00') { return $true }
    $p = $s -split '-'
    $an = (Get-Date).TimeOfDay
    $b = [timespan]::Parse($p[0])
    $e = [timespan]::FromHours(24); if ($p[1] -ne '24:00') { $e = [timespan]::Parse($p[1]) }
    if ($b -le $e) { return ($an -ge $b -and $an -lt $e) }
    return ($an -ge $b -or $an -lt $e)
}
function Betik-Damgasi {
    $f = Get-ChildItem -LiteralPath $Kok -Filter '*.ps1' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    return $f.LastWriteTimeUtc.Ticks
}
function Bekle([int]$Sn) {
    $bas = Get-Date
    $bitis = $bas.AddSeconds($Sn)
    while ((Get-Date) -lt $bitis) {
        Start-Sleep -Seconds 20
        Kalp 'boşta'
        if (Test-Path (Join-Path $Kok 'DURDUR')) { return }
        # Yeni görev eklendiyse ya da bir görev düzenlendiyse beklemeyi kes
        $degisen = Get-ChildItem -LiteralPath $YolGorev -Recurse -Include 'durum.json', 'gorev.md' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $bas } | Select-Object -First 1
        if ($degisen) { return }
    }
}
function Ekip-Durumu-Kisa {
    $parca = @()
    foreach ($rol in @('lider', 'gelistirici', 'denetci', 'sistem', 'ag', 'sorun-giderici')) {
        if (-not $Ayar.roller.$rol) { continue }
        $ilk = $null
        foreach ($g in @($Ayar.roller.$rol)) { if (-not (Arac-Uygun $g)) { $ilk = $g; break } }
        $ad = $rol; if ($rol -eq 'lider') { $ad = 'Engineering Manager' }
        if ($ilk) { $parca += ('{0}: {1}' -f $ad, $ilk.arac) } else { $parca += "${ad}: YOK" }
    }
    return ($parca -join ', ')
}

# ---------------------------------------------------------------- ana döngü
function Ekip-Dongusu {
    param([int]$AdimSiniri = 0, [switch]$BosBitir)
    $damga = Betik-Damgasi
    Ayarlari-Yukle
    Gunluk "=== AI Ekip döngüsü başladı (PID $PID) ==="
    $sirada = @(Gorevleri-Listele | Where-Object { $AktifAsamalar -contains $_.asama }).Count
    Bildir -Baslik 'AI Ekip mesaiye başladı' -Metin ('Sırada {0} görev var. Ekip: {1}' -f $sirada, (Ekip-Durumu-Kisa)) -Anahtar 'mesai' -AralikDk 240
    Rapor-Uret
    $adim = 0
    $hataSayisi = 0
    $sonRapor = Get-Date
    $durdurGunlendi = $false
    while ($true) {
        try {
            Ayarlari-Yukle
            Kalp 'döngü'
            if ((Betik-Damgasi) -ne $damga) { Gunluk 'Betikler güncellendi; döngü yeni sürümle yeniden yükleniyor'; return 'yeniden' }
            if (Test-Path (Join-Path $Kok 'DURDUR')) {
                if (-not $durdurGunlendi) { Gunluk 'DURDUR dosyası var; ekip bekliyor'; $durdurGunlendi = $true }
                Kalp 'durduruldu'
                if ($BosBitir) { return 'bitti' }
                Start-Sleep -Seconds 60
                continue
            }
            $durdurGunlendi = $false
            Ozet-Kontrol
            if (-not (Mesaide-mi)) { Kalp 'mesai dışı'; Start-Sleep -Seconds 300; continue }
            Bekleyenleri-Kontrol
            # Incident Manager: biten yardım işlerinin takılan işlerini sürdür, incelenmemiş takılma varsa önce onu incele
            Yardim-Gorevleri-Kontrol
            # Ekip içi yardım: yardım işleri biten görevler kaldıkları aşamadan sürer (yardim.ps1)
            Yardim-Bekleyenleri-Kontrol
            $tg = Cozulecek-Gorev
            if ($tg) {
                Sorun-Gider $tg
                Rapor-Uret
                $sonRapor = Get-Date
                $hataSayisi = 0
                Start-Sleep -Seconds ([int]$Ayar.dongu.adim_arasi_sn)
                continue
            }
            $g = Siradaki-Gorev
            if (-not $g) {
                $script:AktifGorev = ''; $script:AktifAdim = ''
                if (((Get-Date) - $sonRapor).TotalMinutes -ge 10) { Rapor-Uret; $sonRapor = Get-Date }
                if ($BosBitir) { Gunluk 'Hazır görev kalmadı; döngüden çıkılıyor (-BosBitir)'; Rapor-Uret; return 'bitti' }
                # Ofis boştayken Incident Manager başarısız / iptal edilen işlerin kök nedenini kategorilere ayırır (cozucu.ps1)
                $kg = Kategorilenecek-Gorev
                if ($kg) { Kok-Neden-Belirle $kg; Start-Sleep -Seconds ([int]$Ayar.dongu.adim_arasi_sn); continue }
                Kalp 'boşta'
                Bekle ([int]$Ayar.dongu.bos_bekleme_sn)
                continue
            }
            Gorev-Ilerlet $g
            Rapor-Uret
            $sonRapor = Get-Date
            $hataSayisi = 0
            $adim++
            if ($AdimSiniri -gt 0 -and $adim -ge $AdimSiniri) { Gunluk "Adım sınırına ulaşıldı ($AdimSiniri)"; return 'bitti' }
            Start-Sleep -Seconds ([int]$Ayar.dongu.adim_arasi_sn)
        } catch {
            $hataSayisi++
            $mesaj = $_.Exception.Message
            Gunluk ('Döngü hatası ({0}. ardışık): {1} @ {2}' -f $hataSayisi, $mesaj, ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) 'HATA'
            if ($hataSayisi -ge 5) {
                try { Bildir -Baslik 'AI Ekip hata veriyor' -Metin ("Döngü üst üste {0} kez hata verdi: {1}" -f $hataSayisi, (Kisalt $mesaj 150)) -Anahtar 'dongu-hata' -Onem 'yuksek' -AralikDk 120 } catch {}
            }
            Start-Sleep -Seconds ([Math]::Min(600, 30 * $hataSayisi))
        }
    }
}
