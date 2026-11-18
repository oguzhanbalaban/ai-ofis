// Data and Analytics Office - BOE Java SDK yardimcisi (BI 2025). REST'in yapamadiklari: klasor acma, nesne silme.
// D:\SapIqLab\infra\guest\sapbo\slsdk\CreateFolder.java ve CleanupProbes.java (bu sunucuda calisti) genellestirildi.
// Parola stdin 1. satir (CMS Administrator). Kaynak ASCII tutulur.
// Kullanim (sap-java.ps1 -Arguman ile):
//   klasor "DA Office/Satis"        Public Folders altinda yolu acar (varsa kimligini yazar)
//   evren-klasor "DA Office"        Universes kok klasoru altinda klasor
//   baglanti-klasor "DA Office"     Connections kok klasoru altinda klasor
//   sorgu "SELECT SI_ID, SI_NAME, SI_KIND FROM CI_INFOOBJECTS WHERE ..."
//   sil <SI_ID> [<SI_ID> ...]       yalnizca ekip nesneleri: adi "DA" ile baslayan ya da "DA Office" klasoru altindaki
// Ilk arguman "cms=HOST:PORT" ise CMS adresi olur (varsayilan SAPBO-SRV:6400).
import com.crystaldecisions.sdk.framework.CrystalEnterprise;
import com.crystaldecisions.sdk.framework.IEnterpriseSession;
import com.crystaldecisions.sdk.occa.infostore.IInfoObject;
import com.crystaldecisions.sdk.occa.infostore.IInfoObjects;
import com.crystaldecisions.sdk.occa.infostore.IInfoStore;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class BoeTool {
    static final int PUBLIC_FOLDERS = 23;
    // BO 4.x kok klasor CUID'leri (bulunamazsa ada gore aranir)
    static final String CUID_UNIVERSES = "AWigQI18AAZJoXfRHLzWJ2c";
    static final String CUID_CONNECTIONS = "AZVXOgKIBEdOkiXzUuybja4";
    static IInfoStore store;

    public static void main(String[] a) throws Exception {
        List<String> args = new ArrayList<String>(Arrays.asList(a));
        String cms = "SAPBO-SRV:6400";
        if (!args.isEmpty() && args.get(0).startsWith("cms=")) cms = args.remove(0).substring(4);
        if (args.isEmpty()) { System.out.println("Kullanim: BoeTool klasor|evren-klasor|baglanti-klasor|sorgu|sil ..."); System.exit(2); }
        String pw = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8)).readLine();
        pw = pw == null ? "" : pw.replace("\uFEFF", "").trim();
        IEnterpriseSession es = CrystalEnterprise.getSessionMgr().logon("Administrator", pw, cms, "secEnterprise");
        try {
            store = (IInfoStore) es.getService("InfoStore");
            String k = args.get(0);
            if (k.equals("klasor")) System.out.println("KLASOR " + yol(PUBLIC_FOLDERS, args.get(1), "CI_INFOOBJECTS"));
            else if (k.equals("evren-klasor")) System.out.println("KLASOR " + yol(kok(CUID_UNIVERSES, "Universes"), args.get(1), "CI_APPOBJECTS"));
            else if (k.equals("baglanti-klasor")) System.out.println("KLASOR " + yol(kok(CUID_CONNECTIONS, "Connections"), args.get(1), "CI_APPOBJECTS"));
            else if (k.equals("sorgu")) {
                IInfoObjects r = store.query(args.get(1));
                for (int i = 0; i < r.size(); i++) {
                    IInfoObject o = (IInfoObject) r.get(i);
                    System.out.println(o.getID() + "\t" + o.getKind() + "\t" + o.getTitle() + "\tust=" + o.getParentID());
                }
                System.out.println("toplam: " + r.size());
            } else if (k.equals("sil")) {
                for (String id : args.subList(1, args.size())) sil(Integer.parseInt(id.trim()));
            } else { System.out.println("Bilinmeyen komut: " + k); System.exit(2); }
        } finally {
            es.logoff();
        }
    }

    static int kok(String cuid, String ad) throws Exception {
        IInfoObjects r = store.query("SELECT SI_ID FROM CI_APPOBJECTS WHERE SI_CUID='" + cuid + "'");
        if (r.size() > 0) return ((IInfoObject) r.get(0)).getID();
        r = store.query("SELECT SI_ID FROM CI_APPOBJECTS WHERE SI_KIND='Folder' AND SI_NAME='" + ad + "' ORDER BY SI_ID");
        if (r.size() > 0) { System.out.println("UYARI kok klasor CUID ile bulunamadi; ada gore secildi"); return ((IInfoObject) r.get(0)).getID(); }
        throw new IllegalStateException(ad + " kok klasoru bulunamadi");
    }

    static int yol(int ust, String yol, String tablo) throws Exception {
        for (String parca : yol.replace('\\', '/').split("/")) {
            parca = parca.trim();
            if (parca.isEmpty()) continue;
            String ad = parca.replace("'", "''");
            IInfoObjects r = store.query("SELECT SI_ID FROM " + tablo + " WHERE SI_KIND='Folder' AND SI_NAME='" + ad + "' AND SI_PARENTID=" + ust);
            if (r.size() > 0) { ust = ((IInfoObject) r.get(0)).getID(); continue; }
            IInfoObjects coll = store.newInfoObjectCollection();
            IInfoObject f = coll.add("CrystalEnterprise.Folder");
            f.setTitle(parca);
            f.setDescription("Data and Analytics Office");
            f.setParentID(ust);
            store.commit(coll);
            ust = f.getID();
            System.out.println("olusturuldu: " + parca + " (" + ust + ")");
        }
        return ust;
    }

    static IInfoObject bul(int id) throws Exception {
        for (String t : new String[] {"CI_INFOOBJECTS", "CI_APPOBJECTS", "CI_SYSTEMOBJECTS"}) {
            IInfoObjects r = store.query("SELECT SI_ID, SI_NAME, SI_KIND, SI_PARENTID FROM " + t + " WHERE SI_ID=" + id);
            if (r.size() > 0) return (IInfoObject) r.get(0);
        }
        return null;
    }

    static void sil(int id) throws Exception {
        IInfoObject o = bul(id);
        if (o == null) { System.out.println("yok: " + id); return; }
        boolean ekip = o.getTitle().startsWith("DA_") || o.getTitle().startsWith("DA ");
        int ust = o.getParentID();
        for (int i = 0; i < 15 && !ekip && ust > 0; i++) {
            IInfoObject p = bul(ust);
            if (p == null) break;
            if (p.getTitle().equals("DA Office")) ekip = true;
            ust = p.getParentID();
        }
        if (!ekip) { System.out.println("REDDEDILDI (ekip nesnesi degil): " + id + " " + o.getKind() + " " + o.getTitle()); return; }
        System.out.println("siliniyor: " + o.getKind() + " " + o.getTitle() + " (" + id + ")");
        o.deleteNow();
    }
}
