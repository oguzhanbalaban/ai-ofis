import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useStudio } from './useStudio.js'
import { ADIMLAR, MOTOR_KISA, ajanDurumu, iki, rolNesnesi } from './sabitler.js'
import OfisSahnesi from './components/OfisSahnesi.jsx'
import LogTerminal from './components/LogTerminal.jsx'
import UretimPanosu, { HatSeridi } from './components/UretimPanosu.jsx'
import Istatistik from './components/Istatistik.jsx'
import YeniHikaye from './components/YeniHikaye.jsx'
import OnizlemeCekmecesi from './components/OnizlemeCekmecesi.jsx'
import { AjanPenceresi, KarakterKarti } from './components/Karakter.jsx'

function Logo() {
  return (
    <svg className="logo" viewBox="0 0 32 32" aria-hidden="true">
      <rect width="32" height="32" rx="8" fill="#1f2328" />
      <path d="M5 11 L15 9 L15 24 L5 26 Z" fill="#fdf3dc" />
      <path d="M17 9 L27 11 L27 26 L17 24 Z" fill="#f3dfb8" />
      <rect x="15" y="9" width="2" height="15" fill="#b4875a" />
      <rect x="7" y="14" width="6" height="1.5" fill="#7b4bb7" />
      <rect x="7" y="17.5" width="5" height="1.5" fill="#5fae6e" />
      <rect x="19" y="14" width="6" height="1.5" fill="#ff8fb1" />
      <rect x="19" y="17.5" width="4" height="1.5" fill="#2fb3a8" />
      <path d="M16 2.5 L17.3 5.6 L20.5 5.8 L18 7.8 L18.9 11 L16 9.2 L13.1 11 L14 7.8 L11.5 5.8 L14.7 5.6 Z" fill="#ffd166" />
    </svg>
  )
}

function Saat() {
  const [d, setD] = useState(() => new Date())
  useEffect(() => {
    const t = setInterval(() => setD(new Date()), 15000)
    return () => clearInterval(t)
  }, [])
  return <span className="hud-saat">{`${iki(d.getHours())}:${iki(d.getMinutes())}`}</span>
}

export default function App() {
  const { state, subscribe, clearLogs } = useStudio()
  const { connected, agentsMeta, agents, logs, jobs, stats, config } = state
  const [selected, setSelected] = useState(null)
  const [kartId, setKartId] = useState(null)
  const [modalJob, setModalJob] = useState(null)
  const [yeniAcik, setYeniAcik] = useState(false)
  const [tostlar, setTostlar] = useState([])
  const [ilkBekleme, setIlkBekleme] = useState(true)
  const seenAwaiting = useRef(new Set())
  const firstLoad = useRef(true)

  useEffect(() => {
    const t = setTimeout(() => setIlkBekleme(false), 2500)
    return () => clearTimeout(t)
  }, [])

  const tost = useCallback((metin, hata = false) => {
    const id = Math.random().toString(36).slice(2)
    setTostlar((l) => [...l, { id, metin, hata }].slice(-4))
    setTimeout(() => setTostlar((l) => l.filter((x) => x.id !== id)), hata ? 7000 : 4500)
  }, [])

  // Aktif iş: çalışan/sıradaki varsa o, yoksa en yenisi
  const activeJob = useMemo(
    () => jobs.find((j) => j.status === 'running') || jobs.find((j) => j.status === 'queued') || jobs[0] || null,
    [jobs],
  )
  const busy = jobs.some((j) => j.status === 'running' || j.status === 'queued')
  const onayIsi = jobs.find((j) => j.status === 'awaiting_approval') || null
  const hazir = agentsMeta.length > 0

  // Onaya düşen işi otomatik aç (sayfa ilk yüklendiğinde mevcut olanları açma)
  useEffect(() => {
    if (!jobs.length) return
    if (firstLoad.current) {
      jobs.filter((j) => j.status === 'awaiting_approval').forEach((j) => seenAwaiting.current.add(`${j.id}:${j.revision_count}`))
      firstLoad.current = false
      return
    }
    for (const j of jobs) {
      const key = `${j.id}:${j.revision_count}`
      if (j.status === 'awaiting_approval' && !seenAwaiting.current.has(key)) {
        seenAwaiting.current.add(key)
        setModalJob(j.id)
      }
    }
  }, [jobs])

  const roller = useMemo(
    () =>
      [...agentsMeta]
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
        .map((m) => rolNesnesi(m, agents[m.id], ajanDurumu(agents[m.id] || { id: m.id }, { bagli: connected, onayVar: !!onayIsi }))),
    [agentsMeta, agents, connected, onayIsi],
  )
  const adimlar = useMemo(() => (activeJob ? ADIMLAR.map(([id]) => (activeJob.step_status || {})[id] || 'pending') : []), [activeJob])
  const sayaclar = useMemo(
    () => ({ toplam: stats?.jobs_total || 0, video: stats?.videos_rendered || 0, onayli: stats?.approved || 0, yuklenen: stats?.uploaded || 0, hatali: stats?.failed || 0 }),
    [stats],
  )

  const say = useMemo(() => {
    const s = { calis: 0, hata: 0, soru: 0, bos: 0, uyku: 0 }
    for (const r of roller) s[r.durum] = (s[r.durum] || 0) + 1
    return s
  }, [roller])
  const bugunVideo = useMemo(() => {
    const bugun = new Date().toDateString()
    return jobs.filter((j) => j.video_url && j.created_at && new Date(j.created_at * 1000).toDateString() === bugun).length
  }, [jobs])

  const modal = modalJob ? jobs.find((j) => j.id === modalJob) : null
  const closeModal = useCallback(() => setModalJob(null), [])
  const seciliRol = roller.find((r) => r.anahtar === selected) || null
  const kartRol = roller.find((r) => r.anahtar === kartId) || null

  const git = useCallback((hedef = 'uretimPanosu') => {
    document.getElementById(hedef)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }, [])

  const calisanlar = roller.filter((r) => r.durum === 'calis' && r.anahtar !== 'director')
  const ofisAlt = !connected
    ? 'Sunucu bağlantısı bekleniyor'
    : calisanlar.length
      ? calisanlar.map((r) => `${r.kisa} çalışıyor: ${r.metin}`).join(' · ')
      : say.calis
        ? `Yönetmen: ${roller.find((r) => r.anahtar === 'director')?.metin || 'hazırlanıyor'}`
        : onayIsi
          ? `Yayıncı onayını bekliyor: “${onayIsi.title || onayIsi.topic}”`
          : 'Ekip boşta — yeni hikâye bekleniyor'

  return (
    <>
      <header className="ust">
        <div className="marka">
          <Logo />
          <div>
            <h1>Creative Studio</h1>
            <div className="alt">Piksel ofis · 8 ajanlı çocuk masalı Shorts üretim hattı</div>
          </div>
        </div>
        {config && (
          <span className={`saglik ${config.mock_mode ? 'bilgi' : 'uyari'}`} title={config.mock_mode ? 'Gerçek API çağrısı yapılmaz' : 'Gerçek API anahtarları kullanılıyor'}>
            {config.mock_mode ? 'MOCK MODU · API anahtarı yok' : 'GERÇEK MOD'}
          </span>
        )}
        {config && (
          <span className={`saglik ${config.upload_possible ? 'uyari' : 'iyi'}`} title="YouTube yüklemesi yalnızca önizleme çekmecesindeki açık onayla yapılır">
            Yükleme: {config.upload_possible ? 'onayla açık' : 'kapalı'} · {config.youtube_privacy_status}
          </span>
        )}
        <div className={`saglik ${connected ? `iyi${say.calis ? ' canli' : ''}` : 'hata'}`} role="status">
          <span className="nokta" />
          <span>{connected ? `WebSocket bağlı · ${say.calis} ajan çalışıyor` : 'Bağlantı bekleniyor'}</span>
        </div>
        <div className="eylemler">
          {onayIsi && (
            <button type="button" className="dugme uyari nabiz" onClick={() => setModalJob(onayIsi.id)}>
              🎞 Önizle & Onayla
            </button>
          )}
          <button type="button" className="dugme birincil" onClick={() => setYeniAcik(true)}>
            + Yeni hikâye
          </button>
        </div>
      </header>

      <div id="uyarilar" aria-live="polite">
        {!connected && !ilkBekleme && (
          <div className="serit hata">
            <b>Sunucuya bağlanılamıyor.</b> Backend kapalı olabilir: proje kökünde <code>baslat.ps1</code> çalıştırın. Panel kendiliğinden yeniden bağlanır.
          </div>
        )}
        {onayIsi && (
          <div className="serit bilgi">
            🎞 <b>“{onayIsi.title || onayIsi.topic}”</b> önizlemesi onayını bekliyor. Hiçbir şey sen onaylamadan yüklenmez.
            <button type="button" className="baglanti bosluk" onClick={() => setModalJob(onayIsi.id)}>
              Önizle & Onayla
            </button>
          </div>
        )}
        {config && !config.mock_mode && config.upload_possible && (
          <div className="serit uyari">
            Gerçek YouTube yüklemesi açık (.env). Yükleme yalnızca önizleme çekmecesindeki onay kutusu + düğmeyle yapılır.
          </div>
        )}
      </div>

      <main>
        <section aria-labelledby="ofisBaslik">
          <div className="bolum-baslik">
            <h2 id="ofisBaslik">Ofis</h2>
            <span className="soluk">{ofisAlt}</span>
          </div>
          <div className="oyun">
            <div className="hud">
              <div className="hud-durum">
                <span className={`hud-cip calis${say.calis ? ' canli' : ''}`}>
                  <i />
                  {say.calis} çalışıyor
                </span>
                {say.hata > 0 && (
                  <span className="hud-cip hata">
                    <i />
                    {say.hata} hata
                  </span>
                )}
                {say.soru > 0 && (
                  <span className="hud-cip soru">
                    <i />
                    onay bekleniyor
                  </span>
                )}
                {say.bos + say.uyku > 0 && (
                  <span className="hud-cip bos">
                    <i />
                    {say.bos + say.uyku} boşta
                  </span>
                )}
                <span className="hud-cip tamam" title="Bugün üretilen video sayısı">
                  ✓ bugün {bugunVideo} video
                </span>
              </div>
              <div className="hud-sag">
                {config && (
                  <div className="hud-enerji" title="Varsayılan motorlar (her iş için yeni hikâye penceresinden seçilebilir)">
                    <span className="hud-etiket">Motorlar</span>
                    <span className="enerji">🎨 {MOTOR_KISA[config.image_provider] || config.image_provider}</span>
                    <span className="enerji">🎙 {MOTOR_KISA[config.tts_provider] || config.tts_provider}</span>
                  </div>
                )}
                <Saat />
              </div>
            </div>
            <HatSeridi job={activeJob} onAc={setModalJob} />
            <OfisSahnesi
              roller={roller}
              jobs={jobs}
              hazir={hazir}
              adimlar={adimlar}
              sayaclar={sayaclar}
              bagli={connected}
              mock={config?.mock_mode}
              secili={selected}
              onSec={setSelected}
              onPano={git}
              subscribe={subscribe}
            />
          </div>
        </section>

        <LogTerminal logs={logs} filter={selected} onFilter={setSelected} onClear={clearLogs} />

        <UretimPanosu jobs={jobs} onAc={setModalJob} />

        <Istatistik stats={stats} config={config} onKart={setKartId} />
      </main>

      <AjanPenceresi rol={seciliRol} stats={stats} jobs={jobs} logs={logs} onKapat={() => setSelected(null)} onKart={setKartId} onIsAc={setModalJob} />
      <KarakterKarti
        rol={kartRol}
        stats={stats}
        config={config}
        jobs={jobs}
        logs={logs}
        onKapat={() => setKartId(null)}
        onIsAc={(id) => {
          setKartId(null)
          setModalJob(id)
        }}
        onLoglar={() => {
          setSelected(kartId)
          setKartId(null)
          git('terminal')
        }}
      />
      <YeniHikaye acik={yeniAcik} onKapat={() => setYeniAcik(false)} busy={busy} config={config} tost={tost} />
      {modal && <OnizlemeCekmecesi job={modal} config={config} onClose={closeModal} tost={tost} />}
      <div id="tostlar" aria-live="polite">
        {tostlar.map((t) => (
          <div key={t.id} className={`tost${t.hata ? ' hata' : ''}`}>
            {t.metin}
          </div>
        ))}
      </div>
    </>
  )
}
