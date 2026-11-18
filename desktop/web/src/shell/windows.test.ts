import { initialWindows, windowsReducer, focusedWindow, type WindowsState, type Bounds } from './windows'

const bounds: Bounds = { width: 1440, height: 900, top: 30, bottom: 90, compact: false }
const size = { w: 800, h: 500 }

function open(state: WindowsState, app: string) {
  return windowsReducer(state, { type: 'open', app, size, bounds })
}

describe('windowsReducer', () => {
  it('opens a window cascaded inside the desktop, focused and on top', () => {
    const s1 = open(initialWindows, 'activity')
    const s2 = open(s1, 'files')
    expect(s2.order).toEqual(['activity', 'files'])
    expect(focusedWindow(s2)?.app).toBe('files')
    const a = s2.windows.activity
    const f = s2.windows.files
    expect(f.x).toBeGreaterThan(a.x)
    expect(a.y).toBeGreaterThanOrEqual(bounds.top)
  })

  it('opens at a saved geometry, kept on screen', () => {
    const s = windowsReducer(initialWindows, {
      type: 'open', app: 'activity', size, bounds, saved: { x: 5000, y: -40, w: 3000, h: 300 },
    })
    const w = s.windows.activity
    expect(w.w).toBe(bounds.width)
    expect(w.y).toBe(bounds.top)
    expect(w.x).toBe(0)
  })

  it('opening an open app focuses it and restores it from the dock', () => {
    let s = open(open(initialWindows, 'activity'), 'files')
    s = windowsReducer(s, { type: 'minimize', app: 'activity' })
    expect(s.windows.activity.minimized).toBe(true)
    s = open(s, 'activity')
    expect(s.windows.activity.minimized).toBe(false)
    expect(s.order.at(-1)).toBe('activity')
  })

  it('focus raises a window; unknown apps are ignored', () => {
    let s = open(open(initialWindows, 'activity'), 'files')
    s = windowsReducer(s, { type: 'focus', app: 'activity' })
    expect(s.order).toEqual(['files', 'activity'])
    expect(windowsReducer(s, { type: 'focus', app: 'nope' })).toBe(s)
    expect(windowsReducer(s, { type: 'close', app: 'nope' })).toBe(s)
  })

  it('moves a window, keeping its title bar reachable', () => {
    let s = open(initialWindows, 'activity')
    s = windowsReducer(s, { type: 'move', app: 'activity', x: 200, y: 300, bounds })
    expect(s.windows.activity).toMatchObject({ x: 200, y: 300 })
    s = windowsReducer(s, { type: 'move', app: 'activity', x: 5000, y: -100, bounds })
    expect(s.windows.activity.x).toBe(bounds.width - 120)
    expect(s.windows.activity.y).toBe(bounds.top)
    s = windowsReducer(s, { type: 'move', app: 'activity', x: -5000, y: 5000, bounds })
    expect(s.windows.activity.x).toBe(120 - 800)
    expect(s.windows.activity.y).toBe(bounds.height - 40)
  })

  it('resizes with a minimum size', () => {
    let s = open(initialWindows, 'activity')
    s = windowsReducer(s, { type: 'resize', app: 'activity', w: 100, h: 50 })
    expect(s.windows.activity).toMatchObject({ w: 420, h: 280 })
    s = windowsReducer(s, { type: 'resize', app: 'activity', w: 1000, h: 640 })
    expect(s.windows.activity).toMatchObject({ w: 1000, h: 640 })
  })

  it('maximizes to the free desktop area and back', () => {
    let s = open(initialWindows, 'activity')
    const before = { ...s.windows.activity }
    s = windowsReducer(s, { type: 'toggleMaximize', app: 'activity', bounds })
    expect(s.windows.activity).toMatchObject({
      maximized: true, x: 0, y: bounds.top, w: bounds.width, h: bounds.height - bounds.top - bounds.bottom,
    })
    s = windowsReducer(s, { type: 'toggleMaximize', app: 'activity', bounds })
    expect(s.windows.activity).toMatchObject({ maximized: false, x: before.x, y: before.y, w: before.w, h: before.h })
  })

  it('minimizing moves focus to the next visible window; closing removes it', () => {
    let s = open(open(initialWindows, 'activity'), 'files')
    s = windowsReducer(s, { type: 'minimize', app: 'files' })
    expect(focusedWindow(s)?.app).toBe('activity')
    s = windowsReducer(s, { type: 'minimize', app: 'activity' })
    expect(focusedWindow(s)).toBeNull()
    s = windowsReducer(s, { type: 'close', app: 'files' })
    expect(s.order).toEqual(['activity'])
    expect(s.windows.files).toBeUndefined()
  })
})
