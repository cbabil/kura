/** Pure helpers for the dock's pinned apps, kept in prefs.dock. */

import { DOCKABLE } from '../apps/registry'

export const DEFAULT_DOCK = DOCKABLE

/** Moves `item` before `before`, or to the end when `before` is null. */
export function moveItem(list: string[], item: string, before: string | null): string[] {
  if (!list.includes(item) || item === before) return list
  const rest = list.filter((x) => x !== item)
  const at = before === null ? rest.length : rest.indexOf(before)
  return at < 0 ? list : [...rest.slice(0, at), item, ...rest.slice(at)]
}

export function unpin(list: string[], item: string): string[] {
  return list.filter((x) => x !== item)
}

/** Drops unknown and repeated ids; saved prefs may predate an app's removal. */
export function normalizeDock(saved: string[] | undefined, known: readonly string[] = DOCKABLE): string[] {
  const source = saved && saved.length > 0 ? saved : DEFAULT_DOCK
  return [...new Set(source)].filter((id) => known.includes(id))
}

/**
 * A new dock order, with the pins it could not show kept at its end: an app
 * this server does not offer, or not yet known to (its facts still loading).
 */
export function keepHidden(dock: string[], saved: string[] | undefined, shown: readonly string[]): string[] {
  const before = saved && saved.length > 0 ? saved : DEFAULT_DOCK
  return [...dock, ...before.filter((id) => !shown.includes(id) && !dock.includes(id))]
}
