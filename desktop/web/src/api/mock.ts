/**
 * An in-browser stand-in for kura-desktopd, used by `bun run dev` and the
 * Playwright tests (VITE_MOCK=1). Any user name signs in with MOCK_PASSWORD;
 * the user "expired" gets the expired-password refusal and "guest" is not
 * an administrator. Containers, the journal and the terminal: mockApps.ts.
 */
import { DAY_POINTS, DAY_STEP_MS, HOUR_POINTS } from './types'
import { createMockApps } from './mockApps'
import { createMockCatalog } from './mockCatalog'
import { createMockFiles } from './mockFiles'
import { createMockSettings } from './mockSettings'
import type { Api, Prefs, Proc, Sample, StatsMessage, SystemInfo, Unit, User } from './types'

export const MOCK_PASSWORD = 'kura'
const GB = 1024 ** 3
const SAMPLE_MS = 2000

const system: SystemInfo = {
  hostname: 'kura-nuc',
  os: 'Kura 0.6.0',
  kernel: '6.12.48-amd64',
  arch: 'x86_64',
  cores: 4,
  memTotal: 16 * GB,
  uptime: 3 * 86400 + 4 * 3600,
}

/** A smooth pseudo-random wave so charts look alive but tests stay stable. */
function wave(t: number, base: number, amp: number, period: number): number {
  return base + amp * (Math.sin(t / period) * 0.6 + Math.sin(t / (period * 0.37)) * 0.4)
}

export function sampleAt(t: number): Sample {
  const s = t / 1000
  return {
    t,
    cpu: Math.max(1, Math.min(100, wave(s, 18, 12, 300))),
    memUsed: wave(s, 3.9, 0.3, 1200) * GB,
    memCache: 1.9 * GB,
    memTotal: system.memTotal,
    netRx: Math.max(0, wave(s, 2.5, 2.2, 400)) * 1024 ** 2,
    netTx: Math.max(0, wave(s, 0.4, 0.3, 500)) * 1024 ** 2,
    tempC: Math.round(wave(s, 48, 4, 200)),
    disks: [
      { mount: '/', used: 6.1 * GB, size: 20 * GB },
      { mount: '/var/lib/docker', used: 31 * GB, size: 40 * GB },
      { mount: '/srv', used: 41 * GB, size: 50 * GB },
      { mount: '/home', used: 12.7 * GB, size: 40 * GB },
    ],
  }
}

function history(now: number, count: number, stepMs: number): Sample[] {
  return Array.from({ length: count }, (_, i) => sampleAt(now - (count - 1 - i) * stepMs))
}

const MB = 1024 ** 2
const BOOT = Date.now() - 3 * 86400e3
const units: Unit[] = [
  { name: 'docker.service', state: 'active', mem: 96 * MB, since: BOOT },
  { name: 'kura-desktopd.service', state: 'active', mem: 28 * MB, since: BOOT },
  { name: 'kura-helper.service', state: 'active', mem: 9 * MB, since: BOOT },
  { name: 'ssh.service', state: 'active', mem: 6 * MB, since: BOOT },
  { name: 'NetworkManager.service', state: 'active', mem: 14 * MB, since: BOOT },
  { name: 'unattended-upgrades.service', state: 'active', mem: 21 * MB, since: Date.now() - 86400e3 },
  { name: 'kura-issue.service', state: 'inactive', mem: null, since: Date.now() - 60e3 },
]

const procs: Proc[] = [
  { pid: 2211, name: 'immich-server', user: 'root', cpu: 6.4, mem: 812 * MB },
  { pid: 1980, name: 'jellyfin', user: 'root', cpu: 3.1, mem: 604 * MB },
  { pid: 2048, name: 'python3 (homeassistant)', user: 'root', cpu: 1.8, mem: 421 * MB },
  { pid: 811, name: 'dockerd', user: 'root', cpu: 0.9, mem: 96 * MB },
  { pid: 902, name: 'kura-desktopd', user: 'kura-desktop', cpu: 0.3, mem: 28 * MB },
  { pid: 640, name: 'sshd', user: 'root', cpu: 0, mem: 6 * MB },
]

export function createMockApi(): Api {
  let user: User | null = null
  let prefs: Prefs | null = null
  return {
    session: async () => user,
    async login(name, password) {
      if (password !== MOCK_PASSWORD) return { ok: false, error: 'wrong' }
      if (name === 'expired') return { ok: false, error: 'expired' }
      user = { name, uid: 1000, admin: name !== 'guest' }
      return { ok: true, user }
    },
    async logout() {
      user = null
    },
    system: async () => system,
    prefs: async () => prefs,
    async savePrefs(next) {
      prefs = next
    },
    stats(onMessage: (m: StatsMessage) => void) {
      const now = Date.now()
      const hist = { '1h': history(now, HOUR_POINTS, SAMPLE_MS), '24h': history(now, DAY_POINTS, DAY_STEP_MS) }
      onMessage({ type: 'snapshot', history: hist, units, procs })
      const timer = setInterval(() => onMessage({ type: 'sample', sample: sampleAt(Date.now()) }), SAMPLE_MS)
      return () => clearInterval(timer)
    },
    ...createMockApps(() => user, system.hostname),
    ...createMockSettings(() => user, system.hostname, MOCK_PASSWORD),
    ...createMockFiles(),
    ...createMockCatalog(() => user),
  }
}
