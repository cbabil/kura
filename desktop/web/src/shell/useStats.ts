/**
 * The live stats stream as a small store, opened once by the desktop
 * (DesktopData.ts). Only the components that show stats subscribe (Activity
 * Monitor, the menu bar's status, the Console's unit list), so a sample
 * every 2 s does not re-render the whole desktop.
 * The server sends the 1 h and 24 h history in the snapshot; the 24 h series
 * gains one point a minute.
 */
import { DAY_POINTS, DAY_STEP_MS, HOUR_POINTS, type Api, type Proc, type Range, type Sample, type StatsMessage, type Unit } from '../api'

export interface Stats {
  latest: Sample | null
  history: Record<Range, Sample[]>
  units: Unit[]
  /** Busiest first. */
  procs: Proc[]
}

export const emptyStats: Stats = { latest: null, history: { '1h': [], '24h': [] }, units: [], procs: [] }


const keepLast = <T,>(list: T[], n: number) => (list.length > n ? list.slice(list.length - n) : list)
const busiestFirst = (procs: Proc[]) => [...procs].sort((a, b) => b.cpu - a.cpu)

export function applyMessage(state: Stats, m: StatsMessage): Stats {
  if (m.type === 'snapshot') {
    return { latest: m.history['1h'].at(-1) ?? null, history: m.history, units: m.units, procs: busiestFirst(m.procs) }
  }
  const day = state.history['24h']
  const lastDay = day.at(-1)
  const addToDay = !lastDay || m.sample.t - lastDay.t >= DAY_STEP_MS
  return {
    latest: m.sample,
    history: {
      '1h': keepLast([...state.history['1h'], m.sample], HOUR_POINTS),
      '24h': addToDay ? keepLast([...day, m.sample], DAY_POINTS) : day,
    },
    units: m.units ?? state.units,
    procs: m.procs ? busiestFirst(m.procs) : state.procs,
  }
}

export interface StatsStore {
  get(): Stats
  subscribe(listener: () => void): () => void
  /** Opens the stream; returns a function that closes it. */
  start(): () => void
}

export function createStatsStore(api: Api): StatsStore {
  let state = emptyStats
  const listeners = new Set<() => void>()
  return {
    get: () => state,
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    start: () =>
      api.stats((m) => {
        state = applyMessage(state, m)
        listeners.forEach((l) => l())
      }),
  }
}
