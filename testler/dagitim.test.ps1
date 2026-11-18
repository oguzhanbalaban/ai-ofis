<# Çevrimdışı dağıtım kontrolleri; Pester veya ek paket gerektirmez. #>
$ErrorActionPreference = 'Stop'
# Alt süreçler UTF-8 yazar; çıktı bir dosyaya yönlendirilmişken de doğru okunsun
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$kaynak = Split-Path -Parent $PSScriptRoot
$testKok = Join-Path $kaynak '.test-calisma'
$calisma = Join-Path $testKok ([guid]::NewGuid().ToString('N'))
$paket = Join-Path $calisma 'paket'
$script:kontrol = 0
function Dogrula([bool]$Kosul, [string]$Aciklama) {
    if (-not $Kosul) { throw "BAŞARISIZ: $Aciklama" }
    $script:kontrol++; Write-Host "OK $script:kontrol - $Aciklama"
}
function Json([string]$Yol) { Get-Content -LiteralPath $Yol -Raw -Encoding UTF8 | ConvertFrom-Json }
function AltSurec([string]$Dosya, [string[]]$Ek = @()) {
    $cikti = & "$PSHOME\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Dosya @Ek 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Alt süreç başarısız: $Dosya`n$cikti" }
    return $cikti
}
try {
    $betikler = @(Get-ChildItem -LiteralPath $kaynak -File -Filter '*.ps1') + @(Get-ChildItem -LiteralPath (Join-Path $kaynak 'ofis') -File -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.ps1')
    foreach ($f in $betikler) {
        $tok = $null; $hata = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$hata)
        Dogrula (@($hata).Count -eq 0) "$($f.Name) PowerShell sözdizimi"
        $b = [IO.File]::ReadAllBytes($f.FullName)
        Dogrula ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) "$($f.Name) UTF-8 BOM"
    }
    $a = Json (Join-Path $kaynak 'ayarlar.json'); $k = Json (Join-Path $kaynak 'kadro.json')
    Dogrula (@($k.uyeler).Count -eq 20) 'Tam kadro: 20 çalışan (CTO, Product Manager, Codebase Explorer, Frontend / Backend Developer, Outsource Consultant, Incident Manager ve QA Engineer dahil)'
    $dep = @{}; foreach ($u in $k.uyeler) { $dep[[string]$u.anahtar] = [string]$u.departman }
    Dogrula ($dep['cto'] -eq 'Yönetim' -and $dep['lider'] -eq 'Teknik koordinasyon' -and $dep['urun'] -eq 'Karşılama ve planlama' -and $a.planlama.analiz -and $a.planlama.qa_testi -and $a.yonetim.etkin -and $a.paralel.etkin -and $a.roller.cto -and $a.roller.urun -and $a.roller.kasif -and $a.roller.frontend -and $a.roller.backend) 'Yönetim (CTO), teknik koordinasyon ve planlama katmanı; paralel hat ayarları'
    Dogrula (@($k.uyeler | Where-Object { $_.ise_alinma -or $_.ise_alan }).Count -eq 0) 'İşe alım geçmişi anonim'
    Dogrula (@($a.altyapi.makineler).Count -eq 0 -and -not $a.altyapi.vmrun -and -not $a.altyapi.baglanti_bilgileri -and -not $a.bildirim.telefon.ntfy_konu -and -not $a.claude.kullanim_dosyasi -and -not $a.gorev.yeni_proje_kok) 'Ayarlar kişisel envanter, yol ve bildirim adresi içermiyor'
    Dogrula (@((Json (Join-Path $kaynak 'projeler.json')).projeler).Count -eq 0) 'Dağıtımda boş proje listesi'
    Dogrula ((@($k.uyeler | Where-Object { $_.anahtar -eq 'lider' })[0].ad -eq 'Engineering Manager') -and $a.roller.'sorun-giderici' -and $a.sorun_giderici.etkin) 'Engineering Manager adı, Incident Manager rolü ve ayarı tanımlı'
    Dogrula (@($a.roller.PSObject.Properties | Where-Object { @($_.Value)[0].arac -ne 'claude' }).Count -eq 0) 'Yerleşik rol zincirleri Claude öncelikli'
    $tester = @($k.uyeler | Where-Object { $_.anahtar -eq 'tester' })[0]
    Dogrula ($a.yardimlasma.etkin -and [int]$a.yardimlasma.gorev_basina_en_fazla -gt 0 -and [int]$a.yardimlasma.derinlik -gt 0 -and $tester -and $tester.yetki -eq 'tam' -and $tester.uzman_isi -and @($tester.araclar)[0].arac -eq 'claude') 'Ekip içi yardımlaşma ayarı ve QA Engineer (tam yetki, Claude önce) tanımlı'
    $liderZ = @($a.roller.lider | ForEach-Object { '{0}/{1}' -f $_.arac, $_.model })
    Dogrula (($liderZ -join ',') -like 'claude/claude-opus-5-5,claude/claude-fable-5-2,*' -and @($a.model_katalogu.claude).Count -ge 4 -and @($a.model_katalogu.codex).Count -ge 1 -and @($k.uyeler | Where-Object { -not $_.rol_tr }).Count -eq 0) 'Engineering Manager zinciri Opus 5.5 > Fable 5.2, model kataloğu ve tüm kadroda Türkçe unvan (rol_tr)'
    $yardimIstemi = [IO.File]::ReadAllText((Join-Path $kaynak 'istemler\yonetici-yardim.md'))
    Dogrula ($a.puanlama.etkin -and $yardimIstemi -match 'KARAR: BIRLIKTE' -and (Test-Path -LiteralPath (Join-Path $kaynak 'istemler\yardim-birlikte.md'))) 'Fibonacci puanlama açık; Engineering Manager birlikte çalışma kararı ve istemi var'
    $istemler = @(Get-ChildItem -LiteralPath (Join-Path $kaynak 'istemler') -Filter '*.md' -File -Recurse)
    Dogrula ($istemler.Count -eq 52) '36 akış (Comms, fikir hattı ve ofis geliştirme rehberi dahil) ve 16 kadro istemi'
    $katlarJ = Json (Join-Path $kaynak 'katlar.json')
    Dogrula ((@($katlarJ.katlar | ForEach-Object { $_.id }) -join ',') -eq 'ana,data-analytics,innovation-lab,creative-studio' -and @($katlarJ.katlar | Where-Object { [string]$_.kok -match ':' }).Count -eq 0) 'Şirket binası: dört kat, göreli kat klasörleri'
    $katMetni = (@(Get-ChildItem -LiteralPath (Join-Path $kaynak 'katlar') -Recurse -File | Where-Object { $_.Extension -in @('.json', '.md', '.ps1', '.py', '.java', '.unxspec') } | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
    Dogrula ($katMetni -notmatch '(?i)C:\\Users\\[A-Za-z]|192\.168\.168\.|ntfy_konu"\s*:\s*"[a-z]') 'Kat şablonları kişisel yol / adres / bildirim konusu içermiyor'
    $daAyar = Json (Join-Path $kaynak 'katlar\data-analytics\ayarlar.json')
    Dogrula (-not $daAyar.bildirim -and -not $daAyar.claude -and $daAyar.roller -and (Json (Join-Path $kaynak 'katlar\innovation-lab\kadro.json')).uyeler.anahtar -contains 'iletisim') 'Kat ayarları yalnız kata özgü (ortak ayarlar ana kattan); Innovation Lab katında Comms var'
    $masaMd = Join-Path $kaynak 'danisman\CLAUDE.md'
    $masaAna = [IO.File]::ReadAllText($masaMd).Replace("`r`n", "`n").Trim()
    Dogrula ((@('AGENTS.md', 'GEMINI.md') | Where-Object { [IO.File]::ReadAllText((Join-Path $kaynak "danisman\$_")).Replace("`r`n", "`n").Contains($masaAna) }).Count -eq 2 -and $masaAna -notmatch '(?i)C:\\Users') 'Danışman masası: CLAUDE.md yol içermez; AGENTS.md ve GEMINI.md onun kopyası'
    $dn = @($k.uyeler | Where-Object { $_.anahtar -eq 'danisman' })[0]
    Dogrula ($dn -and $dn.dogrudan_is -and $dn.departman -eq 'Dış danışmanlık' -and $a.danisman.etkin -and @($a.roller.danisman)[0].arac -eq 'claude' -and (@($a.danisman.izinli_araclar) -contains 'Bash') -and (@($a.danisman.yasak_araclar) -contains 'Bash(git push *)') -and (Test-Path -LiteralPath (Join-Path $kaynak 'istemler\danisman-claude.md'))) 'Outsource Consultant: Claude Code zinciri, izin / yasak listeleri, CLAUDE.md şablonu'
    foreach ($uye in $k.uyeler) {
        if ($uye.istem) { Dogrula (Test-Path -LiteralPath (Join-Path $kaynak $uye.istem)) "$($uye.anahtar) talimatı mevcut" }
    }
    Dogrula ((Test-Path -LiteralPath (Join-Path $kaynak 'ofis\panel.html')) -and (Test-Path -LiteralPath (Join-Path $kaynak 'araclar\posta_oku.py'))) 'Panel ve posta bağımlılığı pakette'

    # Gerçek kontrol adımını sahte Git çıktısıyla sınar; index ve AI araçlarına dokunmaz.
    & {
        $ekipAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $kaynak 'ekip.ps1'), [ref]$null, [ref]$null)
        $kontrolAdimi = $ekipAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Adim-Kontrol' }, $true)
        Invoke-Expression $kontrolAdimi.Extent.Text
        # Gizli bilgi taraması ayrı işlevde (kontrol adımı ve QA Engineerʼın test dosyaları ortak kullanır); desen listesi betik düzeyinde
        $gizliAdimi = $ekipAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Gizli-Satir-Sayisi' }, $true)
        Invoke-Expression $gizliAdimi.Extent.Text
        $desenAtamasi = $ekipAst.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:GizliDesenler' }, $true)
        Invoke-Expression $desenAtamasi.Extent.Text
        function QA-Testi-Var($G) { return $false }
        $Ayar = [pscustomobject]@{ gorev = @{ max_degisen_dosya = 60 }; korunan_desenler = @() }
        function Tur-Klasoru($G) { return $calisma }
        function Git-Calistir($Klasor, $Argumanlar) { if ($Argumanlar -contains '--name-only') { return 'ornek.txt' } }
        function Git-Dosyaya($Klasor, $Argumanlar, $Yol) { return $fark }
        function Proje-Bul($Ad) { return $null }
        function Metin-Yaz($Yol, $Metin) { $sonuc.rapor = $Metin }
        function Ayarla($G, $Alan, $Deger) { $sonuc[$Alan] = $Deger }
        function Yeni-Tur($G, $Metin, $Neden) { $sonuc.asama = 'gelistirme' }
        function Asama-Gec($G, $Yeni, $Olay, $Ayrinti) { $sonuc.asama = $Yeni }
        # Örnekler yalnızca çalışma anında üretilir; gerçek erişim bilgisi değildir.
        $ornekler = [ordered]@{
            AWS = 'AKIA' + ('A' * 16)
            AWSGecici = 'ASIA' + ('A' * 16)
            GitHub = 'ghp_' + ('a' * 30)
            GitHubActions = 'gha_' + ('a_-' * 10)
            GitHubCodespace = 'ghc_' + ('a_-' * 10)
            npm = 'npm_' + ('a' * 36)
            StripeCanli = 'sk_live_' + ('a' * 24)
            StripeTest = 'sk_test_' + ('a' * 24)
            Anthropic = 'sk-ant-' + ('a' * 20)
        }
        foreach ($ad in $ornekler.Keys) {
            $sonuc = @{}; $fark = '+' + $ornekler[$ad]
            Adim-Kontrol ([pscustomobject]@{ calisma_klasoru = $calisma; proje = 'test' })
            Dogrula ($sonuc.son_kontrol -eq 'KALDI' -and $sonuc.asama -eq 'gelistirme' -and $sonuc.rapor -match '1 olası gizli bilgi') "$ad eklenen satırda yakalandı ve denetime geçiş engellendi"
        }
        $coklu = '+' + $ornekler.AWSGecici + ' ' + $ornekler.StripeCanli
        $sonuc = @{}; $fark = $coklu
        Adim-Kontrol ([pscustomobject]@{ calisma_klasoru = $calisma; proje = 'test' })
        Dogrula ($sonuc.son_kontrol -eq 'KALDI' -and $sonuc.rapor -match '1 olası gizli bilgi') 'Aynı satırdaki birden fazla sır tek şüpheli satır sayılır'
        $sonuc = @{}
        $fark = @('+++ b/' + $ornekler.npm; '-' + $ornekler.AWSGecici; ' ' + $ornekler.StripeTest; '+zararsiz metin'; '+ASIA' + ('A' * 15); '+gha_' + ('a' * 29); '+ghc_' + ('a' * 29); '+npm_' + ('a' * 35); '+sk_live_' + ('a' * 23); '+sk_test_' + ('a' * 23)) -join "`n"
        Adim-Kontrol ([pscustomobject]@{ calisma_klasoru = $calisma; proje = 'test' })
        Dogrula ($sonuc.son_kontrol -eq 'GEÇTİ' -and $sonuc.asama -eq 'denetim') 'Diff başlığı, silinen/bağlam satırları ve kısa yer tutucular engellenmez'
    }

    New-Item -ItemType Directory -Path $paket -Force | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $kaynak -File -Filter '*.ps1')) { Copy-Item -LiteralPath $f.FullName -Destination $paket }
    foreach ($f in @('ayarlar.json','kadro.json','projeler.json','katlar.json','.gitignore','README.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $kaynak $f) -Destination $paket }
    Copy-Item -Recurse -LiteralPath (Join-Path $kaynak 'katlar') -Destination (Join-Path $paket 'katlar')
    foreach ($d in @('istemler','ofis','araclar','testler','danisman')) {
        $hedef = Join-Path $paket $d; New-Item -ItemType Directory -Path $hedef -Force | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $kaynak $d) -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.md','.html','.py') } | ForEach-Object {
            $goreli = $_.FullName.Substring((Join-Path $kaynak $d).Length).TrimStart('\')
            $yeni = Join-Path $hedef $goreli
            New-Item -ItemType Directory -Path (Split-Path -Parent $yeni) -Force | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $yeni
        }
    }
    $hashler = @{}; foreach ($f in @('ayarlar','kadro','projeler')) { $hashler[$f] = (Get-FileHash -LiteralPath (Join-Path $paket "$f.json")).Hash }
    . (Join-Path $paket 'kur-ofis.ps1')
    Dogrula (-not (Dosya-Var $a.claude.exe) -and -not (Dosya-Var '')) 'Şablon ve boş araç yolları hata vermiyor'
    # Tekli ve karma araç seçimleri, tüm rol ve kadro zincirlerini sınar.
    foreach ($secim in @('claude','codex','gemini','claude,codex','claude,codex,gemini')) {
        $aa = Json (Join-Path $paket 'ayarlar.json'); $kk = Json (Join-Path $paket 'kadro.json')
        $sira = $secim.Split(','); $modeller = @{}
        foreach ($arac in $sira) { $modeller[$arac] = @('model-a','model-b') }
        Araclari-Uyarla $aa $kk $modeller $sira
        $zincirler = @($aa.roller.PSObject.Properties | ForEach-Object { ,@($_.Value) }) + @($kk.uyeler | ForEach-Object { ,@($_.araclar) })
        foreach ($z in $zincirler) {
            if ($z.Count -ne ($sira.Count * 2) -or @($z | Where-Object { $_.arac -notin $sira }).Count) { throw "Araç zinciri hatası: $secim" }
        }
        Dogrula ($zincirler.Count -eq 32) "$secim seçimi: 12 rol ve 20 kadro zinciri"
        Dogrula (@($sira | Where-Object { @($aa.model_katalogu.$_ | Where-Object { $_.model -eq 'model-a' }).Count -eq 0 }).Count -eq 0) "$secim seçimi: kurulumda seçilen modeller panel kataloğunda"
    }

    # Tam kurulum, gerçek Read-Host yerine sıralı yanıtlar kullanır.
    $script:yanitlar = New-Object 'Collections.Generic.Queue[string]'
    function Read-Host([string]$Prompt) {
        if (-not $script:yanitlar.Count) { throw "Test yanıtı eksik: $Prompt" }
        return $script:yanitlar.Dequeue()
    }
    $script:sahteExe = Join-Path $PSHOME 'powershell.exe'
    function Araclari-Bul { return @{ claude = $script:sahteExe; codex = $script:sahteExe; gemini = $script:sahteExe } }
    function Vmrun-Bul { return $script:sahteExe }
    function Ana-Makine { return [pscustomobject]@{ ad = 'ANA-MAKINE'; ip = '127.0.0.1'; isletim = 'Windows test'; vmx = ''; yonetim = ''; aciklama = 'Test donanımı' } }
    $vmKok = Join-Path $calisma 'VM dosyalari'
    New-Item -ItemType Directory -Path $vmKok -Force | Out-Null
    $script:acikVmx = Join-Path $vmKok 'a.vmx'
    [IO.File]::WriteAllText($script:acikVmx, "displayName = `"Acik VM`"`nguestOS = `"windows-test`"")
    [IO.File]::WriteAllText((Join-Path $vmKok 'b.vmx'), "displayName = `"Kapali VM`"`nguestOS = `"linux-test`"")
    $script:listeCagrildi = $false
    function Vmrun-Listele([string]$Exe) { $script:listeCagrildi = [bool]$Exe; return @($script:acikVmx) }
    foreach ($s in @(
        'bilinmeyen','claude,codex', # Hatalı araç, sonra doğru seçim
        '','',               # Claude tespit edilen exe ve modelleri; anonim yol hata vermemeli
        '',                  # Codex tespit edilen exe
        'tek-model','',       # İki model şartı, ardından varsayılanlar
        'gemini','codex',     # Danışman yapay zekası: seçilmeyen araç reddedilir, sonra Codex
        'h',                 # Giriş hazır değil -> görev kurma sorusu yok
        'e','','e',$vmKok,    # Altyapı, vmrun, tara, klasör
        'e','','hatalı-ip','192.0.2.10','','açık VM kaydı',
        'e','','','','kapalı VM kaydı',
        'h','',              # Elle makine yok, bağlantı dosyası boş
        'h','e','',           # Masaüstü kapalı, ntfy açık, rastgele konu
        '25:00','',           # Hatalı özet saati ve düzeltme
        '24:00-30:00','22:00-06:00',
        'h','h'               # İlk proje ve kısayol yok
    )) { $script:yanitlar.Enqueue($s) }
    Kurulumu-Baslat
    Dogrula ($script:yanitlar.Count -eq 0) 'Etkileşimli kurulum tüm yanıtları tüketti'
    $yerel = Json (Join-Path $paket 'ayarlar.yerel.json')
    Dogrula ((@($yerel.roller.danisman)[0].arac -eq 'codex') -and (@($yerel.roller.danisman | Where-Object { $_.arac -eq 'claude' }).Count -ge 1) -and (@($yerel.roller.lider)[0].arac -eq 'claude')) 'Kurulumda seçilen yapay zeka (Codex) danışman oldu; diğer roller ve yedek zincir korunur'
    $katY = Json (Join-Path $paket 'katlar\data-analytics\ayarlar.yerel.json')
    $katKadroY = Json (Join-Path $paket 'katlar\innovation-lab\kadro.yerel.json')
    $katDurdur = Join-Path $paket 'katlar\data-analytics\DURDUR'
    Dogrula ($katY -and (@($katY.roller.lider | ForEach-Object { $_.arac }) -join ',') -eq (@($yerel.roller.lider | ForEach-Object { $_.arac }) -join ',') -and $katKadroY -and (Test-Path -LiteralPath $katDurdur) -and ([IO.File]::ReadAllText($katDurdur)).StartsWith('Ofis kapatıldı')) 'Kurulum alt katların rol zincirlerini uyarladı (*.yerel.json); katlar kapalı başlar'
    Dogrula ($script:listeCagrildi -and $yerel.altyapi.makineler.Count -eq 3) 'vmrun list ve VMX birleşimi, tekilleştirme, kapalı VM ve ana makine'
    Dogrula ($yerel.altyapi.makineler[1].ip -eq '192.0.2.10' -and $yerel.altyapi.makineler[2].ip -eq '') 'IP doğrulama ve bilinmeyen IP'
    Dogrula ($yerel.dongu.calisma_saatleri -eq '22:00-06:00' -and $yerel.bildirim.ozet_saatleri.Count -eq 2) 'Gece mesaisi ve özet saatleri doğrulandı'
    Dogrula ($yerel.bildirim.telefon.ntfy_konu -match '^ai-ofis-[a-f0-9]{32}$') 'Rastgele ntfy konusu üretildi'
    foreach ($f in @('ayarlar','kadro','projeler')) {
        Dogrula ((Get-FileHash -LiteralPath (Join-Path $paket "$f.json")).Hash -eq $hashler[$f]) "$f dağıtım şablonu değişmedi"
    }
    $once = (Get-FileHash -LiteralPath (Join-Path $paket 'ayarlar.yerel.json')).Hash
    $script:yanitlar.Enqueue('h'); Kurulumu-Baslat
    Dogrula ((Get-FileHash -LiteralPath (Join-Path $paket 'ayarlar.yerel.json')).Hash -eq $once) 'Tekrar kurulumdan vazgeçme mevcut ayarı korur'

    # Altyapısız, telefonsuz ve tek araçla yeniden kurulum.
    foreach ($s in @('e','gemini','','','h','h','h','h','','','h','h')) { $script:yanitlar.Enqueue($s) }
    Kurulumu-Baslat
    Dogrula ($script:yanitlar.Count -eq 0) 'Altyapısız yeniden kurulum tamamlandı'
    $yerel = Json (Join-Path $paket 'ayarlar.yerel.json')
    Dogrula ($yerel.altyapi.makineler.Count -eq 3 -and -not $yerel.bildirim.telefon.ntfy_konu) 'Yeniden kurulum makine envanterini korudu, telefonu kapattı'

    # Gerçek işletim sistemi bütünleşmeleri yerine işlev gövdelerini sınar.
    $panelAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $paket 'ofis\ofis.ps1'), [ref]$null, [ref]$null)
    . (Join-Path $paket 'ortak.ps1')
    Ayarlari-Yukle
    Dogrula ($Ayar.roller.lider[0].arac -eq 'gemini') 'Çalışma motoru yerel araç seçimini okuyor'
    Dogrula ((Codex-Exe) -eq $script:sahteExe -and (Gemini-Exe) -eq $script:sahteExe) 'Değiştirilebilir Codex ve Gemini yolları'
    # Kaynak klasör git deposu olmayabilir (ZIP'ten açılmış kurulum): test projesi için geçici depo aç.
    $testDepo = Join-Path $calisma 'test-deposu'
    New-Item -ItemType Directory -Path $testDepo -Force | Out-Null
    & git init -q -- $testDepo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Test deposu oluşturulamadı (git init).' }
    Json-Yaz ([pscustomobject]@{ projeler = @([pscustomobject]@{ ad = 'test'; klasor = $testDepo; temel_dal = ''; dogrulama = @() }) }) (Join-Path $paket 'projeler.json')
    Dogrula ((Json (Join-Path $paket 'projeler.json')).projeler.Count -eq 0 -and (Projeleri-Yukle).projeler.Count -eq 1) 'Yeni proje yazımı kişisel dosyaya yönleniyor'
    $jsonFonksiyon = $panelAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Json-Oku' }, $true)
    Invoke-Expression $jsonFonksiyon.Extent.Text
    Dogrula ((Json-Oku (Join-Path $paket 'ayarlar.json')).roller.lider[0].arac -eq 'gemini') 'Panel de yerel yapılandırmayı okuyor'
    # Boş döngü başka kurulumun global mutex/kalp atışına dokunmasın.
    # Şirket binası: döngü kilidinin adı ortak.ps1 > Kat-Dongu-Kilidi'de (katlar için ek alır); ikisinde de değiştir
    $testKilidi = 'Local\AIEkipTest' + [guid]::NewGuid().ToString('N')
    foreach ($bd in @('baslat.ps1', 'ortak.ps1')) {
        $bdYol = Join-Path $paket $bd
        $metin = [IO.File]::ReadAllText($bdYol).Replace('Local\AIEkipDongusu', $testKilidi)
        [IO.File]::WriteAllText($bdYol, $metin, (New-Object Text.UTF8Encoding $true))
    }
    $baslat = Join-Path $paket 'baslat.ps1'
    $yerel.dongu.calisma_saatleri = '00:00-24:00'; $yerel.bildirim.masaustu = $false; $yerel.bildirim.telefon.ntfy_konu = ''
    Kurulum-Json-Yaz $yerel 'ayarlar'
    $cikti = AltSurec $baslat @('-Konsol','-BosBitir')
    Dogrula ($cikti -match 'Hazır görev kalmadı') 'baslat.ps1 -Konsol -BosBitir boş kuyrukta hatasız çıktı'
    $cikti = AltSurec (Join-Path $paket 'gorev-ekle.ps1') @('-Proje','test','-Baslik','Paket testi','-Aciklama','Çevrimdışı görev oluşturma')
    Dogrula ($cikti -match 'Görev eklendi') 'gorev-ekle.ps1 test görevi oluşturdu'
    $cikti = AltSurec (Join-Path $paket 'durum.ps1')
    Dogrula ($cikti -match '0001-paket-testi' -and (Test-Path -LiteralPath (Join-Path $paket 'raporlar\son-rapor.html'))) 'durum.ps1 görevi ve HTML raporu gösterdi'
    # .gitignore kurallarını geçici depoda sına; kaynak klasörün git deposu olması gerekmez.
    $ignoreDepo = Join-Path $calisma 'ignore-deposu'
    New-Item -ItemType Directory -Path $ignoreDepo -Force | Out-Null
    & git init -q -- $ignoreDepo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Geçici depo oluşturulamadı (git init).' }
    Copy-Item -LiteralPath (Join-Path $kaynak '.gitignore') -Destination $ignoreDepo
    $izin = @('durum/a.json','gunluk/a.log','raporlar/a.html','calisma/a','gorevler/0001/gorev.md','ayarlar.yerel.json','kadro.yerel.json','projeler.yerel.json','ayarlar.yerel.json.bak','eposta.json','BAGLANTI-BILGILERI.md','ofis/uzak.json','ofis/sunucu.json','danisman/notlar/a.md','sirket/yazismalar/a.json','katlar/data-analytics/durum/a.json','katlar/innovation-lab/gorevler/0001/durum.json','katlar/data-analytics/ayarlar.yerel.json','katlar/data-analytics/DURDUR','katlar/creative-studio/.env','katlar/creative-studio/backend/.venv/a.py')
    foreach ($yol in $izin) {
        $null = & git -C $ignoreDepo check-ignore --quiet -- $yol
        Dogrula ($LASTEXITCODE -eq 0) "$yol Git dışında"
    }
    [IO.File]::WriteAllText((Join-Path $paket 'ozel-not.md'), 'Kullanıcı dosyası; arşive alınmamalı.')
    $null = AltSurec (Join-Path $paket 'paketle.ps1')
    $null = AltSurec (Join-Path $paket 'paketle.ps1')
    Dogrula (Test-Path -LiteralPath (Join-Path $paket 'dagitim\ai-ofis.zip')) 'ZIP üretimi ve mevcut ZIP güncellemesi'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arsiv = [IO.Compression.ZipFile]::OpenRead((Join-Path $paket 'dagitim\ai-ofis.zip'))
    try {
        $adlar = @($arsiv.Entries | ForEach-Object { $_.FullName })
        Dogrula ($adlar.Count -eq 233) 'ZIP 233 dağıtım dosyası içeriyor (danışman masası, şirket binasının katları ve kendi kendini geliştirme dahil)'
        Dogrula (@($adlar | Where-Object { $_ -in @('kendini.ps1', 'istemler/ofis-gelistirme.md', 'testler/ofis-duman.test.ps1', 'testler/kendini-gelistirme.test.ps1') }).Count -eq 4) 'ZIP kendi kendini geliştirmeyi içeriyor (ayna, canlıya alma, rehber, testler)'
        Dogrula (@($adlar | Where-Object { $_ -in @('katlar.json', 'katlar/data-analytics/kadro.json', 'katlar/innovation-lab/kadro.json', 'katlar/creative-studio/backend/app/main.py', 'katlar/creative-studio/.env.example', 'ofis/bina.html', 'iletisim.ps1') }).Count -eq 7) 'ZIP şirket binasını içeriyor (katlar, bina paneli, Comms, Creative Studio kaynağı)'
        Dogrula (@($adlar | Where-Object { $_ -match '^katlar/.*(\.yerel\.|/DURDUR$|/\.env$|/durum/|/gorevler/|node_modules|\.venv)' }).Count -eq 0) 'ZIP katların kişisel / çalışma dosyalarını dışlıyor'
        Dogrula (@($adlar | Where-Object { $_ -in @('danisman/CLAUDE.md', 'danisman/AGENTS.md', 'danisman/GEMINI.md') }).Count -eq 3) 'ZIP danışman masasını (CLAUDE.md, AGENTS.md, GEMINI.md) içeriyor'
        Dogrula (@($adlar | Where-Object { $_ -match '\.yerel\.|ozel-not|^durum/|^gorevler/|^raporlar/' }).Count -eq 0) 'ZIP kişisel ayarları ve ek kullanıcı dosyalarını dışlıyor'
    } finally { $arsiv.Dispose() }
    Write-Host "TAMAM: $script:kontrol kontrol geçti. Gerçek ağ/VM/masaüstü/zamanlanmış görev işlemi yapılmadı."
} finally {
    # Yalnızca bu testin, çalışma klasörü içindeki kesin hedefini temizle.
    $sinir = [IO.Path]::GetFullPath($testKok).TrimEnd('\') + '\'
    $kesin = [IO.Path]::GetFullPath($calisma)
    if (-not $kesin.StartsWith($sinir, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test temizleme yolu güvenli değil.' }
    if (Test-Path -LiteralPath $kesin) { Remove-Item -LiteralPath $kesin -Recurse -Force }
}
