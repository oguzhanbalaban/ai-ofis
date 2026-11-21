<#
sinir-beklemesi.test.ps1 - Araçların hepsi yalnız sınır yüzünden kapalıyken deneme hakkının yanmadığını sınar. Engineering Manager
zincirindeki her araç günlük sınırda ya da kullanım / kota sınırı kilidindeyse adım başarısız sayılmaz, iş en erken açılışta yeniden
denenir (ortak.ps1 > Sinir-Acilisi, Ajan-Cagir; ekip.ps1 > Adim-Basarisiz). Başka bir neden (giriş kilidi, araç hatası) varsa eski
davranış sürer. Günlük hak sıfırlanınca o aşamada yalnız sınır yüzünden yanan haklar geri verilir (durum.ps1 -KotaSifirla,
Sinir-Denemelerini-Geri-Ver). Çevrimdışıdır: gerçek Claude / Codex çağrılmaz, sahte araçlar çağrıyı kaydedip hata verir.

  powershell -NoProfile -ExecutionPolicy Bypass -File testler\sinir-beklemesi.test.ps1 [-Kaynak <betik klasörü>] [-Koru]
#>
param([string]$Kaynak = '', [switch]$Koru)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Kaynak) { $Kaynak = Split-Path -Parent $PSScriptRoot }
$Kaynak = (Resolve-Path -LiteralPath $Kaynak).Path
$kum = Join-Path $env:TEMP ('ai-ekip-sinir-beklemesi-testi-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $kum | Out-Null
Write-Host "Kaynak     : $Kaynak"
Write-Host "Kum havuzu : $kum"
Remove-Item env:AIEKIP_KAT -ErrorAction SilentlyContinue

Copy-Item -Path (Join-Path $Kaynak '*.ps1') -Destination $kum
Copy-Item -Recurse -LiteralPath (Join-Path $Kaynak 'istemler') -Destination $kum
$bom = New-Object Text.UTF8Encoding $true
$utf8 = New-Object Text.UTF8Encoding $false
$ascii = New-Object Text.ASCIIEncoding
$ayarJ = [IO.File]::ReadAllText((Join-Path $Kaynak 'ayarlar.json'), $bom) | ConvertFrom-Json
$sahteClaude = Join-Path $kum 'sahte-claude.cmd'
$sahteCodex = Join-Path $kum 'sahte-codex.cmd'
$ayarJ.claude.exe = $sahteClaude
$ayarJ.claude.kullanim_dosyasi = (Join-Path $kum 'yok.json')
$ayarJ.gunluk_sinir = [pscustomobject]@{ claude = 100; codex = 100; gemini = 40 }
$ayarJ.zaman_asimi_dk.claude = 2
$ayarJ.zaman_asimi_dk.codex = 2
$ayarJ.dongu.max_adim_denemesi = 4
$ayarJ.dongu.hata_bekleme_dk = 10
# Engineering Manager zinciri: önce Claude, sonra Codex (canlıdaki #0088 durumu)
$ayarJ.roller = [pscustomobject]@{ lider = @([pscustomobject]@{ arac = 'claude'; model = 'sahte-opus' }, [pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }) }
$ayarJ.bildirim.masaustu = $false
$ayarJ.bildirim.telefon = $null
if ($ayarJ.PSObject.Properties['altyapi']) { $ayarJ.altyapi.makineler = @(); $ayarJ.altyapi.vmrun = '' }
$ayarJ | Add-Member -Force -NotePropertyName yonetim -NotePropertyValue ([pscustomobject]@{ etkin = $false })
[IO.File]::WriteAllText((Join-Path $kum 'ayarlar.json'), ($ayarJ | ConvertTo-Json -Depth 10), $bom)
[IO.File]::WriteAllText((Join-Path $kum 'kadro.json'), '{ "surum": 1, "uyeler": [] }', $bom)
[IO.File]::WriteAllText((Join-Path $kum 'projeler.json'), '{ "projeler": [] }', $bom)
# Sahte Claude: çağrıyı kaydeder, hata verir (günlük sınır doluyken hiç çağrılmamalı)
[IO.File]::WriteAllText($sahteClaude, (@('@echo off', '>> "%~dp0claude-cagrilari.log" echo x', 'echo sahte claude hatasi 1>&2', 'exit /b 1') -join "`r`n") + "`r`n", $ascii)
# Sahte Codex: çağrıyı kaydeder, codex-hata.txt'yi stderr'e yazar, kod 1 ile çıkar
[IO.File]::WriteAllText($sahteCodex, (@('@echo off', 'set D=%~dp0', '>> "%D%codex-cagrilari.log" echo x', 'type "%D%codex-hata.txt" 1>&2', 'exit /b 1') -join "`r`n") + "`r`n", $ascii)

. (Join-Path $kum 'ortak.ps1')
. (Join-Path $kum 'rapor.ps1')
. (Join-Path $kum 'ekip.ps1')
if ($Kok -ne $kum) { throw "Betikler kum havuzunu değil $Kok klasörünü kullanıyor; test durduruldu" }
Ayarlari-Yukle
$script:CodexYolu = $sahteCodex

$script:Kalan = 0; $script:Toplam = 0
function Dogrula([string]$Ad, [bool]$Kosul, [string]$Ayrinti = '') {
    $script:Toplam++
    $et = 'GEÇTİ'; if (-not $Kosul) { $et = 'KALDI'; $script:Kalan++ }
    $ek = ''; if ($Ayrinti) { $ek = " ($Ayrinti)" }
    Write-Host ("  [{0}] {1}{2}" -f $et, $Ad, $ek)
}
function Goster($T) { if ($null -eq $T -or '' -eq $T) { return 'null' }; return ([datetime]$T).ToString('dd.MM HH:mm:ss') }
function Dk($A, $B) { if (-not $A -or -not $B) { return 9999 }; return [Math]::Abs(([datetime]$A - [datetime]$B).TotalMinutes) }
function Sayac-Ayarla([int]$Claude, [int]$Codex) {
    Json-Yaz ([pscustomobject]@{ tarih = (Get-Date).ToString('yyyy-MM-dd'); claude = $Claude; codex = $Codex; gemini = 0; tamamlanan = 0; takilan = 0; ozet_gonderilen = @() }) (Join-Path $YolDurum 'sayaclar.json')
}
function Kilitler([hashtable]$K) {
    $o = New-Object psobject
    foreach ($a in $K.Keys) { $o | Add-Member -NotePropertyName $a -NotePropertyValue ([pscustomobject]@{ bitis = ([datetime]$K[$a][0]).ToString('o'); neden = [string]$K[$a][1] }) }
    Json-Yaz $o (Join-Path $YolDurum 'kilitler.json')
}
function Codex-Hata([string]$Metin) { [IO.File]::WriteAllText((Join-Path $kum 'codex-hata.txt'), $Metin + "`r`n", $utf8) }
function Cagri([string]$Ad) { $f = Join-Path $kum "$Ad-cagrilari.log"; if (-not (Test-Path -LiteralPath $f)) { return 0 }; return @(Get-Content -LiteralPath $f | Where-Object { $_.Trim() }).Count }
function Cagrilari-Sil { foreach ($a in 'claude', 'codex') { Remove-Item -LiteralPath (Join-Path $kum "$a-cagrilari.log") -Force -ErrorAction SilentlyContinue } }
function Test-Gorevi([string]$Id, [string]$Asama = 'plan', [hashtable]$Ek = @{}) {
    $gk = Gorev-Klasoru $Id
    New-Item -ItemType Directory -Force $gk | Out-Null
    $wt = Join-Path $YolCalisma $Id
    New-Item -ItemType Directory -Force $wt | Out-Null
    Metin-Yaz (Join-Path $gk 'gorev.md') "# Sınır testi $Id`n`nSahte görev."
    $d = [ordered]@{
        id = $Id; baslik = "Sınır testi $Id"; proje = 'test'; klasor = $wt; oncelik = 1
        asama = $Asama; tur = 1; max_tur = 3; deneme = 0; dogrulama = @(); son_hata = ''; sonraki_deneme = $null
        olusturma = (Simdi); guncelleme = (Simdi); gecmis = @(); calisma_klasoru = $wt
    }
    foreach ($k in $Ek.Keys) { $d[$k] = $Ek[$k] }
    Json-Yaz ([pscustomobject]$d) (Join-Path $gk 'durum.json')
    return (Gorev-Oku $Id)
}
function Olaylar($D) { return @(@($D.gecmis) | Where-Object { $_ } | ForEach-Object { [string]$_.olay }) }
function Gunluk-Metni { return ((Get-ChildItem -LiteralPath (Join-Path $kum 'gunluk') -Filter '*.log' -File -ErrorAction SilentlyContinue | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n") }
# durum.ps1 ayrı süreçte, kum havuzunun kendi kopyasıyla çalışır (panelin ↺ düğmesiyle aynı yol)
function Durum([string]$ArgMetni) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $komut = "try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}; & '" + (Join-Path $kum 'durum.ps1') + "' $ArgMetni"
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $c = (& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $komut 2>&1 | Out-String); $kod = $LASTEXITCODE }
    finally { $ErrorActionPreference = $eap }
    return [pscustomobject]@{ kod = $kod; cikti = [string]$c }
}
$cl = [pscustomobject]@{ arac = 'claude'; model = 'sahte-opus' }
$cx = [pscustomobject]@{ arac = 'codex'; model = 'sahte-codex' }
$gece = (Get-Date).Date.AddDays(1).AddMinutes(1)
# Canlıdaki #0088 geçmişinden (21.11.2026): ilki 400 karakterde kesilmiş, PUAN satırında boşluksuz | var
$gercek1 = "Backend Developer çalışamadı: claude/claude-opus-5-5: günlük sınır doldu (100/100) | codex/gpt-6.1-sol: kod 1: ERROR: You" + [char]0x2019 + "ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.c"
$gercek2 = "Backend Developer çalışamadı: claude/claude-opus-5-5: günlük sınır doldu (100/100) | codex/gpt-6.1-sol: Codex kullanım sınırı (22:45'e kadar) | codex/gpt-6-astra: Codex kullanım sınırı (22:45'e kadar)"
$puanli = "Backend Developer çalışamadı: claude/claude-opus-5-5: günlük sınır doldu (100/100) | codex/gpt-6-astra: kod 1: PUAN: <1|2|3|5|8|13|21> PUAN_GEREKCE: <tek cümle> ERROR: You" + [char]0x2019 + "ve hit your usage limit."
$gercekHata = "Backend Developer çalışamadı: claude/claude-opus-5-5: zaman aşımı (25 dk) | codex/gpt-6.1-sol: Codex kullanım sınırı (22:45'e kadar)"

try {
    Write-Host 'S1: Sinir-Acilisi (aracın sınırdan açılış saati)'
    Sayac-Ayarla 100 0
    $t = (Get-Date).AddMinutes(45)
    Kilitler @{ 'codex:sahte-codex' = @($t, 'Codex kullanım sınırı') }
    $a = Sinir-Acilisi $cl 'günlük sınır doldu (100/100)'
    Dogrula 'günlük sınır dolu: gece yarısından 1 dk sonra açılır' ((Dk $a $gece) -lt 0.1) (Goster $a)
    $a = Sinir-Acilisi $cx 'Codex kullanım sınırı'
    Dogrula 'Codex kullanım sınırı kilidi: kilidin bitişinde açılır' ((Dk $a $t) -lt 0.1) (Goster $a)
    Dogrula '-YalnizKilit günlük sınırı saymaz' ($null -eq (Sinir-Acilisi $cl -YalnizKilit))
    $ileri = (Get-Date).Date.AddDays(1).AddHours(5)
    Kilitler @{ 'claude' = @($ileri, 'Claude kullanım sınırı') }
    $a = Sinir-Acilisi $cl
    Dogrula 'günlük sınır + daha geç sınır kilidi: geç olan' ((Dk $a $ileri) -lt 0.1) (Goster $a)
    Kilitler @{ 'claude' = @((Get-Date).AddHours(2), 'Claude CLI girişi geçersiz') }
    Dogrula 'giriş kilidi sınır sayılmaz (günlük sınır dolu olsa da)' ($null -eq (Sinir-Acilisi $cl 'günlük sınır doldu'))
    Kilitler @{ 'codex:sahte-codex' = @((Get-Date).AddHours(6), 'model kullanılamıyor') }
    Dogrula 'model kilidi sınır sayılmaz' ($null -eq (Sinir-Acilisi $cx))
    Sayac-Ayarla 0 0; Kilitler @{}
    Dogrula 'açık araç: null' ($null -eq (Sinir-Acilisi $cl))
    $a = Sinir-Acilisi $cl 'Claude kullanım hakkı az (kalan %8)'
    Dogrula 'Claude kullanım hakkı az: yarım saat sonra yeniden bakılır' ((Dk $a (Get-Date).AddMinutes(30)) -lt 0.5) (Goster $a)

    Write-Host 'S2: Sinir-Hatasi-mi (geçmişteki hata metni yalnız sınır mı)'
    $durumlar = @(
        @('#0088 21:35 (400 karakterde kesik)', $gercek1, $true),
        @('#0088 21:46 (üç araç da sınırda)', $gercek2, $true),
        @('PUAN satırındaki boşluksuz | bölmez', $puanli, $true),
        @('kesik parçada sınır sözcüğü yoksa sayılmaz', "Backend Developer çalışamadı: claude/claude-opus-5-5: günlük sınır doldu (100/100) | codex/gpt-6-astra: kod 1: PUAN: <1|2|3|5|8|13|21> PUAN_GER", $false),
        @('araç hatası karışıksa sayılmaz', $gercekHata, $false),
        @('atlandı + sınır', "Code Reviewer çalışamadı: claude/sahte-opus: atlandı | codex/sahte-codex: Codex kullanım sınırı (22:45'e kadar)", $true),
        @('yalnız atlandı sayılmaz', 'Code Reviewer çalışamadı: claude/sahte-opus: atlandı', $false),
        @('Gemini kota sınırı', "QA Engineer test edemedi: gemini/sahte-gemini: Gemini kota sınırı (23:10'e kadar)", $true),
        @('giriş geçersiz sayılmaz', "Engineering Manager plan yazamadı: claude/sahte-opus: Claude CLI girişi geçersiz (01:58'e kadar)", $false),
        @('KARAR satırı yok sayılmaz', 'Plan çıktısında KARAR satırı yok (claude)', $false),
        @('boş metin', '', $false)
    )
    foreach ($d in $durumlar) { $c = Sinir-Hatasi-mi $d[1]; Dogrula $d[0] ($c -eq $d[2]) ("beklenen $($d[2]), çıkan $c") }

    Write-Host 'S3: Engineering Manager zinciri tamamen sınırda (Claude günlük sınır, Codex kilitli)'
    Sayac-Ayarla 100 0; Cagrilari-Sil
    $t = (Get-Date).AddMinutes(45)
    Kilitler @{ 'codex:sahte-codex' = @($t, 'Codex kullanım sınırı') }
    $g = Test-Gorevi '9101-hepsi-sinirda' 'plan' @{ deneme = 1 }
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama plan, deneme hakkı harcanmadı (1/4)' ([string]$d.asama -eq 'plan' -and [int]$d.deneme -eq 1) ("$($d.asama), deneme $($d.deneme)")
    Dogrula 'sonraki deneme Codex kilidinin açılışında' ((Dk $d.sonraki_deneme $t) -lt 0.1) ("sonraki $(Goster $d.sonraki_deneme), kilit $(Goster $t)")
    $o = Olaylar $d
    Dogrula 'geçmişte "sınır bekleniyor" var, "deneme başarısız" yok' ($o -contains 'sınır bekleniyor' -and $o -notcontains 'deneme başarısız') ($o -join ' > ')
    Dogrula 'son hata iki aracın sınırını söyler' ([string]$d.son_hata -match 'claude/sahte-opus: günlük sınır doldu' -and [string]$d.son_hata -match 'codex/sahte-codex: Codex kullanım sınırı') ([string]$d.son_hata)
    Dogrula 'hiçbir araç çağrılmadı' ((Cagri 'claude') -eq 0 -and (Cagri 'codex') -eq 0) ("claude $(Cagri 'claude'), codex $(Cagri 'codex')")
    Dogrula 'günlüğe "deneme hakkı harcanmadı (1/4)" yazıldı' ((Gunluk-Metni) -match "9101-hepsi-sinirda: 'plan' için bütün araçlar sınırda; deneme hakkı harcanmadı \(1/4\)")
    Dogrula 'bayrak kullanıldıktan sonra temizlendi' ($null -eq $script:SinirBeklemesi)
    Gorev-Ilerlet (Gorev-Oku $g.id)
    $d = Gorev-Oku $g.id
    Dogrula 'yeniden denenince de hak yanmaz, geçmiş şişmez' ([int]$d.deneme -eq 1 -and @(Olaylar $d | Where-Object { $_ -eq 'sınır bekleniyor' }).Count -eq 1) ("deneme $($d.deneme), kayıt $(@(Olaylar $d | Where-Object { $_ -eq 'sınır bekleniyor' }).Count)")

    Write-Host 'S4: son hakta (3/4) bütün araçlar sınırda: iş takılmaz'
    $g = Test-Gorevi '9102-son-hak' 'plan' @{ deneme = 3 }
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'aşama plan, deneme 3, takılmadı' ([string]$d.asama -eq 'plan' -and [int]$d.deneme -eq 3 -and (Olaylar $d) -notcontains 'takıldı') ("$($d.asama), deneme $($d.deneme)")

    Write-Host 'S5: Codex çalışıp kullanım sınırına takılır (kendi kilidini koyar)'
    Sayac-Ayarla 100 0; Kilitler @{}; Cagrilari-Sil
    Codex-Hata "ERROR: You've hit your usage limit. Upgrade to Pro, or try again in 30 minutes."
    $g = Test-Gorevi '9103-codex-sinira-takildi' 'plan' @{ deneme = 0 }
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    $kl = Kilitli 'codex:sahte-codex'
    Dogrula 'Codex bir kez çağrıldı, Claude çağrılmadı, Codex sınır kilidi kondu' ((Cagri 'codex') -eq 1 -and (Cagri 'claude') -eq 0 -and $kl -and [string]$kl.neden -eq 'Codex kullanım sınırı') ("codex $(Cagri 'codex'), kilit $(Goster $kl.bitis)")
    $beklenen = $gece; if ($kl -and [datetime]$kl.bitis -lt $beklenen) { $beklenen = [datetime]$kl.bitis }
    Dogrula 'deneme hakkı harcanmadı (0), sonraki deneme en erken açılışta' ([int]$d.deneme -eq 0 -and (Dk $d.sonraki_deneme $beklenen) -lt 0.1) ("deneme $($d.deneme), sonraki $(Goster $d.sonraki_deneme), beklenen $(Goster $beklenen)")

    Write-Host 'S6: Codex başka bir hatayla düşer: eski davranış'
    Sayac-Ayarla 100 0; Kilitler @{}; Cagrilari-Sil
    Codex-Hata 'ERROR: something else went wrong'
    $g = Test-Gorevi '9104-codex-baska-hata' 'plan' @{ deneme = 1 }
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'deneme 2/4, 20 dk sonra yeniden denenecek' ([int]$d.deneme -eq 2 -and (Dk $d.sonraki_deneme (Get-Date).AddMinutes(20)) -lt 1) ("deneme $($d.deneme), sonraki $(Goster $d.sonraki_deneme)")
    Dogrula 'geçmişte "deneme başarısız", "sınır bekleniyor" yok' ((Olaylar $d) -contains 'deneme başarısız' -and (Olaylar $d) -notcontains 'sınır bekleniyor') ((Olaylar $d) -join ' > ')

    Write-Host 'S7: Claude giriş kilidi + Codex sınır kilidi: eski davranış'
    Sayac-Ayarla 0 0; Cagrilari-Sil
    Kilitler @{ 'claude' = @((Get-Date).AddHours(2), 'Claude CLI girişi geçersiz'); 'codex:sahte-codex' = @((Get-Date).AddMinutes(45), 'Codex kullanım sınırı') }
    $g = Test-Gorevi '9105-giris-kilidi' 'plan' @{ deneme = 0 }
    Gorev-Ilerlet $g
    $d = Gorev-Oku $g.id
    Dogrula 'deneme 1/4 (giriş sorunu sınır değildir)' ([int]$d.deneme -eq 1 -and (Olaylar $d) -contains 'deneme başarısız') ("deneme $($d.deneme)")
    Dogrula 'hiçbir araç çağrılmadı' ((Cagri 'claude') -eq 0 -and (Cagri 'codex') -eq 0)

    Write-Host 'S8: bayrak yalnız kendi hatasında ve kendi işinde geçerli; atlanan araç sayılmaz'
    Sayac-Ayarla 100 0
    Kilitler @{ 'codex:sahte-codex' = @((Get-Date).AddMinutes(45), 'Codex kullanım sınırı') }
    $g = Test-Gorevi '9106-baska-mesaj' 'plan' @{ deneme = 0 }
    $script:AktifGorev = $g.id
    $r = Ajan-Cagir -Rol 'lider' -Istem 'x' -Klasor $g.calisma_klasoru -KayitKlasoru (Kayit-Klasoru $g) -Etiket 'plan'
    Dogrula 'Ajan-Cagir sınır açılışını döner' (-not $r.basarili -and (Dk $r.sinir_acilis (Get-Date).AddMinutes(45)) -lt 0.2) (Goster $r.sinir_acilis)
    Adim-Basarisiz $g 'Plan çıktısında KARAR satırı yok (claude)'
    Dogrula 'başka hata mesajı sınır beklemesi sayılmaz (deneme 1)' ([int]$g.deneme -eq 1) ("deneme $($g.deneme)")
    $g2 = Test-Gorevi '9107-baska-is' 'plan' @{ deneme = 0 }
    $r = Ajan-Cagir -Rol 'lider' -Istem 'x' -Klasor $g.calisma_klasoru -KayitKlasoru (Kayit-Klasoru $g) -Etiket 'plan'
    Adim-Basarisiz $g2 "Engineering Manager plan yazamadı: $($r.hata)"
    Dogrula 'başka işin bayrağı sayılmaz (deneme 1)' ([int]$g2.deneme -eq 1) ("deneme $($g2.deneme)")
    Sayac-Ayarla 0 0
    $r = Ajan-Cagir -Rol 'lider' -Istem 'x' -Klasor $g.calisma_klasoru -KayitKlasoru (Kayit-Klasoru $g) -Etiket 'plan' -Haric @('claude/sahte-opus')
    Dogrula 'Claude atlanır (Haric), Codex sınırda: sınır beklemesi' ((Dk $r.sinir_acilis (Get-Date).AddMinutes(45)) -lt 0.2 -and [string]$script:SinirBeklemesi.gorev -eq $g.id) ([string]$r.hata)
    $script:AktifGorev = ''; $script:SinirBeklemesi = $null

    Write-Host 'S9: günlük hak sıfırlanınca sınır yüzünden yanan haklar geri verilir (durum.ps1 -KotaSifirla claude)'
    $eski = (Get-Date).AddHours(-1).ToString('o')
    $olay = { param([string]$Asama, [string]$Olay, [string]$Ayrinti) [ordered]@{ zaman = $eski; asama = $Asama; tur = 1; olay = $Olay; ayrinti = $Ayrinti } }
    $null = Test-Gorevi '9108-iade' 'gelistirme' @{ deneme = 3; sonraki_deneme = (Get-Date).AddMinutes(30).ToString('o'); son_hata = $gercek2
        gecmis = @((& $olay 'plan' 'deneme başarısız' $gercek2), (& $olay 'plan' 'plan hazır' ''), (& $olay 'gelistirme' 'deneme başarısız' $gercek1), (& $olay 'gelistirme' 'deneme başarısız' $gercekHata), (& $olay 'gelistirme' 'deneme başarısız' $gercek2)) }
    $null = Test-Gorevi '9109-iadesiz' 'gelistirme' @{ deneme = 2; sonraki_deneme = (Get-Date).AddMinutes(30).ToString('o'); son_hata = $gercek2
        gecmis = @((& $olay 'gelistirme' 'deneme başarısız' $gercekHata), (& $olay 'gelistirme' 'deneme başarısız' 'Plan çıktısında KARAR satırı yok (claude)')) }
    $r = Durum '-KotaSifirla claude'
    Dogrula 'komut başarılı' ($r.kod -eq 0) ("kod $($r.kod)")
    $d = Gorev-Oku '9108-iade'
    Dogrula 'yalnız sınırdan yanan 2 hak geri verildi (3 -> 1); önceki aşamanınki sayılmadı' ([int]$d.deneme -eq 1) ("deneme $($d.deneme)")
    Dogrula 'beklemeden yeniden denenecek' (-not $d.sonraki_deneme)
    $son = @($d.gecmis)[-1]
    Dogrula 'geçmiş notu: 2 deneme hakkı geri verildi' ([string]$son.olay -eq 'günlük hak sıfırlandı' -and [string]$son.ayrinti -match 'sınır yüzünden yanan 2 deneme hakkı geri verildi') ([string]$son.ayrinti)
    Dogrula 'çıktı: "(2 deneme hakkı geri verildi, deneme 1/4)"' ($r.cikti -match 'Beklemeden yeniden denenecek: #9108 [^\r\n]*\(2 deneme hakkı geri verildi, deneme 1/4\)') ((($r.cikti -split "`n") | Where-Object { $_ -match '#9108' }) -join ' / ')
    $d = Gorev-Oku '9109-iadesiz'
    Dogrula 'başka nedenle yanan haklar geri verilmez (2 kalır), iş yine beklemez' ([int]$d.deneme -eq 2 -and -not $d.sonraki_deneme) ("deneme $($d.deneme)")
    Dogrula 'çıktı: iadesiz işte not yok' ($r.cikti -match 'Beklemeden yeniden denenecek: #9109 ' -and $r.cikti -notmatch '#9109 [^\r\n]*geri verildi')
    $d = Gorev-Oku '9101-hepsi-sinirda'
    Dogrula 'sınır bekleyen iş (S3) sıfırlamayla beklemez, hakkı aynı kalır' (-not $d.sonraki_deneme -and [int]$d.deneme -eq 1) ("deneme $($d.deneme), sonraki $(Goster $d.sonraki_deneme)")
} catch {
    $script:Kalan++
    Write-Host ("BEKLENMEYEN HATA: {0} @ {1}" -f $_.Exception.Message, ($_.InvocationInfo.PositionMessage -replace '\s+', ' '))
} finally {
    Write-Host ''
    Write-Host ("Sonuç: {0}/{1} denetim geçti" -f ($script:Toplam - $script:Kalan), $script:Toplam)
    if (-not $Koru) { Remove-Item -LiteralPath $kum -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "Kum havuzu korundu: $kum" }
}
if ($script:Kalan -gt 0) { exit 1 }
exit 0
