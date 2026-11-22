/**
 * The desktop's state: windows, the viewport, each app's section, and the
 * launcher. The window actions are one stable object, so memoized windows
 * re-render only when their own state changes (dragging one window does not
 * re-render the others).
 */
import { useEffect, useMemo, useReducer, useRef, useState } from 'react'
import type { Prefs } from '../api'
import { APP_BY_ID } from '../apps/registry'
import { boundsFor, type Bounds } from './layout'
import { focusedWindow, initialWindows, windowsReducer } from './windows'

function useBounds(): Bounds {
  const [bounds, setBounds] = useState(() => boundsFor(window.innerWidth, window.innerHeight))
  useEffect(() => {
    const onResize = () => setBounds(boundsFor(window.innerWidth, window.innerHeight))
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])
  return bounds
}

export interface WindowActions {
  open(app: string, view?: string): void
  focus(app: string): void
  close(app: string): void
  minimize(app: string): void
  zoom(app: string): void
  move(app: string, x: number, y: number): void
  resize(app: string, w: number, h: number): void
  /** A drag or resize ended: save the window's geometry. */
  settle(app: string): void
  setView(app: string, view: string): void
}

export function useDesktop(prefs: Prefs, onPrefs: (p: Partial<Prefs>) => void) {
  const bounds = useBounds()
  const [state, dispatch] = useReducer(windowsReducer, initialWindows)
  const [views, setViews] = useState<Record<string, string>>({})
  const [launcher, setLauncher] = useState(false)

  // The actions read the latest values through a ref, so the object itself never changes.
  const latest = useRef({ bounds, state, prefs, onPrefs })
  useEffect(() => {
    latest.current = { bounds, state, prefs, onPrefs }
  })

  const actions = useMemo<WindowActions>(() => {
    const setView = (app: string, view: string) => setViews((v) => ({ ...v, [app]: view }))
    const settle = (app: string) => {
      const { state: s, prefs: p, onPrefs: save } = latest.current
      const w = s.windows[app]
      if (!w) return
      const g = w.maximized && w.restore ? w.restore : { x: w.x, y: w.y, w: w.w, h: w.h }
      save({ windows: { ...p.windows, [app]: g } })
    }
    return {
      open(app, view) {
        const def = APP_BY_ID[app]
        if (!def) return
        const { bounds: b, prefs: p } = latest.current
        dispatch({ type: 'open', app, size: def.size, bounds: b, saved: p.windows[app] })
        if (view) setView(app, view)
      },
      focus: (app) => dispatch({ type: 'focus', app }),
      close(app) {
        settle(app)
        dispatch({ type: 'close', app })
      },
      minimize: (app) => dispatch({ type: 'minimize', app }),
      zoom: (app) => dispatch({ type: 'toggleMaximize', app, bounds: latest.current.bounds }),
      move: (app, x, y) => dispatch({ type: 'move', app, x, y, bounds: latest.current.bounds }),
      resize: (app, w, h) => dispatch({ type: 'resize', app, w, h }),
      settle,
      setView,
    }
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // An app that takes the keyboard for itself (data-keys="app": the terminal, where
      // Ctrl K cuts to the end of the line) keeps Ctrl K; ⌘K still opens the launcher.
      const keptByApp = e.target instanceof Element && e.target.closest('[data-keys="app"]') !== null
      if ((e.metaKey || (e.ctrlKey && !keptByApp)) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setLauncher((v) => !v)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  return { bounds, state, focused: focusedWindow(state), views, actions, launcher, setLauncher }
}
