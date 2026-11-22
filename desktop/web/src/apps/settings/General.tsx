/**
 * Settings › General: the server's name (administrators) and one's own
 * password (everyone). A new name remakes the desktop's certificate, so the
 * page has to be opened again at the new address.
 */
import { useState, type FormEvent } from 'react'
import { Alert, Box, Button, TextField } from '@mui/material'
import type { Settings } from '../../api'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi, useUser } from '../../shell/DesktopData'
import { Card, SectionTitle, ViewBody } from '../parts'
import { Screens } from './Screens'
import { ChangeError, refusalKey, useChange, useSettings } from './useSettings'

function HostName({ settings, reload }: { settings: Settings; reload(): void }) {
  const { t } = useI18n()
  const [name, setName] = useState(settings.hostname)
  const [renamed, setRenamed] = useState<string | null>(null)
  const change = useChange(reload)
  const submit = (e: FormEvent) => {
    e.preventDefault()
    change.run({ what: 'hostname', name }, () => setRenamed(name))
  }
  return (
    <Card sx={{ mb: 2 }}>
      <SectionTitle>{t('settings.hostname')}</SectionTitle>
      <ChangeError error={change.error} />
      {renamed && <Alert severity="info" sx={{ mb: 1.5 }}>{t('settings.hostname.renamed', { name: renamed })}</Alert>}
      <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5, alignItems: 'flex-start' }}>
        <TextField size="small" label={t('settings.hostname')} value={name} onChange={(e) => setName(e.target.value.toLowerCase())}
          helperText={t('settings.hostname.hint')} sx={{ flex: '1 1 220px' }} />
        <Button type="submit" variant="contained" disabled={change.busy || !name || name === settings.hostname}>{t('settings.save')}</Button>
      </Box>
    </Card>
  )
}

function OwnPassword() {
  const api = useApi()
  const { t } = useI18n()
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [again, setAgain] = useState('')
  const [said, setSaid] = useState<{ ok: boolean; key: MessageKey } | null>(null)
  const [busy, setBusy] = useState(false)
  const differ = again !== '' && next !== again
  const submit = (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    api.changePassword(current, next).then(
      () => {
        setSaid({ ok: true, key: 'settings.password.changed' })
        setCurrent('')
        setNext('')
        setAgain('')
      },
      (err: unknown) => setSaid({ ok: false, key: refusalKey(err) === 'settings.invalid' ? 'settings.password.wrong' : 'settings.failed' }),
    ).finally(() => setBusy(false))
  }
  const field = { size: 'small', type: 'password', sx: { flex: '1 1 180px' } } as const
  return (
    <Card>
      <SectionTitle>{t('settings.password')}</SectionTitle>
      {said && <Alert severity={said.ok ? 'success' : 'error'} sx={{ mb: 1.5 }}>{t(said.key)}</Alert>}
      <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5, alignItems: 'flex-start' }}>
        <TextField {...field} label={t('settings.password.current')} autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
        <TextField {...field} label={t('settings.password.new')} autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
        <TextField {...field} label={t('settings.password.again')} autoComplete="new-password" value={again} onChange={(e) => setAgain(e.target.value)}
          error={differ} helperText={differ ? t('settings.password.differ') : ' '} />
        <Button type="submit" variant="contained" disabled={busy || !current || !next || next !== again}>{t('settings.password.change')}</Button>
      </Box>
      <Box sx={{ fontSize: 12.5, color: 'text.secondary' }}>{t('settings.password.note')}</Box>
    </Card>
  )
}

/** The name is for administrators and needs the settings; the password is for everyone and needs nothing. */
function AdminPart({ minimized }: { minimized: boolean }) {
  const { data, reload } = useSettings(minimized)
  // Not remounted when the name changes: the note about the new address must stay
  return data ? <><HostName settings={data} reload={reload} /><Screens settings={data} reload={reload} /></> : null
}

export function General({ minimized }: { minimized: boolean }) {
  return (
    <ViewBody>
      {useUser().admin && <AdminPart minimized={minimized} />}
      <OwnPassword />
    </ViewBody>
  )
}
