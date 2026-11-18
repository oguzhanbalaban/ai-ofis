<#
parola-yukle.ps1 - Araç kitinin parolalarını kullanıcının kendi bağlantı dosyalarından okuyup YALNIZCA bu PowerShell
oturumunun ortam değişkenlerine koyar. Hiçbir şey yazdırmaz, dosyaya yazmaz. Nokta ile çağır:

  . .\araclar\sap\parola-yukle.ps1                       # DAO_BO_PAROLA (BO Administrator) + DAO_DB_PAROLA (SQL sa)
  . .\araclar\sap\parola-yukle.ps1 -Veritabani dsadmin   # DAO_DB_PAROLA = SQL Server dsadmin (sa | boadmin | dsadmin | ipsadmin)
  . .\araclar\sap\parola-yukle.ps1 -Veritabani iq-boadmin   # SAP IQ boadmin (iq-boadmin | iq-dsadmin | iq-dba)

Kaynaklar: H:\VMs\BAGLANTI-BILGILERI.md ve C:\VMs\IQRHEL\local.settings.ps1 (kullanıcının dosyaları; değiştirilmez).
Bulunamayan değer için yalnızca hangi değişkenin boş kaldığını söyler.
#>
param(
    [ValidateSet('sa', 'boadmin', 'dsadmin', 'ipsadmin', 'iq-boadmin', 'iq-dsadmin', 'iq-dba')][string]$Veritabani = 'sa',
    [string]$BaglantiDosyasi = 'H:\VMs\BAGLANTI-BILGILERI.md',
    [string]$IqAyar = 'C:\VMs\IQRHEL\local.settings.ps1'
)
$metin = ''
if (Test-Path -LiteralPath $BaglantiDosyasi) { $metin = [IO.File]::ReadAllText($BaglantiDosyasi, [Text.Encoding]::UTF8) }

$m = [regex]::Match($metin, '\|\s*CMC[^\r\n]*?`Administrator`\s*/\s*`([^`]+)`')
if ($m.Success) { $env:DAO_BO_PAROLA = $m.Groups[1].Value } else { Write-Host 'DAO_BO_PAROLA bulunamadı (BAGLANTI-BILGILERI.md > SAPBO-SRV > CMC satırı).' }

$env:DAO_DB_PAROLA = $null
if ($Veritabani -like 'iq-*') {
    $ad = @{ 'iq-boadmin' = 'IqBoPassword'; 'iq-dsadmin' = 'IqDsPassword'; 'iq-dba' = 'IqDbaPassword' }[$Veritabani]
    if (Test-Path -LiteralPath $IqAyar) {
        $iq = [IO.File]::ReadAllText($IqAyar)
        $m = [regex]::Match($iq, '\$' + $ad + '\s*=\s*[''"]([^''"]+)[''"]')
        if ($m.Success) { $env:DAO_DB_PAROLA = $m.Groups[1].Value }
    }
} else {
    $satir = [regex]::Match($metin, '\|\s*SQL girişleri\s*\|[^\r\n]*')
    if ($satir.Success) {
        $m = [regex]::Match($satir.Value, '`' + [regex]::Escape($Veritabani) + '`\s*/\s*`([^`]+)`')
        if ($m.Success) { $env:DAO_DB_PAROLA = $m.Groups[1].Value }
    }
}
if (-not $env:DAO_DB_PAROLA) { Write-Host "DAO_DB_PAROLA bulunamadı ($Veritabani)." }
