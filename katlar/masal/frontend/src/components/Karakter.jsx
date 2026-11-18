import { useEffect, useMemo, useRef, useState } from 'react'
import { portreCiz } from '../office/pikselOfis.js'
import { AJANLAR, DURUM_ADI, DURUM_RENK, MOTOR_KISA, STATUS_TR, kisaNo, para } from '../sabitler.js'
import { LogSatiri } from './LogTerminal.jsx'

// Sahnedeki sprite'ın büyütülmüş hali
export function Portre({ rol, olcek = 5 }) {
  const ref = useRef(null)
  useEffect(() => {
    if (!ref.current || !rol) return
    ref.current.replaceChildren(portreCiz(rol, olcek))
  }, [rol?.anahtar, rol?.renk, olcek])
  return <div className="portre-kap" ref={ref} />
}

function motorMetni(id, config) {
  if (!config) return '—'
  const llm = config.mock_mode ? 'Mock (hazır masal verisi)' : `${config.llm_provider || 'LLM'}${config.llm_model ? ' · ' + config.llm_model : ''}`
  switch (id) {
    case 'director':
    case 'storyteller':
    case 'art_director':
      return llm
    case 'visual_generator':
      return `${MOTOR_KISA[config.image_provider] || config.image_provider} (varsayılan; iş başına seçilebilir)`
    case 'audio_voice':
      return `${MOTOR_KISA[config.tts_provider] || config.tts_provider} · zaman damgası: ${config.timestamp_provider || '—'}`
    case 'editor':
      return `FFmpeg · 1080x1920 · ${config.render_fps || 60} fps · karaoke altyazı`
    case 'qa_safety':
      return 'Teknik ölçüm (ffprobe) + pedagojik ve güvenlik kontrolleri'
    case 'publisher':
      return `Taslak + SEO · privacyStatus=${config.youtube_privacy_status} · yükleme ${config.upload_possible ? 'onayla açık' : 'kapalı'}`
    default:
      return '—'
  }
}

function adimDurumu(j, id) {
  if (id === 'director') return j.status === 'failed' ? 'failed' : ['approved', 'uploaded', 'awaiting_approval'].includes(j.status) ? 'done' : 'working'
  return (j.step_status || {})[id] || 'pending'
}
const ADIM_ISARET = { done: '✓', failed: '✕', working: '…', pending: '·' }

// Karakter kartı (AI Ekip'teki gibi): portre, durum, istatistik, görevi, motoru, son işleri ve logları
export function KarakterKarti({ rol, stats, config, jobs, logs, onKapat, onIsAc, onLoglar }) {
  const ref = useRef(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (rol && !d.open) d.showModal()
    else if (!rol && d.open) d.close()
  }, [rol])
  const id = rol?.anahtar
  const b = AJANLAR[id] || {}
  const s = (stats?.steps || {})[id]
  const isler = useMemo(() => (id ? jobs.filter((j) => id === 'director' || adimDurumu(j, id) !== 'pending').slice(0, 6) : []), [jobs, id])
  const sonLog = useMemo(() => (id ? logs.filter((l) => l.agent === id).slice(-8) : []), [logs, id])
  const toplam = s ? s.success + s.fail : 0
  return (
    <dialog className="diyalog karakter" ref={ref} aria-labelledby="krAd" onClose={onKapat} onCancel={onKapat}
      onMouseDown={(e) => e.target === e.currentTarget && onKapat()}>
      {rol && (
        <div className="kr" style={{ '--rol': b.renk }}>
          <header className="kr-bas">
            <div className="kr-portre">
              <Portre rol={rol} olcek={5} />
            </div>
            <div className="kr-kim">
              <div className="kr-dep">{rol.departman}</div>
              <h2 id="krAd">{rol.ad}</h2>
              <div className="kr-tr">
                {rol.rol} · {rol.istasyon}
              </div>
              <div className="kr-rozetler">
                <span className="kr-cip" style={{ '--d-renk': DURUM_RENK[rol.durum] }}>
                  <i />
                  {DURUM_ADI[rol.durum] || rol.durum}
                </span>
                <span className="kr-cip">kurucu ekip</span>
                {rol.metin && <span className="kr-cip">{rol.metin}</span>}
              </div>
            </div>
            <button className="kapat" type="button" aria-label="Kapat" onClick={onKapat}>
              ×
            </button>
          </header>
          <div className="kr-stat" aria-label="Tüm işler">
            <div>
              <b>{toplam}</b>
              <span>adım çalıştı</span>
            </div>
            <div>
              <b>{s && s.rate != null ? `%${Math.round(s.rate * 100)}` : '—'}</b>
              <span>başarı</span>
            </div>
            <div>
              <b>{s ? s.fail : 0}</b>
              <span>hata</span>
            </div>
            <div>
              <b>{s?.avg_seconds != null ? `${s.avg_seconds} sn` : '—'}</b>
              <span>ort. süre</span>
            </div>
            <div>
              <b>{s ? para(s.cost_usd, 3) : '$0.000'}</b>
              <span>tahmini maliyet</span>
            </div>
          </div>
          <div className="kr-govde">
            <section className="kr-bolum">
              <h3>Görevi</h3>
              <div className="kr-metin">{b.gorev}</div>
              <div className="kr-kucuk">Devrettiği iş: {b.is}</div>
            </section>
            <section className="kr-bolum">
              <h3>Kullandığı motor</h3>
              <div className="kr-metin">{motorMetni(id, config)}</div>
            </section>
            <section className="kr-bolum">
              <h3>Katıldığı son işler</h3>
              {isler.length ? (
                <ul className="kr-isler">
                  {isler.map((j) => {
                    const d = adimDurumu(j, id)
                    return (
                      <li key={j.id}>
                        <button type="button" onClick={() => onIsAc(j.id)}>
                          <span className={`no adim-${d}`}>{ADIM_ISARET[d]}</span>
                          <span className="bas" title={j.title || j.topic}>
                            #{kisaNo(j.id)} {j.title || j.topic}
                          </span>
                          <span className="as">{STATUS_TR[j.status] || j.status}</span>
                        </button>
                      </li>
                    )
                  })}
                </ul>
              ) : (
                <div className="kr-kucuk">Henüz bir işe katılmadı.</div>
              )}
            </section>
            <section className="kr-bolum">
              <h3>
                Son loglar
                <button type="button" className="baglanti ek" onClick={onLoglar}>
                  terminalde süz →
                </button>
              </h3>
              <div className="kr-log">
                {sonLog.length ? sonLog.map((l) => <LogSatiri key={l.id} log={l} />) : <div className="kr-kucuk">Log yok.</div>}
              </div>
            </section>
          </div>
        </div>
      )}
    </dialog>
  )
}

// Seçili ajanın sağ altta açılan penceresi (AI Ekip'teki sohbet penceresinin yerinde): ayrıntılar + canlı logları
export function AjanPenceresi({ rol, stats, jobs, logs, onKapat, onKart, onIsAc }) {
  const [kucuk, setKucuk] = useState(false)
  const govde = useRef(null)
  const id = rol?.anahtar
  const benimLog = useMemo(() => (id ? logs.filter((l) => l.agent === id).slice(-80) : []), [logs, id])
  useEffect(() => {
    if (govde.current) govde.current.scrollTop = govde.current.scrollHeight
  }, [benimLog.length, id, kucuk])
  if (!rol) return null
  const b = AJANLAR[id] || {}
  const s = (stats?.steps || {})[id]
  const is =
    jobs.find((j) => j.id === rol.isId) ||
    (rol.durum === 'calis' ? jobs.find((j) => j.status === 'running') : rol.durum === 'soru' ? jobs.find((j) => j.status === 'awaiting_approval') : null)
  return (
    <div className="sohbetler">
      <section className={`sohbet${kucuk ? ' kucuk' : ''}`} style={{ '--rol': b.renk }} aria-label={`${rol.ad} penceresi`}>
        <header className="sb-bas" onClick={() => setKucuk((k) => !k)}>
          <span className="rol-nokta" />
          <div className="sb-baslik">
            <div className="sb-ad">{rol.ad}</div>
            <div className="sb-durum">{rol.durum === 'calis' && rol.metin ? rol.metin : `${rol.rol} · ${DURUM_ADI[rol.durum] || rol.durum}`}</div>
          </div>
          <div className="sb-dugmeler" onClick={(e) => e.stopPropagation()}>
            <button type="button" className="sb-ikon" title="Karakter kartı" onClick={() => onKart(id)}>
              🪪
            </button>
            <button type="button" className="sb-ikon" title={kucuk ? 'Büyüt' : 'Küçült'} onClick={() => setKucuk((k) => !k)}>
              {kucuk ? '▴' : '▾'}
            </button>
            <button type="button" className="sb-ikon" title="Kapat (log filtresini de kaldırır)" onClick={onKapat}>
              ×
            </button>
          </div>
        </header>
        <div className="sb-ayrinti">
          <div className="kk-dep2">
            {rol.departman} · {rol.istasyon}
          </div>
          {is ? (
            <div className="mb-gorev">
              <button type="button" className="baglanti" onClick={() => onIsAc(is.id)}>
                #{kisaNo(is.id)} {is.title || is.topic || 'Konu seçiliyor…'}
              </button>
              <span className="soluk"> · {STATUS_TR[is.status] || is.status}</span>
            </div>
          ) : (
            <div className="mb-gorev soluk">Üzerinde iş yok</div>
          )}
          <div className="mb-alt">
            <span>{s ? `${s.success} başarılı · ${s.fail} hatalı` : 'Henüz çalışmadı'}</span>
            {s?.avg_seconds != null && <span>ort. {s.avg_seconds} sn</span>}
            <span>log terminali bu ajana süzüldü</span>
          </div>
        </div>
        <div className="sb-govde" ref={govde}>
          {benimLog.length ? benimLog.map((l) => <LogSatiri key={l.id} log={l} />) : <div className="sb-bos">Bu ajandan henüz log yok.</div>}
        </div>
      </section>
    </div>
  )
}
