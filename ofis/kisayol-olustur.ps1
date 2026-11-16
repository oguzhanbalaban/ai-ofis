<#
kisayol-olustur.ps1 - Masaüstüne "AI Ekip Ofisi" kısayolunu (ve ofis.ico simgesini) kurar. Yönetici gerekmez.

  Kısayol: conhost.exe --headless powershell.exe ... ofis.ps1 -Ac
    * conhost --headless: hiçbir konsol penceresi görünmez (Windows Script Host bazı makinelerde kapalı olduğundan VBS kullanılmaz).
    * Panel sunucusu zaten çalışıyorsa yalnızca tarayıcıda paneli açar.

  .\ofis\kisayol-olustur.ps1            kısayolu kur / güncelle
  .\ofis\kisayol-olustur.ps1 -Kaldir    kısayolu kaldır
#>
param([switch]$Kaldir)
$ErrorActionPreference = 'Stop'
$ofis = $PSScriptRoot
$masaustu = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $masaustu 'AI Ekip Ofisi.lnk'

if ($Kaldir) {
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "Kısayol kaldırıldı: $lnk" } else { Write-Host 'Kısayol zaten yok.' }
    return
}

# ---- simge: PNG içeren .ico (Windows Vista ve sonrası destekler)
$ico = Join-Path $ofis 'ofis.ico'
Add-Type -AssemblyName System.Drawing
function Simge-Ciz([int]$B) {
    $bmp = New-Object Drawing.Bitmap $B, $B, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([Drawing.Color]::Transparent)
    $o = $B / 32.0
    $yol = New-Object Drawing.Drawing2D.GraphicsPath
    $r = 8 * $o; $d = 2 * $r
    $yol.AddArc(0, 0, $d, $d, 180, 90); $yol.AddArc($B - $d - 1, 0, $d, $d, 270, 90)
    $yol.AddArc($B - $d - 1, $B - $d - 1, $d, $d, 0, 90); $yol.AddArc(0, $B - $d - 1, $d, $d, 90, 90); $yol.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#1f2328'))), $yol)
    foreach ($c in @(@(9, 17, '#fb923c'), @(16, 13, '#7aa7ff'), @(23, 17, '#4fd1a1'))) {
        $firca = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($c[2]))
        $g.FillEllipse($firca, [single](($c[0] - 4) * $o), [single](($c[1] - 4) * $o), [single](8 * $o), [single](8 * $o))
    }
    $g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#b4875a'))), [single](5 * $o), [single](22 * $o), [single](22 * $o), [single](3 * $o))
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}
$boyutlar = @(256, 48, 32, 16)
$pngler = @($boyutlar | ForEach-Object { , (Simge-Ciz $_) })
$akis = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $akis
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$boyutlar.Count)
$konum = 6 + 16 * $boyutlar.Count
for ($i = 0; $i -lt $boyutlar.Count; $i++) {
    $b = $boyutlar[$i]; $bayt = 0; if ($b -lt 256) { $bayt = $b }
    $w.Write([byte]$bayt); $w.Write([byte]$bayt); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngler[$i].Length); $w.Write([uint32]$konum)
    $konum += $pngler[$i].Length
}
foreach ($p in $pngler) { $w.Write([byte[]]$p) }
$w.Flush()
[IO.File]::WriteAllBytes($ico, $akis.ToArray())

# ---- kısayol
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$betik = Join-Path $ofis 'ofis.ps1'
$kabuk = New-Object -ComObject WScript.Shell
$k = $kabuk.CreateShortcut($lnk)
$k.TargetPath = $conhost
$k.Arguments = ('--headless "{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}" -Ac' -f $ps, $betik)
$k.WorkingDirectory = $ofis
$k.IconLocation = "$ico,0"
$k.Description = 'AI Ekip görsel ofis panelini tarayıcıda açar (yalnızca bu bilgisayar: 127.0.0.1)'
$k.WindowStyle = 7
$k.Save()
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($kabuk)
Write-Host "Kısayol hazır: $lnk"
Write-Host "Simge: $ico"
