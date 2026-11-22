/**
 * The mock API's Settings (see mock.ts): a small device whose settings
 * change when asked, with the server's own rules for what is refused.
 */
import { ApiError, type Api, type SettingChange, type Settings, type User } from './types'

type Part = Pick<Api, 'settings' | 'changeSetting' | 'changePassword'>

const HOST = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/
const USER = /^[a-z_][a-z0-9_-]{0,31}$/
const SSID = /^[a-zA-Z0-9][a-zA-Z0-9 _.-]*$/
const IPV4 = /^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$/

function initial(host: string): Settings {
  return {
    hostname: host,
    network: {
      devices: [
        { name: 'enp1s0', kind: 'ethernet', connected: true, connection: 'Wired connection 1', mac: 'AA:BB:CC:00:11:22',
          addresses: ['192.168.1.50/24'], gateway: '192.168.1.1', dns: ['192.168.1.1'] },
        { name: 'wlp2s0', kind: 'wifi', connected: false, connection: '', mac: 'AA:BB:CC:00:11:33', addresses: [], gateway: '', dns: [] },
      ],
      wifi: ['Attic'],
      ethernet: { method: 'auto', address: '', gateway: '', dns: [] },
      pending: false,
    },
    time: { zone: 'Europe/Paris', ntp: true, synced: true },
    users: [
      { name: 'chris', uid: 1000, admin: true },
      { name: 'anna', uid: 1001, admin: true },
      { name: 'guest', uid: 1002, admin: false },
    ],
    storage: 'applied',
    screen: false,
    rdp: false,
  }
}

const invalid = (ok: boolean) => {
  if (!ok) throw new ApiError('bad_request')
}

/** Applies one change the way the server would, or refuses it. */
function apply(s: Settings, c: SettingChange, me: string): void {
  const person = (name: string) => {
    const found = s.users.find((u) => u.name === name)
    invalid(Boolean(found))
    return found!
  }
  const lastAdmin = (name: string) => s.users.filter((u) => u.admin && u.name !== name).length === 0
  switch (c.what) {
    case 'hostname': invalid(HOST.test(c.name)); s.hostname = c.name; break
    case 'timezone': invalid(/^[\w+-]+(\/[\w+-]+){0,2}$/.test(c.zone)); s.time.zone = c.zone; break
    case 'ntp': s.time = { ...s.time, ntp: c.on, synced: c.on }; break
    case 'screen': invalid(s.screen !== null); s.screen = c.on; break
    case 'rdp': invalid(s.rdp !== null); s.rdp = c.on; break
    case 'wifi-add':
      invalid(SSID.test(c.ssid) && c.password.length >= 8 && c.password.length <= 63)
      s.network.wifi = [...s.network.wifi.filter((w) => w !== c.ssid), c.ssid]
      break
    case 'wifi-remove': s.network.wifi = s.network.wifi.filter((w) => w !== c.ssid); break
    case 'ethernet-auto': s.network.ethernet = { method: 'auto', address: '', gateway: '', dns: [] }; s.network.pending = true; break
    case 'ethernet-static': {
      const [address, prefix] = c.address.split('/')
      invalid(IPV4.test(address ?? '') && Number(prefix) >= 1 && Number(prefix) <= 32 && IPV4.test(c.gateway))
      invalid(c.dns.length > 0 && c.dns.every((d) => IPV4.test(d)))
      s.network.ethernet = { method: 'manual', address: c.address, gateway: c.gateway, dns: c.dns }
      s.network.pending = true
      break
    }
    case 'network-confirm': s.network.pending = false; break
    case 'user-add':
      invalid(USER.test(c.name) && c.password.length > 0 && !s.users.some((u) => u.name === c.name))
      s.users = [...s.users, { name: c.name, uid: 1000 + s.users.length, admin: c.admin }]
      break
    case 'user-remove':
      invalid(c.name !== me)
      if (person(c.name).admin && lastAdmin(c.name)) throw new ApiError('unavailable')
      s.users = s.users.filter((u) => u.name !== c.name)
      break
    case 'user-admin':
      if (!c.admin && person(c.name).admin && lastAdmin(c.name)) throw new ApiError('unavailable')
      person(c.name).admin = c.admin
      break
    case 'user-password': invalid(c.password.length > 0); person(c.name); break
  }
}

export function createMockSettings(currentUser: () => User | null, host: string, mockPassword: string): Part {
  const state = initial(host)
  const admin = () => {
    if (!currentUser()?.admin) throw new ApiError('admin')
  }
  return {
    async settings() {
      admin()
      return structuredClone(state)
    },
    async changeSetting(change) {
      admin()
      apply(state, change, currentUser()?.name ?? '')
    },
    async changePassword(current, password) {
      if (!currentUser()) throw new ApiError('signed_out')
      if (current !== mockPassword || password.length === 0) throw new ApiError('bad_request')
    },
  }
}
