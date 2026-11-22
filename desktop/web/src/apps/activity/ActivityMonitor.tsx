/**
 * Activity Monitor (D1, read-only): a sidebar of sections and the chosen
 * view, plus the 1 h / 24 h range switch in the title bar. It subscribes to
 * the stats itself, so the rest of the desktop does not re-render with them.
 */
import { memo, useState } from 'react'
import { Box, ToggleButton, ToggleButtonGroup } from '@mui/material'
import type { Range } from '../../api'
import type { GlyphName } from '../../icons/Glyph'
import { useI18n, type MessageKey } from '../../i18n'
import { useStats, useSystem } from '../../shell/DesktopData'
import { WindowToolbar } from '../../shell/WindowToolbar'
import type { AppProps } from '../types'
import { Sidebar, ViewBody } from '../parts'
import { CpuView, MemoryView, NetworkView, ServicesView, StorageView, SummaryView, type ViewProps } from './views'

export const ACTIVITY_VIEWS = ['Summary', 'CPU', 'Memory', 'Storage', 'Network', 'Services'] as const
export type ActivityView = (typeof ACTIVITY_VIEWS)[number]

/** Each section's label in the catalogue. */
export const VIEW_LABELS: Record<ActivityView, MessageKey> = {
  Summary: 'activity.view.Summary',
  CPU: 'activity.view.CPU',
  Memory: 'activity.view.Memory',
  Storage: 'activity.view.Storage',
  Network: 'activity.view.Network',
  Services: 'activity.view.Services',
}

const VIEWS: Record<ActivityView, { glyph: GlyphName; Component: (p: ViewProps) => React.ReactNode; live: boolean }> = {
  Summary: { glyph: 'pulse', Component: SummaryView, live: true },
  CPU: { glyph: 'cpu', Component: CpuView, live: true },
  Memory: { glyph: 'memory', Component: MemoryView, live: true },
  Storage: { glyph: 'disk', Component: StorageView, live: true },
  Network: { glyph: 'network', Component: NetworkView, live: true },
  Services: { glyph: 'services', Component: ServicesView, live: false },
}

export function RangeSwitch({ range, onRange }: { range: Range; onRange(r: Range): void }) {
  const { t } = useI18n()
  return (
    <ToggleButtonGroup size="small" exclusive value={range} aria-label={t('activity.range')}
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
  const { t } = useI18n()
  const stats = useStats()
  const system = useSystem()
  const [range, setRange] = useState<Range>('1h')
  const view = isView(requested) ? requested : 'Summary'
  const { Component, live } = VIEWS[view]
  const waiting = live && !stats.latest

  return (
    <Box sx={{ flex: 1, display: 'flex', flexDirection: compact ? 'column' : 'row', minWidth: 0, minHeight: 0 }}>
      <WindowToolbar><RangeSwitch range={range} onRange={setRange} /></WindowToolbar>
      <Sidebar<ActivityView> label={t('activity.sections')} views={ACTIVITY_VIEWS} current={view} compact={compact}
        glyph={(v) => VIEWS[v].glyph} name={(v) => t(VIEW_LABELS[v])} onChoose={setView} />
      {waiting ? (
        <ViewBody><Box sx={{ color: 'text.secondary' }}>{t('activity.waiting')}</Box></ViewBody>
      ) : (
        <Component stats={stats} system={system} range={range} />
      )}
    </Box>
  )
}

export const ActivityMonitor = memo(ActivityMonitorBody)
