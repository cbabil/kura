import { act, renderHook } from '@testing-library/react'
import { useAwake, usePolled, useSettle } from './usePolled'

describe('usePolled', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('keeps what is on screen when the answer has not changed', async () => {
    const load = vi.fn(() => Promise.resolve([{ id: 1 }]))
    const { result } = renderHook(() => usePolled(load, 1000))
    await act(() => vi.advanceTimersByTimeAsync(0))
    const first = result.current.data
    await act(() => vi.advanceTimersByTimeAsync(1000))
    expect(load).toHaveBeenCalledTimes(2)
    expect(result.current.data).toBe(first)
  })

  it('drops an answer that arrives after a newer one', async () => {
    const answers: ((v: string) => void)[] = []
    const load = vi.fn(() => new Promise<string>((resolve) => answers.push(resolve)))
    const { result } = renderHook(() => usePolled(load, 1000))
    await act(() => vi.advanceTimersByTimeAsync(1000))
    expect(answers).toHaveLength(2)
    await act(async () => answers[1]('new'))
    await act(async () => answers[0]('old'))
    expect(result.current.data).toBe('new')
  })

  it('asks nothing while asleep, and at once on waking', async () => {
    const load = vi.fn(() => Promise.resolve(1))
    const { rerender } = renderHook(({ awake }) => usePolled(load, 1000, awake), { initialProps: { awake: false } })
    await act(() => vi.advanceTimersByTimeAsync(5000))
    expect(load).not.toHaveBeenCalled()
    rerender({ awake: true })
    expect(load).toHaveBeenCalledTimes(1)
  })

  it('marks a failure and keeps the last answer', async () => {
    let fail = false
    const load = () => (fail ? Promise.reject(new Error('down')) : Promise.resolve('ok'))
    const { result } = renderHook(() => usePolled(load, 1000))
    await act(() => vi.advanceTimersByTimeAsync(0))
    fail = true
    await act(async () => result.current.reload())
    expect(result.current).toMatchObject({ data: 'ok', failed: true })
  })
})

describe('useAwake', () => {
  it('is false for a minimised window or a hidden tab', () => {
    const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false)
    const { result, rerender } = renderHook(({ min }) => useAwake(min), { initialProps: { min: false } })
    expect(result.current).toBe(true)
    rerender({ min: true })
    expect(result.current).toBe(false)
    rerender({ min: false })
    hidden.mockReturnValue(true)
    act(() => void document.dispatchEvent(new Event('visibilitychange')))
    expect(result.current).toBe(false)
    hidden.mockRestore()
  })
})

describe('useSettle', () => {
  it('ends a wait that no answer ended', () => {
    vi.useFakeTimers()
    const clear = vi.fn()
    const { rerender } = renderHook(({ waiting }) => useSettle(waiting, clear, 5000), { initialProps: { waiting: false } })
    vi.advanceTimersByTime(6000)
    expect(clear).not.toHaveBeenCalled()
    rerender({ waiting: true })
    vi.advanceTimersByTime(4000)
    expect(clear).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1500)
    expect(clear).toHaveBeenCalledTimes(1)
    // An answer came first: nothing left to end.
    rerender({ waiting: false })
    rerender({ waiting: true })
    rerender({ waiting: false })
    vi.advanceTimersByTime(6000)
    expect(clear).toHaveBeenCalledTimes(1)
    vi.useRealTimers()
  })
})
