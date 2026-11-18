import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import { api } from '../useStudio.js'
import { AJANLAR, DURUM_ADI, STATUS_TR, kisaNo } from '../sabitler.js'
import { LogSatiri } from './LogTerminal.jsx'

// Küçük ve güvenli Markdown: paragraflar, madde listeleri, **kalın**, `kod` (innerHTML kullanılmaz)
function Satir({ metin }) {
  const parcalar = []
  const re = /(\*\*[^*]+\*\*|`[^`]+`)/g
  let son = 0
  let m
  while ((m = re.exec(metin))) {
    if (m.index > son) parcalar.push(metin.slice(son, m.index))
    const p = m[0]
    parcalar.push(p.startsWith('**') ? <b key={m.index}>{p.slice(2, -2)}</b> : <code key={m.index}>{p.slice(1, -1)}</code>)
    son = m.index + p.length
  }
  if (son < metin.length) parcalar.push(metin.slice(son))
  return parcalar
}

export function MiniMd({ metin }) {
  const bloklar = (metin || '').split(/\n{2,}/)
  return (
    <div className="md">
      {bloklar.map((b, i) => {
        const satirlar = b.split('\n').filter((s) => s.trim())
        if (satirlar.length && satirlar.every((s) => /^\s*([-*•]|\d+[.)])\s+/.test(s))) {
          return (
            <ul key={i}>
              {satirlar.map((s, j) => (
                <li key={j}>
                  <Satir metin={s.replace(/^\s*([-*•]|\d+[.)])\s+/, '')} />
                </li>
              ))}
            </ul>
          )
        }
        return (
          <p key={i}>
            {satirlar.map((s, j) => (
              <Fragment key={j}>
                {j > 0 && <br />}
                <Satir metin={s} />
              </Fragment>
            ))}
          </p>
        )
      })}
    </div>
  )
}

const ONERILER = ['Şu an ne yapıyorsun?', 'Son çalışmanı anlatır mısın?', 'Yeni bir masal konusu öner']
const saat = (ts) => new Date(ts * 1000).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })

function Sohbet({ rol, mesajlar, yaziyor, motor, onKonu, tost }) {
  const [metin, setMetin] = useState('')
  const [gonderiyor, setGonderiyor] = useState(false)
  const govde = useRef(null)
  const alan = useRef(null)
  const id = rol.anahtar
  useEffect(() => {
    if (govde.current) govde.current.scrollTop = govde.current.scrollHeight
  }, [mesajlar?.length, yaziyor, id])
  useEffect(() => {
    alan.current?.focus()
  }, [id])

  const gonder = async (yazi) => {
    const m = (yazi ?? metin).trim()
    if (!m || gonderiyor) return
    setGonderiyor(true)
    try {
      await api(`/api/chat/${id}`, { metin: m })
      setMetin('')
    } catch (e) {
      tost(`Gönderilemedi: ${e.message}`, true)
    } finally {
      setGonderiyor(false)
      alan.current?.focus()
    }
  }
  const temizle = async () => {
    if (!mesajlar?.length || !confirm(`${rol.ad} ile sohbet temizlensin mi? (Eski yazışma silinmez, arşive taşınır.)`)) return
    try {
      await api(`/api/chat/${id}/clear`, {})
    } catch (e) {
      tost(e.message, true)
    }
  }

  return (
    <>
      <div className="sb-sohbet" ref={govde} aria-live="polite">
        {mesajlar == null && <div className="sb-bos-acik">Yükleniyor…</div>}
        {mesajlar && !mesajlar.length && (
          <div className="sb-bos-acik">
            <span>
              {rol.ad} ile konuş: soru sor, fikir al, yeni bir masal iste. Sohbette dosya değişmez, iş kendiliğinden başlamaz; konu önerisini sen onaylarsın.
            </span>
            <div className="sb-oneriler">
              {ONERILER.map((o) => (
                <button key={o} type="button" onClick={() => gonder(o)} disabled={gonderiyor || yaziyor}>
                  {o}
                </button>
              ))}
            </div>
          </div>
        )}
        {mesajlar?.map((m) => (
          <div key={m.id} className={`sb-mesaj ${m.kim}`}>
            {m.kim === 'ajan' ? <MiniMd metin={m.metin} /> : <div className="sb-metin">{m.metin}</div>}
            {m.oneri && (
              <div className="sb-oneri">
                <span>
                  🎬 Konu önerisi: <b>“{m.oneri.konu}”</b>
                </span>
                <button type="button" className="dugme kucuk birincil" onClick={() => onKonu(m.oneri.konu)}>
                  Gözden geçir ve ekibe ver
                </button>
              </div>
            )}
            {m.not && <div className="sb-not">ⓘ {m.not}</div>}
            <div className="sb-meta">
              {saat(m.zaman)}
              {m.kim === 'ajan' && m.motor ? ` · ${m.motor === 'yerel' ? 'yerel yanıt' : m.motor === 'claude' ? 'Claude' : 'LLM'}` : ''}
            </div>
          </div>
        ))}
        {yaziyor && (
          <div className="sb-yaziyor" aria-label={`${rol.ad} yazıyor`}>
            <i />
            <i />
            <i />
          </div>
        )}
      </div>
      <form
        className="sb-yaz"
        onSubmit={(e) => {
          e.preventDefault()
          gonder()
        }}
      >
        <textarea
          ref={alan}
          rows={1}
          value={metin}
          maxLength={2000}
          placeholder={yaziyor ? `${rol.kisa} yazıyor…` : `${rol.kisa}'a yaz… (Enter gönderir)`}
          aria-label={`${rol.ad}'a mesaj`}
          onChange={(e) => setMetin(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault()
              gonder()
            }
          }}
        />
        <button type="submit" className="dugme birincil" disabled={!metin.trim() || gonderiyor || yaziyor} title="Gönder">
          ➤
        </button>
      </form>
      <div className="sb-motor">
        <span title={motor?.not || ''}>Yanıtlayan: {motor?.ad || '—'}</span>
        <button type="button" className="baglanti" onClick={temizle} disabled={!mesajlar?.length}>
          sohbeti temizle
        </button>
      </div>
    </>
  )
}

// Seçili ajanın sağ altta açılan penceresi (AI Ekip'teki sohbet penceresi): sohbet + canlı loglar
export default function AjanPenceresi({ rol, stats, jobs, logs, sohbetler, yaziyor, motor, sohbetYukle, onKapat, onKart, onIsAc, onKonu, tost }) {
  const [kucuk, setKucuk] = useState(false)
  const [sekme, setSekme] = useState('sohbet')
  const logGovde = useRef(null)
  const id = rol?.anahtar
  const benimLog = useMemo(() => (id ? logs.filter((l) => l.agent === id).slice(-80) : []), [logs, id])
  useEffect(() => {
    if (id && !sohbetler[id]) sohbetYukle(id).catch((e) => tost(`Sohbet yüklenemedi: ${e.message}`, true))
  }, [id]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (logGovde.current) logGovde.current.scrollTop = logGovde.current.scrollHeight
  }, [benimLog.length, id, kucuk, sekme])
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
            <div className="sb-durum">{yaziyor[id] ? 'yazıyor…' : rol.durum === 'calis' && rol.metin ? rol.metin : `${rol.rol} · ${DURUM_ADI[rol.durum] || rol.durum}`}</div>
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
          </div>
          <div className="sb-sekmeler" role="tablist">
            <button type="button" role="tab" aria-selected={sekme === 'sohbet'} onClick={() => setSekme('sohbet')}>
              💬 Sohbet
            </button>
            <button type="button" role="tab" aria-selected={sekme === 'log'} onClick={() => setSekme('log')}>
              📜 Loglar {benimLog.length ? <span className="soluk">({benimLog.length})</span> : null}
            </button>
          </div>
        </div>
        {sekme === 'sohbet' ? (
          <Sohbet rol={rol} mesajlar={sohbetler[id]} yaziyor={!!yaziyor[id]} motor={motor} onKonu={onKonu} tost={tost} />
        ) : (
          <div className="sb-govde" ref={logGovde}>
            {benimLog.length ? benimLog.map((l) => <LogSatiri key={l.id} log={l} />) : <div className="sb-bos">Bu ajandan henüz log yok.</div>}
          </div>
        )}
      </section>
    </div>
  )
}
