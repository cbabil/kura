/** Number formatting for Activity Monitor: sizes, rates, percentages, ages. */

const UNITS = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']

/** Binary sizes: one decimal under 10, none above ("5.8 GB", "28 MB"). */
export function bytes(n: number | null): string {
  if (n === null) return '—'
  let v = n
  let i = 0
  while (v >= 1024 && i < UNITS.length - 1) {
    v /= 1024
    i++
  }
  const text = i === 0 || v >= 10 ? Math.round(v).toString() : (Math.round(v * 10) / 10).toString()
  return `${text} ${UNITS[i]}`
}

export const rate = (n: number) => `${bytes(n)}/s`

export function percent(n: number, digits = 0): string {
  return `${n.toFixed(digits)}%`
}

/** The largest whole unit of time since `t` ("5 min", "3 d"). */
export function since(t: number | null, now = Date.now()): string {
  if (t === null) return '—'
  const s = Math.max(0, Math.floor((now - t) / 1000))
  if (s < 60) return `${s} s`
  if (s < 3600) return `${Math.floor(s / 60)} min`
  if (s < 86400) return `${Math.floor(s / 3600)} h`
  return `${Math.floor(s / 86400)} d`
}

export const unitName = (name: string) => name.replace(/\.service$/, '')
