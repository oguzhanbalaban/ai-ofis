import { useEffect, useMemo, useRef, useState } from 'react'
import { api } from '../useStudio.js'
import { MiniMd } from './AjanPenceresi.jsx'

// Arka plan (</> kod) çekmecesi (AI Ekip panelindeki gibi): stüdyonun kaynak dosyaları salt okunur.
// Liste sunucudaki izinli dosyalardan gelir; .env, secrets, veri ve modeller hiç listelenmez.
export function KodSekmesi({ onAc }) {
  return (
    <button type="button" className="kod-sekme" onClick={onAc} title="Stüdyonun arka planı: ajanlar, akış, panel kodu (salt okunur)">
      &lt;/&gt; kod
    </button>
  )
}

const kb = (n) => (n < 1024 ? `${n} B` : `${(n / 1024).toFixed(n < 10240 ? 1 : 0)} KB`)

export default function KodCekmecesi({ acik, onKapat, tost }) {
  const [dosyalar, setDosyalar] = useState(null)
  const [secili, setSecili] = useState(null)
  const [icerik, setIcerik] = useState(null)
  const [suz, setSuz] = useState('')
  const [bulunan, setBulunan] = useState(null)
  const [gorunum, setGorunum] = useState('bicimli')
  const [hedefSatir, setHedefSatir] = useState(null)
  const kodRef = useRef(null)

  useEffect(() => {
    if (!acik || dosyalar) return
    api('/api/kaynak')
      .then(setDosyalar)
      .catch((e) => tost(`Dosya listesi alınamadı: ${e.message}`, true))
  }, [acik]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!acik) return
    const onKey = (e) => e.key === 'Escape' && onKapat()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [acik, onKapat])

  // İçerik araması (en az 3 harf): sunucu izinli dosyalarda satır satır arar
  useEffect(() => {
    const q = suz.trim()
    if (q.length < 3) {
      setBulunan(null)
      return
    }
    const t = setTimeout(() => {
      api(`/api/kaynak/ara?q=${encodeURIComponent(q)}`)
        .then(setBulunan)
        .catch(() => setBulunan(null))
    }, 300)
    return () => clearTimeout(t)
  }, [suz])

  const ac = async (yol, satir = null) => {
    setSecili(yol)
    setHedefSatir(satir)
    setIcerik(null)
    try {
      setIcerik(await api(`/api/kaynak/dosya?yol=${encodeURIComponent(yol)}`))
      if (satir) setGorunum('kod')
    } catch (e) {
      setIcerik({ yol, hata: e.message })
    }
  }

  useEffect(() => {
    if (!hedefSatir || !kodRef.current) return
    const el = kodRef.current.querySelector(`[data-s="${hedefSatir}"]`)
    el?.scrollIntoView({ block: 'center' })
  }, [icerik, hedefSatir, gorunum])

  const gruplar = useMemo(() => {
    const q = suz.trim().toLocaleLowerCase('tr-TR')
    const m = new Map()
    for (const d of dosyalar || []) {
      if (q && !d.yol.toLocaleLowerCase('tr-TR').includes(q)) continue
      if (!m.has(d.grup)) m.set(d.grup, [])
      m.get(d.grup).push(d)
    }
    return [...m.entries()]
  }, [dosyalar, suz])

  if (!acik) return null
  const md = icerik?.yol?.endsWith('.md')
  const satirlar = icerik?.metin != null ? icerik.metin.split('\n') : []
  return (
    <>
      <div className="perde" onMouseDown={onKapat} />
      <aside className={`kod-cekmece${secili ? ' dosyada' : ''}`} role="dialog" aria-modal="true" aria-labelledby="kodBaslik">
        <div className="kod-bas">
          <button type="button" className="dugme kucuk kod-geri" onClick={() => setSecili(null)}>
            ← Dosyalar
          </button>
          <h2 id="kodBaslik">&lt;/&gt; Arka plan</h2>
          <span className="soluk">ajanlar, akış, servisler, panel · salt okunur</span>
          <button className="kapat" type="button" aria-label="Kapat" onClick={onKapat}>
            ×
          </button>
        </div>
        <div className="kod-govde">
          <nav className="kod-agac" aria-label="Dosyalar">
            <input type="search" value={suz} onChange={(e) => setSuz(e.target.value)} placeholder="Dosya adı ya da kodda ara…" aria-label="Dosyalarda ara" />
            <div className="kod-liste">
              {!dosyalar && <div className="kod-bos">Yükleniyor…</div>}
              {gruplar.map(([g, l]) => (
                <div key={g}>
                  <div className="kod-grup">{g}</div>
                  {l.map((d) => (
                    <button key={d.yol} type="button" className="kod-dosya" aria-current={secili === d.yol} onClick={() => ac(d.yol)} title={d.yol}>
                      <span className="ad">{d.yol.split('/').pop()}</span>
                      <span className="kb">{kb(d.boyut)}</span>
                    </button>
                  ))}
                </div>
              ))}
              {bulunan && (
                <div>
                  <div className="kod-grup">Kodda bulunan ({bulunan.length})</div>
                  {bulunan.slice(0, 80).map((b, i) => (
                    <button key={`${b.yol}:${b.satir}:${i}`} type="button" className="kod-dosya bulunan" onClick={() => ac(b.yol, b.satir)} title={`${b.yol}:${b.satir}`}>
                      <span className="ad">
                        {b.yol.split('/').pop()}:{b.satir} <span className="soluk">{b.metin}</span>
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </nav>
          <div className="kod-goster">
            {!secili ? (
              <div className="kod-bos">
                Soldan bir dosya seç. Burada stüdyonun nasıl çalıştığını görebilirsin: ajanların düğümleri (<code>backend/app/agents</code>), akış (
                <code>graph.py</code>), iş kuyruğu (<code>jobs.py</code>), sohbet (<code>sohbet.py</code>) ve bu panelin kodu. Hiçbir şey buradan
                değiştirilemez; <code>.env</code> ve anahtarlar hiç gösterilmez.
              </div>
            ) : (
              <>
                <div className="kod-ust">
                  <span className="yol">{secili}</span>
                  {icerik?.satir ? <span className="meta">{icerik.satir} satır</span> : null}
                  {md && (
                    <div className="donem" role="group" aria-label="Görünüm">
                      <button type="button" aria-pressed={gorunum === 'bicimli'} onClick={() => setGorunum('bicimli')}>
                        Biçimli
                      </button>
                      <button type="button" aria-pressed={gorunum === 'kod'} onClick={() => setGorunum('kod')}>
                        Kaynak
                      </button>
                    </div>
                  )}
                </div>
                <div className="kod-icerik" ref={kodRef}>
                  {!icerik && <div className="kod-bos">Yükleniyor…</div>}
                  {icerik?.hata && <div className="kod-bos">{icerik.hata}</div>}
                  {icerik?.metin != null && md && gorunum === 'bicimli' && (
                    <div className="kod-md">
                      <MiniMd metin={icerik.metin} />
                    </div>
                  )}
                  {icerik?.metin != null && (!md || gorunum === 'kod') && (
                    <div className="kod-kod">
                      <pre className="no" aria-hidden="true">
                        {satirlar.map((_, i) => (
                          <span key={i} data-s={i + 1} className={hedefSatir === i + 1 ? 'hedef' : undefined}>
                            {i + 1}
                            {'\n'}
                          </span>
                        ))}
                      </pre>
                      <pre>{icerik.metin}</pre>
                    </div>
                  )}
                </div>
              </>
            )}
          </div>
        </div>
      </aside>
    </>
  )
}
