/**
 * The window manager as a pure reducer: one window per app, `order` is the
 * stacking order (last = top), and geometry is kept inside the desktop so a
 * title bar can always be grabbed. The Desktop component owns the state.
 */
import type { WindowGeometry } from '../api'
import { TITLE_BAR, type Bounds } from './layout'

export type { Bounds }

export interface Win extends WindowGeometry {
  app: string
  minimized: boolean
  maximized: boolean
  /** Geometry before maximizing, restored on the second toggle. */
  restore?: WindowGeometry
}

export interface WindowsState {
  windows: Record<string, Win>
  order: string[]
}

export type WindowAction =
  | { type: 'open'; app: string; size: { w: number; h: number }; bounds: Bounds; saved?: WindowGeometry }
  | { type: 'focus' | 'close' | 'minimize'; app: string }
  | { type: 'move'; app: string; x: number; y: number; bounds: Bounds }
  | { type: 'resize'; app: string; w: number; h: number }
  | { type: 'toggleMaximize'; app: string; bounds: Bounds }

export const initialWindows: WindowsState = { windows: {}, order: [] }

export const MIN_W = 420
export const MIN_H = 280
/** How much of a window must stay on screen horizontally. */
const GRAB = 120
const CASCADE = 28

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi)

function placeOnScreen(g: WindowGeometry, b: Bounds): WindowGeometry {
  const w = clamp(g.w, MIN_W, b.width)
  const h = clamp(g.h, MIN_H, b.height - b.top)
  return { w, h, x: clamp(g.x, GRAB - w, b.width - GRAB), y: clamp(g.y, b.top, b.height - TITLE_BAR) }
}

/** Fully inside the desktop: for windows opening, possibly from a saved layout on a bigger screen. */
function fitInside(g: WindowGeometry, b: Bounds): WindowGeometry {
  const { w, h } = placeOnScreen(g, b)
  return { w, h, x: clamp(g.x, 0, b.width - w), y: clamp(g.y, b.top, Math.max(b.top, b.height - b.bottom - h)) }
}

function raise(order: string[], app: string): string[] {
  return [...order.filter((a) => a !== app), app]
}

function update(state: WindowsState, app: string, change: Partial<Win>): WindowsState {
  return { ...state, windows: { ...state.windows, [app]: { ...state.windows[app], ...change } } }
}

function openWindow(state: WindowsState, a: Extract<WindowAction, { type: 'open' }>): WindowsState {
  if (state.windows[a.app]) {
    return { ...update(state, a.app, { minimized: false }), order: raise(state.order, a.app) }
  }
  const step = state.order.length * CASCADE
  const fresh = { x: 80 + step, y: a.bounds.top + 30 + step, ...a.size }
  const geometry = fitInside(a.saved ?? fresh, a.bounds)
  const win: Win = { app: a.app, ...geometry, minimized: false, maximized: false }
  return { windows: { ...state.windows, [a.app]: win }, order: [...state.order, a.app] }
}

function toggleMaximize(state: WindowsState, app: string, b: Bounds): WindowsState {
  const w = state.windows[app]
  if (w.maximized && w.restore) return update(state, app, { ...w.restore, maximized: false, restore: undefined })
  const full = { x: 0, y: b.top, w: b.width, h: b.height - b.top - b.bottom }
  return update(state, app, { ...full, maximized: true, restore: { x: w.x, y: w.y, w: w.w, h: w.h } })
}

export function windowsReducer(state: WindowsState, action: WindowAction): WindowsState {
  if (action.type === 'open') return openWindow(state, action)
  if (!state.windows[action.app]) return state
  const { app } = action
  switch (action.type) {
    case 'focus':
      return { ...update(state, app, { minimized: false }), order: raise(state.order, app) }
    case 'close': {
      const windows = Object.fromEntries(Object.entries(state.windows).filter(([k]) => k !== app))
      return { windows, order: state.order.filter((a) => a !== app) }
    }
    case 'minimize':
      return update(state, app, { minimized: true })
    case 'move': {
      const w = state.windows[app]
      const placed = placeOnScreen({ ...w, x: action.x, y: action.y }, action.bounds)
      return update(state, app, { x: placed.x, y: placed.y, maximized: false, restore: undefined })
    }
    case 'resize':
      return update(state, app, { w: Math.max(action.w, MIN_W), h: Math.max(action.h, MIN_H), maximized: false })
    case 'toggleMaximize':
      return toggleMaximize(state, app, action.bounds)
  }
}

/** The topmost window that is not minimized: the one with keyboard focus. */
export function focusedWindow(state: WindowsState): Win | null {
  for (let i = state.order.length - 1; i >= 0; i--) {
    const w = state.windows[state.order[i]]
    if (!w.minimized) return w
  }
  return null
}
