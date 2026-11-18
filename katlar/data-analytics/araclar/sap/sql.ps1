<#
sql.ps1 - SQL Server'a (varsayılan SAPBO-SRV 192.168.1.50,1433) ana makineden sorgu çalıştırır (.NET SqlClient; kurulum gerekmez).

  .\sql.ps1 -Sorgu "SELECT COUNT(*) AS n FROM dbo.FactSales" [-Veritabani DA_DWH] [-Kullanici sa] [-Sunucu 192.168.1.50,1433]
  .\sql.ps1 -Dosya .\sql\dogrulama.sql [-Csv .\kanitlar\sonuc.csv]
  .\sql.ps1 -Sorgu "..." -Yaz        # DDL/DML için (varsayılan salt okunur: SELECT/WITH dışındakini reddeder)

Parola: DAO_DB_PAROLA ortam değişkeni (dosyaya yazma). Çok sonuç kümesi desteklenir; her küme tablo olarak yazılır.
'GO' satırları toplu iş ayırıcı olarak işlenir.
#>
param(
    [string]$Sorgu,
    [string]$Dosya,
    [string]$Sunucu = '192.168.1.50,1433',
    [string]$Veritabani = 'master',
    [string]$Kullanici = 'sa',
    [string]$Csv,
    [int]$ZamanAsimiSn = 600,
    [int]$EnFazlaSatir = 200,
    [switch]$Yaz
)
$ErrorActionPreference = 'Stop'
if ($Dosya) { $Sorgu = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Dosya).Path) }
if (-not $Sorgu) { Write-Host 'Sorgu yok: -Sorgu ya da -Dosya ver.'; exit 2 }
if (-not $env:DAO_DB_PAROLA) { Write-Host 'Parola yok: DAO_DB_PAROLA ortam değişkenini ayarla.'; exit 5 }
$toplular = [regex]::Split($Sorgu, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() }
if (-not $Yaz) {
    foreach ($t in $toplular) {
        $temiz = [regex]::Replace($t, '(?s)/\*.*?\*/|--[^\r\n]*', '').Trim()
        if ($temiz -notmatch '^(?i)(SELECT|WITH|SET\s+NOCOUNT|DECLARE|EXEC\s+sp_help|EXEC\s+sp_columns)') {
            Write-Host 'Salt okunur kip: yalnızca SELECT/WITH çalışır. Değişiklik için -Yaz kullan.'; exit 2
        }
    }
}
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$b['Data Source'] = $Sunucu; $b['Initial Catalog'] = $Veritabani; $b['User ID'] = $Kullanici
$b['Password'] = $env:DAO_DB_PAROLA; $b['TrustServerCertificate'] = $true; $b['Connect Timeout'] = 20
$bag = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
try {
    $bag.Open()
    $tumu = New-Object System.Collections.Generic.List[object]
    foreach ($t in $toplular) {
        $k = $bag.CreateCommand(); $k.CommandText = $t; $k.CommandTimeout = $ZamanAsimiSn
        $o = $k.ExecuteReader()
        # DataTable.Load okuyucuyu bir sonraki sonuç kümesine kendisi geçirir (son kümede kapatır)
        while (-not $o.IsClosed) {
            if ($o.FieldCount -gt 0) {
                $tablo = New-Object System.Data.DataTable; $tablo.Load($o)
                $tumu.Add($tablo)
                Write-Host ("-- {0} satır" -f $tablo.Rows.Count)
                $tablo | Select-Object -First $EnFazlaSatir -Property ($tablo.Columns | ForEach-Object { $_.ColumnName }) | Format-Table -AutoSize | Out-String -Width 250 | Write-Host
            } else {
                Write-Host ("-- etkilenen satır: {0}" -f $o.RecordsAffected)
                if (-not $o.NextResult()) { break }
            }
        }
        if (-not $o.IsClosed) { $o.Close() }
    }
    if ($Csv -and $tumu.Count) {
        $tumu[0] | Select-Object -Property ($tumu[0].Columns | ForEach-Object { $_.ColumnName }) | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8
        Write-Host "CSV: $Csv"
    }
} catch {
    Write-Host "HATA: $($_.Exception.Message)"; exit 1
} finally { $bag.Dispose() }
