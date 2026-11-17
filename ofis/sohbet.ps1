<#
sohbet.ps1 - Paneldeki sohbet penceresinden gelen son mesajı ilgili çalışana (rolünün araç zinciriyle) sorar, yanıtı kaydeder.

Ofis sunucusu (ofis.ps1) her mesajda arka planda başlatır:  sohbet.ps1 -Rol <anahtar>
- Salt okunur çalışır: çalışan dosya değiştirmez, komut çalıştırmaz (Claude: Read/Glob/Grep, Codex: read-only).
- Kullanıcı bir iş isterse çalışan yanıtına bir iş önerisi ekler (```is {...}```); kullanıcı panelde onaylayıp ekibe verir.
- Günlük çağrı sınırları ve yedek zinciri döngüyle aynıdır (Ajan-Cagir).
Kayıtlar: durum\sohbet\<rol>.jsonl (mesajlar), <rol>.isleniyor (yanıt yazılırken), kayit\<rol>\ (son istem ve çıktılar)
#>
param([Parameter(Mandatory)][string]$Rol)
$ErrorActionPreference = 'Stop'
# Claude masaüstü uygulamasından devralınan değişkenler claude.exe'yi bozar (401); temizle
$adlar = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } | ForEach-Object { $_.Name })
foreach ($a in $adlar) { Remove-Item -LiteralPath "env:$a" -ErrorAction SilentlyContinue }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$ust = Split-Path -Parent $PSScriptRoot
. (Join-Path $ust 'ortak.ps1')
. (Join-Path $ust 'uzman.ps1')
function Kalp([string]$Durum) { }   # döngünün kalp atışı dosyasına bu süreç yazmasın
Ayarlari-Yukle
Kadro-Rolleri-Yukle

if ($Rol -notmatch '^[a-z0-9-]{1,40}$') { throw "Geçersiz rol: $Rol" }
$klasor = Join-Path $YolDurum 'sohbet'
$dosya = Join-Path $klasor "$Rol.jsonl"
$isaret = Join-Path $klasor "$Rol.isleniyor"
$utf8 = New-Object Text.UTF8Encoding $false

function Mesaj-Ekle($Nesne) {
    [IO.File]::AppendAllText($dosya, (($Nesne | ConvertTo-Json -Compress -Depth 6) + "`n"), $utf8)
}
function Mesajlari-Oku([int]$Son) {
    $l = @()
    if (-not (Test-Path -LiteralPath $dosya)) { return $l }
    foreach ($s in @(Get-Content -LiteralPath $dosya -Encoding UTF8 -Tail $Son)) { if ($s -and $s.Trim()) { try { $l += ($s | ConvertFrom-Json) } catch {} } }
    return $l
}
function Kisa([string]$Metin, [int]$En) { if ($Metin.Length -le $En) { return $Metin }; return $Metin.Substring(0, $En) + '…' }
function Oneri-Dogrula($O) {
    $baslik = ([string]$O.baslik).Trim()
    if (-not $baslik) { return $null }
    $tur = [string]$O.tur; if (@('uzman', 'yazilim', 'altyapi') -notcontains $tur) { $tur = 'uzman' }
    $s = [ordered]@{ tur = $tur; baslik = (Kisa $baslik 120); aciklama = (Kisa ([string]$O.aciklama).Trim() 8000); oncelik = 2 }
    if (@(1, 2, 3) -contains [int]$O.oncelik) { $s.oncelik = [int]$O.oncelik }
    $rolAnahtar = ([string]$O.rol).Trim()
    if ($rolAnahtar) { $u = Kadro-Uye $rolAnahtar; if ($u -and $u.uzman_isi) { $s.rol = $rolAnahtar } }
    if ($O.proje) { $s.proje = Kisa ([string]$O.proje).Trim() 400 }
    if ($O.klasor) { $s.klasor = Kisa ([string]$O.klasor).Trim() 400 }
    if ($O.hedef) { $s.hedef = @(@($O.hedef) | ForEach-Object { Kisa ([string]$_).Trim() 60 } | Where-Object { $_ } | Select-Object -First 8) }
    if ($O.kabul) { $s.kabul = @(@($O.kabul) | ForEach-Object { Kisa ([string]$_).Trim() 300 } | Where-Object { $_ } | Select-Object -First 12) }
    return $s
}
function Isler-Metni {
    $l = @(Gorevleri-Listele | Sort-Object { [string]$_.guncelleme } -Descending | Select-Object -First 15)
    if (-not $l.Count) { return '(henüz görev yok)' }
    $sb = New-Object Text.StringBuilder
    foreach ($g in $l) {
        $tip = [string]$g.tip; if (-not $tip) { $tip = 'yazilim' }
        $kim = @()
        foreach ($a in @('sorumlu', 'inceleyen', 'destek')) { $v = [string]$g.$a; if ($v -and $v -ne 'yok') { $kim += "${a}: $v" } }
        if ($g.proje) { $kim += "proje: $($g.proje)" }
        [void]$sb.AppendLine(('- #{0} {1} [{2}] {3}, tur {4}/{5}{6}' -f ([string]$g.id).Split('-')[0], $g.baslik, $tip, (Asama-Adi ([string]$g.asama)), $g.tur, $g.max_tur, $(if ($kim.Count) { ' · ' + ($kim -join ', ') } else { '' })))
    }
    $kalp = Json-Oku (Join-Path $YolDurum 'kalp.json')
    if ($kalp -and $kalp.gorev -and $kalp.durum -notin @('boşta', 'durduruldu', 'mesai dışı', 'durdu')) { [void]$sb.AppendLine("Şu an çalışılan: $($kalp.gorev) · $($kalp.adim)") }
    if (Test-Path -LiteralPath (Join-Path $Kok 'DURDUR')) { [void]$sb.AppendLine('Ekip şu an duraklatılmış (ya da ofis kapalı); yeni iş almıyor.') }
    return $sb.ToString().TrimEnd()
}

try {
    $uye = Kadro-Uye $Rol
    if (-not $uye) { throw "Kadroda böyle bir çalışan yok: $Rol" }
    $gecmis = @(Mesajlari-Oku 16)
    $son = $gecmis | Where-Object { $_.kim -eq 'sen' } | Select-Object -Last 1
    if (-not $son) { throw 'Yanıtlanacak mesaj bulunamadı' }
    $onceki = @($gecmis | Where-Object { $_ -ne $son -and $_.kim -ne 'sistem' })
    $gecmisMetni = '(bu sohbetin ilk mesajı)'
    if ($onceki.Count) {
        $gecmisMetni = (($onceki | ForEach-Object {
            $kim = $(if ($_.kim -eq 'sen') { 'Kullanıcı' } else { [string]$uye.ad })
            "${kim}: $(Kisa ([string]$_.metin) 1500)"
        }) -join "`n`n")
    }
    $projeler = '(yok)'
    $pj = Json-Oku (Join-Path $Kok 'projeler.json')
    if ($pj -and $pj.projeler) { $projeler = (@($pj.projeler) | ForEach-Object { "$($_.ad) ($($_.klasor))" }) -join ', ' }
    $makineler = '(yok)'
    if ($Ayar.altyapi -and $Ayar.altyapi.makineler) { $makineler = (@($Ayar.altyapi.makineler) | ForEach-Object { "$($_.ad) ($($_.ip))" }) -join ', ' }
    $talimat = Rol-Talimati $uye

    $istem = @"
# Sohbet

Sen bir yapay zeka ekibinde **$($uye.ad)** olarak çalışıyorsun ($($uye.departman)). Ekibin sahibi (kullanıcı) sana ofis panelindeki sohbet penceresinden yazıyor. Bugün: $((Get-Date).ToString('dd.MM.yyyy HH:mm')).

## Rolün
$talimat

## Bu sohbetin kuralları
- Türkçe, kısa ve samimi yanıt ver (genelde 2-8 cümle; gerekirse kısa maddeler). Bir ekip arkadaşı gibi, kendi rolünün bakış açısıyla konuş.
- Bu sohbette yalnızca okuyabilirsin: dosya değiştirme, komut çalıştırma, kurulum yapma. Gerekirse çalışma klasöründeki dosyaları okuyup bilgi ver
  (ör. gorevler\<no-...>\durum.json, gorevler\<no-...>\gorev.md, kadro.json; teslimler calisma\<no-...>\cikti altında).
- Bilmediğin şeyi uydurma; emin değilsen söyle. Parola, anahtar ya da kişisel veri yazma.
- Kullanıcı senden ya da ekipten bir iş isterse işi bu sohbette yapmaya çalışma. Ne yapılacağını kısaca anlat ve yanıtının EN SONUNA
  tek bir iş önerisi ekle; kullanıcı panelde onaylayıp ekibe verir. Biçim (geçerli JSON):

``````is
{"tur": "uzman", "baslik": "kısa başlık", "aciklama": "ne yapılacak, sınırlar, beklenen teslimler", "rol": "kadrodan anahtar ya da boş (Engineering Manager seçer)", "kabul": ["ölçüt 1", "ölçüt 2"], "oncelik": 2}
``````

  - tur: "uzman" (tasarım, mimari, güvenlik incelemesi, araştırma, iletişim, işe alım ...), "yazilim" (bir git projesinde kod; "proje" alanına proje adını yaz),
    "altyapi" (sunucu, kurulum, VM, ağ; "hedef" alanına makine adlarını yaz, ör. ["LAB-SRV"]).
  - Yalnızca kullanıcı gerçekten bir iş istediğinde öneri ekle; sıradan sorularda ekleme.

## Kadro
$(Kadro-Metni)

## Ekibin işleri (son güncellenenler)
$(Isler-Metni)

## Projeler
$projeler

## Makineler
$makineler

## Sohbet geçmişi
$gecmisMetni

## Kullanıcının son mesajı
$([string]$son.metin)

Şimdi $($uye.ad) olarak yanıt ver.
"@
    $r = Ajan-Cagir -Rol $Rol -Istem $istem -Klasor $Kok -KayitKlasoru (Join-Path $klasor "kayit\$Rol") -Etiket 'sohbet'
    if ($r.basarili) {
        $metin = ([string]$r.metin).Trim()
        $oneri = $null
        $m = [regex]::Match($metin, '(?s)```is\s*(\{.*?\})\s*```')
        if ($m.Success) {
            try { $oneri = Oneri-Dogrula ($m.Groups[1].Value | ConvertFrom-Json) } catch {}
            $metin = $metin.Remove($m.Index, $m.Length).Trim()
        }
        if (-not $metin) { $metin = '(öneri hazırladım)' }
        $kayit = [ordered]@{ zaman = (Simdi); kim = 'ajan'; metin = (Kisa $metin 6000); arac = ('{0}/{1}' -f $r.arac, $r.model); sure_sn = $r.sure_sn }
        if ($oneri) { $kayit.oneri = $oneri }
        Mesaj-Ekle $kayit
    } else {
        Mesaj-Ekle ([ordered]@{ zaman = (Simdi); kim = 'sistem'; metin = "Yanıt alınamadı: $(Kisa ([string]$r.hata) 400)" })
    }
} catch {
    Mesaj-Ekle ([ordered]@{ zaman = (Simdi); kim = 'sistem'; metin = "Sohbet hatası: $(Kisa $_.Exception.Message 400)" })
} finally {
    Remove-Item -LiteralPath $isaret -Force -ErrorAction SilentlyContinue
}
