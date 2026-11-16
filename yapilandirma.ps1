# Dağıtılan JSON şablonlarını değiştirmeden kişisel yapılandırmayı saklar.
function Yapilandirma-Yolu([string]$Yol, [switch]$Yaz) {
    if (-not $Yol) { return $Yol }
    foreach ($ad in @('ayarlar', 'kadro', 'projeler')) {
        $sablon = Join-Path $PSScriptRoot "$ad.json"
        if ([IO.Path]::GetFullPath($Yol) -ieq $sablon) {
            $yerel = Join-Path $PSScriptRoot "$ad.yerel.json"
            if ($Yaz -or (Test-Path -LiteralPath $yerel) -or (Test-Path -LiteralPath "$yerel.bak")) { return $yerel }
        }
    }
    return $Yol
}
