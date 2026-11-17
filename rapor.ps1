<#
rapor.ps1 - AI Ekip rapor ve özetleri (baslat.ps1 / durum.ps1 dot-source eder).
  Rapor-Uret   : raporlar\son-rapor.html (her adımdan sonra güncellenir; tarayıcıda kendini yeniler)
  Ozet-Kontrol : ayarlar.bildirim.ozet_saatleri geldiğinde kısa özet bildirimi + raporlar\ozet-<tarih>.md
#>

function HtmlK([string]$s) { [Net.WebUtility]::HtmlEncode([string]$s) }

function Ozet-Metni {
    $liste = @(Gorevleri-Listele)
    $s = Sayac-Oku
    $bugun = (Get-Date).Date
    $tamamBugun = @($liste | Where-Object { $_.asama -eq 'tamam' -and $_.guncelleme -and ([datetime]$_.guncelleme) -ge $bugun })
    $suren = @($liste | Where-Object { $AktifAsamalar -contains $_.asama -and $_.asama -ne 'yeni' })
    $sirada = @($liste | Where-Object { $_.asama -eq 'yeni' })
    $bekleyen = @($liste | Where-Object { $_.asama -eq 'takildi' -or $_.asama -eq 'bekliyor_kullanici' })
    $kisa = 'Bugün {0} görev tamamlandı, {1} sürüyor, {2} sırada, {3} senden işlem bekliyor. Çağrı: Claude {4}, Codex {5}.' -f `
        $tamamBugun.Count, $suren.Count, $sirada.Count, $bekleyen.Count, [int]$s.claude, [int]$s.codex
    $uzun = New-Object Text.StringBuilder
    [void]$uzun.AppendLine("## Özet - $((Get-Date).ToString('dd.MM.yyyy HH:mm'))")
    [void]$uzun.AppendLine('')
    [void]$uzun.AppendLine($kisa)
    [void]$uzun.AppendLine('')
    foreach ($g in $tamamBugun) { [void]$uzun.AppendLine("- Tamamlandı: #$($g.id) $($g.baslik) -> dal ``$($g.dal)`` ($($g.commit)). $($g.ozet)") }
    foreach ($g in $suren) { [void]$uzun.AppendLine("- Sürüyor: #$($g.id) $($g.baslik) [$(Asama-Adi $g.asama), tur $($g.tur)]") }
    foreach ($g in $bekleyen) { [void]$uzun.AppendLine("- Seni bekliyor: #$($g.id) $($g.baslik) [$(Asama-Adi $g.asama)] $($g.son_hata)") }
    foreach ($g in $sirada) { [void]$uzun.AppendLine("- Sırada: #$($g.id) $($g.baslik)") }
    return [pscustomobject]@{ kisa = $kisa; uzun = $uzun.ToString() }
}

function Ozet-Gonder {
    $m = Ozet-Metni
    $yol = Join-Path $YolRapor ('ozet-{0}.md' -f (Get-Date).ToString('yyyy-MM-dd'))
    try { [IO.File]::AppendAllText($yol, $m.uzun + "`r`n", $Utf8) } catch {}
    Bildir -Baslik 'AI Ekip özeti' -Metin $m.kisa
}

function Ozet-Kontrol {
    $s = Sayac-Oku
    $gonderilen = @()
    if ($s.ozet_gonderilen) { $gonderilen = @($s.ozet_gonderilen) }
    foreach ($saat in @($Ayar.bildirim.ozet_saatleri)) {
        if (-not $saat -or $gonderilen -contains $saat) { continue }
        $hedef = (Get-Date).Date + [timespan]::Parse([string]$saat)
        $an = Get-Date
        if ($an -lt $hedef) { continue }
        $gonderilen += [string]$saat
        Ayarla $s 'ozet_gonderilen' $gonderilen
        Json-Yaz $s (Join-Path $YolDurum 'sayaclar.json')
        # Bilgisayar o saatte kapalıysa bayat özeti sonradan atma
        if (($an - $hedef).TotalHours -le 3) { Ozet-Gonder }
    }
}

function Rapor-Uret {
    try {
        $liste = @(Gorevleri-Listele | Sort-Object id -Descending)
        $s = Sayac-Oku
        $k = Json-Oku (Join-Path $YolDurum 'kalp.json')
        $kilitler = Kilit-Oku
        $kalpMetni = 'bilinmiyor'
        if ($k -and $k.zaman) {
            $dk = [int]((Get-Date) - [datetime]$k.zaman).TotalMinutes
            $kalpMetni = '{0} ({1} dk önce, PID {2})' -f $k.durum, $dk, $k.pid
            if ($k.gorev) { $kalpMetni += " - görev $($k.gorev): $($k.adim)" }
        }
        $kilitSatirlari = ''
        foreach ($p in $kilitler.PSObject.Properties) {
            $v = $p.Value
            if ($v -and ([datetime]$v.bitis) -gt (Get-Date)) {
                $kilitSatirlari += '<li><b>{0}</b>: {1} ({2}''e kadar)</li>' -f (HtmlK $p.Name), (HtmlK $v.neden), ([datetime]$v.bitis).ToString('dd.MM HH:mm')
            }
        }
        if (-not $kilitSatirlari) { $kilitSatirlari = '<li>Yok - tüm araçlar kullanılabilir</li>' }

        $satirlar = New-Object Text.StringBuilder
        foreach ($g in $liste) {
            $sinif = 'surer'
            switch ($g.asama) { 'tamam' { $sinif = 'tamam' } 'takildi' { $sinif = 'hata' } 'bekliyor_kullanici' { $sinif = 'hata' } 'iptal' { $sinif = 'pasif' } 'yeni' { $sinif = 'pasif' } }
            $son = ''
            if ($g.gecmis) { $x = @($g.gecmis)[-1]; $son = '{0}: {1}' -f ([datetime]$x.zaman).ToString('dd.MM HH:mm'), $x.olay }
            $ek = ''
            if ($g.son_hata) { $ek = '<div class="not">' + (HtmlK (Kisalt $g.son_hata 220)) + '</div>' }
            if ($g.asama -eq 'tamam' -and $g.ozet) { $ek = '<div class="not">' + (HtmlK $g.ozet) + '</div>' }
            $ekip = @($g.lider, $g.gelistirici, $g.denetci | Where-Object { $_ }) -join ' / '
            [void]$satirlar.AppendLine(('<tr><td>{0}</td><td><b>{1}</b>{2}</td><td>{3}</td><td><span class="rozet {4}">{5}</span></td><td>{6}</td><td><code>{7}</code></td><td>{8}</td><td class="kucuk">{9}</td></tr>' -f `
                (HtmlK $g.id), (HtmlK $g.baslik), $ek, (HtmlK $g.proje), $sinif, (HtmlK (Asama-Adi $g.asama)), $g.tur, (HtmlK $g.dal), (HtmlK $son), (HtmlK $ekip)))
        }
        if ($liste.Count -eq 0) { [void]$satirlar.AppendLine('<tr><td colspan="8">Henüz görev yok. Görev eklemek için: gorev-ekle.ps1</td></tr>') }

        $bildirimler = ''
        $by = Join-Path $YolDurum 'bildirimler.jsonl'
        if (Test-Path -LiteralPath $by) {
            $son20 = @(Get-Content -LiteralPath $by -Encoding UTF8 -Tail 20)
            [array]::Reverse($son20)
            foreach ($l in $son20) {
                try { $b = $l | ConvertFrom-Json; $bildirimler += '<li><span class="kucuk">{0}</span> <b>{1}</b> - {2}</li>' -f ([datetime]$b.zaman).ToString('dd.MM HH:mm'), (HtmlK $b.baslik), (HtmlK $b.metin) } catch {}
            }
        }
        if (-not $bildirimler) { $bildirimler = '<li>Henüz bildirim yok</li>' }

        $html = @"
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="60"><title>AI Ekip</title>
<style>
:root { --zemin:#f6f7f9; --kart:#fff; --yazi:#1d2330; --soluk:#667085; --cizgi:#e4e7ec; --yesil:#127a46; --yesil-z:#e3f5ea; --kirmizi:#b42318; --kirmizi-z:#fde8e6; --mavi:#1f5fbf; --mavi-z:#e6eefb; --gri-z:#eef0f3; }
@media (prefers-color-scheme: dark) { :root { --zemin:#14171c; --kart:#1c2027; --yazi:#e6e8eb; --soluk:#98a2b3; --cizgi:#2d333d; --yesil:#5fd394; --yesil-z:#163626; --kirmizi:#ff8a7a; --kirmizi-z:#3d1d1a; --mavi:#8ab4ff; --mavi-z:#1b2a44; --gri-z:#262b33; } }
body { margin:0; background:var(--zemin); color:var(--yazi); font:14px/1.5 "Segoe UI", system-ui, sans-serif; }
main { max-width:1200px; margin:0 auto; padding:20px 16px 40px; }
h1 { font-size:22px; margin:0 0 4px; } h2 { font-size:16px; margin:24px 0 8px; }
.soluk, .kucuk { color:var(--soluk); } .kucuk { font-size:12px; }
.izgara { display:grid; grid-template-columns:repeat(auto-fit, minmax(170px, 1fr)); gap:10px; margin-top:16px; }
.kart { background:var(--kart); border:1px solid var(--cizgi); border-radius:10px; padding:12px 14px; }
.kart .sayi { font-size:24px; font-weight:600; }
.tablo { overflow-x:auto; background:var(--kart); border:1px solid var(--cizgi); border-radius:10px; }
table { border-collapse:collapse; width:100%; min-width:760px; }
th, td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--cizgi); vertical-align:top; }
th { font-size:12px; color:var(--soluk); font-weight:600; }
.rozet { display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; white-space:nowrap; }
.tamam { background:var(--yesil-z); color:var(--yesil); } .hata { background:var(--kirmizi-z); color:var(--kirmizi); }
.surer { background:var(--mavi-z); color:var(--mavi); } .pasif { background:var(--gri-z); color:var(--soluk); }
.not { color:var(--soluk); font-size:12px; margin-top:2px; }
ul { margin:0; padding-left:18px; } li { margin:3px 0; }
code { font-size:12px; }
</style></head><body><main>
<h1>AI Ekip</h1>
<div class="soluk">Son güncelleme: $((Get-Date).ToString('dd.MM.yyyy HH:mm:ss')) &middot; Döngü: $(HtmlK $kalpMetni)</div>
<div class="izgara">
  <div class="kart"><div class="kucuk">Bugün tamamlanan</div><div class="sayi">$([int]$s.tamamlanan)</div></div>
  <div class="kart"><div class="kucuk">Bugün takılan</div><div class="sayi">$([int]$s.takilan)</div></div>
  <div class="kart"><div class="kucuk">Claude çağrısı (bugün)</div><div class="sayi">$([int]$s.claude) <span class="kucuk">/ $($Ayar.gunluk_sinir.claude)</span></div></div>
  <div class="kart"><div class="kucuk">Codex çağrısı (bugün)</div><div class="sayi">$([int]$s.codex) <span class="kucuk">/ $($Ayar.gunluk_sinir.codex)</span></div></div>
</div>
<h2>Görevler</h2>
<div class="tablo"><table>
<tr><th>No</th><th>Görev</th><th>Proje</th><th>Durum</th><th>Tur</th><th>Dal</th><th>Son olay</th><th>Engineering Manager / Software Developer / Code Reviewer</th></tr>
$($satirlar.ToString())
</table></div>
<h2>Kısıtlı araçlar</h2>
<div class="kart"><ul>$kilitSatirlari</ul></div>
<h2>Son bildirimler</h2>
<div class="kart"><ul>$bildirimler</ul></div>
<p class="kucuk">Klasör: $(HtmlK $Kok) &middot; Durdurmak için klasöre DURDUR adlı boş bir dosya koy &middot; Durum: durum.ps1</p>
</main></body></html>
"@
        Metin-Yaz (Join-Path $YolRapor 'son-rapor.html') $html
    } catch { Gunluk "Rapor üretilemedi: $($_.Exception.Message)" 'UYARI' }
}
