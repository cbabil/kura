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
import { MINCHO, type Mode } from '../theme'
import { MENU_BAR } from './layout'
import { useStats } from './useStats'

interface Props {
  appName: string
  kuraMenu: AppMenu
  menus: AppMenu[]
  compact: boolean
  mode: Mode
  onRun(item: MenuItem): void
  onToggleTheme(): void
  onLauncher(): void
}

const dateFmt = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short' })
const timeFmt = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit' })

export function Clock() {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 15_000)
    return () => clearInterval(timer)
  }, [])
  return (
    <Box component="span" sx={{ whiteSpace: 'nowrap' }}>
      <Box component="span" sx={{ display: { xs: 'none', sm: 'inline' } }}>{dateFmt.format(now)}&nbsp;&nbsp;</Box>
      {timeFmt.format(now)}
    </Box>
  )
}

/** Temperature and connection: the only parts of the bar that change with each sample. */
export function StatusArea() {
  const tempC = useStats((s) => s.latest?.tempC ?? null)
  const online = useStats((s) => s.latest !== null)
  return (
    <>
      {tempC !== null && (
        <Tooltip title="Hottest sensor">
          <Box sx={{ display: { xs: 'none', sm: 'flex' }, gap: '4px' }}><Glyph name="temp" size={15} />{tempC}°</Box>
        </Tooltip>
      )}
      <Tooltip title={online ? 'Connected to the server' : 'Not connected'}>
        <Box aria-label={online ? 'Online' : 'Offline'} sx={{ display: 'flex', color: online ? 'inherit' : 'error.main' }}>
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
      <Box component="button" aria-label="Kura menu" aria-expanded={open?.menu === p.kuraMenu} onClick={show(p.kuraMenu)}
        sx={{ ...menuButton, color: 'primary.light', fontSize: 16, fontFamily: MINCHO }}>蔵</Box>
      <Box component="span" sx={{ fontWeight: 600, px: '9px', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {p.appName}
      </Box>
      {!p.compact && p.menus.map((menu) => (
        <Box component="button" key={menu.title} aria-expanded={open?.menu === menu} onClick={show(menu)} sx={menuButton}>
          {menu.title}
        </Box>
      ))}
      <Menu open={Boolean(open)} anchorEl={open?.el} onClose={() => setOpen(null)}>
        {open?.menu.items.map((item) => <MuiMenuItem key={item.label} dense onClick={() => choose(item)}>{item.label}</MuiMenuItem>)}
      </Menu>
      <Box sx={{ ml: 'auto', display: 'flex', alignItems: 'center', gap: { xs: '8px', sm: '14px' }, pr: 1, flexShrink: 0 }}>
        <StatusArea />
        <IconButton size="small" aria-label={p.mode === 'dark' ? 'Use light theme' : 'Use dark theme'} onClick={p.onToggleTheme}>
          <Glyph name={p.mode === 'dark' ? 'sun' : 'moon'} size={15} />
        </IconButton>
        <IconButton size="small" aria-label="Search (Ctrl K)" onClick={p.onLauncher}><Glyph name="search" size={15} /></IconButton>
        <Clock />
      </Box>
    </Box>
  )
}
