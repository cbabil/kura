/**
 * What the signed-in desktop hands everything inside it: the server, the
 * user, the system facts, the live stats (opened once, see useStats.ts) and
 * whether an update waits (asked now and then, and when something changed it).
 */
import { createContext, createElement, useCallback, useContext, useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from 'react'
import type { Api, SystemInfo, UpdateStatus, User } from '../api'
import { createStatsStore, type Stats, type StatsStore } from './useStats'

interface DesktopData {
  api: Api
  user: User
  store: StatsStore
  system: SystemInfo | null
  updates: UpdateStatus | null
  /** Asks the server again whether an update waits. */
  refreshUpdates(): void
  noteUpdates(status: UpdateStatus): void
}

/** How often the desktop asks whether an update waits (the device itself looks once a day). */
const UPDATES_MS = 10 * 60_000

const DataContext = createContext<DesktopData | null>(null)

/**
 * Opens the stats stream, fetches the system facts and asks now and then
 * whether an update waits, for everything inside it, and hands the apps
 * the API and the signed-in user.
 */
export function DesktopDataProvider({ api, user, children }: { api: Api; user: User; children: ReactNode }) {
  const store = useMemo(() => createStatsStore(api), [api])
  const [system, setSystem] = useState<SystemInfo | null>(null)
  useEffect(() => store.start(), [store])
  useEffect(() => {
    api.system().then(setSystem, () => setSystem(null))
  }, [api])
  const [updates, setUpdates] = useState<UpdateStatus | null>(null)
  const refreshUpdates = useCallback(() => {
    api.updates().then(setUpdates, () => {}) // the next turn asks again
  }, [api])
  useEffect(() => {
    refreshUpdates()
    const timer = setInterval(refreshUpdates, UPDATES_MS)
    return () => clearInterval(timer)
  }, [refreshUpdates])
  const value = useMemo(
    () => ({ api, user, store, system, updates, refreshUpdates, noteUpdates: setUpdates }),
    [api, user, store, system, updates, refreshUpdates],
  )
  return createElement(DataContext.Provider, { value }, children)
}

function useData(): DesktopData {
  const data = useContext(DataContext)
  if (!data) throw new Error('useStats, useSystem, useApi and useUser need a DesktopDataProvider')
  return data
}

/** Subscribes to the stats; with a selector, re-renders only when the selected value changes. */
export function useStats(): Stats
export function useStats<T>(select: (s: Stats) => T): T
export function useStats<T>(select?: (s: Stats) => T): T | Stats {
  const { store } = useData()
  return useSyncExternalStore(store.subscribe, () => (select ? select(store.get()) : store.get()))
}

export const useSystem = () => useData().system
/** The server, for apps that ask it things themselves (Containers, Console, Terminal). */
export const useApi = () => useData().api
/** The signed-in user; `admin` decides what the apps offer. */
export const useUser = () => useData().user
/**
 * Whether an update waits or a restart is due, as last heard. `refresh`
 * asks the server again; `note` takes an answer a window already has.
 */
export function useUpdates(): { status: UpdateStatus | null; refresh(): void; note(status: UpdateStatus): void } {
  const { updates, refreshUpdates, noteUpdates } = useData()
  return { status: updates, refresh: refreshUpdates, note: noteUpdates }
}
