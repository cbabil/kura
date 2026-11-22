/**
 * Restart or shut down the server, asked twice: once in the menu, once
 * here. After a restart the page waits for the server to go and come back,
 * then loads again; after a shut-down there is nothing to wait for.
 */
import { useEffect, useState } from 'react'
import { Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle, LinearProgress } from '@mui/material'
import { ApiError, type PowerKind } from '../api'
import { useI18n } from '../i18n'
import { useApi } from './DesktopData'

/** How often the page looks whether a restarted server is back. */
const LOOK_MS = 3000

type Stage = 'ask' | 'going' | 'failed'

/** A new function on each render would start the wait for the server over. */
const loadAgain = () => location.reload()

interface Props {
  /** What is asked for, or null while the dialog is closed. */
  how: PowerKind | null
  onClose(): void
  /** Loads the page again once the server is back; replaced in tests. */
  reload?(): void
}

export function PowerDialog({ how, onClose, reload = loadAgain }: Props) {
  const api = useApi()
  const { t } = useI18n()
  const [stage, setStage] = useState<Stage>('ask')
  const going = stage === 'going'

  // Back once it has been seen gone: an answer before that is the old
  // server's. The session question is answered by any running server, signed
  // in or not (a restart ends every session), and fails only when none runs.
  useEffect(() => {
    if (!going || how !== 'restart') return
    let gone = false
    const timer = setInterval(() => {
      api.session().then(() => gone && reload(), () => (gone = true))
    }, LOOK_MS)
    return () => clearInterval(timer)
  }, [api, going, how, reload])

  if (!how) return null
  const confirm = () => {
    setStage('going')
    // A connection that drops is the machine going; only a refusal is a failure.
    api.power(how).catch((e: unknown) => {
      if (e instanceof ApiError && e.code !== 'network') setStage('failed')
    })
  }
  const close = () => {
    setStage('ask')
    onClose()
  }

  return (
    <Dialog open onClose={going ? undefined : close} aria-labelledby="power-title" slotProps={{ paper: { sx: { width: 420 } } }}>
      <DialogTitle id="power-title">{t(`power.${how}.title`)}</DialogTitle>
      <DialogContent>
        {going ? (
          <>
            <LinearProgress sx={{ mb: 2 }} />
            {t(`power.${how}.going`)}
          </>
        ) : (
          t(`power.${how}.text`)
        )}
        {stage === 'failed' && <Alert severity="error" sx={{ mt: 2 }}>{t('power.failed')}</Alert>}
      </DialogContent>
      {!going && (
        <DialogActions>
          <Button onClick={close}>{t('power.cancel')}</Button>
          <Button variant="contained" color={how === 'shutdown' ? 'error' : 'primary'} onClick={confirm}>{t(`power.${how}.confirm`)}</Button>
        </DialogActions>
      )}
    </Dialog>
  )
}
