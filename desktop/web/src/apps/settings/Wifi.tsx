/** Settings › Network › Wi-Fi: the networks Kura knows, forgetting one, and adding one. */
import { useState, type FormEvent } from 'react'
import { Box, Button, Checkbox, FormControlLabel, TextField } from '@mui/material'
import { useI18n } from '../../i18n'
import { Card, SectionTitle } from '../parts'
import { ChangeError, useChange, type SectionProps } from './useSettings'

export function Wifi({ settings, reload }: SectionProps) {
  const { t } = useI18n()
  const [ssid, setSsid] = useState('')
  const [password, setPassword] = useState('')
  const [hidden, setHidden] = useState(false)
  const change = useChange(reload)
  const submit = (e: FormEvent) => {
    e.preventDefault()
    change.run({ what: 'wifi-add', ssid, password, hidden }, () => {
      setSsid('')
      setPassword('')
    })
  }
  return (
    <Card>
      <SectionTitle>{t('settings.wifi')}</SectionTitle>
      <ChangeError error={change.error} />
      {settings.network.wifi.length === 0 && <Box sx={{ color: 'text.secondary', mb: 1.5 }}>{t('settings.wifi.none')}</Box>}
      <Box role="list" aria-label={t('settings.wifi')} sx={{ mb: 1.5 }}>
        {settings.network.wifi.map((name) => (
          <Box key={name} role="listitem" sx={{ display: 'flex', alignItems: 'center', py: 0.25 }}>
            <Box sx={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</Box>
            <Button size="small" disabled={change.busy} onClick={() => change.run({ what: 'wifi-remove', ssid: name })}>
              {t('settings.wifi.forget', { name })}
            </Button>
          </Box>
        ))}
      </Box>
      <Box component="form" onSubmit={submit} sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5, alignItems: 'center' }}>
        <TextField size="small" label={t('settings.wifi.name')} value={ssid} onChange={(e) => setSsid(e.target.value)} sx={{ flex: '1 1 170px' }} />
        <TextField size="small" type="password" label={t('settings.wifi.password')} autoComplete="off" value={password}
          onChange={(e) => setPassword(e.target.value)} sx={{ flex: '1 1 170px' }} />
        <FormControlLabel label={t('settings.wifi.hidden')} control={<Checkbox size="small" checked={hidden} onChange={(e) => setHidden(e.target.checked)} />} />
        <Button type="submit" variant="contained" disabled={change.busy || !ssid || password.length < 8}>{t('settings.wifi.add')}</Button>
      </Box>
    </Card>
  )
}
