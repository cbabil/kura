/**
 * The terminal emulator and its shell: xterm.js on one side, the server's
 * /api/terminal WebSocket on the other. One mount is one shell; it ends
 * when this unmounts. The terminal is sized to its box and tells the shell
 * each time the size changes. A separate chunk (see Terminal.tsx).
 */
import { useEffect, useMemo, useRef } from 'react'
import { Box } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { FitAddon } from '@xterm/addon-fit'
import { Terminal as Xterm } from '@xterm/xterm'
import '@xterm/xterm/css/xterm.css'
import type { Api, TerminalEnd } from '../../api'
import { useI18n } from '../../i18n'
import { MONO } from '../parts'

export default function XtermView({ api, onEnd }: { api: Api; onEnd(reason: TerminalEnd): void }) {
  const host = useRef<HTMLDivElement>(null)
  const xterm = useRef<Xterm | null>(null)
  const { palette } = useTheme()
  const { t } = useI18n()
  const colours = useMemo(
    () => ({ background: palette.background.paper, foreground: palette.text.primary, cursor: palette.primary.main, selectionBackground: palette.action.selected }),
    [palette],
  )
  const look = useRef(colours)

  // Before the effect below, so a new terminal starts in the current theme;
  // a theme change recolours the open terminal without restarting its shell.
  useEffect(() => {
    look.current = colours
    if (xterm.current) xterm.current.options.theme = colours
  }, [colours])

  useEffect(() => {
    const box = host.current
    if (!box) return
    const term = new Xterm({ fontFamily: MONO, fontSize: 13, cursorBlink: true, scrollback: 5000, theme: look.current })
    const fit = new FitAddon()
    term.loadAddon(fit)
    term.open(box)
    xterm.current = term
    // A minimised window has no size; fitting to it would shrink the shell to nothing.
    const visible = () => box.clientWidth > 0 && box.clientHeight > 0
    if (visible()) fit.fit()

    const session = api.terminal(
      { cols: term.cols, rows: term.rows },
      {
        onOpen() {
          // The window may have changed size while the connection opened.
          session.resize(term.cols, term.rows)
          term.focus()
        },
        onData: (bytes) => term.write(bytes),
        onEnd,
      },
    )
    const typing = term.onData((text) => session.write(text))
    const resizing = term.onResize(({ cols, rows }) => session.resize(cols, rows))
    const observer = new ResizeObserver(() => visible() && fit.fit())
    observer.observe(box)
    return () => {
      observer.disconnect()
      typing.dispose()
      resizing.dispose()
      session.close()
      term.dispose()
      xterm.current = null
    }
  }, [api, onEnd])

  return (
    <Box data-keys="app" sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', p: '8px 4px 4px 10px' }}>
      <Box ref={host} aria-label={t('terminal.label')} sx={{ flex: 1, minWidth: 0, minHeight: 0, overflow: 'hidden' }} />
    </Box>
  )
}
