/**
 * Asks the server again every few seconds while a window shows the answer
 * (containers, their logs). The last good answer stays on screen when a
 * later request fails, an unchanged answer changes nothing on screen, and
 * nothing is asked while nobody can see it.
 */
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react'

export interface Polled<T> {
  /** null until the first answer. */
  data: T | null
  /** The latest request failed. */
  failed: boolean
  /** Asks now, without waiting for the next turn. */
  reload(): void
}

const onVisibility = (changed: () => void) => {
  document.addEventListener('visibilitychange', changed)
  return () => document.removeEventListener('visibilitychange', changed)
}

/** True while the window can be seen: not minimised, and the browser tab in front. */
export function useAwake(minimized: boolean): boolean {
  const hidden = useSyncExternalStore(onVisibility, () => document.hidden)
  return !minimized && !hidden
}

/**
 * `load` must keep its identity between renders (useCallback), or every
 * render starts over. While `awake` is false nothing is asked; asking
 * starts again, at once, when it turns true.
 */
export function usePolled<T>(load: () => Promise<T>, everyMs: number, awake = true): Polled<T> {
  const [state, setState] = useState<{ data: T | null; failed: boolean }>({ data: null, failed: false })
  const ask = useRef<() => void>(() => {})

  useEffect(() => {
    if (!awake) return
    let live = true
    let asked = 0
    let shown = 0
    const run = () => {
      const turn = ++asked
      load().then(
        (data) => {
          // An answer that comes after a later one's is out of date.
          if (!live || turn < shown) return
          shown = turn
          setState((s) => (!s.failed && JSON.stringify(s.data) === JSON.stringify(data) ? s : { data, failed: false }))
        },
        () => live && setState((s) => (s.failed ? s : { ...s, failed: true })),
      )
    }
    ask.current = run
    run()
    const timer = setInterval(run, everyMs)
    return () => {
      live = false
      clearInterval(timer)
    }
  }, [load, everyMs, awake])

  const reload = useCallback(() => ask.current(), [])
  return { ...state, reload }
}

/**
 * Ends a wait by itself: a window that waits for the server's next
 * different answer (after starting a job) would wait for ever when that
 * answer equals the last one, which changes nothing on screen. `clear` is
 * called once `ms` have passed with `waiting` still true.
 */
export function useSettle(waiting: boolean, clear: () => void, ms: number): void {
  useEffect(() => {
    if (!waiting) return
    const timer = setTimeout(clear, ms)
    return () => clearTimeout(timer)
  }, [waiting, clear, ms])
}
