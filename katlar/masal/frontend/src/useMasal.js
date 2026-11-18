import { useCallback, useEffect, useReducer, useRef } from 'react'

const MAX_LOGS = 600

const initial = {
  connected: false,
  agentsMeta: [],
  agents: {},
  logs: [],
  jobs: [],
  stats: null,
  config: null,
  currentJob: null,
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
      return {
        ...state,
        agentsMeta: m.agents_meta || [],
        agents,
        logs: (m.logs || []).slice(-MAX_LOGS),
        jobs: m.jobs || [],
        stats: m.stats,
        config: m.config,
        currentJob: m.current_job,
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
    default:
      return state
  }
}

export function useMasal() {
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

  return { state, subscribe, clearLogs }
}

export async function api(path, body) {
  const res = await fetch(path, {
    method: body ? 'POST' : 'GET',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`)
  return data
}
