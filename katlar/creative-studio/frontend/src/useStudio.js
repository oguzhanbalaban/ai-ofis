import { useCallback, useEffect, useReducer, useRef } from 'react'

const MAX_LOGS = 600
const MAX_SOHBET = 120

const initial = {
  connected: false,
  agentsMeta: [],
  agents: {},
  logs: [],
  jobs: [],
  stats: null,
  config: null,
  currentJob: null,
  office: { durum: 'acik', ad: 'açık' },
  chat: { isleniyor: [], motor: 'yerel', ad: '' },
  // ajan -> mesaj listesi (pencere açılınca /api/chat/<ajan>'dan yüklenir, sonra WebSocket ile güncellenir)
  sohbetler: {},
  yaziyor: {},
  bildirimler: [],
}

function upsertJob(jobs, job) {
  const i = jobs.findIndex((j) => j.id === job.id)
  if (i === -1) return [job, ...jobs].slice(0, 40)
  const next = jobs.slice()
  next[i] = { ...jobs[i], ...job }
  return next
}

function reducer(state, action) {
  switch (action.type) {
    case 'connected':
      return { ...state, connected: action.value }
    case 'snapshot': {
      const m = action.msg
      const agents = {}
      for (const a of m.agents || []) agents[a.id] = a
      const yaziyor = {}
      for (const a of m.chat?.isleniyor || []) yaziyor[a] = true
      return {
        ...state,
        agentsMeta: m.agents_meta || [],
        agents,
        logs: (m.logs || []).slice(-MAX_LOGS),
        jobs: m.jobs || [],
        stats: m.stats,
        config: m.config,
        currentJob: m.current_job,
        office: m.office || state.office,
        chat: m.chat || state.chat,
        yaziyor,
      }
    }
    case 'agent':
      return { ...state, agents: { ...state.agents, [action.agent.id]: action.agent } }
    case 'log': {
      const logs = state.logs.length >= MAX_LOGS ? state.logs.slice(-MAX_LOGS + 1) : state.logs.slice()
      logs.push(action.log)
      return { ...state, logs }
    }
    case 'job':
      return { ...state, jobs: upsertJob(state.jobs, action.job) }
    case 'stats':
      return { ...state, stats: action.stats }
    case 'clearLogs':
      return { ...state, logs: [] }
    case 'office':
      return { ...state, office: action.office }
    case 'sohbetYuklendi':
      return {
        ...state,
        sohbetler: { ...state.sohbetler, [action.ajan]: action.mesajlar.slice(-MAX_SOHBET) },
        yaziyor: { ...state.yaziyor, [action.ajan]: !!action.yaziyor },
        chat: action.motor ? { ...state.chat, ...action.motor } : state.chat,
      }
    case 'sohbetMesaji': {
      const eski = state.sohbetler[action.ajan]
      if (!eski) return state // pencere hiç açılmadıysa yüklenince gelir
      if (eski.some((m) => m.id === action.mesaj.id)) return state
      return { ...state, sohbetler: { ...state.sohbetler, [action.ajan]: [...eski, action.mesaj].slice(-MAX_SOHBET) } }
    }
    case 'sohbetTemiz':
      return { ...state, sohbetler: { ...state.sohbetler, [action.ajan]: [] } }
    case 'yaziyor': {
      const isleniyor = new Set(state.chat.isleniyor || [])
      if (action.value) isleniyor.add(action.ajan)
      else isleniyor.delete(action.ajan)
      return { ...state, yaziyor: { ...state.yaziyor, [action.ajan]: action.value }, chat: { ...state.chat, isleniyor: [...isleniyor] } }
    }
    case 'bildirim':
      return { ...state, bildirimler: [action.bildirim, ...state.bildirimler].slice(0, 30) }
    default:
      return state
  }
}

export function useStudio() {
  const [state, dispatch] = useReducer(reducer, initial)
  const listeners = useRef(new Set())
  const wsRef = useRef(null)

  useEffect(() => {
    let stop = false
    let retry = 0
    let timer = null
    const connect = () => {
      const proto = location.protocol === 'https:' ? 'wss' : 'ws'
      const ws = new WebSocket(`${proto}://${location.host}/ws`)
      wsRef.current = ws
      ws.onopen = () => {
        retry = 0
        dispatch({ type: 'connected', value: true })
      }
      ws.onmessage = (ev) => {
        let msg
        try {
          msg = JSON.parse(ev.data)
        } catch {
          return
        }
        if (msg.type === 'snapshot') dispatch({ type: 'snapshot', msg })
        else if (msg.type === 'agent') dispatch({ type: 'agent', agent: msg.agent })
        else if (msg.type === 'log') dispatch({ type: 'log', log: msg.log })
        else if (msg.type === 'job') dispatch({ type: 'job', job: msg.job })
        else if (msg.type === 'stats') dispatch({ type: 'stats', stats: msg.stats })
        else if (msg.type === 'office') dispatch({ type: 'office', office: msg.office })
        else if (msg.type === 'chat') dispatch({ type: 'sohbetMesaji', ajan: msg.ajan, mesaj: msg.mesaj })
        else if (msg.type === 'chat_typing') dispatch({ type: 'yaziyor', ajan: msg.ajan, value: msg.yaziyor })
        else if (msg.type === 'chat_clear') dispatch({ type: 'sohbetTemiz', ajan: msg.ajan })
        else if (msg.type === 'notify') dispatch({ type: 'bildirim', bildirim: msg.notify })
        for (const fn of listeners.current) fn(msg)
      }
      ws.onclose = () => {
        dispatch({ type: 'connected', value: false })
        if (stop) return
        retry = Math.min(retry + 1, 6)
        timer = setTimeout(connect, 500 * 2 ** retry)
      }
      ws.onerror = () => ws.close()
    }
    connect()
    const ping = setInterval(() => {
      if (wsRef.current && wsRef.current.readyState === 1) wsRef.current.send('ping')
    }, 25000)
    return () => {
      stop = true
      clearTimeout(timer)
      clearInterval(ping)
      if (wsRef.current) wsRef.current.close()
    }
  }, [])

  const subscribe = useCallback((fn) => {
    listeners.current.add(fn)
    return () => listeners.current.delete(fn)
  }, [])

  const clearLogs = useCallback(() => dispatch({ type: 'clearLogs' }), [])

  const sohbetYukle = useCallback(async (ajan) => {
    const d = await api(`/api/chat/${ajan}`)
    dispatch({ type: 'sohbetYuklendi', ajan, mesajlar: d.mesajlar || [], yaziyor: d.yaziyor, motor: { motor: d.motor, ad: d.ad, not: d.not } })
  }, [])

  return { state, subscribe, clearLogs, sohbetYukle }
}

export async function api(path, body) {
  const res = await fetch(path, {
    method: body ? 'POST' : 'GET',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) {
    const d = data.detail
    throw new Error(typeof d === 'string' ? d : Array.isArray(d) ? d.map((x) => x.msg).join('; ') : `HTTP ${res.status}`)
  }
  return data
}
