/**
 * The JSON contract between the interface and kura-desktopd (ADR-023, D1).
 * kura-desktopd's Go handlers follow these shapes; keep both sides in step.
 */

/** The signed-in user, from GET /api/session and POST /api/login. */
export interface User {
  name: string
  uid: number
  /** Member of `sudo`: may run administrator actions (from D2). */
  admin: boolean
}

/** Why a sign-in was refused, from the error field of POST /api/login. */
export type LoginError = 'wrong' | 'expired' | 'rate' | 'network'

export type LoginResult =
  | { ok: true; user: User }
  | { ok: false; error: LoginError; retryAfter?: number }

/** Static facts about the device, from GET /api/system. */
export interface SystemInfo {
  hostname: string
  /** e.g. "Kura 0.6.0" */
  os: string
  kernel: string
  arch: string
  cores: number
  memTotal: number
  /** Seconds since boot, when the response was made. */
  uptime: number
}

export interface DiskUsage {
  mount: string
  used: number
  size: number
}

/** One measurement; rates are per second, sizes in bytes. */
export interface Sample {
  /** Unix time in milliseconds. */
  t: number
  /** 0..100 across all cores. */
  cpu: number
  memUsed: number
  memCache: number
  memTotal: number
  netRx: number
  netTx: number
  /** Highest temperature sensor, or null when the device has none. */
  tempC: number | null
  disks: DiskUsage[]
}

export type UnitState = 'active' | 'inactive' | 'failed' | 'activating' | 'deactivating'

/** A systemd service. */
export interface Unit {
  name: string
  state: UnitState
  /** Memory in bytes, or null when systemd does not account it. */
  mem: number | null
  /** Unix time in ms the unit last entered its state, or null. */
  since: number | null
}

/** A process among the busiest. */
export interface Proc {
  pid: number
  name: string
  user: string
  /** 0..100 of one core times cores, like top. */
  cpu: number
  mem: number
}

export type Range = '1h' | '24h'

/** History the server keeps: 1 h at one sample per 2 s, 24 h at one per minute. */
export const HOUR_POINTS = 1800
export const DAY_POINTS = 1440
export const DAY_STEP_MS = 60_000

/** Messages on the WebSocket /api/stats. */
export type StatsMessage =
  | { type: 'snapshot'; history: Record<Range, Sample[]>; units: Unit[]; procs: Proc[] }
  | { type: 'sample'; sample: Sample; units?: Unit[]; procs?: Proc[] }

export interface WindowGeometry {
  x: number
  y: number
  w: number
  h: number
}

export type ThemeChoice = 'dark' | 'light' | 'system'

/** Per-user preferences, GET and PUT /api/prefs (at most 64 KB). */
export interface Prefs {
  theme: ThemeChoice
  /** App ids in dock order. */
  dock: string[]
  windows: Record<string, WindowGeometry>
}

/** Everything the interface asks of the server. */
export interface Api {
  session(): Promise<User | null>
  login(user: string, password: string): Promise<LoginResult>
  logout(): Promise<void>
  system(): Promise<SystemInfo>
  prefs(): Promise<Prefs | null>
  savePrefs(prefs: Prefs): Promise<void>
  /** Opens the stats stream; returns a function that closes it. */
  stats(onMessage: (m: StatsMessage) => void): () => void
}
