/**
 * Small, dependency-free SVG charts for Activity Monitor. Series are
 * downsampled and cached per history array, which the stats store replaces
 * (never mutates), so re-renders between samples reuse the work.
 */
import { Box } from '@mui/material'
import type { Sample } from '../../api'

/** More points than this are averaged into buckets: a 1 h series has 1800. */
export const MAX_POINTS = 150
const W = 600

/** Averages `values` into at most `n` buckets, so a long series reads as a trend, not a zigzag. */
export function downsample(values: number[], n = MAX_POINTS): number[] {
  if (values.length <= n) return values
  const size = values.length / n
  const out: number[] = []
  let start = 0
  for (let i = 1; i <= n; i++) {
    const end = Math.floor(i * size)
    let sum = 0
    for (let j = start; j < end; j++) sum += values[j]
    out.push(sum / (end - start))
    start = end
  }
  return out
}

const cache = new WeakMap<Sample[], Map<string, number[]>>()

/** The downsampled series `key` of a history, computed once per history array. */
export function seriesOf(history: Sample[], key: string, pick: (s: Sample) => number): number[] {
  let byKey = cache.get(history)
  if (!byKey) cache.set(history, (byKey = new Map()))
  let values = byKey.get(key)
  if (!values) byKey.set(key, (values = downsample(history.map(pick))))
  return values
}

export interface Series {
  values: number[]
  color: string
  label: string
}

function path(values: number[], max: number, h: number): string {
  const step = values.length > 1 ? W / (values.length - 1) : W
  return values.map((v, i) => `${(i * step).toFixed(1)},${(h - (Math.min(v, max) / max) * h).toFixed(1)}`).join(' L')
}

/** Filled line chart; series are drawn in order, so put the largest first. */
export function AreaChart({ series, max, height, label }: { series: Series[]; max?: number; height: number; label: string }) {
  const top = max ?? Math.max(1, ...series.flatMap((s) => s.values))
  return (
    <svg role="img" aria-label={label} viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none"
      style={{ width: '100%', height, display: 'block' }}>
      {series.filter((s) => s.values.length > 0).map((s) => {
        const line = path(s.values, top, height)
        return (
          <g key={s.label}>
            <path d={`M0,${height} L${line} L${W},${height} Z`} fill={s.color} fillOpacity={0.18} />
            <path d={`M${line}`} fill="none" stroke={s.color} strokeWidth={1.6} vectorEffect="non-scaling-stroke" />
          </g>
        )
      })}
    </svg>
  )
}

/** A horizontal bar split into coloured parts of a total. */
export function Meter({ parts, total, label }: { parts: { value: number; color: string }[]; total: number; label: string }) {
  const used = parts.reduce((a, p) => a + p.value, 0)
  return (
    <Box role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={total} aria-valuenow={used}
      sx={{ height: 6, borderRadius: 3, bgcolor: 'divider', overflow: 'hidden', display: 'flex' }}>
      {parts.map((p, i) => (
        <Box key={i} sx={{ height: '100%', bgcolor: p.color, width: `${total > 0 ? (p.value / total) * 100 : 0}%` }} />
      ))}
    </Box>
  )
}
