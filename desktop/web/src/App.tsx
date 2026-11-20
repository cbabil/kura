/**
 * The root: checks the session, then shows the sign-in page or the desktop,
 * in the user's chosen theme and language (the system's and the browser's
 * before sign-in).
 */
import { useEffect, useMemo, useState } from 'react'
import { CssBaseline, Snackbar, useMediaQuery } from '@mui/material'
import { ThemeProvider } from '@mui/material/styles'
import type { Api, User } from './api'
import { I18nProvider, pickLanguage, useI18n } from './i18n'
import { Desktop } from './shell/Desktop'
import { SignIn } from './signin/SignIn'
import { makeTheme, type Mode } from './theme'
import { usePrefs } from './usePrefs'

function SaveFailed({ open, onClose }: { open: boolean; onClose(): void }) {
  const { t } = useI18n()
  return <Snackbar open={open} onClose={onClose} autoHideDuration={5000} message={t('layout.notSaved')} />
}

export function App({ api }: { api: Api }) {
  /** undefined while the session check runs. */
  const [user, setUser] = useState<User | null | undefined>(undefined)
  const { prefs, update, saveFailed, dismissSaveError } = usePrefs(api, Boolean(user))
  const systemDark = useMediaQuery('(prefers-color-scheme: dark)', { noSsr: true })
  const mode: Mode = prefs.theme === 'system' ? (systemDark ? 'dark' : 'light') : prefs.theme
  const theme = useMemo(() => makeTheme(user ? mode : systemDark ? 'dark' : 'light'), [user, mode, systemDark])
  // Before sign-in the browser's language; after, the user's choice
  const lang = pickLanguage(user ? prefs.language : 'auto', navigator.languages)

  useEffect(() => {
    api.session().then(setUser, () => setUser(null))
  }, [api])

  const signOut = async () => {
    await api.logout().catch(() => undefined) // signed out locally either way
    setUser(null)
  }

  return (
    <I18nProvider lang={lang}>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        {user === null && <SignIn api={api} onSignedIn={setUser} />}
        {user && <Desktop api={api} user={user} prefs={prefs} mode={mode} onPrefs={update} onSignOut={signOut} />}
        <SaveFailed open={saveFailed} onClose={dismissSaveError} />
      </ThemeProvider>
    </I18nProvider>
  )
}
