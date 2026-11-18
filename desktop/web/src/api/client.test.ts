import { httpApi } from './client'

const user = { name: 'chris', uid: 1000, admin: true }

function reply(status: number, body?: unknown, headers: Record<string, string> = {}) {
  return Promise.resolve(
    new Response(body === undefined ? null : JSON.stringify(body), {
      status,
      headers: { 'content-type': 'application/json', ...headers },
    }),
  )
}

describe('httpApi', () => {
  const fetchMock = vi.fn()
  beforeEach(() => {
    fetchMock.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  it('returns the session user, or null when signed out', async () => {
    fetchMock.mockReturnValueOnce(reply(200, { user })).mockReturnValueOnce(reply(401))
    expect(await httpApi.session()).toEqual(user)
    expect(await httpApi.session()).toBeNull()
  })

  it('sends credentials as JSON and maps each refusal', async () => {
    fetchMock
      .mockReturnValueOnce(reply(200, { user }))
      .mockReturnValueOnce(reply(401, { error: 'wrong' }))
      .mockReturnValueOnce(reply(403, { error: 'expired' }))
      .mockReturnValueOnce(reply(429, { error: 'rate' }, { 'retry-after': '42' }))
      .mockRejectedValueOnce(new TypeError('offline'))
    expect(await httpApi.login('chris', 'pw')).toEqual({ ok: true, user })
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/login')
    expect(init.method).toBe('POST')
    expect(init.headers['x-kura-request']).toBe('1')
    expect(JSON.parse(init.body)).toEqual({ user: 'chris', password: 'pw' })
    expect(await httpApi.login('chris', 'x')).toEqual({ ok: false, error: 'wrong' })
    expect(await httpApi.login('chris', 'x')).toEqual({ ok: false, error: 'expired' })
    expect(await httpApi.login('chris', 'x')).toEqual({ ok: false, error: 'rate', retryAfter: 42 })
    expect(await httpApi.login('chris', 'x')).toEqual({ ok: false, error: 'network' })
  })

  it('reads system info and prefs, and saves prefs', async () => {
    const sys = { hostname: 'kura', os: 'Kura 0.6.0', kernel: '6.12', arch: 'x86_64', cores: 4, memTotal: 1, uptime: 5 }
    const prefs = { theme: 'dark', dock: ['activity'], windows: {} }
    fetchMock
      .mockReturnValueOnce(reply(200, sys))
      .mockReturnValueOnce(reply(200, prefs))
      .mockReturnValueOnce(reply(404))
      .mockReturnValueOnce(reply(204))
    expect(await httpApi.system()).toEqual(sys)
    expect(await httpApi.prefs()).toEqual(prefs)
    expect(await httpApi.prefs()).toBeNull()
    await httpApi.savePrefs(prefs as never)
    expect(fetchMock.mock.calls[3][1].method).toBe('PUT')
    expect(fetchMock.mock.calls[3][1].headers['x-kura-request']).toBe('1')
  })

  it('throws on a failed request it cannot recover from', async () => {
    fetchMock.mockReturnValueOnce(reply(500)).mockReturnValueOnce(reply(500))
    await expect(httpApi.system()).rejects.toThrow('/api/system failed (500)')
    await expect(httpApi.savePrefs({ theme: 'dark', dock: [], windows: {} })).rejects.toThrow()
  })

  it('posts logout', async () => {
    fetchMock.mockReturnValueOnce(reply(204))
    await httpApi.logout()
    expect(fetchMock).toHaveBeenCalledWith('/api/logout', expect.objectContaining({ method: 'POST', headers: { 'x-kura-request': '1' } }))
  })

  it('streams stats over a WebSocket and closes it', () => {
    const sockets: FakeSocket[] = []
    class FakeSocket {
      onmessage: ((e: { data: string }) => void) | null = null
      closed = false
      constructor(public url: string) {
        sockets.push(this)
      }
      close() {
        this.closed = true
      }
    }
    vi.stubGlobal('WebSocket', FakeSocket)
    const seen: unknown[] = []
    const stop = httpApi.stats((m) => seen.push(m))
    expect(sockets[0].url).toBe(`ws://${location.host}/api/stats`)
    sockets[0].onmessage?.({ data: JSON.stringify({ type: 'sample', sample: { t: 1 } }) })
    sockets[0].onmessage?.({ data: 'not json' })
    expect(seen).toEqual([{ type: 'sample', sample: { t: 1 } }])
    stop()
    expect(sockets[0].closed).toBe(true)
  })
})
