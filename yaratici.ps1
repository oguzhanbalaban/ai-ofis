<#
yaratici.ps1 - Fikir hattı: durum.json > tip = "yaratici". ekip.ps1 dot-source eder (kopru.ps1'i bu dosya yükler).

Altı çalışanın sıralı hattı (rol anahtarları kadro.json'da; araç zincirleri ayarlar.json > roller, panelden değişir):
  yeni      görev hazırlanır, fikir hattına alınır                                              [betik]
  fikir     Creative Strategist (fikirci): 2-3 küçük, uygulanabilir fikir                    -> fikir.md
  elestiri  Product Analyst (elestirmen): fizibilite / risk, bir fikri seçer                 -> elestiri.md
  poc_plan  Product Manager (planlamaci): tek küçük POC planı, test edilebilir ölçütler      -> poc-plan.md
  maliyet   Cost Analyst (maliyet): süre, çağrı, kaynak maliyeti                             -> maliyet.md
  karar     Head of Product (karar-verici): KARAR: ONAYLA | REVIZE | REDDET                  -> karar.md
            REVIZE: geri bildirimle eleştiriye döner (en fazla yaratici.revizyon_siniri); REDDET: reddedildi
  teslim    Head of Product teslim paketini (JSON) hazırlar                                  -> teslim.md, teslim.json
            yaratici.ana_ofis_yolu varsa köprü (kopru.ps1) AI Ofis'e görev açar; yoksa yerel teslim (sonuc-ekle.ps1)
  bekleme   AI Ofis görevini izler (yaratici.izleme_araligi_sn). Orada takılırsa bekler (AI Ofis'in Incident Managerʼı ilgilenir),
            iptal edilirse iş takılır. Yerel teslimde sonuc-ekle.ps1 çıktıyı ekleyip puanlamaya alır.
  puanlama  QA Analyst (puanlayici): çıktıyı 1-10 puanlar                                    -> puanlama.md, sonuc.md, raporlar\<no>.md
Fikir hattının ajan adımları salt okunurdur (dosya değiştirmez, komut çalıştırmaz). Ajan kayıtları gorevler\<no>\kayitlar\revizyon-N\.
#>

. (Join-Path $PSScriptRoot 'kopru.ps1')

$script:YaraticiAsamaRol = [ordered]@{ fikir = 'fikirci'; elestiri = 'elestirmen'; poc_plan = 'planlamaci'; maliyet = 'maliyet'; karar = 'karar-verici'; teslim = 'karar-verici'; puanlama = 'puanlayici' }
$script:YaraticiSira = @('yeni', 'fikir', 'elestiri', 'poc_plan', 'maliyet', 'karar', 'teslim', 'bekleme', 'puanlama', 'tamam')
# Fikir hattı yalnızca kadrosunda Creative Strategist (fikirci) olan katta çalışır (şirket binasında Creativity Office katı)
function Yaratici-Katta-mi {
    if (-not (Get-Command Kadro-Uye -ErrorAction SilentlyContinue)) { return $false }
    return [bool](Kadro-Uye 'fikirci')
}
$script:YaraticiTasimaHedefleri = @('yeni', 'fikir', 'elestiri', 'poc_plan', 'maliyet', 'karar', 'teslim')

# ayarlar.json > yaratici (eski düz alanlar revizyon_siniri / ana_ofis_yolu / varsayilan_proje da okunur)
function Yaratici-Ayari {
    $s = [ordered]@{ revizyon_siniri = 3; ana_ofis_yolu = ''; varsayilan_proje = ''; izleme_araligi_sn = 300; yardimlasma = $false }
    foreach ($ad in @('revizyon_siniri', 'ana_ofis_yolu', 'varsayilan_proje')) { if ($Ayar -and $Ayar.PSObject.Properties[$ad] -and $null -ne $Ayar.$ad) { $s[$ad] = $Ayar.$ad } }
    if ($Ayar -and $Ayar.yaratici) { foreach ($p in $Ayar.yaratici.PSObject.Properties) { if ($s.Contains($p.Name) -and $null -ne $p.Value) { $s[$p.Name] = $p.Value } } }
    $s.revizyon_siniri = [Math]::Max(0, [Math]::Min(3, [int]$s.revizyon_siniri))
    $s.izleme_araligi_sn = [Math]::Max(30, [int]$s.izleme_araligi_sn)
    $s.ana_ofis_yolu = ([string]$s.ana_ofis_yolu).Trim()
    # Şirket binasında POC'lar ana kata (AI Ekip Ofisi, kod kökü) gider; ayrı bir ana ofis yolu verilmediyse
    if (-not $s.ana_ofis_yolu -and $KatKimligi -ne 'ana') { $s.ana_ofis_yolu = $KodKok }
    $s.varsayilan_proje = ([string]$s.varsayilan_proje).Trim()
    return [pscustomobject]$s
}
# Yeni konu (proje-ekle.ps1) ya da Creative Directorʼın fikir hattına yönlendirdiği iş için alanlar
function Yaratici-Gorev-Hazirla($G, [string]$Alan = '', [string]$Proje = '') {
    $ya = Yaratici-Ayari
    if (-not $Alan) { $Alan = [string]$G.alan }
    if (-not $Alan) { $Alan = 'genel' }
    if (-not $Proje) { $Proje = [string]$G.proje }
    if (-not $Proje -or $Proje -eq 'Creative Director') { $Proje = $ya.varsayilan_proje }
    if ($Proje -and (Test-Path -LiteralPath $Proje -PathType Container)) { $Proje = (Resolve-Path -LiteralPath $Proje).Path.TrimEnd('\') }
    Ayarla $G 'tip' 'yaratici'
    Ayarla $G 'alan' $Alan
    Ayarla $G 'proje' $Proje
    Ayarla $G 'klasor' ''
    if ($null -eq $G.revizyon) { Ayarla $G 'revizyon' 0 }
    if ($null -eq $G.geri_bildirimler) { Ayarla $G 'geri_bildirimler' @() }
    if (-not $G.teslim_anahtari) { Ayarla $G 'teslim_anahtari' ([guid]::NewGuid().ToString('N')) }
}
function Yaratici-Belgeleri($G) {
    $gk = Gorev-Klasoru $G.id
    $b = New-Object Text.StringBuilder
    foreach ($ad in @('gorev.md', 'fikir.md', 'elestiri.md', 'poc-plan.md', 'maliyet.md', 'karar.md')) {
        $m = Metin-Oku (Join-Path $gk $ad)
        if ($m) { [void]$b.AppendLine("## $ad`n$m`n") }
    }
    $gb = @($G.geri_bildirimler | Where-Object { $_ })
    [void]$b.AppendLine("## Önceki revizyon geri bildirimleri`n" + $(if ($gb.Count) { $gb -join "`n`n" } else { '(yok)' }))
    # Kullanıcının ya da Incident Managerʼın sürdürürken / panoda taşırken yazdığı notlar (cozucu.ps1 > Gorev-Surdur)
    $not = Metin-Oku (Join-Path (Join-Path $gk ('tur{0}' -f [int]$G.tur)) 'geri-bildirim.md')
    if ($not.Trim()) { [void]$b.AppendLine("`n## Notlar (kullanıcı / Incident Manager)`n$($not.Trim())") }
    return $b.ToString()
}
function Yaratici-Rol-Calistir($G, [string]$Rol, [string]$Sablon, [string]$Dosya, [string]$Ek = '', [string]$Etiket = '') {
    if (-not $Etiket) { $Etiket = $Rol }
    $ya = Yaratici-Ayari
    $gk = Gorev-Klasoru $G.id
    $istem = Sablon-Doldur $Sablon @{ BELGELER = (Yaratici-Belgeleri $G); EK = $Ek; REVIZYON = [string][int]$G.revizyon; SINIR = [string]$ya.revizyon_siniri; PROJE = [string]$G.proje }
    $kayit = Join-Path $gk ('kayitlar\revizyon-{0}\{1}-deneme-{2}' -f [int]$G.revizyon, $Etiket, ([int]$G.deneme + 1))
    $r = Ajan-Cagir -Rol $Rol -Istem $istem -Klasor $gk -KayitKlasoru $kayit -Etiket $Etiket
    if (-not $r.basarili -or -not ([string]$r.metin).Trim()) {
        $h = [string]$r.hata; if (-not $h) { $h = 'boş çıktı' }
        throw "$(Calisan-Adi $Rol) çalışamadı: $h"
    }
    Metin-Yaz (Join-Path $kayit 'yanit.md') $r.metin
    if ($Dosya) { Metin-Yaz (Join-Path $gk $Dosya) $r.metin }
    Ayarla $G $Rol ('{0}/{1}' -f $r.arac, $r.model)   # panel: çalışanın son kullandığı model, katıldığı işler
    return $r
}
function Yaratici-Karar-Oku([string]$Metin) {
    $k = [regex]::Matches([string]$Metin, '(?m)^KARAR:\s*(ONAYLA|REVIZE|REDDET)\s*$')
    if ($k.Count -ne 1) { return '' }
    return $k[0].Groups[1].Value
}
function Yaratici-Rapor-Yaz($G) {
    $ya = Yaratici-Ayari
    $gk = Gorev-Klasoru $G.id
    $metin = "# $($G.baslik)`n`nDurum: $(Asama-Adi ([string]$G.asama))`nRevizyon: $([int]$G.revizyon)/$($ya.revizyon_siniri)`nAI Ofis görevi: $($G.ana_gorev_id)`nPuan: $($G.puan)`n`n"
    $metin += Yaratici-Belgeleri $G
    $metin += "`n## Puanlama`n" + (Metin-Oku (Join-Path $gk 'puanlama.md'))
    Metin-Yaz (Join-Path $gk 'sonuc.md') $metin
    Metin-Yaz (Join-Path $YolRapor "$($G.id).md") $metin
    Metin-Yaz (Join-Path $YolRapor 'son-rapor.md') $metin
}
# Teslim paketi: model JSON'u kod çitiyle ya da açıklamayla sarabilir; ilk JSON nesnesi alınır
function Yaratici-Paket-Coz([string]$Metin) {
    $t = ([string]$Metin).Trim()
    try { return ($t | ConvertFrom-Json) } catch {}
    $m = [regex]::Match($t, '(?s)\{.*\}')
    if ($m.Success) { try { return ($m.Value | ConvertFrom-Json) } catch {} }
    throw 'Teslim paketi geçerli JSON değil (baslik, aciklama, kabul).'
}

function Yaratici-Adim($G) {
    $ya = Yaratici-Ayari
    $gk = Gorev-Klasoru $G.id
    if ($null -eq $G.revizyon) { Ayarla $G 'revizyon' 0 }
    if ($null -eq $G.geri_bildirimler) { Ayarla $G 'geri_bildirimler' @() }
    switch ([string]$G.asama) {
        'yeni' {
            Yaratici-Gorev-Hazirla $G
            Asama-Gec $G 'fikir' 'fikir hattına alındı' ("alan: $($G.alan)")
        }
        'fikir' { $r = Yaratici-Rol-Calistir $G 'fikirci' 'fikirci.md' 'fikir.md'; Asama-Gec $G 'elestiri' 'fikirler hazır' '' $r }
        'elestiri' { $r = Yaratici-Rol-Calistir $G 'elestirmen' 'elestirmen.md' 'elestiri.md'; Asama-Gec $G 'poc_plan' 'eleştiri hazır' '' $r }
        'poc_plan' { $r = Yaratici-Rol-Calistir $G 'planlamaci' 'planlamaci.md' 'poc-plan.md'; Asama-Gec $G 'maliyet' 'POC planı hazır' '' $r }
        'maliyet' { $r = Yaratici-Rol-Calistir $G 'maliyet' 'maliyet.md' 'maliyet.md'; Asama-Gec $G 'karar' 'maliyet hesaplandı' '' $r }
        'karar' {
            $ek = ''
            if ([int]$G.revizyon -ge $ya.revizyon_siniri) { $ek = 'Revizyon hakkı bitti. Yalnızca ONAYLA veya REDDET seç. REVIZE gelirse sistem reddeder.' }
            $r = Yaratici-Rol-Calistir $G 'karar-verici' 'karar-verici.md' 'karar.md' $ek
            $karar = Yaratici-Karar-Oku $r.metin
            if (-not $karar) { throw 'Karar çıktısı tam bir KARAR: ONAYLA/REVIZE/REDDET satırı içermelidir.' }
            Ayarla $G 'karar' $karar
            if ($karar -eq 'ONAYLA') { Asama-Gec $G 'teslim' 'POC onaylandı' '' $r }
            elseif ($karar -eq 'REVIZE' -and [int]$G.revizyon -lt $ya.revizyon_siniri) {
                Ayarla $G 'geri_bildirimler' @(@($G.geri_bildirimler | Where-Object { $_ }) + ("Revizyon $([int]$G.revizyon + 1):`n" + [string]$r.metin))
                $G.revizyon = [int]$G.revizyon + 1
                Asama-Gec $G 'elestiri' 'revizyon istendi' ("revizyon $($G.revizyon)/$($ya.revizyon_siniri)") $r
            } else {
                $neden = "$(Calisan-Adi 'karar-verici') reddetti"
                if ($karar -eq 'REVIZE') { $neden = 'Revizyon sınırında yeniden revizyon istendi; otomatik red' }
                Asama-Gec $G 'reddedildi' $neden '' $r
                Yaratici-Rapor-Yaz $G
                Bildir -Baslik "POC reddedildi: $($G.baslik)" -Metin ('#{0}: {1}' -f (No-Kisa $G.id), $neden) -Anahtar "red-$($G.id)"
            }
        }
        'teslim' {
            if (-not ([string]$G.proje).Trim() -and $ya.varsayilan_proje) { $G.proje = $ya.varsayilan_proje }
            if (-not ([string]$G.proje).Trim()) { throw 'Hedef proje eksik: proje-ekle.ps1 -Proje ya da ayarlar.json > yaratici.varsayilan_proje gerekli. Görevin proje alanını düzeltip "Devam" de.' }
            if (-not $G.teslim_anahtari) { Ayarla $G 'teslim_anahtari' ([guid]::NewGuid().ToString('N')) }
            $teslimYolu = Join-Path $gk 'teslim.json'
            $paket = Json-Oku $teslimYolu
            $r = $null
            if (-not $paket) {
                $r = Yaratici-Rol-Calistir $G 'karar-verici' 'teslim.md' 'teslim.md' '' 'teslim'
                $paket = Yaratici-Paket-Coz $r.metin
                Ayarla $paket 'proje' ([string]$G.proje)
                Ayarla $paket 'anahtar' ([string]$G.teslim_anahtari)
                # AI Ofis'e maliyet ve karar dahil tüm onaylı bağlam gider
                Ayarla $paket 'aciklama' (([string]$paket.aciklama) + "`n`n" + (Yaratici-Belgeleri $G))
                Teslim-Dogrula $paket
                Json-Yaz $paket $teslimYolu
            }
            if (-not $ya.ana_ofis_yolu) {
                # Köprü yok: onaylı paket bu ofiste bekler; uygulama çıktısı sonuc-ekle.ps1 ile eklenir
                Ayarla $G 'teslim_turu' 'yerel'
                Asama-Gec $G 'bekleme' 'yerel teslim hazır' 'teslim.json; uygulama çıktısı sonuc-ekle.ps1 ile eklenecek' $r
                Bildir -Baslik "POC onaylandı: $($G.baslik)" -Metin ('#{0}: teslim paketi hazır (yerel teslim); uygulama çıktısını sonuc-ekle.ps1 ile ekle.' -f (No-Kisa $G.id)) -Anahtar "teslim-$($G.id)"
                return
            }
            Ayarla $G 'teslim_turu' 'kopru'
            $ana = Gorevi-Gonder $paket $ya.ana_ofis_yolu (Join-Path $gk 'teslim-kaydi.json')
            Ayarla $G 'ana_gorev_id' ([string]$ana.id)
            Ayarla $G 'ana_asama' ([string]$ana.asama)
            # Gönderimden sonra ayar değişse de görev aynı ofiste izlenir
            Ayarla $G 'ana_ofis' (Ana-Ofis-Koku $ya.ana_ofis_yolu)
            # Katlar arası yazışma kaydı: POC'u Comms ana kata teslim etti (panelde ve iki katın günlüğünde görünür)
            try { [void](Kat-Yazisma-Kaydi $G (Kok-Kat-Kimligi ([string]$G.ana_ofis)) ([string]$ana.id) 'poc' ([string]$paket.baslik) ([string]$paket.aciklama) @($paket.kabul)) } catch { Gunluk "POC yazışma kaydı yazılamadı: $($_.Exception.Message)" 'UYARI' }
            Ayarla $G 'ana_takildi' $false
            Asama-Gec $G 'bekleme' 'AI Ofisʼe teslim edildi' ("AI Ofis görevi #$(No-Kisa $ana.id)") $r
            Bildir -Baslik "POC AI Ofisʼe gitti: $($G.baslik)" -Metin ('#{0} onaylandı; AI Ofis görevi #{1} olarak sıraya girdi.' -f (No-Kisa $G.id), (No-Kisa $ana.id)) -Anahtar "teslim-$($G.id)"
        }
        'bekleme' {
            if ([string]$G.teslim_turu -eq 'yerel') {
                Ayarla $G 'sonraki_deneme' ((Get-Date).AddSeconds([int]$ya.izleme_araligi_sn).ToString('o'))
                return
            }
            $ana = Gorevi-Izle ([string]$G.ana_gorev_id) ([string]$G.ana_ofis)
            Ayarla $G 'ana_asama' ([string]$ana.asama)
            switch ([string]$ana.asama) {
                'tamam' {
                    Ayarla $G 'ana_takildi' $false
                    Asama-Gec $G 'puanlama' 'AI Ofis işi tamamladı' ("#{0} · commit {1}" -f (No-Kisa $ana.id), $ana.commit)
                }
                'iptal' {
                    Takildi $G ("AI Ofisʼteki görev #{0} iptal edildi. POCʼu yeniden göndermek için işi panoda Teslim şeridine taşı; vazgeçtiysen iptal et." -f (No-Kisa $ana.id))
                }
                default {
                    if ([string]$ana.asama -eq 'takildi') {
                        # AI Ofis kendi Incident Managerʼı ve kullanıcıyla ilgilenir: burada takılı sayılmaz, beklemeye devam
                        if (-not $G.ana_takildi) {
                            Gecmis-Ekle $G 'AI Ofisʼte takıldı' ([string]$ana.son_hata)
                            Bildir -Baslik "AI Ofisʼte takıldı: $($G.baslik)" -Metin ('#{0} (AI Ofis #{1}) takıldı; orada çözülünce puanlama kendiliğinden başlar.' -f (No-Kisa $G.id), (No-Kisa $ana.id)) -Anahtar "ana-takildi-$($G.id)" -AralikDk 720
                        }
                        Ayarla $G 'ana_takildi' $true
                    } elseif ($G.ana_takildi) {
                        Ayarla $G 'ana_takildi' $false
                        Gecmis-Ekle $G 'AI Ofisʼte yeniden yürüyor' ([string]$ana.asama)
                    }
                    $G.deneme = 0
                    Ayarla $G 'son_hata' ''
                    Ayarla $G 'sonraki_deneme' ((Get-Date).AddSeconds([int]$ya.izleme_araligi_sn).ToString('o'))
                }
            }
        }
        'puanlama' {
            if ([string]$G.teslim_turu -eq 'yerel') {
                $cikti = Metin-Oku (Join-Path $gk 'uygulama-ciktisi.md')
                if (-not $cikti.Trim()) { throw 'Yerel uygulama çıktısı bulunamadı; sonuc-ekle.ps1 kullanın.' }
            } else { $cikti = Ciktiyi-Oku ([string]$G.ana_gorev_id) ([string]$G.ana_ofis) }
            Metin-Yaz (Join-Path $gk 'ana-ofis-ciktisi.md') $cikti
            $r = Yaratici-Rol-Calistir $G 'puanlayici' 'puanlayici.md' '' $cikti
            $puanlar = [regex]::Matches([string]$r.metin, '(?m)^PUAN:\s*(10|[1-9])\s*$')
            if ($puanlar.Count -ne 1) { throw 'Puanlama tam bir PUAN: 1-10 satırı içermelidir.' }
            Ayarla $G 'puan' ([int]$puanlar[0].Groups[1].Value)
            Metin-Yaz (Join-Path $gk 'puanlama.md') $r.metin
            Asama-Gec $G 'tamam' 'çıktı puanlandı' ("puan: $($G.puan)/10") $r
            Ayarla $G 'ozet' ("Puan $($G.puan)/10")
            Yaratici-Rapor-Yaz $G
            Sayac-Artir 'tamamlanan'
            Bildir -Baslik "POC tamamlandı: $($G.baslik)" -Metin ('#{0}: {1}/10' -f (No-Kisa $G.id), $G.puan) -Anahtar "tamam-$($G.id)"
        }
        default { throw "Bilinmeyen fikir hattı aşaması: $($G.asama)" }
    }
}

# Kullanıcının komutunda (komut.ps1 > Adim-Rolu) ve panelde adımın sahibi
function Yaratici-Adim-Rolu([string]$Asama) {
    if ($Asama -eq 'yeni') { return 'fikirci' }
    if ($Asama -eq 'bekleme') { return 'karar-verici' }
    if ($YaraticiAsamaRol.Contains($Asama)) { return [string]$YaraticiAsamaRol[$Asama] }
    return 'lider'
}

# ---------------------------------------------------------------- panoda elle taşıma (cozucu.ps1 > Gorev-Asamaya-Tasi buraya yönlendirir)
function Yaratici-Asamaya-Tasi($G, [string]$Hedef, [string]$Not = '') {
    if ($YaraticiTasimaHedefleri -notcontains $Hedef) { throw "Fikir hattında bu aşamaya taşınamaz: $Hedef" }
    $simdiki = [string]$G.asama
    if ($simdiki -eq $Hedef) { throw "İş zaten bu aşamada ($(Asama-Adi $Hedef))" }
    $gk = Gorev-Klasoru $G.id
    $gerek = @{ elestiri = 'fikir.md'; poc_plan = 'elestiri.md'; maliyet = 'poc-plan.md'; karar = 'maliyet.md'; teslim = 'karar.md' }
    if ($gerek.ContainsKey($Hedef) -and -not ([string](Metin-Oku (Join-Path $gk $gerek[$Hedef]))).Trim()) {
        throw "Bu aşama için önce $($gerek[$Hedef]) gerekli; daha önceki bir şeride taşı"
    }
    if ($Hedef -eq 'teslim' -and (Yaratici-Karar-Oku (Metin-Oku (Join-Path $gk 'karar.md'))) -ne 'ONAYLA') { throw 'Teslim için onaylı karar gerekir; önce Kararʼa taşı' }
    # Teslim yeniden yapılacak: eski paket ve teslim kaydı arşivlenir, yeni anahtarla yeniden gönderilir (AI Ofis'teki eski görev olduğu gibi kalır)
    $arsiv = @()
    if ($G.ana_gorev_id -or (Test-Path -LiteralPath (Join-Path $gk 'teslim.json')) -or (Test-Path -LiteralPath (Join-Path $gk 'teslim-kaydi.json'))) {
        $damga = (Get-Date).ToString('yyyyMMddHHmmss')
        foreach ($ad in @('teslim.json', 'teslim-kaydi.json')) {
            $f = Join-Path $gk $ad
            if (Test-Path -LiteralPath $f) { $yeniAd = ($ad -replace '\.json$', "-$damga.json"); Move-Item -LiteralPath $f (Join-Path $gk $yeniAd) -Force; $arsiv += $yeniAd }
            if (Test-Path -LiteralPath "$f.bak") { Remove-Item -LiteralPath "$f.bak" -Force }
        }
        $onceki = @($G.onceki_teslimler | Where-Object { $_ })
        $onceki += [pscustomobject][ordered]@{ zaman = (Simdi); ana_gorev_id = [string]$G.ana_gorev_id; ana_asama = [string]$G.ana_asama; teslim_anahtari = [string]$G.teslim_anahtari }
        Ayarla $G 'onceki_teslimler' @($onceki)
        Ayarla $G 'teslim_anahtari' ([guid]::NewGuid().ToString('N'))
        foreach ($a in @('ana_gorev_id', 'ana_asama', 'ana_ofis', 'teslim_turu')) { Ayarla $G $a '' }
        Ayarla $G 'ana_takildi' $false
    }
    if ($null -ne $G.puan -and [string]$G.puan) { Ayarla $G 'onceki_puan' $G.puan; Ayarla $G 'puan' $null }
    $eskiAd = Asama-Adi $simdiki
    $hedefAd = Asama-Adi $Hedef
    if ($Not) {
        $f = Join-Path (Tur-Klasoru $G) 'geri-bildirim.md'
        Metin-Yaz $f ("## Kullanıcının notu ($eskiAd -> $hedefAd)`n`n$Not`n`n" + (Metin-Oku $f))
    }
    $ayrinti = $Not; if ($arsiv.Count) { $ayrinti = (("eski teslim arşivlendi: " + ($arsiv -join ', ')) + $(if ($Not) { " · $Not" } else { '' })) }
    Gecmis-Ekle $G "kullanıcı panoda taşıdı: $eskiAd -> $hedefAd" $ayrinti
    $G.asama = $Hedef
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'son_hata' ''
    Ayarla $G 'yardim_bekleyen' @()
    Ayarla $G 'cozum_durumu' ''
    Ayarla $G 'cozum_sayisi' 0
    Ayarla $G 'elle_tasima' ([pscustomobject][ordered]@{ onceki = $simdiki; asama = $Hedef; zaman = (Simdi) })
    Gunluk "Görev $($G.id) panoda taşındı: $simdiki -> $Hedef"
    return ('#{0}: {1} -> {2}' -f (No-Kisa $G.id), $eskiAd, $hedefAd)
}
