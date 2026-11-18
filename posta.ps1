<#
posta.ps1 - AI Ekip e-posta yardımcıları (uzman.ps1 ve eposta-kur.ps1 dot-source eder; ortak.ps1 önce yüklenmiş olmalı).

  durum\eposta.json : adres, sunucular ve DPAPI (bu Windows kullanıcısına bağlı) ile şifrelenmiş uygulama şifresi.
                      Kullanıcı eposta-kur.ps1 ile oluşturur; şifre düz metin olarak hiçbir yere yazılmaz.
  Okuma  : araclar\posta_oku.py (Python imaplib, salt okunur, iletileri okundu yapmaz)
  Gönderme: .NET SmtpClient (STARTTLS 587). Günlük sınır: ayarlar.json > iletisim.gunluk_eposta_siniri (varsayılan 30).
  Her gönderim durum\giden-postalar.jsonl dosyasına kaydedilir (alıcı, konu, sonuç; gövde değil).
#>

function Posta-Ayari {
    $a = Json-Oku (Join-Path $YolDurum 'eposta.json')
    if (-not $a -or -not $a.adres -or -not $a.sifre) { return $null }
    return $a
}
function Posta-Sifre($A) {
    $ss = ConvertTo-SecureString ([string]$A.sifre)
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { return ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) -replace '\s', '') }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
function Python-Exe {
    foreach ($ad in @('python', 'py')) { $c = Get-Command $ad -ErrorAction SilentlyContinue; if ($c) { return $c.Source } }
    return $null
}
# Gelen kutusundaki son iletiler: [pscustomobject]@{ basarili; iletiler; hata }
function Posta-Oku([int]$Adet = 20, [string]$Klasor = $env:TEMP) {
    $a = Posta-Ayari
    if (-not $a) { return [pscustomobject]@{ basarili = $false; iletiler = @(); hata = 'E-posta hesabı kurulmamış (eposta-kur.ps1).' } }
    $py = Python-Exe
    if (-not $py) { return [pscustomobject]@{ basarili = $false; iletiler = @(); hata = 'Python bulunamadı.' } }
    $betik = Join-Path $KodKok 'araclar\posta_oku.py'
    $cik = Join-Path $Klasor ('posta-{0}.json' -f [Guid]::NewGuid().ToString('N'))
    $err = "$cik.err"
    $env:EKIP_POSTA_ADRES = [string]$a.adres
    $env:EKIP_POSTA_IMAP = [string]$a.imap
    $env:EKIP_POSTA_SIFRE = Posta-Sifre $a
    try {
        $arg = if ($Adet -le 0) { 'dene' } else { [string]$Adet }
        $s = Surec-Calistir -Komut ('{0} -I {1} {2}' -f (Q $py), (Q $betik), $arg) -Cikti $cik -Hata $err -Klasor $Klasor -ZamanAsimiDk 3 -Etiket 'posta'
    } finally {
        Remove-Item env:EKIP_POSTA_SIFRE -ErrorAction SilentlyContinue
        Remove-Item env:EKIP_POSTA_ADRES -ErrorAction SilentlyContinue
        Remove-Item env:EKIP_POSTA_IMAP -ErrorAction SilentlyContinue
    }
    $metin = Metin-Oku $cik
    $hata = (Metin-Oku $err).Trim()
    Remove-Item -LiteralPath $cik, $err -Force -ErrorAction SilentlyContinue
    if ($s.kod -ne 0 -or -not $metin.Trim()) { return [pscustomobject]@{ basarili = $false; iletiler = @(); hata = "IMAP okunamadı (kod $($s.kod)): $(Kisalt $hata 300)" } }
    $j = $metin | ConvertFrom-Json
    return [pscustomobject]@{ basarili = $true; iletiler = @($j); hata = '' }
}
function Posta-Gonder {
    param([string[]]$Kime, [string[]]$Bilgi = @(), [string]$Konu, [string]$Govde, [string[]]$Ekler = @())
    $a = Posta-Ayari
    if (-not $a) { throw 'E-posta hesabı kurulmamış (eposta-kur.ps1).' }
    $port = 587; if ($a.smtp_port) { $port = [int]$a.smtp_port }
    $ileti = New-Object Net.Mail.MailMessage
    $ileti.From = New-Object Net.Mail.MailAddress([string]$a.adres)
    foreach ($k in $Kime) { $ileti.To.Add([string]$k) }
    foreach ($k in $Bilgi) { if ($k) { $ileti.CC.Add([string]$k) } }
    $ileti.Subject = $Konu
    $ileti.SubjectEncoding = [Text.Encoding]::UTF8
    $ileti.Body = $Govde
    $ileti.BodyEncoding = [Text.Encoding]::UTF8
    foreach ($e in $Ekler) { $ileti.Attachments.Add((New-Object Net.Mail.Attachment($e))) }
    $istemci = New-Object Net.Mail.SmtpClient([string]$a.smtp, $port)
    $istemci.EnableSsl = $true
    $istemci.Credentials = New-Object Net.NetworkCredential([string]$a.adres, (Posta-Sifre $a))
    $istemci.Timeout = 60000
    try { $istemci.Send($ileti) } finally { $ileti.Dispose(); $istemci.Dispose() }
}
function Posta-Kaydet($Kayit) {
    try { [IO.File]::AppendAllText((Join-Path $YolDurum 'giden-postalar.jsonl'), (($Kayit | ConvertTo-Json -Compress) + "`n"), $Utf8) } catch {}
}
