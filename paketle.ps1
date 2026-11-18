<# Kişisel dosyaları almadan, sabit dağıtım listesiyle paylaşılabilir ZIP üretir. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$dosyalar = @(
    'README.md','LICENSE','.gitignore','ayarlar.json','kadro.json','projeler.json',
    'kur-ofis.ps1','yapilandirma.ps1','paketle.ps1',
    'ortak.ps1','ekip.ps1','altyapi.ps1','uzman.ps1','yonlendirme.ps1','cozucu.ps1','yardim.ps1','posta.ps1','baslat.ps1',
    'komut.ps1','paralel.ps1','planlama.ps1','yonetim.ps1','danisman.ps1',
    'katlar.json','iletisim.ps1','yaratici.ps1','kopru.ps1','proje-ekle.ps1','sonuc-ekle.ps1','ofis/bina.html','ofis/panel-creativity.html','testler/katlar.test.ps1',
    'danisman/CLAUDE.md','danisman/AGENTS.md','danisman/GEMINI.md',
    'kur.ps1','kaldir.ps1','durum.ps1','rapor.ps1','is-ver.ps1','gorev-ekle.ps1','talep-ekle.ps1','uzman-ekle.ps1','eposta-kur.ps1',
    'ofis/ofis.ps1','ofis/kisayol-olustur.ps1','ofis/sohbet.ps1','ofis/telefon-kur.ps1','ofis/panel.html',
    'araclar/posta_oku.py','araclar/kullanim-gecmis.ps1',
    'testler/dagitim.test.ps1','testler/yonetici-cozucu.test.ps1','testler/iptal-yarisi.test.ps1','testler/yardimlasma.test.ps1','testler/birlikte-puan-tasima.test.ps1',
    'testler/komut-paralel.test.ps1','testler/planlama-katmani.test.ps1','testler/yonetim-cto.test.ps1','testler/danisman.test.ps1'
)
foreach ($ad in @('lider-plan','gelistirici','denetci','lider-kabul','altyapi-uygulama','altyapi-dogrulama','lider-altyapi-plan','lider-altyapi-kabul','lider-uzman-plan','uzman-calisma','uzman-inceleme','lider-uzman-kabul','ek-inceleme','ik-ise-alim','yonetici-yonlendirme','sorun-giderici','yonetici-yardim','tester-inceleme','sorun-kategori','yardim-birlikte','urun-analiz','kasif-kesif','qa-test','cto-degerlendirme','danisman-gorev','danisman-claude',
        'iletisim-gonder','iletisim-rapor','fikirci','elestirmen','planlamaci','maliyet','karar-verici','teslim','puanlayici')) {
    $dosyalar += "istemler/$ad.md"
}
foreach ($ad in @('mimar','guvenlik','tasarimci-ui','tasarimci-grafik','ik','iletisim','ses-tasarimci','sorun-giderici','tester','urun','kasif','frontend','backend','gelistirici','cto','danisman')) { $dosyalar += "istemler/kadro/$ad.md" }
# Şirket binasının katları (katlar\<id>): şablon ve kaynak dosyalarının tümü; çalışma kayıtları, kişisel ayarlar, ortam dosyaları,
# bağımlılık / model / çıktı klasörleri hariç
$katKok = Join-Path $PSScriptRoot 'katlar'
$haricKlasor = '(^|\\)(durum|gunluk|gorevler|calisma|raporlar|node_modules|\.venv[^\\]*|__pycache__|dist|logs|models|data|data-test|notlar|\.pytest_cache|secrets)(\\|$)'
if (Test-Path -LiteralPath $katKok) {
    foreach ($f in @(Get-ChildItem -LiteralPath $katKok -Recurse -File | Sort-Object FullName)) {
        $g = $f.FullName.Substring($PSScriptRoot.Length + 1)
        if ((Split-Path -Parent $g) -match $haricKlasor) { continue }
        if ($f.Name -match '^(DURDUR|\.env)$|\.yerel\.json|\.(bak|tmp|log|pyc)$') { continue }
        $dosyalar += ($g -replace '\\', '/')
    }
}
foreach ($ad in $dosyalar) { if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $ad) -PathType Leaf)) { throw "Paket dosyası eksik: $ad" } }

$hedef = Join-Path $PSScriptRoot 'dagitim'
New-Item -ItemType Directory -Path $hedef -Force | Out-Null
$zip = Join-Path $hedef 'ai-ofis.zip'
$tmp = Join-Path $hedef ('ai-ofis-' + [guid]::NewGuid().ToString('N') + '.tmp')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    $arsiv = [IO.Compression.ZipFile]::Open($tmp, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($ad in $dosyalar) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arsiv, (Join-Path $PSScriptRoot $ad), $ad, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $arsiv.Dispose() }
    if (Test-Path -LiteralPath $zip) {
        [IO.File]::Replace($tmp, $zip, "$zip.bak")
        Remove-Item -LiteralPath "$zip.bak" -Force
    }
    else { [IO.File]::Move($tmp, $zip) }
} finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
Write-Host ("Paket hazır: {0} ({1} dosya)" -f $zip, $dosyalar.Count)
Get-FileHash -LiteralPath $zip -Algorithm SHA256 | Format-List
