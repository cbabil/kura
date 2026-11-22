/**
 * Settings › Users: the people's accounts, who is an administrator, new
 * passwords, adding and removing. Removing keeps the person's files. The
 * server refuses to leave Kura without an administrator.
 */
import { useState, type FormEvent } from 'react'
import { Box, Button, Checkbox, Dialog, DialogActions, DialogContent, DialogTitle, FormControlLabel, Switch, TextField } from '@mui/material'
import type { Person } from '../../api'
import { useI18n } from '../../i18n'
import { useUser } from '../../shell/DesktopData'
import { Card, SectionTitle } from '../parts'
import { ChangeError, useChange, type Changer, type SectionProps } from './useSettings'

/** What a dialog is about: a new password for someone, or their removal. */
type Asking = { person: Person; what: 'password' | 'remove' } | null

function AskDialog({ asking, change, onClose }: { asking: Asking; change: Changer; onClose(): void }) {
  const { t } = useI18n()
  const [password, setPassword] = useState('')
  if (!asking) return null
  const { person, what } = asking
  const close = () => {
    setPassword('')
    change.clear()
    onClose()
  }
  const confirm = (e: FormEvent) => {
    e.preventDefault()
    change.run(what === 'remove' ? { what: 'user-remove', name: person.name } : { what: 'user-password', name: person.name, password }, close)
  }
  return (
    <Dialog open onClose={close} aria-labelledby="user-ask" slotProps={{ paper: { sx: { width: 400 } } }}>
      <Box component="form" onSubmit={confirm}>
        <DialogTitle id="user-ask">{t(what === 'remove' ? 'settings.users.remove.title' : 'settings.users.password.title', { name: person.name })}</DialogTitle>
        <DialogContent>
          <ChangeError error={change.error} />
          {what === 'remove' ? t('settings.users.remove.text', { name: person.name }) : (
            <TextField size="small" fullWidth autoFocus type="password" autoComplete="new-password" sx={{ mt: 1 }}
              label={t('settings.password.new')} value={password} onChange={(e) => setPassword(e.target.value)} />
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={close}>{t('power.cancel')}</Button>
          <Button type="submit" variant="contained" color={what === 'remove' ? 'error' : 'primary'} disabled={change.busy || (what === 'password' && !password)}>
            {t(what === 'remove' ? 'settings.users.remove' : 'settings.save')}
          </Button>
        </DialogActions>
      </Box>
    </Dialog>
  )
}

function AddUser({ change }: { change: Changer }) {
  const { t } = useI18n()
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [admin, setAdmin] = useState(false)
  const submit = (e: FormEvent) => {
    e.preventDefault()
    change.run({ what: 'user-add', name, password, admin }, () => {
      setName('')
      setPassword('')
      setAdmin(false)
    })
  }
  return (
    <Card>
      <SectionTitle>{t('settings.users.add')}</SectionTitle>
      <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5, alignItems: 'center' }}>
        <TextField size="small" label={t('signin.user')} autoComplete="off" value={name} onChange={(e) => setName(e.target.value.toLowerCase())} sx={{ flex: '1 1 160px' }} />
        <TextField size="small" type="password" label={t('signin.password')} autoComplete="new-password" value={password}
          onChange={(e) => setPassword(e.target.value)} sx={{ flex: '1 1 160px' }} />
        <FormControlLabel label={t('settings.users.admin')} control={<Checkbox size="small" checked={admin} onChange={(e) => setAdmin(e.target.checked)} />} />
        <Button type="submit" variant="contained" disabled={change.busy || !name || !password}>{t('settings.users.add.confirm')}</Button>
      </Box>
    </Card>
  )
}

export function Users({ settings, reload }: SectionProps) {
  const { t } = useI18n()
  const me = useUser().name
  const change = useChange(reload)
  const [asking, setAsking] = useState<Asking>(null)
  return (
    <>
      <SectionTitle>{t('settings.users.title')}</SectionTitle>
      {!asking && <ChangeError error={change.error} />}
      <Card sx={{ mb: 2, py: '6px' }}>
        <Box role="list" aria-label={t('settings.users.title')}>
          {settings.users.map((u) => (
            <Box key={u.name} role="listitem" aria-label={u.name} sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', columnGap: 1, py: '3px' }}>
              <Box sx={{ flex: '1 1 140px', fontWeight: 500 }}>
                {u.name}
                {u.name === me && <Box component="span" sx={{ color: 'text.secondary', fontWeight: 400 }}> · {t('settings.users.you')}</Box>}
              </Box>
              <FormControlLabel label={t('settings.users.admin')} sx={{ mr: 1 }}
                control={<Switch size="small" checked={u.admin} disabled={change.busy}
                  onChange={(e) => change.run({ what: 'user-admin', name: u.name, admin: e.target.checked })} />} />
              <Button size="small" onClick={() => setAsking({ person: u, what: 'password' })}>{t('settings.users.password')}</Button>
              <Button size="small" color="error" disabled={u.name === me} onClick={() => setAsking({ person: u, what: 'remove' })}>{t('settings.users.remove')}</Button>
            </Box>
          ))}
        </Box>
      </Card>
      <AddUser change={change} />
      <AskDialog asking={asking} change={change} onClose={() => setAsking(null)} />
    </>
  )
}
