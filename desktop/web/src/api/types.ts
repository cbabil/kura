/**
 * The JSON contract between the interface and kura-desktopd (ADR-023,
 * ADR-027). kura-desktopd's handlers follow these shapes; keep both sides
 * in step. The shapes of the D2 apps (containers, journal, terminal) are in
 * appTypes.ts and re-exported here.
 */
import type { AppChange, Catalog } from './catalogTypes'
import type { FileChange, Folder, Trashed } from './filesTypes'
import type { SettingChange, Settings } from './settingsTypes'
import type { Container, ContainerAction, JournalFilter, JournalPage, LogLine, PowerKind, TerminalHandlers, TerminalSession, UpdateKind, UpdateStatus } from './appTypes'

export * from './appTypes'
export * from './catalogTypes'
export * from './filesTypes'
export * from './settingsTypes'

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
  /** Whether the shared Browser (ADR-036) can run on this server. */
  browser: boolean
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
  /** 'auto' (the browser's languages) or a language code the desktop has, e.g. 'fr'. */
  language: string
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
  /** The requests below reject with an ApiError. */
  containers(): Promise<Container[]>
  containerAction(id: string, action: ContainerAction): Promise<void>
  containerLogs(id: string, lines: number): Promise<LogLine[]>
  journal(filter: JournalFilter): Promise<JournalPage>
  updates(): Promise<UpdateStatus>
  startUpdate(what: UpdateKind): Promise<void>
  /** Restarts or shuts down the server; the connection goes soon after. */
  power(how: PowerKind): Promise<void>
  settings(): Promise<Settings>
  changeSetting(change: SettingChange): Promise<void>
  /** One's own password; the current one proves who asks. */
  changePassword(current: string, password: string): Promise<void>
  /** The apps Kura ships and the last job (administrators). */
  catalog(): Promise<Catalog>
  /** Starts installing, updating or removing one app. */
  changeApp(change: AppChange): Promise<void>
  /** A folder of the signed-in user's own view of the disk; their home when no path is given. */
  files(path?: string): Promise<Folder>
  fileChange(change: FileChange): Promise<void>
  trash(): Promise<Trashed[]>
  /** Where a file's bytes are: a download, or shown in the page when `inline` and it is a picture or plain text. */
  fileUrl(path: string, inline?: boolean): string
  /** A text file's content, for a preview. */
  fileText(path: string): Promise<string>
  /** A new file at `path`; refused when something is there. */
  upload(path: string, data: Blob): Promise<void>
  /** Opens a shell of `size` for the signed-in user. */
  terminal(size: { cols: number; rows: number }, handlers: TerminalHandlers): TerminalSession
  /** Opens the shared Browser's screen (ADR-036): the channel noVNC speaks RFB over. */
  browser(): BrowserChannel
  /** Quits the shared Browser, for everyone watching it. */
  browserStop(): Promise<void>
}

/**
 * What noVNC needs of a connection: a WebSocket has all of it. The mock
 * build hands it a stand-in server of its own instead.
 */
export interface BrowserChannel {
  binaryType: string
  readonly protocol: string
  readonly readyState: number
  send(data: ArrayBuffer | ArrayBufferView): void
  close(): void
  onopen: ((event: Event) => void) | null
  onmessage: ((event: MessageEvent) => void) | null
  onclose: ((event: CloseEvent) => void) | null
  onerror: ((event: Event) => void) | null
}
