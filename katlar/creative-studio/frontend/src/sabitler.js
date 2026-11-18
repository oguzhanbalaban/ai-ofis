// Panelin her yerinde ortak kullanılan adlar, renkler ve seçenekler.

// Ajanlar: sahne, çipler, log etiketleri ve karakter kartı aynı bilgiyi kullanır.
// renk = karakterin gömleği (sahne), log = koyu terminalde okunur açık ton.
export const AJANLAR = {
  director: {
    kisa: 'Yönetmen', etiket: 'YÖN', renk: '#7b4bb7', log: '#c3a6ff', departman: 'Yönetim & Yayın', is: '📋 görev',
    gorev: 'Günün konusunu seçer, hattı yönetir; bir adım hata verirse yeniden tetikler, QA reddinde işi geri gönderir.',
  },
  storyteller: {
    kisa: 'Senarist', etiket: 'SEN', renk: '#5fae6e', log: '#8ce99a', departman: 'Hikâye & Tasarım', is: '📜 hikâye',
    gorev: 'Konuyu 45-60 saniyelik, sahnelere bölünmüş bir çocuk masalına çevirir; kanca cümlesini ve mesajı yazar.',
  },
  art_director: {
    kisa: 'Görsel Yön.', etiket: 'GYN', renk: '#f39c4a', log: '#ffc078', departman: 'Hikâye & Tasarım', is: '🎨 sahne planı',
    gorev: 'Kahramanın görünüşünü sabitler, her sahne için çizim istemini ve karakter referansını hazırlar.',
  },
  visual_generator: {
    kisa: 'Görsel Üretici', etiket: 'GÖR', renk: '#2fb3a8', log: '#66d9e8', departman: 'Stüdyo', is: '🖼 görseller',
    gorev: 'Sahneleri seçilen çizim motoruyla çizer ve Ken Burns hareketli ara klipleri üretir.',
  },
  audio_voice: {
    kisa: 'Ses', etiket: 'SES', renk: '#ff8fb1', log: '#ffa8c5', departman: 'Stüdyo', is: '🎙 ses',
    gorev: 'Hikâyeyi seslendirir, kelime zamanlarını çıkarır (karaoke altyazı için) ve müziği ekler.',
  },
  editor: {
    kisa: 'Kurgucu', etiket: 'KRG', renk: '#3d5a98', log: '#91a7ff', departman: 'Stüdyo', is: '🎬 kurgu',
    gorev: 'Klipleri, sesi ve karaoke altyazıyı FFmpeg ile 1080x1920 dikey videoya birleştirir.',
  },
  qa_safety: {
    kisa: 'QA', etiket: 'QA ', renk: '#ffd23f', log: '#ffe066', departman: 'Yönetim & Yayın', is: '✅ QA raporu',
    gorev: 'Videoyu ve metni pedagojik ve teknik açıdan denetler; sorun varsa Kurgucuya geri gönderir.',
  },
  publisher: {
    kisa: 'Yayıncı', etiket: 'YAY', renk: '#e63946', log: '#ff8787', departman: 'Yönetim & Yayın', is: '📦 taslak',
    gorev: 'SEO başlığı, açıklama ve etiketleri hazırlar; yalnız senin onayınla (varsayılan private) yükler.',
  },
}
export const AJAN_SIRASI = Object.keys(AJANLAR)

// Üretim hattının 7 adımı (Yönetmen hariç)
export const ADIMLAR = [
  ['storyteller', 'Senarist'],
  ['art_director', 'Görsel Yön.'],
  ['visual_generator', 'Görsel+Hareket'],
  ['audio_voice', 'Ses'],
  ['editor', 'Kurgu'],
  ['qa_safety', 'QA'],
  ['publisher', 'Yayın'],
]

export const STATUS_TR = {
  queued: 'Sırada',
  running: 'Üretiliyor',
  awaiting_approval: 'Onay bekliyor',
  approved: 'Onaylandı',
  uploading: 'Yükleniyor',
  uploaded: 'Yüklendi',
  failed: 'Başarısız',
  interrupted: 'Yarıda kaldı',
}
// rozet rengi sınıfı
export const STATUS_ROZET = {
  queued: '', running: 'r-surer', uploading: 'r-surer', awaiting_approval: 'r-uyari',
  approved: 'r-tamam', uploaded: 'r-tamam', failed: 'r-hata', interrupted: 'r-hata',
}

export const TTS_OPTIONS = [
  ['chatterbox', 'Chatterbox — duygulu anlatım, ekran kartında, ücretsiz'],
  ['elevenlabs', 'ElevenLabs — en doğal ses, ücretli API'],
  ['piper', 'Piper — hızlı ama robotik, çevrimdışı'],
  ['babble', 'Mırıltı — test sesi (gerçek konuşma yok)'],
]
export const IMAGE_OPTIONS = [
  ['flux_local', 'FLUX.2 klein — ekran kartında, ücretsiz'],
  ['fal', 'fal.ai FLUX — API, ~0,03 $/video'],
  ['openai', 'OpenAI gpt-image-1 — API, ~0,45 $/video'],
  ['placeholder', 'Yer tutucu — kodla çizilmiş test görseli'],
]
export const MOTOR_KISA = {
  chatterbox: 'Chatterbox', elevenlabs: 'ElevenLabs', piper: 'Piper', babble: 'Mırıltı', silence: 'Sessiz',
  flux_local: 'FLUX.2 klein', fal: 'fal.ai FLUX', openai: 'gpt-image-1', placeholder: 'Yer tutucu',
}
export const MISSING = {
  chatterbox: ' (kurulu değil)',
  piper: ' (model yok)',
  elevenlabs: ' (anahtar yok)',
  flux_local: ' (kurulu değil)',
  fal: ' (FAL_KEY yok)',
  openai: ' (OPENAI_API_KEY yok)',
}
export function pick(options, avail, wanted, preferred) {
  if (wanted && avail[wanted]) return wanted
  if (preferred && avail[preferred]) return preferred
  return options.map(([k]) => k).find((k) => avail[k]) || options[options.length - 1][0]
}

// Revizyon hedefleri (backend REVISION_TARGETS ile aynı)
export const TARGETS = [
  ['story', 'Hikaye (Senarist)'],
  ['art', 'Görsel promptları (Görsel Yönetmen)'],
  ['visuals', 'Görseller & hareket'],
  ['audio', 'Seslendirme & müzik'],
  ['edit', 'Kurgu & altyazı'],
]

// Sahnedeki durum adları (motorla aynı): calis | hata | soru | uyku | bos
export function ajanDurumu(a, { bagli, onayVar }) {
  if (!bagli) return 'uyku'
  if (a?.status === 'WORKING') return 'calis'
  if (a?.status === 'ERROR') return 'hata'
  if (onayVar && a?.id === 'publisher') return 'soru'
  return 'bos'
}
export const DURUM_ADI = { calis: 'çalışıyor', hata: 'hata verdi', soru: 'onayını bekliyor', uyku: 'bağlantı yok', bos: 'boşta' }
export const DURUM_RENK = { calis: '#4ade80', hata: '#f87171', soru: '#facc15', uyku: '#64748b', bos: '#94a3b8' }

// Sahne motoruna giden rol nesnesi
export function rolNesnesi(meta, ajan, durum) {
  const b = AJANLAR[meta.id] || {}
  return {
    anahtar: meta.id, ad: meta.name, kisa: b.kisa, rol: meta.role, istasyon: meta.station,
    departman: b.departman || 'Ekip', renk: b.renk, durum, metin: ajan?.task || '', isId: ajan?.job_id || null,
    calisiyor: durum === 'calis', hata: durum === 'hata', onayBekliyor: durum === 'soru',
  }
}

export const iki = (n) => String(n).padStart(2, '0')
export function saatMetni(ts) {
  const d = new Date(ts * 1000)
  return d.toLocaleTimeString('tr-TR', { hour12: false })
}
export function goreli(ts) {
  if (!ts) return ''
  const sn = Math.max(0, Date.now() / 1000 - ts)
  if (sn < 45) return 'şimdi'
  if (sn < 3600) return `${Math.round(sn / 60)} dk`
  if (sn < 86400) return `${Math.round(sn / 3600)} sa`
  return `${Math.round(sn / 86400)} gün`
}
export const kisaNo = (id) => String(id || '').split('-').slice(-1)[0]
export const para = (v, n = 3) => `$${Number(v || 0).toFixed(n)}`
