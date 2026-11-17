<#
altyapi.ps1 - Sunucu / kurulum talepleri (durum.json > tip = "altyapi"). ekip.ps1 dot-source eder.

Roller (ayarlar.json > roller):
  sistem : SİSTEM YÖNETİCİSİ - sunucu, işletim sistemi, servis, kurulum, VM, veritabanı sunucusu
  ag     : NETWORK ÇALIŞANI  - IP/DNS, VMware ağları, port, konuk güvenlik duvarı, bağlantı
Bu iki rol yalnızca kullanıcının görevlendirdiği makinelerde tam yetkiyle çalışır: uygulama ve doğrulama adımları
onay beklemeden, sandbox'sız çalışır (Ajan-Cagir -TamYetki). Sınırlar, istemlere eklenen ayarlar.json > altyapi.kurallar
metinleridir (teknik engel değil, talimattır). Ana makinede yönetici hakkı olmadığından UAC isteyen işler zaten yapılamaz.

Aşama adları yazılım görevleriyle aynıdır (durum.ps1 -Devam/-Iptal, rapor ve panel değişmeden çalışsın diye):
  yeni       keşif (vmrun list, ping, ana makine kaynakları) + çalışma klasörü      [betik]
  plan       lider talebi planlar; SORUMLU ve DESTEK rollerini seçer                [lider, salt okunur]
  gelistirme SORUMLU rol talebi uygular                                             [sistem|ag, tam yetki]
  kontrol    talebin doğrulama komutları + keşif yenilemesi                         [betik]
  denetim    DESTEK rol kendi kısmını yapar ve bağımsız doğrular (ONAY | DUZELT)    [ag|sistem, tam yetki]
  kabul      lider KABUL | RET                                                      [lider, salt okunur]
  tamamla    sonuç raporu + bildirim (git / commit yok)                             [betik]
#>

$script:AltyapiRolleri = @{
    sistem = @{ ad = 'SİSTEM YÖNETİCİSİ'; tanim = 'Sunucular, işletim sistemleri, servisler, yazılım kurulumları, VM yönetimi (vmrun) ve veritabanı sunucuları senin sorumluluğunda.' }
    ag     = @{ ad = 'NETWORK ÇALIŞANI'; tanim = 'IP/DNS/hosts, VMware ağları (NAT / host-only), portlar, konuk güvenlik duvarı kuralları ve makineler arası bağlantı (ping, port, HTTP, ODBC) senin sorumluluğunda.' }
}

# ---------------------------------------------------------------- yardımcılar
function Altyapi-Calisma($G) {
    $wt = Join-Path $YolCalisma $G.id
    if (-not (Test-Path -LiteralPath $wt)) { New-Item -ItemType Directory -Force $wt | Out-Null }
    return $wt
}
function Altyapi-Vmrun {
    $v = [string]$Ayar.altyapi.vmrun
    if ($v -and (Test-Path -LiteralPath $v)) { return $v }
    return $null
}
function Acik-VMler {
    $v = Altyapi-Vmrun
    if (-not $v) { return @() }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & $v list 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $eap }
    return @($o | Where-Object { $_ -match '\.vmx\s*$' } | ForEach-Object { $_.Trim() })
}
function Ping-Dene([string]$Ip, [int]$Ms = 700) {
    if (-not $Ip) { return '-' }
    try {
        $r = (New-Object Net.NetworkInformation.Ping).Send($Ip, $Ms)
        if ($r.Status -eq 'Success') { return "yanıt ($($r.RoundtripTime) ms)" }
    } catch {}
    return 'yanıt yok'
}
function Altyapi-Kesif {
    $sb = New-Object Text.StringBuilder
    $acik = @(Acik-VMler)
    [void]$sb.AppendLine("Zaman: $((Get-Date).ToString('dd.MM.yyyy HH:mm:ss'))")
    if (-not (Altyapi-Vmrun)) { [void]$sb.AppendLine('(vmrun bulunamadı; VM durumları bilinmiyor)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Makine | IP | VM | Ping |')
    [void]$sb.AppendLine('|---|---|---|---|')
    $bilinen = @()
    foreach ($m in @($Ayar.altyapi.makineler)) {
        if (-not $m) { continue }
        $vm = '-'
        if ($m.vmx) {
            $bilinen += [string]$m.vmx
            $vm = 'kapalı'
            foreach ($a in $acik) { if ($a -ieq [string]$m.vmx) { $vm = 'AÇIK' } }
        }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $m.ad, $m.ip, $vm, (Ping-Dene ([string]$m.ip))))
    }
    $diger = @()
    foreach ($a in $acik) { $var = $false; foreach ($b in $bilinen) { if ($a -ieq $b) { $var = $true } }; if (-not $var) { $diger += $a } }
    if ($diger.Count) { [void]$sb.AppendLine(''); [void]$sb.AppendLine('Listede olmayan açık VM: ' + ($diger -join ', ')) }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('Ana makine: boş RAM {0:N1} GB / {1:N1} GB' -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB)))
        $diskler = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { '{0} {1:N0} GB boş' -f $_.DeviceID, ($_.FreeSpace / 1GB) })
        [void]$sb.AppendLine('Diskler: ' + ($diskler -join ', '))
    } catch {}
    return [pscustomobject]@{ metin = $sb.ToString(); acik = $acik }
}
function Altyapi-Ortam {
    $a = $Ayar.altyapi
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('## Makineler')
    [void]$sb.AppendLine('| Ad | IP | İşletim sistemi | VMX | Yönetim betiği | Açıklama |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|')
    foreach ($m in @($a.makineler)) {
        if ($m) { [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $m.ad, $m.ip, $m.isletim, $m.vmx, $m.yonetim, $m.aciklama)) }
    }
    [void]$sb.AppendLine('')
    if ($a.baglanti_bilgileri) { [void]$sb.AppendLine("Kullanıcı adları ve parolalar: ``$($a.baglanti_bilgileri)`` (oku; parolaları hiçbir rapora, özete ya da bildirime yazma).") }
    if ($a.vmrun) { [void]$sb.AppendLine("vmrun: ``$($a.vmrun)`` (VMware Player: ``vmrun list``, ``vmrun start <vmx> nogui``, ``vmrun stop <vmx> soft``).") }
    [void]$sb.AppendLine("Ekip klasörü: ``$Kok`` (döngünün kendi dosyaları).")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Kurallar')
    foreach ($k in @($a.kurallar)) { if ($k) { [void]$sb.AppendLine("- $k") } }
    $ipuclari = @($a.ipuclari | Where-Object { $_ })
    if ($ipuclari.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Önceki deneyimlerden ipuçları')
        foreach ($k in $ipuclari) { [void]$sb.AppendLine("- $k") }
    }
    return $sb.ToString()
}
function Baslangic-VM-Metni($G) {
    $l = @($G.baslangic_acik_vmler | Where-Object { $_ })
    if ($l.Count -eq 0) { return 'Görev başladığında açık VM yoktu.' }
    return 'Görev başladığında açık olan VM''ler (kullanıcının açtığı sayılır): ' + ($l -join ', ')
}
function Rol-Coz([string]$Metin, [string]$Varsayilan) {
    $t = ([string]$Metin).ToLowerInvariant()
    if ($t -match 'yok|none|gerekmez|^\s*-\s*$') { return 'yok' }
    if ($t -match 'network|ağ|\bag\b') { return 'ag' }
    if ($t -match 'sistem|system|admin') { return 'sistem' }
    return $Varsayilan
}
function Diger-Rol([string]$Rol) { if ($Rol -eq 'ag') { return 'sistem' }; return 'ag' }
function Gizli-Maskele([string]$Metin) {
    return ($Metin -replace '(?i)((?:parola|şifre|sifre|password|passwd|pwd)\s*[:=]\s*)\S+', '$1***')
}

function Altyapi-Soru($G, [string]$Metin, $Sonuc, [string]$Olay = 'yönetici soru sordu') {
    Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) 'sorular.md') $Metin
    Gecmis-Ekle $G $Olay '' $Sonuc
    $G.asama = 'bekliyor_kullanici'
    $G.deneme = 0
    Ayarla $G 'soru_zamani' (Simdi)
    Bildir -Baslik "Yönetici soru soruyor: $($G.baslik)" -Metin ("#{0}: sorular.md dosyasını oku, yanıtını ofis panelinden ya da gorev.md'ye ekleyerek ver; ekip kendiliğinden devam eder." -f $G.id) -Anahtar "soru-$($G.id)" -Onem 'yuksek'
}

# Yazılım akışına gelmiş bir sunucu / kurulum işini altyapı ekibine aktarır (lider KARAR: ALTYAPI dediğinde).
# Plan aşamasında lider dosya değiştirmez: yazılım için açılan çalışma ağacı ve iş içermeyen dal güvenle kaldırılır
function Yazilim-Agaci-Temizle($G) {
    $wt = [string]$G.calisma_klasoru; $proje = [string]$G.klasor; $dal = [string]$G.dal; $temel = [string]$G.temel_commit
    if ($wt -and $proje -and (Test-Path -LiteralPath (Join-Path $wt '.git')) -and $wt.StartsWith($YolCalisma, [StringComparison]::OrdinalIgnoreCase)) {
        Git-Calistir $proje @('worktree', 'remove', '--force', $wt) -Sessiz | Out-Null
        Git-Calistir $proje @('worktree', 'prune') -Sessiz | Out-Null
    }
    if ($dal -and $proje -and $temel) {
        $uc = Git-Calistir $proje @('rev-parse', "refs/heads/$dal") -Sessiz
        if ($script:GitKod -eq 0 -and $uc -eq $temel) { Git-Calistir $proje @('branch', '-D', $dal) -Sessiz | Out-Null }
    }
}
function Altyapiya-Aktar($G, [string]$Neden, $Sonuc = $null) {
    Yazilim-Agaci-Temizle $G
    Gecmis-Ekle $G $Neden '' $Sonuc
    Ayarla $G 'tip' 'altyapi'
    Ayarla $G 'onceki_proje' ([string]$G.proje)
    $G.proje = 'altyapı'
    $G.klasor = ''
    foreach ($a in @('dal', 'calisma_klasoru', 'temel_commit')) { Ayarla $G $a '' }
    $G.asama = 'yeni'
    $G.deneme = 0
    Ayarla $G 'sonraki_deneme' $null
    Ayarla $G 'son_hata' ''
    Gunluk "Görev $($G.id): altyapı ekibine (sistem yöneticisi + network) aktarıldı"
}

# ---------------------------------------------------------------- adımlar
function Altyapi-Hazirla($G) {
    $wt = Altyapi-Calisma $G
    $k = Altyapi-Kesif
    Metin-Yaz (Join-Path (Gorev-Klasoru $G.id) 'kesif.md') ("# Keşif (talep başı)`n`n" + $k.metin)
    Ayarla $G 'calisma_klasoru' $wt
    Ayarla $G 'dal' ''
    Ayarla $G 'baslangic_acik_vmler' @($k.acik)
    Asama-Gec $G 'plan' 'keşif tamam' ('{0} VM açık' -f @($k.acik).Count)
}

function Altyapi-Plan($G) {
    $gk = Gorev-Klasoru $G.id
    $istem = Sablon-Doldur 'lider-altyapi-plan.md' @{
        GOREV = (Gorev-Metni $G); ORTAM = (Altyapi-Ortam); KESIF = (Metin-Oku (Join-Path $gk 'kesif.md')); BASLANGIC_VM = (Baslangic-VM-Metni $G)
    }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor (Altyapi-Calisma $G) -KayitKlasoru (Kayit-Klasoru $G) -Etiket 'plan'
    if (-not $r.basarili) { Adim-Basarisiz $G "Yönetici plan yazamadı: $($r.hata)"; return }
    Ayarla $G 'lider' ('{0}/{1}' -f $r.arac, $r.model)
    switch (Karar-Oku $r.metin) {
        'PLAN_HAZIR' {
            $sorumlu = Rol-Coz (Alan-Oku $r.metin 'SORUMLU') 'sistem'
            if ($sorumlu -eq 'yok') { $sorumlu = 'sistem' }
            $destek = Rol-Coz (Alan-Oku $r.metin 'DESTEK') (Diger-Rol $sorumlu)
            if ($destek -eq $sorumlu) { $destek = Diger-Rol $sorumlu }
            Metin-Yaz (Join-Path $gk 'plan.md') $r.metin
            Ayarla $G 'sorumlu' $sorumlu
            Ayarla $G 'destek' $destek
            Asama-Gec $G 'gelistirme' 'plan hazır' ('sorumlu: {0}, destek: {1}' -f $sorumlu, $destek) $r
        }
        'SORU_VAR' { Altyapi-Soru $G $r.metin $r }
        default {
            Metin-Yaz (Join-Path $gk 'plan-gecersiz.md') $r.metin
            Adim-Basarisiz $G "Plan çıktısında KARAR satırı yok ($($r.arac))"
        }
    }
}

function Altyapi-Uygulama($G) {
    $tk = Tur-Klasoru $G
    $wt = Altyapi-Calisma $G
    $rol = [string]$G.sorumlu
    if (-not $AltyapiRolleri.ContainsKey($rol)) { $rol = 'sistem' }
    $k = Altyapi-Kesif
    Metin-Yaz (Join-Path $tk 'kesif.md') ("# Keşif ($($G.tur). tur başı)`n`n" + $k.metin)
    $gb = Metin-Oku (Join-Path $tk 'geri-bildirim.md')
    if (-not $gb) { $gb = '(Yok; bu ilk tur.)' }
    $istem = Sablon-Doldur 'altyapi-uygulama.md' @{
        ROL_ADI = $AltyapiRolleri[$rol].ad; ROL_TANIMI = $AltyapiRolleri[$rol].tanim; TUR = [string]$G.tur; CALISMA = $wt
        ORTAM = (Altyapi-Ortam); KESIF = $k.metin; BASLANGIC_VM = (Baslangic-VM-Metni $G)
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G); GERI_BILDIRIM = $gb
    }
    $r = Ajan-Cagir -Rol $rol -Istem $istem -Klasor $wt -KayitKlasoru $tk -Etiket 'uygulama' -TamYetki
    if (-not $r.basarili) { Adim-Basarisiz $G "$($AltyapiRolleri[$rol].ad) çalışamadı: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'uygulama-ozet.md') $r.metin
    $kimlik = '{0}/{1}' -f $r.arac, $r.model
    Ayarla $G 'uygulayan' $kimlik
    Ayarla $G $rol $kimlik
    Asama-Gec $G 'kontrol' 'uygulama bitti' '' $r
}

function Altyapi-Kontrol($G) {
    $tk = Tur-Klasoru $G
    $wt = Altyapi-Calisma $G
    $sorunlar = New-Object 'Collections.Generic.List[string]'
    $rapor = New-Object Text.StringBuilder
    $komutlar = @()
    if ($G.dogrulama) { $komutlar += @($G.dogrulama | Where-Object { $_ }) }
    [void]$rapor.AppendLine('### Doğrulama komutları')
    if (-not $komutlar) { [void]$rapor.AppendLine('- (talepte doğrulama komutu yok; doğrulamayı destek rolü ve yönetici yapacak)') }
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
    $kes = Altyapi-Kesif
    [void]$rapor.AppendLine('')
    [void]$rapor.AppendLine('### Keşif (uygulamadan sonra)')
    [void]$rapor.AppendLine($kes.metin)

    $gecti = ($sorunlar.Count -eq 0)
    $baslik = 'KALDI'; if ($gecti) { $baslik = 'GEÇTİ' }
    $metin = "## Otomatik kontrol: $baslik`n`n"
    if (-not $gecti) { $metin += "### Sorunlar`n" + (($sorunlar | ForEach-Object { "- $_" }) -join "`n") + "`n`n" }
    $metin += $rapor.ToString()
    Metin-Yaz (Join-Path $tk 'kontrol.md') $metin
    Ayarla $G 'son_kontrol' $baslik
    if ($gecti) {
        $sonraki = 'denetim'
        if ([string]$G.destek -eq 'yok') { $sonraki = 'kabul' }
        Asama-Gec $G $sonraki 'otomatik kontroller geçti' ('{0} komut' -f @($komutlar).Count)
    } else { Yeni-Tur $G $metin ('otomatik kontroller kaldı: ' + ($sorunlar -join '; ')) }
}

function Altyapi-Dogrulama($G) {
    $destek = [string]$G.destek
    if (-not $AltyapiRolleri.ContainsKey($destek)) { Asama-Gec $G 'kabul' 'destek rolü yok; doğrulama atlandı'; return }
    $tk = Tur-Klasoru $G
    $wt = Altyapi-Calisma $G
    $sorumlu = [string]$G.sorumlu
    if (-not $AltyapiRolleri.ContainsKey($sorumlu)) { $sorumlu = 'sistem' }
    $istem = Sablon-Doldur 'altyapi-dogrulama.md' @{
        ROL_ADI = $AltyapiRolleri[$destek].ad; ROL_TANIMI = $AltyapiRolleri[$destek].tanim; ROL_KISA = $destek
        SORUMLU_ADI = $AltyapiRolleri[$sorumlu].ad; CALISMA = $wt
        ORTAM = (Altyapi-Ortam); KESIF = (Metin-Oku (Join-Path $tk 'kesif.md')); BASLANGIC_VM = (Baslangic-VM-Metni $G)
        GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G)
        UYGULAMA_OZET = (Metin-Oku (Join-Path $tk 'uygulama-ozet.md')); KONTROL = (Metin-Oku (Join-Path $tk 'kontrol.md'))
    }
    # Uygulayan model kendi işini doğrulamasın
    $haric = @(); if ($G.uygulayan) { $haric = @([string]$G.uygulayan) }
    $r = Ajan-Cagir -Rol $destek -Istem $istem -Klasor $wt -KayitKlasoru $tk -Etiket 'dogrulama' -Haric $haric -TamYetki
    if (-not $r.basarili) { Adim-Basarisiz $G "$($AltyapiRolleri[$destek].ad) doğrulayamadı: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'dogrulama.md') $r.metin
    $kimlik = '{0}/{1}' -f $r.arac, $r.model
    Ayarla $G 'dogrulayan' $kimlik
    Ayarla $G $destek $kimlik
    switch (Karar-Oku $r.metin) {
        'ONAY' { Asama-Gec $G 'kabul' 'doğrulama onayladı' '' $r }
        'DUZELT' {
            Gecmis-Ekle $G 'doğrulama düzeltme istedi' '' $r
            Yeni-Tur $G ("## Doğrulama düzeltme istedi`n`n" + $r.metin) 'doğrulama düzeltme istedi'
        }
        default { Adim-Basarisiz $G "Doğrulama çıktısında KARAR satırı yok ($($r.arac))" }
    }
}

function Altyapi-Kabul($G) {
    $tk = Tur-Klasoru $G
    $dog = Metin-Oku (Join-Path $tk 'dogrulama.md')
    if (-not $dog) { $dog = '(Bu talepte destek rolü yoktu; bağımsız doğrulama yapılmadı.)' }
    $istem = Sablon-Doldur 'lider-altyapi-kabul.md' @{
        ORTAM = (Altyapi-Ortam); GOREV = (Gorev-Metni $G); PLAN = (Plan-Metni $G)
        UYGULAMA_OZET = (Metin-Oku (Join-Path $tk 'uygulama-ozet.md')); KONTROL = (Metin-Oku (Join-Path $tk 'kontrol.md')); DOGRULAMA = $dog
    }
    $r = Ajan-Cagir -Rol 'lider' -Istem $istem -Klasor (Altyapi-Calisma $G) -KayitKlasoru $tk -Etiket 'kabul'
    if (-not $r.basarili) { Adim-Basarisiz $G "Yönetici son kararı veremedi: $($r.hata)"; return }
    Metin-Yaz (Join-Path $tk 'kabul.md') $r.metin
    switch (Karar-Oku $r.metin) {
        'KABUL' {
            Ayarla $G 'ozet' (Alan-Oku $r.metin 'OZET')
            Asama-Gec $G 'tamamla' 'yönetici kabul etti' '' $r
        }
        'RET' {
            Gecmis-Ekle $G 'yönetici reddetti' '' $r
            Yeni-Tur $G ("## Yönetici reddetti`n`n" + $r.metin) 'yönetici reddetti'
        }
        'SORU_VAR' { Altyapi-Soru $G $r.metin $r 'yönetici kullanıcıdan bilgi istedi' }
        default { Adim-Basarisiz $G "Kabul çıktısında KARAR satırı yok ($($r.arac))" }
    }
}

function Altyapi-Tamamla($G) {
    $gk = Gorev-Klasoru $G.id
    $ozet = [string]$G.ozet
    if (-not $ozet) { $ozet = 'Talep tamamlandı.' }
    $k = Altyapi-Kesif
    $md = @(
        "# Sonuç: $($G.baslik)", '', $ozet, '',
        "- Sorumlu: $($G.sorumlu) ($($G.uygulayan)) | Destek: $($G.destek) ($($G.dogrulayan)) | Yönetici: $($G.lider) | Tur: $($G.tur)",
        "- Raporlar: tur$($G.tur)\uygulama-ozet.md, tur$($G.tur)\kontrol.md, tur$($G.tur)\dogrulama.md, tur$($G.tur)\kabul.md",
        "- Çalışma klasörü (ajanların betik ve günlükleri): $($G.calisma_klasoru)", '',
        '## Son durum', '', $k.metin
    ) -join "`n"
    Metin-Yaz (Join-Path $gk 'sonuc.md') $md
    Asama-Gec $G 'tamam' 'talep kapatıldı' ''
    Sayac-Artir 'tamamlanan'
    Bildir -Baslik "Talep tamamlandı: $($G.baslik)" -Metin (Gizli-Maskele ('{0} ({1} tur)' -f (Kisalt $ozet 180), $G.tur)) -Anahtar "tamam-$($G.id)"
}

function Altyapi-Adim($G) {
    switch ($G.asama) {
        'yeni'       { Altyapi-Hazirla $G }
        'plan'       { Altyapi-Plan $G }
        'gelistirme' { Altyapi-Uygulama $G }
        'kontrol'    { Altyapi-Kontrol $G }
        'denetim'    { Altyapi-Dogrulama $G }
        'kabul'      { Altyapi-Kabul $G }
        'tamamla'    { Altyapi-Tamamla $G }
    }
}
