// Data and Analytics Office - UNX evren olusturucu (SAP BI 2025 SL SDK, Java 8).
// D:/SapIqLab/infra/guest/sapbo/slsdk/IqUniverse.java (13.11.2026'da bu sunucuda calisti) genellestirildi.
// Tanim: UTF-8 ".unxspec" dosyasi (bkz. araclar/sap/BENIOKU.md ve ornek-groupo.unxspec).
// Parolalar stdin'den: 1. satir CMS kullanicisi, 2. satir veritabani (yalniz yeni baglanti olusturulurken).
// Calistirma: araclar/sap/sap-java.ps1 -Kaynak araclar/sap/unx/UnxBuilder.java -Ek <tanim>.unxspec -Arguman <tanim>.unxspec
// Kaynak dosya ASCII tutulur (konuga aktarim); Turkce adlar tanim dosyasinda. Yorumlarda ters bolu kullanma (Java \ u kacisi).
import com.crystaldecisions.sdk.framework.CrystalEnterprise;
import com.crystaldecisions.sdk.framework.IEnterpriseSession;
import com.sap.sl.sdk.authoring.businesslayer.*;
import com.sap.sl.sdk.authoring.businesslayer.DataType;   // datafoundation.DataType ile cakismasin
import com.sap.sl.sdk.authoring.cms.CmsResourceService;
import com.sap.sl.sdk.authoring.connection.ConnectionFactory;
import com.sap.sl.sdk.authoring.connection.RelationalConnection;
import com.sap.sl.sdk.authoring.datafoundation.*;
import com.sap.sl.sdk.authoring.local.LocalResourceService;
import com.sap.sl.sdk.framework.SlContext;
import com.sap.sl.sdk.framework.cms.CmsSessionService;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.*;

public class UnxBuilder {
    static DataFoundationFactory dff;
    static BusinessLayerFactory blf;
    static Map<String, Folder> folders = new HashMap<String, Folder>();

    // ---------------------------------------------------------------- tanim dosyasi
    static Map<String, String> tek = new LinkedHashMap<String, String>();
    static Map<String, List<String>> cok = new LinkedHashMap<String, List<String>>();
    static final Set<String> COKLU = new HashSet<String>(Arrays.asList("parametre", "tablo", "birlestirme", "klasor", "boyut", "olcu"));

    static void oku(String yol) throws Exception {
        int no = 0;
        for (String satir : Files.readAllLines(Paths.get(yol), StandardCharsets.UTF_8)) {
            no++;
            String s = satir.replace("\uFEFF", "").trim();
            if (s.isEmpty() || s.startsWith("#")) continue;
            int i = s.indexOf(':');
            if (i < 1) throw new IllegalArgumentException("Satir " + no + ": 'anahtar: deger' bekleniyordu: " + s);
            String k = s.substring(0, i).trim().toLowerCase(Locale.ROOT);
            String v = s.substring(i + 1).trim();
            if (COKLU.contains(k)) {
                if (!cok.containsKey(k)) cok.put(k, new ArrayList<String>());
                cok.get(k).add(v);
            } else tek.put(k, v);
        }
    }
    static String al(String k, String vars) { String v = tek.get(k); return (v == null || v.isEmpty()) ? vars : v; }
    static List<String> liste(String k) { List<String> l = cok.get(k); return l == null ? new ArrayList<String>() : l; }
    static String[] parcala(String v, int en) {
        String[] p = v.split("\\|", -1);
        for (int i = 0; i < p.length; i++) p[i] = p[i].trim();
        if (p.length < en) throw new IllegalArgumentException("En az " + en + " alan ('|' ile) gerekli: " + v);
        return p;
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) { System.out.println("Kullanim: UnxBuilder <tanim.unxspec>"); System.exit(2); }
        oku(args[0]);
        String ad = al("evren", null);
        if (ad == null) throw new IllegalArgumentException("'evren:' satiri zorunlu");
        String dir = "C:\\Install\\da-office\\unx\\" + ad.replaceAll("[^A-Za-z0-9_.-]", "_") + "\\";
        new File(dir).mkdirs();

        BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String cmsPw = satir(in), dbPw = satir(in);
        String cmsAdi = al("cms", "SAPBO-SRV:6400"), kullanici = al("cms_kullanici", "Administrator");

        SlContext ctx = SlContext.create();
        IEnterpriseSession es = CrystalEnterprise.getSessionMgr().logon(kullanici, cmsPw, cmsAdi, "secEnterprise");
        try {
            ctx.getService(CmsSessionService.class).setSession(es);
            LocalResourceService local = ctx.getService(LocalResourceService.class);
            CmsResourceService cms = ctx.getService(CmsResourceService.class);
            dff = ctx.getService(DataFoundationFactory.class);
            blf = ctx.getService(BusinessLayerFactory.class);

            // 1) Baglanti: mevcut (CMS yolu) ya da yeni
            String cnxPath = al("mevcut_baglanti", null);
            RelationalConnection cnx = null;
            if (cnxPath == null) {
                String cnxAdi = al("baglanti", ad);
                cnx = ctx.getService(ConnectionFactory.class).createRelationalConnection(
                        cnxAdi, al("ara_katman", null), al("surucu", "ODBC Drivers"));
                cnx.setDescription(al("baglanti_aciklama", "Data and Analytics Office"));
                for (String p : liste("parametre")) {
                    int i = p.indexOf('=');
                    if (i < 1) throw new IllegalArgumentException("parametre: AD = DEGER bekleniyordu: " + p);
                    cnx.getParameter(p.substring(0, i).trim()).setValue(p.substring(i + 1).trim());
                }
                if (dbPw != null && !dbPw.isEmpty()) cnx.getParameter("PASSWORD").setValue(dbPw);
                local.save(cnx, dir + cnxAdi + ".cnx", true);
                cnxPath = yayimla(cms, dir + cnxAdi + ".cnx", CmsResourceService.CONNECTIONS_ROOT, al("baglanti_klasoru", ""));
                System.out.println("BAGLANTI yayimlandi: " + cnxPath);
            } else System.out.println("BAGLANTI (mevcut): " + cnxPath);
            String kisayol = cms.createShortcut(cnxPath, dir);

            // 2) Veri temeli
            MonoSourceDataFoundation df = dff.createMonoSourceDataFoundation(ad, kisayol);
            df.setDescription(al("aciklama", ""));
            String niteleyici = al("niteleyici", "");
            for (String t : liste("tablo")) {
                String[] p = t.split("\\.");
                String q = niteleyici, sahip, tablo;
                if (p.length == 3) { q = p[0]; sahip = p[1]; tablo = p[2]; }
                else if (p.length == 2) { sahip = p[0]; tablo = p[1]; }
                else { sahip = ""; tablo = p[0]; }
                DatabaseTable tb = dff.createDatabaseTable(q, sahip, tablo, df);
                System.out.println("  tablo " + tb.getName() + " (" + tb.getColumns().size() + " sutun)");
            }
            for (String b : liste("birlestirme")) {
                String[] p = b.split(";");
                SQLJoin j = dff.createSqlJoin(p[0].trim(), df);
                Cardinality kd = kardinalite(p.length > 1 ? p[1].trim() : "N-1");
                j.setCardinality(kd);
                System.out.println("  birlestirme " + p[0].trim() + " (" + kd + ")");
            }
            int i = 0;
            for (Table t : df.getTables()) {
                TableView v = dff.createTableView(t, df.getMasterView());
                v.setX((i % 4) * 260); v.setY((i / 4) * 280); v.setWidth(200); i++;
            }
            local.save(df, dir + ad + ".dfx", true);
            System.out.println("VERI TEMELI kaydedildi (" + df.getTables().size() + " tablo)");

            // 3) Is katmani
            RelationalBusinessLayer bl = blf.createRelationalBusinessLayer(ad, dir + ad + ".dfx");
            bl.setDescription(al("aciklama", ""));
            Folder kok = bl.getRootFolder();
            for (String k : liste("klasor")) klasor(k, kok);
            int nb = 0, no = 0;
            for (String d : liste("boyut")) {
                String[] p = parcala(d, 3);
                Dimension x = blf.createBlItem(Dimension.class, p[1], klasor(p[0], kok));
                x.setDataType(veriTipi(p.length > 3 ? p[3] : "STRING"));
                x.setAccessLevel(AccessLevel.PUBLIC);
                x.setState(ItemState.ACTIVE);
                ((RelationalBinding) x.getBinding()).setSelect(p[2]);
                if (p.length > 4) aciklama(x, p[4]);
                nb++;
            }
            for (String m : liste("olcu")) {
                String[] p = parcala(m, 3);
                Measure x = blf.createBlItem(Measure.class, p[1], klasor(p[0], kok));
                x.setDataType(veriTipi(p.length > 3 && !p[3].isEmpty() ? p[3] : "NUMERIC"));
                x.setAccessLevel(AccessLevel.PUBLIC);
                x.setState(ItemState.ACTIVE);
                ((RelationalBinding) x.getBinding()).setSelect(p[2]);
                if (p.length > 4) aciklama(x, p[4]);
                no++;
            }
            local.save(bl, dir + ad + ".blx", true);
            System.out.println("IS KATMANI kaydedildi (" + nb + " boyut, " + no + " olcu)");
            String unx = yayimla(cms, dir + ad + ".blx", CmsResourceService.UNIVERSES_ROOT, al("evren_klasoru", ""));
            System.out.println("EVREN yayimlandi: " + unx);

            local.close(bl); local.close(df); if (cnx != null) local.close(cnx);
        } finally {
            ctx.close();
            es.logoff();
        }
    }

    static String satir(BufferedReader in) throws Exception {
        String s = in.readLine();
        return s == null ? null : s.replace("\uFEFF", "").trim();
    }

    // Alt klasore yayimla; klasor yoksa ya da SDK reddederse kok klasore yayimla ve uyar.
    static String yayimla(CmsResourceService cms, String yerel, String kok, String alt) {
        if (alt != null && !alt.isEmpty()) {
            try { return cms.publish(yerel, kok + "/" + alt, true); }
            catch (Exception e) {
                System.out.println("UYARI '" + kok + "/" + alt + "' klasorune yayimlanamadi (" + e.getMessage()
                        + "); kok klasore yayimlaniyor. Klasoru acmak icin: BoeTool evren-klasor / baglanti-klasor");
            }
        }
        return cms.publish(yerel, kok, true);
    }

    static Folder klasor(String yol, Folder kok) {
        if (yol == null || yol.isEmpty()) return kok;
        Folder f = folders.get(yol);
        if (f != null) return f;
        Folder ust = kok;
        String birikim = "";
        for (String parca : yol.split("/")) {
            parca = parca.trim();
            if (parca.isEmpty()) continue;
            birikim = birikim.isEmpty() ? parca : birikim + "/" + parca;
            Folder v = folders.get(birikim);
            if (v == null) {
                v = blf.createBlItem(Folder.class, parca, ust);
                v.setState(ItemState.ACTIVE);
                folders.put(birikim, v);
            }
            ust = v;
        }
        return ust;
    }

    static Cardinality kardinalite(String s) {
        String k = s.toUpperCase(Locale.ROOT).replace(" ", "");
        String ad = k.equals("N-1") ? "CN_1" : k.equals("1-N") ? "C1_N" : k.equals("1-1") ? "C1_1" : k.equals("N-N") ? "CN_N" : k;
        try { return Cardinality.valueOf(ad); }
        catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Bilinmeyen kardinalite '" + s + "'. Gecerli: N-1, 1-N, 1-1, N-N ya da " + Arrays.toString(Cardinality.values()));
        }
    }

    static DataType veriTipi(String s) {
        try { return DataType.valueOf(s.toUpperCase(Locale.ROOT)); }
        catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Bilinmeyen veri tipi '" + s + "'. Gecerli: " + Arrays.toString(DataType.values()));
        }
    }

    static void aciklama(Object nesne, String metin) {
        try {
            Method m = nesne.getClass().getMethod("setDescription", String.class);
            m.invoke(nesne, metin);
        } catch (Exception e) {
            System.out.println("UYARI aciklama yazilamadi: " + e);
        }
    }
}
