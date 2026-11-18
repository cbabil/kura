import { act, render, screen } from '@testing-library/react'
import { applyMessage, createStatsStore, DesktopDataProvider, emptyStats, useStats, useSystem } from './useStats'
import { createMockApi } from '../api/mock'
import type { Api, Sample, StatsMessage } from '../api'

const s = (t: number, cpu = 10): Sample => ({
  t, cpu, memUsed: 1, memCache: 1, memTotal: 4, netRx: 0, netTx: 0, tempC: 40, disks: [],
})

describe('applyMessage', () => {
  it('takes a snapshot whole, busiest processes first', () => {
    const next = applyMessage(emptyStats, {
      type: 'snapshot', history: { '1h': [s(1), s(2)], '24h': [s(0)] }, units: [],
      procs: [{ pid: 1, name: 'a', user: 'u', cpu: 1, mem: 1 }, { pid: 2, name: 'b', user: 'u', cpu: 9, mem: 1 }],
    })
    expect(next.latest?.t).toBe(2)
    expect(next.procs.map((p) => p.pid)).toEqual([2, 1])
  })

  it('appends samples, trims the hour, and adds to the day once a minute', () => {
    let st = applyMessage(emptyStats, {
      type: 'snapshot', history: { '1h': Array.from({ length: 1800 }, (_, i) => s(i)), '24h': [s(0)] }, units: [], procs: [],
    })
    st = applyMessage(st, { type: 'sample', sample: s(30_000) })
    expect(st.history['1h']).toHaveLength(1800)
    expect(st.history['1h'].at(-1)?.t).toBe(30_000)
    expect(st.history['24h']).toHaveLength(1)
    st = applyMessage(st, {
      type: 'sample', sample: s(61_000), units: [{ name: 'a', state: 'active', mem: 1, since: 1 }],
      procs: [{ pid: 3, name: 'c', user: 'u', cpu: 1, mem: 1 }],
    })
    expect(st.history['24h']).toHaveLength(2)
    expect(st.units).toHaveLength(1)
    expect(st.procs).toHaveLength(1)
  })

  it('caps the day at 1440 samples', () => {
    const day = Array.from({ length: 1440 }, (_, i) => s(i * 60_000))
    let st = applyMessage(emptyStats, { type: 'snapshot', history: { '1h': [], '24h': day }, units: [], procs: [] })
    st = applyMessage(st, { type: 'sample', sample: s(1440 * 60_000) })
    expect(st.history['24h']).toHaveLength(1440)
  })
})

describe('stats store', () => {
  it('notifies subscribers and stops the stream', () => {
    let send: (m: StatsMessage) => void = () => {}
    const stop = vi.fn()
    const store = createStatsStore({ stats: (cb: (m: StatsMessage) => void) => ((send = cb), stop) } as unknown as Api)
    const listener = vi.fn()
    const unsubscribe = store.subscribe(listener)
    const close = store.start()
    send({ type: 'sample', sample: s(5) })
    expect(store.get().latest?.t).toBe(5)
    expect(listener).toHaveBeenCalledTimes(1)
    unsubscribe()
    send({ type: 'sample', sample: s(6) })
    expect(listener).toHaveBeenCalledTimes(1)
    close()
    expect(stop).toHaveBeenCalled()
  })
})

function Probe() {
  const t = useStats((st) => st.latest?.t ?? 0)
  const host = useSystem()?.hostname ?? 'none'
  return <p>{`${host} ${t > 0 ? 'live' : 'idle'}`}</p>
}

describe('DesktopDataProvider', () => {
  it('provides live stats and the system facts', async () => {
    render(<DesktopDataProvider api={createMockApi()}><Probe /></DesktopDataProvider>)
    expect(await screen.findByText('kura-nuc live')).toBeInTheDocument()
  })

  it('keeps going without system facts', async () => {
    const api = { ...createMockApi(), system: () => Promise.reject(new Error('down')) }
    render(<DesktopDataProvider api={api}><Probe /></DesktopDataProvider>)
    await act(async () => {})
    expect(screen.getByText('none live')).toBeInTheDocument()
  })

  it('refuses to work outside the provider', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    expect(() => render(<Probe />)).toThrow(/DesktopDataProvider/)
    vi.restoreAllMocks()
  })
})
