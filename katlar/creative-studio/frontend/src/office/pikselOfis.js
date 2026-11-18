// Creative Studio piksel ofis motoru — AI Ekip ofisindeki PikselOfis sahnesinden uyarlandı.
// Her şey kodla çizilir (dış görsel, yazı tipi ya da kütüphane yok). Dünya 16 px'lik karolardan oluşur;
// düşük çözünürlükte çizilip tam sayı katıyla büyütülür, yazılar (isimlik, balon) tam çözünürlükte üstüne yazılır.
// Kullanım: const m = pikselOfisOlustur(); m.baglan({ tuval, sarici, ipucu, kisiSec, pano, tv, olay }); m.guncelle(veri); ... m.kapat()
export function pikselOfisOlustur() {
const T = 16, BOS = 2;
const azSorgu = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : { matches: false };
const azHareket = () => azSorgu.matches;
const an = () => performance.now();

// ---------------------------------------------------------------- yardımcılar
const karma = s => { let h = 2166136261; for (const c of String(s)) { h ^= c.codePointAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
// Ortak sahne saati (sunucunun /api/durum > zaman alanına göre düzeltilmiş): sahne kararları tarayıcıya değil saate bağlıdır
let saatFarki = null;
const ortakZaman = () => Date.now() + (saatFarki || 0);
function saatAyarla(iso) { const f = Date.parse(iso) - Date.now(); if (!isFinite(f)) return; saatFarki = saatFarki === null ? f : saatFarki * 0.7 + f * 0.3; }
function tohumlu(t) { let a = t >>> 0; return () => { a = (a + 0x6D2B79F5) | 0; let x = Math.imul(a ^ (a >>> 15), 1 | a); x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x; return ((x ^ (x >>> 14)) >>> 0) / 4294967296; }; }
const ara = (a, b) => a + Math.random() * (b - a);
const birini = l => l[Math.floor(Math.random() * l.length)];
const hexRgb = h => { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
const rgbHex = a => '#' + a.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
const kar = (a, b, t) => { const A = hexRgb(a), B = hexRgb(b); return rgbHex(A.map((v, i) => v + (B[i] - v) * t)); };
const koyu = (c, t = 0.3) => kar(c, '#000000', t);
const acik = (c, t = 0.3) => kar(c, '#ffffff', t);
function tuval(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, w); c.height = Math.max(1, h); const x = c.getContext('2d'); x.imageSmoothingEnabled = false; return [c, x]; }
const R = (x, X, Y, W, H, c) => { x.fillStyle = c; x.fillRect(X, Y, W, H); };
const onbellek = new Map();
function sprite(anahtar, w, h, ciz) {
  let s = onbellek.get(anahtar);
  if (!s) { const [c, x] = tuval(w, h); ciz(x); s = c; onbellek.set(anahtar, s); if (onbellek.size > 1500) onbellek.delete(onbellek.keys().next().value); }
  return s;
}
function glif(x, satirlar, X, Y, renk) { for (let j = 0; j < satirlar.length; j++) for (let i = 0; i < satirlar[j].length; i++) if (satirlar[j][i] === '#') R(x, X + i, Y + j, 1, 1, renk); }
const GLIF_SORU = [' ## ', '#  #', '  # ', ' #  ', '    ', ' #  '];
const GLIF_UNLEM = ['#', '#', '#', '#', ' ', '#'];
const GLIF_KUM = ['####', ' ## ', ' ## ', '####'];

// Creative Studio ekibinin renkleri (React tarafı r.renk olarak da gönderir; ikisi aynı)
const VARSAYILAN_RENK = { director: '#7b4bb7', storyteller: '#5fae6e', art_director: '#f39c4a', visual_generator: '#2fb3a8', audio_voice: '#ff8fb1', editor: '#3d5a98', qa_safety: '#ffd23f', publisher: '#e63946' };
const rolRengi = r => (/^#[0-9a-f]{6}$/i.test(r.renk || '') ? r.renk : VARSAYILAN_RENK[r.anahtar]) || '#64748b';
const KISA_AD = { director: 'Yönetmen', storyteller: 'Senarist', art_director: 'Görsel Yön.', visual_generator: 'Görsel Üretici', audio_voice: 'Ses', editor: 'Kurgucu', qa_safety: 'QA', publisher: 'Yayıncı' };
const kisaAd = r => r.kisa || KISA_AD[r.anahtar] || String(r.ad || r.anahtar).split(/\s+/)[0].slice(0, 14);
// Creative Studio ofisi kapanmaz; "evde" durumu motorda yalnız uyumluluk için duruyor
const ofisKapaliMi = d => !!(d && d.kapali);
// Durumlar: calis | hata | soru (onayını bekliyor) | uyku (sunucu bağlantısı yok) | bos. React tarafı r.durum'u hazır gönderir.
function durumu(r, d) {
  if (r.durum) return r.durum;
  d = d || {};
  if (d.bagli === false) return 'uyku';
  if (r.calisiyor) return 'calis';
  if (r.hata) return 'hata';
  if (r.onayBekliyor) return 'soru';
  return 'bos';
}
const DURUM_RENK = { calis: '#4ade80', hata: '#f87171', soru: '#facc15', bekliyor: '#fb923c', mola: '#c4b5fd', uyku: '#64748b', bos: '#94a3b8', evde: '#64748b' };

// ---------------------------------------------------------------- karakter şablonları (12 x 19, üstte 2 satır boşluk)
// S ten, E göz, M ağız, T gömlek, D gömlek gölgesi, A kol, P pantolon, B ayakkabı
const ON = [
  '............', '............', '...SSSSSS...', '..SSSSSSSS..', '.SSSSSSSSSS.', '.SSESSSSESS.', '.SSSSSSSSSS.', '..SSSMMSSS..', '...SSSSSS...',
  '...TTTTTT...', '..TTTTTTTT..', '.ATTTTTTTTA.', '.ATTTTTTTTA.', '.ATTTTTTTTA.', '.S.DDDDDD.S.', '...PPPPPP...', '...PP..PP...', '...PP..PP...', '...BB..BB...'];
const ARKA = [
  '............', '............', '...SSSSSS...', '..SSSSSSSS..', '.SSSSSSSSSS.', '.SSSSSSSSSS.', '.SSSSSSSSSS.', '..SSSSSSSS..', '...SSSSSS...',
  '...TTTTTT...', '..TTTTTTTT..', '.ATTTTTTTTA.', '.ATTTTTTTTA.', '.ATTTTTTTTA.', '.S.DDDDDD.S.', '...PPPPPP...', '...PP..PP...', '...PP..PP...', '...BB..BB...'];
const YAN = [
  '............', '............', '...SSSSSS...', '..SSSSSSSS..', '.SSSSSSSSSS.', '.SSSSSSSESS.', '.SSSSSSSSSSS', '..SSSSSSSM..', '...SSSSSS...',
  '....TTTT....', '...TTTTTT...', '...TTATTT...', '...TTATTT...', '...TTATTT...', '....DSDD....', '....PPPP....', '....PPPP....', '....PPPP....', '....BBBB....'];
// Saç ve aksesuar katmanları: [satır, ilk sütun, son sütun, renk anahtarı (varsayılan H = saç)]
const KISA = {
  on: [[0, 3, 8], [1, 2, 9], [2, 1, 10], [3, 1, 10], [4, 1, 1], [4, 10, 10]],
  arka: [[0, 3, 8], [1, 2, 9], [2, 1, 10], [3, 1, 10], [4, 1, 10], [5, 1, 10], [6, 1, 10], [7, 2, 9]],
  yan: [[0, 3, 8], [1, 2, 9], [2, 1, 10], [3, 1, 7], [4, 1, 4], [5, 1, 3], [6, 1, 3], [7, 2, 3]],
};
const SACLAR = {
  kisa: KISA,
  uzun: {
    on: KISA.on.concat([[4, 0, 1], [4, 10, 11], [5, 0, 0], [5, 11, 11], [6, 0, 0], [6, 11, 11], [7, 0, 1], [7, 10, 11], [8, 0, 2], [8, 9, 11], [9, 1, 2], [9, 9, 10], [10, 1, 1], [10, 10, 10]]),
    arka: KISA.arka.concat([[8, 1, 10], [9, 2, 9], [10, 2, 9], [11, 3, 8]]),
    yan: KISA.yan.concat([[7, 1, 4], [8, 1, 4], [9, 2, 4], [10, 2, 3]]),
  },
  kivircik: {
    on: [[-1, 3, 8], [0, 1, 10], [1, 0, 11], [2, 0, 11], [3, 0, 11], [4, 0, 1], [4, 10, 11], [5, 0, 0], [5, 11, 11]],
    arka: [[-1, 3, 8], [0, 1, 10], [1, 0, 11], [2, 0, 11], [3, 0, 11], [4, 0, 11], [5, 0, 11], [6, 0, 11], [7, 1, 10]],
    yan: [[-1, 3, 8], [0, 1, 10], [1, 0, 11], [2, 0, 10], [3, 0, 8], [4, 0, 5], [5, 0, 4], [6, 0, 3], [7, 1, 3]],
  },
  topuz: {
    on: KISA.on.concat([[-2, 4, 7], [-1, 3, 8]]),
    arka: KISA.arka.concat([[-2, 4, 7], [-1, 3, 8]]),
    yan: KISA.yan.concat([[-2, 1, 3], [-1, 1, 4]]),
  },
  kel: {
    on: [[1, 4, 7, 'S'], [3, 1, 2], [3, 9, 10], [4, 1, 1], [4, 10, 10]],
    arka: [[1, 4, 7, 'S'], [4, 1, 10], [5, 1, 10], [6, 2, 9]],
    yan: [[1, 4, 7, 'S'], [3, 1, 3], [4, 1, 4], [5, 1, 3], [6, 2, 3]],
  },
  kep: {
    on: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 10, 'V'], [4, 1, 1], [4, 10, 10]],
    arka: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 10, 'K'], [4, 1, 10], [5, 1, 10], [6, 2, 9], [7, 3, 8]],
    yan: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 6, 'K'], [3, 7, 11, 'V'], [4, 1, 4], [5, 1, 3], [6, 2, 3]],
  },
  bere: {
    on: [[-1, 5, 6, 'V'], [0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 10, 'V'], [4, 1, 1], [4, 10, 10]],
    arka: [[-1, 5, 6, 'V'], [0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 10, 'V'], [4, 1, 10], [5, 1, 10], [6, 2, 9]],
    yan: [[-1, 4, 5, 'V'], [0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 1, 9, 'V'], [4, 1, 4], [5, 1, 3]],
  },
  beret: {
    on: [[-1, 6, 6, 'K'], [0, 2, 9, 'K'], [1, 1, 10, 'K'], [2, 0, 9, 'K'], [3, 1, 2], [3, 9, 10], [4, 1, 1], [4, 10, 10]],
    arka: [[-1, 6, 6, 'K'], [0, 2, 9, 'K'], [1, 1, 10, 'K'], [2, 0, 9, 'K'], [3, 1, 10], [4, 1, 10], [5, 1, 10], [6, 2, 9], [7, 2, 9]],
    yan: [[-1, 5, 5, 'K'], [0, 2, 9, 'K'], [1, 0, 10, 'K'], [2, 1, 8, 'K'], [3, 1, 4], [4, 1, 4], [5, 1, 3], [6, 1, 3], [7, 2, 3]],
  },
  kapson: {
    on: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 2, 9], [3, 0, 1, 'K'], [3, 10, 11, 'K'], [4, 0, 1, 'K'], [4, 10, 11, 'K'], [5, 0, 0, 'K'], [5, 11, 11, 'K'],
      [6, 0, 0, 'K'], [6, 11, 11, 'K'], [7, 0, 1, 'K'], [7, 10, 11, 'K'], [8, 1, 2, 'K'], [8, 9, 10, 'K']],
    arka: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 0, 11, 'K'], [4, 0, 11, 'K'], [5, 0, 11, 'K'], [6, 0, 11, 'K'], [7, 0, 11, 'K'], [8, 1, 10, 'K'], [9, 2, 9, 'K']],
    yan: [[0, 3, 8, 'K'], [1, 2, 9, 'K'], [2, 1, 10, 'K'], [3, 0, 7, 'K'], [3, 8, 8], [4, 0, 4, 'K'], [5, 0, 3, 'K'], [6, 0, 3, 'K'], [7, 0, 3, 'K'], [8, 1, 4, 'K']],
  },
  // inşaat bareti (Pedagojik QA)
  baret: {
    on: [[-1, 3, 8, 'K'], [0, 2, 9, 'K'], [1, 1, 10, 'K'], [2, 1, 10, 'K'], [3, 0, 11, 'V'], [4, 1, 1], [4, 10, 10]],
    arka: [[-1, 3, 8, 'K'], [0, 2, 9, 'K'], [1, 1, 10, 'K'], [2, 1, 10, 'K'], [3, 0, 11, 'V'], [4, 1, 10], [5, 1, 10], [6, 2, 9]],
    yan: [[-1, 3, 8, 'K'], [0, 2, 9, 'K'], [1, 1, 10, 'K'], [2, 1, 10, 'K'], [3, 0, 11, 'V'], [4, 1, 4], [5, 1, 3], [6, 2, 3]],
  },
};
const KULAKLIK = [[-1, 3, 8, 'Q'], [0, 2, 2, 'Q'], [0, 9, 9, 'Q'], [1, 1, 1, 'Q'], [1, 10, 10, 'Q'], [2, 0, 0, 'Q'], [2, 11, 11, 'Q'], [3, 0, 0, 'Q'], [3, 11, 11, 'Q'],
  [4, 0, 0, 'Q'], [4, 11, 11, 'Q'], [5, 0, 0, 'Q'], [5, 11, 11, 'Q']];
const EKLER = {
  gozluk: { on: [[4, 2, 4, 'G'], [4, 7, 9, 'G'], [5, 2, 2, 'G'], [5, 4, 7, 'G'], [5, 9, 9, 'G']], yan: [[4, 6, 9, 'G'], [5, 6, 6, 'G'], [5, 9, 9, 'G']] },
  gunes: { on: [[4, 2, 9, 'G'], [5, 2, 4, 'G'], [5, 7, 9, 'G']], yan: [[4, 6, 9, 'G'], [5, 7, 9, 'G']] },
  kulaklik: { on: KULAKLIK, arka: KULAKLIK, yan: [[-1, 4, 6, 'Q'], [0, 4, 4, 'Q'], [1, 4, 4, 'Q'], [2, 4, 4, 'Q'], [3, 3, 5, 'Q'], [4, 3, 5, 'Q'], [5, 3, 5, 'Q']] },
  mikrofon: { on: [[6, 1, 1, 'Q'], [7, 2, 3, 'Q']], yan: [[6, 5, 5, 'Q'], [7, 6, 8, 'Q']] },
  kravat: { on: [[9, 4, 4, 'W'], [9, 7, 7, 'W'], [9, 5, 6, 'R'], [10, 5, 6, 'R'], [11, 5, 6, 'R'], [12, 5, 6, 'R'], [13, 5, 6, 'R']] },
  sakal: { on: [[6, 1, 1], [6, 10, 10], [7, 1, 4], [7, 7, 10], [8, 3, 8]], yan: [[6, 4, 8], [7, 4, 8], [8, 4, 7]] },
  // Creative Studio ekibinin aksesuarları (Y = kişinin aksesuar rengi)
  atki: { on: [[9, 2, 9, 'Y'], [10, 3, 4, 'Y'], [11, 3, 4, 'Y'], [12, 3, 3, 'Y']], arka: [[9, 2, 9, 'Y']], yan: [[9, 4, 8, 'Y'], [10, 7, 8, 'Y']] },
  onluk: { on: [[10, 4, 7, 'Y'], [11, 3, 8, 'Y'], [12, 3, 8, 'Y'], [13, 3, 8, 'Y'], [14, 3, 8, 'Y']], yan: [[11, 7, 8, 'Y'], [12, 7, 8, 'Y'], [13, 7, 8, 'Y']] },
  yelek: { on: [[9, 3, 3, 'Y'], [9, 8, 8, 'Y'], [10, 2, 3, 'Y'], [10, 8, 9, 'Y'], [11, 2, 3, 'Y'], [11, 8, 9, 'Y'], [12, 2, 9, 'W'], [13, 2, 3, 'Y'], [13, 8, 9, 'Y']],
    arka: [[10, 2, 9, 'Y'], [11, 2, 9, 'Y'], [12, 2, 9, 'W'], [13, 2, 9, 'Y']], yan: [[10, 3, 8, 'Y'], [11, 3, 8, 'Y'], [12, 3, 8, 'W'], [13, 3, 8, 'Y']] },
  anten: { on: [[-2, 5, 6, 'Y'], [-1, 5, 5, 'Q']], arka: [[-2, 5, 6, 'Y'], [-1, 5, 5, 'Q']], yan: [[-2, 4, 5, 'Y'], [-1, 4, 4, 'Q']] },
};
const TEN = ['#f3cfb1', '#e2b08a', '#c98e66', '#8d5a3b', '#f7dcc5'];
const SAC_RENGI = ['#2b1d16', '#4b2e1a', '#7c2d12', '#1f2937', '#a16207', '#6b7280', '#c9a86a'];
const SAC_TIPI = ['kisa', 'uzun', 'kivircik', 'topuz', 'kel', 'kep', 'beret', 'bere'];
const PANTOLON = ['#374151', '#2f3b52', '#4a3f35', '#334155', '#3f3f46'];
// Creative Studio ekibi: eski paneldeki karakterlerin saçı, rengi ve aksesuarları bu şablonlara taşındı
const HAZIR = {
  director: { sac: 'kisa', sr: '#3b2a20', ten: 0, ek: ['gunes', 'atki'], aks: '#ffd166' },
  storyteller: { sac: 'uzun', sr: '#8a4b2a', ten: 1, ek: ['gozluk'] },
  art_director: { sac: 'beret', sr: '#e06c9f', ten: 4, ek: ['onluk'], sapka: '#2f6fb5', aks: '#fff1d6' },
  visual_generator: { sac: 'kep', sr: '#1f1f2e', ten: 2, ek: [], sapka: '#ff6b6b' },
  audio_voice: { sac: 'uzun', sr: '#f2c14e', ten: 4, ek: ['kulaklik', 'mikrofon'] },
  editor: { sac: 'bere', sr: '#2a1d17', ten: 3, ek: ['gozluk'], sapka: '#e9c46a' },
  qa_safety: { sac: 'baret', sr: '#5b3a29', ten: 1, ek: ['yelek'], sapka: '#facc15', aks: '#f08a24' },
  publisher: { sac: 'kivircik', sr: '#b5462f', ten: 2, ek: ['anten'], aks: '#7cf29c' },
};
function gorunumu(r) {
  const h = karma(r.anahtar);
  const z = HAZIR[r.anahtar] || { sac: SAC_TIPI[h % SAC_TIPI.length], sr: SAC_RENGI[(h >>> 4) % SAC_RENGI.length], ten: (h >>> 8) % TEN.length, ek: [[], ['gozluk'], ['kulaklik']][(h >>> 12) % 3] };
  const g = rolRengi(r), ten = TEN[z.ten];
  const sapka = z.sapka || (z.sac === 'kapson' ? koyu(g, 0.35) : koyu(g, 0.15));
  return {
    sac: z.sac, ek: z.ek, gomlek: g,
    pal: { S: ten, E: '#2a2522', M: koyu(ten, 0.38), T: g, D: koyu(g, 0.25), A: koyu(g, 0.12), P: PANTOLON[(h >>> 16) % PANTOLON.length], B: '#25252b',
      H: z.sr, K: sapka, V: koyu(sapka, 0.45), G: '#1f2937', Q: '#2b2f36', W: '#f8fafc', R: '#7f1d1d', Y: z.aks || '#ffd166' },
  };
}
function sablon(g, poz, kare) {
  let s = (g === 'yan' ? YAN : g === 'arka' ? ARKA : ON).slice();
  if (poz === 'yuru') {
    const a = kare % 4;
    if (g === 'yan') { if (a === 1 || a === 3) s.splice(15, 4, '....PPPP....', '...PP.PP....', '..PP...PP...', '..BB...BBB..'); }
    else if (a === 1) s.splice(16, 3, '...PP..PP...', '...PP..BB...', '...BB.......');
    else if (a === 3) s.splice(16, 3, '...PP..PP...', '...BB..PP...', '.......BB...');
  } else if (poz === 'otur') {
    s = s.slice(0, 14);
    if (kare === 1) { s[10] = '.ATTTTTTTT..'; s[13] = '..TTTTTTTTA.'; }
    else if (kare === 2) { s[10] = '..TTTTTTTTA.'; s[13] = '.ATTTTTTTT..'; }
  } else if (poz === 'koltuk') {
    s = s.slice(0, 15).concat(['..PPPPPPPP..', '..BB....BB..']);
  } else if (poz === 'sevinc' && g === 'on') {
    s.splice(6, 9, 'SSSSSSSSSSSS', 'A.SSSMMSSS.A', 'A..SSSSSS..A', '.A.TTTTTT.A.', '..TTTTTTTT..', '..TTTTTTTT..', '..TTTTTTTT..', '..TTTTTTTT..', '...DDDDDD...');
  }
  return s;
}
// gor: on | arka | yan (sağa bakar) | yanSol
function kisiSprite(k, gor, poz, kare) {
  const anahtar = `k|${k.imza}|${gor}|${poz}|${kare}`;
  if (gor === 'yanSol') return sprite(anahtar, 12, 21, x => { x.translate(12, 0); x.scale(-1, 1); x.drawImage(kisiSprite(k, 'yan', poz, kare), 0, 0); });
  return sprite(anahtar, 12, 21, x => {
    const sat = sablon(gor, poz, kare), p = k.gor.pal;
    for (let j = 0; j < sat.length; j++) for (let i = 0; i < 12; i++) { const c = sat[j][i]; if (c !== '.' && p[c]) R(x, i, BOS + j, 1, 1, p[c]); }
    const sinir = poz === 'otur' ? 13 : 99;
    const katman = liste => {
      for (const [s, a, b, anah = 'H'] of liste || []) {
        if (s > sinir) continue;
        for (let i = a; i <= b; i++) { let c = p[anah]; if (anah === 'H' && k.gor.sac === 'kivircik' && (i + s) % 3 === 0) c = koyu(c, 0.25); R(x, i, BOS + s, 1, 1, c); }
      }
    };
    katman((SACLAR[k.gor.sac] || KISA)[gor]);
    for (const e of k.gor.ek) katman((EKLER[e] || {})[gor]);
  });
}

// ---------------------------------------------------------------- eşya sprite'ları
function masaSprite(k) {
  return sprite('masa|' + k.imza, 32, 22, x => {
    R(x, 2, 20, 28, 2, 'rgba(0,0,0,.18)');
    R(x, 0, 7, 32, 9, '#c4915f'); R(x, 0, 7, 32, 1, '#dcae7c'); R(x, 0, 15, 32, 1, '#a9774b');
    R(x, 1, 16, 30, 5, '#8e6240'); R(x, 1, 20, 30, 1, '#704c2d'); R(x, 22, 17, 7, 3, '#9d6e48'); R(x, 25, 18, 1, 1, '#e2c08f');
    R(x, 15, 10, 2, 2, '#4b5160'); R(x, 12, 12, 8, 1, '#5b6272');
    R(x, 8, 0, 16, 11, '#2b2f36'); R(x, 8, 0, 16, 1, '#3d4450'); R(x, 22, 9, 1, 1, '#4ade80');
    R(x, 10, 13, 12, 2, '#d6d9df'); R(x, 10, 14, 12, 1, '#b3b8c1'); R(x, 24, 13, 2, 2, '#d6d9df');
    const kr = k.gor.gomlek; R(x, 2, 10, 4, 4, kr); R(x, 2, 10, 4, 1, acik(kr, 0.35)); R(x, 6, 11, 1, 2, kr);
    masaEsyasi(x, k.a);
  });
}
// Her istasyonun masasında işini anlatan bir eşya
function masaEsyasi(x, a) {
  if (a === 'director') { // klaket
    R(x, 24, 7, 7, 5, '#1f2937'); R(x, 25, 9, 5, 1, '#e5e7eb'); R(x, 24, 4, 7, 3, '#f8fafc');
    R(x, 25, 4, 1, 3, '#1f2937'); R(x, 27, 4, 1, 3, '#1f2937'); R(x, 29, 4, 1, 3, '#1f2937');
  } else if (a === 'storyteller') { // kitaplar ve tüy kalem
    R(x, 24, 9, 7, 3, '#7c2d12'); R(x, 24, 8, 7, 1, '#f8fafc'); R(x, 25, 6, 6, 2, '#2563eb'); R(x, 25, 5, 6, 1, '#f1f5f9');
    R(x, 30, 0, 1, 6, '#f8fafc'); R(x, 29, 0, 1, 3, '#e2e8f0');
  } else if (a === 'art_director') { // boya kalemleri
    R(x, 26, 7, 4, 5, '#475569'); R(x, 26, 7, 4, 1, '#64748b');
    R(x, 26, 3, 1, 4, '#ef4444'); R(x, 27, 2, 1, 5, '#facc15'); R(x, 28, 3, 1, 4, '#22c55e'); R(x, 29, 4, 1, 3, '#3b82f6');
  } else if (a === 'visual_generator') { // ekran kartlı kasa
    R(x, 25, 0, 6, 12, '#111827'); R(x, 25, 0, 6, 1, '#374151'); R(x, 26, 2, 4, 1, '#22d3ee'); R(x, 26, 4, 4, 1, '#a855f7'); R(x, 26, 7, 4, 3, '#374151'); R(x, 27, 8, 2, 1, '#6b7280');
  } else if (a === 'audio_voice') { // masa mikrofonu
    R(x, 27, 1, 3, 4, '#9ca3af'); R(x, 27, 1, 3, 1, '#d1d5db'); R(x, 28, 5, 1, 6, '#4b5563'); R(x, 26, 11, 5, 1, '#374151');
  } else if (a === 'editor') { // film makarası
    R(x, 26, 3, 4, 8, '#1f2937'); R(x, 25, 4, 6, 6, '#1f2937'); R(x, 27, 6, 2, 2, '#e5e7eb');
    R(x, 26, 4, 1, 1, '#9ca3af'); R(x, 29, 4, 1, 1, '#9ca3af'); R(x, 26, 9, 1, 1, '#9ca3af'); R(x, 29, 9, 1, 1, '#9ca3af');
  } else if (a === 'qa_safety') { // kontrol listesi
    R(x, 25, 3, 6, 9, '#b45309'); R(x, 26, 4, 4, 7, '#f8fafc'); R(x, 27, 2, 2, 2, '#9ca3af');
    for (let i = 0; i < 3; i++) { R(x, 26, 5 + i * 2, 1, 1, '#16a34a'); R(x, 28, 5 + i * 2, 2, 1, '#94a3b8'); }
  } else if (a === 'publisher') { // yayın anteni
    R(x, 28, 2, 1, 9, '#6b7280'); R(x, 26, 11, 5, 1, '#4b5563'); R(x, 27, 1, 3, 1, '#ef4444');
    R(x, 25, 2, 1, 2, '#7cf29c'); R(x, 31, 2, 1, 2, '#7cf29c'); R(x, 24, 1, 1, 4, '#4ade80');
  } else { R(x, 27, 6, 4, 4, '#b45309'); R(x, 26, 1, 6, 5, '#16a34a'); }
}
const sandalye = () => sprite('sandalye', 14, 12, x => {
  R(x, 1, 0, 12, 7, '#3d4350'); R(x, 1, 0, 12, 1, '#59606f'); R(x, 2, 1, 10, 5, '#4a5160'); R(x, 1, 6, 12, 1, '#2f343e');
  R(x, 6, 7, 2, 2, '#2a2e36'); R(x, 2, 9, 10, 1, '#2a2e36'); R(x, 2, 10, 2, 2, '#1c1f25'); R(x, 6, 10, 2, 2, '#1c1f25'); R(x, 10, 10, 2, 2, '#1c1f25');
});
const kanepeUst = renk => sprite('kanepeU' + renk, 48, 26, x => {
  const k1 = koyu(renk, 0.15), k2 = koyu(renk, 0.3), ac = acik(renk, 0.15);
  R(x, 2, 24, 44, 2, 'rgba(0,0,0,.2)'); R(x, 0, 6, 48, 18, k1);
  R(x, 4, 0, 40, 12, renk); R(x, 4, 0, 40, 1, ac); R(x, 17, 1, 1, 10, k1); R(x, 30, 1, 1, 10, k1);
  R(x, 4, 12, 40, 7, ac); R(x, 17, 12, 1, 7, renk); R(x, 30, 12, 1, 7, renk);
  R(x, 0, 4, 5, 18, renk); R(x, 43, 4, 5, 18, renk); R(x, 0, 4, 5, 1, ac); R(x, 43, 4, 5, 1, ac);
  R(x, 4, 19, 40, 4, k2); R(x, 2, 23, 3, 1, '#3b2a1e'); R(x, 43, 23, 3, 1, '#3b2a1e');
});
const kanepeAlt = renk => sprite('kanepeA' + renk, 48, 20, x => {
  R(x, 2, 18, 44, 2, 'rgba(0,0,0,.2)');
  R(x, 0, 0, 5, 16, renk); R(x, 43, 0, 5, 16, renk);
  R(x, 2, 6, 44, 10, koyu(renk, 0.1)); R(x, 2, 6, 44, 1, acik(renk, 0.08)); R(x, 17, 7, 1, 8, koyu(renk, 0.22)); R(x, 30, 7, 1, 8, koyu(renk, 0.22));
  R(x, 2, 15, 44, 2, koyu(renk, 0.32));
});
const sehpa = () => sprite('sehpa', 40, 14, x => {
  R(x, 2, 12, 36, 2, 'rgba(0,0,0,.18)'); R(x, 0, 2, 40, 8, '#8e6240'); R(x, 0, 2, 40, 1, '#a9774b'); R(x, 1, 10, 38, 2, '#6b4a2f');
  R(x, 6, 3, 4, 3, '#f8fafc'); R(x, 7, 4, 2, 1, '#9a3412'); R(x, 26, 3, 8, 5, '#3b82f6'); R(x, 27, 4, 6, 1, '#fde68a'); R(x, 16, 4, 3, 3, '#e5e7eb');
});
const puf = renk => sprite('puf' + renk, 16, 12, x => {
  R(x, 1, 10, 14, 2, 'rgba(0,0,0,.18)'); R(x, 2, 2, 12, 9, renk); R(x, 1, 4, 14, 6, renk); R(x, 4, 1, 8, 2, acik(renk, 0.2)); R(x, 3, 3, 4, 2, acik(renk, 0.3)); R(x, 2, 9, 12, 2, koyu(renk, 0.25));
});
function bitkiSprite(tur, kare) {
  return sprite(`bitki|${tur}|${kare}`, 16, 26, x => {
    const s = kare ? 1 : 0;
    R(x, 3, 24, 10, 2, 'rgba(0,0,0,.18)');
    R(x, 4, 17, 8, 8, '#b45309'); R(x, 3, 17, 10, 2, '#c2410c'); R(x, 5, 19, 1, 5, '#d97706');
    if (tur === 0) { // uzun yapraklı
      R(x, 7, 6, 2, 11, '#166534'); R(x, 2 + s, 4, 5, 3, '#22c55e'); R(x, 9 + s, 2, 5, 3, '#16a34a'); R(x, 1, 9, 6, 3, '#16a34a'); R(x, 9, 8, 6, 3, '#22c55e');
      R(x, 4 + s, 0, 4, 3, '#4ade80'); R(x, 3, 13, 4, 3, '#15803d'); R(x, 10, 12, 4, 3, '#15803d');
    } else if (tur === 1) { // yuvarlak çalı
      R(x, 2, 8, 12, 9, '#15803d'); R(x, 1, 10, 14, 5, '#16a34a'); R(x, 3, 6, 10, 3, '#22c55e'); R(x, 4 + s, 7, 3, 2, '#4ade80'); R(x, 9, 11, 3, 2, '#4ade80');
    } else { // çiçekli
      R(x, 3, 9, 10, 8, '#15803d'); R(x, 2, 11, 12, 4, '#16a34a');
      R(x, 4 + s, 7, 3, 3, '#f43f5e'); R(x, 9, 6 + s, 3, 3, '#facc15'); R(x, 6, 4, 3, 3, '#fb7185'); R(x, 5 + s, 8, 1, 1, '#fde68a'); R(x, 10, 7 + s, 1, 1, '#a16207');
    }
  });
}
const lamba = () => sprite('lamba', 10, 32, x => { R(x, 2, 30, 6, 2, '#374151'); R(x, 4, 8, 2, 22, '#4b5563'); R(x, 0, 0, 10, 8, '#fef3c7'); R(x, 0, 7, 10, 1, '#e5d3a0'); R(x, 1, 1, 8, 1, '#fffbeb'); });
const kitaplik = () => sprite('kitaplik', 32, 32, x => {
  R(x, 1, 30, 30, 2, 'rgba(0,0,0,.18)'); R(x, 0, 0, 32, 31, '#7c5434'); R(x, 2, 2, 28, 27, '#5b3d25');
  const r = tohumlu(11), renk = ['#dc2626', '#2563eb', '#16a34a', '#f59e0b', '#7c3aed', '#0891b2', '#e5e7eb', '#be185d'];
  for (const raf of [2, 11, 20]) {
    let bx = 3; while (bx < 28) { const w = 2 + Math.floor(r() * 2), h = 5 + Math.floor(r() * 3); R(x, bx, raf + 8 - h, w, h, renk[Math.floor(r() * renk.length)]); bx += w + (r() < 0.2 ? 2 : 0); }
    R(x, 2, raf + 8, 28, 1, '#7c5434');
  }
});
const tezgah = () => sprite('tezgah', 64, 26, x => {
  R(x, 0, 0, 64, 10, '#e7e2da'); for (let i = 0; i < 64; i += 8) R(x, i, 0, 1, 10, '#d6d0c6'); R(x, 0, 5, 64, 1, '#d6d0c6');
  R(x, 0, 10, 64, 4, '#d8d2c8'); R(x, 0, 10, 64, 1, '#efeae2'); R(x, 0, 14, 64, 11, '#9b6b45'); R(x, 0, 24, 64, 2, '#6b4a2f');
  for (let i = 0; i < 64; i += 16) { R(x, i, 14, 1, 10, '#7c5434'); R(x, i + 12, 18, 2, 1, '#d6c4a8'); }
  // kahve makinesi
  R(x, 4, 0, 10, 12, '#2f3640'); R(x, 4, 0, 10, 2, '#4b5563'); R(x, 6, 3, 6, 3, '#111827'); R(x, 11, 3, 1, 1, '#ef4444'); R(x, 8, 7, 2, 2, '#9ca3af'); R(x, 7, 10, 4, 2, '#f8fafc');
  // mikrodalga
  R(x, 22, 3, 14, 8, '#e5e7eb'); R(x, 23, 4, 9, 6, '#374151'); R(x, 33, 5, 2, 1, '#22c55e'); R(x, 33, 7, 2, 2, '#9ca3af');
  // evye
  R(x, 42, 10, 14, 3, '#9ca3af'); R(x, 43, 11, 12, 1, '#6b7280'); R(x, 48, 4, 2, 6, '#9ca3af'); R(x, 48, 4, 5, 2, '#9ca3af');
});
const buzdolabi = () => sprite('buzdolabi', 16, 32, x => { R(x, 1, 30, 14, 2, 'rgba(0,0,0,.18)'); R(x, 1, 0, 14, 31, '#e8ecef'); R(x, 1, 0, 14, 1, '#f8fafc'); R(x, 1, 11, 14, 1, '#c3cad1'); R(x, 12, 4, 1, 5, '#9aa3ad'); R(x, 12, 14, 1, 8, '#9aa3ad'); R(x, 3, 2, 3, 2, '#fde68a'); });
const otomat = () => sprite('otomat', 16, 32, x => {
  R(x, 0, 30, 16, 2, 'rgba(0,0,0,.18)'); R(x, 0, 0, 16, 31, '#b91c1c'); R(x, 0, 0, 16, 2, '#dc2626'); R(x, 2, 3, 9, 20, '#1e293b');
  const renk = ['#facc15', '#22c55e', '#3b82f6', '#f97316', '#ec4899'];
  for (let s = 0; s < 4; s++) for (let i = 0; i < 3; i++) R(x, 3 + i * 3, 5 + s * 5, 2, 3, renk[(s + i) % renk.length]);
  R(x, 12, 5, 3, 6, '#fde68a'); R(x, 12, 13, 3, 2, '#111827'); R(x, 2, 25, 9, 4, '#0f172a');
});
const sebil = () => sprite('sebil', 12, 26, x => { R(x, 1, 24, 10, 2, 'rgba(0,0,0,.18)'); R(x, 2, 0, 8, 10, '#93c5fd'); R(x, 3, 1, 2, 7, '#dbeafe'); R(x, 4, 0, 4, 1, '#3b82f6'); R(x, 1, 10, 10, 15, '#e5e7eb'); R(x, 1, 10, 10, 1, '#f8fafc'); R(x, 3, 13, 2, 2, '#3b82f6'); R(x, 7, 13, 2, 2, '#ef4444'); R(x, 2, 18, 8, 1, '#9ca3af'); });
const cop = () => sprite('cop', 8, 10, x => { R(x, 0, 8, 8, 2, 'rgba(0,0,0,.18)'); R(x, 1, 1, 6, 8, '#64748b'); R(x, 0, 0, 8, 2, '#94a3b8'); R(x, 2, 3, 1, 5, '#475569'); R(x, 5, 3, 1, 5, '#475569'); });
const masaYuvarlak = () => sprite('masaY', 24, 16, x => { R(x, 3, 14, 18, 2, 'rgba(0,0,0,.18)'); R(x, 2, 2, 20, 8, '#e7e5e4'); R(x, 0, 4, 24, 4, '#e7e5e4'); R(x, 2, 2, 20, 1, '#fafaf9'); R(x, 10, 10, 4, 4, '#78716c'); R(x, 7, 14, 10, 1, '#57534e'); R(x, 5, 4, 3, 2, '#f8fafc'); R(x, 15, 3, 3, 3, '#dc2626'); });
const yazici = () => sprite('yazici', 16, 18, x => { R(x, 1, 16, 14, 2, 'rgba(0,0,0,.18)'); R(x, 1, 7, 14, 10, '#9ca3af'); R(x, 0, 4, 16, 5, '#d1d5db'); R(x, 3, 0, 10, 5, '#f8fafc'); R(x, 4, 11, 8, 1, '#374151'); R(x, 12, 6, 2, 1, '#22c55e'); });
const dolap = () => sprite('dolap', 12, 18, x => { R(x, 1, 16, 10, 2, 'rgba(0,0,0,.18)'); R(x, 1, 0, 10, 17, '#94a3b8'); R(x, 1, 0, 10, 1, '#cbd5e1'); for (const y of [5, 11]) R(x, 1, y, 10, 1, '#64748b'); for (const y of [2, 8, 13]) R(x, 5, y, 2, 1, '#e2e8f0'); });
const ADIM_RENK = { pending: '#cbd5e1', working: '#60a5fa', done: '#4ade80', failed: '#f87171' };
// Üretim panosu: aktif hikâyenin yedi adımı (Senarist → Yayıncı); her sütun bir adımın durumunu gösterir
function panoSprite(adimlar, alarm, yanip) {
  return sprite(`pano|${adimlar.join(',')}|${alarm}|${yanip}`, 48, 36, x => {
    R(x, 4, 26, 2, 9, '#6b7280'); R(x, 42, 26, 2, 9, '#6b7280'); R(x, 2, 34, 6, 2, '#4b5563'); R(x, 40, 34, 6, 2, '#4b5563');
    R(x, 0, 0, 48, 28, '#9ca3af'); R(x, 1, 1, 46, 26, '#f8fafc'); R(x, 0, 27, 48, 1, '#6b7280'); R(x, 6, 27, 6, 1, '#2563eb'); R(x, 14, 27, 4, 1, '#dc2626');
    for (let i = 0; i < 7; i++) {
      const cx = 2 + Math.floor(i * 6.4), d = adimlar[i] || 'pending', renk = ADIM_RENK[d] || ADIM_RENK.pending;
      R(x, cx, 2, 5, 1, koyu(renk, 0.2)); if (i < 6) R(x, cx + 5, 2, 1, 24, '#e2e8f0');
      if (d === 'done') { for (let j = 0; j < 4; j++) R(x, cx + 1, 5 + j * 5, 3, 4, renk); }
      else if (d === 'working') { for (let j = 0; j < 2; j++) R(x, cx + 1, 5 + j * 5, 3, 4, yanip ? renk : acik(renk, 0.55)); }
      else if (d === 'failed') { R(x, cx + 1, 5, 3, 4, renk); R(x, cx + 2, 11, 1, 3, renk); R(x, cx + 2, 15, 1, 1, renk); }
      else R(x, cx + 1, 5, 3, 1, renk);
    }
    if (alarm) R(x, 21, 0, 6, 2, '#ef4444');
  });
}
function bulutCiz(x, X, Y, w, renk) { R(x, X, Y + 2, w, 3, renk); R(x, X + 2, Y, Math.max(2, w - 6), 2, renk); R(x, X + 4, Y - 1, Math.max(2, w - 11), 1, renk); }

// ---------------------------------------------------------------- durum
let tuvalEl = null, ctx = null, sarici = null, ipucuEl = null, cb = {};
let dpr = 1, K = 2, GW = 40, GH = 18;
let dunya = null, dctx = null, zemin = null, duvar = null, gok = null, gokDakika = -1;
let izgara = new Uint8Array(0);
let statik = [], poiler = [], pencereler = [], bolgeler = [], bulutlar = [];
const kisiler = new Map();
let asansor = null, saatYeri = null, tvYeri = null, panoYeri = null, kahveYeri = null, yayinYeri = null;
let veri = null, onceki = null, yerlesimImza = '', ilkKurulum = true, gorunur = true, sonCizim = 0;
let secili = null, uzerinde = null, vurgu = null, uzerindeNesne = null;
let parcaciklar = [], paketler = [], yuzenler = [], zamanlayicilar = [], alarmBitis = 0, kapiAcik = 0, kapiBitis = 0, isikSonuk = 0, kapandi = false, gozlemciler = [], dinleyiciler = [];
let olcuOnbellek = new Map();

const zamanla = (ms, f) => zamanlayicilar.push({ zaman: an() + ms, f });
const merkez = (tx, ty) => ({ x: tx * T + 8, y: ty * T + 12 });
const karoBul = (x, y) => ({ tx: Math.max(0, Math.min(GW - 1, Math.floor(x / T))), ty: Math.max(0, Math.min(GH - 1, Math.floor(y / T))) });
const gecilir = (tx, ty) => tx >= 0 && ty >= 0 && tx < GW && ty < GH && izgara[ty * GW + tx] > 0;
function engelle(tx, ty, w = 1, h = 1) { for (let y = ty; y < ty + h; y++) for (let x = tx; x < tx + w; x++) if (x >= 0 && y >= 0 && x < GW && y < GH) izgara[y * GW + x] = 0; }
function olayBildir(metin) { if (cb.olay) try { cb.olay(metin); } catch (e) { /* yut */ } }

// ---------------------------------------------------------------- ölçek ve yerleşim
function olcekHesapla() {
  dpr = Math.max(1, window.devicePixelRatio || 1);
  const devW = Math.floor(Math.max(280, sarici.clientWidth) * dpr);
  let k = Math.max(Math.ceil(1.25 * dpr), Math.floor(devW / (40 * T)));
  let gw = Math.floor(devW / (k * T));
  if (gw < 13) { k = Math.max(1, Math.floor(devW / (13 * T))); gw = Math.floor(devW / (k * T)); }
  K = k; GW = Math.min(gw, 64);
}
function bolumlere(roller) {
  const gruplar = [];
  for (const r of roller) {
    const ad = r.departman || 'Uzmanlar';
    let g = gruplar.find(x => x.ad === ad);
    if (!g) { g = { ad, uyeler: [] }; gruplar.push(g); }
    g.uyeler.push(r);
  }
  return gruplar;
}
function yerlesimKur(roller, koru) {
  olcekHesapla();
  const gruplar = bolumlere(roller);
  const enFazlaSutun = Math.max(1, Math.floor((GW - 3) / 3));
  const dep = gruplar.map(g => {
    const c = Math.min(g.uyeler.length, g.uyeler.length > 6 && enFazlaSutun >= 4 ? 4 : 3, enFazlaSutun);
    const satir = Math.ceil(g.uyeler.length / c);
    return { tur: 'bolum', g, c, satir, w: 1 + c * 3, h: 1 + satir * 3 };
  });
  const salon = { tur: 'salon', w: 10, h: 7 }, mutfak = { tur: 'mutfak', w: 8, h: 5 }, toplanti = { tur: 'toplanti', w: 7, h: 5 };
  const liste = GW >= 34 ? [salon, ...dep, mutfak, toplanti] : [...dep, toplanti, mutfak, salon];
  const satirlar = []; let s = null;
  for (const b of liste) {
    if (!s || s.w + 1 + b.w > GW - 2) { s = { bloklar: [], w: -1, h: 0 }; satirlar.push(s); }
    s.w += 1; b.rx = s.w; s.w += b.w; s.h = Math.max(s.h, b.h); s.bloklar.push(b);
  }
  let y = 4;
  for (const sa of satirlar) { const x0 = 1 + Math.max(0, Math.floor((GW - 2 - sa.w) / 2)); for (const b of sa.bloklar) { b.x = x0 + b.rx; b.y = y; } sa.y = y; y += sa.h + 1; }
  GH = y;
  izgara = new Uint8Array(GW * GH).fill(1);
  engelle(0, 0, GW, 3);
  statik = []; poiler = []; bolgeler = [];
  const masaYerleri = new Map();
  const [zc, zx] = tuval(GW * T, GH * T); zemin = zc;
  zeminCiz(zx);
  const ekle = (img, x, yy, sy, ek) => { const o = Object.assign({ img, x, y: yy, sy }, ek || {}); statik.push(o); return o; };
  const bitki = (tx, ty, tur) => { engelle(tx, ty); statik.push({ bitki: tur, x: tx * T, y: ty * T - 10, sy: ty * T + 16, faz: karma(tx * 31 + ty) % 1000 }); };
  const poi = (tx, ty, yon, balon, ek) => { const p = Object.assign({ karo: { tx, ty }, nokta: merkez(tx, ty), yon, balon, sure: [5000, 11000], kullanan: null }, ek || {}); poiler.push(p); return p; };

  for (const b of liste) {
    const bx = b.x, by = b.y;
    if (b.tur === 'bolum') {
      const renk = rolRengi(b.g.uyeler[0]);
      hali(zx, bx, by, b.w, b.h, kar(renk, '#d1ba95', 0.8), kar(renk, '#d1ba95', 0.62));
      bolgeler.push({ ad: b.g.ad, x: bx * T + 3, y: by * T + 2, renk, adet: b.g.uyeler.length });
      b.g.uyeler.forEach((r, i) => {
        const col = bx + 1 + (i % b.c) * 3, row = by + 1 + Math.floor(i / b.c) * 3;
        engelle(col, row, 2, 1);
        izgara[(row + 1) * GW + col] = 4; izgara[(row + 1) * GW + col + 1] = 4;
        masaYerleri.set(r.anahtar, {
          col, row, px: col * T, py: row * T - 6,
          oturak: { x: col * T + 16, y: (row + 1) * T + 14 }, yaklas: { tx: col, ty: row + 1 },
          ziyaret: [{ tx: col - 1, ty: row + 1, yon: 'sag' }, { tx: col + 2, ty: row + 1, yon: 'sol' }], faz: karma(r.anahtar) % 997,
        });
      });
      if (b.h > 4 && b.w > 4) bitki(bx + b.w - 1, by, 1);
    } else if (b.tur === 'salon') {
      haliSalon(zx, bx + 1, by + 1, 8, 5);
      bitki(bx, by, 0); bitki(bx + 9, by, 2); bitki(bx, by + 6, 1); bitki(bx + 9, by + 6, 0);
      engelle(bx + 1, by, 2, 1); ekle(kitaplik(), (bx + 1) * T, by * T - 16, by * T + 16);
      poi(bx + 1, by + 1, 'yukari', () => ['📚', '📖'], {});
      engelle(bx + 7, by); const lmb = ekle(lamba(), (bx + 7) * T + 3, by * T - 14, by * T + 16); lmb.isik = { x: (bx + 7) * T + 8, y: by * T - 8, r: 34 };
      const kRenk = '#5b6b8c';
      engelle(bx + 3, by + 1, 3, 1); ekle(kanepeUst(kRenk), (bx + 3) * T, (by + 1) * T - 10, (by + 1) * T + 6);
      for (let i = 0; i < 3; i++) poi(bx + 3 + i, by + 2, 'asagi', () => ['😌', '☕', '💬', '🎧'], { otur: 'koltuk', nokta: { x: (bx + 3) * T + 8 + i * 16, y: (by + 1) * T + 8 }, sure: [7000, 15000], mola: true });
      engelle(bx + 3, by + 3, 3, 1); ekle(sehpa(), (bx + 3) * T + 4, (by + 3) * T, (by + 3) * T + 14);
      R(zx, (bx + 3) * T + 5, (by + 5) * T - 4, 38, 7, acik(kRenk, 0.15)); R(zx, (bx + 3) * T + 5, (by + 5) * T - 4, 38, 1, acik(kRenk, 0.3));
      engelle(bx + 3, by + 5, 3, 1); ekle(kanepeAlt(kRenk), (bx + 3) * T, (by + 5) * T - 4, (by + 5) * T + 17);
      for (let i = 0; i < 3; i++) poi(bx + 3 + i, by + 4, 'yukari', () => ['😌', '💬', '📱'], { otur: 'otur', nokta: { x: (bx + 3) * T + 8 + i * 16, y: (by + 5) * T + 16 }, sure: [7000, 15000], mola: true });
      engelle(bx + 1, by + 3); ekle(puf('#f59e0b'), (bx + 1) * T, (by + 3) * T + 4, (by + 3) * T + 8);
      poi(bx + 2, by + 3, 'asagi', () => ['😌', '🎧', '📱'], { otur: 'koltuk', nokta: { x: (bx + 1) * T + 8, y: (by + 3) * T + 12 }, sure: [7000, 14000], mola: true });
      engelle(bx + 7, by + 3); ekle(puf('#14b8a6'), (bx + 7) * T, (by + 3) * T + 4, (by + 3) * T + 8);
      poi(bx + 6, by + 3, 'asagi', () => ['😌', '💭', '📱'], { otur: 'koltuk', nokta: { x: (bx + 7) * T + 8, y: (by + 3) * T + 12 }, sure: [7000, 14000], mola: true });
    } else if (b.tur === 'mutfak') {
      mutfakZemin(zx, bx, by, b.w, b.h);
      engelle(bx, by, 4, 1); ekle(tezgah(), bx * T, by * T - 10, by * T + 16);
      kahveYeri = { x: bx * T + 4, y: by * T - 10, w: 10, h: 14, buhar: { x: bx * T + 9, y: by * T - 12 }, kullaniliyor: false };
      const kp = poi(bx, by + 1, 'yukari', () => ['☕', '☕', '😋'], { efekt: 'kahve', kupa: true, mola: true });
      kahveYeri.poi = kp;
      poi(bx + 2, by + 1, 'yukari', () => ['🍲', '⏱️'], {});
      engelle(bx + 4, by); ekle(buzdolabi(), (bx + 4) * T, by * T - 16, by * T + 16); poi(bx + 4, by + 1, 'yukari', () => ['🥤', '🧃'], {});
      engelle(bx + 5, by); const ot = ekle(otomat(), (bx + 5) * T, by * T - 16, by * T + 16); ot.isik = { x: (bx + 5) * T + 7, y: by * T - 2, r: 22, renk: '255,120,120' };
      poi(bx + 5, by + 1, 'yukari', () => ['🍫', '🥨'], {});
      engelle(bx + 6, by); ekle(cop(), (bx + 6) * T + 4, by * T + 6, by * T + 16);
      engelle(bx + 7, by); const sb = ekle(sebil(), (bx + 7) * T + 2, by * T - 10, by * T + 16); sb.sebil = true;
      poi(bx + 7, by + 1, 'yukari', () => ['💧', '😊'], { efekt: 'su', mola: true });
      engelle(bx + 2, by + 3, 2, 1); ekle(masaYuvarlak(), (bx + 2) * T + 4, (by + 3) * T - 1, (by + 3) * T + 14);
      poi(bx + 1, by + 3, 'sag', () => ['🥪', '💬', '😄'], { mola: true }); poi(bx + 4, by + 3, 'sol', () => ['😋', '💬', '👍'], { mola: true });
      bitki(bx + 7, by + 4, 2);
    } else if (b.tur === 'toplanti') {
      hali(zx, bx + 1, by + 2, 4, 3, '#3f5a7a', '#33495f');
      engelle(bx + 1, by + 1, 3, 1);
      panoYeri = { x: (bx + 1) * T, y: (by + 1) * T - 20, w: 48, h: 36, sy: (by + 1) * T + 16 };
      for (let i = 0; i < 3; i++) poi(bx + 1 + i, by + 2, 'yukari', () => ['🤔', '💡', '📌', '🎬'], {});
      engelle(bx + 5, by, 2, 1); ekle(kitaplik(), (bx + 5) * T, by * T - 16, by * T + 16);
      poi(bx + 5, by + 1, 'yukari', () => ['📚', '🔍'], {}); poi(bx + 6, by + 1, 'yukari', () => ['📚', '📖'], {});
      engelle(bx + 6, by + 3); ekle(yazici(), (bx + 6) * T, (by + 3) * T - 2, (by + 3) * T + 16); poi(bx + 5, by + 3, 'sag', () => ['🖨️', '📄'], {});
      bitki(bx, by + 4, 1); engelle(bx + 6, by + 4); ekle(dolap(), (bx + 6) * T + 2, (by + 4) * T - 2, (by + 4) * T + 16);
    }
  }
  // Satırlarda kısa kalan blokların altına süs
  for (const sa of satirlar) for (const b of sa.bloklar) {
    if (sa.h - b.h >= 2) {
      const yy = sa.y + sa.h - 1;
      if (gecilir(b.x, yy)) bitki(b.x, yy, (b.x + yy) % 3);
      if (b.w > 3 && gecilir(b.x + b.w - 1, yy)) bitki(b.x + b.w - 1, yy, (b.x + yy + 1) % 3);
      if (b.w > 6 && sa.h - b.h >= 3 && gecilir(b.x + Math.floor(b.w / 2), yy)) { engelle(b.x + Math.floor(b.w / 2), yy); ekle(dolap(), (b.x + Math.floor(b.w / 2)) * T + 2, yy * T - 2, yy * T + 16); }
    }
  }
  duvarKur();
  for (const p of pencereler) { const tx = Math.floor((p.x + p.w / 2) / T); if (tx !== asansor.karo.tx && gecilir(tx, 3)) poi(tx, 3, 'yukari', () => (gokRenk().gece ? ['🌙', '✨', '🌃'] : ['🌤️', '🏙️', '😌']), {}); }
  // masaları ve kişileri bağla
  for (const [a, m] of masaYerleri) {
    let k = kisiler.get(a);
    const r = (veri.roller || []).find(x => x.anahtar === a);
    if (!k) { k = kisiYap(r, m); kisiler.set(a, k); k.yeniGelen = !ilkKurulum; }
    else {
      k.r = r; k.masa = m; kisiGorunumYenile(k); planTemizle(k);
      // Kadro değişince ayakta olanlar yerinde kalır ve yeni masasına yürür; oturanların oturduğu yer değiştiği için masasına alınır
      const kt = karoBul(k.x, k.y);
      if (k.gitti) { k.x = asansor.ic.x; k.y = asansor.ic.y; k.yer = null; }
      else if (koru && !k.yer && gecilir(kt.tx, kt.ty)) { k.poz = 'ayakta'; k.kalkNokta = null; }
      else { k.yer = 'masa'; k.x = m.oturak.x; k.y = m.oturak.y; k.poz = 'otur'; k.yon = 'yukari'; k.kalkNokta = merkez(m.yaklas.tx, m.yaklas.ty); k.ilk = true; }
    }
    m.sahip = k;
    statik.push({ masa: m, sy: m.row * T + 16 });
    statik.push({ sandalye: m, sy: m.oturak.y - 0.5 });
  }
  for (const a of [...kisiler.keys()]) if (!masaYerleri.has(a)) kisiler.delete(a);
  [dunya, dctx] = tuval(GW * T, GH * T);
  tuvalEl.width = GW * T * K; tuvalEl.height = GH * T * K;
  tuvalEl.style.width = (GW * T * K / dpr) + 'px'; tuvalEl.style.height = (GH * T * K / dpr) + 'px';
  ctx = tuvalEl.getContext('2d'); ctx.imageSmoothingEnabled = false;
  gokDakika = -1;
  const rb = tohumlu(5); bulutlar = Array.from({ length: Math.max(4, Math.floor(GW / 6)) }, () => ({ x0: rb() * GW * T, y: 7 + Math.floor(rb() * 12), w: 10 + Math.floor(rb() * 14), hiz: 1.5 + rb() * 3 }));
}
function zeminCiz(x) {
  for (let ty = 3; ty < GH; ty++) for (let tx = 0; tx < GW; tx++) {
    R(x, tx * T, ty * T, T, T, (tx + ty) % 2 ? '#d7c19d' : '#d1ba95');
    R(x, tx * T, ty * T, T, 1, '#c9b088'); R(x, tx * T, ty * T, 1, T, '#c9b088');
    if ((tx * 7 + ty * 13) % 11 === 0) R(x, tx * T + 5, ty * T + 9, 3, 1, '#cbb28b');
  }
  R(x, 0, 3 * T, GW * T, 3, 'rgba(0,0,0,.13)');
  R(x, 0, GH * T - 3, GW * T, 3, '#a58c68');
}
function hali(x, tx, ty, w, h, renk, kenar) {
  const X = tx * T + 2, Y = ty * T + 2, W = w * T - 4, H = h * T - 4;
  R(x, X, Y, W, H, kenar); R(x, X + 2, Y + 2, W - 4, H - 4, renk);
  R(x, X + 4, Y + 4, W - 8, 1, kar(renk, '#ffffff', 0.18)); R(x, X + 4, Y + H - 5, W - 8, 1, kar(renk, '#ffffff', 0.18));
  R(x, X + 4, Y + 4, 1, H - 8, kar(renk, '#ffffff', 0.18)); R(x, X + W - 5, Y + 4, 1, H - 8, kar(renk, '#ffffff', 0.18));
}
function haliSalon(x, tx, ty, w, h) {
  const X = tx * T, Y = ty * T, W = w * T, H = h * T;
  R(x, X, Y, W, H, '#6e2a22'); R(x, X + 3, Y + 3, W - 6, H - 6, '#9a3b30');
  let sira = 0;
  for (let j = Y + 8; j < Y + H - 7; j += 8, sira++) for (let i = X + 8 + (sira % 2 ? 4 : 0); i < X + W - 7; i += 8) { R(x, i, j - 1, 1, 1, '#c26a4f'); R(x, i - 1, j, 3, 1, '#c26a4f'); R(x, i, j + 1, 1, 1, '#c26a4f'); }
  R(x, X + 5, Y + 5, W - 10, 1, '#c26a4f'); R(x, X + 5, Y + H - 6, W - 10, 1, '#c26a4f');
  for (let i = X + 2; i < X + W - 2; i += 3) { R(x, i, Y - 2, 1, 2, '#e7d3b0'); R(x, i, Y + H, 1, 2, '#e7d3b0'); }
}
function mutfakZemin(x, tx, ty, w, h) {
  for (let j = 0; j < h * 2; j++) for (let i = 0; i < w * 2; i++) R(x, tx * T + i * 8, ty * T + j * 8, 8, 8, (i + j) % 2 ? '#e5e7eb' : '#cbd5e1');
}
function duvarKur() {
  const [c, x] = tuval(GW * T, 3 * T); duvar = c; pencereler = [];
  R(x, 0, 0, GW * T, 3 * T, '#454d5e'); R(x, 0, 0, GW * T, 2, '#363d4b');
  for (let i = 0; i < GW * T; i += 32) R(x, i, 2, 1, 40, '#4c5568');
  const sol = 4, sag = 6, orta = Math.floor(GW / 2) - 1;   // sağda ON AIR levhasına yer
  let tx = sol;
  while (tx < GW - sag) {
    if (tx >= orta && tx < orta + 2) { tx = orta + 2; continue; }
    const sinir = tx < orta ? orta : GW - sag;
    const g = Math.min(3, sinir - tx);
    if (g <= 0) { tx++; continue; }
    pencereler.push({ x: tx * T + 2, y: 5, w: g * T - 4, h: 34 });
    tx += g;
  }
  for (const p of pencereler) {
    R(x, p.x - 2, p.y - 2, p.w + 4, p.h + 4, '#2b313c'); x.clearRect(p.x, p.y, p.w, p.h);
    R(x, p.x, p.y + 15, p.w, 2, '#2b313c'); if (p.w > 24) R(x, p.x + Math.floor(p.w / 2) - 1, p.y, 2, p.h, '#2b313c');
    R(x, p.x - 3, p.y + p.h + 1, p.w + 6, 2, '#cbd5e1');
  }
  R(x, 0, 42, GW * T, 6, '#2f3542'); R(x, 0, 42, GW * T, 1, '#5b6475');
  // pano (mantar) ve tablo
  R(x, 4, 8, 10, 14, '#7c5434'); R(x, 5, 9, 8, 12, '#c8a26b'); R(x, 6, 10, 3, 3, '#fde68a'); R(x, 9, 14, 3, 3, '#93c5fd'); R(x, 6, 16, 3, 3, '#f9a8d4');
  tvYeri = { x: 18, y: 8, w: 38, h: 24 };
  saatYeri = { x: (orta + 1) * T, y: 20 };
  const ax = (GW - 3) * T - 8;
  asansor = { x: ax, y: 8, w: 32, h: 34, karo: { tx: GW - 3, ty: 3 }, ic: { x: (GW - 3) * T + 8, y: 44 }, cikis: merkez(GW - 3, 3) };
  R(x, ax - 3, 5, 38, 38, '#2b313c'); R(x, ax - 2, 6, 36, 36, '#6b7280'); R(x, ax + 12, 1, 8, 4, '#111827');
  yayinYeri = { x: (GW - 6) * T + 3, y: 12, w: 26, h: 9 };
}
function gokRenk() {
  const d = new Date(), s = d.getHours() + d.getMinutes() / 60;
  if (s < 5.5 || s >= 20.5) return { ust: '#0b1330', alt: '#1c2a52', b1: '#1b2442', b2: '#111a33', pen: '#fcd34d', gece: true, isik: 0.3, bulut: '#33405f' };
  if (s < 7) return { ust: '#3b4a7a', alt: '#f2a477', b1: '#4f5a7d', b2: '#2e3654', pen: '#fde68a', gece: true, isik: 0.16, bulut: '#f6c8b0' };
  if (s < 17.5) return { ust: '#6fb3ee', alt: '#cbe6fb', b1: '#a6bad2', b2: '#71859f', pen: '#e0f2fe', gece: false, isik: 0, bulut: '#ffffff' };
  if (s < 19.3) return { ust: '#59609e', alt: '#f59e6b', b1: '#6b6084', b2: '#433b5a', pen: '#fcd34d', gece: false, isik: 0.08, bulut: '#fbd5c0' };
  return { ust: '#1e2552', alt: '#6d4a7a', b1: '#2c2c4f', b2: '#1a1a36', pen: '#fcd34d', gece: true, isik: 0.22, bulut: '#4b4a72' };
}
function gokKur() {
  const g = gokRenk();
  const [c, x] = tuval(GW * T, 48); gok = c;
  const gr = x.createLinearGradient(0, 5, 0, 40); gr.addColorStop(0, g.ust); gr.addColorStop(1, g.alt);
  x.fillStyle = gr; x.fillRect(0, 0, GW * T, 48);
  if (g.gece) { const r = tohumlu(7); for (let i = 0; i < GW * 2; i++) R(x, Math.floor(r() * GW * T), 5 + Math.floor(r() * 16), 1, 1, r() > 0.7 ? '#ffffff' : '#8ea0cc'); R(x, GW * T * 0.72 | 0, 9, 5, 5, '#f1f5f9'); R(x, (GW * T * 0.72 | 0) + 2, 9, 3, 3, g.ust); }
  else R(x, GW * T * 0.2 | 0, 9, 6, 6, '#fde68a');
  const r1 = tohumlu(42);
  let bx = 0; while (bx < GW * T) { const w = 8 + Math.floor(r1() * 14), h = 8 + Math.floor(r1() * 16); R(x, bx, 40 - h, w, h, g.b1); bx += w + Math.floor(r1() * 3); }
  const r2 = tohumlu(99), ls = tohumlu(Math.floor(Date.now() / 600000));
  bx = -4;
  while (bx < GW * T) {
    const w = 10 + Math.floor(r2() * 16), h = 12 + Math.floor(r2() * 20);
    R(x, bx, 41 - h, w, h, g.b2);
    for (let yy = 41 - h + 3; yy < 39; yy += 3) for (let xx = bx + 2; xx < bx + w - 2; xx += 3) {
      const yan = g.gece ? ls() < 0.42 : ls() < 0.1;
      if (yan) R(x, xx, yy, 1, 1, g.pen); else if (!g.gece) R(x, xx, yy, 1, 1, koyu(g.b2, 0.12));
    }
    bx += w + 1 + Math.floor(r2() * 4);
  }
}

// ---------------------------------------------------------------- kişiler
function kisiGorunumYenile(k) { k.gor = gorunumu(k.r); k.imza = k.a + '|' + k.gor.gomlek; k.ad = kisaAd(k.r); }
function kisiYap(r, m) {
  const k = { a: r.anahtar, r, masa: m, x: m.oturak.x, y: m.oturak.y, yon: 'yukari', poz: 'otur', yer: 'masa', kalkNokta: merkez(m.yaklas.tx, m.yaklas.ty),
    plan: [], adim: null, yol: [], adimSayaci: 0, kare: 0, durum: 'bos', balon: null, tasi: null, zipla: 0, faz: karma(r.anahtar) % 13, poi: null, olayda: false, geziyor: false };
  kisiGorunumYenile(k);
  k.ilk = true;   // ilk kararda yürümeden ortak programdaki yerine geçer (ortakPlan)
  return k;
}
function planTemizle(k) {
  if (k.adim && k.adim.t === 'bekle' && k.adim.efekt === 'kahve' && kahveYeri) kahveYeri.kullaniliyor = false;
  k.su = false;
  if (k.ziyaretEdilen && k.ziyaretEdilen.ziyaretci === k) k.ziyaretEdilen.ziyaretci = null;
  k.ziyaretEdilen = null;
  if (k.poi) { k.poi.kullanan = null; k.poi = null; }
  k.plan = []; k.adim = null; k.yol = []; k.olayda = false; k.geziyor = false;
  if (k.tasi === 'kagit' || k.tasi === 'zarf') k.tasi = null;
}
function durumAyarla(k, yeni) {
  if (k.durum === yeni) return;
  k.durum = yeni;
  if (k.olayda && yeni !== 'calis') return;
  planTemizle(k);
}
function masayaPlan(k, d) {
  k.geziyor = false;
  const m = k.masa;
  if (k.yer !== 'masa') {
    k.plan.push({ t: 'git', hedef: m.yaklas, son: m.oturak, hiz: d === 'calis' ? 62 : 40 });
    k.plan.push({ t: 'otur', x: m.oturak.x, y: m.oturak.y, poz: 'otur', yon: 'yukari', yer: 'masa', kalk: merkez(m.yaklas.tx, m.yaklas.ty) });
  }
  k.plan.push({ t: 'bekle', sure: d === 'bos' ? ara(9000, 24000) : 0 });
}
function poiSec(k, sadeceMola) {
  const bos = poiler.filter(p => !p.kullanan && (!sadeceMola || p.mola));
  if (!bos.length) return null;
  return birini(bos);
}
function gezPlan(k, p, surekli) {
  p.kullanan = k; k.poi = p; k.geziyor = true;
  k.plan.push({ t: 'git', hedef: p.karo, son: p.otur ? null : p.nokta });
  if (p.otur) k.plan.push({ t: 'otur', x: p.nokta.x, y: p.nokta.y, poz: p.otur, yon: p.yon, yer: 'poi', kalk: merkez(p.karo.tx, p.karo.ty) });
  else k.plan.push({ t: 'dur', yon: p.yon });
  k.plan.push({ t: 'bekle', sure: surekli ? 0 : ara(p.sure[0], p.sure[1]), efekt: p.efekt, balon: p.balon ? { metin: birini(p.balon(k)), gecikme: ara(400, 2400), sure: 2600 } : null,
    bitince: () => { if (p.kupa) { k.tasi = 'kupa'; k.kupaBitis = an() + 40000; } } });
  k.plan.push({ t: 'fn', f: () => { if (k.poi === p) { p.kullanan = null; k.poi = null; } } });
}
const SOHBET = ['Bugün hangi masal?', 'Pastel renkler 🎨', 'Çocuklar bayılacak!', 'Kurabiye var mı? 🍪', 'Yeni fikir var 💡', 'Sıradaki konu ne?', 'Kahve? ☕', 'Harika sahne!'];
const YANIT = ['😄', '👍', 'Olur!', 'Süper', 'Aynen', 'Bakarım 👀', '☕ Gidelim'];
function sohbetPlan(k) {
  const adaylar = [...kisiler.values()].filter(o => o !== k && o.yer === 'masa' && o.durum === 'bos' && !o.olayda && !o.ziyaretci);
  if (!adaylar.length) return false;
  const o = birini(adaylar);
  const z = o.masa.ziyaret.find(v => gecilir(v.tx, v.ty) && ![...kisiler.values()].some(x => x !== k && karoBul(x.x, x.y).tx === v.tx && karoBul(x.x, x.y).ty === v.ty));
  if (!z) return false;
  k.geziyor = true; o.ziyaretci = k; k.ziyaretEdilen = o;
  k.plan.push({ t: 'git', hedef: z });
  k.plan.push({ t: 'dur', yon: z.yon });
  k.plan.push({ t: 'bekle', sure: ara(4200, 7000), balon: { metin: birini(SOHBET), gecikme: 200, sure: 2200 },
    basla: () => zamanla(1700, () => { if (o.ziyaretci === k) o.balon = { metin: birini(YANIT), bitis: an() + 2200 }; }) });
  k.plan.push({ t: 'fn', f: () => { if (o.ziyaretci === k) o.ziyaretci = null; k.ziyaretEdilen = null; } });
  return true;
}
const VEDA = ['İyi akşamlar! 👋', 'Görüşürüz 👋', 'Yarın görüşürüz', 'Eve gidiyorum 🏠'];
const SELAM = ['Günaydın! ☀️', 'Merhaba! 👋', 'Geldim ☕', 'Hadi başlayalım 💪'];
// Ofis kapanınca: biraz sonra (sırayla) kalkar, vedalaşır, asansöre yürür, binip kaybolur
function gidisPlan(k) {
  k.geziyor = false;
  k.plan.push({ t: 'bekle', sure: azHareket() ? 1 : ara(300, 7000) });
  k.plan.push({ t: 'git', hedef: asansor.karo, hiz: 42, basla: () => { k.balon = { metin: birini(VEDA), bitis: an() + 2600 }; } });
  k.plan.push({ t: 'dur', yon: 'yukari' });
  k.plan.push({ t: 'fn', f: () => asansorAc(2600) });
  k.plan.push({ t: 'bekle', sure: 500 });
  k.plan.push({ t: 'git', dogrudan: [asansor.ic], hiz: 26 });
  k.plan.push({ t: 'fn', f: () => { k.gitti = true; k.balon = null; k.tasi = null; k.yer = null; } });
  k.plan.push({ t: 'bekle', sure: 0 });
}
// Ofis açılınca: asansörden (sırayla) çıkar, selam verir, masasına oturur
function gelisPlan(k, d) {
  const acil = d === 'calis' || d === 'soru';
  k.plan.push({ t: 'bekle', sure: acil || azHareket() ? 1 : ara(300, 9000) });
  k.plan.push({ t: 'fn', f: () => { k.gitti = false; k.x = asansor.ic.x; k.y = asansor.ic.y; k.yer = null; k.poz = 'ayakta'; k.yon = 'asagi'; k.kalkNokta = null; asansorAc(2600); k.balon = { metin: birini(SELAM), bitis: an() + 2600 }; } });
  const m = k.masa;
  k.plan.push({ t: 'git', ilk: asansor.cikis, hedef: m.yaklas, son: m.oturak, hiz: acil ? 62 : 40 });
  k.plan.push({ t: 'otur', x: m.oturak.x, y: m.oturak.y, poz: 'otur', yon: 'yukari', yer: 'masa', kalk: merkez(m.yaklas.tx, m.yaklas.ty) });
  k.plan.push({ t: 'bekle', sure: d === 'bos' ? ara(6000, 15000) : 0 });
}
// ---------------------------------------------------------------- ortak program (her oturumda aynı sahne)
// Zaman DILIM'lere bölünür. Her dilimde her çalışan için seçim, anahtarından ve dilim numarasından tohumlanır: masada kal, bir mekâna
// git (kahve, kanepe, kitaplık, pencere...) ya da masasında oturan bir arkadaşıyla sohbet et. Mekânlar türlerine göre eşleşir (dar
// ekranda yerleşim farklı olsa da aynı tür seçilir); çakışmalar anahtar sırasıyla çözülür. Kalkış dilim başından birkaç saniye sonra.
const DILIM = 90000, DILIM_MOLA = 600000;
let dagilimOnbellek = { imza: '', tablo: null };
function poiTuru(p) {
  if (!p.tur) { let b = ''; try { b = (p.balon && p.balon({})[0]) || ''; } catch (e) {} p.tur = (p.efekt || p.otur || 'dur') + ':' + b; }
  return p.tur;
}
function dagilim(n, mola) {
  const anahtarlar = [...kisiler.keys()].sort();
  const bostakiler = anahtarlar.filter(a => { const x = kisiler.get(a); return x && x.durum === 'bos' && !x.gitti; });
  const imza = n + '|' + (mola ? 1 : 0) + '|' + yerlesimImza + '|' + poiler.length + '|' + bostakiler.join(',');
  if (dagilimOnbellek.imza === imza) return dagilimOnbellek.tablo;
  const turler = new Map();
  for (const p of poiler) { if (mola && !p.mola) continue; const t = poiTuru(p); if (!turler.has(t)) turler.set(t, []); turler.get(t).push(p); }
  const turListe = [...turler.keys()].sort();
  const dolu = new Set(), tablo = new Map(), masada = [];
  for (const a of anahtarlar) {
    const r = tohumlu(karma(a + '|' + n + (mola ? '|mola' : '')));
    const x = r();
    if (!mola && x < 0.45) { tablo.set(a, { tur: 'masa' }); masada.push(a); continue; }
    if (!mola && x < 0.57) { tablo.set(a, { tur: 'sohbet', r: r() }); continue; }
    let secilen = null;
    if (turListe.length) {
      const t0 = Math.floor(r() * turListe.length), s0 = r();
      for (let i = 0; i < turListe.length && !secilen; i++) {
        const liste = turler.get(turListe[(t0 + i) % turListe.length]), b0 = Math.floor(s0 * liste.length);
        for (let j = 0; j < liste.length; j++) { const p = liste[(b0 + j) % liste.length]; if (!dolu.has(p)) { secilen = p; break; } }
      }
    }
    if (secilen) { dolu.add(secilen); tablo.set(a, { tur: 'poi', poi: secilen }); } else { tablo.set(a, { tur: 'masa' }); masada.push(a); }
  }
  // Sohbet: masasında kalan boştaki bir arkadaş (anahtar sırasıyla; her masaya tek ziyaretçi)
  const ziyaret = new Set();
  for (const a of anahtarlar) {
    const s = tablo.get(a); if (s.tur !== 'sohbet') continue;
    const adaylar = masada.filter(b => b !== a && !ziyaret.has(b) && bostakiler.includes(b));
    if (!adaylar.length) { s.tur = 'masa'; continue; }
    s.ortak = adaylar[Math.floor(s.r * adaylar.length)]; ziyaret.add(s.ortak);
  }
  dagilimOnbellek = { imza, tablo };
  return tablo;
}
const sabitSec = (l, tohum) => l[karma(tohum) % l.length];
function ortakPlan(k, mola) {
  const ilk = k.ilk; k.ilk = false;
  const t = ortakZaman(), L = mola ? DILIM_MOLA : DILIM;
  const n = Math.floor(t / L), bas = n * L, bitis = bas + L;
  const s = dagilim(n, mola).get(k.a) || { tur: 'masa' };
  const kalkis = bas + (mola ? 0 : karma(k.a + ':' + n) % 9000);
  const m = k.masa;
  const masaya = son => {
    k.geziyor = false;
    if (k.yer !== 'masa') {
      k.plan.push({ t: 'git', hedef: m.yaklas, son: m.oturak, hiz: 40, aninda: ilk });
      k.plan.push({ t: 'otur', x: m.oturak.x, y: m.oturak.y, poz: 'otur', yon: 'yukari', yer: 'masa', kalk: merkez(m.yaklas.tx, m.yaklas.ty) });
    }
    k.plan.push({ t: 'bekle', bitisOrtak: son });
  };
  if (s.tur === 'masa') { masaya(bitis); return; }
  if (t < kalkis && (ilk || k.yer === 'masa')) { masaya(kalkis); return; }   // kalkış saati gelmedi: masada bekle
  if (s.tur === 'poi') {
    const p = s.poi;
    if (k.poi && k.poi !== p) { k.poi.kullanan = null; k.poi = null; }
    p.kullanan = k; k.poi = p; k.geziyor = true;
    if (!(k.yer === 'poi' && Math.abs(k.x - p.nokta.x) < 1 && Math.abs(k.y - p.nokta.y) < 1)) {
      k.plan.push({ t: 'git', hedef: p.karo, son: p.otur ? null : p.nokta, aninda: ilk });
      if (p.otur) k.plan.push({ t: 'otur', x: p.nokta.x, y: p.nokta.y, poz: p.otur, yon: p.yon, yer: 'poi', kalk: merkez(p.karo.tx, p.karo.ty) });
      else k.plan.push({ t: 'dur', yon: p.yon });
    }
    const tohum = k.a + '#' + n;
    k.plan.push({ t: 'bekle', bitisOrtak: bitis, efekt: p.efekt, balon: p.balon ? { metin: sabitSec(p.balon(k), tohum), gecikme: 400 + karma(tohum) % 2000, sure: 2600 } : null,
      bitince: () => { if (p.kupa) { k.tasi = 'kupa'; k.kupaBitis = an() + 40000; } } });
    k.plan.push({ t: 'fn', f: () => { if (k.poi === p) { p.kullanan = null; k.poi = null; } } });
    return;
  }
  // sohbet: arkadaşın masasına git, birkaç saniye konuş, masaya dön (dilim sonuna kadar orada)
  const o = kisiler.get(s.ortak);
  const sohbetSon = kalkis + 7000 + karma(k.a + '~' + n) % 5000;
  if (!o || o.gitti || o.durum !== 'bos' || t >= sohbetSon - 1500 || (o.ziyaretci && o.ziyaretci !== k)) { masaya(bitis); return; }
  const z = o.masa.ziyaret.find(v => gecilir(v.tx, v.ty));
  if (!z) { masaya(bitis); return; }
  k.geziyor = true; o.ziyaretci = k; k.ziyaretEdilen = o;
  const tohum = k.a + '~' + n;
  k.plan.push({ t: 'git', hedef: z, aninda: ilk });
  k.plan.push({ t: 'dur', yon: z.yon });
  k.plan.push({ t: 'bekle', bitisOrtak: sohbetSon, balon: { metin: sabitSec(SOHBET, tohum), gecikme: 200, sure: 2200 },
    basla: () => zamanla(1700, () => { if (o.ziyaretci === k) o.balon = { metin: sabitSec(YANIT, tohum + 'y'), bitis: an() + 2200 }; }) });
  k.plan.push({ t: 'fn', f: () => { if (o.ziyaretci === k) o.ziyaretci = null; k.ziyaretEdilen = null; } });
}
function karar(k) {
  const d = k.durum;
  if (d !== 'bos' && d !== 'mola') k.ilk = false;
  if (k.gitti) { if (d === 'evde') k.plan.push({ t: 'bekle', sure: 0 }); else gelisPlan(k, d); return; }
  if (d === 'evde') { gidisPlan(k); return; }
  if (d === 'calis' || d === 'hata' || d === 'soru' || d === 'bekliyor' || d === 'uyku' || d === 'sohbet') { masayaPlan(k, d === 'sohbet' ? 'calis' : d); return; }
  if (azHareket()) { k.ilk = false; masayaPlan(k, 'bos'); return; }
  // Boştaki ve moladaki çalışanlar ortak programa göre: her oturumda (telefon, bilgisayar, yenileme) aynı yerde, aynı işle
  ortakPlan(k, d === 'mola');
}
function yolBul(sx, sy, hx, hy) {
  if (!gecilir(hx, hy)) return null;
  if (sx === hx && sy === hy) return [];
  const N = GW * GH, g = new Float32Array(N).fill(Infinity), f = new Float32Array(N).fill(Infinity), geldi = new Int32Array(N).fill(-1), kapali = new Uint8Array(N);
  const bas = sy * GW + sx, son = hy * GW + hx;
  const hs = i => Math.abs((i % GW) - hx) + Math.abs(Math.floor(i / GW) - hy);
  g[bas] = 0; f[bas] = hs(bas);
  const acik = [bas];
  while (acik.length) {
    let bi = 0; for (let i = 1; i < acik.length; i++) if (f[acik[i]] < f[acik[bi]]) bi = i;
    const c = acik[bi]; acik[bi] = acik[acik.length - 1]; acik.pop();
    if (c === son) break;
    if (kapali[c]) continue; kapali[c] = 1;
    const cx = c % GW, cy = Math.floor(c / GW);
    for (const [ox, oy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = cx + ox, ny = cy + oy;
      if (nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue;
      const n = ny * GW + nx; if (kapali[n] || !izgara[n]) continue;
      const ng = g[c] + izgara[n];
      if (ng < g[n]) { g[n] = ng; f[n] = ng + hs(n); geldi[n] = c; acik.push(n); }
    }
  }
  if (geldi[son] < 0) return null;
  const yol = []; let c = son;
  while (c !== bas) { yol.push(c); c = geldi[c]; if (c < 0) return null; }
  yol.reverse();
  return yol.map(i => merkez(i % GW, Math.floor(i / GW)));
}
function adimBasla(k, a) {
  if (a.basla) a.basla();
  if (a.t === 'git' && a.dogrudan) {
    k.yol = a.dogrudan.slice(); k.yer = null; k.poz = 'yuru';
    if (azHareket()) { const son = k.yol[k.yol.length - 1]; k.x = son.x; k.y = son.y; k.yol = []; }
  } else if (a.t === 'git') {
    const yol = [];
    let bas = { x: k.x, y: k.y };
    if (a.ilk) { yol.push(a.ilk); bas = a.ilk; }
    else if (k.yer && k.kalkNokta) { yol.push(k.kalkNokta); bas = k.kalkNokta; }
    let { tx, ty } = karoBul(bas.x, bas.y);
    if (!gecilir(tx, ty)) { const yk = k.kalkNokta && karoBul(k.kalkNokta.x, k.kalkNokta.y); if (yk && gecilir(yk.tx, yk.ty)) { yol.push(k.kalkNokta); tx = yk.tx; ty = yk.ty; } }
    const p = yolBul(tx, ty, a.hedef.tx, a.hedef.ty);
    if (p) yol.push(...p); else yol.push(merkez(a.hedef.tx, a.hedef.ty));
    if (a.son) yol.push(a.son);
    k.yol = yol; k.yer = null; k.poz = 'yuru';
    if (azHareket() || a.aninda) { const s = yol[yol.length - 1]; if (s) { k.x = s.x; k.y = s.y; } k.yol = []; }
  } else if (a.t === 'otur') {
    k.x = a.x; k.y = a.y; k.poz = a.poz; k.yon = a.yon; k.yer = a.yer; k.kalkNokta = a.kalk;
  } else if (a.t === 'dur') {
    k.poz = 'ayakta'; if (a.yon) k.yon = a.yon;
  } else if (a.t === 'bekle') {
    a.bitis = a.bitisOrtak ? an() + Math.max(1, a.bitisOrtak - ortakZaman()) : (a.sure ? an() + a.sure : 0);
    if (a.balon) zamanla(a.balon.gecikme || 0, () => { if (k.adim === a) k.balon = { metin: a.balon.metin, bitis: an() + (a.balon.sure || 2500) }; });
    if (a.efekt === 'kahve' && kahveYeri) kahveYeri.kullaniliyor = true;
    if (a.efekt === 'su') k.su = true;
  } else if (a.t === 'fn') a.f(k);
}
function adimBitti(k) {
  const a = k.adim;
  if (a && a.t === 'bekle') { if (a.efekt === 'kahve' && kahveYeri) kahveYeri.kullaniliyor = false; if (a.efekt === 'su') k.su = false; if (a.bitince) a.bitince(); }
  k.adim = null;
}
function kisiGuncelle(k, dt, s) {
  if (k.balon && k.balon.bitis && s > k.balon.bitis) k.balon = null;
  if (k.tasi === 'kupa' && s > (k.kupaBitis || 0)) k.tasi = null;
  for (let guvenlik = 0; guvenlik < 6 && !k.adim; guvenlik++) {
    k.adim = k.plan.shift() || null;
    if (!k.adim) { karar(k); k.adim = k.plan.shift() || null; }
    if (k.adim) { const a = k.adim; adimBasla(k, a); if (a.t !== 'git' && a.t !== 'bekle') { k.adim = null; continue; } if (a.t === 'git' && !k.yol.length) { k.adim = null; continue; } }
  }
  const a = k.adim; if (!a) return;
  if (a.t === 'git') {
    let kalan = (a.hiz || 40) * dt;
    while (kalan > 0 && k.yol.length) {
      const h = k.yol[0], dx = h.x - k.x, dy = h.y - k.y, d = Math.hypot(dx, dy);
      if (Math.abs(dx) > Math.abs(dy)) k.yon = dx > 0 ? 'sag' : 'sol'; else if (d > 0.01) k.yon = dy > 0 ? 'asagi' : 'yukari';
      if (d <= kalan) { k.x = h.x; k.y = h.y; k.yol.shift(); kalan -= d; } else { k.x += dx / d * kalan; k.y += dy / d * kalan; kalan = 0; }
    }
    k.adimSayaci += (a.hiz || 40) * dt; k.kare = Math.floor(k.adimSayaci / 5) % 4; k.poz = 'yuru';
    if (!k.yol.length) { k.poz = 'ayakta'; adimBitti(k); }
  } else if (a.t === 'bekle') {
    if (a.bitis && s >= a.bitis) adimBitti(k);
  }
}

// ---------------------------------------------------------------- olaylar
function ziyaretYeri(o, k) {
  const dolu = v => [...kisiler.values()].some(x => x !== k && Math.abs(x.x - merkez(v.tx, v.ty).x) < 4 && Math.abs(x.y - merkez(v.tx, v.ty).y) < 4);
  return o.masa.ziyaret.find(v => gecilir(v.tx, v.ty) && !dolu(v)) || o.masa.ziyaret.find(v => gecilir(v.tx, v.ty)) || { tx: o.masa.yaklas.tx, ty: o.masa.yaklas.ty + 1, yon: 'yukari' };
}
// Bir adım bitince sonraki istasyona "dosya" götürülür: veren boştaysa masaya yürür, meşgulse JSON paketi uçar
function teslimOlayi(kimden, kime, etiket) {
  olayBildir(`${kimden.ad} → ${kime.ad}: ${etiket}`);
  if (kimden.gitti || kime.gitti) return;
  if (azHareket() || kimden.durum === 'calis' || kimden.durum === 'hata' || kimden.olayda) {
    paketAt(kimden, kime);
    zamanla(900, () => { kime.balon = { metin: `📄 ${etiket} geldi`, bitis: an() + 2600 }; });
    return;
  }
  planTemizle(kimden); kimden.olayda = true;
  const z = ziyaretYeri(kime, kimden);
  kimden.plan.push({ t: 'git', hedef: z, hiz: 60, basla: () => { kimden.tasi = 'kagit'; } });
  kimden.plan.push({ t: 'dur', yon: z.yon });
  kimden.plan.push({ t: 'bekle', sure: 1900, balon: { metin: `📄 ${etiket} sende`, gecikme: 0, sure: 1800 },
    basla: () => zamanla(1000, () => { kimden.tasi = null; kime.balon = { metin: '👍 Aldım', bitis: an() + 1800 }; }) });
  kimden.plan.push({ t: 'fn', f: () => { kimden.olayda = false; } });
}
function paketAt(a, b) {
  if (azHareket()) return;
  paketler.push({ x0: a.x, y0: a.y - 20, x1: b.x, y1: b.y - 20, bas: an(), sure: 1100 });
}
const panoOnu = () => (panoYeri ? { x: panoYeri.x + panoYeri.w / 2, y: panoYeri.y } : { x: GW * T / 2, y: 64 });
function kutlamaOlayi(metin) {
  olayBildir(metin);
  // Kutlama üretim panosunun önünde: herkesin gördüğü yer
  const yer = panoOnu();
  yuzenler.push({ x: yer.x, y: yer.y - 4, metin, renk: '#4ade80', bas: an(), sure: 3600 });
  if (azHareket()) return;
  konfeti(yer.x, yer.y + 6, 80);
  [...kisiler.values()].filter(k => !k.gitti).forEach((k, i) => zamanla(i * 110, () => { k.zipla = an() + 1000; k.balon = { metin: birini(['🎉', '👏', '🥳', '🙌']), bitis: an() + 2400 }; }));
}
function takildiOlayi(metin, rolA) {
  olayBildir(metin);
  alarmBitis = an() + 15000;
  const k = kisiler.get(rolA) || kisiler.get('director');
  if (k) k.balon = { metin: '❗ Takıldım', bitis: an() + 5000, kenar: '#ef4444' };
  // Her hata Yönetmene gider
  const yon = kisiler.get('director');
  if (yon && yon !== k && !yon.gitti) zamanla(2200, () => { yon.balon = { metin: '🔍 Bakıyorum', bitis: an() + 3200 }; });
}
function onayOlayi(metin) {
  olayBildir(metin);
  const yer = panoOnu();
  yuzenler.push({ x: yer.x, y: yer.y - 4, metin: '🎞 Önizleme hazır', renk: '#facc15', bas: an(), sure: 3600 });
  const y = kisiler.get('publisher');
  if (y && !y.gitti) y.balon = { metin: '🎞 Önizleme hazır!', bitis: an() + 3500 };
}
// Kullanıcı işi iptal etti: alarm çalmaz, Yönetmen kısa bir balonla duyurur
function iptalOlayi(metin) {
  olayBildir(metin);
  const yon = kisiler.get('director');
  if (yon && !yon.gitti) yon.balon = { metin: '✕ İş iptal edildi', bitis: an() + 3200 };
}
function revizyonOlayi(metin) {
  olayBildir(metin);
  const yon = kisiler.get('director');
  if (yon && !yon.gitti) yon.balon = { metin: '↺ Revizyon geliyor', bitis: an() + 3200 };
}
// Yeni hikâye isteği: Yayıncı asansörden zarfı alıp Yönetmene götürür (meşgulse Yönetmen balonla karşılar)
function yeniIsOlayi(metin) {
  olayBildir(metin);
  const lider = kisiler.get('director'); if (!lider || lider.gitti) return;
  if (lider.durum === 'bos' && !lider.olayda && lider.yer !== 'masa' && !azHareket()) { planTemizle(lider); masayaPlan(lider, 'bos'); }
  const kurye = kisiler.get('publisher');
  if (azHareket() || !kurye || kurye.durum !== 'bos' || kurye.olayda || kurye === lider) { lider.balon = { metin: '📨 Yeni hikâye isteği', bitis: an() + 3500 }; asansorAc(2000); return; }
  planTemizle(kurye); kurye.olayda = true;
  kurye.plan.push({ t: 'git', hedef: asansor.karo, hiz: 58 });
  kurye.plan.push({ t: 'dur', yon: 'yukari' });
  kurye.plan.push({ t: 'bekle', sure: 1300, basla: () => { asansorAc(2400); zamanla(900, () => { kurye.tasi = 'zarf'; }); } });
  const z = ziyaretYeri(lider, kurye);
  kurye.plan.push({ t: 'git', hedef: z, hiz: 58 });
  kurye.plan.push({ t: 'dur', yon: z.yon });
  kurye.plan.push({ t: 'bekle', sure: 1900, balon: { metin: '📨 Yeni masal isteği', gecikme: 0, sure: 1800 },
    basla: () => zamanla(1000, () => { kurye.tasi = null; lider.balon = { metin: '👀 Bakıyorum', bitis: an() + 2200 }; }) });
  kurye.plan.push({ t: 'fn', f: () => { kurye.olayda = false; } });
}
function yeniCalisanOlayi(k) {
  olayBildir(`${k.r.ad || k.ad} ekibe katıldı 👋`);
  asansorAc(3200);
  planTemizle(k); k.olayda = true; k.yer = null; k.poz = 'ayakta'; k.yon = 'asagi';
  k.x = asansor.ic.x; k.y = asansor.ic.y;
  const m = k.masa;
  k.plan.push({ t: 'bekle', sure: 900 });
  k.plan.push({ t: 'git', ilk: asansor.cikis, hedef: m.yaklas, son: m.oturak, hiz: 36, basla: () => { k.balon = { metin: '👋 Merhaba!', bitis: an() + 2600 }; } });
  k.plan.push({ t: 'otur', x: m.oturak.x, y: m.oturak.y, poz: 'otur', yon: 'yukari', yer: 'masa', kalk: merkez(m.yaklas.tx, m.yaklas.ty) });
  k.plan.push({ t: 'fn', f: () => {
    k.olayda = false;
    if (!azHareket()) konfeti(k.x, k.y - 26, 40);
    for (const o of ['lider', 'ik']) { const x = kisiler.get(o); if (x && x !== k) zamanla(o === 'ik' ? 900 : 300, () => { x.balon = { metin: 'Hoş geldin! 🎉', bitis: an() + 2600 }; }); }
  } });
}
function kahveMolasi() {
  olayBildir('Kahve molası ☕');
  const bos = [...kisiler.values()].filter(k => k.durum === 'bos' && !k.olayda);
  for (const k of bos.slice(0, 5)) {
    const p = poiler.filter(x => !x.kullanan && x.mola);
    if (!p.length) break;
    planTemizle(k);
    const yakin = p.sort((a, b) => Math.hypot(a.nokta.x - kahveYeri.x, a.nokta.y - kahveYeri.y) - Math.hypot(b.nokta.x - kahveYeri.x, b.nokta.y - kahveYeri.y))[0];
    gezPlan(k, yakin, false);
  }
}
function asansorAc(ms) { kapiBitis = Math.max(kapiBitis, an() + ms); }
function konfeti(x, y, n) {
  const renk = ['#f43f5e', '#facc15', '#22c55e', '#3b82f6', '#a855f7', '#f97316', '#ffffff'];
  for (let i = 0; i < n; i++) parcaciklar.push({ x, y, vx: ara(-55, 55), vy: ara(-95, -30), renk: birini(renk), omur: ara(1.2, 2.2), yas: 0, g: 140 });
}

// ---------------------------------------------------------------- veri
function guncelle(v) {
  if (!tuvalEl) return;
  if (v && v.zaman) saatAyarla(v.zaman);
  onceki = veri; veri = v;
  const roller = v.roller || [];
  const imza = roller.map(r => `${r.anahtar}:${r.departman || ''}:${rolRengi(r)}`).join(',');
  if (imza !== yerlesimImza) {
    yerlesimImza = imza;
    yerlesimKur(roller, !ilkKurulum);
    if (!ilkKurulum) for (const k of kisiler.values()) if (k.yeniGelen) { k.yeniGelen = false; yeniCalisanOlayi(k); }
    ilkKurulum = false;
  }
  for (const r of roller) {
    const k = kisiler.get(r.anahtar); if (!k) continue;
    const eski = k.durum; k.r = r;
    durumAyarla(k, durumu(r, v.dongu));
    if (k.durum === 'calis' && r.metin) k.sonMetin = r.metin;
    if (!onceki || eski === k.durum) continue;
    // adım bitti: kısa bir "✓ son görev" balonu
    if (eski === 'calis' && k.durum === 'bos' && k.sonMetin) { const m = k.sonMetin; k.balon = { metin: /[✓⏸]\s*$/.test(m) ? m : `✓ ${m}`, bitis: an() + 2600, kenar: '#16a34a' }; }
    // hata: kırmızı balon ve titreme
    if (k.durum === 'hata') { k.titre = an() + 2600; k.balon = { metin: `⚠ ${r.metin || 'Hata!'}`, bitis: an() + 3600, kenar: '#ef4444' }; }
  }
}

// ---------------------------------------------------------------- çizim
function ekranCiz(x, m, t) {
  const k = m.sahip, X = m.px + 9, Y = m.py + 1, W = 14, H = 9;
  const d = k ? k.durum : 'bos', masada = k && k.yer === 'masa';
  if (d === 'calis' || d === 'sohbet') istasyonEkrani(x, k, m, X, Y, W, H, t);
  else if (d === 'hata') { R(x, X, Y, W, H, Math.floor(t / 250) % 2 ? '#4a1010' : '#2a0a0a'); glif(x, GLIF_UNLEM, X + 6, Y + 1, '#f87171'); }
  else if (d === 'soru') { R(x, X, Y, W, H, '#3d2f05'); if (Math.floor(t / 500) % 2) glif(x, GLIF_SORU, X + 5, Y + 1, '#facc15'); }
  else if (d === 'bekliyor') { R(x, X, Y, W, H, '#1e293b'); glif(x, GLIF_KUM, X + 5, Y + 2, '#fb923c'); }
  else if (d === 'uyku') R(x, X, Y, W, H, '#0b0d12');
  else if (masada && d === 'bos') { R(x, X, Y, W, H, '#1e3a5f'); R(x, X, Y + H - 1, W, 1, '#0f172a'); R(x, X + 2, Y + 1, 7, 5, '#e2e8f0'); R(x, X + 2, Y + 1, 7, 1, '#94a3b8'); R(x, X + 10, Y + 2, 2, 2, '#fbbf24'); R(x, X + 10, Y + 5, 2, 2, '#60a5fa'); }
  else {
    R(x, X, Y, W, H, '#0b0f17');
    if (d !== 'mola' && d !== 'evde') { const p = (t / 1000 + m.faz) % 2, q = (t / 1400 + m.faz) % 2; R(x, X + Math.floor((p < 1 ? p : 2 - p) * (W - 2)), Y + Math.floor((q < 1 ? q : 2 - q) * (H - 2)), 2, 2, k ? k.gor.gomlek : '#64748b'); }
  }
}
// Çalışırken her istasyonun ekranı kendi işini gösterir
function istasyonEkrani(x, k, m, X, Y, W, H, t) {
  const rk = k.gor.gomlek;
  R(x, X, Y, W, H, koyu(rk, 0.84));
  if (k.a === 'audio_voice') { // ses dalgası
    for (let i = 0; i < W - 2; i++) { const h = 1 + Math.round(Math.abs(Math.sin(t / 120 + i * 0.9) * Math.sin(t / 400 + i)) * 3); R(x, X + 1 + i, Y + 5 - h, 1, h * 2 - 1, i % 2 ? rk : acik(rk, 0.4)); }
  } else if (k.a === 'visual_generator') { // görsel satır satır çiziliyor
    const p = (t / 2600 + m.faz / 7) % 1, satir = Math.floor(p * (H - 2)), renk = ['#7dd3fc', '#86efac', '#fde68a', '#fca5a5', '#c4b5fd'];
    for (let j = 0; j < satir; j++) R(x, X + 1, Y + 1 + j, W - 2, 1, renk[(j + m.faz) % renk.length]);
    R(x, X + 1, Y + 1 + satir, 1 + Math.floor(((t / 90) % 1) * (W - 3)), 1, '#ffffff');
  } else if (k.a === 'editor') { // zaman çizelgesi
    R(x, X + 1, Y + 2, W - 2, 2, '#334155'); R(x, X + 1, Y + 5, W - 2, 2, '#334155');
    for (let i = 0; i < 3; i++) { R(x, X + 1 + i * 4, Y + 2, 3, 2, ['#60a5fa', '#f472b6', '#facc15'][i]); R(x, X + 2 + i * 4, Y + 5, 2, 2, '#4ade80'); }
    R(x, X + 1 + Math.floor((t / 80) % (W - 2)), Y + 1, 1, H - 2, '#f8fafc');
  } else if (k.a === 'publisher') { // yükleme çubuğu
    const p = (t / 3000) % 1;
    R(x, X + 6, Y + 1, 2, 1, '#f8fafc'); R(x, X + 5, Y + 2, 4, 1, '#f8fafc');
    R(x, X + 2, Y + 4, W - 4, 3, '#1f2937'); R(x, X + 2, Y + 4, Math.max(1, Math.round(p * (W - 4))), 3, '#4ade80');
  } else if (k.a === 'qa_safety') { // kontrol listesi işaretleniyor
    const n = Math.floor(t / 400) % 5;
    for (let i = 0; i < 4; i++) { R(x, X + 2, Y + 1 + i * 2, 1, 1, i < n ? '#4ade80' : '#475569'); R(x, X + 4, Y + 1 + i * 2, 7, 1, '#cbd5e1'); }
  } else if (k.a === 'art_director') { // renk paleti
    const renk = ['#f87171', '#fbbf24', '#4ade80', '#60a5fa', '#c084fc', '#f472b6'];
    for (let i = 0; i < 6; i++) R(x, X + 1 + (i % 3) * 4, Y + 1 + Math.floor(i / 3) * 4, 3, 3, renk[(i + Math.floor(t / 500)) % 6]);
  } else { // senarist, yönetmen: yazı satırları
    const kay = Math.floor(t / 170) + m.faz;
    for (let i = 0; i < 4; i++) {
      const s = kay + i, h = karma(m.faz * 7 + s), gir = h % 3, uz = 3 + ((h >>> 3) % 8);
      R(x, X + 1 + gir, Y + 1 + i * 2, Math.min(uz, W - 2 - gir), 1, [rk, '#cbd5e1', '#fbbf24', acik(rk, 0.45)][(h >>> 7) % 4]);
    }
    if (Math.floor(t / 400) % 2) R(x, X + 1 + (karma(kay) % 8), Y + 7, 1, 1, '#ffffff');
  }
}
function ekranAcik(m) { const k = m.sahip; if (!k) return false; return k.durum === 'calis' || k.durum === 'hata' || k.durum === 'soru' || (k.yer === 'masa' && k.durum === 'bos'); }
function kisiCiz(x, k, t) {
  if (k.gitti) return;
  const gor = k.yon === 'yukari' ? 'arka' : k.yon === 'sag' ? 'yan' : k.yon === 'sol' ? 'yanSol' : 'on';
  let poz = k.poz, kare = 0;
  if (poz === 'yuru') kare = k.kare;
  else if (poz === 'otur' && (k.durum === 'calis' || k.durum === 'sohbet') && !azHareket()) kare = 1 + ((Math.floor(t / 150) + k.faz) % 2);
  let dy = 0;
  if (k.zipla > t) { const p = (k.zipla - t) / 1000; dy = -Math.round(Math.abs(Math.sin(p * Math.PI * 2)) * (poz === 'otur' || poz === 'koltuk' ? 2 : 4)); if (poz === 'ayakta' && gor === 'on') poz = 'sevinc'; }
  const nefes = (poz === 'otur' || poz === 'koltuk') && !azHareket() && Math.floor(t / 900 + k.faz) % 3 === 0 ? 1 : 0;
  if (poz === 'otur') {
    x.drawImage(kisiSprite(k, gor, 'otur', kare), Math.round(k.x - 6), Math.round(k.y - 25 + nefes + dy));
    if (k.yer === 'masa') x.drawImage(sandalye(), Math.round(k.x - 7), Math.round(k.y - 12));
    return;
  }
  if (poz === 'koltuk') { x.drawImage(kisiSprite(k, 'on', 'koltuk', 0), Math.round(k.x - 6), Math.round(k.y - 18 + nefes + dy)); return; }
  R(x, Math.round(k.x - 4), Math.round(k.y - 1), 8, 2, 'rgba(0,0,0,.2)');
  const sx = Math.round(k.x - 6), sy = Math.round(k.y - 20 + dy + (poz === 'yuru' && (kare === 1 || kare === 3) ? -1 : 0));
  x.drawImage(kisiSprite(k, gor, poz === 'sevinc' ? 'sevinc' : poz === 'yuru' ? 'yuru' : 'ayakta', kare), sx, sy);
  if (k.tasi) {
    const hx = gor === 'yan' ? sx + 8 : gor === 'yanSol' ? sx + 1 : sx + 9, hy = sy + BOS + 11;
    if (k.tasi === 'kagit') { R(x, hx, hy - 2, 4, 5, '#f8fafc'); R(x, hx + 1, hy - 1, 2, 1, '#94a3b8'); R(x, hx + 1, hy + 1, 2, 1, '#94a3b8'); }
    else if (k.tasi === 'zarf') { R(x, hx - 1, hy - 1, 6, 4, '#fde68a'); R(x, hx, hy, 4, 1, '#d97706'); }
    else if (k.tasi === 'kupa' && gor !== 'arka') { R(x, hx, hy, 3, 3, k.gor.gomlek); R(x, hx + 3, hy + 1, 1, 1, k.gor.gomlek); }
  }
  if (k.su && Math.floor(t / 300) % 2) R(x, Math.round(k.x - 1), Math.round(k.y - 33), 1, 1, '#bfdbfe');
}
function halka(x, k, renk) {
  const X = Math.round(k.x), Y = Math.round(k.poz === 'otur' ? k.y + 1 : k.y);
  R(x, X - 4, Y - 2, 8, 1, renk); R(x, X - 6, Y - 1, 2, 1, renk); R(x, X + 4, Y - 1, 2, 1, renk);
  R(x, X - 7, Y, 1, 1, renk); R(x, X + 6, Y, 1, 1, renk); R(x, X - 6, Y + 1, 2, 1, renk); R(x, X + 4, Y + 1, 2, 1, renk); R(x, X - 4, Y + 2, 8, 1, renk);
}
function duvarDinamik(x, t) {
  // saat
  if (saatYeri) {
    const { x: cx, y: cy } = saatYeri;
    R(x, cx - 7, cy - 6, 14, 12, '#e5e7eb'); R(x, cx - 6, cy - 7, 12, 14, '#e5e7eb'); R(x, cx - 6, cy - 6, 12, 12, '#f8fafc');
    R(x, cx - 1, cy - 6, 2, 1, '#334155'); R(x, cx - 1, cy + 5, 2, 1, '#334155'); R(x, cx - 6, cy - 1, 1, 2, '#334155'); R(x, cx + 5, cy - 1, 1, 2, '#334155');
    const d = new Date(), dk = d.getMinutes() + d.getSeconds() / 60, sa = (d.getHours() % 12) + dk / 60;
    const el = (aci, boy, renk) => { for (let i = 0; i <= boy; i++) R(x, Math.round(cx - 0.5 + Math.sin(aci) * i), Math.round(cy - 0.5 - Math.cos(aci) * i), 1, 1, renk); };
    el(sa / 12 * Math.PI * 2, 3, '#111827'); el(dk / 60 * Math.PI * 2, 5, '#334155'); el(d.getSeconds() / 60 * Math.PI * 2, 5, '#dc2626');
  }
  // televizyon: video / onaylı / yüklenen / hatalı sayaçları
  if (tvYeri && veri) {
    const { x: X, y: Y, w, h } = tvYeri, s = veri.sayaclar || {};
    R(x, X, Y, w, h, '#0b0f17'); R(x, X + 1, Y + 1, w - 2, h - 2, '#0f1d33');
    if (veri.dongu && veri.dongu.bagli === false) R(x, X + 1, Y + 1, w - 2, h - 2, '#05070b');
    else {
      const top = Math.max(1, s.toplam || 0);
      const cubuk = (i, oran, renk) => { const yuk = Math.max(1, Math.round(Math.min(1, oran) * (h - 8))); R(x, X + 5 + i * 8, Y + h - 4 - yuk, 5, yuk, renk); };
      cubuk(0, (s.video || 0) / top, '#60a5fa');
      cubuk(1, (s.onayli || 0) / top, '#4ade80');
      cubuk(2, (s.yuklenen || 0) / top, '#facc15');
      cubuk(3, (s.hatali || 0) / top, '#f87171');
      R(x, X + 3, Y + h - 4, w - 6, 1, '#334155');
    }
    if (Math.floor(t / 900) % 2) R(x, X + w - 3, Y + h - 2, 1, 1, '#22c55e');
  }
  // asansör kapıları
  if (asansor) {
    const hedef = kapiBitis > t ? 1 : 0;
    kapiAcik += (hedef - kapiAcik) * Math.min(1, 0.12 * (azHareket() ? 10 : 1));
    const { x: X, y: Y, w, h } = asansor, ac = Math.round(kapiAcik * 13);
    R(x, X, Y, w, h, '#111827'); R(x, X + 4, Y + 2, w - 8, 3, '#fef9c3');
    R(x, X, Y, 16 - ac, h, '#9aa5b5'); R(x, X + 16 + ac, Y, 16 - ac, h, '#9aa5b5');
    R(x, X + 15 - ac, Y, 1, h, '#6b7280'); R(x, X + 16 + ac, Y, 1, h, '#6b7280'); R(x, X + 2, Y + 2, 1, h - 4, '#c3cad5'); R(x, X + w - 3, Y + 2, 1, h - 4, '#c3cad5');
    R(x, X + 13, Y - 6, 6, 3, '#111827'); R(x, X + 15, Y - 5, 2, 1, kapiBitis > t ? '#22c55e' : '#475569');
  }
  // ON AIR: seslendirme sürerken yanar
  if (yayinYeri) {
    const ses = kisiler.get('audio_voice'), yanik = !!(ses && ses.durum === 'calis');
    const { x: X, y: Y, w, h } = yayinYeri;
    R(x, X - 1, Y - 1, w + 2, h + 2, '#1f2937');
    R(x, X, Y, w, h, yanik ? (Math.floor(t / 600) % 2 ? '#ef4444' : '#dc2626') : '#4b1d1d');
    pikselYazi(x, 'ON AIR', X + 3, Y + 2, yanik ? '#ffffff' : '#9a6a6a');
  }
}
const HARF = { O: ['111', '101', '101', '101', '111'], N: ['101', '111', '111', '111', '101'], A: ['010', '101', '111', '101', '101'], I: ['111', '010', '010', '010', '111'], R: ['110', '101', '110', '101', '101'] };
function pikselYazi(x, metin, X, Y, renk) {
  let cx = X;
  for (const c of metin) {
    const g = HARF[c];
    if (g) for (let j = 0; j < 5; j++) for (let i = 0; i < 3; i++) if (g[j][i] === '1') R(x, cx + i, Y + j, 1, 1, renk);
    cx += c === ' ' ? 2 : 4;
  }
}
function ciz(t) {
  const s = gokRenk(), dk = Math.floor(Date.now() / 60000);
  if (dk !== gokDakika || !gok) { gokDakika = dk; gokKur(); }
  const x = dctx;
  x.clearRect(0, 0, GW * T, GH * T);
  x.drawImage(gok, 0, 0);
  for (const b of bulutlar) { const bx = ((b.x0 + (azHareket() ? 0 : t / 1000 * b.hiz)) % (GW * T + 60)) - 30; bulutCiz(x, Math.round(bx), b.y, b.w, s.bulut); }
  x.drawImage(duvar, 0, 0);
  duvarDinamik(x, t);
  x.drawImage(zemin, 0, 0);
  for (const k of kisiler.values()) {
    if (k.gitti) continue;
    if (k.a === secili) halka(x, k, Math.floor(t / 300) % 2 ? '#facc15' : '#fde68a');
    else if (k.a === uzerinde || k.a === vurgu) halka(x, k, '#ffffff');
  }
  const liste = statik.slice();
  for (const k of kisiler.values()) liste.push({ kisi: k, sy: k.y });
  if (panoYeri) liste.push({ pano: true, sy: panoYeri.sy });
  liste.sort((a, b) => a.sy - b.sy);
  for (const o of liste) {
    if (o.kisi) { const k = o.kisi, ox = k.titre > t && !azHareket() ? Math.round(Math.sin(t / 16)) : 0; k.x += ox; kisiCiz(x, k, t); k.x -= ox; }
    else if (o.masa) { if (o.masa.sahip) { x.drawImage(masaSprite(o.masa.sahip), o.masa.px, o.masa.py); ekranCiz(x, o.masa, t); } }
    else if (o.sandalye) { const k = o.sandalye.sahip; if (!(k && k.yer === 'masa')) x.drawImage(sandalye(), o.sandalye.oturak.x - 7, o.sandalye.oturak.y - 12); }
    else if (o.bitki !== undefined) x.drawImage(bitkiSprite(o.bitki, !azHareket() && Math.floor(t / 1600 + o.faz) % 4 === 0 ? 1 : 0), o.x, o.y);
    else if (o.pano) { x.drawImage(panoSprite(panoAdimlari(), alarmBitis > t && Math.floor(t / 350) % 2 ? 1 : 0, Math.floor(t / 450) % 2), panoYeri.x, panoYeri.y); }
    else if (o.img) {
      x.drawImage(o.img, o.x, o.y);
      if (o.sebil && [...kisiler.values()].some(k => k.su)) { const f = Math.floor(t / 200) % 6; R(x, o.x + 5, o.y + 7 - f, 1, 1, '#eff6ff'); R(x, o.x + 3, o.y + 4 - (f % 3), 1, 1, '#eff6ff'); }
    }
  }
  if (kahveYeri && kahveYeri.kullaniliyor && !azHareket()) for (let i = 0; i < 3; i++) { const f = ((t / 260) + i * 1.7) % 5; R(x, kahveYeri.buhar.x + Math.round(Math.sin(t / 300 + i) * 1.4), Math.round(kahveYeri.buhar.y - f * 2), 1, 1, 'rgba(255,255,255,.75)'); }
  // parçacıklar
  for (const p of parcaciklar) {
    if (p.tur === 'nota') { x.globalAlpha = Math.max(0, 1 - p.yas / p.omur); const px = Math.round(p.x), py = Math.round(p.y); R(x, px, py, 2, 2, p.renk); R(x, px + 1, py - 4, 1, 4, p.renk); R(x, px + 2, py - 4, 2, 1, p.renk); x.globalAlpha = 1; }
    else if (p.tur === 'kivilcim') { x.globalAlpha = Math.max(0, 1 - p.yas / p.omur); R(x, Math.round(p.x), Math.round(p.y), 1, 1, p.renk); x.globalAlpha = 1; }
    else R(x, Math.round(p.x), Math.round(p.y), p.yas < 0.15 ? 1 : 2, 1, p.renk);
  }
  // ajanlar arası JSON paketleri (meşgul bir ajan işi devrederken)
  paketler = paketler.filter(p => t - p.bas < p.sure);
  for (const p of paketler) {
    const q = Math.min(1, (t - p.bas) / p.sure), e = q < 0.5 ? 2 * q * q : 1 - Math.pow(-2 * q + 2, 2) / 2;
    const px = Math.round(p.x0 + (p.x1 - p.x0) * e) - 4, py = Math.round(p.y0 + (p.y1 - p.y0) * e - Math.sin(Math.PI * q) * 26) - 3;
    R(x, px - 1, py - 1, 10, 8, 'rgba(255,209,102,.45)'); R(x, px, py, 8, 6, '#fffdf5'); R(x, px, py, 8, 1, '#4dabf7');
    R(x, px + 1, py + 2, 1, 3, '#4dabf7'); R(x, px + 6, py + 2, 1, 3, '#4dabf7'); R(x, px + 3, py + 3, 2, 1, '#adb5bd');
  }
  // gece / akşam ışığı; ofis kapanınca son kişi çıkınca ışıklar söner
  const kapali = veri && ofisKapaliMi(veri.dongu);
  const icerde = [...kisiler.values()].filter(k => !k.gitti).length;
  isikSonuk += ((kapali ? (icerde ? 0.35 : 1) : 0) - isikSonuk) * (azHareket() ? 1 : 0.04);
  const karanlik = Math.min(0.8, s.isik + isikSonuk * 0.5);
  if (karanlik > 0.01) {
    x.fillStyle = `rgba(10,16,40,${karanlik})`; x.fillRect(0, 0, GW * T, GH * T);
    x.globalCompositeOperation = 'lighter';
    const parilti = (cx, cy, r, renk, guc) => { const g = x.createRadialGradient(cx, cy, 0, cx, cy, r); g.addColorStop(0, `rgba(${renk},${guc})`); g.addColorStop(1, `rgba(${renk},0)`); x.fillStyle = g; x.fillRect(cx - r, cy - r, r * 2, r * 2); };
    for (const o of statik) {
      if (o.masa && ekranAcik(o.masa)) parilti(o.masa.px + 16, o.masa.py + 6, 22, o.masa.sahip.durum === 'calis' ? '120,200,255' : '90,140,220', 0.22);
      if (o.isik && isikSonuk < 0.5) parilti(o.isik.x, o.isik.y, o.isik.r, o.isik.renk || '255,200,120', 0.25);
    }
    if (tvYeri && isikSonuk < 0.5) parilti(tvYeri.x + tvYeri.w / 2, tvYeri.y + tvYeri.h / 2, 26, '120,160,255', 0.16);
    x.globalCompositeOperation = 'source-over';
  }
  const d = (veri && veri.dongu) || {};
  if (d.bagli === false) { x.fillStyle = 'rgba(8,10,16,.35)'; x.fillRect(0, 0, GW * T, GH * T); }
  // ekrana büyüt
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(dunya, 0, 0, GW * T * K, GH * T * K);
  yazilariCiz(t);
}
function panoAdimlari() { return (veri && veri.adimlar) || []; }

// ---------------------------------------------------------------- yazılar (tam çözünürlük)
// Küçük ekranlarda yazılar biraz küçülür ki isimlikler üst üste binmesin
const yaziOlcek = () => Math.max(0.8, Math.min(1, K / dpr / 1.8));
const yaziTipi = (px, kalin = 600) => `${kalin} ${Math.round(px * dpr * yaziOlcek())}px "Segoe UI", system-ui, -apple-system, sans-serif`;
function olc(metin, tip) { const a = tip + '|' + metin; let w = olcuOnbellek.get(a); if (w === undefined) { ctx.font = tip; w = ctx.measureText(metin).width; if (olcuOnbellek.size > 600) olcuOnbellek.clear(); olcuOnbellek.set(a, w); } return w; }
function kisalt(metin, tip, enFazla) {
  if (olc(metin, tip) <= enFazla) return metin;
  let a = 0, b = metin.length;
  while (a < b) { const m = Math.ceil((a + b) / 2); if (olc(metin.slice(0, m) + '…', tip) <= enFazla) a = m; else b = m - 1; }
  return metin.slice(0, a) + '…';
}
function yuvarlak(x, X, Y, W, H, r) { x.beginPath(); x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath(); }
function isimlik(k, X, Y, vurgulu) {
  const tip = yaziTipi(10.5, 650), p = 4 * dpr, h = 15 * dpr, nok = 6 * dpr;
  const metin = (k.r.yeni ? '✨ ' : '') + k.ad;
  const w = olc(metin, tip) + p * 2 + nok + 4 * dpr;
  let L = Math.round(X - w / 2); L = Math.max(2, Math.min(tuvalEl.width - w - 2, L));
  ctx.globalAlpha = vurgulu ? 1 : 0.88;
  yuvarlak(ctx, L, Y, w, h, 4 * dpr); ctx.fillStyle = 'rgba(17,21,30,.82)'; ctx.fill();
  if (vurgulu) { ctx.lineWidth = 1.5 * dpr; ctx.strokeStyle = '#facc15'; ctx.stroke(); }
  ctx.fillStyle = DURUM_RENK[k.durum] || '#94a3b8'; ctx.fillRect(L + p, Y + (h - nok) / 2, nok, nok);
  ctx.fillStyle = '#f1f5f9'; ctx.font = tip; ctx.textBaseline = 'middle'; ctx.fillText(metin, L + p + nok + 4 * dpr, Y + h / 2 + 0.5 * dpr);
  ctx.globalAlpha = 1;
}
function balon(X, Y, metin, kenar, yaziyor, t) {
  const tip = yaziTipi(11.5, 600), p = 7 * dpr, h = 21 * dpr, enFazla = 210 * dpr;
  const noktaW = yaziyor ? 16 * dpr : 0;
  const m = kisalt(metin, tip, enFazla - p * 2 - noktaW);
  const w = olc(m, tip) + p * 2 + noktaW;
  let L = Math.round(X - w / 2); L = Math.max(2, Math.min(tuvalEl.width - w - 2, L));
  const Ust = Math.max(2, Y - h - 6 * dpr);
  ctx.fillStyle = 'rgba(0,0,0,.22)'; yuvarlak(ctx, L + dpr, Ust + 2 * dpr, w, h, 8 * dpr); ctx.fill();
  yuvarlak(ctx, L, Ust, w, h, 8 * dpr); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.lineWidth = 1.6 * dpr; ctx.strokeStyle = kenar; ctx.stroke();
  const ux = Math.max(L + 8 * dpr, Math.min(L + w - 8 * dpr, X));
  ctx.beginPath(); ctx.moveTo(ux - 5 * dpr, Ust + h - 0.5); ctx.lineTo(ux, Ust + h + 6 * dpr); ctx.lineTo(ux + 5 * dpr, Ust + h - 0.5); ctx.closePath(); ctx.fillStyle = '#ffffff'; ctx.fill();
  ctx.beginPath(); ctx.moveTo(ux - 5 * dpr, Ust + h); ctx.lineTo(ux, Ust + h + 6 * dpr); ctx.lineTo(ux + 5 * dpr, Ust + h); ctx.strokeStyle = kenar; ctx.stroke();
  ctx.fillStyle = '#1f2328'; ctx.font = tip; ctx.textBaseline = 'middle'; ctx.fillText(m, L + p, Ust + h / 2 + 0.5 * dpr);
  if (yaziyor) for (let i = 0; i < 3; i++) { const a = azHareket() ? 0.6 : 0.3 + 0.7 * Math.max(0, Math.sin(t / 180 - i * 0.9)); ctx.globalAlpha = a; ctx.fillStyle = kenar; ctx.beginPath(); ctx.arc(L + w - p - noktaW + 3 * dpr + i * 5 * dpr, Ust + h / 2, 1.8 * dpr, 0, Math.PI * 2); ctx.fill(); }
  ctx.globalAlpha = 1;
}
function yazilariCiz(t) {
  // bölüm levhaları
  for (const b of bolgeler) {
    const tip = yaziTipi(9.5, 750), metin = `${b.ad.toLocaleUpperCase('tr-TR')} · ${b.adet}`;
    const X = b.x * K, Y = b.y * K, w = olc(metin, tip) + 10 * dpr, h = 14 * dpr;
    yuvarlak(ctx, X, Y, w, h, 3 * dpr); ctx.fillStyle = 'rgba(30,26,20,.55)'; ctx.fill();
    ctx.fillStyle = '#fdf6e9'; ctx.font = tip; ctx.textBaseline = 'middle'; ctx.fillText(metin, X + 5 * dpr, Y + h / 2 + 0.5 * dpr);
  }
  if (panoYeri) { const tip = yaziTipi(9, 700); ctx.font = tip; ctx.fillStyle = '#334155'; ctx.textBaseline = 'top'; ctx.fillText('ÜRETİM PANOSU', (panoYeri.x + 3) * K, (panoYeri.y - 1) * K - 12 * dpr); }
  // isimlikler
  const sirali = [...kisiler.values()].filter(k => !k.gitti).sort((a, b) => a.y - b.y);
  for (const k of sirali) {
    const vur = k.a === secili || k.a === uzerinde || k.a === vurgu;
    const X = k.x * K;
    if (k.poz === 'otur' && k.yer === 'masa') isimlik(k, X, (k.y + 1) * K, vur);
    else isimlik(k, X, (k.y + 2) * K, vur);
  }
  // balonlar
  for (const k of sirali) {
    let metin = '', kenar = k.gor.gomlek, yaziyor = false;
    if (k.balon) { metin = k.balon.metin; if (k.balon.kenar) kenar = k.balon.kenar; }
    else if (k.durum === 'calis') { metin = k.r.metin || 'Çalışıyor'; yaziyor = true; }
    else if (k.durum === 'hata') { metin = `⚠ ${k.r.metin || 'Hata!'}`; kenar = '#ef4444'; }
    else if (k.durum === 'soru') { metin = '❓ Onayını bekliyorum'; kenar = '#eab308'; }
    else if (k.durum === 'bekliyor') { metin = '⏳ Yeniden deneyeceğim'; kenar = '#f97316'; }
    else if (k.durum === 'uyku' && k.yer === 'masa') metin = '💤';
    if (!metin) continue;
    if (k.durum === 'soru' && !k.balon && !azHareket()) { /* zıplayan soru balonu */ }
    const bas = k.poz === 'otur' && k.yer === 'masa' ? k.y - 38 : k.poz === 'koltuk' ? k.y - 19 : k.y - 23;
    const zip = k.durum === 'soru' && !k.balon && !azHareket() ? Math.round(Math.sin(t / 220) * 2 * dpr) : 0;
    balon(k.x * K, bas * K + zip, metin, kenar, yaziyor, t);
  }
  // yüzen yazılar
  yuzenler = yuzenler.filter(y => t - y.bas < y.sure);
  for (const y of yuzenler) {
    const p = (t - y.bas) / y.sure, tip = yaziTipi(13, 750);
    ctx.globalAlpha = Math.min(1, (1 - p) * 2); ctx.font = tip; ctx.textBaseline = 'middle';
    const w = olc(y.metin, tip), X = Math.max(4, Math.min(tuvalEl.width - w - 4, y.x * K - w / 2)), Y = y.y * K - p * 26 * dpr;
    ctx.lineWidth = 3 * dpr; ctx.strokeStyle = 'rgba(15,23,42,.85)'; ctx.strokeText(y.metin, X, Y); ctx.fillStyle = y.renk; ctx.fillText(y.metin, X, Y);
    ctx.globalAlpha = 1;
  }
  // sahne şeridi: bağlantı durumu ya da panelin verdiği kısa bilgi
  const d = (veri && veri.dongu) || {};
  let serit = '', renk = '#f87171';
  if (d.bagli === false) serit = '⚠ Sunucu bağlantısı yok · yeniden bağlanılıyor';
  else if (d.serit) { serit = d.serit; renk = d.seritRenk || '#93c5fd'; }
  if (serit) {
    const tip = yaziTipi(12.5, 700), w = olc(serit, tip) + 24 * dpr, h = 26 * dpr, X = (tuvalEl.width - w) / 2, Y = 52 * K;
    yuvarlak(ctx, X, Y, w, h, 13 * dpr); ctx.fillStyle = 'rgba(15,18,26,.88)'; ctx.fill(); ctx.lineWidth = 1.5 * dpr; ctx.strokeStyle = renk; ctx.stroke();
    ctx.fillStyle = renk; ctx.font = tip; ctx.textBaseline = 'middle'; ctx.fillText(serit, X + 12 * dpr, Y + h / 2 + 0.5 * dpr);
  }
}

// ---------------------------------------------------------------- döngü
// Sahne bir süre çizilmediyse (gizli sekme / görünmeyen tuval) boştakileri ortak programdaki yerlerine anında taşı
let gizliyken = 0;
function esitle() {
  for (const k of kisiler.values()) if (!k.gitti && !k.olayda && (k.durum === 'bos' || k.durum === 'mola')) { planTemizle(k); k.ilk = true; }
}
function tik(t) {
  if (kapandi) return;
  requestAnimationFrame(tik);
  if (!gorunur || !dunya || !veri) { if (!gizliyken) gizliyken = t; sonCizim = t; return; }
  if ((gizliyken && t - gizliyken > 4000) || (sonCizim && t - sonCizim > 4000)) esitle();
  gizliyken = 0;
  const aralik = azHareket() ? 250 : 33;
  if (t - sonCizim < aralik) return;
  const dt = Math.min(0.5, (t - sonCizim) / 1000); sonCizim = t;   // arka planda kare hızı düşse de yürüyüş gerçek zamanda kalsın
  const kalan = []; for (const z of zamanlayicilar) { if (t >= z.zaman) { try { z.f(); } catch (e) { /* yut */ } } else kalan.push(z); } zamanlayicilar = kalan;
  for (const k of kisiler.values()) kisiGuncelle(k, dt, t);
  istasyonParcaciklari(dt);
  for (const p of parcaciklar) { p.yas += dt; p.vy += p.g * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.985; }
  parcaciklar = parcaciklar.filter(p => p.yas < p.omur);
  ciz(t);
}
// Ses kabininden notalar, render istasyonundan kıvılcımlar
function istasyonParcaciklari(dt) {
  if (azHareket()) return;
  const ses = kisiler.get('audio_voice');
  if (ses && ses.durum === 'calis' && ses.yer === 'masa' && Math.random() < dt * 2.2)
    parcaciklar.push({ x: ses.masa.px + 27 + ara(-2, 3), y: ses.masa.py + 2, vx: ara(-6, 8), vy: -14, renk: '#ff8fb1', omur: 1.8, yas: 0, g: 0, tur: 'nota' });
  const gor = kisiler.get('visual_generator');
  if (gor && gor.durum === 'calis' && gor.yer === 'masa' && Math.random() < dt * 1.6)
    parcaciklar.push({ x: gor.masa.px + 25 + ara(0, 6), y: gor.masa.py + 1, vx: ara(-3, 3), vy: -10, renk: '#7cf2ff', omur: 1.2, yas: 0, g: 0, tur: 'kivilcim' });
}

// ---------------------------------------------------------------- etkileşim
function dunyaNoktasi(e) { const b = tuvalEl.getBoundingClientRect(); return { x: (e.clientX - b.left) / b.width * GW * T, y: (e.clientY - b.top) / b.height * GH * T }; }
function kisiBul(p) {
  let en = null;
  for (const k of kisiler.values()) {
    if (k.gitti) continue;
    let x0 = k.x - 7, x1 = k.x + 7, y0 = k.y - 21, y1 = k.y + 1;
    if (k.poz === 'otur') { y0 = k.y - 24; y1 = k.y - 4; } else if (k.poz === 'koltuk') { y0 = k.y - 17; }
    if (p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 && (!en || k.y > en.y)) en = k;
  }
  return en;
}
function nesneBul(p) {
  const ic = (r, pay = 0) => r && p.x >= r.x - pay && p.x <= r.x + r.w + pay && p.y >= r.y - pay && p.y <= r.y + r.h + pay;
  if (ic(panoYeri)) return { tur: 'pano', ipucu: 'Üretim panosu: aktif hikâyenin 7 adımı · tıkla, işlere git' };
  if (ic(tvYeri)) return { tur: 'tv', ipucu: 'Sayaçlar: video, onaylı, yüklenen, hatalı' };
  if (ic(yayinYeri)) return { tur: 'yayin', ipucu: 'ON AIR: seslendirme sürerken yanar' };
  if (kahveYeri && ic(kahveYeri, 3)) return { tur: 'kahve', ipucu: 'Kahve makinesi: tıkla, boştakiler molaya çıksın ☕' };
  if (ic(asansor)) return { tur: 'asansor', ipucu: 'Asansör: yeni hikâye istekleri buradan gelir' };
  return null;
}
function ipucuGoster(e, metin) {
  if (!ipucuEl) return;
  if (!metin) { ipucuEl.hidden = true; return; }
  ipucuEl.textContent = metin; ipucuEl.hidden = false;
  const s = sarici.getBoundingClientRect();
  let x = e.clientX - s.left + 14, y = e.clientY - s.top + 14;
  const w = ipucuEl.offsetWidth, h = ipucuEl.offsetHeight;
  if (x + w > s.width - 4) x = e.clientX - s.left - w - 10;
  if (y + h > s.height - 4) y = e.clientY - s.top - h - 10;
  ipucuEl.style.left = Math.max(4, x) + 'px'; ipucuEl.style.top = Math.max(4, y) + 'px';
}
function etkilesimKur() {
  const dinle = (tur, f) => { tuvalEl.addEventListener(tur, f); dinleyiciler.push([tur, f]); };
  dinle('pointermove', e => {
    if (!dunya) return;
    const p = dunyaNoktasi(e), k = kisiBul(p);
    uzerinde = k ? k.a : null;
    uzerindeNesne = k ? null : nesneBul(p);
    tuvalEl.style.cursor = k || uzerindeNesne ? 'pointer' : 'default';
    if (e.pointerType === 'mouse') ipucuGoster(e, k ? `${k.r.ad} — ${durumMetni(k)}` : uzerindeNesne ? uzerindeNesne.ipucu : '');
  });
  dinle('pointerleave', () => { uzerinde = null; uzerindeNesne = null; if (ipucuEl) ipucuEl.hidden = true; });
  dinle('click', e => {
    if (!dunya) return;
    const p = dunyaNoktasi(e), k = kisiBul(p);
    if (k) { if (cb.kisiSec) cb.kisiSec(k.a); return; }
    const n = nesneBul(p);
    if (n && n.tur === 'pano' && cb.pano) { cb.pano(); return; }
    if (n && n.tur === 'tv' && cb.tv) { cb.tv(); return; }
    if (n && n.tur === 'kahve') { kahveMolasi(); return; }
    if (n && n.tur === 'asansor') { asansorAc(1500); return; }
    if (n) return;
    if (cb.kisiSec) cb.kisiSec(null);
  });
}
function durumMetni(k) {
  return { calis: k.r.metin || 'çalışıyor', hata: 'hata verdi', evde: 'evde', soru: 'onayını bekliyor', bekliyor: 'yeniden denemeyi bekliyor', mola: 'molada', uyku: 'sunucu bağlantısı yok', bos: k.geziyor ? 'ofiste dolaşıyor' : 'boşta' }[k.durum] || '';
}

// ---------------------------------------------------------------- dış arayüz
function baglan(s) {
  tuvalEl = s.tuval; sarici = s.sarici; ipucuEl = s.ipucu || null; cb = s;
  etkilesimKur();
  let zaman = null;
  const yeniden = () => { if (!veri || kapandi) return; const eskiGW = GW, eskiK = K, eskiDpr = dpr; olcekHesapla(); if (GW !== eskiGW || K !== eskiK || dpr !== eskiDpr) guncelleYerlesim(); };
  if (window.ResizeObserver) { const ro = new ResizeObserver(() => { clearTimeout(zaman); zaman = setTimeout(yeniden, 150); }); ro.observe(sarici); gozlemciler.push(ro); }
  if (window.IntersectionObserver) { const io = new IntersectionObserver(g => { gorunur = g.some(x => x.isIntersecting); }); io.observe(tuvalEl); gozlemciler.push(io); }
  requestAnimationFrame(tik);
}
// React bileşeni kaldırılınca (StrictMode'da aynı tuval yeniden kullanılır) döngüyü ve dinleyicileri bırak
function kapat() {
  kapandi = true;
  for (const o of gozlemciler) o.disconnect();
  if (tuvalEl) for (const [tur, f] of dinleyiciler) tuvalEl.removeEventListener(tur, f);
  gozlemciler = []; dinleyiciler = [];
}
function guncelleYerlesim() {
  const v = veri; if (!v) return;
  yerlesimImza = (v.roller || []).map(r => `${r.anahtar}:${r.departman || ''}:${rolRengi(r)}`).join(',');
  yerlesimKur(v.roller || []);
  for (const k of kisiler.values()) { k.yeniGelen = false; const r = (v.roller || []).find(x => x.anahtar === k.a); if (r) { k.durum = ''; durumAyarla(k, durumu(r, v.dongu)); } }
}
return {
  baglan, guncelle, kapat, durumu, kisaAd, rolRengi,
  sec(a) { secili = a || null; },
  // Salt okunur: her çalışanın sahnedeki yeri (oturumlar arası aynılığı denemek için)
  programOzeti() { const n = Math.floor(ortakZaman() / DILIM); return [...dagilim(n, false)].map(([a, s]) => `${a}|${s.tur}|${s.poi ? poiTuru(s.poi) : (s.ortak || '')}`); },
  sahneOzeti() { return [...kisiler.values()].map(k => ({ a: k.a, durum: k.durum, yer: k.yer || '', poi: k.poi ? poiTuru(k.poi) : '', x: Math.round(k.x), y: Math.round(k.y) })); },
  vurgula(a) { vurgu = a || null; },
  balon(a, metin, ms) { const k = kisiler.get(a); if (k && !k.gitti) k.balon = { metin, bitis: an() + (ms || 2500) }; },
  // Ajanlar arası iş devri (backend'in handoff olayı)
  teslim(kimden, kime, etiket) {
    const b = kisiler.get(kime); if (!b) return;
    const a = kisiler.get(kimden || 'director');
    if (!a || a === b) { b.balon = { metin: '🔁 Yeniden deniyorum', bitis: an() + 2600 }; olayBildir(`${b.ad} adımı yeniden deniyor 🔁`); return; }
    zamanla(250, () => teslimOlayi(a, b, etiket || 'iş'));
  },
  yeniIs: yeniIsOlayi, onayBekliyor: onayOlayi, kutlama: kutlamaOlayi, takildi: takildiOlayi, iptal: iptalOlayi, revizyon: revizyonOlayi, kahveMolasi,
  // Karakter kartı için büyütülmüş portre (sahnedeki sprite'ın aynısı)
  portre(r, olcek = 6) {
    const gor = gorunumu(r), k = { gor, imza: 'portre|' + r.anahtar + '|' + gor.gomlek };
    const s = kisiSprite(k, 'on', 'ayakta', 0);
    const [c, x] = tuval(s.width * olcek, s.height * olcek);
    x.imageSmoothingEnabled = false; x.drawImage(s, 0, 0, c.width, c.height);
    c.className = 'portre'; c.setAttribute('role', 'img'); c.setAttribute('aria-label', (r.ad || r.anahtar) + ' portresi');
    return c;
  },
};
}

// Portreler sahneden bağımsız çizilebilsin diye tuvale bağlanmamış ortak bir motor
let portreMotoru = null;
export function portreCiz(r, olcek) {
  if (!portreMotoru) portreMotoru = pikselOfisOlustur();
  return portreMotoru.portre(r, olcek);
}
