<#
cozucu.ps1 - Sorun Giderici: kullanıcıya soru sorulmadan takılan işleri (asama = takildi) inceler. ekip.ps1 dot-source eder.

Döngü her turda, sıradaki görevi ilerletmeden önce:
  1. Yardim-Gorevleri-Kontrol  Sorun Gidericinin açtığı yardım işi bittiyse takılan işi kaldığı yerden sürdürür.
  2. Cozulecek-Gorev / Sorun-Gider  incelenmemiş bir takılma varsa bir ajan adımı olarak çalışır (salt okunur):
       YONLENDIR     kadrodan birine yardım işi açar (sistem/ag -> altyapı talebi, diğerleri -> uzman işi); iş bitince 1. adım sürdürür
       YENIDEN_DENE  işi takıldığı aşamadan (tur sınırı dolduysa bir tur daha vererek, notuyla) yeniden yürütür; BEKLE_DK erteler
       AKTAR         işi doğru akışa (altyapı / uzman) taşır; yazılım çalışma ağacı korunur
       KULLANICI     kullanıcıya ne yapması gerektiğini bildirir (iş takılı kalır; panelden "Devam" ile sürer)
     DOGRULAMA_EKLE satırları güvenli biçimdeyse (Dogrulama-Guvenli-mi) görevin doğrulama komutlarına eklenir.
Takildi() bu modül işi üstlenecekse telefona "takıldı" bildirimi göndermez; Sorun Giderici kararına göre bildirir.
Sınırlar: ayarlar.json > sorun_giderici (etkin, gorev_basina_en_fazla, en_eski_saat). Kullanıcının "Devam" demesi
hakkı sıfırlar. Yardım işinin kendisi takılırsa ona yeni yardım işi açılmaz (zincir olmasın).
#>

function Cozucu-Ayari {
    $a = $Ayar.sorun_giderici
    $etkin = $true; $enFazla = 2; $enEski = 72
    if ($a) {
        if ($null -ne $a.etkin) { $etkin = [bool]$a.etkin }
        if ($a.gorev_basina_en_fazla) { $enFazla = [int]$a.gorev_basina_en_fazla }
        if ($a.en_eski_saat) { $enEski = [int]$a.en_eski_saat }
    }
    $rolVar = [bool]($Ayar.roller -and $Ayar.roller.PSObject.Properties['sorun-giderici'])
    return [pscustomobject]@{ etkin = ($etkin -and $rolVar); en_fazla = $enFazla; en_eski_saat = $enEski }
}
function Cozucu-Ustlenir($G) {
    $c = Cozucu-Ayari
    return [bool]($c.etkin -and [int]$G.cozum_sayisi -lt $c.en_fazla)
}
function Takilma-Zamani($G) {
    if ($G.takildi_zamani) { try { return [datetime]$G.takildi_zamani } catch {} }
    $son = @($G.gecmis | Where-Object { $_ -and [string]$_.olay -eq 'takıldı' } | Select-Object -Last 1)
    if ($son.Count) { try { return [datetime]$son[0].zaman } catch {} }
    try { return [datetime]$G.guncelleme } catch { return (Get-Date) }
}
function Cozulecek-Gorev {
    $c = Cozucu-Ayari
    if (-not $c.etkin) { return $null }
    $simdi = Get-Date
    $adaylar = @()
    foreach ($g in (Gorevleri-Listele)) {
        if ([string]$g.asama -ne 'takildi') { continue }
        if ([int]$g.cozum_sayisi -ge $c.en_fazla) { continue }
        if ([string]$g.cozum_durumu -eq 'yardim_bekleniyor') { continue }
        if ($g.cozum_sonraki -and ([datetime]$g.cozum_sonraki) -gt $simdi) { continue }
        $tz = Takilma-Zamani $g
        if (($simdi - $tz).TotalHours -gt $c.en_eski_saat) { continue }
        if ($g.cozum_inceleme -and ([datetime]$g.cozum_inceleme) -ge $tz) { continue }
        $adaylar += $g
    }
    if ($adaylar.Count -eq 0) { return $null }
    return ($adaylar | Sort-Object @{ e = { [int]$_.oncelik } }, @{ e = { $_.id } } | Select-Object -First 1)
}

# Ortak "sürdür" mantığı (durum.ps1 -Devam, Sorun Giderici ve yardım işi bitince)
function Gorev-Surdur($G, [string]$Not = '', [string]$Kim = 'kullanıcı', [string]$NotBasligi = 'Kullanıcının notu') {
    $gk = Gorev-Klasoru $G.id
    $bekleyen = Join-Path $gk 'bekleyen-geri-bildirim.md'
    $notMd = ''; if ($Not) { $notMd = "## $NotBasligi`n`n$Not`n`n" }
    if ([string]$G.asama -eq 'bekliyor_kullanici') {
        $G.asama = 'plan'
        if ($G.soru_donus_asama -and ($AktifAsamalar -contains [string]$G.soru_donus_asama)) { $G.asama = [string]$G.soru_donus_asama; Ayarla $G 'soru_donus_asama' '' }
        if ($notMd) { $f = Join-Path (Tur-Klasoru $G) 'geri-bildirim.md'; Metin-Yaz $f ($notMd + (Metin-Oku $f)) }
    } elseif ([string]$G.asama -eq 'yardim_bekliyor' -or [string]$G.asama -eq 'yardim') {
        # Ekip içi yardım beklenirken kullanıcı sürdürdü: yardımı beklemeden kaldığı aşamadan devam
        $d = [string]$G.yardim_donus_asama; if (-not $d -or $AktifAsamalar -notcontains $d -or $d -eq 'yardim') { $d = 'gelistirme' }
        Ayarla $G 'yardim_bekleyen' @()
        if ($notMd) { $f = Join-Path (Tur-Klasoru $G) 'geri-bildirim.md'; Metin-Yaz $f ($notMd + (Metin-Oku $f)) }
        $G.asama = $d
    } elseif (Test-Path -LiteralPath $bekleyen) {
        # Tur sınırına takılmıştı: bir tur hakkı daha ver, son geri bildirimle geliştiriciye dön
        $gb = $notMd + (Metin-Oku $bekleyen)
        $G.max_tur = [int]$G.tur + 1
        $G.tur = [int]$G.tur + 1
        Metin-Yaz (Join-Path (Tur-Klasoru $G) 'geri-bildirim.md') $gb
        Remove-Item -LiteralPath $bekleyen -Force
        $G.asama = 'gelistirme'
    } else {
        $hedef = [string]$G.takildi_asama
        if (-not $hedef -or -not ($AktifAsamalar -contains $hedef)) { $hedef = 'gelistirme' }
        if ($notMd) { $f = Join-Path (Tur-Klasoru $G) 'geri-bildirim.md'; Metin-Yaz $f ($notMd + (Metin-Oku $f)) }
        $G.asama = $hedef
    }
    Gecmis-Ekle $G "$Kim devam ettirdi" $Not
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'son_hata' ''
    if ($Kim -eq 'kullanıcı') { Ayarla $G 'cozum_sayisi' 0; Ayarla $G 'cozum_durumu' '' }
}

# ---------------------------------------------------------------- istem bağlamı
function Arac-Durumu-Metni {
    $s = Sayac-Oku
    $l = @()
    foreach ($a in @('claude', 'codex')) {
        $sinir = 0; if ($Ayar.gunluk_sinir.PSObject.Properties[$a]) { $sinir = [int]$Ayar.gunluk_sinir.$a }
        $kul = 0; if ($s.PSObject.Properties[$a]) { $kul = [int]$s.$a }
        $l += ('- {0}: bugün {1}/{2} çağrı{3}' -f $a, $kul, $sinir, $(if ($sinir -gt 0 -and $kul -ge $sinir) { ' (SINIR DOLU; gece yarısı sıfırlanır)' } else { '' }))
    }
    $k = Kilit-Oku
    foreach ($p in $k.PSObject.Properties) {
        if ($p.Value -and ([datetime]$p.Value.bitis) -gt (Get-Date)) { $l += ('- kilit {0}: {1} ({2}''e kadar)' -f $p.Name, $p.Value.neden, ([datetime]$p.Value.bitis).ToString('dd.MM HH:mm')) }
    }
    Kadro-Rolleri-Yukle
    # Her rolün tam yedek zinciri: inceleme adımlarında işi yapan model atlanır, o zaman zincirdeki sonraki uygun araç çalışır
    foreach ($p in $Ayar.roller.PSObject.Properties) {
        $parcalar = @()
        foreach ($g in @($p.Value)) { if (-not $g) { continue }; $n = Arac-Uygun $g; $parcalar += ('{0}/{1} ({2})' -f $g.arac, $g.model, $(if ($n) { $n } else { 'uygun' })) }
        $l += ('- {0}: {1}' -f $p.Name, ($parcalar -join ' > '))
    }
    $l += '- Not: denetim/inceleme/doğrulama adımlarında işi yapan araç/model (görevin "uygulayan" ya da "gelistirici" alanı) atlanır; zincirde başka uygun araç varsa onunla çalışır.'
    return ($l -join "`n")
}
function Takilan-Durum-Metni($G) {
    $tip = [string]$G.tip; if (-not $tip) { $tip = 'yazilim' }
    $l = @(
        "- No: $($G.id) | Başlık: $($G.baslik) | Tür: $tip | Öncelik: $($G.oncelik)"
        "- Takıldığı aşama: $(Asama-Adi ([string]$G.takildi_asama)) ($($G.takildi_asama)) | Tur: $($G.tur)/$($G.max_tur)"
        "- Takılma nedeni: $($G.son_hata)"
    )
    foreach ($a in @('proje', 'klasor', 'calisma_klasoru', 'dal', 'sorumlu', 'inceleyen', 'destek', 'uygulayan', 'gelistirici', 'denetci', 'hedef_rol', 'kaynak_klasor')) {
        $v = $G.$a
        if ($v) { $l += "- ${a}: $v" }
    }
    $d = @($G.dogrulama | Where-Object { $_ })
    $l += "- Doğrulama komutları (görev): $(if ($d.Count) { $d -join ' | ' } else { '(yok)' })"
    $pr = $null; if ($G.proje) { $pr = Proje-Bul ([string]$G.proje) }
    if ($pr) { $pd = @($pr.dogrulama | Where-Object { $_ }); $l += "- Doğrulama komutları (proje): $(if ($pd.Count) { $pd -join ' | ' } else { '(yok)' })" }
    if ($G.ana_gorev) { $l += "- Bu iş, #$($G.ana_gorev) için açılmış bir YARDIM İŞİ." }
    $l += "- Görev klasörü (çalışma dizinin): $(Gorev-Klasoru $G.id)"
    return ($l -join "`n")
}
function Gecmis-Metni($G, [int]$Adet = 15) {
    $l = @()
    foreach ($e in @($G.gecmis | Where-Object { $_ } | Select-Object -Last $Adet)) {
        $z = ''; try { $z = ([datetime]$e.zaman).ToString('dd.MM HH:mm') } catch {}
        $ek = ''; if ($e.ayrinti) { $ek = " — $($e.ayrinti)" }
        $ar = ''; if ($e.arac) { $ar = " [$($e.arac)]" }
        $l += "- $z [$($e.asama), tur $($e.tur)] $($e.olay)$ek$ar"
    }
    if (-not $l.Count) { return '(yok)' }
    return ($l -join "`n")
}
function Son-Raporlar-Metni($G) {
    $gk = Gorev-Klasoru $G.id
    $tk = Join-Path $gk ('tur{0}' -f $G.tur)
    $sb = New-Object Text.StringBuilder
    foreach ($ad in @('geri-bildirim.md', 'kontrol.md', 'denetim.md', 'inceleme.md', 'dogrulama.md', 'kabul.md', 'gelistirici-ozet.md', 'calisma-ozet.md', 'uygulama-ozet.md')) {
        $f = Join-Path $tk $ad
        if (Test-Path -LiteralPath $f) { [void]$sb.AppendLine("### tur$($G.tur)/$ad"); [void]$sb.AppendLine((Kirp (Gizli-Maskele (Metin-Oku $f)) 3500)); [void]$sb.AppendLine('') }
    }
    foreach ($ad in @('bekleyen-geri-bildirim.md', 'plan-gecersiz.md', 'plan.md')) {
        $f = Join-Path $gk $ad
        if (Test-Path -LiteralPath $f) { [void]$sb.AppendLine("### $ad"); [void]$sb.AppendLine((Kirp (Gizli-Maskele (Metin-Oku $f)) 3000)); [void]$sb.AppendLine('') }
    }
    if ($sb.Length -eq 0) { return '(rapor yok)' }
    return $sb.ToString()
}
function Son-Gunluk-Metni($G) {
    $gk = Gorev-Klasoru $G.id
    $f = Get-ChildItem -LiteralPath $gk -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.err.txt' -or $_.Name -like '*.out.txt' -or $_.Name -like 'dogrulama-*.txt' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return '(günlük yok)' }
    $kuyruk = Son-Satirlar (Metin-Oku $f.FullName) 30
    if ($kuyruk.Length -gt 4000) { $kuyruk = '…' + $kuyruk.Substring($kuyruk.Length - 4000) }
    return ("({0})`n``````text`n{1}`n``````" -f $f.FullName.Substring($gk.Length + 1), (Gizli-Maskele $kuyruk))
}
function Onceki-Mudahaleler-Metni($G) {
    $gk = Gorev-Klasoru $G.id
    $l = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $gk -Filter 'cozum-*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $l += "### $($f.Name)`n" + (Kirp (Metin-Oku $f.FullName) 1500)
    }
    if (-not $l.Count) { return '(yok; bu iş için ilk müdahale)' }
    return ($l -join "`n`n")
}

# ---------------------------------------------------------------- doğrulama komutu ekleme (güvenlik süzgeci)
# Doğrulama komutları otomatik kontrolde korumasız çalışır; bu yüzden yapay zekanın önerdiği komut yalnızca bilinen
# test / derleme araçlarıyla, kabuk yönlendirmesi ve satır içi kod olmadan kabul edilir.
$script:GuvenliDogrulamaAraclari = @('flutter', 'dart', 'npm', 'pnpm', 'yarn', 'node', 'python', 'py', 'pytest', 'dotnet', 'cargo', 'go',
    'mvn', 'gradle', 'gradlew', 'gradlew.bat', 'msbuild', 'tsc', 'eslint', 'jest', 'vitest', 'phpunit', 'ruby', 'rake', 'swift', 'make', 'cmake', 'ctest', 'deno')
function Dogrulama-Guvenli-mi([string]$Komut) {
    $k = $Komut.Trim()
    if (-not $k -or $k.Length -gt 200) { return $false }
    if ($k -match '[|<>^%`;\r\n]' -or $k -match '(?<!&)&(?!&)') { return $false }
    $parca = @($k -split '\s*&&\s*')
    if ($parca.Count -gt 2) { return $false }
    if ($parca.Count -eq 2) {
        $cd = [regex]::Match($parca[0], '^cd\s+(/d\s+)?"?([A-Za-z0-9._\-\\/ ]+?)"?$')
        if (-not $cd.Success) { return $false }
        $yol = $cd.Groups[2].Value
        if ($yol -match '\.\.' -or $yol -match '^[\\/]' -or $yol -match ':') { return $false }
        $k = $parca[1]
    }
    $kelimeler = @($k -split '\s+' | Where-Object { $_ })
    if (-not $kelimeler.Count) { return $false }
    $arac = $kelimeler[0].ToLowerInvariant() -replace '\.(exe|cmd|bat)$', ''
    if ($kelimeler[0] -match '^\.[\\/]gradlew') { $arac = 'gradlew' }
    if ($GuvenliDogrulamaAraclari -notcontains $arac) { return $false }
    for ($i = 1; $i -lt $kelimeler.Count; $i++) {
        $w = $kelimeler[$i].ToLowerInvariant()
        if (@('-c', '-e', '--eval', '-p', '--print', '--command', 'exec', 'dlx', 'x') -contains $w) { return $false }
        # python -m yalnızca test / denetim modülleriyle (pip, http.server gibi modüller olmasın)
        if ($w -eq '-m') {
            $mod = ''; if ($i + 1 -lt $kelimeler.Count) { $mod = $kelimeler[$i + 1].ToLowerInvariant() }
            if (@('pytest', 'unittest', 'compileall', 'py_compile', 'mypy', 'flake8', 'pylint', 'ruff', 'black') -notcontains $mod) { return $false }
        }
    }
    if (@('npm', 'pnpm', 'yarn') -contains $arac -and $kelimeler.Count -ge 2 -and @('install', 'i', 'add', 'publish', 'exec', 'dlx', 'create', 'init', 'link') -contains $kelimeler[1].ToLowerInvariant()) { return $false }
    return $true
}
function Dogrulama-Ekle($G, [string]$Metin) {
    $sonuc = [pscustomobject]@{ eklenen = @(); reddedilen = @() }
    $adaylar = @([regex]::Matches([string]$Metin, '(?m)^\W{0,4}DOGRULAMA_EKLE\W{0,4}\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value.Trim().Trim('`') } |
        Where-Object { $_ -and -not $_.StartsWith('<') })
    if (-not $adaylar.Count) { return $sonuc }
    $mevcut = @($G.dogrulama | Where-Object { $_ })
    foreach ($k in $adaylar) {
        if ($mevcut -contains $k -or $sonuc.eklenen -contains $k) { continue }
        if ((Dogrulama-Guvenli-mi $k) -and ($mevcut.Count + $sonuc.eklenen.Count) -lt 8) { $sonuc.eklenen += $k } else { $sonuc.reddedilen += $k }
    }
    if ($sonuc.eklenen.Count) { Ayarla $G 'dogrulama' @($mevcut + $sonuc.eklenen) }
    return $sonuc
}

# ---------------------------------------------------------------- yardım işi
function Yeni-Gorev-Klasoru([string]$Baslik) {
    for ($i = 0; $i -lt 20; $i++) {
        $numaralar = @(Get-ChildItem -LiteralPath $YolGorev -Directory | ForEach-Object { if ($_.Name -match '^(\d{4})-') { [int]$Matches[1] } })
        $no = 1; if ($numaralar.Count -gt 0) { $no = [int](($numaralar | Measure-Object -Maximum).Maximum) + 1 + $i }
        $id = '{0:D4}-{1}' -f $no, (Slug $Baslik)
        $gk = Gorev-Klasoru $id
        if (-not (Test-Path -LiteralPath $gk)) { New-Item -ItemType Directory -Force $gk | Out-Null; return $id }
    }
    throw 'Yeni görev numarası alınamadı'
}
# Yardım işi: Sorun Giderici (takılan iş için) ya da Yönetici (ekip içi yardım isteği / plan ön işi, yardim.ps1) açar.
# $Ek: yeni görevin durum.json'una eklenecek alanlar (ör. ise_alim_aranan)
function Yardim-Gorevi-Ac($G, [string]$Hedef, $Uye, [string]$Baslik, [string]$Talep, [string]$Kabul, [string]$Teshis,
    [string]$Acan = 'Sorun Giderici', [string]$NedenBasligi = 'Takılmanın nedeni (Sorun Giderici)', [hashtable]$Ek = @{}) {
    $altyapi = @('sistem', 'ag') -contains $Hedef
    if (-not $Baslik) { $Baslik = 'Yardım: ' + [string]$G.baslik }
    $Baslik = Kisalt $Baslik 110
    $id = Yeni-Gorev-Klasoru $Baslik
    $gk = Gorev-Klasoru $id
    $kabulMetni = '- (belirtilmedi; Yönetici planda ölçüt belirlesin)'
    if ($Kabul) { $kabulMetni = $Kabul }
    $tur = 'uzman işi'; if ($altyapi) { $tur = 'sunucu / kurulum talebi (sistem yöneticisi + network)' }
    $kime = '(Yönetici seçer; uygun kimse yoksa İK işe alır)'
    if ($Hedef -and $Uye) { $kime = "$($Uye.ad) ($Hedef)" }
    $md = @(
        "# $Baslik", '',
        "- Tür: yardım işi ($tur); $Acan açtı",
        "- İstenen çalışan: $kime",
        "- Yardım edilen iş: #$($G.id) $($G.baslik)",
        '- Öncelik: 1',
        "- Eklenme: $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '',
        '## Açıklama', '', $Talep, '',
        "## $NedenBasligi", '', $Teshis, '',
        '## Kabul ölçütleri', '', $kabulMetni, '',
        '## Notlar ve yanıtlar', '',
        '(Yönetici soru sorarsa yanıtlarını buraya yazıp dosyayı kaydet; ekip kendiliğinden devam eder.)'
    ) -join "`n"
    Metin-Yaz (Join-Path $gk 'gorev.md') $md
    $d = [ordered]@{
        id = $id; baslik = $Baslik; oncelik = 1; asama = 'yeni'; tur = 1; max_tur = [int]$Ayar.gorev.max_tur; deneme = 0; dogrulama = @()
        olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); ana_gorev = [string]$G.id
    }
    if ($altyapi) { $d.tip = 'altyapi'; $d.proje = 'altyapı'; $d.klasor = ''; $d.hedef = @(); $d.istenen_sorumlu = $Hedef }
    else {
        $d.tip = 'uzman'; $d.proje = 'uzman'; $d.klasor = ''; $d.hedef_rol = $Hedef
        $kaynak = [string]$G.calisma_klasoru; if (-not $kaynak -or -not (Test-Path -LiteralPath $kaynak)) { $kaynak = [string]$G.klasor }
        $d.kaynak_klasor = $kaynak
    }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    Gunluk "$Acan yardım işi açtı: $id ($(if ($Hedef) { $Hedef } else { 'Yönetici seçer' })) <- $($G.id)"
    return $id
}
# Yazılım işi başka akışa aktarılırken çalışma ağacındaki emek silinmesin: ağaç calisma\<no>-yazilim'e taşınır
function Yazilim-Agacini-Koru($G) {
    $wt = [string]$G.calisma_klasoru
    if ([string]$G.tip -eq 'altyapi' -or [string]$G.tip -eq 'uzman' -or -not $wt -or -not (Test-Path -LiteralPath (Join-Path $wt '.git'))) { return '' }
    $yeni = "$wt-yazilim"
    if (Test-Path -LiteralPath $yeni) { $yeni = "$wt-yazilim-$((Get-Date).ToString('HHmmss'))" }
    Git-Calistir ([string]$G.klasor) @('worktree', 'move', $wt, $yeni) | Out-Null
    Ayarla $G 'onceki_calisma_klasoru' $yeni
    Ayarla $G 'calisma_klasoru' ''
    return $yeni
}

# ---------------------------------------------------------------- Sorun Giderici adımı
function Cozum-Kullaniciya($G, [string]$Metin, [string]$Teshis, $R, [string]$Olay = 'Sorun Giderici kullanıcıya bıraktı') {
    Ayarla $G 'cozum_durumu' 'kullanici'
    Ayarla $G 'cozum_kullaniciya' (Kirp $Metin 1500)
    Gecmis-Ekle $G $Olay $Teshis $R
    Bildir -Baslik "Takılan iş seni bekliyor: $($G.baslik)" -Metin (Gizli-Maskele ('#{0}: {1} Yaptıktan sonra panelde "Devam" de.' -f (No-Kisa $G.id), (Kisalt $Metin 170))) -Anahtar "cozum-kullanici-$($G.id)" -Onem 'yuksek' -AralikDk 0
}
function Sorun-Gider($G) {
    $script:AktifGorev = $G.id
    $script:AktifAdim = 'cozum'
    Kalp 'çalışıyor'
    Gunluk "Sorun Giderici #$($G.id) takılmasını inceliyor ($($G.son_hata))"
    try {
        Kadro-Rolleri-Yukle
        $yardimKurali = 'YONLENDIR ile yardım işi açabilirsin.'
        if ($G.ana_gorev) { $yardimKurali = 'Bu iş zaten başka bir iş için açılmış bir yardım işi: YONLENDIR KULLANMA (zincir olmasın); YENIDEN_DENE, AKTAR ya da KULLANICI seç.' }
        $istem = Sablon-Doldur 'sorun-giderici.md' @{
            KADRO = (Kadro-Metni); ARACLAR = (Arac-Durumu-Metni); DURUM = (Takilan-Durum-Metni $G); GOREV = (Kirp (Gorev-Metni $G) 6000)
            GECMIS = (Gecmis-Metni $G); RAPORLAR = (Son-Raporlar-Metni $G); GUNLUK = (Son-Gunluk-Metni $G); ONCEKI = (Onceki-Mudahaleler-Metni $G)
            YARDIM_KURALI = $yardimKurali
        }
        $r = Ajan-Cagir -Rol 'sorun-giderici' -Istem $istem -Klasor (Gorev-Klasoru $G.id) -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'cozum'
        # Ajan çalışırken kullanıcı işi sürdürmüş ya da iptal etmiş olabilir: güncel kaydın üzerine kararı uygula
        $disk = Gorev-Diskten $G.id
        if (-not $disk -or [string]$disk.asama -ne 'takildi') { Gunluk "Sorun Giderici kararı uygulanmadı: #$($G.id) artık takılı değil ($($disk.asama))" 'UYARI'; return }
        $G = $disk
        if (-not $r.basarili) {
            $hata = [int]$G.cozum_hata + 1
            Ayarla $G 'cozum_hata' $hata
            Ayarla $G 'cozum_sonraki' ((Get-Date).AddMinutes(30).ToString('o'))
            Gunluk "Sorun Giderici çalışamadı (#$($G.id), $hata. deneme): $($r.hata)" 'UYARI'
            if ($hata -ge 3) {
                Ayarla $G 'cozum_inceleme' (Simdi)
                Ayarla $G 'cozum_durumu' 'incelenemedi'
                Gecmis-Ekle $G 'Sorun Giderici inceleyemedi' $r.hata
                Bildir -Baslik "Görev takıldı: $($G.baslik)" -Metin ('#{0}: {1} Sorun Giderici de inceleyemedi. Devam için panelde "Devam".' -f (No-Kisa $G.id), (Kisalt ([string]$G.son_hata) 140)) -Anahtar "takildi-$($G.id)" -Onem 'yuksek' -AralikDk 0
            }
            Gorev-Kaydet $G
            return
        }
        $gk = Gorev-Klasoru $G.id
        $sira = [int]$G.cozum_sayisi + 1
        $karar = Karar-Oku $r.metin
        $teshis = Bolum-Oku $r.metin 'Teşhis'; if (-not $teshis) { $teshis = Kisalt $r.metin 400 }
        $dog = Dogrulama-Ekle $G $r.metin
        $ek = ''
        if ($dog.eklenen.Count) { $ek += "`n`n> Doğrulama komutlarına eklendi: " + ($dog.eklenen -join ' | ') }
        if ($dog.reddedilen.Count) { $ek += "`n`n> Güvenlik süzgecinden geçmediği için eklenmedi: " + ($dog.reddedilen -join ' | ') }
        $ust = '# Sorun Giderici · {0} · {1}/{2}' -f (Get-Date).ToString('dd.MM.yyyy HH:mm'), $r.arac, $r.model
        Metin-Yaz (Join-Path $gk ('cozum-{0}.md' -f $sira)) ($ust + "`n`n" + $r.metin + $ek)
        Ayarla $G 'cozum_sayisi' $sira
        Ayarla $G 'cozum_inceleme' (Simdi)
        Ayarla $G 'cozum_son_karar' $karar
        Ayarla $G 'cozum_hata' 0
        Ayarla $G 'cozum_teshis' (Kisalt $teshis 400)
        Ayarla $G 'sorun-giderici' ('{0}/{1}' -f $r.arac, $r.model)
        if ($dog.eklenen.Count) { Gecmis-Ekle $G 'Sorun Giderici doğrulama komutu ekledi' ($dog.eklenen -join ' | ') }
        $hedef = Kadro-Anahtar-Coz (Alan-Oku $r.metin 'HEDEF')
        if ($karar -eq 'YONLENDIR' -and $G.ana_gorev) { $karar = 'KULLANICI_ZINCIR' }
        switch ($karar) {
            'YONLENDIR' {
                $u = Kadro-Uye $hedef
                $talep = Bolum-Oku $r.metin 'Talep'
                if (-not $u -or -not $talep -or @('lider', 'gelistirici', 'denetci', 'sorun-giderici') -contains $hedef) {
                    # Geçersiz hedef: işi yapan ekibe Sorun Gidericinin notuyla yeniden dene
                    Gorev-Surdur $G ((Bolum-Oku $r.metin 'Not') + "`n`n" + $teshis).Trim() 'Sorun Giderici' 'Sorun Gidericinin notu'
                    Ayarla $G 'cozum_durumu' 'yeniden_denendi'
                    break
                }
                $yid = Yardim-Gorevi-Ac $G $hedef $u (Alan-Oku $r.metin 'BASLIK') $talep (Bolum-Oku $r.metin 'Kabul') $teshis
                Ayarla $G 'yardim_gorevi' $yid
                Ayarla $G 'cozum_durumu' 'yardim_bekleniyor'
                Gecmis-Ekle $G 'Sorun Giderici yardım işi açtı' ('#{0} → {1}: {2}' -f (No-Kisa $yid), $u.ad, (Kisalt $teshis 200)) $r
                Bildir -Baslik "Sorun Giderici devrede: $($G.baslik)" -Metin (Gizli-Maskele ('#{0} takılmıştı: {1} {2} için #{3} açıldı; bitince iş kendiliğinden sürecek.' -f (No-Kisa $G.id), (Kisalt $teshis 100), $u.ad, (No-Kisa $yid))) -Anahtar "cozum-$($G.id)" -AralikDk 0
            }
            'YENIDEN_DENE' {
                $not = Bolum-Oku $r.metin 'Not'; if (-not $not) { $not = $teshis }
                Gorev-Surdur $G $not 'Sorun Giderici' 'Sorun Gidericinin notu'
                $bekle = [int](Sayi (Deger-Temizle (Alan-Oku $r.metin 'BEKLE_DK')))
                if ($bekle -gt 0) { Ayarla $G 'sonraki_deneme' ((Get-Date).AddMinutes([Math]::Min($bekle, 1440)).ToString('o')) }
                Ayarla $G 'cozum_durumu' 'yeniden_denendi'
            }
            'AKTAR' {
                $tur = (Deger-Temizle (Alan-Oku $r.metin 'TUR')).ToLowerInvariant()
                if (@('altyapi', 'uzman') -notcontains $tur -or $tur -eq [string]$G.tip) {
                    Cozum-Kullaniciya $G ("Sorun Giderici işi başka bir ekibe aktarmak istedi ama hedef geçersiz ('$tur'). " + $teshis) $teshis $r
                    break
                }
                $agac = ''
                try { $agac = Yazilim-Agacini-Koru $G } catch {
                    Cozum-Kullaniciya $G ("İş $tur ekibine aktarılmalı ama yazılım çalışma ağacı taşınamadı ($($_.Exception.Message)). " + $teshis) $teshis $r
                    break
                }
                $bek = Join-Path $gk 'bekleyen-geri-bildirim.md'
                if (Test-Path -LiteralPath $bek) { Move-Item -LiteralPath $bek (Join-Path $gk ('bekleyen-geri-bildirim-{0}.md' -f (Get-Date).ToString('HHmmss'))) -Force }
                # Temiz bir tur klasörüyle başlasın
                $G.tur = [int]$G.tur + 1
                $G.max_tur = [int]$G.tur + [int]$Ayar.gorev.max_tur - 1
                if ($tur -eq 'altyapi') { Altyapiya-Aktar $G 'Sorun Giderici işi altyapı ekibine aktardı' $r }
                else {
                    $s = Kadro-Anahtar-Coz (Alan-Oku $r.metin 'SORUMLU')
                    if (-not (Kadro-Uye $s)) { $s = '' }
                    Uzmana-Aktar $G 'Sorun Giderici işi uzmana aktardı' $r $s ''
                    if ($agac) { Ayarla $G 'kaynak_klasor' $agac }
                }
                $not = Bolum-Oku $r.metin 'Not'
                if ($not -or $agac) { Gorev-Notu-Ekle $G 'Sorun Gidericinin notu' ((($not + "`n`n") + $(if ($agac) { "Önceki yazılım çalışması: ``$agac``" } else { '' })).Trim()) }
                Ayarla $G 'cozum_durumu' 'aktarildi'
                Bildir -Baslik "Sorun Giderici işi aktardı: $($G.baslik)" -Metin (Gizli-Maskele ('#{0}: {1} ekibine aktarıldı. {2}' -f (No-Kisa $G.id), $(if ($tur -eq 'altyapi') { 'altyapı' } else { 'uzman' }), (Kisalt $teshis 120))) -Anahtar "cozum-$($G.id)" -AralikDk 0
            }
            'KULLANICI_ZINCIR' {
                $t = Bolum-Oku $r.metin 'Talep'; if (-not $t) { $t = $teshis }
                Cozum-Kullaniciya $G ("Bu bir yardım işi; Sorun Giderici zincir olmasın diye yeni yardım işi açmadı. Önerdiği: " + $t) $teshis $r
            }
            'KULLANICI' {
                $k = Bolum-Oku $r.metin 'Kullanıcıya'; if (-not $k) { $k = $teshis }
                Cozum-Kullaniciya $G $k $teshis $r
            }
            default {
                Metin-Yaz (Join-Path $gk 'cozum-gecersiz.md') $r.metin
                Cozum-Kullaniciya $G ("Sorun Giderici geçerli bir karar veremedi. Takılma nedeni: " + [string]$G.son_hata) $teshis $r 'Sorun Giderici karar veremedi'
            }
        }
        Gorev-Kaydet $G
        Gunluk "Sorun Giderici #$($G.id): $karar"
    } finally {
        $script:AktifGorev = ''
        $script:AktifAdim = ''
    }
}

# Sorun Gidericinin açtığı yardım işleri: bitince takılan işi sürdür, iptal edilirse kullanıcıya bildir
function Yardim-Gorevleri-Kontrol {
    $liste = @(Gorevleri-Listele)
    foreach ($g in $liste) {
        if ([string]$g.cozum_durumu -ne 'yardim_bekleniyor' -or -not $g.yardim_gorevi) { continue }
        if ([string]$g.asama -ne 'takildi') {
            # Kullanıcı işi elle sürdürmüş ya da iptal etmiş
            Ayarla $g 'cozum_durumu' ''
            Gorev-Kaydet $g
            continue
        }
        $y = $null
        foreach ($x in $liste) { if ($x.id -eq $g.yardim_gorevi) { $y = $x; break } }
        if (-not $y) { continue }
        switch ([string]$y.asama) {
            'tamam' {
                $sonuc = Metin-Oku (Join-Path (Gorev-Klasoru $y.id) 'sonuc.md')
                $ozet = [string]$y.ozet; if (-not $ozet) { $ozet = 'Yardım işi tamamlandı.' }
                $not = "Takılmayı gidermek için açılan #$($y.id) ($($y.baslik)) tamamlandı.`n`n$ozet"
                if ($sonuc) { $not += "`n`n" + (Kirp (Gizli-Maskele $sonuc) 2500) }
                Gorev-Surdur $g $not 'Sorun Giderici' 'Yardım işi tamamlandı'
                Ayarla $g 'cozum_durumu' 'yardim_tamam'
                Gorev-Kaydet $g
                Gunluk "Yardım işi #$($y.id) bitti; #$($g.id) sürdürülüyor ($($g.asama))"
                Bildir -Baslik "Takılan iş yeniden yürüyor: $($g.baslik)" -Metin (Gizli-Maskele ('#{0}: yardım işi #{1} bitti ({2}). İş kaldığı yerden sürüyor.' -f (No-Kisa $g.id), (No-Kisa $y.id), (Kisalt $ozet 110))) -Anahtar "cozum-$($g.id)" -AralikDk 0
            }
            'iptal' {
                Ayarla $g 'cozum_durumu' 'yardim_iptal'
                Gecmis-Ekle $g 'yardım işi iptal edildi' "#$($y.id)"
                Gorev-Kaydet $g
                Bildir -Baslik "Takılan iş seni bekliyor: $($g.baslik)" -Metin ('#{0}: yardım işi #{1} iptal edildi; iş takılı kaldı. Panelde "Devam" ile sürdürebilirsin.' -f (No-Kisa $g.id), (No-Kisa $y.id)) -Anahtar "cozum-kullanici-$($g.id)" -Onem 'yuksek' -AralikDk 0
            }
        }
    }
}
