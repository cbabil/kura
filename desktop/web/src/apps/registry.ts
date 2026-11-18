/**
 * The built-in apps. Each declares its window, menus, sections and catalogue
 * keys here, and the dock, the menu bar and the launcher derive from this
 * list. Apps without a Body show what is coming (ADR-023: D2 Containers,
 * Terminal, Console; D3 Files, Settings; D4 App Catalog).
 */
import type { I18n, MessageKey } from '../i18n'
import type { Entry } from '../shell/search'
import { ACTIVITY_VIEWS, ActivityMonitor, VIEW_LABELS } from './activity/ActivityMonitor'
import type { AppDef, AppMenu } from './types'

const FILE: AppMenu = { title: 'menu.file', items: [{ label: 'menu.closeWindow', run: (c) => c.close() }] }
const WINDOW: AppMenu = {
  title: 'menu.window',
  items: [{ label: 'menu.minimize', run: (c) => c.minimize() }, { label: 'menu.zoom', run: (c) => c.zoom() }],
}
const HELP: AppMenu = { title: 'menu.help', items: [{ label: 'menu.desktopHelp', run: (c) => c.about() }] }
const STANDARD = [FILE, WINDOW, HELP]

const ACTIVITY = ACTIVITY_VIEWS.map((id) => ({ id, label: VIEW_LABELS[id] }))

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
    menus: [
      FILE,
      { title: 'menu.view', items: ACTIVITY.map((v) => ({ label: v.label, run: (c) => c.setView(v.id) })) },
      WINDOW,
      HELP,
    ],
  }),
  app('containers', 760, 600),
  app('terminal', 760, 480),
  app('files', 860, 560),
  app('console', 860, 560),
  app('settings', 760, 560),
  app('catalog', 860, 600),
  app('trash', 640, 440, { placement: 'end' }),
]

export const APP_BY_ID: Record<string, AppDef> = Object.fromEntries(APPS.map((a) => [a.id, a]))

/** Apps that can be pinned, in default order. */
export const DOCKABLE = APPS.filter((a) => a.placement === 'dock').map((a) => a.id)
/** Apps fixed at the dock's end. */
export const DOCK_END = APPS.filter((a) => a.placement === 'end').map((a) => a.id)

/** An app's name or blurb in the current language; unknown apps show their id. */
export function appText(t: I18n['t'], id: string, part: 'name' | 'blurb'): string {
  const def = APP_BY_ID[id]
  return def ? t(def[part]) : id
}

/** Everything the launcher can find, in the current language: dockable apps and their sections. */
export function launcherEntries(t: I18n['t']): Entry[] {
  return APPS.filter((a) => a.placement === 'dock').flatMap((a) => {
    const name = t(a.name)
    return [
      { id: `app:${a.id}`, title: name, subtitle: t(a.blurb), section: t('launcher.apps'), app: a.id },
      ...(a.views ?? []).map((v) => ({
        id: `${a.id}:${v.id}`, title: t(v.label), subtitle: t('launcher.section', { app: name }), section: name, app: a.id, view: v.id,
      })),
    ]
  })
}
