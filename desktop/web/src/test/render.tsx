/** Renders inside Kura's theme and a language, and optionally the desktop's stats and system data. */
import type { ReactElement, ReactNode } from 'react'
import { render } from '@testing-library/react'
import { ThemeProvider } from '@mui/material/styles'
import { makeTheme, type Mode } from '../theme'
import { DesktopDataProvider } from '../shell/useStats'
import type { Api } from '../api'
import { I18nProvider, type Lang } from '../i18n'

export function renderWithTheme(
  ui: ReactElement,
  { mode = 'dark', api, lang = 'en' }: { mode?: Mode; api?: Api; lang?: Lang } = {},
) {
  const wrapper = ({ children }: { children: ReactNode }) => (
    <I18nProvider lang={lang}>
      <ThemeProvider theme={makeTheme(mode)}>
        {api ? <DesktopDataProvider api={api}>{children}</DesktopDataProvider> : children}
      </ThemeProvider>
    </I18nProvider>
  )
  return render(ui, { wrapper })
}
