/**
 * The dock: pinned apps in the owner's order, then running apps that are not
 * pinned, a separator, minimised windows, and the apps fixed at the end
 * (Trash). A dot marks running apps; hovering names the app. Drag to
 * reorder, drop a running app among the kept ones to keep it, pull a kept
 * one up and away to remove it (useDockDrag); right-click to keep or remove.
 * No magnification and no bounce.
 */
import { useState, type MouseEvent, type PointerEvent } from 'react'
import { Box, Tooltip } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { AppIcon } from '../icons/AppIcon'
import { appText, DOCK_END } from '../apps/registry'
import { useI18n } from '../i18n'
import { DockMenu } from './DockMenu'
import { unpin } from './dockOrder'
import { useDockDrag, type DockDrag } from './useDockDrag'
import { COMPACT_DOCK_ICON, DOCK_ICON } from './layout'

interface Props {
  pinned: string[]
  running: string[]
  minimized: string[]
  compact: boolean
  onOpen(app: string): void
  /** Closes the app's window (the menu's Quit). */
  onQuit(app: string): void
  onPinnedChange(next: string[]): void
}

interface ItemProps {
  app: string
  size: number
  running: boolean
  minimizedTile?: boolean
  onOpen(app: string): void
  onMenu?(app: string, el: HTMLElement): void
  /** For an icon that can be dragged: the press that may begin a drag. */
  onPress?(app: string, e: PointerEvent<HTMLElement>): void
  /** A kept app: the drag measures these to find where an icon lands. */
  kept?: boolean
}

function MinimizedTile({ app, name, size }: { app: string; name: string; size: number }) {
  const k = useTheme().kura
  return (
    <Box sx={{ width: size, height: size, display: 'grid', placeItems: 'center', position: 'relative' }}>
      <Box sx={{ width: size * 0.84, height: size * 0.62, borderRadius: '5px', bgcolor: 'background.paper',
        border: `1px solid ${k.edge}`, boxShadow: k.shadow }} />
      <Box sx={{ position: 'absolute', right: 2, bottom: 2 }}><AppIcon app={app} name={name} size={size * 0.42} /></Box>
    </Box>
  )
}

function DockItem({ app, size, running, minimizedTile, onOpen, onMenu, onPress, kept }: ItemProps) {
  const { t } = useI18n()
  const name = appText(t, app, 'name')
  return (
    <Tooltip title={name} placement="top" disableInteractive>
      <Box component="button" aria-label={minimizedTile ? t('dock.minimised', { name }) : name} data-running={running}
        data-kept={kept ? app : undefined}
        onClick={() => onOpen(app)}
        onPointerDown={onPress ? (e: PointerEvent<HTMLElement>) => onPress(app, e) : undefined}
        onContextMenu={(e: MouseEvent<HTMLElement>) => {
          e.preventDefault()
          onMenu?.(app, e.currentTarget)
        }}
        sx={{
          position: 'relative', p: 0, border: 0, background: 'none', cursor: 'pointer', width: size, height: size,
          '&::after': running ? {
            content: '""', position: 'absolute', left: '50%', bottom: -5, width: 4, height: 4, ml: '-2px',
            borderRadius: '50%', bgcolor: 'text.primary', opacity: 0.8,
          } : undefined,
        }}>
        {minimizedTile ? <MinimizedTile app={app} name={name} size={size} /> : <AppIcon app={app} name={name} size={size} />}
      </Box>
    </Tooltip>
  )
}

/** The icon under the pointer while it is dragged (placed by useDockDrag), and what letting go there would do. */
function Dragged({ drag, size, floatRef }: { drag: DockDrag; size: number; floatRef(el: HTMLElement | null): void }) {
  const { t } = useI18n()
  const name = appText(t, drag.app, 'name')
  return (
    <Box ref={floatRef} aria-hidden sx={{ position: 'fixed', left: 0, top: 0, zIndex: 2000, pointerEvents: 'none',
      opacity: drag.out ? 0.5 : 1, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <AppIcon app={drag.app} name={name} size={size} />
      {drag.out && (
        <Box sx={{ mt: 0.5, px: 1, py: 0.25, borderRadius: 1, bgcolor: 'background.paper', fontSize: 12, whiteSpace: 'nowrap' }}>
          {t('dock.remove')}
        </Box>
      )}
    </Box>
  )
}

export function Dock({ pinned, running, minimized, compact, onOpen, onQuit, onPinnedChange }: Props) {
  const k = useTheme().kura
  const { t } = useI18n()
  const size = compact ? COMPACT_DOCK_ICON : DOCK_ICON
  const [menu, setMenu] = useState<{ el: HTMLElement; app: string } | null>(null)
  const { drag, begin, dockProps, floatRef } = useDockDrag(pinned, onPinnedChange)
  const extra = running.filter((a) => !pinned.includes(a) && !DOCK_END.includes(a) && a !== drag?.app)
  const openMenu = (app: string, el: HTMLElement) => setMenu({ el, app })
  const keep = (app: string, yes: boolean) => onPinnedChange(yes ? [...unpin(pinned, app), app] : unpin(pinned, app))
  const draggable = (app: string) => ({ app, size, onOpen, onMenu: openMenu, onPress: begin })

  // While dragging, the dragged icon leaves its place and an empty slot opens where it would land.
  const kept = drag ? pinned.filter((a) => a !== drag.app) : pinned
  const keptRow = kept.map((app) => <DockItem key={app} kept running={running.includes(app)} {...draggable(app)} />)
  const slot = drag?.slot ?? null
  const row = slot === null ? keptRow : [
    ...keptRow.slice(0, slot),
    <Box key="dock-gap" data-testid="dock-gap" sx={{ width: size, height: size, flexShrink: 0 }} />,
    ...keptRow.slice(slot),
  ]

  return (
    <>
      <Box component="nav" {...dockProps} aria-label={t('dock.label')}
        sx={{
          position: 'absolute', left: '50%', bottom: compact ? 6 : 10, transform: 'translateX(-50%)', zIndex: 1000,
          display: 'flex', alignItems: 'flex-end', gap: '2px', px: 1, pt: '4px', pb: '8px', borderRadius: '22px',
          bgcolor: k.dock, backdropFilter: 'blur(28px)', border: `1px solid ${k.edge}`, maxWidth: 'calc(100vw - 16px)', overflowX: 'auto',
          userSelect: 'none',
        }}>
        {row}
        {extra.map((app) => <DockItem key={app} running {...draggable(app)} />)}
        <Box aria-hidden sx={{ width: '1px', height: size * 0.84, bgcolor: k.edge, mx: 1, mb: '5px', flexShrink: 0 }} />
        {minimized.map((app) => <DockItem key={`min-${app}`} app={app} size={size} running={false} minimizedTile onOpen={onOpen} />)}
        {DOCK_END.map((app) => <DockItem key={app} app={app} size={size} running={running.includes(app)} onOpen={onOpen} />)}
      </Box>
      <DockMenu menu={menu} kept={menu !== null && pinned.includes(menu.app)} running={menu !== null && running.includes(menu.app)}
        onClose={() => setMenu(null)} onOpen={onOpen} onQuit={onQuit} onKeep={keep} />
      {/* Outside the dock: its transform and scrolling would place and clip it */}
      {drag && <Dragged drag={drag} size={size} floatRef={floatRef} />}
    </>
  )
}
