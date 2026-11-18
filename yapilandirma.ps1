# Dağıtılan JSON şablonlarını değiştirmeden kişisel yapılandırmayı saklar.
# Şirket binası: kod kökündeki ve her katın (katlar\<id>) ayarlar / kadro / projeler şablonları için kişisel kopya <ad>.yerel.json
function Yapilandirma-Yolu([string]$Yol, [switch]$Yaz) {
    if (-not $Yol) { return $Yol }
    $tam = [IO.Path]::GetFullPath($Yol)
    if ([IO.Path]::GetExtension($tam) -ne '.json') { return $Yol }
    $ad = [IO.Path]::GetFileNameWithoutExtension($tam)
    if (@('ayarlar', 'kadro', 'projeler') -notcontains $ad) { return $Yol }
    $klasor = [IO.Path]::GetDirectoryName($tam).TrimEnd('\')
    $kok = $PSScriptRoot.TrimEnd('\')
    $katlar = $kok + '\katlar\'
    $katMi = $klasor.StartsWith($katlar, [StringComparison]::OrdinalIgnoreCase) -and ($klasor.Substring($katlar.Length) -notmatch '\\') -and $klasor.Length -gt $katlar.Length
    if ($klasor -ine $kok -and -not $katMi) { return $Yol }
    $yerel = Join-Path $klasor "$ad.yerel.json"
    if ($Yaz -or (Test-Path -LiteralPath $yerel) -or (Test-Path -LiteralPath "$yerel.bak")) { return $yerel }
    return $Yol
}
