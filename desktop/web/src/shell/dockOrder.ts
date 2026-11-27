/** Pure helpers for the dock's pinned apps, kept in prefs.dock. */

import { DOCKABLE } from '../apps/registry'

export const DEFAULT_DOCK = DOCKABLE

/** The slot under the pointer at `x`: how many of the other icons' centres lie before it. */
export function slotAt(centres: readonly number[], x: number): number {
  return centres.filter((c) => c < x).length
}

/** Puts `item` at `slot` of the list without it: a move when it was pinned, a new pin when not. */
export function placeAt(list: string[], item: string, slot: number): string[] {
  const rest = unpin(list, item)
  return [...rest.slice(0, slot), item, ...rest.slice(slot)]
}

export function unpin(list: string[], item: string): string[] {
  return list.filter((x) => x !== item)
}

/** The saved order, or the default when nothing is saved. */
const savedOrDefault = (saved: string[] | undefined): string[] => (saved && saved.length > 0 ? saved : DEFAULT_DOCK)

/** Drops unknown and repeated ids; saved prefs may predate an app's removal. */
export function normalizeDock(saved: string[] | undefined, known: readonly string[] = DOCKABLE): string[] {
  return [...new Set(savedOrDefault(saved))].filter((id) => known.includes(id))
}

/**
 * A new dock order, with the pins it could not show kept at its end: an app
 * this server does not offer, or not yet known to (its facts still loading).
 */
export function keepHidden(dock: string[], saved: string[] | undefined, shown: readonly string[]): string[] {
  return [...dock, ...savedOrDefault(saved).filter((id) => !shown.includes(id) && !dock.includes(id))]
}
