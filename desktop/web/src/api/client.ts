/**
 * The real API: fetch for requests, a WebSocket for the stats stream.
 * The session cookie is HttpOnly and same-origin, so no token is handled here.
 * Requests that change something carry X-Kura-Request: a custom header needs
 * a CORS preflight, so another site cannot forge them; kura-desktopd refuses
 * POST and PUT without it (CSRF defence, alongside SameSite=Strict and Origin).
 */
import { API_ERROR_CODES, ApiError, type Api, type Container, type AppChange, type Catalog, type FileChange, type Folder, type JournalFilter, type JournalPage, type LogLine, type LoginError, type LoginResult, type Prefs, type StatsMessage, type SystemInfo, type TerminalHandlers, type Settings, type TerminalSession, type Trashed, type UpdateStatus, type User } from './types'

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

/** A request of the D2 apps: the JSON answer (nothing for 204), or an ApiError with the server's code. */
async function call<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response
  try {
    res = await request(path, init)
  } catch {
    throw new ApiError('network')
  }
  const body = (await res.json().catch(() => null)) as ({ error?: string } & T) | null
  if (res.ok && (res.status === 204 || body !== null)) return body as T
  const code = API_ERROR_CODES.find((c) => c === body?.error)
  throw new ApiError(code ?? 'unavailable')
}

const wsUrl = (path: string) => `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}${path}`

function journal(filter: JournalFilter): Promise<JournalPage> {
  const query = new URLSearchParams()
  for (const [key, value] of Object.entries(filter)) {
    if (value !== undefined && value !== '') query.set(key, String(value))
  }
  const text = query.toString()
  return call<JournalPage>(text ? `/api/journal?${text}` : '/api/journal')
}

/** Binary frames carry the terminal's bytes both ways; text frames are JSON control messages. */
function terminal(size: { cols: number; rows: number }, handlers: TerminalHandlers): TerminalSession {
  const socket = new WebSocket(wsUrl(`/api/terminal?cols=${size.cols}&rows=${size.rows}`))
  socket.binaryType = 'arraybuffer'
  const encoder = new TextEncoder()
  let opened = false
  let exited = false
  socket.onopen = () => {
    opened = true
    handlers.onOpen()
  }
  socket.onmessage = (event: MessageEvent<ArrayBuffer | string>) => {
    if (typeof event.data !== 'string') handlers.onData(new Uint8Array(event.data))
    else if (isExit(event.data)) exited = true
  }
  socket.onclose = () => handlers.onEnd(exited ? 'exit' : opened ? 'lost' : 'refused')
  const send = (data: string | Uint8Array) => {
    if (socket.readyState === WebSocket.OPEN) socket.send(data)
  }
  return {
    write: (data) => send(typeof data === 'string' ? encoder.encode(data) : data),
    resize: (cols, rows) => send(JSON.stringify({ type: 'resize', cols, rows })),
    close() {
      // Closed on purpose: nothing ended that the window should hear about.
      socket.onclose = null
      socket.close()
    },
  }
}

/** True for the server's `{"type":"exit"}` control message. */
function isExit(text: string): boolean {
  try {
    return (JSON.parse(text) as { type?: string }).type === 'exit'
  } catch {
    return false
  }
}

const fileUrl = (path: string, inline?: boolean) => `/api/files/content?path=${encodeURIComponent(path)}${inline ? '&inline=1' : ''}`

async function fileText(path: string): Promise<string> {
  const res = await request(fileUrl(path, true)).catch(() => null)
  if (!res?.ok) throw new ApiError(res?.status === 404 ? 'not_found' : 'unavailable')
  return res.text()
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
  const socket = new WebSocket(wsUrl('/api/stats'))
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
  containers: () => call<Container[]>('/api/containers'),
  containerAction: (id, action) => call<void>(`/api/containers/${id}/${action}`, { method: 'POST', headers: CHANGE }),
  containerLogs: (id, lines) => call<LogLine[]>(`/api/containers/${id}/logs?lines=${lines}`),
  journal,
  updates: () => call<UpdateStatus>('/api/updates'),
  startUpdate: (what) => call<void>(`/api/updates/${what}`, { method: 'POST', headers: CHANGE }),
  power: (how) => call<void>(`/api/power/${how}`, { method: 'POST', headers: CHANGE }),
  settings: () => call<Settings>('/api/settings'),
  changeSetting: (change) => call<void>('/api/settings', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify(change) }),
  changePassword: (current, password) =>
    call<void>('/api/password', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify({ current, password }) }),
  catalog: () => call<Catalog>('/api/catalog'),
  changeApp: (change: AppChange) => call<void>('/api/catalog', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify(change) }),
  files: (path) => call<Folder>(path ? `/api/files?path=${encodeURIComponent(path)}` : '/api/files'),
  fileChange: (change: FileChange) => call<void>('/api/files', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify(change) }),
  trash: async () => (await call<{ items: Trashed[] }>('/api/files/trash')).items,
  fileUrl,
  fileText,
  upload: (path, data) => call<void>(`/api/files/content?path=${encodeURIComponent(path)}`, { method: 'PUT', headers: CHANGE, body: data }),
  terminal,
}
