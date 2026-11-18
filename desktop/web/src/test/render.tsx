/** Renders inside Kura's theme, and optionally the desktop's stats and system data. */
import type { ReactElement, ReactNode } from 'react'
import { render } from '@testing-library/react'
import { ThemeProvider } from '@mui/material/styles'
import { makeTheme, type Mode } from '../theme'
import { DesktopDataProvider } from '../shell/useStats'
import type { Api } from '../api'

export function renderWithTheme(ui: ReactElement, { mode = 'dark', api }: { mode?: Mode; api?: Api } = {}) {
  const wrapper = ({ children }: { children: ReactNode }) => (
    <ThemeProvider theme={makeTheme(mode)}>
      {api ? <DesktopDataProvider api={api}>{children}</DesktopDataProvider> : children}
    </ThemeProvider>
  )
  return render(ui, { wrapper })
}
