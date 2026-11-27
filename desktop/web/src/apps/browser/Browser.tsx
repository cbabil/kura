/**
 * Browser (ADR-036): a Chromium that runs on the server, shared by everyone
 * signed in, shown in a window. The viewer (noVNC) is loaded when the window
 * first opens, so the desktop itself stays small. Closing the window leaves
 * the browser running; it stops after 15 minutes nobody watched, or from
 * File › Quit Browser.
 */
import { lazy, memo, Suspense, useEffect, useRef, useState, type FormEvent } from 'react'
import { Box, Button, Dialog, DialogActions, DialogContent, DialogTitle, TextField } from '@mui/material'
import { useI18n } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { Notice } from '../parts'
import type { AppProps } from '../types'
import { BROWSER_PASTE, BROWSER_QUIT } from './commands'
import type { BrowserEnd, Paste } from './RfbView'

const RfbView = lazy(() => import('./RfbView'))

/** Text typed here for the server's clipboard, for browsers that will not share theirs. */
function PasteDialog({ onPaste, onClose }: { onPaste(text: string): void; onClose(): void }) {
  const { t } = useI18n()
  const [text, setText] = useState('')
  const submit = (e: FormEvent) => {
    e.preventDefault()
    onPaste(text)
    onClose()
  }
  return (
    <Dialog open onClose={onClose} aria-labelledby="browser-paste" slotProps={{ paper: { sx: { width: 440 } } }}>
      <Box component="form" onSubmit={submit}>
        <DialogTitle id="browser-paste">{t('browser.paste.title')}</DialogTitle>
        <DialogContent>
          <TextField size="small" fullWidth multiline minRows={3} autoFocus sx={{ mt: 1 }} label={t('browser.paste.text')}
            value={text} onChange={(e) => setText(e.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={onClose}>{t('power.cancel')}</Button>
          <Button type="submit" variant="contained" disabled={!text}>{t('browser.paste.send')}</Button>
        </DialogActions>
      </Box>
    </Dialog>
  )
}

function BrowserBody({ command }: AppProps) {
  const api = useApi()
  const { t } = useI18n()
  const [ended, setEnded] = useState<BrowserEnd | null>(null)
  /** The seq of the last Paste Text… whose dialog was closed. */
  const [answered, setAnswered] = useState<number | undefined>()
  /** The open view's way to paste; null while none is connected. */
  const paste = useRef<Paste | null>(null)

  // The menus' commands, each acted on once (its seq tells a new one): Paste
  // Text… shows the dialog until it is closed; Quit asks the server. A
  // refused quit leaves the view as it is, which shows it.
  const [name, seq] = [command?.name, command?.seq]
  const asking = name === BROWSER_PASTE && seq !== answered
  useEffect(() => {
    if (name === BROWSER_QUIT) api.browserStop().catch(() => {})
  }, [api, name, seq])

  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column', bgcolor: 'background.paper' }}>
      {ended ? (
        <Notice action={<Button variant="contained" onClick={() => setEnded(null)}>{t('browser.open')}</Button>}>
          {t(`browser.ended.${ended}`)}
        </Notice>
      ) : (
        <Suspense fallback={<Notice>{t('browser.loading')}</Notice>}>
          <RfbView api={api} onEnd={setEnded} pasteRef={paste} />
        </Suspense>
      )}
      {asking && <PasteDialog onPaste={(text) => paste.current?.(text)} onClose={() => setAnswered(seq)} />}
    </Box>
  )
}

/** Takes the window's props like every app; it reads only the menus' commands. */
export const Browser = memo<AppProps>(BrowserBody)
