/**
 * Activity Monitor (D1, read-only): a sidebar of sections and the chosen
 * view, plus the 1 h / 24 h range switch in the title bar. It subscribes to
 * the stats itself, so the rest of the desktop does not re-render with them.
 */
import { memo, useState } from 'react'
import { Box, List, ListItemButton, ListItemIcon, ListItemText, ToggleButton, ToggleButtonGroup } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { Range } from '../../api'
import { Glyph, type GlyphName } from '../../icons/Glyph'
import { useStats, useSystem } from '../../shell/useStats'
import { WindowToolbar } from '../../shell/WindowToolbar'
import type { AppProps } from '../types'
import { ViewBody } from './parts'
import { CpuView, MemoryView, NetworkView, ServicesView, StorageView, SummaryView, type ViewProps } from './views'

export const ACTIVITY_VIEWS = ['Summary', 'CPU', 'Memory', 'Storage', 'Network', 'Services'] as const
export type ActivityView = (typeof ACTIVITY_VIEWS)[number]

const VIEWS: Record<ActivityView, { glyph: GlyphName; Component: (p: ViewProps) => React.ReactNode; live: boolean }> = {
  Summary: { glyph: 'pulse', Component: SummaryView, live: true },
  CPU: { glyph: 'cpu', Component: CpuView, live: true },
  Memory: { glyph: 'memory', Component: MemoryView, live: true },
  Storage: { glyph: 'disk', Component: StorageView, live: true },
  Network: { glyph: 'network', Component: NetworkView, live: true },
  Services: { glyph: 'services', Component: ServicesView, live: false },
}

export function RangeSwitch({ range, onRange }: { range: Range; onRange(r: Range): void }) {
  return (
    <ToggleButtonGroup size="small" exclusive value={range} aria-label="Time range"
      onChange={(_, v: Range | null) => v && onRange(v)}
      sx={{ '& .MuiToggleButton-root': { py: '1px', px: '10px', fontSize: 12, textTransform: 'none' },
        '& .Mui-selected, & .Mui-selected:hover': { bgcolor: 'primary.main', color: 'primary.contrastText' } }}>
      <ToggleButton value="1h">1 h</ToggleButton>
      <ToggleButton value="24h">24 h</ToggleButton>
    </ToggleButtonGroup>
  )
}

const isView = (v: string): v is ActivityView => v in VIEWS

function ActivityMonitorBody({ view: requested, setView, compact }: AppProps) {
  const k = useTheme().kura
  const stats = useStats()
  const system = useSystem()
  const [range, setRange] = useState<Range>('1h')
  const view = isView(requested) ? requested : 'Summary'
  const { Component, live } = VIEWS[view]
  const waiting = live && !stats.latest

  return (
    <Box sx={{ flex: 1, display: 'flex', flexDirection: compact ? 'column' : 'row', minWidth: 0, minHeight: 0 }}>
      <WindowToolbar><RangeSwitch range={range} onRange={setRange} /></WindowToolbar>
      <List component="nav" aria-label="Sections" dense disablePadding sx={{
        width: compact ? 'auto' : 186, flexShrink: 0, p: compact ? 1 : '12px 8px', bgcolor: k.chrome,
        borderRight: compact ? 0 : 1, borderBottom: compact ? 1 : 0, borderColor: 'divider',
        display: 'flex', flexDirection: compact ? 'row' : 'column', overflowX: 'auto', gap: '2px',
      }}>
        {ACTIVITY_VIEWS.map((v) => (
          <ListItemButton key={v} selected={v === view} aria-current={v === view ? 'page' : undefined} onClick={() => setView(v)}
            sx={{ borderRadius: '7px', flexGrow: 0, py: '4px', px: 1, '&.Mui-selected': { color: k.selected } }}>
            <ListItemIcon sx={{ minWidth: 25, color: 'inherit' }}><Glyph name={VIEWS[v].glyph} /></ListItemIcon>
            <ListItemText primary={v} slotProps={{ primary: { noWrap: true, sx: { fontSize: 13 } } }} />
          </ListItemButton>
        ))}
      </List>
      {waiting ? (
        <ViewBody><Box sx={{ color: 'text.secondary' }}>Waiting for the first measurement…</Box></ViewBody>
      ) : (
        <Component stats={stats} system={system} range={range} />
      )}
    </Box>
  )
}

export const ActivityMonitor = memo(ActivityMonitorBody)
