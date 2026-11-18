import { useEffect, useRef, useState } from 'react'
import { api } from '../useStudio.js'

// Günlük özet (AI Ekip ofisindeki 12:30 / 18:30 özetlerinin karşılığı): o günün özeti her an üretilebilir.
function Tablo({ satirlar }) {
  const hucre = (s) => s.split('|').slice(1, -1).map((x) => x.trim())
  const [bas, , ...govde] = satirlar
  return (
    <div className="tablo-sar">
      <table className="kul-tablo">
        <thead>
          <tr>
            {hucre(bas).map((h, i) => (
              <th key={i}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {govde.map((s, i) => (
            <tr key={i}>
              {hucre(s).map((h, j) => (
                <td key={j}>{h}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function OzetMetni({ metin }) {
  const bloklar = []
  let tablo = []
  for (const s of metin.split('\n')) {
    if (s.startsWith('|')) {
      tablo.push(s)
      continue
    }
    if (tablo.length) {
      bloklar.push({ tablo })
      tablo = []
    }
    if (s.trim()) bloklar.push({ s })
  }
  if (tablo.length) bloklar.push({ tablo })
  const kalin = (x) => x.split(/\*\*(.+?)\*\*/g).map((p, i) => (i % 2 ? <b key={i}>{p}</b> : p))
  return (
    <div className="ozet-metin">
      {bloklar.map((b, i) => {
        if (b.tablo) return <Tablo key={i} satirlar={b.tablo} />
        if (b.s.startsWith('# ')) return null
        if (b.s.startsWith('## ')) return <h3 key={i}>{b.s.slice(3)}</h3>
        if (b.s.startsWith('- ')) return <div key={i} className="ozet-madde">• {kalin(b.s.slice(2))}</div>
        if (b.s.startsWith('_')) return <div key={i} className="soluk kucuk-yazi">{b.s.replace(/^_|_$/g, '')}</div>
        return <p key={i}>{kalin(b.s)}</p>
      })}
    </div>
  )
}

export default function OzetDiyalogu({ acik, onKapat, config }) {
  const ref = useRef(null)
  const [tarih, setTarih] = useState(() => new Date().toLocaleDateString('sv-SE'))
  const [ozet, setOzet] = useState(null)
  const [hata, setHata] = useState(null)

  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (acik && !d.open) d.showModal()
    else if (!acik && d.open) d.close()
  }, [acik])

  useEffect(() => {
    if (!acik) return
    setOzet(null)
    setHata(null)
    api(`/api/ozet?tarih=${tarih}`)
      .then(setOzet)
      .catch((e) => setHata(e.message))
  }, [acik, tarih])

  const saatler = (config?.ozet_saatleri || '').split(',').filter((s) => /^\d{1,2}:\d{2}$/.test(s.trim()))
  return (
    <dialog className="diyalog ozet" ref={ref} aria-labelledby="ozetBaslik" onClose={onKapat} onCancel={onKapat}
      onMouseDown={(e) => e.target === e.currentTarget && onKapat()}>
      <div className="diyalog-ic">
        <div className="ozet-bas">
          <h2 id="ozetBaslik">📄 Günlük özet</h2>
          <input type="date" value={tarih} max={new Date().toLocaleDateString('sv-SE')} onChange={(e) => e.target.value && setTarih(e.target.value)} aria-label="Tarih" />
          <button className="kapat" type="button" aria-label="Kapat" onClick={onKapat}>
            ×
          </button>
        </div>
        <div className="soluk kucuk-yazi">
          {saatler.length
            ? `Her gün ${saatler.join(' ve ')}'da kendiliğinden yazılır (backend\\data\\raporlar) ve bildirilir. Burada istediğin an görürsün.`
            : 'Otomatik özet kapalı (OZET_SAATLERI). Burada istediğin an görürsün.'}
        </div>
        {hata && <div className="form-hata">{hata}</div>}
        {!ozet && !hata && <div className="soluk">Hazırlanıyor…</div>}
        {ozet && <OzetMetni metin={ozet.metin} />}
      </div>
    </dialog>
  )
}
