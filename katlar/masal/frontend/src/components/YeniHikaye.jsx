import { useEffect, useRef, useState } from 'react'
import { api } from '../useMasal.js'
import { IMAGE_OPTIONS, MISSING, TTS_OPTIONS, pick } from '../sabitler.js'

// "+ Yeni hikâye" diyaloğu (AI Ekip'teki "İş ver" diyaloğunun karşılığı)
export default function YeniHikaye({ acik, onKapat, busy, config, tost }) {
  const ref = useRef(null)
  const konuRef = useRef(null)
  const [topic, setTopic] = useState('')
  const [failure, setFailure] = useState('none')
  const [tts, setTts] = useState(null)
  const [image, setImage] = useState(null)
  const [sending, setSending] = useState(false)
  const [err, setErr] = useState(null)
  const avail = config?.tts_available || {}
  const imgAvail = config?.image_available || { placeholder: true }
  const chosen = pick(TTS_OPTIONS, avail, tts, config?.tts_provider)
  const chosenImage = pick(IMAGE_OPTIONS, imgAvail, image, config?.image_provider)

  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (acik && !d.open) {
      setErr(null)
      d.showModal()
      setTimeout(() => konuRef.current?.focus(), 0)
    } else if (!acik && d.open) d.close()
  }, [acik])

  const submit = async (e) => {
    e.preventDefault()
    setSending(true)
    setErr(null)
    try {
      const job = await api('/api/jobs', { topic: topic.trim() || null, failure, tts: chosen, image: chosenImage })
      setTopic('')
      tost(`Hikâye ${busy ? 'kuyruğa alındı' : 'başladı'}: ${job.topic || job.id}`)
      onKapat()
    } catch (ex) {
      setErr(ex.message)
    } finally {
      setSending(false)
    }
  }

  return (
    <dialog className="diyalog" ref={ref} aria-labelledby="yeniBaslik" onClose={onKapat} onCancel={onKapat}
      onMouseDown={(e) => e.target === e.currentTarget && onKapat()}>
      <form className="diyalog-ic" onSubmit={submit} noValidate>
        <h2 id="yeniBaslik">✨ Yeni hikâye üret</h2>
        <div className="kutu ekle-bilgi">
          İsteği <b>Yönetmen Yıldız</b> alır; konu boşsa günün konusunu kendisi seçer. Ekip hikâyeyi yazar, çizer, seslendirir ve kurgular.
          Hiçbir şey kendiliğinden yüklenmez: video <b>taslak</b> olarak onayına gelir.
        </div>
        <label className="alan">
          Konu <span className="ipucu">boş bırakılırsa Yönetmen günün konusunu seçer</span>
          <input ref={konuRef} value={topic} maxLength={120} onChange={(e) => setTopic(e.target.value)} placeholder="ör. paylaşmak, cesaret, sabır…" autoComplete="off" />
        </label>
        <label className="alan">
          🎨 Çizim motoru
          <select value={chosenImage} onChange={(e) => setImage(e.target.value)}>
            {IMAGE_OPTIONS.map(([k, label]) => (
              <option key={k} value={k} disabled={!imgAvail[k]}>
                {label}
                {!imgAvail[k] ? MISSING[k] || '' : ''}
              </option>
            ))}
          </select>
          {chosenImage === 'flux_local' && <span className="ipucu">Apache 2.0 — ticari kullanım serbest. Video başına ~1-2 dk çizim.</span>}
          {(chosenImage === 'fal' || chosenImage === 'openai') && <span className="ipucu uyari-yazi">Her üretim API hesabınızdan ücret harcar.</span>}
          {!imgAvail.flux_local && <span className="ipucu">Yerel FLUX için proje kökünde yerel-modeller.ps1 çalıştırın.</span>}
        </label>
        <label className="alan">
          🎙 Ses motoru
          <select value={chosen} onChange={(e) => setTts(e.target.value)}>
            {TTS_OPTIONS.map(([k, label]) => (
              <option key={k} value={k} disabled={!avail[k]}>
                {label}
                {!avail[k] ? MISSING[k] || '' : ''}
              </option>
            ))}
          </select>
          {chosen === 'chatterbox' && (
            <span className="ipucu">
              MIT lisansı — ticari kullanım serbest.{' '}
              {config?.chatterbox_reference
                ? 'Anlatıcı sesi: assets\\voices\\anlatici.wav'
                : 'Kendi anlatıcı sesiniz için assets\\voices\\anlatici.wav ekleyebilirsiniz.'}
            </span>
          )}
          {chosen === 'piper' && config?.piper_license && (
            <span className="ipucu">Lisans: {config.piper_license} — para kazanılan yayın için uygun değil.</span>
          )}
          {chosen === 'elevenlabs' && <span className="ipucu uyari-yazi">Her üretim ElevenLabs hesabınızdan kredi harcar.</span>}
          {!avail.elevenlabs && (
            <span className="ipucu">ElevenLabs için .env → ELEVENLABS_API_KEY ve ELEVENLABS_VOICE_ID girip backend’i yeniden başlatın.</span>
          )}
        </label>
        <label className="alan">
          Senaryo testi
          <select value={failure} onChange={(e) => setFailure(e.target.value)}>
            <option value="none">Normal akış</option>
            <option value="visual_timeout">Görsel API zaman aşımı → Yönetmen yeniden tetikler</option>
            <option value="qa_reject">QA reddi → Kurgucuya geri gönderim</option>
          </select>
        </label>
        {err && <div className="form-hata">{err}</div>}
        <div className="diyalog-alt">
          <button className="dugme" type="button" onClick={onKapat}>
            Vazgeç
          </button>
          <button className="dugme birincil" type="submit" disabled={sending}>
            {sending ? 'Gönderiliyor…' : busy ? '➕ Kuyruğa ekle' : '▶ Üret'}
          </button>
        </div>
      </form>
    </dialog>
  )
}
