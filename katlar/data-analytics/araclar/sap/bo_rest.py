"""BO BI 2025 RESTful (biprws / raylight) komut satiri araci - Data and Analytics Office.

SAP IQ lab projesinde (D:\\SapIqLab\\infra\\host\\bo_rest.py) bu sunucuda dogrulanmis yontemin genellestirilmis hali.

Parola: DAO_BO_PAROLA ortam degiskeni ya da stdin'in ilk satiri (BO Administrator). Kullanici: DAO_BO_KULLANICI
(varsayilan Administrator). Adres: DAO_BO_URL (varsayilan http://192.168.1.50:8080/biprws).

Komutlar:
  ping                                   oturum ac/kapat, sunucu bilgisi
  sorgu "<CMS sorgusu>"                  /v1/cmsquery (ör. SELECT SI_ID, SI_NAME FROM CI_INFOOBJECTS WHERE SI_KIND='Webi')
  evrenler                               UNX evren listesi (kimlik, ad, klasor)
  nesneler <evren adi|kimlik>            evrendeki boyut/olcu/oznitelik ve kimlikleri
  belgeler [klasor yolu]                 WebI belgeleri (Public Folders altindaki yol, ör. "DA Office/Satis")
  klasor <yol>                           Public Folders altindaki klasorun kimligi (yoksa hata; acmak icin BoeTool klasor)
  webi-olustur <tanim.webi.json>         JSON tanimdan belge olustur/yenile/kaydet (bkz. BENIOKU.md)
  yenile <belge kimligi>                 belgeyi yenile, veri saglayici satir sayilarini yaz
  disa-aktar <belge kimligi> <dosya>     .xlsx | .pdf | .csv olarak indir (ilk kullanimda dogrula)

Cikti UTF-8. Hata durumunda cikis kodu 1 ve HTTP yanitinin ilk 800 karakteri.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get('DAO_BO_URL', 'http://192.168.1.50:8080/biprws').rstrip('/')
USER = os.environ.get('DAO_BO_KULLANICI', 'Administrator')
PUBLIC_FOLDERS = 23


class Bo:
    def __init__(self, password):
        body = json.dumps({'userName': USER, 'password': password, 'auth': 'secEnterprise'}).encode()
        req = urllib.request.Request(BASE + '/logon/long', body, method='POST',
                                     headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                self.token = r.headers['X-SAP-LogonToken']
        except urllib.error.HTTPError as e:
            raise SystemExit(f'Oturum acilamadi: HTTP {e.code}: {e.read().decode("utf-8", "replace")[:400]}')
        except urllib.error.URLError as e:
            raise SystemExit(f'BO REST adresine ulasilamadi ({BASE}): {e.reason}. SAPBO-SRV acik mi, Tomcat 8080 dinliyor mu?')

    def call(self, method, path, data=None, ctype='application/json', accept='application/json', raw=False, binary=False):
        headers = {'X-SAP-LogonToken': self.token, 'Accept': accept}
        body = None
        if data is not None:
            body = data.encode('utf-8') if isinstance(data, str) else json.dumps(data).encode('utf-8')
            headers['Content-Type'] = ctype
        req = urllib.request.Request(BASE + path, body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                b = r.read()
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'{method} {path} -> HTTP {e.code}: {e.read().decode("utf-8", "replace")[:800]}')
        if binary:
            return b
        txt = b.decode('utf-8')
        if raw or accept != 'application/json':
            return txt
        return json.loads(txt) if txt.strip() else {}

    def logoff(self):
        try:
            self.call('POST', '/logoff')
        except Exception:
            pass


def as_list(x):
    return x if isinstance(x, list) else ([x] if x else [])


def cms(bo, q):
    return as_list(bo.call('POST', '/v1/cmsquery', {'query': q}).get('entries'))


def q_str(s):
    return s.replace("'", "''")


def folder_id(bo, path, create_hint=True):
    """Public Folders altindaki 'A/B/C' yolunun SI_ID'si."""
    parent = PUBLIC_FOLDERS
    for part in [p for p in path.replace('\\', '/').split('/') if p]:
        ents = cms(bo, f"SELECT SI_ID FROM CI_INFOOBJECTS WHERE SI_KIND='Folder' AND SI_NAME='{q_str(part)}' AND SI_PARENTID={parent}")
        if not ents:
            hint = (' Klasoru acmak icin: sap-java.ps1 -Kaynak araclar\\sap\\boe\\BoeTool.java -Arguman klasor,"' + path + '"'
                    if create_hint else '')
            raise SystemExit(f'Klasor yok: Public Folders/{path} ("{part}" bulunamadi).{hint}')
        parent = int(ents[0]['SI_ID'])
    return parent


def universes(bo):
    out, offset = [], 0
    while True:
        r = bo.call('GET', f'/raylight/v1/universes?type=unx&offset={offset}&limit=50')
        page = as_list(r.get('universes', {}).get('universe'))
        out += page
        if len(page) < 50:
            return out
        offset += 50


def universe_id(bo, name_or_id):
    if str(name_or_id).isdigit():
        return int(name_or_id)
    name = name_or_id if name_or_id.lower().endswith('.unx') else name_or_id + '.unx'
    for u in universes(bo):
        if u.get('name') == name:
            return int(u['id'])
    raise SystemExit(f'Evren bulunamadi: {name}')


def outline(bo, uid):
    """Evren nesneleri: ad -> {id, tur, veri_tipi, yol}"""
    u = bo.call('GET', f'/raylight/v1/universes/{uid}')['universe']
    found = {}

    def walk(node, path):
        if isinstance(node, dict):
            name = node.get('name')
            typ = node.get('@type')
            if 'id' in node and name and (node.get('@dataType') or typ in ('Dimension', 'Measure', 'Attribute')):
                found[name] = {'id': node['id'], 'tur': typ, 'veri_tipi': node.get('@dataType'), 'yol': '/'.join(path)}
            sub = path + [name] if (name and typ == 'Folder') else path
            for v in node.values():
                walk(v, sub)
        elif isinstance(node, list):
            for v in node:
                walk(v, path)
    walk(u.get('outline', u), [])
    return found


def cmd_ping(bo, args):
    try:
        info = bo.call('GET', '/v1/serverinfo')
        print('serverinfo:', json.dumps(info, ensure_ascii=False)[:600])
    except RuntimeError as e:
        print('serverinfo alinamadi (onemli degil):', str(e)[:200])
    n = cms(bo, "SELECT SI_ID FROM CI_APPOBJECTS WHERE SI_KIND='DSL.MetaDataFile'")
    print(f'OK: oturum acildi ({BASE}, {USER}); CMS\'te {len(n)} UNX evreni (ilk sayfa)')


def cmd_sorgu(bo, args):
    for e in cms(bo, args[0]):
        print(json.dumps(e, ensure_ascii=False))


def cmd_evrenler(bo, args):
    for u in universes(bo):
        print(f"{u.get('id'):>8}  {u.get('name')}  (klasor {u.get('folderId', '?')})")


def cmd_nesneler(bo, args):
    uid = universe_id(bo, args[0])
    print('evren kimligi:', uid)
    for k, v in outline(bo, uid).items():
        print(f"  {v['id']:<28} {str(v['tur']):<10} {str(v['veri_tipi']):<9} {v['yol'] + '/' if v['yol'] else ''}{k}")


def cmd_belgeler(bo, args):
    q = "SELECT SI_ID, SI_NAME, SI_PARENTID, SI_UPDATE_TS FROM CI_INFOOBJECTS WHERE SI_KIND='Webi' AND SI_INSTANCE=0"
    if args:
        q += f' AND SI_PARENTID={folder_id(bo, args[0])}'
    for e in cms(bo, q):
        print(f"{e.get('SI_ID'):>8}  {e.get('SI_NAME')}  (klasor {e.get('SI_PARENTID')}, {e.get('SI_UPDATE_TS', '')})")


def cmd_klasor(bo, args):
    print(folder_id(bo, args[0]))


def dp_rows(bo, doc):
    res = []
    for dp in as_list(bo.call('GET', f'/raylight/v1/documents/{doc}/dataproviders').get('dataproviders', {}).get('dataprovider')):
        info = bo.call('GET', f"/raylight/v1/documents/{doc}/dataproviders/{dp['id']}")['dataprovider']
        res.append((dp['id'], dp.get('name'), info.get('rowCount'), info.get('updated')))
    return res


def cmd_yenile(bo, args):
    doc = int(args[0])
    info = bo.call('GET', f'/raylight/v1/documents/{doc}').get('document', {})
    bo.call('PUT', f'/raylight/v1/documents/{doc}/parameters', {'parameters': {}})
    for dp, name, rows, upd in dp_rows(bo, doc):
        print(f'veri saglayici {dp} ({name}): satir = {rows}, son yenileme = {upd}')
    try:
        bo.call('PUT', f'/raylight/v1/documents/{doc}', {'document': {'name': info.get('name'), 'folderId': info.get('folderId')}})
        print('KAYDEDILDI')
    except RuntimeError as e:
        print('UYARI yenilenen belge kaydedilemedi (veri yine de okundu):', str(e)[:300])


MIME = {'.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.pdf': 'application/pdf',
        '.csv': 'text/csv'}


def cmd_disa_aktar(bo, args):
    doc, path = int(args[0]), args[1]
    ext = os.path.splitext(path)[1].lower()
    if ext not in MIME:
        raise SystemExit('Desteklenen uzantilar: ' + ', '.join(MIME))
    if ext == '.csv':
        dps = dp_rows(bo, doc)
        if not dps:
            raise SystemExit('Belgede veri saglayici yok')
        b = bo.call('GET', f'/raylight/v1/documents/{doc}/dataproviders/{dps[0][0]}/flows/0', accept='text/csv', binary=True)
    else:
        b = bo.call('GET', f'/raylight/v1/documents/{doc}', accept=MIME[ext], binary=True)
    with open(path, 'wb') as f:
        f.write(b)
    print(f'yazildi: {path} ({len(b):,} bayt)')


def cmd_webi_olustur(bo, args):
    with open(args[0], encoding='utf-8-sig') as f:
        t = json.load(f)
    name = t['ad']
    folder = int(t['klasor_id']) if t.get('klasor_id') else folder_id(bo, t['klasor'])
    uid = universe_id(bo, t['evren'])
    objs = outline(bo, uid)
    query = t['sorgu']
    missing = [n for n in query if n not in objs]
    if missing:
        raise SystemExit('Evrende bulunamayan nesneler: ' + ', '.join(missing) + ' (nesneler komutuyla adlari kontrol et)')
    print('klasor:', folder, ' evren:', uid)

    ents = cms(bo, f"SELECT SI_ID FROM CI_INFOOBJECTS WHERE SI_KIND='Webi' AND SI_PARENTID={folder} AND SI_NAME='{q_str(name)}'")
    if ents and t.get('varsa', 'yeniden_kullan') == 'hata':
        raise SystemExit(f'Belge zaten var: {name} ({ents[0]["SI_ID"]})')
    if ents:
        doc = int(ents[0]['SI_ID'])
        bo.call('GET', f'/raylight/v1/documents/{doc}')
        print('mevcut belge yeniden kullaniliyor:', doc)
    else:
        doc = bo.call('POST', '/raylight/v1/documents', {'document': {'name': name, 'folderId': folder}})['success']['id']
        print('belge olusturuldu:', doc)

    dps = as_list(bo.call('GET', f'/raylight/v1/documents/{doc}/dataproviders').get('dataproviders', {}).get('dataprovider'))
    if dps:
        dp = dps[0]['id']
    else:
        dp = bo.call('POST', f'/raylight/v1/documents/{doc}/dataproviders',
                     {'dataprovider': {'name': t.get('veri_saglayici', 'Sorgu 1'), 'dataSourceId': uid}})['success']['id']
    print('veri saglayici:', dp)

    # Sorgu tanimi: queriesTree > bOQuery > resultObjects. UNX nesne kimligi on eksiz kullanilir.
    spec = bo.call('GET', f'/raylight/v1/documents/{doc}/dataproviders/{dp}/specification', accept='text/xml', raw=True)
    items = ''.join(f'<resultObjects identifier="{objs[n]["id"]}" name="{_xml(n)}"/>' for n in query)
    tree = ('<queriesTree xsi:type="queryspec:QueryDataNode">'
            '<bOQuery identifier="9d1c2f3a-1a2b-4c5d-8e9f-001122334455" name="Query">' + items + '</bOQuery></queriesTree>')
    spec = re.sub(r'<queriesTree.*</queriesTree>', '', spec, flags=re.S)
    spec2 = re.sub(r'<queryspec:QuerySpec[^>]*>',
                   '<queryspec:QuerySpec xmlns:queryspec="http://com.sap.sl.queryspec" '
                   'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" dataProviderId="' + dp + '">', spec, count=1)
    if '</queryParameters>' in spec2:
        spec2 = spec2.replace('</queryParameters>', '</queryParameters>' + tree, 1)
    else:
        spec2 = spec2.replace('</queryspec:QuerySpec>', tree + '</queryspec:QuerySpec>', 1)
    r = bo.call('PUT', f'/raylight/v1/documents/{doc}/dataproviders/{dp}/specification', spec2, ctype='text/xml')
    print('sorgu tanimi:', r.get('success', {}).get('message'))

    if t.get('yenile', True):
        bo.call('PUT', f'/raylight/v1/documents/{doc}/parameters', {'parameters': {}})
        for d, n, rows, upd in dp_rows(bo, doc):
            print(f'yenilendi: {n} satir = {rows}')

    cols = t.get('tablo', query)
    if cols:
        try:
            rep = as_list(bo.call('GET', f'/raylight/v1/documents/{doc}/reports')['reports']['report'])[0]['id']
            els = as_list(bo.call('GET', f'/raylight/v1/documents/{doc}/reports/{rep}/elements')['elements']['element'])
            if any(e.get('@type') in ('VTable', 'HTable', 'XTable') for e in els):
                print('raporda tablo zaten var; dokunulmadi')
            else:
                body = next(e['id'] for e in els if e.get('name') == 'Body')
                formulas = []
                for n in cols:
                    o = objs.get(n, {})
                    is_m = o.get('tur') == 'Measure' or n in t.get('olcu', [])
                    dt = {'Numeric': 'Numeric', 'Date': 'Date', 'DateTime': 'DateTime'}.get(str(o.get('veri_tipi')), 'String')
                    formulas.append({'@dataType': 'Numeric' if is_m else dt,
                                     '@qualification': 'Measure' if is_m else 'Dimension', '$': f'=[{n}]'})
                last = None
                for role in ('Column', 'Row', 'Body'):
                    try:
                        bo.call('POST', f'/raylight/v1/documents/{doc}/reports/{rep}/elements',
                                {'element': {'@type': 'VTable', 'parentId': body,
                                             'content': {'axes': {'axis': [{'@role': role, 'expressions': {'formula': formulas}}]}}}})
                        print('rapora tablo eklendi (eksen', role + ')')
                        break
                    except RuntimeError as e:
                        last = e
                else:
                    raise last
        except Exception as e:
            print('UYARI tablo eklenemedi:', str(e)[:500])

    bo.call('PUT', f'/raylight/v1/documents/{doc}', {'document': {'name': name, 'folderId': folder}})
    print(f'KAYDEDILDI: {name} (belge {doc})')


def _xml(s):
    return s.replace('&', '&amp;').replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')


KOMUTLAR = {'ping': (cmd_ping, 0), 'sorgu': (cmd_sorgu, 1), 'evrenler': (cmd_evrenler, 0), 'nesneler': (cmd_nesneler, 1),
            'belgeler': (cmd_belgeler, 0), 'klasor': (cmd_klasor, 1), 'webi-olustur': (cmd_webi_olustur, 1),
            'yenile': (cmd_yenile, 1), 'disa-aktar': (cmd_disa_aktar, 2)}

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    if len(sys.argv) < 2 or sys.argv[1] not in KOMUTLAR:
        print(__doc__)
        sys.exit(2)
    fn, need = KOMUTLAR[sys.argv[1]]
    if len(sys.argv) - 2 < need:
        raise SystemExit(f'{sys.argv[1]}: {need} arguman gerekli')
    pw = os.environ.get('DAO_BO_PAROLA') or sys.stdin.buffer.readline().decode('utf-8-sig').strip()
    if not pw:
        raise SystemExit('Parola yok: DAO_BO_PAROLA ortam degiskeni ya da stdin ilk satiri')
    bo = Bo(pw)
    try:
        fn(bo, sys.argv[2:])
    except RuntimeError as e:
        print('HATA:', e)
        sys.exit(1)
    finally:
        bo.logoff()
