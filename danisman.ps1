<#
danisman.ps1 - Outsource Consultant (anahtar danisman; durum.json > tip = "danisman"). ekip.ps1 dot-source eder.

Paralel ekip çalışması gerektirmeyen, tek bağlam penceresinde baştan sona çözülebilecek işleri iç ekibe dağıtmak yerine tek parça olarak
terminal yetkili Claude Code'a (claude -p, headless) verir:
  - Yönlendirme: Product Manager analizde "ATAMA: danisman" der ve "## Danışman brifi" bölümüne tek, net bir istem yazar
    (planlama.ps1 > Adim-Analiz). Kullanıcı işi doğrudan Outsource Consultant'a verdiyse (is-ver.ps1 -Rol danisman, panelde
    "Bu çalışana iş ver") yönlendirme zorunludur; Product Manager kapalıysa iş görev metniyle doğrudan devredilir (Genel-Adim).
  - Masa: ai-ekip\danisman\ (CLAUDE.md: danışmanın kuralları ve öncelikleri; yoksa istemler\danisman-claude.md şablonundan oluşur,
    sonra kullanıcı düzenleyebilir). Claude Code bu klasörde çalışır, CLAUDE.md'yi kendisi yükler; işin klasörü --add-dir ile açılır.
  - İzinler (ayarlar.json > danisman): --permission-mode dontAsk + --allowedTools (terminal dahil) + --disallowedTools; izin listesinde
    olmayan her şey sormadan reddedilir, arka planda onay bekleyip kilitlenmez (ortak.ps1 > Claude-Calistir, profil "danisman").

Aşamalar (adları diğer akışlarla aynı):
  yeni        çalışma klasörü: proje bir git deposuysa görev dalı (ekip/<no>, calisma\<no>), değilse calisma\<no> (+ cikti\)  [betik]
  gelistirme  Outsource Consultant işi baştan sona yapar; KARAR: TAMAM | SORU_VAR | YAPILAMADI                       [Claude Code]
  kontrol     değişen dosyalar, korunan dosyalar, gizli bilgi taraması, doğrulama komutları; kalırsa yeni tur           [betik]
  tamamla     git'te dala commit (iç ekip incelemesi yapılmadığı commit'e yazılır), değilse sonuc.md; bildirim ve
              Outsource Consultant'ın sohbetine rapor                                                                    [betik]
#>

function Danisman-Ayari {
    $o = [ordered]@{ etkin = $true; zaman_asimi_dk = 120 }
    $d = $Ayar.danisman
    if ($d) { foreach ($k in @($o.Keys)) { if ($d.PSObject.Properties[$k] -and $null -ne $d.$k) { $o[$k] = $d.$k } } }
    $o.etkin = [bool]$o.etkin
    return [pscustomobject]$o
}
# Danışman Claude Code'dur: zincirinde Claude yoksa (ör. yalnız Codex seçilen kurulum) katman atlanır, işler iç ekipte kalır
function Danisman-Hazir-mi {
    if (-not (Danisman-Ayari).etkin -or -not (Rol-Hazir-mi 'danisman')) { return $false }
    return (@($Ayar.roller.danisman | Where-Object { $_ -and [string]$_.arac -eq 'claude' }).Count -gt 0)
}
function Danisman-Masasi {
    $m = Join-Path $Kok 'danisman'
    if (-not (Test-Path -LiteralPath $m)) { New-Item -ItemType Directory -Force $m | Out-Null }
    $f = Join-Path $m 'CLAUDE.md'
    if (-not (Test-Path -LiteralPath $f)) {
        $codex = Codex-Exe; if (-not $codex) { $codex = '(bu makinede bulunamadı)' }
        Metin-Yaz $f (Sablon-Doldur 'danisman-claude.md' @{ KOK = $Kok; MASA = $m; CODEX = $codex })
        Gunluk "Outsource Consultant masası hazırlandı: $f"
    }
    return $m
}
# Danışmanın sohbetine (panelde çalışanla yazışma penceresi) rapor satırı
function Danisman-Sohbete-Yaz($G, [string]$Metin) {
    try {
        $kl = Join-Path $YolDurum 'sohbet'
        if (-not (Test-Path -LiteralPath $kl)) { New-Item -ItemType Directory -Force $kl | Out-Null }
        $k = [ordered]@{ zaman = (Simdi); kim = 'ajan'; metin = (Kisalt $Metin 4000); gorev = [string]$G.id }
        [void](Satir-Ekle (Join-Path $kl 'danisman.jsonl') ($k | ConvertTo-Json -Compress))
    } catch { Gunluk "Outsource Consultant sohbetine yazılamadı: $($_.Exception.Message)" 'UYARI' }
}

# Product Manager (ya da doğrudan atama) işi Outsource Consultant'a devreder: brif plan.md'ye yazılır, görev danışman akışına geçer
function Danismana-Aktar($G, [string]$Metin, $Sonuc, [string]$Kaynak) {
    $brif = Bolum-Oku $Metin 'Danışman brifi'
    if (-not $brif.Trim()) { $brif = Karar-Satirini-At $Metin }
    Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) 'plan.md') ("# Danışman brifi`n`n" + $brif.Trim() + "`n")
    $p = $null
    $pa = Alan-Oku $Metin 'PROJE'
    if ($pa -and $pa -notmatch '^(?i)\W*(yok|none|-)\W*$') { try { $p = Proje-Coz $pa } catch {} }
    if (-not $p -and [string]$G.ipucu) { try { $p = Proje-Coz ([string]$G.ipucu) } catch {} }
    $tip = [string]$G.tip
    if ($p) { $G.proje = [string]$p.ad; $G.klasor = [string]$p.klasor }
    elseif ($tip -ne 'yazilim') { $G.proje = 'danışman'; $G.klasor = '' }
    Ayarla $G 'tip' 'danisman'
    Ayarla $G 'onceki_tip' $tip
    Ayarla $G 'yonlendirme_karari' 'DANISMAN'
    Ayarla $G 'yonlendiren' $Kaynak
    $nerede = 'ayrı çalışma klasöründe'; if ($p) { $nerede = "proje: $($p.ad) (``$($p.klasor)``)" }
    Gorev-Notu-Ekle $G "$Kaynak yönlendirmesi" "İş tek parça olarak Outsource Consultantʼa (terminal yetkili Claude Code) verildi; $nerede. Brif: plan.md."
    Asama-Gec $G 'yeni' 'Outsource Consultantʼa verildi' "$Kaynak; $nerede" $Sonuc
}

# ---------------------------------------------------------------- adımlar
function Danisman-Hazirla($G) {
    $mod = 'klasor'
    if ([string]$G.klasor -and (Test-Path -LiteralPath ([string]$G.klasor) -PathType Container)) {
        $h = Calisma-Agaci-Kur $G
        if (-not $h) { $mod = 'git' }
        else { Ayarla $G 'kaynak_klasor' ([string]$G.klasor); Gunluk "Görev $($G.id): $h; Outsource Consultant ayrı klasörde çalışacak (proje okunabilir)" }
    }
    if ($mod -eq 'klasor') {
        $wt = Uzman-Calisma-Klasoru $G
        [void](Uzman-Cikti $G)
        Ayarla $G 'calisma_klasoru' $wt
        Ayarla $G 'dal' ''
    }
    Ayarla $G 'danisman_mod' $mod
    [void](Danisman-Masasi)
    $ne = [string]$G.calisma_klasoru; if ($mod -eq 'git') { $ne = "$($G.dal) @ $(([string]$G.temel_commit).Substring(0, 8))" }
    Asama-Gec $G 'gelistirme' 'çalışma klasörü hazır' $ne
}

function Danisman-Calis($G) {
    Kadro-Rolleri-Yukle
    $tk = Tur-Klasoru $G
    $wt = [string]$G.calisma_klasoru
    if (-not $wt -or -not (Test-Path -LiteralPath $wt)) { Asama-Gec $G 'yeni' 'çalışma klasörü yok; yeniden hazırlanacak'; return }
    $masa = Danisman-Masasi
    $gb = Metin-Oku (Join-Path $tk 'geri-bildirim.md'); if (-not $gb) { $gb = '(Yok; bu ilk tur.)' }
    if ([string]$G.danisman_mod -eq 'git') {
        $not = "Bu klasör projenin görev dalı ($($G.dal), git worktree). Değişiklikleri burada yap. git commit / push / dal değiştirme YAPMA: ekip betiği kontrol edip bu dala commit eder, kullanıcı inceleyip birleştirir."
    } else {
        $not = "Teslim dosyalarını (rapor, betik, veri, görsel…) $(Uzman-Cikti $G) klasörüne yaz; ara dosyaları çalışma klasöründe tut."
        if ($G.kaynak_klasor) { $not += " İlgili klasör: $($G.kaynak_klasor) (okuyabilirsin; iş açıkça istemedikçe değiştirme)." }
    }
    $istem = Sablon-Doldur 'danisman-gorev.md' @{
        CALISMA = $wt; KLASOR_NOTU = $not; TUR = [string]$G.tur; MASA = $masa
        BRIF = (Plan-Metni $G); GOREV = (Gorev-Metni $G); GERI_BILDIRIM = $gb
    }
    $ek = @($wt); if ($G.kaynak_klasor -and (Test-Path -LiteralPath ([string]$G.kaynak_klasor))) { $ek += [string]$G.kaynak_klasor }
    # Claude dışı yedeklere düşme: izin profili ve CLAUDE.md yalnızca Claude Code'da geçerli
    $haric = @($Ayar.roller.danisman | Where-Object { $_ -and [string]$_.arac -ne 'claude' } | ForEach-Object { '{0}/{1}' -f $_.arac, $_.model })
    $r = Ajan-Cagir -Rol 'danisman' -Istem $istem -Klasor $masa -KayitKlasoru $tk -Etiket 'danisman' -IzinProfili 'danisman' -EkKlasorler $ek -Haric $haric
    if (-not $r.basarili) { Adim-Basarisiz $G "Outsource Consultant çalışamadı: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'danisman-rapor.md') $r.metin
    Ayarla $G 'danisman' ('{0}/{1}' -f $r.arac, $r.model)
    $ozet = Alan-Oku $r.metin 'OZET'
    if ($ozet) { Ayarla $G 'ozet' (Kisalt $ozet 400) }
    $cm = Alan-Oku $r.metin 'COMMIT'; if ($cm) { Ayarla $G 'commit_mesaji' (Kisalt $cm 72) }
    switch (Karar-Oku $r.metin) {
        'SORU_VAR' {
            Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) 'sorular.md') $r.metin
            Ayarla $G 'soru_soran' 'danisman'
            Ayarla $G 'soru_donus_asama' 'gelistirme'
            Gecmis-Ekle $G 'Outsource Consultant soru sordu' '' $r
            $G.asama = 'bekliyor_kullanici'; $G.deneme = 0
            Ayarla $G 'soru_zamani' (Simdi)
            Danisman-Sohbete-Yaz $G ("❓ #{0} {1}: devam etmek için senden bilgi lazım. Soruları görev ayrıntısının Soru sekmesinde yanıtla.`n`n{2}" -f (No-Kisa $G.id), $G.baslik, (Kisalt (Bolum-Oku $r.metin 'Sorular') 1500))
            Bildir -Baslik "Outsource Consultant soru soruyor: $($G.baslik)" -Metin ("#{0}: panelde Soru sekmesinden yanıtla; iş kaldığı yerden sürer." -f (No-Kisa $G.id)) -Anahtar "soru-$($G.id)" -Onem 'yuksek'
        }
        'YAPILAMADI' {
            $neden = Kisalt ((Bolum-Oku $r.metin 'Açık kalanlar') + ' ' + $ozet).Trim() 300
            Danisman-Sohbete-Yaz $G ("⚠️ #{0} {1}: işi tamamlayamadım. {2}" -f (No-Kisa $G.id), $G.baslik, $neden)
            Takildi $G "Outsource Consultant işi yapamadı: $neden"
        }
        default {
            $ek2 = ''; if ((Karar-Oku $r.metin) -ne 'TAMAM') { $ek2 = 'KARAR satırı yok; otomatik kontrol karar verecek'; Gunluk "Görev $($G.id): Outsource Consultant çıktısında KARAR satırı yok" 'UYARI' }
            Asama-Gec $G 'kontrol' 'Outsource Consultant işi bitirdi' $ek2 $r
        }
    }
}

function Danisman-Kontrol($G) {
    $tk = Tur-Klasoru $G
    $wt = [string]$G.calisma_klasoru
    $sorunlar = New-Object 'Collections.Generic.List[string]'
    $rapor = New-Object Text.StringBuilder
    if ([string]$G.danisman_mod -eq 'git') {
        Git-Calistir $wt @('add', '-A') | Out-Null
        $dosyalar = @((Git-Calistir $wt @('diff', '--cached', '--name-only')) -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^(warning|hint):' })
        [void]$rapor.AppendLine("### Değişen dosyalar ($($dosyalar.Count))")
        foreach ($f in ($dosyalar | Select-Object -First 40)) { [void]$rapor.AppendLine("- $f") }
        if (-not $dosyalar.Count) { [void]$rapor.AppendLine('- (değişiklik yok: iş inceleme / rapor niteliğinde)') }
        if ($dosyalar.Count -gt [int]$Ayar.gorev.max_degisen_dosya) { $sorunlar.Add("Çok fazla dosya değişmiş ($($dosyalar.Count)); kapsam taşmış olabilir.") }
        foreach ($f in $dosyalar) { $ad = Split-Path $f -Leaf; foreach ($d in @($Ayar.korunan_desenler)) { if ($ad -like $d) { $sorunlar.Add("Korunan dosya değişmiş: $f"); break } } }
        $supheli = Gizli-Satir-Sayisi (Git-Dosyaya $wt 'diff --cached -U0 --no-color' (Join-Path $tk 'degisiklik-u0.diff'))
        if ($supheli -gt 0) { $sorunlar.Add("Eklenen satırlarda $supheli olası gizli bilgi (parola/anahtar) var; kaldırılmalı ya da yapılandırmaya taşınmalı.") }
        [void]$rapor.AppendLine(''); [void]$rapor.AppendLine("### Gizli bilgi taraması: $(if ($supheli) { "$supheli şüpheli satır" } else { 'temiz' })")
        $komutlar = @(); $p = Proje-Bul $G.proje; if ($p -and $p.dogrulama) { $komutlar += @($p.dogrulama) }
    } else {
        $t = Teslim-Listesi $G
        [void]$rapor.AppendLine("### Teslim dosyaları ($($t.adet), $(Uzman-Cikti $G))")
        if ($t.adet) { [void]$rapor.AppendLine($t.metin) } else { [void]$rapor.AppendLine('- (yok; sonuç danışman raporunda)') }
        $komutlar = @()
    }
    if ($G.dogrulama) { $komutlar += @($G.dogrulama | Where-Object { $_ }) }
    [void]$rapor.AppendLine(''); [void]$rapor.AppendLine('### Doğrulama komutları')
    if (-not $komutlar) { [void]$rapor.AppendLine('- (tanımlı doğrulama komutu yok)') }
    $i = 0
    foreach ($k in $komutlar) {
        $i++
        $cik = Join-Path $tk "dogrulama-$i.txt"
        $s = Surec-Calistir -Komut $k -Cikti $cik -Klasor $wt -ZamanAsimiDk ([int]$Ayar.zaman_asimi_dk.dogrulama) -Etiket "doğrulama $i"
        $durum = "KALDI (kod $($s.kod))"; if ($s.zaman_asimi) { $durum = 'ZAMAN AŞIMI' } elseif ($s.kod -eq 0) { $durum = 'GEÇTİ' }
        [void]$rapor.AppendLine("- ``$k`` -> **$durum** ($($s.sure_sn) sn)")
        [void]$rapor.AppendLine('```'); [void]$rapor.AppendLine((Son-Satirlar (Metin-Oku $cik) 25)); [void]$rapor.AppendLine('```')
        if ($s.zaman_asimi -or $s.kod -ne 0) { $sorunlar.Add("Doğrulama başarısız: $k ($durum)") }
    }
    $gecti = ($sorunlar.Count -eq 0)
    $metin = "## Otomatik kontrol: $(if ($gecti) { 'GEÇTİ' } else { 'KALDI' })`n`n"
    if (-not $gecti) { $metin += "### Sorunlar`n" + (($sorunlar | ForEach-Object { "- $_" }) -join "`n") + "`n`n" }
    $metin += $rapor.ToString()
    Metin-Yaz (Join-Path $tk 'kontrol.md') $metin
    Ayarla $G 'son_kontrol' $(if ($gecti) { 'GEÇTİ' } else { 'KALDI' })
    if ($gecti) { Asama-Gec $G 'tamamla' 'otomatik kontroller geçti' '' }
    else { Yeni-Tur $G $metin ('otomatik kontroller kaldı: ' + ($sorunlar -join '; ')) }
}

function Danisman-Tamamla($G) {
    $gk = Gorev-Klasoru $G.id
    $wt = [string]$G.calisma_klasoru
    $ozet = [string]$G.ozet; if (-not $ozet) { $ozet = 'İş tamamlandı.' }
    $dalNotu = ''
    if ([string]$G.danisman_mod -eq 'git') {
        Git-Calistir $wt @('add', '-A') | Out-Null
        Git-Calistir $wt @('diff', '--cached', '--quiet') -Sessiz | Out-Null
        if ($script:GitKod -ne 0) {
            $baslik = [string]$G.commit_mesaji; if (-not $baslik) { $baslik = [string]$G.baslik }
            if ($baslik.Length -gt 72) { $baslik = $baslik.Substring(0, 72) }
            $govde = @($baslik, '', "AI Ekip görevi: $($G.id)",
                "Outsource Consultant (Claude Code, headless): $($G.danisman) | Tur: $($G.tur)",
                'Onay: dış danışman akışı; iç ekip incelemesi yapılmadı (otomatik kontrol geçti). Birleştirmeden önce inceleyin.',
                '', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>') -join "`n"
            $mf = Join-Path $gk 'commit-mesaji.txt'
            Metin-Yaz $mf $govde
            $kimlik = @(); $eposta = Git-Calistir $wt @('config', 'user.email') -Sessiz
            if (-not $eposta) { $kimlik = @('-c', 'user.name=AI Ekip', '-c', 'user.email=ai-ekip@localhost') }
            Git-Calistir $wt ($kimlik + @('commit', '-q', '-F', $mf)) | Out-Null
            $commit = Git-Calistir $wt @('rev-parse', '--short', 'HEAD')
            Ayarla $G 'commit' $commit
            $dalNotu = " Dal: $($G.dal) ($commit); inceleyip birleştirebilirsin."
        } else { $dalNotu = ' Kodda değişiklik yok.' }
        Git-Calistir $G.klasor @('worktree', 'remove', $wt) -Sessiz | Out-Null
        Ayarla $G 'calisma_klasoru_kaldirildi' ($script:GitKod -eq 0)
    } else {
        $t = Teslim-Listesi $G 200
        $md = @("# Sonuç: $($G.baslik)", '', $ozet, '', "- Outsource Consultant (Claude Code): $($G.danisman) | Tur: $($G.tur)",
            "- Çıktı klasörü: $(Uzman-Cikti $G)", '', "## Teslimler ($($t.adet))", '', $(if ($t.adet) { $t.metin } else { '(dosya yok; sonuç danışman raporunda)' })) -join "`n"
        Metin-Yaz (Join-Path $gk 'sonuc.md') $md
        if ($t.adet) { $dalNotu = " $($t.adet) dosya; panelde Çıktılar sekmesinde." }
    }
    Asama-Gec $G 'tamam' 'iş tamamlandı' "Outsource Consultant$dalNotu"
    Sayac-Artir 'tamamlanan'
    Danisman-Sohbete-Yaz $G ("✅ #{0} {1} bitti. {2}{3} Raporun tamamı görev ayrıntısında (Turlar > Danışman raporu)." -f (No-Kisa $G.id), $G.baslik, $ozet, $dalNotu)
    Bildir -Baslik "Outsource Consultant bitirdi: $($G.baslik)" -Metin (Gizli-Maskele ((Kisalt $ozet 150) + $dalNotu)) -Anahtar "tamam-$($G.id)"
}

function Danisman-Adim($G) {
    switch ([string]$G.asama) {
        'yeni'       { Danisman-Hazirla $G }
        'gelistirme' { Danisman-Calis $G }
        'kontrol'    { Danisman-Kontrol $G }
        'tamamla'    { Danisman-Tamamla $G }
        default      { Asama-Gec $G 'gelistirme' 'Outsource Consultant işe dönüyor' "($($G.asama) aşaması bu akışta yok)" }
    }
}
