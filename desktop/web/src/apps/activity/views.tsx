/**
 * Activity Monitor's views. ActivityMonitor shows "waiting" until the first
 * sample, so the live views can rely on `stats.latest`.
 */
import type { ReactNode } from 'react'
import { Box } from '@mui/material'
import type { Proc, Range, Sample, SystemInfo, Unit } from '../../api'
import type { Stats } from '../../shell/useStats'
import { colors } from '../../theme'
import { AreaChart, Meter, seriesOf } from './Charts'
import { Card, DataTable, Dot, Legend, SectionTitle, STATE_COLORS, Tile, TileGrid, ViewBody, type Column } from './parts'
import { bytes, percent, rate, since, unitName } from './format'

export interface ViewProps {
  stats: Stats
  system: SystemInfo | null
  range: Range
}

const cpu = (s: Sample) => s.cpu
const memApps = (s: Sample) => s.memUsed
const memAll = (s: Sample) => s.memUsed + s.memCache
const netRx = (s: Sample) => s.netRx
const netTx = (s: Sample) => s.netTx

/** The latest sample; ActivityMonitor renders live views only once there is one. */
const latestOf = (stats: Stats) => stats.latest as Sample

const cores = (system: SystemInfo | null) => `${system?.cores ?? '?'} cores`

const PROC_COLUMNS: Column<Proc>[] = [
  { label: 'Process', cell: (p) => p.name },
  { label: 'User', cell: (p) => p.user },
  { label: 'PID', numeric: true, cell: (p) => p.pid },
  { label: 'CPU', numeric: true, cell: (p) => percent(p.cpu, 1) },
  { label: 'Memory', numeric: true, cell: (p) => bytes(p.mem) },
]

export function SummaryView({ stats, system, range }: ViewProps) {
  const s = latestOf(stats)
  const h = stats.history[range]
  const disk = s.disks.reduce((a, d) => ({ used: a.used + d.used, size: a.size + d.size }), { used: 0, size: 0 })
  const memParts = [{ value: s.memUsed, color: colors.primary }, { value: s.memCache, color: colors.info }]
  const memLegend = [
    { color: colors.primary, label: `Apps ${bytes(s.memUsed)}` },
    { color: colors.info, label: `Cache ${bytes(s.memCache)}` },
  ]
  return (
    <ViewBody>
      <TileGrid min={170}>
        <Tile title={`CPU · ${cores(system)}`} value={percent(s.cpu)}>
          <AreaChart label="CPU history" height={34} max={100}
            series={[{ label: 'cpu', color: colors.primary, values: seriesOf(h, 'cpu', cpu) }]} />
        </Tile>
        <Tile title={`Memory · ${bytes(s.memTotal)}`} value={bytes(s.memUsed)} unit="used">
          <Meter label="Memory" total={s.memTotal} parts={memParts} />
          <Legend items={memLegend} />
        </Tile>
        <Tile title={`Storage · ${bytes(disk.size)}`} value={bytes(disk.used)} unit="used">
          <Meter label="Storage" total={disk.size} parts={[{ value: disk.used, color: colors.success }]} />
          <Legend items={[{ color: colors.success, label: `${s.disks.length} volumes` }]} />
        </Tile>
        <Tile title="Network" value={rate(s.netRx)} unit="down">
          <AreaChart label="Network history" height={34}
            series={[{ label: 'rx', color: colors.info, values: seriesOf(h, 'rx', netRx) }]} />
        </Tile>
      </TileGrid>
      <DataTable label="Busiest processes" rows={stats.procs} columns={PROC_COLUMNS} rowKey={(p) => p.pid} />
    </ViewBody>
  )
}

function DetailChart({ title, figures, children }: { title: string; figures: [string, string][]; children: ReactNode }) {
  return (
    <ViewBody>
      <SectionTitle>{title}</SectionTitle>
      <Card sx={{ p: 2, mb: 2 }}>{children}</Card>
      <TileGrid min={140}>{figures.map(([k, v]) => <Tile key={k} title={k} value={v} />)}</TileGrid>
    </ViewBody>
  )
}

export function CpuView({ stats, system, range }: ViewProps) {
  const values = seriesOf(stats.history[range], 'cpu', cpu)
  const avg = values.reduce((a, b) => a + b, 0) / Math.max(values.length, 1)
  const figures: [string, string][] = [
    ['Now', percent(latestOf(stats).cpu)], ['Average', percent(avg)], ['Peak', percent(Math.max(0, ...values))],
  ]
  return (
    <DetailChart title={`CPU · ${cores(system)}`} figures={figures}>
      <AreaChart label="CPU history" height={220} max={100} series={[{ label: 'cpu', color: colors.primary, values }]} />
    </DetailChart>
  )
}

export function MemoryView({ stats, range }: ViewProps) {
  const s = latestOf(stats)
  const h = stats.history[range]
  const free = Math.max(0, s.memTotal - s.memUsed - s.memCache)
  return (
    <DetailChart title={`Memory · ${bytes(s.memTotal)}`}
      figures={[['Apps', bytes(s.memUsed)], ['Cache', bytes(s.memCache)], ['Free', bytes(free)]]}>
      <AreaChart label="Memory history" height={220} max={s.memTotal} series={[
        { label: 'total', color: colors.info, values: seriesOf(h, 'memAll', memAll) },
        { label: 'apps', color: colors.primary, values: seriesOf(h, 'memApps', memApps) },
      ]} />
      <Legend items={[{ color: colors.primary, label: 'Apps' }, { color: colors.info, label: 'Apps and cache' }]} />
    </DetailChart>
  )
}

export function NetworkView({ stats, range }: ViewProps) {
  const s = latestOf(stats)
  const h = stats.history[range]
  return (
    <DetailChart title="Network" figures={[['Download', rate(s.netRx)], ['Upload', rate(s.netTx)]]}>
      <AreaChart label="Network history" height={220} series={[
        { label: 'down', color: colors.info, values: seriesOf(h, 'rx', netRx) },
        { label: 'up', color: colors.primary, values: seriesOf(h, 'tx', netTx) },
      ]} />
      <Legend items={[{ color: colors.info, label: 'Download' }, { color: colors.primary, label: 'Upload' }]} />
    </DetailChart>
  )
}

export function StorageView({ stats }: ViewProps) {
  return (
    <ViewBody>
      <SectionTitle>Volumes</SectionTitle>
      {latestOf(stats).disks.map((d) => (
        <Card key={d.mount} sx={{ mb: 1.25 }}>
          <Box sx={{ display: 'flex', mb: 1 }}>
            <Box component="span" sx={{ fontFamily: 'monospace' }}>{d.mount}</Box>
            <Box component="span" sx={{ ml: 'auto', color: 'text.secondary' }}>{bytes(d.used)} of {bytes(d.size)}</Box>
          </Box>
          <Meter label={`${d.mount} used`} total={d.size}
            parts={[{ value: d.used, color: d.used / d.size > 0.9 ? colors.error : colors.success }]} />
        </Card>
      ))}
    </ViewBody>
  )
}

const UNIT_COLUMNS: Column<Unit>[] = [
  { label: 'Service', cell: (u) => <><Dot color={STATE_COLORS[u.state] ?? colors.info} />{unitName(u.name)}</> },
  { label: 'State', cell: (u) => u.state },
  { label: 'For', cell: (u) => since(u.since) },
  { label: 'Memory', numeric: true, cell: (u) => bytes(u.mem) },
]

export function ServicesView({ stats }: ViewProps) {
  return <ViewBody><DataTable label="Services" rows={stats.units} columns={UNIT_COLUMNS} rowKey={(u) => u.name} /></ViewBody>
}
