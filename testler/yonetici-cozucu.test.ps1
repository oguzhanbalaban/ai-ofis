<#
yonetici-cozucu.test.ps1 - Engineering Manager yönlendirmesini, Incident Managerʼı ve token / bağlam kaydını sınar. Çevrimdışıdır: gerçek Claude / Codex çağrılmaz, gerçek gorevler\
klasörüne, bildirimlere ve e-postaya dokunulmaz. Betikler geçici bir kum havuzuna kopyalanır; claude.exe yerine her
senaryoda verilen yanıtı stream-json biçiminde basan sahte bir ajan (.cmd) kullanılır.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\yonetici-cozucu.test.ps1 [-Kaynak <betik klasörü>] [-Koru]

  K   token / bağlam kaydı (Claude stream-json, Codex oturum dosyası)
  Y   "İş ver" -> Engineering Manager yönlendirmesi (UZMAN, YAZILIM + yeni depo, YAZILIM + kayıtlı proje, ALTYAPI, SORU_VAR -> yanıt -> yeniden)
  S   Incident Manager (bildirim bastırma, YONLENDIR + yardım işi + otomatik sürdürme, YENIDEN_DENE, KULLANICI, sınır, zincir yok,
      kullanıcının Devam'ı hakkı sıfırlar, doğrulama komutu güvenlik süzgeci)
Çıkış kodu: kalan denetim sayısı (0 = hepsi geçti).
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-yonetici-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"

# ---------------------------------------------------------------- kum havuzu
Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
$ayar = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$sahteAjan = Join-Path $kum 'sahte-ajan.cmd'
$ayar.claude.exe = $sahteAjan
$ayar.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayar.zaman_asimi_dk.claude = 5
$ayar.gunluk_sinir.claude = 1000
$sahte = { param($m) [pscustomobject]@{ arac = 'claude'; model = $m } }
$ayar.roller = [pscustomobject]@{ lider = @(& $sahte 'sahte-yonetici'); 'sorun-giderici' = @(& $sahte 'sahte-cozucu'); sistem = @(& $sahte 'sahte-sistem'); ag = @(& $sahte 'sahte-ag') }
$ayar.bildirim.masaustu = $false
$ayar.bildirim.telefon = $null
$ayar.altyapi.makineler = @([pscustomobject]@{ ad = 'LAB-SRV'; ip = ''; isletim = 'test'; vmx = ''; yonetim = ''; aciklama = 'test makinesi' })
$ayar.altyapi.vmrun = ''
$ayar.gorev.yeni_proje_kok = (Join-Path $kum 'projeler')
$ayar.sorun_giderici = [pscustomobject]@{ etkin = $true; gorev_basina_en_fazla = 2; en_eski_saat = 72 }
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayar | ConvertTo-Json -Depth 10), $bom)
$uye = { param($a, $ad, $uz, $yer) [pscustomobject]@{ anahtar = $a; ad = $ad; departman = 'Test'; yerlesik = $yer; uzman_isi = (-not $yer); yetki = 'yaz'; uzmanlik = "$ad işleri" } }
$kadro = [pscustomobject]@{ surum = 1; uyeler = @(
    (& $uye 'lider' 'Engineering Manager' '' $true), (& $uye 'sorun-giderici' 'Incident Manager' '' $true), (& $uye 'gelistirici' 'Software Developer' '' $true),
    (& $uye 'sistem' 'System Administrator' '' $true), (& $uye 'ag' 'Network Engineer' '' $true), (& $uye 'tasarimci-ui' 'UI/UX Designer' '' $false)) }
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), ($kadro | ConvertTo-Json -Depth 6), $bom)
# Kayıtlı test projesi (git deposu)
$mevcutProje = Join-Path $kum 'mevcut-proje'
New-Item -ItemType Directory -Force $mevcutProje | Out-Null
& git -C $mevcutProje init -q -b main 2>$null
[IO.File]::WriteAllText((Join-Path $mevcutProje 'a.txt'), 'a', $ascii)
& git -C $mevcutProje add -A 2>$null
& git -C $mevcutProje -c user.name=t -c user.email=t@t commit -q -m ilk 2>$null
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), ((@{ projeler = @(@{ ad = 'mevcut-proje'; klasor = $mevcutProje; temel_dal = ''; dogrulama = @() }) }) | ConvertTo-Json -Depth 5), $bom)
# Sahte ajan: çağrıyı kaydeder, sahte-cikti.txt'yi (stream-json) basar
[IO.File]::WriteAllText($sahteAjan, (@('@echo off', '>> "%~dp0cagrilar.log" echo %*', 'type "%~dp0sahte-cikti.txt"') -join "`r`n") + "`r`n", $ascii)
function Sahte-Yanit([string]$Metin) {
    $u1 = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 50; cache_creation_input_tokens = 50; output_tokens = 10 }
    $u2 = [ordered]@{ input_tokens = 5; cache_read_input_tokens = 150; cache_creation_input_tokens = 0; output_tokens = 10 }
    $satirlar = @(
        ([ordered]@{ type = 'system'; subtype = 'init'; model = 'sahte' } | ConvertTo-Json -Compress),
        ([ordered]@{ type = 'assistant'; message = [ordered]@{ id = 'msg_1'; usage = $u1 } } | ConvertTo-Json -Compress -Depth 5),
        ([ordered]@{ type = 'assistant'; message = [ordered]@{ id = 'msg_1'; usage = $u1 } } | ConvertTo-Json -Compress -Depth 5),
        ([ordered]@{ type = 'user'; message = [ordered]@{ content = 'büyük araç sonucu' } } | ConvertTo-Json -Compress -Depth 5),
        ([ordered]@{ type = 'assistant'; message = [ordered]@{ id = 'msg_2'; usage = $u2 } } | ConvertTo-Json -Compress -Depth 5),
        ([ordered]@{ type = 'result'; subtype = 'success'; is_error = $false; num_turns = 2; result = $Metin; total_cost_usd = 0.0123
            usage = [ordered]@{ input_tokens = 10; cache_read_input_tokens = 200; cache_creation_input_tokens = 50; output_tokens = 20 }
            modelUsage = [ordered]@{ sahte = [ordered]@{ contextWindow = 200000 } } } | ConvertTo-Json -Compress -Depth 6)
    )
    [IO.File]::WriteAllText((Join-Path $kum 'sahte-cikti.txt'), ($satirlar -join "`n") + "`n", $utf8)
}
Sahte-Yanit 'KARAR: YOK'

. (Join-Path $kum 'ortak.ps1')
. (Join-Path $kum 'rapor.ps1')
. (Join-Path $kum 'ekip.ps1')
if ($Kok -ne $kum) { throw "Betikler kum havuzunu değil $Kok klasörünü kullanıyor; test durduruldu" }
Ayarlari-Yukle

# ---------------------------------------------------------------- yardımcılar
$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Test-Gorevi([string]$Id, [string]$Asama, [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# Test $Id`n`nSahte görev."
    $d = [ordered]@{ id = $Id; baslik = "Test $Id"; proje = 'mevcut-proje'; klasor = $mevcutProje; oncelik = 2; asama = $Asama; tur = 1; max_tur = 3
        deneme = 0; dogrulama = @(); olusturma = (Simdi); guncelleme = (Simdi); gecmis = @() }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Bildirimler { $f = Join-Path $YolDurum 'bildirimler.jsonl'; if (-not (Test-Path $f)) { return @() }; return @(Get-Content $f -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
function Son-Kullanim { $f = Get-ChildItem (Join-Path $YolDurum 'kullanim') -Filter '*.jsonl' | Select-Object -First 1; return ((Get-Content $f.FullName -Encoding UTF8 | Where-Object { $_ } | Select-Object -Last 1) | ConvertFrom-Json) }
function Is-Ver([string[]]$Arg) {
    $o = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kum 'is-ver.ps1') @Arg 2>&1 | Out-String
    $m = [regex]::Match($o, 'İş eklendi: (\S+)')
    if (-not $m.Success) { throw "is-ver.ps1 başarısız: $o" }
    return (Gorev-Oku $m.Groups[1].Value)
}

try {
    # ------------------------------------------------------------ K: kullanım kaydı
    Write-Host ''; Write-Host 'K1: Claude stream-json çıktısından token ve bağlam kaydı'
    $script:AktifGorev = '9100-kullanim'
    Sahte-Yanit "KARAR: TAMAM`n`nyanıt"
    $r = Ajan-Cagir -Rol 'lider' -Istem 'merhaba' -Klasor $kum -KayitKlasoru (Join-Path $kum 'kayit-k1') -Etiket 'plan'
    $script:AktifGorev = ''
    $k = Son-Kullanim
    Dogrula 'çağrı başarılı ve sonuç metni okundu' ($r.basarili -and $r.metin -match 'KARAR: TAMAM')
    Dogrula 'kayıt: rol, görev, araç' ($k.rol -eq 'lider' -and $k.gorev -eq '9100-kullanim' -and $k.arac -eq 'claude' -and $k.model -eq 'sahte-yonetici') "$($k.rol) $($k.gorev) $($k.arac)/$($k.model)"
    Dogrula 'kayıt: giriş/önbellek/çıkış/toplam' ($k.giris -eq 10 -and $k.onbellek_okuma -eq 200 -and $k.onbellek_yazma -eq 50 -and $k.cikis -eq 20 -and $k.toplam -eq 280) "$($k.giris)/$($k.onbellek_okuma)/$($k.onbellek_yazma)/$($k.cikis)=$($k.toplam)"
    Dogrula 'kayıt: en büyük bağlam (165) ve pencere (200000), tekrarlanan yanıt bir kez sayıldı' ($k.baglam_tepe -eq 165 -and $k.baglam_pencere -eq 200000 -and $k.istek -eq 2) "tepe=$($k.baglam_tepe) pencere=$($k.baglam_pencere) istek=$($k.istek)"
    Dogrula 'kayıt: maliyet ve ölçüm türü' ([double]$k.maliyet_usd -eq 0.0123 -and $k.olcum -eq 'tam')

    Write-Host ''; Write-Host 'K2: Codex oturum dosyasından token, bağlam ve hak yüzdesi'
    $eskiCodexHome = $env:CODEX_HOME
    $env:CODEX_HOME = Join-Path $kum 'codex-ev'
    $sid = '01a1e955-ad79-7cf1-84a0-4ff5451c83d6'
    $gunKl = Join-Path $env:CODEX_HOME ('sessions\{0:yyyy}\{0:MM}\{0:dd}' -f (Get-Date))
    New-Item -ItemType Directory -Force $gunKl | Out-Null
    $tc = { param($ti, $tc2, $to, $li, $lo) ([ordered]@{ type = 'event_msg'; payload = [ordered]@{ type = 'token_count'
        info = [ordered]@{ total_token_usage = [ordered]@{ input_tokens = $ti; cached_input_tokens = $tc2; output_tokens = $to; total_tokens = $ti + $to }
            last_token_usage = [ordered]@{ input_tokens = $li; output_tokens = $lo; total_tokens = $li + $lo }; model_context_window = 258400 }
        rate_limits = [ordered]@{ primary = [ordered]@{ used_percent = 23.0; window_minutes = 300; resets_at = 1794931948 }; secondary = [ordered]@{ used_percent = 4.0; window_minutes = 10080; resets_at = 1795518748 }; plan_type = 'plus' } } } | ConvertTo-Json -Compress -Depth 8) }
    $rollout = @('{"type":"session_meta"}', '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}', (& $tc 1000 600 50 1000 50), (& $tc 3000 2000 120 2000 70))
    [IO.File]::WriteAllText((Join-Path $gunKl "rollout-2026-11-17T14-47-48-$sid.jsonl"), ($rollout -join "`n"), $utf8)
    $errDosya = Join-Path $kum 'codex.err.txt'
    [IO.File]::WriteAllText($errDosya, "OpenAI Codex v0`n--------`nworkdir: x`nmodel: gpt`nsession id: $sid`n--------`nuser`nmerhaba`ntokens used`n3,120`n", $utf8)
    $ck = Codex-Kullanim $errDosya
    Dogrula 'Codex: giriş (önbelleksiz) / önbellek / çıkış' ($ck.giris -eq 1000 -and $ck.onbellek_okuma -eq 2000 -and $ck.cikis -eq 120) "$($ck.giris)/$($ck.onbellek_okuma)/$($ck.cikis)"
    Dogrula 'Codex: en büyük bağlam 2070 / 258400, 2 istek' ($ck.baglam_tepe -eq 2070 -and $ck.baglam_pencere -eq 258400 -and $ck.istek -eq 2) "tepe=$($ck.baglam_tepe) istek=$($ck.istek)"
    $hk = Json-Oku (Join-Path $YolDurum 'arac-haklari.json')
    Dogrula 'Codex hak yüzdeleri kaydedildi (5 saat %23, haftalık %4)' ($hk.codex.bes_saat.yuzde -eq 23 -and $hk.codex.haftalik.yuzde -eq 4)
    Remove-Item -Recurse -Force (Join-Path $env:CODEX_HOME 'sessions')
    $ck2 = Codex-Kullanim $errDosya
    Dogrula 'oturum dosyası yoksa "tokens used" toplamı okunur' ($ck2 -and $ck2.toplam -eq 3120 -and $ck2.olcum -eq 'toplam') "toplam=$($ck2.toplam)"
    $env:CODEX_HOME = $eskiCodexHome

    # ------------------------------------------------------------ Y: Engineering Manager yönlendirmesi
    Write-Host ''; Write-Host 'Y1: İş ver -> Engineering Manager UZMAN der'
    $g = Is-Ver @('-Baslik', 'Giriş ekranı tasarımı', '-Aciklama', 'Mobil uygulama için giriş ekranı', '-Rol', 'tasarimci-ui', '-Ipucu', 'mevcut-proje')
    Dogrula 'is-ver.ps1 türü genel, aşaması yeni olan görev açtı' ($g.tip -eq 'genel' -and $g.asama -eq 'yeni' -and $g.istenen_rol -eq 'tasarimci-ui') "$($g.tip) $($g.asama)"
    Dogrula 'gorev.md ipuçlarını içeriyor' ((Gorev-Metni $g) -match 'Önerilen çalışan' -and (Gorev-Metni $g) -match 'mevcut-proje')
    Sahte-Yanit "KARAR: UZMAN`nSORUMLU: tasarimci-ui`nPROJE: mevcut-proje`n`n## Gerekçe`nBu bir arayüz tasarımı işi."
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'uzman akışına geçti, sorumlu tasarimci-ui, ilgili klasör proje' ($d.tip -eq 'uzman' -and $d.hedef_rol -eq 'tasarimci-ui' -and $d.asama -eq 'yeni' -and $d.kaynak_klasor -eq $mevcutProje) "$($d.tip) $($d.hedef_rol) $($d.asama) $($d.kaynak_klasor)"
    Dogrula 'yonlendirme.md yazıldı, gorev.md''ye Engineering Managerʼın notu eklendi' ((Test-Path (Join-Path (Gorev-Klasoru $g.id) 'yonlendirme.md')) -and (Gorev-Metni $d) -match 'Engineering Managerʼın yönlendirmesi')
    Dogrula 'geçmiş: "Engineering Manager uzmana verdi"' (@($d.gecmis | Where-Object { $_.olay -eq 'Engineering Manager uzmana verdi' }).Count -eq 1)
    Dogrula 'kullanım kaydında etiket yonlendirme' ((Son-Kullanim).etiket -eq 'yonlendirme')

    Write-Host ''; Write-Host 'Y2: Engineering Manager YAZILIM + YENI_PROJE der (boş git deposu açılır)'
    $g = Is-Ver @('-Baslik', 'Kelime oyunu', '-Aciklama', 'Yeni bir oyun yaz')
    Sahte-Yanit "KARAR: YAZILIM`nYENI_PROJE: Kelime Oyunu`n`n## Gerekçe`nYeni bir depo gerekiyor."
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    $yeniKl = Join-Path (Join-Path $kum 'projeler') 'kelime-oyunu'
    Dogrula 'yazılım akışına geçti, proje kelime-oyunu' ($d.tip -eq 'yazilim' -and $d.proje -eq 'kelime-oyunu' -and $d.klasor -eq $yeniKl -and $d.asama -eq 'yeni') "$($d.tip) $($d.proje) $($d.klasor)"
    $log = & git -C $yeniKl log --oneline 2>$null
    Dogrula 'yeni depo git deposu ve ilk commit var' (@($log).Count -eq 1) ($log -join ' ')
    Dogrula 'projeler.json''a kaydedildi' ((Proje-Bul 'kelime-oyunu') -ne $null)

    Write-Host ''; Write-Host 'Y3: Engineering Manager YAZILIM + kayıtlı proje der'
    $g = Is-Ver @('-Baslik', 'Hata düzelt', '-Aciklama', 'a.txt içindeki hatayı düzelt')
    Sahte-Yanit "KARAR: YAZILIM`nPROJE: ``mevcut-proje```n`n## Gerekçe`nKod işi."
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'kayıtlı projeye bağlandı' ($d.tip -eq 'yazilim' -and $d.klasor -eq $mevcutProje) "$($d.proje) $($d.klasor)"

    Write-Host ''; Write-Host 'Y4: Engineering Manager ALTYAPI der (bilinmeyen makine adı süzülür)'
    $g = Is-Ver @('-Baslik', 'Servis kontrolü', '-Aciklama', 'LAB-SRV servislerine bak')
    Sahte-Yanit "KARAR: ALTYAPI`nHEDEF: LAB-SRV, YOK-BOYLE`n`n## Gerekçe`nSunucu işi."
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'altyapı talebine dönüştü, hedef yalnızca LAB-SRV' ($d.tip -eq 'altyapi' -and (@($d.hedef) -join ',') -eq 'LAB-SRV' -and $d.proje -eq 'altyapı') "$($d.tip) $(@($d.hedef) -join ',')"

    Write-Host ''; Write-Host 'Y5: Engineering Manager SORU_VAR der, kullanıcı yanıtlayınca yeniden yönlendirir; geçersiz karar yeniden denenir'
    $g = Is-Ver @('-Baslik', 'Belirsiz iş', '-Aciklama', 'şunu yap')
    Sahte-Yanit "KARAR: SORU_VAR`n`n## Sorular`n1. Ne yapılacak?"
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'soru: bekliyor_kullanici, sorular.md' ($d.asama -eq 'bekliyor_kullanici' -and (Test-Path (Join-Path (Gorev-Klasoru $g.id) 'sorular.md')))
    Dogrula 'bildirim başlığı "Engineering Manager soru soruyor"' (@(Bildirimler | Where-Object { $_.baslik -like 'Engineering Manager soru soruyor*' }).Count -ge 1)
    Start-Sleep -Milliseconds 1100
    $f = Join-Path (Gorev-Klasoru $g.id) 'gorev.md'; Metin-Yaz $f ((Metin-Oku $f) + "`n### Yanıt`nArayüz tasarla.")
    Bekleyenleri-Kontrol
    $d = Gorev-Oku $g.id
    Dogrula 'yanıttan sonra aşama plan (yeniden yönlendirme)' ($d.asama -eq 'plan')
    Sahte-Yanit "Bilmiyorum."
    Gorev-Ilerlet $d
    $d = Gorev-Oku $g.id
    Dogrula 'KARAR satırı yoksa adım başarısız sayılır (deneme 1, tür genel kalır)' ([int]$d.deneme -eq 1 -and $d.tip -eq 'genel') "deneme=$($d.deneme)"
    Ayarla $d 'sonraki_deneme' $null; Gorev-Kaydet $d
    Sahte-Yanit "KARAR: UZMAN`nSORUMLU: tasarimci-ui`n`n## Gerekçe`nArayüz."
    Gorev-Ilerlet (Gorev-Oku $g.id)
    $d = Gorev-Oku $g.id
    Dogrula 'yeniden denemede uzmana yönlendi' ($d.tip -eq 'uzman' -and $d.hedef_rol -eq 'tasarimci-ui')

    # ------------------------------------------------------------ S: Incident Manager
    Write-Host ''; Write-Host 'S1: Takildi, Incident Manager üstlenecekse telefona bildirim göndermez'
    $once = @(Bildirimler).Count
    $g = Test-Gorevi '9201-takilan-yazilim' 'denetim'
    $tk = Tur-Klasoru $g
    Metin-Yaz (Join-Path $tk 'denetim.md') "KARAR: DUZELT`nflutter analyze çalıştırılamadı."
    $g.tur = 3
    Yeni-Tur $g '## Code Reviewer düzeltme istedi' 'Code Reviewer düzeltme istedi'
    Gorev-Kaydet $g
    $d = Gorev-Oku $g.id
    Dogrula 'tur sınırında takıldı, bekleyen geri bildirim var, takılma zamanı yazıldı' ($d.asama -eq 'takildi' -and (Test-Path (Join-Path (Gorev-Klasoru $g.id) 'bekleyen-geri-bildirim.md')) -and $d.takildi_zamani)
    Dogrula '"Görev takıldı" bildirimi gönderilmedi' (@(Bildirimler | Where-Object { $_.baslik -like 'Görev takıldı*' }).Count -eq 0)

    Write-Host ''; Write-Host 'S2: YONLENDIR -> System Administratorʼa yardım işi, güvenli doğrulama komutu eklenir, tehlikeli olan eklenmez'
    $sec = Cozulecek-Gorev
    Dogrula 'Cozulecek-Gorev takılan işi seçti' ($sec -and $sec.id -eq '9201-takilan-yazilim') "$($sec.id)"
    Sahte-Yanit "KARAR: YONLENDIR`nHEDEF: sistem`nBASLIK: Flutter SDK kurulumu`nDOGRULAMA_EKLE: cd app && flutter analyze`nDOGRULAMA_EKLE: del /q *`n`n## Teşhis`nFlutter kurulu değil; Code Reviewer analiz sonucu istiyor.`n`n## Talep`nFlutter SDK'yı kur ve PATH'e ekle.`n`n## Kabul`n- flutter --version çalışır"
    Sorun-Gider $sec
    $d = Gorev-Oku '9201-takilan-yazilim'
    $yid = [string]$d.yardim_gorevi
    $y = $null; if ($yid) { $y = Gorev-Oku $yid }
    Dogrula 'ana iş takılı, yardım bekleniyor' ($d.asama -eq 'takildi' -and $d.cozum_durumu -eq 'yardim_bekleniyor' -and $yid) "$($d.cozum_durumu) $yid"
    Dogrula 'yardım işi: altyapı talebi, öncelik 1, ana_gorev bağlı, başlık' ($y -and $y.tip -eq 'altyapi' -and [int]$y.oncelik -eq 1 -and $y.ana_gorev -eq '9201-takilan-yazilim' -and $y.baslik -eq 'Flutter SDK kurulumu') "$($y.tip) $($y.baslik)"
    Dogrula 'yardım işinin gorev.md''sinde talep ve teşhis var' ((Gorev-Metni $y) -match 'Flutter SDK''yı kur' -and (Gorev-Metni $y) -match 'Flutter kurulu değil')
    Dogrula 'güvenli doğrulama komutu eklendi, tehlikeli komut eklenmedi' ((@($d.dogrulama) -contains 'cd app && flutter analyze') -and -not (@($d.dogrulama) -contains 'del /q *')) (@($d.dogrulama) -join ' | ')
    Dogrula 'cozum-1.md yazıldı ve reddedilen komutu not ediyor' ((Metin-Oku (Join-Path (Gorev-Klasoru $d.id) 'cozum-1.md')) -match 'eklenmedi: del /q')
    Dogrula 'bildirim: "Incident Manager devrede"' (@(Bildirimler | Where-Object { $_.baslik -like 'Incident Manager devrede*' }).Count -eq 1)
    Dogrula 'yardım beklenirken yeniden incelenmez' ((Cozulecek-Gorev) -eq $null)
    Dogrula 'kullanım kaydı: rol sorun-giderici, etiket cozum' ((Son-Kullanim).rol -eq 'sorun-giderici' -and (Son-Kullanim).etiket -eq 'cozum')

    Write-Host ''; Write-Host 'S3: yardım işi bitince takılan iş kendiliğinden sürer (bir tur hakkı daha, yardım sonucu geri bildirimde)'
    Yardim-Gorevleri-Kontrol
    Dogrula 'yardım işi bitmeden ana iş sürmez' ((Gorev-Oku '9201-takilan-yazilim').asama -eq 'takildi')
    $y = Gorev-Oku $yid
    $y.asama = 'tamam'; Ayarla $y 'ozet' 'Flutter 3.38 kuruldu, PATH güncellendi.'; Gorev-Kaydet $y
    Metin-Yaz (Join-Path (Gorev-Klasoru $yid) 'sonuc.md') "# Sonuç`n`nflutter --version: 3.38"
    Yardim-Gorevleri-Kontrol
    $d = Gorev-Oku '9201-takilan-yazilim'
    $gb = Metin-Oku (Join-Path (Join-Path (Gorev-Klasoru $d.id) 'tur4') 'geri-bildirim.md')
    Dogrula 'ana iş geliştirmeye döndü, tur 4/4' ($d.asama -eq 'gelistirme' -and [int]$d.tur -eq 4 -and [int]$d.max_tur -eq 4) "$($d.asama) $($d.tur)/$($d.max_tur)"
    Dogrula 'geri bildirimde yardım sonucu ve eski denetim notu var' ($gb -match 'Yardım işi tamamlandı' -and $gb -match 'Flutter 3.38' -and $gb -match 'Code Reviewer düzeltme istedi')
    Dogrula 'cozum_durumu yardim_tamam, bekleyen geri bildirim silindi' ($d.cozum_durumu -eq 'yardim_tamam' -and -not (Test-Path (Join-Path (Gorev-Klasoru $d.id) 'bekleyen-geri-bildirim.md')))

    Write-Host ''; Write-Host 'S4: YENIDEN_DENE + BEKLE_DK (araç sınırı) -> takıldığı aşamadan, ertelenmiş'
    $g = Test-Gorevi '9202-arac-siniri' 'denetim' @{ tip = 'uzman'; sorumlu = 'tasarimci-ui'; inceleyen = 'sistem' }
    Takildi $g "'Denetleniyor' aşaması 4 denemede tamamlanamadı: claude/sonnet: günlük sınır doldu (40/40)"; Gorev-Kaydet $g
    Sahte-Yanit "KARAR: YENIDEN_DENE`nBEKLE_DK: 45`n`n## Teşhis`nClaude günlük sınırı doldu; geçici.`n`n## Not`nSınır sıfırlanınca yeniden incele."
    Sorun-Gider (Cozulecek-Gorev)
    $d = Gorev-Oku '9202-arac-siniri'
    $dk = 0; if ($d.sonraki_deneme) { $dk = ([datetime]$d.sonraki_deneme - (Get-Date)).TotalMinutes }
    Dogrula 'aşama denetim, ~45 dk sonra' ($d.asama -eq 'denetim' -and $dk -gt 40 -and $dk -le 46) ("{0} {1:N0} dk" -f $d.asama, $dk)
    Dogrula 'geri bildirime Incident Managerʼın notu yazıldı' ((Metin-Oku (Join-Path (Tur-Klasoru $d) 'geri-bildirim.md')) -match 'Incident Managerʼın notu')
    Dogrula 'geçmiş: "Incident Manager devam ettirdi", hak 1/2' (@($d.gecmis | Where-Object { $_.olay -eq 'Incident Manager devam ettirdi' }).Count -eq 1 -and [int]$d.cozum_sayisi -eq 1)

    Write-Host ''; Write-Host 'S5: aynı iş yine takılınca ikinci kez incelenir; KULLANICI -> yüksek önemli bildirim, iş takılı kalır'
    $d.asama = 'denetim'; Takildi $d 'yine sınır'; Gorev-Kaydet $d
    Dogrula 'ikinci takılmada da bildirim bastırıldı (hak 1/2)' (@(Bildirimler | Where-Object { $_.baslik -like 'Görev takıldı*' }).Count -eq 0)
    Sahte-Yanit "KARAR: KULLANICI`n`n## Teşhis`nSınır kullanıcı kararı.`n`n## Kullanıcıya`nayarlar.json > gunluk_sinir.claude değerini artır."
    Sorun-Gider (Cozulecek-Gorev)
    $d = Gorev-Oku '9202-arac-siniri'
    Dogrula 'iş takılı, cozum_durumu kullanici' ($d.asama -eq 'takildi' -and $d.cozum_durumu -eq 'kullanici' -and [int]$d.cozum_sayisi -eq 2)
    $bk = @(Bildirimler | Where-Object { $_.baslik -like 'Takılan iş seni bekliyor*' })
    Dogrula 'bildirim kullanıcıya ne yapacağını söylüyor (yüksek önem)' ($bk.Count -eq 1 -and $bk[0].metin -match 'gunluk_sinir' -and $bk[0].onem -eq 'yuksek')
    Dogrula 'karar verilen takılma yeniden incelenmez' ((Cozulecek-Gorev) -eq $null)

    Write-Host ''; Write-Host 'S6: hak bitince Incident Manager üstlenmez, bildirim eskisi gibi gider; kullanıcının Devam''ı hakkı sıfırlar'
    $d.asama = 'denetim'; Takildi $d 'üçüncü kez'; Gorev-Kaydet $d
    Dogrula '"Görev takıldı" bildirimi gitti' (@(Bildirimler | Where-Object { $_.baslik -like 'Görev takıldı*' }).Count -eq 1)
    Dogrula 'Cozulecek-Gorev seçmiyor' ((Cozulecek-Gorev) -eq $null)
    $o = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kum 'durum.ps1') -Devam '9202' -Not 'sınırı artırdım' 2>&1 | Out-String
    $d = Gorev-Oku '9202-arac-siniri'
    Dogrula 'durum.ps1 -Devam: aşama denetim, hak sıfırlandı, not geri bildirimde' ($d.asama -eq 'denetim' -and [int]$d.cozum_sayisi -eq 0 -and (Metin-Oku (Join-Path (Tur-Klasoru $d) 'geri-bildirim.md')) -match 'Kullanıcının notu') "$($d.asama) hak=$($d.cozum_sayisi)"

    Write-Host ''; Write-Host 'S7: yardım işinin kendisi takılırsa yeni yardım işi açılmaz (zincir yok)'
    $sayi = @(Get-ChildItem $YolGorev -Directory).Count
    $g = Test-Gorevi '9203-yardim-isi' 'gelistirme' @{ tip = 'altyapi'; ana_gorev = '9201-takilan-yazilim' }
    Takildi $g 'kurulum başarısız'; Gorev-Kaydet $g
    Sahte-Yanit "KARAR: YONLENDIR`nHEDEF: ag`n`n## Teşhis`nPort kapalı.`n`n## Talep`nPortu aç."
    Sorun-Gider (Gorev-Oku '9203-yardim-isi')
    $d = Gorev-Oku '9203-yardim-isi'
    Dogrula 'yeni görev açılmadı, kullanıcıya bırakıldı' (@(Get-ChildItem $YolGorev -Directory).Count -eq ($sayi + 1) -and $d.cozum_durumu -eq 'kullanici') "$($d.cozum_durumu)"

    Write-Host ''; Write-Host 'S8: Incident Manager çalışırken kullanıcı işi sürdürürse karar uygulanmaz'
    $g = Test-Gorevi '9204-yaris' 'denetim'
    Takildi $g 'x'; Gorev-Kaydet $g
    # Ajan "çalışırken" kullanıcı Devam der: sahte ajan çıktısını basmadan önce durum.json'u değiştir
    [IO.File]::WriteAllText($sahteAjan, (@('@echo off', '>> "%~dp0cagrilar.log" echo %*', ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Devam 9204 >nul 2>&1' -f "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe", (Join-Path $kum 'durum.ps1')), 'type "%~dp0sahte-cikti.txt"') -join "`r`n") + "`r`n", $ascii)
    Sahte-Yanit "KARAR: KULLANICI`n`n## Teşhis`nx`n`n## Kullanıcıya`ny"
    Sorun-Gider (Gorev-Oku '9204-yaris')
    [IO.File]::WriteAllText($sahteAjan, (@('@echo off', '>> "%~dp0cagrilar.log" echo %*', 'type "%~dp0sahte-cikti.txt"') -join "`r`n") + "`r`n", $ascii)
    $d = Gorev-Oku '9204-yaris'
    Dogrula 'iş kullanıcının sürdürdüğü aşamada, Incident Manager kararı yazılmadı' ($d.asama -eq 'denetim' -and -not $d.cozum_durumu -and -not (Test-Path (Join-Path (Gorev-Klasoru $d.id) 'cozum-1.md'))) "$($d.asama) $($d.cozum_durumu)"

    Write-Host ''; Write-Host 'S9: doğrulama komutu güvenlik süzgeci'
    foreach ($k in @('flutter analyze', 'cd app && flutter test', 'cd "kelime labirenti" && flutter analyze', 'npm test', 'npm run build', 'python -m pytest -q', 'dotnet test', 'node --test', '.\gradlew.bat test')) {
        Dogrula "kabul: $k" (Dogrulama-Guvenli-mi $k)
    }
    foreach ($k in @('del /q *', 'powershell -c "x"', 'npm install left-pad', 'npx cowsay', 'python -c "import os"', 'node -e "1"', 'python -m pip install x', 'flutter analyze > a.txt',
        'npm test & del x', 'cd .. && npm test', 'cd C:\ && npm test', 'curl http://x', 'flutter test | more', 'cd a && cd b && npm test')) {
        Dogrula "red: $k" (-not (Dogrulama-Guvenli-mi $k))
    }
} catch {
    $script:Kalan++
    Write-Host ("  [HATA] Test çöktü: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
}

Write-Host ''
Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
if ($script:Kalan -eq 0 -and -not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "Kum havuzu korundu: $kum (günlük: $(Join-Path $kum 'gunluk'))" }
exit $script:Kalan
