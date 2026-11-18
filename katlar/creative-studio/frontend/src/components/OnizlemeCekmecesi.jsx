import { useEffect, useState } from 'react'
import { api } from '../useStudio.js'
import { AJANLAR, MOTOR_KISA, STATUS_ROZET, STATUS_TR, TARGETS, kisaNo } from '../sabitler.js'
import { AdimCubugu } from './UretimPanosu.jsx'

// Önizleme ve onay çekmecesi (AI Ekip'teki görev ayrıntısı çekmecesinin düzeninde).
// Yükleme yalnızca buradaki onay kutusu işaretlenip düğmeye basılınca yapılır.
export default function OnizlemeCekmecesi({ job, config, onClose, tost }) {
  const [tab, setTab] = useState('seo')
  const [ack, setAck] = useState(false)
  const [target, setTarget] = useState('story')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)

  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  if (!job) return null
  const awaiting = job.status === 'awaiting_approval'
  const retryable = job.status === 'failed' || job.status === 'interrupted'
  const pub = job.publish || {}
  const qa = job.qa || {}
  const mock = config?.mock_mode
  const uploadAllowed = mock || config?.upload_possible

  const act = async (path, body, okText) => {
    setBusy(true)
    setMsg(null)
    try {
      await api(`/api/jobs/${job.id}/${path}`, body)
      setMsg({ ok: true, text: okText })
      tost?.(okText)
      setAck(false)
    } catch (e) {
      setMsg({ ok: false, text: e.message })
      tost?.(e.message, true)
    } finally {
      setBusy(false)
    }
  }

  const sekmeler = [
    ['seo', 'SEO & Taslak'],
    ['qa', `QA ${qa.passed ? '✓' : qa.passed === false ? '✕' : ''}`],
    ['story', 'Hikaye'],
    ['visuals', 'Görseller'],
    ['cost', 'Maliyet'],
  ]

  return (
    <>
      <div className="perde" onMouseDown={onClose} />
      <aside className="cekmece" role="dialog" aria-modal="true" aria-labelledby="ckBaslik">
        <div className="ck-bas">
          <div>
            <div className="ck-no">
              <span>#{kisaNo(job.id)}</span>
              <span className={`rozet ${STATUS_ROZET[job.status] || ''}`}>{STATUS_TR[job.status] || job.status}</span>
              {job.revision_count ? <span className="rozet r-uyari">{job.revision_count}. revizyon</span> : null}
              {job.mock && <span className="rozet">mock</span>}
            </div>
            <h2 className="ck-baslik" id="ckBaslik">
              {job.title || job.topic || 'Konu seçiliyor…'}
            </h2>
            <div className="ck-meta">
              {job.id}
              {job.topic ? ` · konu: ${job.topic}` : ''}
              {job.image ? ` · 🎨 ${MOTOR_KISA[job.image] || job.image}` : ''}
              {job.tts ? ` · 🎙 ${MOTOR_KISA[job.tts] || job.tts}` : ''}
            </div>
          </div>
          <button className="kapat" type="button" aria-label="Kapat" onClick={onClose}>
            ×
          </button>
        </div>

        <div className="ck-eylemler">
          {!awaiting && !retryable && (
            <div className="soluk kucuk-yazi">
              {job.status === 'running' || job.status === 'queued'
                ? 'Üretim sürüyor… Ofisten takip edin; bitince burada güncellenir.'
                : 'Bu iş için onay adımı tamamlandı.'}
            </div>
          )}
          {retryable && (
            <div className="kutu hata tam">
              Bu iş tamamlanamadı{job.error ? `: ${job.error}` : ''}. Aşağıdan bir adımı yeniden başlatabilirsiniz.
            </div>
          )}
          {awaiting && (
            <button className="dugme birincil" type="button" disabled={busy} onClick={() => act('approve', { upload: false }, 'Onaylandı. Yerel taslak olarak saklandı; yükleme yapılmadı.')}>
              ✅ Onayla — taslak olarak sakla
            </button>
          )}
          {awaiting && (
            <div className="yukleme-kutu">
              <label className="tik">
                <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} disabled={!uploadAllowed} />
                <span>
                  {mock
                    ? 'Mock mod: yükleme yalnızca simüle edilir, YouTube’a hiçbir şey gönderilmez.'
                    : `Bu videonun YouTube’a privacyStatus=${pub.privacyStatus || 'private'} ve “çocuklar için yapıldı” olarak yükleneceğini onaylıyorum.`}
                </span>
              </label>
              <button
                className="dugme uyari"
                type="button"
                disabled={busy || !ack || !uploadAllowed}
                onClick={() => act('approve', { upload: true, confirm: true }, mock ? 'Yükleme simüle edildi (gerçek yükleme yok).' : 'YouTube’a yüklendi (private).')}
                title={!uploadAllowed ? 'YOUTUBE_UPLOAD_ENABLED=false — .env içinden açılmadıkça yükleme yapılmaz.' : ''}
              >
                {mock ? '⬆ Yüklemeyi simüle et' : '⬆ Onayla ve YouTube’a yükle'}
              </button>
              {!uploadAllowed && <div className="soluk kucuk-yazi">Yükleme kapalı (YOUTUBE_UPLOAD_ENABLED=false).</div>}
            </div>
          )}
          {(awaiting || retryable) && (
            <div className="revizyon-kutu">
              <div className="satir">
                <select value={target} onChange={(e) => setTarget(e.target.value)} aria-label="Revizyon hedefi">
                  {TARGETS.map(([k, l]) => (
                    <option key={k} value={k}>
                      {l}
                    </option>
                  ))}
                </select>
                <button className="dugme" type="button" disabled={busy} onClick={() => act('revise', { target, note }, 'Revizyon kuyruğa alındı.')}>
                  ↺ {retryable ? 'Bu adımdan yeniden başlat' : 'Revizyon iste'}
                </button>
              </div>
              <textarea value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} placeholder="Revizyon notu (ör. daha neşeli bir son, altyazı renkleri…)" rows={2} />
            </div>
          )}
          {msg && <div className={`kutu tam ${msg.ok ? 'iyi' : 'hata'}`}>{msg.text}</div>}
        </div>

        <div className="ck-icerik">
          <div className="ck-izgara">
            <div className="oynatici">
              {job.video_url ? (
                <video key={job.video_url} src={job.video_url} controls playsInline poster={job.thumb_url || undefined} />
              ) : (
                <div className="video-yok">Video henüz yok</div>
              )}
              {job.probe && (
                <div className="soluk kucuk-yazi orta">
                  {job.probe.width}x{job.probe.height} · {job.probe.fps} fps · {Number(job.probe.duration).toFixed(2)} sn · {(job.probe.size_bytes / 1e6).toFixed(1)} MB · ölçüm:{' '}
                  {job.probe.tool}
                </div>
              )}
              <div className="ck-adimlar">
                <AdimCubugu job={job} />
                <span className="soluk kucuk-yazi">
                  {job.current_agent ? `${AJANLAR[job.current_agent]?.kisa || job.current_agent} çalışıyor` : 'üretim adımları'}
                </span>
              </div>
            </div>
            <div className="detay">
              <nav className="sekmeler" role="tablist">
                {sekmeler.map(([k, l]) => (
                  <button key={k} type="button" role="tab" className="sekme" aria-selected={tab === k} onClick={() => setTab(k)}>
                    {l}
                  </button>
                ))}
              </nav>
              <div className="sekme-govde">
                {tab === 'seo' && (
                  <dl className="kv">
                    <dt>Başlık</dt>
                    <dd>{pub.title || '—'}</dd>
                    <dt>Açıklama</dt>
                    <dd>
                      <pre className="duz">{pub.description || '—'}</pre>
                    </dd>
                    <dt>Etiketler</dt>
                    <dd className="etiketler">{(pub.tags || []).length ? pub.tags.map((t) => <i key={t}>#{t}</i>) : '—'}</dd>
                    <dt>Yayın ayarı</dt>
                    <dd>
                      privacyStatus=<code>{pub.privacyStatus || 'private'}</code> · selfDeclaredMadeForKids=
                      <code>{String(pub.selfDeclaredMadeForKids ?? true)}</code>
                    </dd>
                    {pub.upload && (
                      <>
                        <dt>Yükleme</dt>
                        <dd>
                          {pub.upload.simulated ? (
                            'Simüle edildi — YouTube’a hiçbir şey gönderilmedi.'
                          ) : (
                            <a href={pub.upload.url} target="_blank" rel="noreferrer">
                              {pub.upload.url}
                            </a>
                          )}
                        </dd>
                      </>
                    )}
                  </dl>
                )}
                {tab === 'qa' && (
                  <ul className="kontroller">
                    {(qa.checks || []).map((c, i) => (
                      <li key={i} className={c.ok ? 'ok' : 'bad'}>
                        <span>{c.ok ? '✓' : '✕'}</span>
                        <b>{c.name}</b>
                        <em>{c.detail}</em>
                      </li>
                    ))}
                    {!qa.checks && <li className="soluk">QA raporu yok.</li>}
                  </ul>
                )}
                {tab === 'story' &&
                  (job.story ? (
                    <div>
                      <p className="kanca">“{job.story.hook}”</p>
                      <p className="hikaye-metni">{job.story.text}</p>
                      <p className="soluk kucuk-yazi">
                        {job.story.word_count} kelime · mesaj: {job.story.moral}
                      </p>
                      {job.voice && (
                        <p className="soluk kucuk-yazi">
                          🎙 Ses: {job.voice.voice_source} · zaman damgası: {job.voice.timestamp_source}
                          {job.voice.engine?.avg_match != null
                            ? ` · Whisper uyumu %${Math.round(job.voice.engine.avg_match * 100)}` +
                              (job.voice.engine.retakes ? ` (${job.voice.engine.retakes} cümle yeniden okundu)` : '')
                            : ''}
                          {job.voice.engine?.license ? ` · lisans: ${job.voice.engine.license}` : ''}
                        </p>
                      )}
                    </div>
                  ) : (
                    <p className="soluk">Hikâye henüz yazılmadı.</p>
                  ))}
                {tab === 'visuals' &&
                  (job.visuals ? (
                    <div>
                      {job.visuals.engine && (
                        <p className="soluk kucuk-yazi">
                          🎨 Çizim: {job.visuals.engine.label}
                          {job.visuals.engine.seconds ? ` · ${Math.round(job.visuals.engine.seconds)} sn` : ''}
                          {job.visuals.engine.reference_url ? ' · karakter referanslı' : ''}
                        </p>
                      )}
                      {job.visuals.images?.length > 0 && (
                        <div className="sahne-seridi">
                          {job.visuals.engine?.reference_url && (
                            <a href={job.visuals.engine.reference_url} target="_blank" rel="noreferrer" title="Karakter referansı">
                              <img src={job.visuals.engine.reference_url} alt="Karakter referansı" className="ref" />
                            </a>
                          )}
                          {job.visuals.images.map((u, i) => (
                            <a key={u} href={u} target="_blank" rel="noreferrer" title={`Sahne ${i + 1}`}>
                              <img src={u} alt={`Sahne ${i + 1}`} />
                            </a>
                          ))}
                        </div>
                      )}
                    </div>
                  ) : (
                    <p className="soluk">Görseller henüz çizilmedi.</p>
                  ))}
                {tab === 'cost' && (
                  <ul className="kontroller">
                    {Object.entries(job.cost_by_agent || {}).map(([k, v]) => (
                      <li key={k}>
                        <b>{AJANLAR[k]?.kisa || k}</b>
                        <em>${Number(v).toFixed(4)}</em>
                      </li>
                    ))}
                    <li>
                      <b>Toplam</b>
                      <em>${(job.cost_usd || 0).toFixed(4)}</em>
                    </li>
                  </ul>
                )}
              </div>
            </div>
          </div>
        </div>
      </aside>
    </>
  )
}
