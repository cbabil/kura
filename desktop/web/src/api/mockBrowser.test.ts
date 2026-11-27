import { MOCK_COLOURS, MOCK_SCREEN, MockVncChannel } from './mockBrowser'

/** Collects what the mock server sends, once its timers have run. */
async function talk(channel: MockVncChannel, ...messages: number[][]): Promise<Uint8Array[]> {
  const got: Uint8Array[] = []
  channel.onmessage = (e) => got.push(new Uint8Array(e.data as ArrayBuffer))
  await vi.runAllTimersAsync()
  for (const m of messages) {
    channel.send(Uint8Array.from(m))
    await vi.runAllTimersAsync()
  }
  return got
}

describe('the mock Browser’s VNC server', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('greets, asks no password and draws a page on a full request', async () => {
    const channel = new MockVncChannel()
    const opened = vi.fn()
    channel.onopen = opened
    const version = [...new TextEncoder().encode('RFB 003.008\n')]
    const got = await talk(channel, version, [1], [1], [3, 0, 0, 0, 0, 0, 4, 0, 2, 128], [3, 1, 0, 0, 0, 0, 4, 0, 2, 128])
    expect(opened).toHaveBeenCalled()
    expect(new TextDecoder().decode(got[0])).toBe('RFB 003.008\n')
    expect([...got[1]]).toEqual([1, 1])
    expect([...got[2]]).toEqual([0, 0, 0, 0])
    const init = got[3]
    expect([(init[0] << 8) | init[1], (init[2] << 8) | init[3]]).toEqual([MOCK_SCREEN.width, MOCK_SCREEN.height])
    expect(new TextDecoder().decode(init.slice(24))).toBe('Kura Browser (mock)')
    // one update for the full request, none for the incremental one
    expect(got).toHaveLength(5)
    const update = got[4]
    expect([update[0], (update[2] << 8) | update[3]]).toEqual([0, 7])
    expect([...update.slice(16, 19)]).toEqual([...MOCK_COLOURS.tabs])
  })

  it('takes messages split across sends, keeps what was pasted, and closes on nonsense', async () => {
    const channel = new MockVncChannel()
    const closed = vi.fn()
    channel.onclose = closed
    const version = [...new TextEncoder().encode('RFB 003.008\n')]
    const text = [...new TextEncoder().encode('hello')]
    await talk(channel, version.slice(0, 5), version.slice(5), [1], [1],
      [2, 0, 0, 1], [0, 0, 0, 0], [4, 1, 0, 0, 0, 0, 0, 97], [5, 1, 0, 10, 0, 10], [6, 0, 0, 0, 0, 0, 0, 5], text)
    expect(channel.pasted).toEqual(['hello'])
    expect(closed).not.toHaveBeenCalled()
    await talk(channel, [99])
    expect(closed).toHaveBeenCalled()
    expect(channel.readyState).toBe(3)
    channel.close()
    await vi.runAllTimersAsync()
    expect(closed).toHaveBeenCalledTimes(1)
  })
})
