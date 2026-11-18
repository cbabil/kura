/**
 * The real API: fetch for requests, a WebSocket for the stats stream.
 * The session cookie is HttpOnly and same-origin, so no token is handled here.
 * Requests that change something carry X-Kura-Request: a custom header needs
 * a CORS preflight, so another site cannot forge them; kura-desktopd refuses
 * POST and PUT without it (CSRF defence, alongside SameSite=Strict and Origin).
 */
import type { Api, LoginError, LoginResult, Prefs, StatsMessage, SystemInfo, User } from './types'

const CHANGE = { 'x-kura-request': '1' }
const JSON_HEADERS = { ...CHANGE, 'content-type': 'application/json' }

async function request(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(path, { credentials: 'same-origin', ...init })
}

async function json<T>(path: string): Promise<T> {
  const res = await request(path)
  if (!res.ok) throw new Error(`${path} failed (${res.status})`)
  return (await res.json()) as T
}

const REFUSALS: Record<number, LoginError> = { 401: 'wrong', 403: 'expired', 429: 'rate' }

async function login(user: string, password: string): Promise<LoginResult> {
  let res: Response
  try {
    res = await request('/api/login', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify({ user, password }) })
  } catch {
    return { ok: false, error: 'network' }
  }
  if (res.ok) return { ok: true, user: ((await res.json()) as { user: User }).user }
  const error = REFUSALS[res.status] ?? 'network'
  const retry = Number(res.headers.get('retry-after'))
  return error === 'rate' && retry > 0 ? { ok: false, error, retryAfter: retry } : { ok: false, error }
}

function stats(onMessage: (m: StatsMessage) => void): () => void {
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws'
  const socket = new WebSocket(`${scheme}://${location.host}/api/stats`)
  socket.onmessage = (event: MessageEvent<string>) => {
    try {
      onMessage(JSON.parse(event.data) as StatsMessage)
    } catch {
      // A malformed frame is dropped; the next sample replaces it.
    }
  }
  return () => socket.close()
}

export const httpApi: Api = {
  async session() {
    const res = await request('/api/session')
    return res.ok ? ((await res.json()) as { user: User }).user : null
  },
  login,
  async logout() {
    await request('/api/logout', { method: 'POST', headers: CHANGE })
  },
  system: () => json<SystemInfo>('/api/system'),
  async prefs() {
    const res = await request('/api/prefs')
    return res.ok ? ((await res.json()) as Prefs) : null
  },
  async savePrefs(prefs) {
    const res = await request('/api/prefs', { method: 'PUT', headers: JSON_HEADERS, body: JSON.stringify(prefs) })
    if (!res.ok) throw new Error(`/api/prefs failed (${res.status})`)
  },
  stats,
}
