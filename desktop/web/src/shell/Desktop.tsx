/**
 * The signed-in desktop: wallpaper, menu bar, windows, dock and launcher.
 * Apps come from the registry; the desktop knows none of them by name except
 * Activity Monitor, which opens on arrival.
 */
import { useEffect, useMemo, useState } from 'react'
import { Box } from '@mui/material'
import type { Api, Prefs, User } from '../api'
import { APP_BY_ID, LAUNCHER_ENTRIES } from '../apps/registry'
import type { AppMenu, MenuCtx, MenuItem } from '../apps/types'
import type { Mode } from '../theme'
import { Dock } from './Dock'
import { normalizeDock } from './dockOrder'
import { Launcher } from './Launcher'
import { MenuBar } from './MenuBar'
import { About, Wallpaper } from './Panels'
import { useDesktop } from './useDesktop'
import { DesktopDataProvider, useSystem } from './useStats'
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
  const [about, setAbout] = useState(false)
  const { actions, state, bounds } = d

  useEffect(() => actions.open(FIRST_APP), [actions])

  const focused = d.focused ? APP_BY_ID[d.focused.app] : null
  const kuraMenu = useMemo<AppMenu>(() => ({
    title: '蔵',
    items: [{ label: 'About Kura', run: () => setAbout(true) }, { label: `Sign Out ${user.name}`, run: onSignOut }],
  }), [user.name, onSignOut])
  const run = (item: MenuItem) => {
    const app = d.focused?.app ?? ''
    const ctx: MenuCtx = {
      close: () => actions.close(app),
      minimize: () => actions.minimize(app),
      zoom: () => actions.zoom(app),
      setView: (v) => actions.setView(app, v),
      about: () => setAbout(true),
    }
    item.run(ctx)
  }
  const pinned = useMemo(() => normalizeDock(prefs.dock), [prefs.dock])
  const minimized = state.order.filter((a) => state.windows[a].minimized)

  return (
    <Box sx={{ position: 'fixed', inset: 0, overflow: 'hidden', color: 'text.primary' }}>
      <Wallpaper hostname={system?.hostname ?? 'kura'} />
      <MenuBar appName={focused?.name ?? 'Kura'} kuraMenu={kuraMenu} menus={focused?.menus ?? []} compact={bounds.compact}
        mode={mode} onRun={run} onToggleTheme={() => onPrefs({ theme: mode === 'dark' ? 'light' : 'dark' })}
        onLauncher={() => d.setLauncher(true)} />
      {state.order.map((app, i) => {
        const isFocused = d.focused?.app === app
        // On a phone only the front window shows.
        if (bounds.compact && !isFocused && !state.windows[app].minimized) return null
        const def = APP_BY_ID[app]
        return (
          <Window key={app} win={state.windows[app]} def={def} focused={isFocused} bounds={bounds} z={10 + i}
            view={d.views[app] ?? def.views?.[0] ?? ''} actions={actions} />
        )
      })}
      <Dock pinned={pinned} running={state.order} minimized={minimized} compact={bounds.compact}
        onOpen={actions.open} onPinnedChange={(dock) => onPrefs({ dock })} />
      {d.launcher && (
        <Launcher entries={LAUNCHER_ENTRIES} onClose={() => d.setLauncher(false)}
          onChoose={(entry) => {
            actions.open(entry.app, entry.view)
            d.setLauncher(false)
          }} />
      )}
      <About open={about} system={system} onClose={() => setAbout(false)} />
    </Box>
  )
}

export function Desktop({ api, ...rest }: Props) {
  return (
    <DesktopDataProvider api={api}>
      <DesktopView {...rest} />
    </DesktopDataProvider>
  )
}
