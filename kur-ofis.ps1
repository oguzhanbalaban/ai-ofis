<#
AI Ofis etkileşimli kurulumu. Windows PowerShell 5.1+.
Paket indirmez; seçilen araçların kurulumunu ve girişini kullanıcı tamamlar.
Dot-source edildiğinde yalnızca işlevler yüklenir (çevrimdışı testler için).
#>
[CmdletBinding()]
param()
$script:KurulumKok = $PSScriptRoot

function Yanit-Al {
    param([string]$Soru, [string]$Varsayilan = '', [scriptblock]$Dogrula, [switch]$BosIzin)
    while ($true) {
        $etiket = $Soru
        if ($Varsayilan) { $etiket += " [$Varsayilan]" }
        if ($BosIzin) { $etiket += ' (-: boş bırak)' }
        $y = (Read-Host $etiket).Trim()
        if (-not $y) { $y = $Varsayilan }
        if ($BosIzin -and $y -eq '-') { $y = '' }
        if (-not $y -and -not $BosIzin) { Write-Host 'Bir değer girin.'; continue }
        if ($Dogrula -and -not (& $Dogrula $y)) { Write-Host 'Geçersiz değer; tekrar deneyin.'; continue }
        return $y
    }
}
function Evet-Hayir([string]$Soru, [bool]$Varsayilan = $false) {
    $v = 'h'; if ($Varsayilan) { $v = 'e' }
    return ((Yanit-Al "$Soru (e/h)" $v { param($s) $s -match '^(e|h)$' }) -eq 'e')
}
function Dosya-Var([string]$Yol) {
    if (-not $Yol) { return $false }
    try { return [bool](Test-Path -LiteralPath $Yol -PathType Leaf -ErrorAction Stop) }
    catch { return $false }
}
function Kurulum-Json-Oku([string]$Ad) {
    $yol = Join-Path $script:KurulumKok "$Ad.yerel.json"
    if (-not (Test-Path -LiteralPath $yol)) { $yol = Join-Path $script:KurulumKok "$Ad.json" }
    # Bozuk kişisel ayarı sessizce şablonla değiştirme.
    return (Get-Content -LiteralPath $yol -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}
# Şirket binasının katları (katlar.json): katın şablonu ya da kişisel kopyası (<ad>.yerel.json)
function Kat-Json-Oku([string]$Klasor, [string]$Ad) {
    $y = Join-Path $Klasor "$Ad.yerel.json"; if (-not (Test-Path -LiteralPath $y)) { $y = Join-Path $Klasor "$Ad.json" }
    return ([IO.File]::ReadAllText($y) | ConvertFrom-Json)
}
function Kat-Json-Yaz($Nesne, [string]$Klasor, [string]$Ad) {
    [IO.File]::WriteAllText((Join-Path $Klasor "$Ad.yerel.json"), ($Nesne | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding $false))
}
function Kurulum-Json-Yaz($Nesne, [string]$Ad) {
    $yol = Join-Path $script:KurulumKok "$Ad.yerel.json"
    $tmp = "$yol.tmp"
    [IO.File]::WriteAllText($tmp, ($Nesne | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $yol) { [IO.File]::Replace($tmp, $yol, "$yol.bak") }
    else { [IO.File]::Move($tmp, $yol) }
}
function Komut-Bul([string[]]$Adlar, [string[]]$Yollar = @()) {
    foreach ($ad in $Adlar) {
        $c = Get-Command $ad -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
    }
    foreach ($yol in $Yollar) { if (Dosya-Var $yol) { return $yol } }
    return ''
}
function Araclari-Bul {
    $codex = Komut-Bul @('codex.exe', 'codex.cmd')
    if (-not $codex -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        $pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg) { $codex = Komut-Bul @() @((Join-Path $pkg.InstallLocation 'app\resources\codex.exe')) }
    }
    return @{
        claude = (Komut-Bul @('claude.exe') @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')))
        codex = $codex
        gemini = (Komut-Bul @('gemini.cmd', 'gemini.exe'))
    }
}
function Araclari-Uyarla($Ayar, $Kadro, [hashtable]$Modeller, [string[]]$Sira) {
    # Mevcut rolün ilk araç tercihini koru, kalan seçili araçları yedek ekle.
    # İki model aynı araçla bağımsız denetim yapılabilmesini sağlar.
    $hedefler = @($Ayar.roller.PSObject.Properties) + @($Kadro.uyeler)
    foreach ($hedef in $hedefler) {
        $yerlesik = $hedef -is [System.Management.Automation.PSPropertyInfo]
        $eski = @($hedef.araclar); if ($yerlesik) { $eski = @($hedef.Value) }
        $oncelik = @()
        foreach ($g in $eski) { if ($g.arac -in $Sira -and $g.arac -notin $oncelik) { $oncelik += [string]$g.arac } }
        foreach ($arac in $Sira) { if ($arac -notin $oncelik) { $oncelik += $arac } }
        $zincir = @()
        foreach ($arac in $oncelik) {
            foreach ($model in $Modeller[$arac]) {
                $g = [ordered]@{ arac = $arac; model = $model }
                if ($arac -eq 'codex') { $g.efor = 'high' }
                $zincir += [pscustomobject]$g
            }
        }
        if ($yerlesik) { $Ayar.roller.($hedef.Name) = @($zincir) }
        else { $hedef | Add-Member -NotePropertyName araclar -NotePropertyValue @($zincir) -Force }
    }
    # Paneldeki model seçici yalnızca katalogdaki modelleri kaydeder: kurulumda seçilen modelleri kataloğa ekle
    if (-not $Ayar.model_katalogu) { $Ayar | Add-Member -NotePropertyName model_katalogu -NotePropertyValue ([pscustomobject]@{}) -Force }
    foreach ($arac in $Sira) {
        $liste = @(); if ($Ayar.model_katalogu.PSObject.Properties[$arac]) { $liste = @($Ayar.model_katalogu.$arac | Where-Object { $_ }) }
        foreach ($model in $Modeller[$arac]) {
            if (-not @($liste | Where-Object { [string]$_.model -eq $model }).Count) { $liste += [pscustomobject][ordered]@{ model = $model; ad = $model; not = 'kurulumda seçildi' } }
        }
        $Ayar.model_katalogu | Add-Member -NotePropertyName $arac -NotePropertyValue @($liste) -Force
    }
}
function Vmrun-Bul {
    $adaylar = @()
    foreach ($taban in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($taban) {
            foreach ($urun in @('VMware Workstation', 'VMware Player')) { $adaylar += Join-Path $taban "VMware\$urun\vmrun.exe" }
        }
    }
    return (Komut-Bul @('vmrun.exe') $adaylar)
}
function Vmrun-Listele([string]$Exe) {
    if (-not $Exe) { return @() }
    $cikti = Join-Path $script:KurulumKok ('.vmrun-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $hata = "$cikti.err.tmp"
    $p = $null
    try {
        # Yalnızca listeleme; VM açma, kapatma veya konukta komut çalıştırma yok.
        $p = Start-Process -FilePath $Exe -ArgumentList 'list' -WindowStyle Hidden -PassThru -RedirectStandardOutput $cikti -RedirectStandardError $hata
        $null = $p.Handle
        if (-not $p.WaitForExit(10000)) { $p.Kill(); Write-Warning 'vmrun list zaman aşımına uğradı.'; return @() }
        if ($p.ExitCode -ne 0) { Write-Warning 'vmrun list başarısız; VMX taraması kullanılacak.'; return @() }
        return @(Get-Content -LiteralPath $cikti | Where-Object { $_ -match '\.vmx\s*$' } | ForEach-Object { $_.Trim() })
    } catch { Write-Warning 'vmrun list çalıştırılamadı; VMX taraması kullanılacak.'; return @() }
    finally {
        if ($p) { $p.Dispose() }
        Remove-Item -LiteralPath $cikti,$hata -Force -ErrorAction SilentlyContinue
    }
}
function Vmleri-Bul([string]$Vmrun, [string[]]$Kokler) {
    $yollar = @(Vmrun-Listele $Vmrun)
    foreach ($kok in $Kokler) {
        if ($kok -and (Test-Path -LiteralPath $kok -PathType Container -ErrorAction SilentlyContinue)) {
            $yollar += @(Get-ChildItem -LiteralPath $kok -Filter '*.vmx' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    return @($yollar | Where-Object { $_ } | Sort-Object -Unique)
}
function Vmx-Bilgisi([string]$Yol) {
    $ad = [IO.Path]::GetFileNameWithoutExtension($Yol); $isletim = 'Bilinmiyor'
    if (Dosya-Var $Yol) {
        $metin = Get-Content -LiteralPath $Yol -Raw -Encoding UTF8
        if ($metin -match '(?m)^\s*displayName\s*=\s*"([^"]+)"') { $ad = $Matches[1] }
        if ($metin -match '(?m)^\s*guestOS\s*=\s*"([^"]+)"') { $isletim = $Matches[1] }
    }
    return [pscustomobject]@{ ad = $ad; isletim = $isletim }
}
function Ana-Makine {
    $isletim = 'Windows'; $aciklama = ''
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $isletim = [string]$os.Caption
        $aciklama = '{0}; {1:N1} GB RAM' -f $cpu.Name, ($os.TotalVisibleMemorySize / 1MB)
    } catch { Write-Warning 'Ana makine donanımı okunamadı; genel Windows kaydı kullanılacak.' }
    return [pscustomobject]@{ ad = 'ANA-MAKINE'; ip = '127.0.0.1'; isletim = $isletim; vmx = ''; yonetim = ''; aciklama = $aciklama }
}
function Makine-Sor([string]$Vmx = '', $Onceki = $null, [string[]]$Adlar = @()) {
    $bilgi = [pscustomobject]@{ ad = 'LAB-SRV'; isletim = 'Bilinmiyor' }
    if ($Vmx) { $bilgi = Vmx-Bilgisi $Vmx }
    if ($Onceki) { $bilgi = $Onceki }
    do {
        $ad = Yanit-Al 'Makine adı' $bilgi.ad
        if ($ad -in $Adlar) { Write-Host 'Bu makine adı zaten var.' }
    } while ($ad -in $Adlar)
    $ipVars = ''; if ($Onceki) { $ipVars = [string]$Onceki.ip }
    $ip = Yanit-Al 'IP adresi (bilinmiyorsa boş)' $ipVars {
        param($s) $adres = $null; (-not $s) -or [Net.IPAddress]::TryParse($s, [ref]$adres)
    } -BosIzin
    $isletim = Yanit-Al 'İşletim sistemi' $bilgi.isletim
    $aciklama = ''; $yonetim = ''
    if ($Onceki) { $aciklama = [string]$Onceki.aciklama; $yonetim = [string]$Onceki.yonetim }
    $aciklama = Yanit-Al 'Açıklama' $aciklama -BosIzin
    return [pscustomobject]@{ ad = $ad; ip = $ip; isletim = $isletim; vmx = $Vmx; yonetim = $yonetim; aciklama = $aciklama }
}
function Kurulumu-Baslat {
    $ErrorActionPreference = 'Stop'
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'PowerShell 5.1 veya üstü gerekir.' }
    if ($env:OS -ne 'Windows_NT') { throw 'AI Ofis Windows üzerinde çalışır.' }
    Write-Host 'AI Ofis kurulumu — tam kadro, kişisel ayarlar, isteğe bağlı altyapı'
    Write-Host 'Mevcut ofis döngüsünü durdurup kurulumu çalıştırın. Hiçbir paket otomatik indirilmez.'
    if (-not (Komut-Bul @('git.exe'))) { throw 'Git bulunamadı. Git for Windows kurup terminali yeniden açın: https://git-scm.com/download/win' }
    if (Test-Path -LiteralPath (Join-Path $script:KurulumKok 'ayarlar.yerel.json')) {
        if (-not (Evet-Hayir 'Mevcut kişisel ayarlar yeniden yapılandırılsın mı?')) { Write-Host 'Ayarlar değiştirilmedi.'; return }
    }
    $a = Kurulum-Json-Oku 'ayarlar'; $k = Kurulum-Json-Oku 'kadro'; $projeler = Kurulum-Json-Oku 'projeler'
    $araclar = Araclari-Bul
    foreach ($arac in @('claude','codex','gemini')) {
        if ($araclar[$arac]) { Write-Host ("{0}: {1}" -f $arac, $araclar[$arac]) }
        else { Write-Host "${arac}: bulunamadı (kurup giriş yapın veya kurulumda tam yol girin)." }
    }
    Write-Host 'Claude: https://code.claude.com/docs/en/setup ; Codex: https://developers.openai.com/codex/ ; Gemini: https://geminicli.com/'
    $varsayilan = @('claude','codex','gemini' | Where-Object { $araclar[$_] }) -join ','
    if (-not $varsayilan) { $varsayilan = 'claude,codex' }
    $secim = Yanit-Al 'Kullanacağınız araçlar (virgülle: claude,codex,gemini)' $varsayilan {
        param($s) $parcalar = @($s.ToLowerInvariant().Split(',') | ForEach-Object { $_.Trim() }); @($parcalar | Where-Object { $_ -notin @('claude','codex','gemini') }).Count -eq 0
    }
    $secilen = @($secim.ToLowerInvariant().Split(',') | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $varsModel = @{ claude = 'opus,sonnet'; codex = 'gpt-6.1-sol,gpt-6-astra'; gemini = 'gemini-2.5-pro,gemini-2.5-flash' }
    foreach ($arac in $secilen) {
        $mevcut = @($a.roller.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_.arac -eq $arac } | ForEach-Object { $_.model } | Select-Object -Unique)
        if ($mevcut.Count -ge 2) { $varsModel[$arac] = $mevcut -join ',' }
    }
    $modeller = @{}
    foreach ($arac in $secilen) {
        $yolVars = [string]$araclar[$arac]
        if ($a.PSObject.Properties[$arac] -and (Dosya-Var $a.$arac.exe)) { $yolVars = [string]$a.$arac.exe }
        $yol = Yanit-Al "$arac çalıştırılabilir dosyasının tam yolu" $yolVars {
            param($s) (Dosya-Var $s) -and ([IO.Path]::GetExtension($s) -in @('.exe','.cmd','.bat'))
        }
        if (-not $a.PSObject.Properties[$arac]) { $a | Add-Member -NotePropertyName $arac -NotePropertyValue ([pscustomobject]@{ exe = $yol }) }
        else { $a.$arac.exe = $yol }
        $m = Yanit-Al "$arac modelleri (birincil,denetim/yedek; hesabınızda erişilebilir kimlikler)" $varsModel[$arac] {
            param($s)
            $liste = @($s.Split(',') | ForEach-Object { $_.Trim() })
            (@($liste | Where-Object { $_ -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$' }).Count -eq 0) -and (@($liste | Select-Object -Unique).Count -ge 2)
        }
        $modeller[$arac] = @($m.Split(',') | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    }
    Araclari-Uyarla $a $k $modeller $secilen
    # Outsource Consultant, seçilen yapay zekanın terminal ajanıdır (Claude Code / Codex / Gemini); birden çok araç seçildiyse sor
    $danismanArac = $secilen[0]
    if ($secilen.Count -gt 1) {
        $secenekler = $secilen
        $danismanArac = (Yanit-Al ("Outsource Consultant (tek parça işleri terminalde kendi başına yapan dış danışman) hangi yapay zekayla çalışsın? ({0})" -f ($secilen -join ', ')) $secilen[0] {
            param($s) $s.Trim().ToLowerInvariant() -in $secenekler
        }.GetNewClosure()).Trim().ToLowerInvariant()
    }
    if ($a.roller.PSObject.Properties['danisman']) {
        $dz = @($a.roller.danisman)
        $a.roller.danisman = @(@($dz | Where-Object { $_.arac -eq $danismanArac }) + @($dz | Where-Object { $_.arac -ne $danismanArac }))
    }
    Write-Host "Outsource Consultant: $danismanArac (masa: danisman\CLAUDE.md; Codex AGENTS.md, Gemini GEMINI.md kopyasını okur)"
    $girisHazir = Evet-Hayir 'Seçtiğiniz araçlarda giriş ve model/abonelik erişimi hazır mı? (Çevrimiçi doğrulanmaz)'
    if (-not $girisHazir) { Write-Warning 'Yeni otomatik başlatma görevi kurulmayacak. CLI girişlerini tamamlayın; kurulumunuz yine kaydedilecek.' }

    $makineler = @($a.altyapi.makineler | Where-Object { $_ -and $_.ad -ne 'ANA-MAKINE' })
    $a.altyapi.makineler = @((Ana-Makine)) + $makineler
    if (Evet-Hayir 'Altyapı / VM makinelerini yapılandırmak ister misiniz?' $true) {
        $vmrun = Vmrun-Bul
        $vmrun = Yanit-Al 'VMware vmrun.exe yolu (yoksa boş)' $vmrun { param($s) (-not $s) -or (Dosya-Var $s) } -BosIzin
        $a.altyapi.vmrun = $vmrun
        if (Evet-Hayir 'Açık VM listesini ve seçilen klasörlerde VMX dosyalarını tara?' $true) {
            $kokVars = @('C:\VMs','D:\VMs','H:\VMs', (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines')) -join ';'
            $kokler = Yanit-Al 'VMX aranacak klasörler (noktalı virgülle)' $kokVars -BosIzin
            $bulunan = @(Vmleri-Bul $vmrun @($kokler.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
            Write-Host ("Bulunan VM sayısı: {0}" -f $bulunan.Count)
            foreach ($vmx in $bulunan) {
                Write-Host "VM: $vmx"
                $onceki = $a.altyapi.makineler | Where-Object { $_.vmx -ieq $vmx } | Select-Object -First 1
                if (-not (Evet-Hayir 'Bu VM kaydedilsin/güncellensin mi?' $true)) { continue }
                $diger = @($a.altyapi.makineler | Where-Object { $_ -ne $onceki })
                $makine = Makine-Sor $vmx $onceki @($diger | ForEach-Object { $_.ad })
                $a.altyapi.makineler = $diger + @($makine)
            }
        }
        while (Evet-Hayir 'Elle makine eklemek ister misiniz? (fiziksel veya VM)') {
            $vmx = Yanit-Al 'VMX tam yolu (fiziksel makine için boş)' '' { param($s) (-not $s) -or ((Dosya-Var $s) -and $s.EndsWith('.vmx', [StringComparison]::OrdinalIgnoreCase)) } -BosIzin
            $a.altyapi.makineler += Makine-Sor $vmx $null @($a.altyapi.makineler | ForEach-Object { $_.ad })
        }
        $a.altyapi.baglanti_bilgileri = Yanit-Al 'Kendi bağlantı bilgileri dosyanızın yolu (isteğe bağlı; içeriği kopyalanmaz)' ([string]$a.altyapi.baglanti_bilgileri) { param($s) (-not $s) -or (Dosya-Var $s) } -BosIzin
    }
    $a.bildirim.masaustu = Evet-Hayir 'Masaüstü bildirimleri açılsın mı?' ([bool]$a.bildirim.masaustu)
    if (Evet-Hayir 'Telefona ntfy bildirimi ister misiniz?' ([bool]$a.bildirim.telefon.ntfy_konu)) {
        $konu = [string]$a.bildirim.telefon.ntfy_konu
        if (-not $konu) { $konu = 'ai-ofis-' + [guid]::NewGuid().ToString('N') }
        $a.bildirim.telefon.ntfy_konu = Yanit-Al 'ntfy konusu (rastgele varsayılan önerilir)' $konu { param($s) $s -match '^[a-zA-Z0-9_-]{8,128}$' }
        Write-Host 'Telefonda ntfy uygulamasını açın. Aşağıdaki sunucu ve konuya abone olun; konuyu paylaşmayın.'
        Write-Host ("Sunucu: {0}; konu: {1}" -f $a.bildirim.telefon.ntfy_sunucu, $a.bildirim.telefon.ntfy_konu)
    } else { $a.bildirim.telefon.ntfy_konu = '' }
    $ozet = Yanit-Al 'Özet saatleri (virgülle HH:mm)' ($a.bildirim.ozet_saatleri -join ',') {
        param($s) @($s.Split(',') | Where-Object { $_.Trim() -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$' }).Count -eq 0
    }
    $a.bildirim.ozet_saatleri = @($ozet.Split(',') | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $a.dongu.calisma_saatleri = Yanit-Al 'Çalışma saatleri (geceyi aşabilir, HH:mm-HH:mm)' ([string]$a.dongu.calisma_saatleri) {
        param($s) $s -match '^([01][0-9]|2[0-3]):[0-5][0-9]-(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' -and ($s.Split('-')[0] -ne $s.Split('-')[1])
    }
    if (Evet-Hayir 'Hemen bir yazılım projesi eklemek ister misiniz?') {
        $klasor = Yanit-Al 'Var olan Git proje klasörü' '' {
            param($s)
            if (-not (Test-Path -LiteralPath $s -PathType Container -ErrorAction SilentlyContinue)) { return $false }
            $null = & git -C $s rev-parse --show-toplevel 2>$null
            return ($LASTEXITCODE -eq 0)
        }
        $klasor = (Resolve-Path -LiteralPath $klasor).Path
        if (-not @($projeler.projeler | Where-Object { $_.klasor -ieq $klasor }).Count) {
            $ad = Yanit-Al 'Proje adı' (Split-Path $klasor -Leaf) { param($s) $s -notin @($projeler.projeler | ForEach-Object { $_.ad }) }
            $projeler.projeler = @($projeler.projeler) + [pscustomobject]@{ ad = $ad; klasor = $klasor; temel_dal = ''; dogrulama = @() }
        }
    }
    foreach ($d in @('gorevler','durum','gunluk','raporlar','calisma')) { New-Item -ItemType Directory -Path (Join-Path $script:KurulumKok $d) -Force | Out-Null }
    $kilit = Join-Path $script:KurulumKok 'durum\kilitler.json'
    if (-not (Test-Path -LiteralPath $kilit)) { [IO.File]::WriteAllText($kilit, '{}') }
    Kurulum-Json-Yaz $a 'ayarlar'; Kurulum-Json-Yaz $k 'kadro'; Kurulum-Json-Yaz $projeler 'projeler'
    # Şirket binası: alt katların rol zincirleri de seçilen araçlara uyarlanır (katın *.yerel.json'u); bildirim, araç yolları gibi
    # ortak ayarları ana kattan alırlar. Katlar kapalı başlar; panelde solda Kat seçiciden açılır.
    $katlarYolu = Join-Path $script:KurulumKok 'katlar.json'
    $katlarJ = $null; if (Test-Path -LiteralPath $katlarYolu) { $katlarJ = [IO.File]::ReadAllText($katlarYolu) | ConvertFrom-Json }
    foreach ($kat in @($katlarJ.katlar | Where-Object { $_ -and [string]$_.id -ne 'ana' -and [string]$_.tur -ne 'uygulama' -and [string]$_.kok })) {
        $katKoku = Join-Path $script:KurulumKok ([string]$kat.kok)
        if (-not (Test-Path -LiteralPath (Join-Path $katKoku 'ayarlar.json')) -or -not (Test-Path -LiteralPath (Join-Path $katKoku 'kadro.json'))) { continue }
        $katAyar = Kat-Json-Oku $katKoku 'ayarlar'; $katKadro = Kat-Json-Oku $katKoku 'kadro'
        if ($katAyar.roller) { Araclari-Uyarla $katAyar $katKadro $modeller $secilen }
        Kat-Json-Yaz $katAyar $katKoku 'ayarlar'; Kat-Json-Yaz $katKadro $katKoku 'kadro'
        foreach ($dd in @('gorevler','durum','gunluk','raporlar','calisma')) { New-Item -ItemType Directory -Path (Join-Path $katKoku $dd) -Force | Out-Null }
        $durdur = Join-Path $katKoku 'DURDUR'
        if (-not (Test-Path -LiteralPath $durdur)) { [IO.File]::WriteAllText($durdur, "Ofis kapatıldı (kurulum). Kat, paneldeki bina görünümünden (solda Kat seçici) açılır.`n", (New-Object Text.UTF8Encoding $false)) }
        Write-Host "Kat hazır: $($kat.ad) (kapalı; panelden açılır)"
    }
    Write-Host 'Kişisel ayarlar *.yerel.json dosyalarına kaydedildi. Dağıtım şablonları değişmedi.'
    if ($girisHazir -and (Evet-Hayir 'Ekip oturum açılışında otomatik başlasın mı?')) {
        try { & (Join-Path $script:KurulumKok 'kur.ps1') } catch { Write-Warning "Otomatik başlatma kurulamadı: $($_.Exception.Message)" }
    }
    if (Evet-Hayir 'Masaüstüne ofis paneli kısayolu eklensin mi?' $true) {
        try { & (Join-Path $script:KurulumKok 'ofis\kisayol-olustur.ps1') } catch { Write-Warning "Kısayol kurulamadı: $($_.Exception.Message)" }
    }
    Write-Host 'Kurulum tamamlandı. Durum: .\durum.ps1 ; boş döngü kontrolü: .\baslat.ps1 -Konsol -BosBitir'
    Write-Host 'Ofis: .\ofis\ofis.ps1 -Ac ; e-posta: .\eposta-kur.ps1 ; telefon paneli: .\ofis\telefon-kur.ps1'
}

if ($MyInvocation.InvocationName -ne '.') { Kurulumu-Baslat }
