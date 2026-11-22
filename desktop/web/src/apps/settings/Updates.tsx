/**
 * Settings › Updates: the installed version, the one that waits, and the
 * buttons to look for one and to install it (ADR-025: only when asked, and
 * the server never restarts by itself). While an update runs, its output.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Alert, Box, Button, LinearProgress } from '@mui/material'
import type { PowerKind, UpdateKind, UpdateStatus } from '../../api'
import { useI18n } from '../../i18n'
import { useApi, useUpdates, useUser } from '../../shell/DesktopData'
import { PowerDialog } from '../../shell/PowerDialog'
import { LogRows, type LogRow } from '../LogRows'
import { Card, Notice, SectionTitle, ViewBody } from '../parts'
import { useAwake, usePolled, useSettle } from '../usePolled'

/** While an update runs the server is asked often; otherwise now and then. */
const BUSY_MS = 2000
/** A start whose answer looks like the last one stops being waited for after this. */
const SETTLE_MS = 3 * BUSY_MS
const IDLE_MS = 30_000

export function Updates({ minimized }: { minimized: boolean }) {
  const api = useApi()
  const { admin } = useUser()
  const { t } = useI18n()
  const { note } = useUpdates()
  /** A start was sent and the server's next answer is awaited. */
  const [asked, setAsked] = useState(false)
  const settle = useCallback(() => setAsked(false), [])
  useSettle(asked, settle, SETTLE_MS)
  const [refused, setRefused] = useState(false)
  const [power, setPower] = useState<PowerKind | null>(null)
  const [shown, setShown] = useState<UpdateStatus | null>(null)
  const load = useCallback(() => api.updates(), [api])
  const { data, failed, reload } = usePolled(load, asked || shown?.job?.state === 'running' ? BUSY_MS : IDLE_MS, useAwake(minimized))
  const running = data?.job?.state === 'running'

  // A new answer: the wait for it is over, and the menu bar's notice follows.
  if (data && data !== shown) {
    setShown(data)
    setAsked(false)
  }
  useEffect(() => {
    if (data) note(data)
  }, [data, note])

  const rows = useMemo<LogRow[]>(() => (data?.job?.output ?? []).map((text, i) => ({ key: i, t: null, text })), [data])
  if (!data) return <Notice>{t(failed ? 'updates.error' : 'updates.loading')}</Notice>

  const busy = running || asked
  const start = (what: UpdateKind) => {
    setAsked(true)
    setRefused(false)
    api.startUpdate(what).then(reload, () => {
      setAsked(false)
      setRefused(true)
    })
  }
  const { job } = data
  return (
    <ViewBody>
      <SectionTitle>{data.current ? t('updates.title', { version: data.current }) : t('updates.unknown')}</SectionTitle>
      <Card sx={{ mb: 1.5 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 1.5 }}>
          <Box sx={{ flex: '1 1 220px' }}>{data.available ? t('updates.available', { version: data.available }) : t('updates.upToDate')}</Box>
          {admin && <Button size="small" disabled={busy} onClick={() => start('check')}>{t('updates.check')}</Button>}
          {admin && data.available && (
            <Button size="small" variant="contained" disabled={busy} onClick={() => start('install')}>{t('updates.install')}</Button>
          )}
        </Box>
        {busy && <LinearProgress aria-label={t('updates.running')} sx={{ mt: 1.5 }} />}
      </Card>
      {data.restartRequired && (
        <Alert severity="warning" sx={{ mb: 1.5 }}
          action={admin && !busy && <Button color="inherit" size="small" onClick={() => setPower('restart')}>{t('updates.restart')}</Button>}>
          {t('updates.restartDue')}
        </Alert>
      )}
      {refused && <Alert severity="error" sx={{ mb: 1.5 }} onClose={() => setRefused(false)}>{t('updates.refused')}</Alert>}
      {job?.state === 'failed' && <Alert severity="error" sx={{ mb: 1.5 }}>{t('updates.failed')}</Alert>}
      {job?.state === 'done' && <Box role="status" sx={{ mb: 1.5, color: 'text.secondary' }}>{t('updates.done')}</Box>}
      {rows.length > 0 && (
        <Card sx={{ mb: 1.5, p: 0, display: 'flex', maxHeight: 240 }}><LogRows label={t('updates.output')} rows={rows} /></Card>
      )}
      <Box sx={{ fontSize: 12.5, color: 'text.secondary' }}>{t(admin ? 'updates.note' : 'updates.adminOnly')}</Box>
      <PowerDialog how={power} onClose={() => setPower(null)} />
    </ViewBody>
  )
}
