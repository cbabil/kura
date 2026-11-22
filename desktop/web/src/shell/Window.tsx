/**
 * One app window: a title bar to drag (double-click to zoom), close /
 * minimize / zoom buttons, resize handles, a slot for the app's own title-bar
 * controls, and the app's body (or what is coming, for apps not built yet).
 * In compact mode (phone width) it fills the desktop and cannot be moved.
 * Memoized: it re-renders only when its own window state changes.
 */
import { memo, useMemo, useRef, useState, type PointerEvent } from 'react'
import { Box } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { appText } from '../apps/registry'
import type { AppDef, AppProps } from '../apps/types'
import { useI18n } from '../i18n'
import { colors } from '../theme'
import { TITLE_BAR, type Bounds } from './layout'
import { ComingSoon } from './Panels'
import type { WindowActions } from './useDesktop'
import type { Win } from './windows'
import { ToolbarSlot } from './WindowToolbar'

interface Props {
  win: Win
  def: AppDef
  focused: boolean
  bounds: Bounds
  z: number
  view: string
  actions: WindowActions
}

type Drag = { kind: 'move' | 'right' | 'bottom' | 'corner'; px: number; py: number; win: Win }

const LIGHTS = [
  { label: 'window.close', color: colors.error, act: 'close' },
  { label: 'window.minimize', color: colors.warning, act: 'minimize' },
  { label: 'window.zoom', color: colors.success, act: 'zoom' },
] as const

const HANDLES = [
  { kind: 'right', sx: { top: TITLE_BAR, right: 0, bottom: 12, width: 6, cursor: 'ew-resize' } },
  { kind: 'bottom', sx: { left: 0, right: 12, bottom: 0, height: 6, cursor: 'ns-resize' } },
  { kind: 'corner', sx: { right: 0, bottom: 0, width: 14, height: 14, cursor: 'nwse-resize' } },
] as const

function WindowFrame({ win, def, focused, bounds, z, view, actions }: Props) {
  const k = useTheme().kura
  const { t } = useI18n()
  const { app } = win
  const title = appText(t, app, 'name')
  const { compact } = bounds
  const drag = useRef<Drag | null>(null)
  const [slot, setSlot] = useState<HTMLElement | null>(null)
  const { minimized } = win
  const body = useMemo<AppProps>(
    () => ({ view, setView: (v) => actions.setView(app, v), compact, minimized }),
    [view, actions, app, compact, minimized],
  )

  /** Starts a move or resize; the handle says which in data-drag. */
  const start = (e: PointerEvent<HTMLElement>) => {
    if (compact || e.button !== 0) return
    e.currentTarget.setPointerCapture(e.pointerId)
    drag.current = { kind: e.currentTarget.dataset.drag as Drag['kind'], px: e.clientX, py: e.clientY, win }
  }
  const follow = (e: PointerEvent) => {
    const d = drag.current
    if (!d) return
    const dx = e.clientX - d.px
    const dy = e.clientY - d.py
    if (d.kind === 'move') actions.move(app, d.win.x + dx, d.win.y + dy)
    else actions.resize(app, d.win.w + (d.kind === 'bottom' ? 0 : dx), d.win.h + (d.kind === 'right' ? 0 : dy))
  }
  const end = () => {
    if (drag.current) actions.settle(app)
    drag.current = null
  }
  const handle = { onPointerDown: start, onPointerMove: follow, onPointerUp: end, onPointerCancel: end }

  const frame = compact
    ? { left: 0, right: 0, top: bounds.top, bottom: bounds.bottom, borderRadius: 0 }
    : { left: win.x, top: win.y, width: win.w, height: win.h, borderRadius: win.maximized ? 0 : '12px' }
  const Body = def.Body

  return (
    <Box role="dialog" aria-label={title} data-focused={focused}
      onPointerDownCapture={() => !focused && actions.focus(app)}
      sx={{
        position: 'absolute', ...frame, zIndex: z, display: win.minimized ? 'none' : 'flex', flexDirection: 'column',
        bgcolor: 'background.paper', border: `1px solid ${k.edge}`, boxShadow: k.shadow, overflow: 'hidden',
      }}>
      <Box data-drag="move" {...handle} onDoubleClick={() => !compact && actions.zoom(app)}
        sx={{
          height: TITLE_BAR, flexShrink: 0, display: 'flex', alignItems: 'center', px: '14px', gap: 1, position: 'relative',
          bgcolor: k.chrome, borderBottom: 1, borderColor: 'divider', cursor: compact ? 'default' : 'grab',
          userSelect: 'none', touchAction: 'none',
        }}>
        <Box sx={{ display: 'flex', gap: 1, zIndex: 1 }} onPointerDown={(e) => e.stopPropagation()}>
          {LIGHTS.map((l) => (
            <Box component="button" key={l.act} aria-label={t(l.label)} onClick={() => actions[l.act](app)}
              sx={{ width: 12, height: 12, p: 0, border: 0, borderRadius: '50%', cursor: 'pointer',
                bgcolor: focused ? l.color : k.edge, '&:hover': { bgcolor: l.color } }} />
          ))}
        </Box>
        <Box sx={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontWeight: 600, fontSize: 13,
          pointerEvents: 'none', color: focused ? 'text.primary' : 'text.secondary' }}>
          {title}
        </Box>
        <Box ref={setSlot} sx={{ ml: 'auto', zIndex: 1 }} onPointerDown={(e) => e.stopPropagation()} />
      </Box>
      <ToolbarSlot.Provider value={slot}>
        <Box sx={{ flex: 1, minHeight: 0, display: 'flex' }}>{Body ? <Body {...body} /> : <ComingSoon app={def} />}</Box>
      </ToolbarSlot.Provider>
      {!compact && !win.maximized && HANDLES.map((h) => (
        <Box key={h.kind} aria-hidden data-testid={`resize-${h.kind}`} data-drag={h.kind} {...handle}
          sx={{ position: 'absolute', touchAction: 'none', ...h.sx }} />
      ))}
    </Box>
  )
}

export const Window = memo(WindowFrame)
