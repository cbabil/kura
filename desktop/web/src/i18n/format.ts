/**
 * Number, size, duration, date and time formatting for one language. The
 * decimal marks, duration words and dates come from Intl; the size unit
 * names come from the language's catalogue (unit.b … unit.pb), so a new
 * language brings its own ("5,8 Go"). Every formatter is built once.
 */

export interface Format {
  /** Binary sizes: one decimal under 10, none above ("5.8 GB", "28 MB"). */
  bytes(n: number | null): string
  rate(n: number): string
  /** 0 or 1 decimal places. */
  percent(n: number, digits?: 0 | 1): string
  /** The largest whole unit of time since `t` ("5 min", "3 days"). */
  since(t: number | null, now?: number): string
  /** Short weekday, day and month ("Tue, Nov 17"). */
  date(d: Date): string
  /** Hours and minutes. */
  time(d: Date): string
  /** Hours, minutes and seconds, for log lines. */
  clock(d: Date): string
}

const TIME_STEPS: [unit: 'day' | 'hour' | 'minute' | 'second', seconds: number][] = [
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
  ['second', 1],
]

/** `units`: the size unit names, bytes first. */
export function makeFormat(lang: string, units: readonly string[]): Format {
  const number = (digits: number) => new Intl.NumberFormat(lang, { maximumFractionDigits: digits })
  const percent = (digits: number) =>
    new Intl.NumberFormat(lang, { style: 'percent', minimumFractionDigits: digits, maximumFractionDigits: digits })
  const whole = number(0)
  const oneDecimal = number(1)
  const percents = [percent(0), percent(1)]
  const durations = new Map(
    TIME_STEPS.map(([unit]) => [unit, new Intl.NumberFormat(lang, { style: 'unit', unit, unitDisplay: 'short' })]),
  )
  const dateFmt = new Intl.DateTimeFormat(lang, { weekday: 'short', day: 'numeric', month: 'short' })
  const timeFmt = new Intl.DateTimeFormat(lang, { hour: '2-digit', minute: '2-digit' })
  const clockFmt = new Intl.DateTimeFormat(lang, { hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' })

  const bytes = (n: number | null): string => {
    if (n === null) return '—'
    let v = n
    let i = 0
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024
      i++
    }
    return `${(i === 0 || v >= 10 ? whole : oneDecimal).format(v)} ${units[i]}`
  }

  return {
    bytes,
    rate: (n) => `${bytes(n)}/s`,
    percent: (n, digits = 0) => percents[digits].format(n / 100),
    since(t, now = Date.now()) {
      if (t === null) return '—'
      const s = Math.max(0, Math.floor((now - t) / 1000))
      const [unit, size] = TIME_STEPS.find(([, sec]) => s >= sec) ?? TIME_STEPS[3]
      return (durations.get(unit) as Intl.NumberFormat).format(Math.floor(s / size))
    },
    date: (d) => dateFmt.format(d),
    time: (d) => timeFmt.format(d),
    clock: (d) => clockFmt.format(d),
  }
}
