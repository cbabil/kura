/**
 * The dock: pinned apps in the owner's order, then running apps that are not
 * pinned, a separator, minimised windows, and the apps fixed at the end
 * (Trash). A dot marks running apps; hovering names the app. Drag to
 * reorder; right-click to keep or remove. No magnification and no bounce.
 */
import { useState, type DragEvent, type MouseEvent } from 'react'
import { Box, Menu, MenuItem, Tooltip } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { AppIcon } from '../icons/AppIcon'
import { appText, DOCK_END } from '../apps/registry'
import { useI18n } from '../i18n'
import { moveItem, unpin } from './dockOrder'
import { COMPACT_DOCK_ICON, DOCK_ICON } from './layout'

interface Props {
  pinned: string[]
  running: string[]
  minimized: string[]
  compact: boolean
  onOpen(app: string): void
  onPinnedChange(next: string[]): void
}

interface ItemProps {
  app: string
  size: number
  running: boolean
  minimizedTile?: boolean
  onOpen(app: string): void
  onMenu?(app: string, el: HTMLElement): void
  onDragStart?(app: string): void
  onDropOn?(app: string): void
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

function DockItem({ app, size, running, minimizedTile, onOpen, onMenu, onDragStart, onDropOn }: ItemProps) {
  const { t } = useI18n()
  const name = appText(t, app, 'name')
  const draggable = Boolean(onDropOn)
  return (
    <Tooltip title={name} placement="top" disableInteractive>
      <Box component="button" aria-label={minimizedTile ? t('dock.minimised', { name }) : name} data-running={running}
        draggable={draggable}
        onClick={() => onOpen(app)}
        onContextMenu={(e: MouseEvent<HTMLElement>) => {
          e.preventDefault()
          onMenu?.(app, e.currentTarget)
        }}
        onDragStart={(e: DragEvent) => {
          e.dataTransfer.setData('text/plain', app)
          onDragStart?.(app)
        }}
        onDragOver={(e: DragEvent) => draggable && e.preventDefault()}
        onDrop={(e: DragEvent) => {
          if (!onDropOn) return
          e.preventDefault()
          e.stopPropagation()
          onDropOn(app)
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

export function Dock({ pinned, running, minimized, compact, onOpen, onPinnedChange }: Props) {
  const k = useTheme().kura
  const { t } = useI18n()
  const size = compact ? COMPACT_DOCK_ICON : DOCK_ICON
  const [dragging, setDragging] = useState<string | null>(null)
  const [menu, setMenu] = useState<{ el: HTMLElement; app: string } | null>(null)
  const extra = running.filter((a) => !pinned.includes(a) && !DOCK_END.includes(a))
  const isPinned = menu !== null && pinned.includes(menu.app)

  const drop = (before: string | null) => {
    if (dragging) onPinnedChange(moveItem(pinned, dragging, before))
    setDragging(null)
  }
  const openMenu = (app: string, el: HTMLElement) => setMenu({ el, app })
  const fromMenu = (act: (app: string) => void) => () => {
    if (menu) act(menu.app)
    setMenu(null)
  }
  const togglePin = (app: string) => onPinnedChange(isPinned ? unpin(pinned, app) : [...pinned, app])

  return (
    <Box component="nav" aria-label={t('dock.label')} onDragOver={(e) => e.preventDefault()} onDrop={() => drop(null)}
      sx={{
        position: 'absolute', left: '50%', bottom: compact ? 6 : 10, transform: 'translateX(-50%)', zIndex: 1000,
        display: 'flex', alignItems: 'flex-end', gap: '2px', px: 1, pt: '4px', pb: '8px', borderRadius: '22px',
        bgcolor: k.dock, backdropFilter: 'blur(28px)', border: `1px solid ${k.edge}`, maxWidth: 'calc(100vw - 16px)', overflowX: 'auto',
      }}>
      {pinned.map((app) => (
        <DockItem key={app} app={app} size={size} running={running.includes(app)} onOpen={onOpen} onMenu={openMenu}
          onDragStart={setDragging} onDropOn={drop} />
      ))}
      {extra.map((app) => <DockItem key={app} app={app} size={size} running onOpen={onOpen} onMenu={openMenu} />)}
      <Box aria-hidden sx={{ width: '1px', height: size * 0.84, bgcolor: k.edge, mx: 1, mb: '5px', flexShrink: 0 }} />
      {minimized.map((app) => <DockItem key={`min-${app}`} app={app} size={size} running={false} minimizedTile onOpen={onOpen} />)}
      {DOCK_END.map((app) => <DockItem key={app} app={app} size={size} running={running.includes(app)} onOpen={onOpen} />)}
      <Menu open={Boolean(menu)} anchorEl={menu?.el} onClose={() => setMenu(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }} transformOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <MenuItem onClick={fromMenu(onOpen)}>{t('dock.open')}</MenuItem>
        <MenuItem onClick={fromMenu(togglePin)}>{t(isPinned ? 'dock.remove' : 'dock.keep')}</MenuItem>
      </Menu>
    </Box>
  )
}
