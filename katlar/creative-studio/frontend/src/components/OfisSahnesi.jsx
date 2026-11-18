import { useEffect, useMemo, useRef, useState } from 'react'
import { pikselOfisOlustur } from '../office/pikselOfis.js'
import { AJANLAR, DURUM_ADI, iki } from '../sabitler.js'

// Piksel ofis sahnesi + olay akışı + ekip çipleri (AI Ekip ofisinin düzeni).
// roller: sabitler.rolNesnesi çıktıları; jobs: iş listesi (olaylar buradan çıkarılır).
export default function OfisSahnesi({ roller, jobs, hazir, adimlar, sayaclar, bagli, mock, secili, onSec, onPano, subscribe }) {
  const tuvalRef = useRef(null)
  const sariciRef = useRef(null)
  const ipucuRef = useRef(null)
  const motorRef = useRef(null)
  const cbRef = useRef({})
  const [olaylar, setOlaylar] = useState([])
  cbRef.current = { onSec, onPano, secili }

  useEffect(() => {
    const m = pikselOfisOlustur()
    motorRef.current = m
    if (import.meta.env.DEV) window.__ofis = m // geliştirmede tarayıcı konsolundan deneme için
    m.baglan({
      tuval: tuvalRef.current,
      sarici: sariciRef.current,
      ipucu: ipucuRef.current,
      // aynı ajana yeniden tıklamak seçimi kaldırır (eski paneldeki gibi)
      kisiSec: (id) => cbRef.current.onSec?.(id && id === cbRef.current.secili ? null : id),
      pano: () => cbRef.current.onPano?.(),
      tv: () => cbRef.current.onPano?.('istatistik'),
      olay: (metin) => setOlaylar((l) => [{ zaman: new Date(), metin }, ...l].slice(0, 3)),
    })
    return () => {
      m.kapat()
      motorRef.current = null
    }
  }, [])

  // Sahneye veri
  useEffect(() => {
    // Kadro gelmeden boş ofis kurulursa ilk gelişte herkes "yeni çalışan" sayılırdı
    if (!roller.length) return
    motorRef.current?.guncelle({ roller, dongu: { bagli }, adimlar, sayaclar })
  }, [roller, bagli, adimlar, sayaclar])

  useEffect(() => motorRef.current?.sec(secili), [secili])

  // Ajanlar arası iş devri
  useEffect(
    () =>
      subscribe((msg) => {
        if (msg.type !== 'handoff') return
        motorRef.current?.teslim(msg.from, msg.to, (AJANLAR[msg.from] || AJANLAR.director).is)
      }),
    [subscribe],
  )

  // İş durumundaki geçişler sahnede olay olur (ilk yüklemede olay üretilmez)
  const onceki = useRef(null)
  useEffect(() => {
    if (!hazir) return // ilk anlık görüntü gelmeden karşılaştırma yapma
    const m = motorRef.current
    const simdi = new Map(jobs.map((j) => [j.id, j]))
    const eski = onceki.current
    onceki.current = simdi
    if (!eski || !m) return
    for (const j of jobs) {
      const e = eski.get(j.id)
      const ad = j.title || j.topic || 'günün konusu'
      if (!e) {
        if (j.status === 'queued' || j.status === 'running') m.yeniIs(`📨 Yeni hikâye isteği: ${j.topic || 'konuyu Yönetmen seçecek'}`)
        continue
      }
      if ((j.revision_count || 0) > (e.revision_count || 0)) m.revizyon(`↺ "${ad}" için revizyon istendi`)
      if (e.status === j.status) continue
      if (j.status === 'awaiting_approval') m.onayBekliyor(`🎞 "${ad}" hazır — onayını bekliyor`)
      else if (j.status === 'approved') m.kutlama(`✓ "${ad}" onaylandı`)
      else if (j.status === 'uploaded') m.kutlama(`⬆ "${ad}" yüklendi${mock ? ' (simülasyon)' : ''}`)
      else if (j.status === 'failed') {
        const kim = Object.entries(j.step_status || {}).find(([, s]) => s === 'failed')?.[0]
        m.takildi(`❗ "${ad}" takıldı${j.error ? `: ${j.error}` : ''}`, kim)
      } else if (j.status === 'interrupted') m.takildi(`⏸ "${ad}" yarıda kaldı`, 'director')
    }
  }, [jobs, mock, hazir])

  const calisan = roller.filter((r) => r.durum === 'calis')
  const etiket = `Ofis sahnesi. ${calisan.length ? calisan.map((r) => `${r.ad}: ${r.metin}`).join('; ') : 'Şu an kimse çalışmıyor'}.`

  const olayListesi = useMemo(() => {
    if (olaylar.length) return olaylar
    return [{ zaman: new Date(), metin: 'Ofis canlı. Bir ajana tıkla: logları süzülür, penceresi açılır. Kahve makinesine tıkla, boştakiler molaya çıksın.' }]
  }, [olaylar])

  return (
    <>
      <div className="sahne-sar" ref={sariciRef}>
        <canvas ref={tuvalRef} id="ofisTuval" role="img" aria-label={etiket} />
        <div className="ofis-ipucu" ref={ipucuRef} hidden />
      </div>
      <ul className="olay-akisi" aria-live="polite">
        {olayListesi.map((o, i) => (
          <li key={`${o.zaman.getTime()}-${i}`}>
            <time>{`${iki(o.zaman.getHours())}:${iki(o.zaman.getMinutes())}`}</time>
            <span title={o.metin}>{o.metin}</span>
          </li>
        ))}
      </ul>
      <ul className="ekip-cipler" aria-label="Ekip: bir ajanı seçmek için tıkla">
        {roller.map((r) => (
          <li key={r.anahtar}>
            <button
              type="button"
              className={`ekip-cip ${r.durum}`}
              aria-pressed={secili === r.anahtar}
              title={`${r.ad} · ${r.rol}${r.metin ? ' — ' + r.metin : ''}`}
              style={{ '--rol': r.renk }}
              onClick={() => onSec(secili === r.anahtar ? null : r.anahtar)}
              onMouseEnter={() => motorRef.current?.vurgula(r.anahtar)}
              onMouseLeave={() => motorRef.current?.vurgula(null)}
              onFocus={() => motorRef.current?.vurgula(r.anahtar)}
              onBlur={() => motorRef.current?.vurgula(null)}
            >
              <span className="renk" />
              {r.kisa}
              <span className="d">{DURUM_ADI[r.durum] || r.durum}</span>
            </button>
          </li>
        ))}
      </ul>
    </>
  )
}
