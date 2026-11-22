/**
 * Activity Monitor's views, in the user's language. ActivityMonitor shows
 * "waiting" until the first sample, so the live views can rely on
 * `stats.latest`.
 */
import type { ReactNode } from 'react'
import type { Proc, Range, Sample, SystemInfo, Unit, UnitState } from '../../api'
import { useI18n, type I18n, type MessageKey } from '../../i18n'
import type { Stats } from '../../shell/useStats'
import { colors } from '../../theme'
import { AreaChart, Meter, seriesOf } from './Charts'
import { Volumes } from '../Volumes'
import { Card, DataTable, Dot, Legend, SectionTitle, Tile, TileGrid, unitName, ViewBody, type Column } from '../parts'

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

/** "CPU · 4 cores", or without a count until the system facts arrive. */
const cpuTitle = ({ t, tn }: I18n, system: SystemInfo | null) =>
  system ? tn('activity.cpu', system.cores) : t('activity.view.CPU')

const UNIT_COLORS: Record<string, string> = {
  active: colors.success, failed: colors.error, activating: colors.warning, deactivating: colors.warning,
}

const STATE_LABELS: Record<UnitState, MessageKey> = {
  active: 'state.active',
  inactive: 'state.inactive',
  failed: 'state.failed',
  activating: 'state.activating',
  deactivating: 'state.deactivating',
}

function procColumns({ t, format }: I18n): Column<Proc>[] {
  return [
    { label: t('activity.col.process'), cell: (p) => p.name },
    { label: t('activity.col.user'), cell: (p) => p.user },
    { label: t('activity.col.pid'), numeric: true, cell: (p) => p.pid },
    { label: t('activity.col.cpu'), numeric: true, cell: (p) => format.percent(p.cpu, 1) },
    { label: t('activity.col.memory'), numeric: true, cell: (p) => format.bytes(p.mem) },
  ]
}

export function SummaryView({ stats, system, range }: ViewProps) {
  const i18n = useI18n()
  const { t, tn, format } = i18n
  const s = latestOf(stats)
  const h = stats.history[range]
  const disk = s.disks.reduce((a, d) => ({ used: a.used + d.used, size: a.size + d.size }), { used: 0, size: 0 })
  const memParts = [{ value: s.memUsed, color: colors.primary }, { value: s.memCache, color: colors.info }]
  const memLegend = [
    { color: colors.primary, label: t('activity.appsSize', { size: format.bytes(s.memUsed) }) },
    { color: colors.info, label: t('activity.cacheSize', { size: format.bytes(s.memCache) }) },
  ]
  return (
    <ViewBody>
      <TileGrid min={170}>
        <Tile title={cpuTitle(i18n, system)} value={format.percent(s.cpu)}>
          <AreaChart label={t('activity.cpuHistory')} height={34} max={100}
            series={[{ label: 'cpu', color: colors.primary, values: seriesOf(h, 'cpu', cpu) }]} />
        </Tile>
        <Tile title={t('activity.memory', { total: format.bytes(s.memTotal) })} value={format.bytes(s.memUsed)} unit={t('activity.used')}>
          <Meter label={t('activity.view.Memory')} total={s.memTotal} parts={memParts} />
          <Legend items={memLegend} />
        </Tile>
        <Tile title={t('activity.storage', { total: format.bytes(disk.size) })} value={format.bytes(disk.used)} unit={t('activity.used')}>
          <Meter label={t('activity.view.Storage')} total={disk.size} parts={[{ value: disk.used, color: colors.success }]} />
          <Legend items={[{ color: colors.success, label: tn('activity.volumes', s.disks.length) }]} />
        </Tile>
        <Tile title={t('activity.network')} value={format.rate(s.netRx)} unit={t('activity.down')}>
          <AreaChart label={t('activity.networkHistory')} height={34}
            series={[{ label: 'rx', color: colors.info, values: seriesOf(h, 'rx', netRx) }]} />
        </Tile>
      </TileGrid>
      <DataTable label={t('activity.busiest')} rows={stats.procs} columns={procColumns(i18n)} rowKey={(p) => p.pid} />
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
  const i18n = useI18n()
  const { t, format } = i18n
  const values = seriesOf(stats.history[range], 'cpu', cpu)
  const avg = values.reduce((a, b) => a + b, 0) / Math.max(values.length, 1)
  const figures: [string, string][] = [
    [t('activity.now'), format.percent(latestOf(stats).cpu)],
    [t('activity.average'), format.percent(avg)],
    [t('activity.peak'), format.percent(Math.max(0, ...values))],
  ]
  return (
    <DetailChart title={cpuTitle(i18n, system)} figures={figures}>
      <AreaChart label={t('activity.cpuHistory')} height={220} max={100} series={[{ label: 'cpu', color: colors.primary, values }]} />
    </DetailChart>
  )
}

export function MemoryView({ stats, range }: ViewProps) {
  const { t, format } = useI18n()
  const s = latestOf(stats)
  const h = stats.history[range]
  const free = Math.max(0, s.memTotal - s.memUsed - s.memCache)
  const figures: [string, string][] = [
    [t('activity.apps'), format.bytes(s.memUsed)], [t('activity.cache'), format.bytes(s.memCache)], [t('activity.free'), format.bytes(free)],
  ]
  return (
    <DetailChart title={t('activity.memory', { total: format.bytes(s.memTotal) })} figures={figures}>
      <AreaChart label={t('activity.memoryHistory')} height={220} max={s.memTotal} series={[
        { label: 'total', color: colors.info, values: seriesOf(h, 'memAll', memAll) },
        { label: 'apps', color: colors.primary, values: seriesOf(h, 'memApps', memApps) },
      ]} />
      <Legend items={[{ color: colors.primary, label: t('activity.apps') }, { color: colors.info, label: t('activity.appsAndCache') }]} />
    </DetailChart>
  )
}

export function NetworkView({ stats, range }: ViewProps) {
  const { t, format } = useI18n()
  const s = latestOf(stats)
  const h = stats.history[range]
  return (
    <DetailChart title={t('activity.network')}
      figures={[[t('activity.download'), format.rate(s.netRx)], [t('activity.upload'), format.rate(s.netTx)]]}>
      <AreaChart label={t('activity.networkHistory')} height={220} series={[
        { label: 'down', color: colors.info, values: seriesOf(h, 'rx', netRx) },
        { label: 'up', color: colors.primary, values: seriesOf(h, 'tx', netTx) },
      ]} />
      <Legend items={[{ color: colors.info, label: t('activity.download') }, { color: colors.primary, label: t('activity.upload') }]} />
    </DetailChart>
  )
}

export function StorageView({ stats }: ViewProps) {
  return (
    <ViewBody>
      <Volumes disks={latestOf(stats).disks} />
    </ViewBody>
  )
}

function unitColumns({ t, format }: I18n): Column<Unit>[] {
  return [
    { label: t('activity.col.service'), cell: (u) => <><Dot color={UNIT_COLORS[u.state] ?? colors.info} />{unitName(u.name)}</> },
    { label: t('activity.col.state'), cell: (u) => t(STATE_LABELS[u.state]) },
    { label: t('activity.col.for'), cell: (u) => format.since(u.since) },
    { label: t('activity.col.memory'), numeric: true, cell: (u) => format.bytes(u.mem) },
  ]
}

export function ServicesView({ stats }: ViewProps) {
  const i18n = useI18n()
  return <ViewBody><DataTable label={i18n.t('activity.services')} rows={stats.units} columns={unitColumns(i18n)} rowKey={(u) => u.name} /></ViewBody>
}
