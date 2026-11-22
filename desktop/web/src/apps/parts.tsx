/** Building blocks shared by the apps: cards, tiles, tables, dots, notices and monospaced text. */
import type { ReactNode } from 'react'
import { Box, List, ListItemButton, ListItemIcon, ListItemText, Paper, Table, TableBody, TableCell, TableHead, TableRow, type SxProps } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { Glyph, type GlyphName } from '../icons/Glyph'

/** An outlined card (radius and border from the theme's Paper "outlined"). */
export function Card({ children, sx }: { children: ReactNode; sx?: SxProps }) {
  return <Paper variant="outlined" sx={{ p: '12px 14px', minWidth: 0, ...sx }}>{children}</Paper>
}

export function SectionTitle({ children }: { children: ReactNode }) {
  return <Box sx={{ fontWeight: 600, mb: 1.5 }}>{children}</Box>
}

/** Tiles that wrap to the window's width. */
export function TileGrid({ min, children }: { min: number; children: ReactNode }) {
  return <Box sx={{ display: 'grid', gridTemplateColumns: `repeat(auto-fit, minmax(${min}px, 1fr))`, gap: '12px', mb: 2 }}>{children}</Box>
}

export function Tile({ title, value, unit, children }: { title: string; value: string; unit?: string; children?: ReactNode }) {
  return (
    <Card>
      <Box sx={{ fontSize: 12, color: 'text.secondary' }}>{title}</Box>
      <Box sx={{ fontSize: 'clamp(18px, 1.6vw, 22px)', fontWeight: 600, letterSpacing: '-.4px', mt: '2px', whiteSpace: 'nowrap' }}>
        {value}
        {unit && <Box component="small" sx={{ fontSize: 13, color: 'text.secondary', fontWeight: 500 }}> {unit}</Box>}
      </Box>
      {children && <Box sx={{ mt: 1 }}>{children}</Box>}
    </Card>
  )
}

export function Dot({ color }: { color: string }) {
  return <Box component="span" sx={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', bgcolor: color, mr: 1 }} />
}

export function Legend({ items }: { items: { color: string; label: string }[] }) {
  return (
    <Box sx={{ fontSize: 11.5, color: 'text.secondary', mt: '7px', display: 'flex', flexWrap: 'wrap', columnGap: '10px' }}>
      {items.map((i) => (
        <Box key={i.label} component="span" sx={{ whiteSpace: 'nowrap' }}><Dot color={i.color} />{i.label}</Box>
      ))}
    </Box>
  )
}

/** A systemd unit's name as people say it: without ".service". */
export const unitName = (name: string) => name.replace(/\.service$/, '')

export interface Column<T> {
  label: string
  numeric?: boolean
  cell(row: T): ReactNode
}

const CELL = { py: '7px', px: '10px', borderColor: 'divider', fontSize: 13, whiteSpace: 'nowrap' } as const

export function DataTable<T>(p: { rows: T[]; columns: Column<T>[]; rowKey(r: T): string | number; label: string }) {
  return (
    <Table size="small" aria-label={p.label} stickyHeader>
      <TableHead>
        <TableRow>
          {p.columns.map((c) => (
            <TableCell key={c.label} align={c.numeric ? 'right' : 'left'}
              sx={{ ...CELL, color: 'text.secondary', fontWeight: 500, fontSize: 12, bgcolor: 'background.paper' }}>
              {c.label}
            </TableCell>
          ))}
        </TableRow>
      </TableHead>
      <TableBody>
        {p.rows.map((r) => (
          <TableRow key={p.rowKey(r)} hover>
            {p.columns.map((c) => (
              <TableCell key={c.label} align={c.numeric ? 'right' : 'left'} sx={{ ...CELL, fontVariantNumeric: 'tabular-nums' }}>
                {c.cell(r)}
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

/** The stack for anything that must line up: logs, images, the terminal. */
export const MONO = 'ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'

/** A message in the middle of a window: nothing to show, not allowed, or not answering. */
export function Notice({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <Box role="status" sx={{ flex: 1, display: 'grid', placeItems: 'center', p: 3, textAlign: 'center', color: 'text.secondary' }}>
      <Box>
        {children}
        {action && <Box sx={{ mt: 1.5 }}>{action}</Box>}
      </Box>
    </Box>
  )
}

/** A view's scrolling body: the window stays put, the content scrolls. */
export function ViewBody({ children }: { children: ReactNode }) {
  return <Box className="no-scrollbar" sx={{ flex: 1, minWidth: 0, minHeight: 0, overflowY: 'auto', p: '18px 20px' }}>{children}</Box>
}

/** The sections of an app, down its side (along its top on a phone). */
export function Sidebar<V extends string>(p: {
  label: string
  views: readonly V[]
  current: V
  compact: boolean
  glyph(view: V): GlyphName
  name(view: V): string
  onChoose(view: V): void
}) {
  const k = useTheme().kura
  return (
    <List component="nav" aria-label={p.label} dense disablePadding sx={{
      width: p.compact ? 'auto' : 186, flexShrink: 0, p: p.compact ? 1 : '12px 8px', bgcolor: k.chrome,
      borderRight: p.compact ? 0 : 1, borderBottom: p.compact ? 1 : 0, borderColor: 'divider',
      display: 'flex', flexDirection: p.compact ? 'row' : 'column', overflowX: 'auto', gap: '2px',
    }}>
      {p.views.map((v) => (
        <ListItemButton key={v} selected={v === p.current} aria-current={v === p.current ? 'page' : undefined} onClick={() => p.onChoose(v)}
          sx={{ borderRadius: '7px', flexGrow: 0, py: '4px', px: 1, '&.Mui-selected': { color: k.selected } }}>
          <ListItemIcon sx={{ minWidth: 25, color: 'inherit' }}><Glyph name={p.glyph(v)} /></ListItemIcon>
          <ListItemText primary={p.name(v)} slotProps={{ primary: { noWrap: true, sx: { fontSize: 13 } } }} />
        </ListItemButton>
      ))}
    </List>
  )
}
