/**
 * The signed-in desktop: wallpaper, menu bar, windows, dock and launcher.
 * Apps come from the registry; the desktop knows none of them by name except
 * Activity Monitor, which opens on arrival.
 */
import { useEffect, useMemo, useState } from 'react'
import { Box } from '@mui/material'
import type { Api, PowerKind, Prefs, User } from '../api'
import { APP_BY_ID, appText, dockable, launcherEntries } from '../apps/registry'
import type { AppMenu, MenuCtx, MenuItem } from '../apps/types'
import { useI18n } from '../i18n'
import type { Mode } from '../theme'
import { Dock } from './Dock'
import { keepHidden, normalizeDock } from './dockOrder'
import { LanguageDialog } from './LanguageDialog'
import { Launcher } from './Launcher'
import { MenuBar } from './MenuBar'
import { About, Wallpaper } from './Panels'
import { PowerDialog } from './PowerDialog'
import { useDesktop } from './useDesktop'
import { DesktopDataProvider, useSystem } from './DesktopData'
import { Window } from './Window'

interface Props {
  api: Api
  user: User
  prefs: Prefs
  mode: Mode
  onPrefs(p: Partial<Prefs>): void
  onSignOut(): void
}

const FIRST_APP = 'activity'


function DesktopView({ user, prefs, mode, onPrefs, onSignOut }: Omit<Props, 'api'>) {
  const d = useDesktop(prefs, onPrefs)
  const system = useSystem()
  const { t } = useI18n()
  const [about, setAbout] = useState(false)
  const [language, setLanguage] = useState(false)
  const [power, setPower] = useState<PowerKind | null>(null)
  const { actions, state, bounds } = d

  useEffect(() => actions.open(FIRST_APP), [actions])

  const focused = d.focused ? APP_BY_ID[d.focused.app] : null
  const kuraMenu = useMemo<AppMenu>(() => ({
    title: '蔵',
    items: [
      { label: 'menu.about', run: () => setAbout(true) },
      { label: 'menu.language', run: () => setLanguage(true) },
      // Switching the server off is for administrators (the server checks too)
      ...(user.admin
        ? [{ label: 'menu.restart' as const, run: () => setPower('restart') }, { label: 'menu.shutdown' as const, run: () => setPower('shutdown') }]
        : []),
      { label: 'menu.signOut', vars: { name: user.name }, run: onSignOut },
    ],
  }), [user.name, user.admin, onSignOut])
  const entries = useMemo(() => launcherEntries(t, system), [t, system])
  const run = (item: MenuItem) => {
    const app = d.focused?.app ?? ''
    const ctx: MenuCtx = {
      close: () => actions.close(app),
      minimize: () => actions.minimize(app),
      zoom: () => actions.zoom(app),
      setView: (v) => actions.setView(app, v),
      about: () => setAbout(true),
      command: (name) => actions.command(app, name),
    }
    item.run(ctx)
  }
  const pinned = useMemo(() => normalizeDock(prefs.dock, dockable(system)), [prefs.dock, system])
  const minimized = state.order.filter((a) => state.windows[a].minimized)

  return (
    <Box sx={{ position: 'fixed', inset: 0, overflow: 'hidden', color: 'text.primary' }}>
      <Wallpaper hostname={system?.hostname ?? 'kura'} version={system?.version ?? ''} />
      <MenuBar appName={focused ? appText(t, focused.id, 'name') : 'Kura'} kuraMenu={kuraMenu} menus={focused?.menus ?? []} compact={bounds.compact}
        mode={mode} onRun={run} onToggleTheme={() => onPrefs({ theme: mode === 'dark' ? 'light' : 'dark' })}
        onLauncher={() => d.setLauncher(true)} onUpdates={() => actions.open('settings', 'Updates')} />
      {state.order.map((app, i) => {
        const isFocused = d.focused?.app === app
        // On a phone only the front window shows.
        if (bounds.compact && !isFocused && !state.windows[app].minimized) return null
        const def = APP_BY_ID[app]
        return (
          <Window key={app} win={state.windows[app]} def={def} focused={isFocused} bounds={bounds} z={10 + i}
            view={d.views[app] ?? def.views?.[0]?.id ?? ''} command={d.commands[app] ?? null} actions={actions} />
        )
      })}
      <Dock pinned={pinned} running={state.order} minimized={minimized} compact={bounds.compact}
        onOpen={actions.open} onQuit={actions.close} onPinnedChange={(dock) => onPrefs({ dock: keepHidden(dock, prefs.dock, pinned) })} />
      {d.launcher && (
        <Launcher entries={entries} onClose={() => d.setLauncher(false)}
          onChoose={(entry) => {
            actions.open(entry.app, entry.view)
            d.setLauncher(false)
          }} />
      )}
      <About open={about} system={system} onClose={() => setAbout(false)} />
      <PowerDialog how={power} onClose={() => setPower(null)} />
      <LanguageDialog open={language} choice={prefs.language} onClose={() => setLanguage(false)}
        onChoose={(choice) => onPrefs({ language: choice })} />
    </Box>
  )
}

export function Desktop({ api, ...rest }: Props) {
  return (
    <DesktopDataProvider api={api} user={rest.user}>
      <DesktopView {...rest} />
    </DesktopDataProvider>
  )
}
