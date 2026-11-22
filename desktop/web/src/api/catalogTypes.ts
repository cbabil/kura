/**
 * The JSON contract of the App Catalog (ADR-032): the apps Kura ships as
 * fixed templates, what is installed of each, and the job that installs,
 * updates or removes one (kura-desktop-core's catalog.rs).
 */
import type { Job } from './appTypes'

/** One app of the catalog. */
export interface CatalogApp {
  id: string
  name: string
  /** The version this Kura installs. */
  version: string
  /** The port proposed for its page. */
  port: number
  /** Ports it also needs, which cannot be chosen. */
  fixedPorts: number[]
  shared: string[]
  homepage: string
  /** The port chosen and the version installed, or null. */
  installed: { port: number; version: string } | null
}

/** GET /api/catalog (administrators). */
export interface Catalog {
  apps: CatalogApp[]
  /** The last installation, update or removal, if one ran since the server started. */
  job: Job | null
}

/** POST /api/catalog. Only the port can be chosen; the rest is the template's. */
export type AppChange =
  | { what: 'install'; id: string; port: number }
  | { what: 'update'; id: string }
  /** `data` also deletes what the app kept. */
  | { what: 'remove'; id: string; data: boolean }
