<#
sap-java.ps1 - Bir Java programını SAPBO-SRV'de BI 2025 SL SDK / BOE Java SDK sınıf yoluyla derleyip çalıştırır.
D:\SapIqLab\infra\guest\sapbo\run-iq-universe.ps1 yönteminin (13.11.2026'da bu sunucuda çalıştı) genelleştirilmiş hâli.

  .\sap-java.ps1 -Kaynak <Sinif.java> [-Ek <dosya>,<dosya>] [-Arguman <a>,<b>] [-ZamanAsimiDk 20]

  -Kaynak   derlenecek ana sınıf (dosya adı = sınıf adı). Kaynak ASCII olmalı.
  -Ek       programın çalışma klasörüne konacak ek dosyalar (ör. .unxspec); program bunları adıyla açar.
  -Arguman  programa verilecek argümanlar.
  Parolalar ortam değişkenlerinden programın stdin'ine verilir: DAO_BO_PAROLA (1. satır, zorunlu),
  DAO_DB_PAROLA (2. satır, isteğe bağlı). Parolalar dosyaya yazılmaz; konuk betiği iş bitince kendini siler.

Örnekler:
  .\sap-java.ps1 -Kaynak .\unx\UnxBuilder.java -Ek .\unx\ornek-groupo.unxspec -Arguman ornek-groupo.unxspec
  .\sap-java.ps1 -Kaynak .\boe\BoeTool.java -Arguman klasor,"DA Office/Satis"

Çıkış kodu: programın çıkış kodu; 3 = SAPBO-SRV kapalı, 4 = zaman aşımı, 5 = parola yok.
#>
param(
    [Parameter(Mandatory)][string]$Kaynak,
    [string[]]$Ek = @(),
    [string[]]$Arguman = @(),
    [int]$ZamanAsimiDk = 20,
    [string]$Yonetim = 'H:\VMs\bovm.ps1',
    [string]$Vmx = 'H:\VMs\SAPBO\SAPBO.vmx'
)
$ErrorActionPreference = 'Stop'
$vmrun = 'C:\Program Files (x86)\VMware\VMware Player\vmrun.exe'

if (-not $env:DAO_BO_PAROLA) { Write-Host 'Parola yok: DAO_BO_PAROLA ortam değişkenini ayarla (BO Administrator).'; exit 5 }
$acik = (& $vmrun list) -join "`n"
if ($acik -notmatch [regex]::Escape($Vmx)) { Write-Host "SAPBO-SRV kapalı ($Vmx). Önce aç: & '$Yonetim' start; sonra CMS (6400) ve Tomcat (8080) dinliyor mu bak."; exit 3 }

$KaynakYol = (Resolve-Path -LiteralPath $Kaynak).Path
$sinif = [IO.Path]::GetFileNameWithoutExtension($KaynakYol)
$kimlik = [guid]::NewGuid().ToString('N').Substring(0, 10)
function B64([string]$Yol) { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Yol).Path)) }
function Tirnak([string]$s) { "'" + $s.Replace("'", "''") + "'" }

$dosyalar = @(@{ ad = "$sinif.java"; b64 = (B64 $KaynakYol) })
foreach ($e in $Ek) { $dosyalar += @{ ad = [IO.Path]::GetFileName($e); b64 = (B64 $e) } }
$parola = $env:DAO_BO_PAROLA + "`n"; if ($env:DAO_DB_PAROLA) { $parola += $env:DAO_DB_PAROLA + "`n" }
$parolaB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($parola))
$javaArg = ($Arguman | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '

# Konuk betiği: yalnızca ASCII (vmrun aktarımında ASCII dışı karakterler bozuluyor)
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('$ErrorActionPreference = ''Stop''')
[void]$sb.AppendLine('$bo = ''C:\Program Files (x86)\SAP BusinessObjects\SAP BusinessObjects Enterprise XI 4.0''')
[void]$sb.AppendLine('$jdk = "$bo\win64_x64\sapjvm\bin"; $cp = "$bo\SL SDK\java\sl_sdk.jar"')
[void]$sb.AppendLine("`$w = 'C:\Install\da-office\run\$kimlik'")
[void]$sb.AppendLine('New-Item -ItemType Directory -Force "$w\classes" | Out-Null')
[void]$sb.AppendLine('function Proc($exe, $argStr, $stdin) {')
[void]$sb.AppendLine('  $psi = New-Object Diagnostics.ProcessStartInfo $exe; $psi.Arguments = $argStr; $psi.UseShellExecute = $false')
[void]$sb.AppendLine('  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $w')
[void]$sb.AppendLine('  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8')
[void]$sb.AppendLine('  $p = [Diagnostics.Process]::Start($psi)')
[void]$sb.AppendLine('  if ($stdin) { $bytes = [Text.Encoding]::UTF8.GetBytes($stdin); $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length) }')
[void]$sb.AppendLine('  $p.StandardInput.Close(); $e = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()')
[void]$sb.AppendLine('  return @{ kod = $p.ExitCode; out = $o; err = $e.Result } }')
[void]$sb.AppendLine('try {')
foreach ($d in $dosyalar) { [void]$sb.AppendLine("  [IO.File]::WriteAllBytes((Join-Path `$w $(Tirnak $d.ad)), [Convert]::FromBase64String('$($d.b64)'))") }
[void]$sb.AppendLine("  `$pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$parolaB64'))")
[void]$sb.AppendLine("  `$r = Proc `"`$jdk\javac.exe`" ('-encoding UTF-8 -cp `"' + `$cp + '`" -d `"' + `$w + '\classes`" `"' + `$w + '\$sinif.java`"') `$null")
[void]$sb.AppendLine('  if ($r.kod) { "DERLEME HATASI ($($r.kod))"; $r.out; $r.err; exit 2 }')
[void]$sb.AppendLine("  'derleme tamam: $sinif'")
[void]$sb.AppendLine('  $env:Path = "$bo\win64_x64;$env:Path"')
[void]$sb.AppendLine("  `$a = '`"-Dbusinessobjects.connectivity.directory=' + `$bo + '\dataAccess\connectionServer`" `"-Djava.library.path=' + `$bo + '\win64_x64`" -Dfile.encoding=UTF-8 -cp `"' + `$w + '\classes;' + `$cp + '`" $sinif ' + $(Tirnak $javaArg)")
[void]$sb.AppendLine('  $r = Proc "$jdk\java.exe" $a $pw')
[void]$sb.AppendLine('  $pw = $null')
[void]$sb.AppendLine('  $r.out')
[void]$sb.AppendLine('  if ($r.err) { ''--- stderr (son 40 satir)''; ($r.err -split "`n") | Select-Object -Last 40 }')
[void]$sb.AppendLine('  ''cikis: '' + $r.kod')
[void]$sb.AppendLine('  exit $r.kod')
[void]$sb.AppendLine('} finally {')
[void]$sb.AppendLine('  Remove-Item -Recurse -Force -LiteralPath $w -ErrorAction SilentlyContinue')
[void]$sb.AppendLine('  Remove-Item -Force -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue')
[void]$sb.AppendLine('}')
$metin = $sb.ToString()
if ($metin -match '[^\x00-\x7F]') { Write-Host 'Konuk betiğinde ASCII dışı karakter var (Kaynak/Ek dosyaları base64 olduğundan yalnız argümanlar olabilir); argümanları ASCII yaz.'; exit 2 }

$gecici = Join-Path $env:TEMP "dao-java-$kimlik"
New-Item -ItemType Directory -Force $gecici | Out-Null
$konukBetik = Join-Path $gecici "dao-java-$kimlik.ps1"
[IO.File]::WriteAllText($konukBetik, $metin, (New-Object Text.ASCIIEncoding))
$cikti = Join-Path $gecici 'cikti.txt'
$kod = 1
try {
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Yonetim, 'script', $konukBetik) `
        -RedirectStandardOutput $cikti -RedirectStandardError "$cikti.err" -NoNewWindow -PassThru
    if (-not $p.WaitForExit($ZamanAsimiDk * 60000)) {
        & taskkill.exe /T /F /PID $p.Id | Out-Null
        Write-Host "ZAMAN AŞIMI ($ZamanAsimiDk dk): konuk çağrısı sonlandırıldı."
        $kod = 4
    } else { $kod = $p.ExitCode }
    if (Test-Path $cikti) { Get-Content -LiteralPath $cikti -Encoding UTF8 }
    if ((Test-Path "$cikti.err") -and (Get-Item "$cikti.err").Length) { '--- yönetim betiği hata çıktısı'; Get-Content -LiteralPath "$cikti.err" -Encoding UTF8 | Select-Object -Last 20 }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $gecici -ErrorAction SilentlyContinue
    $kisaKopya = Join-Path (Split-Path $Yonetim) ".tmp\dao-java-$kimlik.ps1"
    Remove-Item -Force -LiteralPath $kisaKopya -ErrorAction SilentlyContinue
}
exit $kod
