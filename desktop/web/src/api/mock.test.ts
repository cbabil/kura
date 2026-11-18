import { createMockApi, MOCK_PASSWORD } from './mock'
import type { StatsMessage } from './types'

describe('mock api', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('signs in with the mock password only, and remembers the session', async () => {
    const api = createMockApi()
    expect(await api.session()).toBeNull()
    expect(await api.login('chris', 'nope')).toEqual({ ok: false, error: 'wrong' })
    expect(await api.login('expired', MOCK_PASSWORD)).toEqual({ ok: false, error: 'expired' })
    const ok = await api.login('chris', MOCK_PASSWORD)
    expect(ok).toEqual({ ok: true, user: { name: 'chris', uid: 1000, admin: true } })
    expect(await api.session()).toEqual({ name: 'chris', uid: 1000, admin: true })
    await api.logout()
    expect(await api.session()).toBeNull()
  })

  it('keeps prefs it is given', async () => {
    const api = createMockApi()
    expect(await api.prefs()).toBeNull()
    await api.savePrefs({ theme: 'light', dock: ['files'], windows: {} })
    expect(await api.prefs()).toEqual({ theme: 'light', dock: ['files'], windows: {} })
  })

  it('describes a system', async () => {
    const sys = await createMockApi().system()
    expect(sys.hostname).toBe('kura-nuc')
    expect(sys.cores).toBe(4)
  })

  it('streams a snapshot then samples, until stopped', () => {
    const seen: StatsMessage[] = []
    const stop = createMockApi().stats((m) => seen.push(m))
    expect(seen[0].type).toBe('snapshot')
    const snap = seen[0] as Extract<StatsMessage, { type: 'snapshot' }>
    expect(snap.history['1h'].length).toBe(1800)
    expect(snap.history['24h'].length).toBe(1440)
    expect(snap.units.length).toBeGreaterThan(3)
    vi.advanceTimersByTime(4000)
    expect(seen.filter((m) => m.type === 'sample')).toHaveLength(2)
    for (const m of seen) {
      const s = m.type === 'sample' ? m.sample : m.history['1h'][0]
      expect(s.cpu).toBeGreaterThanOrEqual(0)
      expect(s.cpu).toBeLessThanOrEqual(100)
    }
    stop()
    vi.advanceTimersByTime(4000)
    expect(seen.filter((m) => m.type === 'sample')).toHaveLength(2)
  })
})
