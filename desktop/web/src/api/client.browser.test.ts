import { httpApi } from './client'

describe('httpApi: the shared Browser (ADR-036)', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('opens the screen as a WebSocket on this server', () => {
    const made: string[] = []
    vi.stubGlobal('WebSocket', class { constructor(url: string) { made.push(url) } })
    httpApi.browser()
    expect(made).toEqual([`ws://${location.host}/api/browser`])
  })

  it('quits it with the request header', async () => {
    const fetchMock = vi.fn(() => Promise.resolve(new Response(null, { status: 204 })))
    vi.stubGlobal('fetch', fetchMock)
    await httpApi.browserStop()
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit & { headers: Record<string, string> }]
    expect([url, init.method, init.headers['x-kura-request']]).toEqual(['/api/browser/stop', 'POST', '1'])
  })
})
