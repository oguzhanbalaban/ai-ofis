# SAP araç kiti

Data and Analytics Office ajanlarının SAP sistemleriyle çalışmak için kullandığı araçlar. Hepsi ana makinede çalışır.
Ortam bilgisi: `..\..\bilgi\sap-ortami.md`. Önce parolaları oturuma al (hiçbir şey yazdırmaz):

```powershell
cd {KAT_KOKU}
. .\araclar\sap\parola-yukle.ps1                      # DAO_BO_PAROLA + DAO_DB_PAROLA (SQL sa)
. .\araclar\sap\parola-yukle.ps1 -Veritabani iq-boadmin   # DAO_DB_PAROLA = SAP IQ boadmin
```

Parolaları komut satırına, dosyalara ve raporlara yazma; araçlar ortam değişkeninden okur.

| Araç | Ne yapar | Durum |
|---|---|---|
| `bo_rest.py` | BO BI 2025 REST: ping, CMS sorgusu, evren/nesne listesi, WebI oluştur/yenile/dışa aktar | Belge oluşturma ve yenileme yöntemi 13.11.2026'da bu sunucuda çalıştı (SapIqLab); bu genel sürüm ilk kullanımda doğrulanmalı. `disa-aktar` doğrulanmadı |
| `unx\UnxBuilder.java` | `.unxspec` tanımından bağlantı + veri temeli + iş katmanı + UNX yayımı (SL SDK) | Yöntem 13.11.2026'da çalıştı (IqUniverse.java); bu genel sürüm ilk kullanımda doğrulanmalı |
| `boe\BoeTool.java` | BOE Java SDK: klasör aç, CMS sorgusu, ekip nesnesi sil | Klasör açma ve silme yöntemi çalıştı; evren/bağlantı klasörü kökü doğrulanmalı |
| `sap-java.ps1` | Bir Java programını SAPBO-SRV'de SL/BOE SDK sınıf yoluyla derleyip çalıştırır | Yeni (run-iq-universe.ps1 yönteminin genellemesi) |
| `sql.ps1` | SQL Server'a ana makineden sorgu (.NET SqlClient), CSV çıktısı | Yeni |
| `parola-yukle.ps1` | Parolaları kullanıcının bağlantı dosyalarından oturum ortam değişkenine alır | Yeni |

Bir aracı ilk kez kullanan ve bir hata düzelten ajan, düzeltmeyi kendi çıktı klasöründe önerir (bu klasördeki dosyaları
değiştirmez); kullanıcı ya da yönetici araç kitine işler.

## bo_rest.py

```powershell
python -I .\araclar\sap\bo_rest.py ping
python -I .\araclar\sap\bo_rest.py evrenler
python -I .\araclar\sap\bo_rest.py nesneler DA_GROUPO_ORNEK
python -I .\araclar\sap\bo_rest.py belgeler "DA Office"
python -I .\araclar\sap\bo_rest.py sorgu "SELECT SI_ID, SI_NAME FROM CI_INFOOBJECTS WHERE SI_KIND='Folder' AND SI_PARENTID=23"
python -I .\araclar\sap\bo_rest.py webi-olustur .\cikti\bolge-ciro.webi.json
python -I .\araclar\sap\bo_rest.py yenile 6012
python -I .\araclar\sap\bo_rest.py disa-aktar 6012 .\cikti\bolge-ciro.xlsx
```

WebI tanımı (`*.webi.json`, UTF-8):

```json
{
  "ad": "Bölge Bazında Ciro",
  "klasor": "DA Office/Satış",
  "evren": "DA_GROUPO_ORNEK",
  "veri_saglayici": "Satış",
  "sorgu": ["Bölge", "Ürün Adı", "Sipariş Yılı", "Adet", "Ciro"],
  "tablo": ["Bölge", "Ürün Adı", "Sipariş Yılı", "Adet", "Ciro"],
  "yenile": true,
  "varsa": "yeniden_kullan"
}
```

`klasor` yerine `klasor_id` verilebilir. Klasör yoksa önce BoeTool ile aç. Nesne adları evrendeki adlarla birebir aynı
olmalı (`nesneler` komutuyla bak). Filtre, istem, grafik ve çoklu sekme gibi ayrıntılar REST'te belge spesifikasyonu
(XML) ve rapor öğeleri üzerinden eklenir; aracın yapmadığını kendi Python kodunla (aynı oturum sınıfını kullanarak) yap ve
kodu teslim et.

## UnxBuilder (.unxspec)

```powershell
. .\araclar\sap\parola-yukle.ps1 -Veritabani iq-boadmin    # yeni bağlantı oluşturulacaksa veritabanı parolası
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\boe\BoeTool.java -Arguman evren-klasor,"DA Office"
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\boe\BoeTool.java -Arguman baglanti-klasor,"DA Office"
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\unx\UnxBuilder.java -Ek .\araclar\sap\unx\ornek-groupo.unxspec -Arguman ornek-groupo.unxspec
```

Tanım biçimi için `unx\ornek-groupo.unxspec` dosyasına bak: `evren`, `aciklama`, `evren_klasoru`, `baglanti` /
`mevcut_baglanti`, `ara_katman`, `surucu`, `parametre: AD = DEGER`, `baglanti_klasoru`, `niteleyici`,
`tablo: sahip.tablo` (ya da `niteleyici.sahip.tablo`), `birlestirme: <ifade> ; N-1|1-N|1-1|N-N`,
`boyut: <klasör> | <ad> | <SELECT> | <tip> | <açıklama>`, `olcu: <klasör> | <ad> | <SELECT> | [tip] | <açıklama>`.
Veri tipleri SL SDK `DataType` değerleridir (STRING, NUMERIC, DATE, DATETIME…; yanlış verilirse araç geçerli listeyi yazar).
Klasöre yayımlanamazsa araç kök klasöre yayımlar ve uyarır. Aynı adla yeniden çalıştırmak evreni günceller (üzerine yazar).

Ara katman adları: SAPBO-SRV'de doğrula —
`& H:\VMs\bovm.ps1 run '& "C:\Program Files (x86)\SAP BusinessObjects\SAP BusinessObjects Enterprise XI 4.0\win64_x64\cscheck.exe" list -m local'`
(SAP IQ için doğrulanmış: `Sybase IQ 16` / `ODBC Drivers`). SQL Server için SAPBO-SRV'de 64-bit sistem DSN'i (ODBC Driver 17)
gerekir; yoksa Database Administrator'dan iste.

## BoeTool

```powershell
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\boe\BoeTool.java -Arguman klasor,"DA Office/Satış"
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\boe\BoeTool.java -Arguman sorgu,"SELECT SI_ID, SI_NAME, SI_KIND FROM CI_INFOOBJECTS WHERE SI_PARENTID=23"
.\araclar\sap\sap-java.ps1 -Kaynak .\araclar\sap\boe\BoeTool.java -Arguman sil,6012,6013
```

`sil` yalnızca ekip nesnelerini siler (adı `DA_`/`DA ` ile başlayan ya da `DA Office` klasörü altındaki); diğerlerini reddeder.
Not: konuk betiği ASCII olmalı; `sap-java.ps1` argümanlarda ASCII dışı karakter görürse durur. Türkçe klasör adı gerekiyorsa
adı bir `-Ek` dosyasına yazıp programda oradan oku ya da ASCII ad kullan (`Satis`).

## sql.ps1

```powershell
. .\araclar\sap\parola-yukle.ps1 -Veritabani sa
.\araclar\sap\sql.ps1 -Veritabani DA_DWH -Sorgu "SELECT COUNT(*) AS n FROM dbo.FACT_SATIS"
.\araclar\sap\sql.ps1 -Dosya .\cikti\sql\ddl.sql -Veritabani DA_DWH -Yaz        # DDL/DML: -Yaz şart
.\araclar\sap\sql.ps1 -Dosya .\sql\mutabakat.sql -Csv .\kanitlar\mutabakat.csv
```

SAP IQ için ana makinede sürücü yok: IQ-SRV'de `dbisql` ile sorgu için `D:\SapIqLab\infra\host\iqssh.py` (bkz.
`D:\SapIqLab\docs\ISLETIM.md`) ya da SAPBO-SRV'deki `IQDEMO`/`IQLAB` DSN'leriyle konukta .NET ODBC kullan.

## Data Services

DS için hazır araç henüz yok; yol `bilgi\sap-ortami.md > DS-SRV ayrıntıları`'nda. DS-SRV'de komut: `& C:\VMs\DSSRV\dsvm.ps1 run '<ps>'`
ya da `script <x.ps1>` (ASCII). İlk çalışan ATL içe aktarma / iş çalıştırma / günlük okuma tarifi `ds-tarifi.md` olarak
teslim edilir ve buraya araç olarak eklenir.
