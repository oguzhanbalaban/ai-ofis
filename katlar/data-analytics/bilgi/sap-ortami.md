> Örnek ortam: bu dosyayı kendi SAP Data Services / BusinessObjects / veritabanı ortamınıza göre düzenleyin (sunucu adları, adresler, portlar, klasörler). Parola yazmayın; bağlantı bilgileri BAGLANTI-BILGILERI.md dosyasında (Git'e eklenmez).

# SAP laboratuvar ortamı — Data and Analytics Office

Ekibin çalıştığı SAP Data Services / BusinessObjects ortamı. Her SAP işinden önce oku.
Parolalar burada YOK: `H:\VMs\BAGLANTI-BILGILERI.md` (BO, SQL Server, Windows) ve `C:\VMs\IQRHEL\local.settings.ps1` (SAP IQ).
Araçlar için parolaları ortam değişkenine almanın yolu: `. {KAT_KOKU}\araclar\sap\parola-yukle.ps1`
(hiçbir şey yazdırmaz). Araç kullanımı: `araclar\sap\BENIOKU.md`.

## Makineler

| Makine | IP | Ne var | VM dosyası / yönetim |
|---|---|---|---|
| SAPBO-SRV | 192.168.1.50 | **SAP BO BI 2025 Patch 12** (14.4.0.5749): CMS 6400, SIA 6410, Tomcat 8080 (CMC, BI Launchpad, `/biprws`); **BI 2025 Client Tools P12** (IDT, WebI Rich Client, SL SDK java); **SQL Server 2022** 1433 | `H:\VMs\SAPBO\SAPBO.vmx` · `H:\VMs\bovm.ps1` |
| DS-SRV | 192.168.1.52 | **IPS 4.3** + **SAP Data Services 4.3 SP1** (14.3.1.330): Designer, Job Server (`DI_JOBSERVICE`), Management Console 8080, CMS 6400 | `C:\VMs\DSSRV\DSSRV.vmx` · `C:\VMs\DSSRV\dsvm.ps1` |
| IQ-SRV | 192.168.1.54 | **SAP IQ 16.2** (RHEL 9.9): `iqlab` 2638, `iqdemo` 2640 | `C:\VMs\IQRHEL\IQSRV.vmx` · `D:\SapIqLab\infra\host\iqssh.py` |

Ağ: VMware NAT VMnet8 192.168.1.0/24; ana makine bu ağa doğrudan erişir (REST, SQL, IQ).

## Açma, kapatma ve sağlık kontrolü

1. `& 'C:\Program Files (x86)\VMware\VMware Player\vmrun.exe' list` — hangi VM açık? Açık olanı kullanıcı açmış olabilir: kapatma.
2. Açma sırası **SAPBO-SRV → DS-SRV** (DS-SRV'nin CMS, audit ve repository veritabanları SAPBO-SRV'deki SQL Server'da).
   `& H:\VMs\bovm.ps1 start`, birkaç dakika sonra `& C:\VMs\DSSRV\dsvm.ps1 start`. SAPBO-SRV diski yavaş HDD: hizmetlerin
   kalkması 5-10 dakika sürebilir. IQ kaynaklı iş varsa IQ-SRV de açık olmalı (`vmrun -T player start C:\VMs\IQRHEL\IQSRV.vmx nogui`).
3. Sağlık: `Test-NetConnection 192.168.1.50 -Port 6400` (CMS), `-Port 8080` (Tomcat), `-Port 1433` (SQL);
   REST: `python -I araclar\sap\bo_rest.py ping`. DS-SRV: 6400 ve `http://192.168.1.52:8080/DataServices` (HTTP 200).
4. **CMS "Running" ama 6400 dinlemiyor** → SQL hazırken SIA'yı yeniden başlat: `& H:\VMs\bovm.ps1 run 'Restart-Service BOEXI40SIASAPBOSRV'`
   (DS-SRV: `BOEXI40SIADSSRVSIA`). **CMC HTTP 500** → Tomcat'i durdur, `tomcat\work\Catalina\localhost\*` sil, başlat.
5. Kapatma: yalnızca bu işte senin açtığın VM'i, başka iş beklemiyorsa `vmrun -T player stop <vmx> soft`. IQ-SRV'de önce
   `systemctl stop sapiq-*`. Emin değilsen açık bırak.

## SAPBO-SRV ayrıntıları

- CMS adı (SDK/IDT): `SAPBO-SRV:6400`, kimlik doğrulama Enterprise (`secEnterprise`), kullanıcı `Administrator`.
- REST: `http://192.168.1.50:8080/biprws` (logon `/logon/long`, raylight `/raylight/v1`, CMS sorgusu `/v1/cmsquery`).
- BI Launchpad: `http://192.168.1.50:8080/BOE/BI` · CMC: `http://192.168.1.50:8080/BOE/CMC`.
- Sunucudaki Java: `C:\Program Files (x86)\SAP BusinessObjects\SAP BusinessObjects Enterprise XI 4.0\win64_x64\sapjvm\bin`
  (javac var, Java 8: `--release` bayrağını tanımaz). SL SDK sınıf yolu: `...\SL SDK\java\sl_sdk.jar` (BOE SDK sınıflarını da getirir).
- SQL Server 2022 (`192.168.1.50,1433`, "Trust server certificate"): girişler `sa`, `boadmin`, `dsadmin`, `ipsadmin`.
  Veritabanları: `BOE_CMS`, `BOE_AUDIT` (BO), `IPS_CMS`, `IPS_AUDIT`, `DS_REPO` (DS-SRV için). **Bunlar sistem veritabanıdır:
  içlerine tablo açma, veri değiştirme.** Ekibin veri ambarı için ayrı veritabanı: **`DA_DWH`** (yoksa ag açar; hazırlama
  katmanı için `DA_STG` açılabilir). SQL Server bellek sınırı 2 GB: büyük yüklemelerde dikkat.
- SAPBO-SRV'deki 64-bit sistem DSN'leri: `BOE_CMS`, `BOE_AUDIT` (SQL), `IQDEMO`, `IQLAB` (SAP IQ). SQL Server'a evren bağlantısı
  için DSN ya da JDBC gerekir; ara katman adını `cscheck list` ile doğrula (bkz. BENIOKU).
- CMS'te kullanıcının/önceki projenin hazır içeriği (DOKUNMA, okuyabilirsin): bağlantı `Connections/IQDEMO_GROUPO`, evren
  `Universes/IQDEMO_GROUPO.unx` (GROUPO: 17 boyut + 3 ölçü), klasör `Public Folders/IQ Lab`, WebI `IQ GROUPO - Bölge Ürün Ciro`.

## DS-SRV ayrıntıları

- Servisler: `BOEXI40SIADSSRVSIA` (SIA), `BOEXI40Tomcat`, `DI_JOBSERVICE` (Data Services Job Service).
- Management Console: `http://192.168.1.52:8080/DataServices` (Administrator, Enterprise). IPS CMC: `http://192.168.1.52:8080/BOE/CMC`.
- Yerel repository: `DS_REPO` (SAPBO-SRV SQL Server, kullanıcı `dsadmin`, tür Microsoft_SQL_Server), `AL_VERSION 14.3.1.0000`.
  DS-SRV'deki 64-bit DSN'ler: `IPS_CMS`, `IPS_AUDIT`, `DS_REPO` (hepsi 192.168.1.50,1433).
- Komut satırı araçları DS kurulumunun `bin` klasöründe (PATH'te): `al_engine.exe` (ATL/XML içe-dışa aktarma ve iş çalıştırma
  motoru), `RepoManBatch.exe` (repository oluşturma/doğrulama: `-U -P -S -Q -N -t local -c|-v`).
- **İş çalıştırma ve ATL içe aktarma yolu henüz ekip tarafından doğrulanmadı.** Olası yollar: (a) `al_engine` ile ATL içe aktarma
  (`-f<dosya>` ve repository bağlantı bayrakları), (b) Management Console'da işin "Export Execution Command" ile ürettiği
  komut dosyası (`<LINK_DIR>\log\*.bat`), (c) Management Console web servisleri (Run_Batch_Job / Get_BatchJob_Status;
  Administrator > Web Services'ta etkinleştirilmeli). İlk çalışan yolu bulan ds-gelistirici adım adım `ds-tarifi.md` olarak
  teslim eder; tarif doğrulandıktan sonra bu bölüme işlenir.
- Bilinen sorunlar: `DS\bin\BCM-4-0.dll` sürüm hattı IPS ile aynı olmalı (Designer "Unable to locate BOE platform components");
  GUI araçlarını (`AWServerConfig.exe` vb.) `-h`/`-?` ile çağırma — görünmez diyalogda asılı kalır. Designer görünmez vmrun
  oturumunda kullanılamaz: komut satırı yollarını kullan.

## IQ-SRV ayrıntıları

- `iqdemo` (2640): GROUPO örnek satış verisi (126 müşteri, 648 sipariş, 1097 kalem, 10 ürün) — kaynak olarak uygun.
- `iqlab` (2638): laboratuvar veritabanı; `dsadmin` kullanıcısının tablo oluşturma yetkisi var (IQ hedefli ETL için).
- Kullanıcılar: `boadmin` (okuma, BO bağlantısı), `dsadmin` (yazma), `DBA` (yalnız yönetim). Belgeler `D:\SapIqLab\docs`
  (`BO-ENTEGRASYON.md`, `ISLETIM.md`, `TUZAKLAR.md`).
- **2642 portlu örnek DWH kullanıcının müşteri şemasıdır: iş açıkça istemedikçe kullanma, içeriğini hiçbir çıktıya kopyalama.**

## Ekip adlandırma kuralları

| Nesne | Kural | Örnek |
|---|---|---|
| CMS klasörleri | `Public Folders/DA Office/<konu>`, `Universes/DA Office`, `Connections/DA Office` | `DA Office/Satış` |
| Evren / bağlantı | `DA_` öneki, büyük harf | `DA_SATIS.unx`, `DA_SQL_DWH` |
| WebI belgesi | iş diliyle ad, DA Office klasöründe | "Bölge Bazında Aylık Ciro" |
| DS nesneleri | `DA_` öneki + tür: `DA_JOB_`, `DA_WF_`, `DA_DF_`, datastore `DA_DS_`; proje `DA_OFFICE` | `DA_JOB_SATIS_YUKLE` |
| Veritabanı | `DA_DWH` (ambar), `DA_STG` (hazırlama); tablolar `DIM_`, `FACT_`, `STG_` | `DA_DWH.dbo.FACT_SATIS` |
| Test nesneleri | `DA_TEST_` öneki; iş sonunda silinir | `DA_TEST_RAPOR` |

Kullanıcının ve önceki projelerin nesnelerine (yukarıdaki IQ Lab içeriği dahil) dokunma; ekip yalnızca kendi `DA` nesnelerini değiştirir/siler.

## BO 2025 REST ve SDK tuzakları (13.11.2026'da yaşandı)

- REST klasör AÇAMAZ ve belge SİLEMEZ (`DELETE /infostore` 405) → BOE Java SDK (`araclar\sap\boe\BoeTool.java`).
- Public Folders kökü (SI_ID 23) belge kabul etmez; belge bir alt klasörde olmalı.
- `POST /raylight/v1/documents` boş belgeyi hemen kaydeder (yarım kalan denemeler CMS'te kalır: temizle).
- `GET .../specification` yalnız `text/xml` döner; sorgu `queriesTree xsi:type="queryspec:QueryDataNode"` → `bOQuery` →
  `resultObjects` ile eklenir. UNX nesne kimliği **ön eksiz** (`_Ays0...`); `DS0.DOxx` biçimi UNV içindir (yanlışı "yetki yok" hatası verir).
- Rapor tablosu: `@type: VTable`, `parentId` = `PageZone "Body"`, eksen `@role` yalnız `Row|Column|Body` (`Column` çalıştı).
- SL SDK: `DataType` hem businesslayer hem datafoundation paketinde var → açık import. `createDatabaseTable(niteleyici, sahip, tablo, df)`.
- IDT'de DSN listesi boşsa sürücü adı sorunu (IQ sürücüsü "Sybase IQ" adıyla da kayıtlı olmalı) — SDK ve cscheck DSN adıyla çalıştığı için etkilenmez.
- Sayısal yıl boyutu raporda `2,000` görünür → evrende metne çevir ya da WebI biçimini değiştir.

## vmrun ve konuk betiği tuzakları

- Konuğa giden .ps1 dosyalarında ASCII dışı karakter kullanma (aktarımda bozulur, ayrıştırma hatası).
- `vmrun runProgramInGuest`'e uzun `cmd /c ...` yazma (sona fazladan tırnak ekler); `bovm.ps1`/`dsvm.ps1` `script` komutunu kullan.
- vmrun konuk çağrısı bazen hiç dönmez: önce `vmrun checkToolsState <vmx>`; her çağrıyı zaman aşımıyla çalıştır.
- Çalışan bir günlük dosyasını doğrudan kopyalama: `fetch` komutu önce konukta kopyasını alır.
