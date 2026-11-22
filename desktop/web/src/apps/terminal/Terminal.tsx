/**
 * Terminal (D2): the signed-in user's own shell on the server, in a window.
 * The terminal emulator (xterm.js) is loaded when the window first opens,
 * so the desktop itself stays small. Closing the window ends the shell.
 */
import { lazy, memo, Suspense, useState } from 'react'
import { Box, Button } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { TerminalEnd } from '../../api'
import { useI18n } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { Notice } from '../parts'
import type { AppProps } from '../types'

const XtermView = lazy(() => import('./XtermView'))

function TerminalBody() {
  const api = useApi()
  const k = useTheme().kura
  const { t } = useI18n()
  /** Counts shells: a new number is a new terminal and a new shell. */
  const [shell, setShell] = useState(0)
  const [ended, setEnded] = useState<TerminalEnd | null>(null)

  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column', bgcolor: 'background.paper' }}>
      <Suspense fallback={<Notice>{t('terminal.loading')}</Notice>}>
        <XtermView key={shell} api={api} onEnd={setEnded} />
      </Suspense>
      {ended && (
        <Box role="status" sx={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 1.5, px: 1.5, py: 1,
          borderTop: 1, borderColor: 'divider', bgcolor: k.chrome, fontSize: 13 }}>
          <Box sx={{ flex: 1, color: 'text.secondary' }}>{t(`terminal.ended.${ended}`)}</Box>
          <Button size="small" variant="contained" sx={{ flexShrink: 0 }}
            onClick={() => {
              setEnded(null)
              setShell((n) => n + 1)
            }}>
            {t('terminal.new')}
          </Button>
        </Box>
      )}
    </Box>
  )
}

/** Takes the window's props like every app, and needs none of them. */
export const Terminal = memo<AppProps>(TerminalBody)
