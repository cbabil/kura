/**
 * The menu bar: the 蔵 menu, the active app's name and menus, and on the
 * right temperature, connection, the theme switch, search and the clock.
 * Menu items carry their own actions; the bar only runs the one chosen.
 */
import { useEffect, useState, type MouseEvent } from 'react'
import { Box, IconButton, Menu, MenuItem as MuiMenuItem, Tooltip } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { AppMenu, MenuItem } from '../apps/types'
import { Glyph } from '../icons/Glyph'
import { useI18n } from '../i18n'
import { MINCHO, type Mode } from '../theme'
import { MENU_BAR } from './layout'
import { useStats, useUpdates } from './DesktopData'

interface Props {
  appName: string
  kuraMenu: AppMenu
  menus: AppMenu[]
  compact: boolean
  mode: Mode
  onRun(item: MenuItem): void
  onToggleTheme(): void
  onLauncher(): void
  /** Opens where updates are installed. */
  onUpdates(): void
}

export function Clock() {
  const { format } = useI18n()
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 15_000)
    return () => clearInterval(timer)
  }, [])
  return (
    <Box component="span" sx={{ whiteSpace: 'nowrap' }}>
      <Box component="span" sx={{ display: { xs: 'none', sm: 'inline' } }}>{format.date(now)}&nbsp;&nbsp;</Box>
      {format.time(now)}
    </Box>
  )
}

/**
 * Beside the date and time, only when an update waits or a restart is due:
 * says which in words (the icon alone on a phone) and opens Settings › Updates.
 */
export function UpdateNotice({ onOpen }: { onOpen(): void }) {
  const { t } = useI18n()
  const { status } = useUpdates()
  if (!status?.available && !status?.restartRequired) return null
  const restart = !status.available
  const label = restart ? t('status.restartDue') : t('status.update', { version: status.available ?? '' })
  return (
    <Tooltip title={label}>
      <Box component="button" aria-label={label} onClick={onOpen} sx={{
        display: 'flex', alignItems: 'center', gap: '5px', height: 20, px: '8px', border: 0, borderRadius: '10px', cursor: 'pointer',
        font: 'inherit', fontSize: 12, fontWeight: 600, whiteSpace: 'nowrap', color: '#fff',
        bgcolor: restart ? 'warning.main' : 'primary.main', '&:hover': { bgcolor: restart ? 'warning.dark' : 'primary.dark' },
      }}>
        <Glyph name="update" size={13} />
        <Box component="span" sx={{ display: { xs: 'none', sm: 'inline' } }}>
          {restart ? t('status.restartShort') : t('status.updateShort', { version: status.available ?? '' })}
        </Box>
      </Box>
    </Tooltip>
  )
}

/** Temperature and connection: the only parts of the bar that change with each sample. */
export function StatusArea() {
  const { t } = useI18n()
  const tempC = useStats((s) => s.latest?.tempC ?? null)
  const online = useStats((s) => s.latest !== null)
  return (
    <>
      {tempC !== null && (
        <Tooltip title={t('status.temp')}>
          <Box sx={{ display: { xs: 'none', sm: 'flex' }, gap: '4px', whiteSpace: 'nowrap' }}><Glyph name="temp" size={15} />{tempC}°</Box>
        </Tooltip>
      )}
      <Tooltip title={t(online ? 'status.connected' : 'status.disconnected')}>
        <Box aria-label={t(online ? 'status.online' : 'status.offline')} sx={{ display: 'flex', color: online ? 'inherit' : 'error.main' }}>
          <Glyph name={online ? 'ethernet' : 'offline'} size={15} />
        </Box>
      </Tooltip>
    </>
  )
}

const menuButton = {
  border: 0, background: 'none', color: 'inherit', font: 'inherit', px: '9px', height: 24, borderRadius: '6px',
  cursor: 'default', '&[aria-expanded="true"]': { bgcolor: 'action.selected' },
} as const

export function MenuBar(p: Props) {
  const k = useTheme().kura
  const { t } = useI18n()
  const [open, setOpen] = useState<{ el: HTMLElement; menu: AppMenu } | null>(null)
  const show = (menu: AppMenu) => (e: MouseEvent<HTMLElement>) => setOpen({ el: e.currentTarget, menu })
  const choose = (item: MenuItem) => {
    setOpen(null)
    p.onRun(item)
  }

  return (
    <Box component="header" sx={{
      position: 'absolute', inset: '0 0 auto 0', height: MENU_BAR, zIndex: 1100, display: 'flex', alignItems: 'center',
      px: 1, fontSize: 13, whiteSpace: 'nowrap', bgcolor: k.bar, backdropFilter: 'blur(24px)', borderBottom: 1, borderColor: 'divider',
    }}>
      <Box component="button" aria-label={t('menu.kura')} aria-expanded={open?.menu === p.kuraMenu} onClick={show(p.kuraMenu)}
        sx={{ ...menuButton, color: 'primary.light', fontSize: 16, fontFamily: MINCHO }}>蔵</Box>
      <Box component="span" sx={{ fontWeight: 600, px: '9px', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {p.appName}
      </Box>
      {!p.compact && p.menus.map((menu) => (
        <Box component="button" key={menu.title} aria-expanded={open?.menu === menu} onClick={show(menu)} sx={menuButton}>
          {menu.title === '蔵' ? menu.title : t(menu.title)}
        </Box>
      ))}
      <Menu open={Boolean(open)} anchorEl={open?.el} onClose={() => setOpen(null)}>
        {open?.menu.items.map((item) => <MuiMenuItem key={item.label} dense onClick={() => choose(item)}>{t(item.label, item.vars)}</MuiMenuItem>)}
      </Menu>
      <Box sx={{ ml: 'auto', display: 'flex', alignItems: 'center', gap: { xs: '8px', sm: '14px' }, pr: 1, flexShrink: 0 }}>
        <StatusArea />
        <IconButton size="small" aria-label={t(p.mode === 'dark' ? 'status.light' : 'status.dark')} onClick={p.onToggleTheme}>
          <Glyph name={p.mode === 'dark' ? 'sun' : 'moon'} size={15} />
        </IconButton>
        <IconButton size="small" aria-label={t('status.search')} onClick={p.onLauncher}><Glyph name="search" size={15} /></IconButton>
        <UpdateNotice onOpen={p.onUpdates} />
        <Clock />
      </Box>
    </Box>
  )
}
