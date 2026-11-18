/**
 * The built-in apps. Each declares its window, menus and sections here, and
 * the dock, the menu bar and the launcher derive from this list. Apps without
 * a Body show what is coming (ADR-023: D2 Containers, Terminal, Console;
 * D3 Files, Settings; D4 App Catalog).
 */
import type { Entry } from '../shell/search'
import { ACTIVITY_VIEWS, ActivityMonitor } from './activity/ActivityMonitor'
import type { AppDef, AppMenu } from './types'

const FILE: AppMenu = { title: 'File', items: [{ label: 'Close Window', run: (c) => c.close() }] }
const WINDOW: AppMenu = {
  title: 'Window',
  items: [{ label: 'Minimize', run: (c) => c.minimize() }, { label: 'Zoom', run: (c) => c.zoom() }],
}
const HELP: AppMenu = { title: 'Help', items: [{ label: 'Kura Desktop Help', run: (c) => c.about() }] }
const STANDARD = [FILE, WINDOW, HELP]

function app(id: string, name: string, blurb: string, w: number, h: number, extra: Partial<AppDef> = {}): AppDef {
  return { id, name, blurb, size: { w, h }, placement: 'dock', menus: STANDARD, ...extra }
}

export const APPS: AppDef[] = [
  app('activity', 'Activity Monitor', 'CPU, memory, storage, network and services', 980, 640, {
    Body: ActivityMonitor,
    views: ACTIVITY_VIEWS,
    menus: [FILE, { title: 'View', items: ACTIVITY_VIEWS.map((v) => ({ label: v, run: (c) => c.setView(v) })) }, WINDOW, HELP],
  }),
  app('containers', 'Containers', 'Docker apps and compose stacks', 760, 600),
  app('terminal', 'Terminal', 'A shell on this server, in a window', 760, 480),
  app('files', 'Files', 'Browse, upload and download your data', 860, 560),
  app('console', 'Console', 'The system logs', 860, 560),
  app('settings', 'Settings', 'Network, users, time, storage and updates', 760, 560),
  app('catalog', 'App Catalog', 'Install apps in one click', 860, 600),
  app('trash', 'Trash', 'Deleted files, kept until you empty it', 640, 440, { placement: 'end' }),
]

export const APP_BY_ID: Record<string, AppDef> = Object.fromEntries(APPS.map((a) => [a.id, a]))

/** Apps that can be pinned, in default order. */
export const DOCKABLE = APPS.filter((a) => a.placement === 'dock').map((a) => a.id)
/** Apps fixed at the dock's end. */
export const DOCK_END = APPS.filter((a) => a.placement === 'end').map((a) => a.id)

/** Everything the launcher can find: dockable apps and their sections. */
export const LAUNCHER_ENTRIES: Entry[] = APPS.filter((a) => a.placement === 'dock').flatMap((a) => [
  { id: `app:${a.id}`, title: a.name, subtitle: a.blurb, section: 'Apps', app: a.id },
  ...(a.views ?? []).map((v) => ({ id: `${a.id}:${v}`, title: v, subtitle: `${a.name} section`, section: a.name, app: a.id, view: v })),
])
