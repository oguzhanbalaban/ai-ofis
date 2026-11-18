import { useEffect, useMemo, useRef, useState } from 'react'
import { AJANLAR, AJAN_SIRASI, saatMetni } from '../sabitler.js'

export function LogSatiri({ log }) {
  const [open, setOpen] = useState(false)
  const a = AJANLAR[log.agent]
  const [tag, color] = a ? [a.etiket, a.log] : ['SYS', '#adb5bd']
  return (
    <div className={`log-line lv-${log.level}`}>
      <span className="ts">{saatMetni(log.ts)}</span>
      <span className="tag" style={{ color }}>
        [{tag}]
      </span>
      <span className="msg">{log.message}</span>
      {log.data != null && (
        <button type="button" className="json-toggle" onClick={() => setOpen((v) => !v)} title="JSON çıktısı" aria-expanded={open}>
          {open ? '▾ JSON' : '▸ JSON'}
        </button>
      )}
      {open && <pre className="json">{JSON.stringify(log.data, null, 2)}</pre>}
    </div>
  )
}

// Canlı log terminali: ajana göre süzme (sahnede seçili ajan), takip, temizle, satır başına JSON
export default function LogTerminal({ logs, filter, onFilter, onClear }) {
  const boxRef = useRef(null)
  const [follow, setFollow] = useState(true)
  const shown = useMemo(() => (filter ? logs.filter((l) => l.agent === filter) : logs), [logs, filter])

  useEffect(() => {
    if (follow && boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight
  }, [shown, follow])

  const onScroll = () => {
    const el = boxRef.current
    if (!el) return
    setFollow(el.scrollHeight - el.scrollTop - el.clientHeight < 30)
  }

  return (
    <section className="terminal" id="terminal" aria-labelledby="terminalBaslik">
      <header className="term-bas">
        <span className="term-title" id="terminalBaslik">
          ▌Canlı log terminali
        </span>
        <div className="term-cipler" role="group" aria-label="Ajana göre süz">
          <button type="button" className="term-cip" aria-pressed={!filter} onClick={() => onFilter(null)}>
            Tümü
          </button>
          {AJAN_SIRASI.map((id) => (
            <button
              key={id}
              type="button"
              className="term-cip"
              aria-pressed={filter === id}
              style={{ '--c': AJANLAR[id].log }}
              title={`${AJANLAR[id].kisa} loglarını göster`}
              onClick={() => onFilter(filter === id ? null : id)}
            >
              {AJANLAR[id].etiket.trim()}
            </button>
          ))}
        </div>
        <span className="spacer" />
        {filter && (
          <button type="button" className="term-cip filtre" onClick={() => onFilter(null)} title="Filtreyi kaldır">
            filtre: {AJANLAR[filter]?.etiket.trim() || filter} ✕
          </button>
        )}
        <span className="term-sayi">{shown.length} satır</span>
        <button type="button" className="term-cip" onClick={() => setFollow(true)} disabled={follow}>
          ⤓ takip
        </button>
        <button type="button" className="term-cip" onClick={onClear}>
          temizle
        </button>
      </header>
      <div className="term-body" ref={boxRef} onScroll={onScroll}>
        {shown.map((l) => (
          <LogSatiri key={l.id} log={l} />
        ))}
        <div className="cursor">█</div>
      </div>
    </section>
  )
}
