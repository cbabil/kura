import { httpApi } from './client'
import { ApiError, type TerminalEnd } from './types'

function reply(status: number, body?: unknown) {
  return Promise.resolve(
    new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } }),
  )
}

const code = (p: Promise<unknown>) => p.then(() => 'resolved', (e: unknown) => (e instanceof ApiError ? e.code : 'other'))

describe('httpApi: containers and the journal', () => {
  const fetchMock = vi.fn()
  beforeEach(() => {
    fetchMock.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  it('lists containers and reads their logs', async () => {
    fetchMock.mockReturnValueOnce(reply(200, [{ id: 'a' }])).mockReturnValueOnce(reply(200, [{ text: 'hi' }]))
    expect(await httpApi.containers()).toEqual([{ id: 'a' }])
    expect(await httpApi.containerLogs('abc', 50)).toEqual([{ text: 'hi' }])
    expect(fetchMock.mock.calls.map((c) => c[0])).toEqual(['/api/containers', '/api/containers/abc/logs?lines=50'])
  })

  it('posts an action with the request header', async () => {
    fetchMock.mockReturnValueOnce(reply(204))
    await httpApi.containerAction('abc', 'restart')
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/containers/abc/restart')
    expect(init.method).toBe('POST')
    expect(init.headers['x-kura-request']).toBe('1')
  })

  it('turns each refusal into its code', async () => {
    fetchMock
      .mockReturnValueOnce(reply(403, { error: 'admin' }))
      .mockReturnValueOnce(reply(401, { error: 'signed_out' }))
      .mockReturnValueOnce(reply(404, { error: 'not_found' }))
      .mockReturnValueOnce(reply(503, { error: 'unavailable' }))
      .mockReturnValueOnce(reply(500))
      .mockReturnValueOnce(reply(418, { error: 'teapot' }))
      .mockRejectedValueOnce(new TypeError('offline'))
      .mockReturnValueOnce(Promise.resolve(new Response('<html>a proxy page</html>', { status: 200 })))
    const got = []
    for (let i = 0; i < 7; i++) got.push(await code(httpApi.containerAction('abc', 'stop')))
    expect(got).toEqual(['admin', 'signed_out', 'not_found', 'unavailable', 'unavailable', 'unavailable', 'network'])
    expect(await code(httpApi.containers())).toBe('unavailable')
  })

  it('reads the update status, starts an update and switches the server off', async () => {
    fetchMock.mockReturnValueOnce(reply(200, { current: '0.6.1' })).mockImplementation(() => reply(204))
    expect(await httpApi.updates()).toEqual({ current: '0.6.1' })
    await httpApi.startUpdate('install')
    await httpApi.power('restart')
    expect(fetchMock.mock.calls.map((c) => [c[0], c[1]?.method])).toEqual([
      ['/api/updates', undefined], ['/api/updates/install', 'POST'], ['/api/power/restart', 'POST'],
    ])
    expect(fetchMock.mock.calls[2][1].headers['x-kura-request']).toBe('1')
  })

  it('reads settings, posts a change and a new password as JSON', async () => {
    fetchMock.mockReturnValueOnce(reply(200, { hostname: 'kura' })).mockImplementation(() => reply(204))
    expect(await httpApi.settings()).toEqual({ hostname: 'kura' })
    await httpApi.changeSetting({ what: 'ntp', on: false })
    await httpApi.changePassword('old', 'new')
    const [, change, password] = fetchMock.mock.calls
    expect([change[0], change[1].method, JSON.parse(change[1].body)]).toEqual(['/api/settings', 'POST', { what: 'ntp', on: false }])
    expect([password[0], JSON.parse(password[1].body)]).toEqual(['/api/password', { current: 'old', password: 'new' }])
    expect(password[1].headers['x-kura-request']).toBe('1')
  })

  it('sends only the journal filters that are set', async () => {
    fetchMock.mockImplementation(() => reply(200, { entries: [], cursor: null }))
    await httpApi.journal({})
    await httpApi.journal({ lines: 300, unit: 'ssh.service', priority: 3, after: 's=1;i=2' })
    expect(fetchMock.mock.calls.map((c) => c[0])).toEqual([
      '/api/journal',
      '/api/journal?lines=300&unit=ssh.service&priority=3&after=s%3D1%3Bi%3D2',
    ])
  })
})

class FakeSocket {
  static last: FakeSocket
  static OPEN = 1
  readyState = 0
  binaryType = ''
  sent: unknown[] = []
  closed = false
  onopen: (() => void) | null = null
  onmessage: ((e: { data: unknown }) => void) | null = null
  onclose: (() => void) | null = null
  constructor(public url: string) {
    FakeSocket.last = this
  }
  send(data: unknown) {
    this.sent.push(data)
  }
  close() {
    this.closed = true
  }
  open() {
    this.readyState = 1
    this.onopen?.()
  }
}

describe('httpApi: the terminal', () => {
  beforeEach(() => vi.stubGlobal('WebSocket', FakeSocket))
  afterEach(() => vi.unstubAllGlobals())

  function start() {
    const seen: string[] = []
    const ends: TerminalEnd[] = []
    const opened = vi.fn()
    const session = httpApi.terminal(
      { cols: 100, rows: 30 },
      { onOpen: opened, onData: (b) => seen.push(new TextDecoder().decode(b)), onEnd: (r) => ends.push(r) },
    )
    return { session, socket: FakeSocket.last, seen, ends, opened }
  }

  it('opens a socket of the terminal’s size and relays both ways', () => {
    const { session, socket, seen, ends, opened } = start()
    expect(socket.url).toMatch(/^ws:\/\/.*\/api\/terminal\?cols=100&rows=30$/)
    expect(socket.binaryType).toBe('arraybuffer')
    session.write('too early')
    expect(socket.sent).toHaveLength(0)
    socket.open()
    expect(opened).toHaveBeenCalled()
    socket.onmessage?.({ data: new TextEncoder().encode('$ ').buffer })
    expect(seen).toEqual(['$ '])
    session.write('ls\r')
    session.resize(120, 40)
    expect(new TextDecoder().decode(socket.sent[0] as Uint8Array)).toBe('ls\r')
    expect(socket.sent[1]).toBe('{"type":"resize","cols":120,"rows":40}')
    socket.onmessage?.({ data: 'not json "exit"' })
    socket.onmessage?.({ data: '{"type":"exit"}' })
    socket.onclose?.()
    expect(ends).toEqual(['exit'])
    session.close()
    expect(socket.closed).toBe(true)
  })

  it('reports nothing once it was closed on purpose', () => {
    const { session, socket, ends } = start()
    socket.open()
    session.close()
    expect(socket.onclose).toBeNull()
    expect(ends).toEqual([])
  })

  it('tells a refused terminal from a lost one', () => {
    const refused = start()
    refused.socket.onclose?.()
    expect(refused.ends).toEqual(['refused'])
    const lost = start()
    lost.socket.open()
    lost.socket.onclose?.()
    expect(lost.ends).toEqual(['lost'])
  })
})
