/**
 * The root: checks the session, then shows the sign-in page or the desktop,
 * in the user's chosen theme (or the system's, before sign-in).
 */
import { useEffect, useMemo, useState } from 'react'
import { CssBaseline, Snackbar, useMediaQuery } from '@mui/material'
import { ThemeProvider } from '@mui/material/styles'
import type { Api, User } from './api'
import { Desktop } from './shell/Desktop'
import { SignIn } from './signin/SignIn'
import { makeTheme, type Mode } from './theme'
import { usePrefs } from './usePrefs'

export function App({ api }: { api: Api }) {
  /** undefined while the session check runs. */
  const [user, setUser] = useState<User | null | undefined>(undefined)
  const { prefs, update, saveFailed, dismissSaveError } = usePrefs(api, Boolean(user))
  const systemDark = useMediaQuery('(prefers-color-scheme: dark)', { noSsr: true })
  const mode: Mode = prefs.theme === 'system' ? (systemDark ? 'dark' : 'light') : prefs.theme
  const theme = useMemo(() => makeTheme(user ? mode : systemDark ? 'dark' : 'light'), [user, mode, systemDark])

  useEffect(() => {
    api.session().then(setUser, () => setUser(null))
  }, [api])

  const signOut = async () => {
    await api.logout().catch(() => undefined) // signed out locally either way
    setUser(null)
  }

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      {user === null && <SignIn api={api} onSignedIn={setUser} />}
      {user && <Desktop api={api} user={user} prefs={prefs} mode={mode} onPrefs={update} onSignOut={signOut} />}
      <Snackbar open={saveFailed} onClose={dismissSaveError} autoHideDuration={5000}
        message="Your desktop layout could not be saved. It will be tried again on the next change." />
    </ThemeProvider>
  )
}
