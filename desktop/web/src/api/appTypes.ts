/**
 * The JSON contract of the D2 apps (ADR-027): Containers, Console and
 * Terminal. kura-desktopd passes on what kura-helper answers in these
 * shapes (kura-desktop-core's containers.rs and journal.rs).
 */

/** A Docker container, from GET /api/containers. */
export interface Container {
  id: string
  name: string
  image: string
  /** Docker's state: running, exited, paused, restarting, created, dead. */
  state: string
  /** Docker's own words, e.g. "Up 3 days"; shown as they are. */
  status: string
  /** Unix time in ms the container was created. */
  created: number
  /** The compose project and service, or null for a container started alone. */
  project: string | null
  service: string | null
  /** Published host ports. */
  ports: number[]
}

export type ContainerAction = 'start' | 'stop' | 'restart'

/** One line of a container's output, from GET /api/containers/{id}/logs. */
export interface LogLine {
  /** Unix time in ms, or null when the line carries none. */
  t: number | null
  stream: 'stdout' | 'stderr'
  text: string
}

/** One entry of the system journal. */
export interface JournalEntry {
  /** Unix time in ms. */
  t: number
  /** syslog priority: 0 (emergency) to 7 (debug). */
  priority: number
  /** The systemd unit, or ''. */
  unit: string
  /** The program's name, or ''. */
  ident: string
  pid: number | null
  message: string
}

/** GET /api/journal: entries oldest first, and the cursor to ask for what follows. */
export interface JournalPage {
  entries: JournalEntry[]
  cursor: string | null
}

export interface JournalFilter {
  /** How many of the newest entries (at most 1000; the server's default is 200). */
  lines?: number
  unit?: string
  /** This priority and more serious ones. */
  priority?: number
  /** Only entries after this cursor. */
  after?: string
}

/** Why the server refused a request (its `error` field), or 'network' when it did not answer. */
export const API_ERROR_CODES = ['signed_out', 'admin', 'not_found', 'bad_request', 'busy', 'no_shell', 'unavailable', 'network', 'exists', 'denied', 'other_volume', 'failed'] as const
export type ApiErrorCode = (typeof API_ERROR_CODES)[number]

export class ApiError extends Error {
  readonly code: ApiErrorCode
  constructor(code: ApiErrorCode) {
    super(code)
    this.code = code
  }
}

/** How a terminal ended: the shell exited, the connection dropped, or it never opened. */
export type TerminalEnd = 'exit' | 'lost' | 'refused'

export interface TerminalHandlers {
  onOpen(): void
  /** Bytes the shell wrote. */
  onData(bytes: Uint8Array): void
  onEnd(reason: TerminalEnd): void
}

/** An open terminal on the WebSocket /api/terminal. */
export interface TerminalSession {
  /** Sends what was typed. */
  write(data: string | Uint8Array): void
  resize(cols: number, rows: number): void
  close(): void
}

/** A job the server runs on its own (an update), from GET /api/updates. */
export interface Job {
  state: 'running' | 'done' | 'failed'
  /** The last lines it wrote; empty for a user who is not an administrator. */
  output: string[]
}

/** GET /api/updates. Installing is the owner's decision; nothing restarts by itself. */
export interface UpdateStatus {
  /** The installed Kura version, or '' when the device cannot say. */
  current: string
  /** The newer version waiting, or null. */
  available: string | null
  restartRequired: boolean
  /** The last check or installation since the machine started, or null. */
  job: Job | null
}

/** 'check' refreshes the list of versions; 'install' installs what waits. */
export type UpdateKind = 'check' | 'install'
export type PowerKind = 'restart' | 'shutdown'
