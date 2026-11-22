/** Renders inside Kura's theme and a language, and optionally the desktop's stats and system data. */
import type { ReactElement, ReactNode } from 'react'
import { render } from '@testing-library/react'
import { ThemeProvider } from '@mui/material/styles'
import { makeTheme, type Mode } from '../theme'
import { DesktopDataProvider } from '../shell/DesktopData'
import type { Api, User } from '../api'
import { I18nProvider, type Lang } from '../i18n'

/** The administrator the apps are shown to unless a test names another user. */
export const CHRIS: User = { name: 'chris', uid: 1000, admin: true }

export function renderWithTheme(
  ui: ReactElement,
  { mode = 'dark', api, lang = 'en', user = CHRIS }: { mode?: Mode; api?: Api; lang?: Lang; user?: User } = {},
) {
  const wrapper = ({ children }: { children: ReactNode }) => (
    <I18nProvider lang={lang}>
      <ThemeProvider theme={makeTheme(mode)}>
        {api ? <DesktopDataProvider api={api} user={user}>{children}</DesktopDataProvider> : children}
      </ThemeProvider>
    </I18nProvider>
  )
  return render(ui, { wrapper })
}
