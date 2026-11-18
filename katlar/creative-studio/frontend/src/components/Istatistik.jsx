import { AJANLAR, AJAN_SIRASI, para } from '../sabitler.js'

// Maliyet ve istatistik: sayaçlar + ajan başarı oranları (satıra tıkla → karakter kartı)
export default function Istatistik({ stats, config, onKart, onOzet }) {
  if (!stats) return null
  const steps = stats.steps || {}
  return (
    <section aria-labelledby="istBaslik" id="istatistik">
      <div className="bolum-baslik">
        <h2 id="istBaslik">Maliyet ve istatistik</h2>
        <span className="soluk">
          video başına ≈ {para(stats.cost_per_video_usd)}
          {config?.mock_mode ? ' · mock modda gerçek harcama $0 (gerçek modda tutacak tahmin)' : ''}
        </span>
        <button type="button" className="dugme kucuk bolum-dugme" onClick={onOzet}>
          📄 Günlük özet
        </button>
      </div>
      <div className="kul-kpi">
        <div className="sayac">
          <div className="s-etiket">Video</div>
          <div className="s-deger">{stats.videos_rendered}</div>
          <div className="s-alt">toplam {stats.jobs_total} iş</div>
        </div>
        <div className="sayac">
          <div className="s-etiket">Onaylı</div>
          <div className="s-deger">{stats.approved}</div>
          <div className="s-alt">{stats.awaiting_approval || 0} onay bekliyor</div>
        </div>
        <div className="sayac">
          <div className="s-etiket">Yüklenen</div>
          <div className="s-deger">{stats.uploaded}</div>
          <div className="s-alt">yalnız onay penceresinden</div>
        </div>
        <div className="sayac">
          <div className="s-etiket">Tahmini maliyet</div>
          <div className="s-deger">{para(stats.cost_total_usd)}</div>
          <div className="s-alt">
            {stats.failed || 0} başarısız{stats.cancelled ? ` · ${stats.cancelled} iptal` : ''} iş
          </div>
        </div>
      </div>
      <div className="kart">
        <h2>Ajan başarı oranları</h2>
        <div className="tablo-sar">
          <table className="kul-tablo">
            <thead>
              <tr>
                <th>Ajan</th>
                <th>Başarı</th>
                <th className="sag">Başarılı</th>
                <th className="sag">Hatalı</th>
                <th className="sag gizle-m">Ort. süre</th>
                <th className="sag gizle-m">Maliyet</th>
              </tr>
            </thead>
            <tbody>
              {AJAN_SIRASI.map((id) => {
                const s = steps[id]
                const a = AJANLAR[id]
                const rate = s && s.rate != null ? Math.round(s.rate * 100) : null
                const renk = rate == null ? 'transparent' : rate >= 90 ? 'var(--yesil)' : rate >= 60 ? 'var(--sari)' : 'var(--kirmizi)'
                return (
                  <tr key={id} className="tiklanir" tabIndex={0} onClick={() => onKart(id)} onKeyDown={(e) => e.key === 'Enter' && onKart(id)}
                    title={s ? `${s.success} başarılı / ${s.fail} hatalı · ort. ${s.avg_seconds ?? '-'} sn` : 'Henüz çalışmadı'}>
                    <td>
                      <span className="kul-ad" style={{ '--rol': a.renk }}>
                        <span className="rol-nokta" />
                        {a.kisa}
                      </span>
                    </td>
                    <td>
                      <span className="baglam">
                        <span className="bc">
                          <i style={{ width: `${rate ?? 0}%`, background: renk }} />
                        </span>
                        <b>{rate == null ? '—' : `%${rate}`}</b>
                      </span>
                    </td>
                    <td className="sag">{s ? s.success : 0}</td>
                    <td className={`sag${s && s.fail ? ' hata-yazi' : ''}`}>{s ? s.fail : 0}</td>
                    <td className="sag gizle-m">{s?.avg_seconds != null ? `${s.avg_seconds} sn` : '—'}</td>
                    <td className="sag gizle-m">{s ? para(s.cost_usd, 4) : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        <div className="kul-not">Başarı oranı = başarılı adım / toplam adım (tüm işler). Bir satıra tıkla: o ajanın karakter kartı açılır.</div>
      </div>
    </section>
  )
}
