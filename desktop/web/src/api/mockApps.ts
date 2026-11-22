/**
 * The mock API's containers, journal and terminal (see mock.ts): sample
 * stacks whose state changes when acted on, a short journal, and a small
 * demonstration shell. Kept close to kura-desktopd's own development helper.
 */
import { ApiError, type Api, type Container, type JournalEntry, type LogLine, type TerminalSession, type UpdateStatus, type User } from './types'

type Apps = Pick<Api, 'containers' | 'containerAction' | 'containerLogs' | 'journal' | 'terminal' | 'updates' | 'startUpdate' | 'power'>

const NOW = Date.now()
const DAY = 86400e3

const SAMPLES: [name: string, image: string, compose: [string, string] | null, running: boolean, port: number | null][] = [
  ['immich-server', 'ghcr.io/immich-app/immich-server:v2.3', ['immich', 'server'], true, 2283],
  ['immich-machine-learning', 'ghcr.io/immich-app/immich-ml:v2.3', ['immich', 'machine-learning'], true, null],
  ['immich-postgres', 'tensorchord/pgvecto-rs:pg16', ['immich', 'postgres'], true, null],
  ['immich-redis', 'redis:7-alpine', ['immich', 'redis'], true, null],
  ['jellyfin', 'jellyfin/jellyfin:10.11', null, true, 8096],
  ['homeassistant', 'ghcr.io/home-assistant/home-assistant:2026.11', null, true, 8123],
  ['pihole', 'pihole/pihole:2026.10', null, false, 8080],
]

const STATUS = { running: 'Up 3 days', exited: 'Exited (0) 2 hours ago' }

function sampleContainers(): Container[] {
  return SAMPLES.map(([name, image, compose, running, port], i) => ({
    id: (i + 10).toString(16).repeat(12),
    name,
    image,
    state: running ? 'running' : 'exited',
    status: running ? STATUS.running : STATUS.exited,
    created: NOW - 30 * DAY,
    project: compose?.[0] ?? null,
    service: compose?.[1] ?? null,
    ports: port ? [port] : [],
  }))
}

const JOURNAL: [unit: string, ident: string, priority: number, message: string][] = [
  ['kura-desktopd.service', 'kura-desktopd', 6, 'listening on https://[::]:443'],
  ['docker.service', 'dockerd', 6, 'Container immich-server started'],
  ['ssh.service', 'sshd', 6, 'Accepted publickey for kura from 192.168.1.20'],
  ['docker.service', 'dockerd', 4, 'immich-machine-learning ran out of memory and was restarted'],
  ['unattended-upgrades.service', 'unattended-upgrade', 6, 'No packages found that can be upgraded unattended'],
  ['ssh.service', 'sshd', 3, 'Failed password for invalid user admin from 192.168.1.77'],
  ['kura-helper.service', 'kura-helper', 6, 'authenticate user=kura ok=true'],
  ['systemd-timesyncd.service', 'systemd-timesyncd', 6, 'Synchronized to time server 162.159.200.1:123'],
]

const entries: { index: number; entry: JournalEntry }[] = JOURNAL.map(([unit, ident, priority, message], i) => ({
  index: i + 1,
  entry: { t: NOW - (JOURNAL.length - i - 1) * 90e3, priority, unit, ident, pid: 601 + i, message },
}))

function logs(name: string, lines: number): LogLine[] {
  const count = Math.min(lines, 40)
  return Array.from({ length: count }, (_, i) => {
    const slow = i % 9 === 8
    return {
      t: NOW - (count - 1 - i) * 60e3,
      stream: slow ? 'stderr' : 'stdout',
      text: slow ? `${name}: request took 2.1 s` : `${name}: handled request ${i + 1}`,
    }
  })
}

/** A shell good enough to show the terminal working: it echoes, and knows four commands. */
function shell(user: string, host: string, out: (text: string) => void, end: () => void): (typed: string) => void {
  const prompt = `${user}@${host}:~$ `
  let line = ''
  const run = (command: string) => {
    const [name, ...args] = command.trim().split(/\s+/)
    if (name === 'exit') return end()
    if (name === 'whoami') out(`${user}\r\n`)
    else if (name === 'hostname') out(`${host}\r\n`)
    else if (name === 'echo') out(`${args.join(' ')}\r\n`)
    else if (name) out(`${name}: not in this demonstration shell\r\n`)
    out(prompt)
  }
  out(prompt)
  return (typed) => {
    for (const ch of typed) {
      if (ch === '\r') {
        out('\r\n')
        const command = line
        line = ''
        run(command)
      } else if (ch === '\x7f') {
        if (line) out('\b \b')
        line = line.slice(0, -1)
      } else if (ch >= ' ') {
        line += ch
        out(ch)
      }
    }
  }
}

export function createMockApps(currentUser: () => User | null, host: string): Apps {
  const containers = sampleContainers()
  // Kura 0.6.1 with 0.6.2 waiting; installing it is done at once and asks for a restart
  const update: UpdateStatus = { current: '0.6.1', available: '0.6.2', restartRequired: false, job: null }
  const admin = () => {
    if (!currentUser()?.admin) throw new ApiError('admin')
  }
  const find = (id: string) => {
    const c = containers.find((x) => x.id === id)
    if (!c) throw new ApiError('not_found')
    return c
  }
  return {
    containers: async () => containers.map((c) => ({ ...c })),
    async containerAction(id, action) {
      admin()
      const c = find(id)
      c.state = action === 'stop' ? 'exited' : 'running'
      c.status = action === 'stop' ? 'Exited (0) 1 second ago' : 'Up 1 second'
    },
    async containerLogs(id, lines) {
      admin()
      return logs(find(id).name, lines)
    },
    async journal({ lines = 200, unit, priority, after }) {
      admin()
      const from = Number(after?.split('i=')[1] ?? 0)
      const matching = entries
        .filter(({ index, entry }) => index > from && (!unit || entry.unit === unit) && (priority === undefined || entry.priority <= priority))
        .slice(-lines)
      const last = matching.at(-1)
      return { entries: matching.map((e) => e.entry), cursor: last ? `s=mock;i=${last.index}` : null }
    },
    updates: async () => ({ ...update, job: update.job && { ...update.job, output: currentUser()?.admin ? update.job.output : [] } }),
    async startUpdate(what) {
      admin()
      if (what === 'check') {
        update.job = { state: 'done', output: ['Hit:1 https://deb.debian.org/debian trixie InRelease', 'Reading package lists...'] }
        return
      }
      Object.assign(update, { current: '0.6.2', available: null, restartRequired: true })
      update.job = { state: 'done', output: ['Unpacking kura (0.6.2) over (0.6.1) ...', 'Setting up kura (0.6.2) ...'] }
    },
    async power() {
      admin()
    },
    terminal(_size, handlers): TerminalSession {
      const encoder = new TextEncoder()
      const decoder = new TextDecoder()
      let open = true
      let type: (typed: string) => void = () => {}
      // Like a socket, it opens a moment after it is asked for.
      void Promise.resolve().then(() => {
        if (!open) return
        handlers.onOpen()
        type = shell(currentUser()?.name ?? 'kura', host, (text) => handlers.onData(encoder.encode(text)), () => {
          open = false
          handlers.onEnd('exit')
        })
      })
      return {
        write: (data) => open && type(typeof data === 'string' ? data : decoder.decode(data)),
        resize: () => {},
        close: () => {
          open = false
        },
      }
    },
  }
}
