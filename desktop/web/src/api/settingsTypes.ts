/**
 * The JSON contract of Settings (ADR-029): what GET /api/settings shows and
 * the one change POST /api/settings takes (kura-desktop-core's settings.rs).
 */

/** An Ethernet or Wi-Fi device as it is now. */
export interface NetworkDevice {
  name: string
  kind: 'ethernet' | 'wifi'
  connected: boolean
  /** The connection in use (a Wi-Fi network's name), or ''. */
  connection: string
  mac: string
  /** IPv4 addresses with their prefix, e.g. "192.168.1.50/24". */
  addresses: string[]
  gateway: string
  dns: string[]
}

/** The Ethernet address Kura was told to use. */
export interface EthernetConfig {
  method: 'auto' | 'manual'
  address: string
  gateway: string
  dns: string[]
}

export interface Person {
  name: string
  uid: number
  admin: boolean
}

/** GET /api/settings (administrators). */
export interface Settings {
  hostname: string
  network: {
    devices: NetworkDevice[]
    /** The saved Wi-Fi networks' names; passwords never leave the server. */
    wifi: string[]
    ethernet: EthernetConfig
    /** An address change waits to be kept, and goes back by itself if it is not. */
    pending: boolean
  }
  time: { zone: string; ntp: boolean; synced: boolean }
  users: Person[]
  /** How the disk layout went at first boot ("applied", "skipped: …"), or ''. */
  storage: string
  /** The local screen (ADR-033): on or off, or null on a server whose image has none. */
  screen: boolean | null
}

/** One change, the body of POST /api/settings (administrators). */
export type SettingChange =
  | { what: 'hostname'; name: string }
  | { what: 'timezone'; zone: string }
  | { what: 'ntp'; on: boolean }
  | { what: 'screen'; on: boolean }
  | { what: 'wifi-add'; ssid: string; password: string; hidden: boolean }
  | { what: 'wifi-remove'; ssid: string }
  | { what: 'ethernet-auto' }
  | { what: 'ethernet-static'; address: string; gateway: string; dns: string[] }
  | { what: 'network-confirm' }
  | { what: 'user-add'; name: string; password: string; admin: boolean }
  | { what: 'user-remove'; name: string }
  | { what: 'user-admin'; name: string; admin: boolean }
  | { what: 'user-password'; name: string; password: string }
