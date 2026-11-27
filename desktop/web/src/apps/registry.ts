/**
 * The built-in apps. Each declares its window, menus, sections and catalogue
 * keys here, and the dock, the menu bar and the launcher derive from this
 * list. An app without a Body would show that it is coming; all have one now.
 */
import type { SystemInfo } from '../api'
import type { I18n, MessageKey } from '../i18n'
import type { Entry } from '../shell/search'
import { ACTIVITY_VIEWS, ActivityMonitor, VIEW_LABELS } from './activity/ActivityMonitor'
import { Browser } from './browser/Browser'
import { BROWSER_PASTE, BROWSER_QUIT } from './browser/commands'
import { Catalog } from './catalog/Catalog'
import { Console } from './console/Console'
import { Containers } from './containers/Containers'
import { Files } from './files/Files'
import { Trash } from './files/Trash'
import { SETTINGS_LABELS, SETTINGS_VIEWS, Settings } from './settings/Settings'
import { Terminal } from './terminal/Terminal'
import type { AppDef, AppMenu } from './types'

const FILE: AppMenu = { title: 'menu.file', items: [{ label: 'menu.closeWindow', run: (c) => c.close() }] }
const WINDOW: AppMenu = {
  title: 'menu.window',
  items: [{ label: 'menu.minimize', run: (c) => c.minimize() }, { label: 'menu.zoom', run: (c) => c.zoom() }],
}
const HELP: AppMenu = { title: 'menu.help', items: [{ label: 'menu.desktopHelp', run: (c) => c.about() }] }
const STANDARD = [FILE, WINDOW, HELP]

/** The Browser's menus: quitting it for everyone, and text to paste where the clipboard is not shared. */
const BROWSER_MENUS: AppMenu[] = [
  {
    title: 'menu.file',
    items: [
      { label: 'menu.closeWindow', run: (c) => c.close() },
      { label: 'menu.quitBrowser', run: (c) => c.command(BROWSER_QUIT) },
    ],
  },
  { title: 'menu.edit', items: [{ label: 'menu.pasteText', run: (c) => c.command(BROWSER_PASTE) }] },
  WINDOW,
  HELP,
]

const ACTIVITY = ACTIVITY_VIEWS.map((id) => ({ id, label: VIEW_LABELS[id] }))
const SETTINGS = SETTINGS_VIEWS.map((id) => ({ id, label: SETTINGS_LABELS[id] }))

/** The standard menus with a View menu of the app's sections. */
const withViews = (views: { id: string; label: MessageKey }[]): AppMenu[] => [
  FILE,
  { title: 'menu.view', items: views.map((v) => ({ label: v.label, run: (c) => c.setView(v.id) })) },
  WINDOW,
  HELP,
]

/** Ids that have a name in the catalogue: an app without one does not compile. */
type AppId = { [K in MessageKey]: K extends `app.${infer I}.name` ? I : never }[MessageKey]

function app(id: AppId, w: number, h: number, extra: Partial<AppDef> = {}): AppDef {
  return {
    id, name: `app.${id}.name`, blurb: `app.${id}.blurb`, size: { w, h }, placement: 'dock', menus: STANDARD, ...extra,
  }
}

export const APPS: AppDef[] = [
  app('activity', 980, 640, {
    Body: ActivityMonitor,
    views: ACTIVITY,
    menus: withViews(ACTIVITY),
  }),
  app('containers', 760, 600, { Body: Containers }),
  app('terminal', 760, 480, { Body: Terminal }),
  app('files', 860, 560, { Body: Files }),
  app('console', 860, 560, { Body: Console }),
  app('settings', 760, 560, { Body: Settings, views: SETTINGS, menus: withViews(SETTINGS) }),
  app('catalog', 860, 600, { Body: Catalog }),
  app('browser', 1100, 720, { Body: Browser, menus: BROWSER_MENUS, needs: 'browser' }),
  app('trash', 640, 440, { placement: 'end', Body: Trash }),
]

export const APP_BY_ID: Record<string, AppDef> = Object.fromEntries(APPS.map((a) => [a.id, a]))

/** Whether this server offers the app: one that needs nothing always does. */
export function offered(def: AppDef, system: SystemInfo | null): boolean {
  return def.needs === undefined || system?.[def.needs] === true
}

/** Apps that can be pinned, in default order. */
export const DOCKABLE = APPS.filter((a) => a.placement === 'dock').map((a) => a.id)

/** The pinnable apps this server offers (until its facts are known, those that need nothing). */
function offeredInDock(system: SystemInfo | null): AppDef[] {
  return APPS.filter((a) => a.placement === 'dock' && offered(a, system))
}

/** The ids of the pinnable apps this server offers. */
export function dockable(system: SystemInfo | null): string[] {
  return offeredInDock(system).map((a) => a.id)
}
/** Apps fixed at the dock's end. */
export const DOCK_END = APPS.filter((a) => a.placement === 'end').map((a) => a.id)

/** An app's name or blurb in the current language; unknown apps show their id. */
export function appText(t: I18n['t'], id: string, part: 'name' | 'blurb'): string {
  const def = APP_BY_ID[id]
  return def ? t(def[part]) : id
}

/** Everything the launcher can find, in the current language: the dockable apps this server offers, and their sections. */
export function launcherEntries(t: I18n['t'], system: SystemInfo | null = null): Entry[] {
  return offeredInDock(system).flatMap((a) => {
    const name = t(a.name)
    return [
      { id: `app:${a.id}`, title: name, subtitle: t(a.blurb), section: t('launcher.apps'), app: a.id },
      ...(a.views ?? []).map((v) => ({
        id: `${a.id}:${v.id}`, title: t(v.label), subtitle: t('launcher.section', { app: name }), section: name, app: a.id, view: v.id,
      })),
    ]
  })
}
