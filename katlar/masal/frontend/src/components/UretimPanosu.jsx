import { useMemo, useState } from 'react'
import { ADIMLAR, AJANLAR, MOTOR_KISA, STATUS_ROZET, STATUS_TR, goreli, kisaNo, para } from '../sabitler.js'

// Aktif işin üretim hattı şeridi (sahnenin üstünde)
export function HatSeridi({ job, onAc }) {
  if (!job) {
    return (
      <div className="hat">
        <span className="hat-bos">Henüz iş yok. “+ Yeni hikâye” ile başlayın.</span>
      </div>
    )
  }
  const steps = job.step_status || {}
  const bekliyor = job.status === 'awaiting_approval'
  return (
    <div className="hat">
      <button type="button" className="hat-is" onClick={() => onAc(job.id)} title={`${job.id} · ayrıntılar`}>
        <span className={`rozet ${STATUS_ROZET[job.status] || ''}`}>{STATUS_TR[job.status] || job.status}</span>
        <span className="hat-ad">{job.title || job.topic || 'Konu seçiliyor…'}</span>
      </button>
      <ol className="hat-adimlar" aria-label="Üretim hattı adımları">
        {ADIMLAR.map(([id, label]) => (
          <li key={id} className={`hat-adim ${steps[id] || 'pending'}`} title={`${label}: ${steps[id] || 'pending'}`}>
            <i />
            {label}
          </li>
        ))}
      </ol>
      {bekliyor && (
        <button type="button" className="hud-dugme onay nabiz" onClick={() => onAc(job.id)}>
          🎞 Önizle & Onayla
        </button>
      )}
      {job.error && job.status === 'failed' && <div className="hat-hata">{job.error}</div>}
    </div>
  )
}

// Bir işin 7 adımlık ilerleme çubuğu
export function AdimCubugu({ job }) {
  const s = job.step_status || {}
  return (
    <span className="adimlar" aria-hidden="true">
      {ADIMLAR.map(([id]) => (
        <i key={id} className={s[id] === 'done' ? 'tamam' : s[id] === 'working' ? 'simdi' : s[id] === 'failed' ? 'hata' : ''} />
      ))}
    </span>
  )
}

const SERITLER = [
  { a: 'sira', ad: 'Sırada', renk: 'var(--soluk)', durumlar: ['queued'] },
  { a: 'uretim', ad: 'Üretiliyor', renk: 'var(--mavi)', durumlar: ['running', 'uploading'] },
  { a: 'onay', ad: 'Onay bekliyor', renk: 'var(--sari)', durumlar: ['awaiting_approval'] },
  { a: 'bitti', ad: 'Tamamlandı', renk: 'var(--yesil)', durumlar: ['approved', 'uploaded'] },
  { a: 'sorun', ad: 'Sorunlu', renk: 'var(--kirmizi)', durumlar: ['failed', 'interrupted'] },
]

function okuAyar() {
  try {
    return JSON.parse(localStorage.getItem('masal.pano') || '{}') || {}
  } catch {
    return {}
  }
}

function sahipMetni(j) {
  if (j.status === 'running') {
    const a = j.current_agent && AJANLAR[j.current_agent]
    return a ? [j.current_agent, `${a.kisa} çalışıyor`] : ['director', 'Yönetmen hazırlıyor']
  }
  if (j.status === 'queued') return ['director', 'sırasını bekliyor']
  if (j.status === 'awaiting_approval') return ['publisher', 'onayını bekliyor']
  if (j.status === 'uploading') return ['publisher', 'yüklüyor']
  if (j.status === 'failed') {
    const kim = Object.entries(j.step_status || {}).find(([, s]) => s === 'failed')?.[0]
    return [kim || 'director', `${(AJANLAR[kim] || AJANLAR.director).kisa} adımında takıldı`]
  }
  if (j.status === 'interrupted') return ['director', 'sunucu kapanınca yarıda kaldı']
  return null
}

function motorlar(j) {
  return [j.image && `🎨 ${MOTOR_KISA[j.image] || j.image}`, j.tts && `🎙 ${MOTOR_KISA[j.tts] || j.tts}`].filter(Boolean).join(' · ')
}

function IsKarti({ j, onAc }) {
  const sahip = sahipMetni(j)
  const a = sahip && AJANLAR[sahip[0]]
  return (
    <button type="button" className={`gkart s-${j.status}`} onClick={() => onAc(j.id)} title={`${j.id} · ayrıntılar`}>
      <div className="gk-ust">
        <span className="gk-no">#{kisaNo(j.id)}</span>
        {j.mock && <span className="gk-rozet mock">mock</span>}
        {j.revision_count ? <span className="gk-rozet rev">↺ {j.revision_count}</span> : null}
        {j.status === 'running' && <span className="gk-rozet calisiyor">üretiliyor</span>}
        <span className="gk-zaman">{goreli(j.updated_at || j.created_at)}</span>
      </div>
      <div className="gk-govde">
        {j.thumb_url ? <img src={j.thumb_url} alt="" loading="lazy" /> : <span className="gk-ph">🎞</span>}
        <div className="gk-baslik">{j.title || j.topic || 'Konu seçiliyor…'}</div>
      </div>
      <div className="gk-adim">
        <AdimCubugu job={j} />
        <span>{STATUS_TR[j.status] || j.status}</span>
      </div>
      {sahip && (
        <div className="gk-sahip" style={{ '--rol': a?.renk }}>
          <span className="av">{(a?.kisa || '?').slice(0, 2)}</span>
          <span className="ne">{sahip[1]}</span>
        </div>
      )}
      {j.status === 'failed' && j.error && <div className="gk-hata">{j.error}</div>}
      <div className="gk-alt">
        <span className="gk-proje">{motorlar(j) || '—'}</span>
        <span className="gk-tok">
          {j.duration ? `${j.duration.toFixed(1)} sn · ` : ''}
          {para(j.cost_usd)}
        </span>
      </div>
    </button>
  )
}

// İşler panosu: şeritler (pano) ya da tablo (liste); arama ve görünüm tarayıcıda hatırlanır
export default function UretimPanosu({ jobs, onAc }) {
  const [ayar, setAyar] = useState(() => ({ gorunum: 'pano', ...okuAyar() }))
  const [ara, setAra] = useState('')
  const [acikSerit, setAcikSerit] = useState({})
  const kaydet = (y) => {
    const n = { ...ayar, ...y }
    setAyar(n)
    try {
      localStorage.setItem('masal.pano', JSON.stringify(n))
    } catch {
      /* gizli pencere vb. */
    }
  }

  const suzulmus = useMemo(() => {
    const q = ara.trim().toLocaleLowerCase('tr-TR')
    if (!q) return jobs
    return jobs.filter((j) =>
      [j.id, j.title, j.topic, STATUS_TR[j.status], motorlar(j)].filter(Boolean).join(' ').toLocaleLowerCase('tr-TR').includes(q),
    )
  }, [jobs, ara])

  const ozet = `${jobs.filter((j) => ['queued', 'running', 'uploading'].includes(j.status)).length} sürüyor · ${
    jobs.filter((j) => j.status === 'awaiting_approval').length
  } onay bekliyor · gösterilen ${suzulmus.length}`

  return (
    <section aria-labelledby="panoBaslik" id="uretimPanosu">
      <div className="bolum-baslik">
        <h2 id="panoBaslik">Üretim panosu</h2>
        <span className="soluk">{ozet}</span>
      </div>
      <div className="pano-arac">
        <input type="search" value={ara} onChange={(e) => setAra(e.target.value)} placeholder="Ara: başlık, konu, no, motor…" aria-label="İşlerde ara" autoComplete="off" />
        <div className="donem" role="group" aria-label="Görünüm">
          <button type="button" aria-pressed={ayar.gorunum === 'pano'} onClick={() => kaydet({ gorunum: 'pano' })}>
            ▦ Pano
          </button>
          <button type="button" aria-pressed={ayar.gorunum === 'liste'} onClick={() => kaydet({ gorunum: 'liste' })}>
            ☰ Liste
          </button>
        </div>
      </div>
      {ayar.gorunum === 'pano' ? (
        <div className="pano2">
          {SERITLER.map((s) => {
            const liste = suzulmus.filter((j) => s.durumlar.includes(j.status))
            const sinir = acikSerit[s.a] ? liste.length : s.a === 'bitti' || s.a === 'sorun' ? 6 : 12
            return (
              <div key={s.a} className={`serit2${liste.length ? '' : ' bos'}`} style={{ '--s-renk': s.renk }}>
                <div className="serit2-bas">
                  <span className="nokta" />
                  {s.ad}
                  <span className="adet">{liste.length}</span>
                </div>
                <div className="serit2-govde">
                  {!liste.length && <div className="serit2-bos">Boş</div>}
                  {liste.slice(0, sinir).map((j) => (
                    <IsKarti key={j.id} j={j} onAc={onAc} />
                  ))}
                  {liste.length > sinir && (
                    <button type="button" className="serit2-daha" onClick={() => setAcikSerit((x) => ({ ...x, [s.a]: true }))}>
                      +{liste.length - sinir} daha
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        <div className="liste-kap">
          <table className="liste-tablo">
            <thead>
              <tr>
                <th>Hikâye</th>
                <th>Durum</th>
                <th className="gizle-m">Adımlar</th>
                <th className="gizle-m">Motorlar</th>
                <th className="sag">Süre</th>
                <th className="sag">Maliyet</th>
                <th className="sag gizle-m">Zaman</th>
              </tr>
            </thead>
            <tbody>
              {!suzulmus.length && (
                <tr>
                  <td colSpan={7} className="soluk">
                    Liste boş.
                  </td>
                </tr>
              )}
              {suzulmus.map((j) => (
                <tr key={j.id} tabIndex={0} onClick={() => onAc(j.id)} onKeyDown={(e) => e.key === 'Enter' && onAc(j.id)}>
                  <td>
                    <div className="liste-baslik">{j.title || j.topic || j.id}</div>
                    <div className="soluk mono kucuk-yazi">
                      #{kisaNo(j.id)}
                      {j.revision_count ? ` · ${j.revision_count} rev.` : ''}
                    </div>
                  </td>
                  <td>
                    <span className={`rozet ${STATUS_ROZET[j.status] || ''}`}>{STATUS_TR[j.status] || j.status}</span>
                  </td>
                  <td className="gizle-m">
                    <AdimCubugu job={j} />
                  </td>
                  <td className="gizle-m soluk">{motorlar(j) || '—'}</td>
                  <td className="sag">{j.duration ? `${j.duration.toFixed(1)} sn` : '—'}</td>
                  <td className="sag">{para(j.cost_usd)}</td>
                  <td className="sag gizle-m soluk">{goreli(j.updated_at || j.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}
