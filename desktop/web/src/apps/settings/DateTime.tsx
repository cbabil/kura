/** Settings › Date & Time: the time zone and whether the clock is set from the network. */
import { useMemo } from 'react'
import { Box, FormControlLabel, Switch, TextField } from '@mui/material'
import { useI18n } from '../../i18n'
import { colors } from '../../theme'
import { Card, Dot, SectionTitle } from '../parts'
import { ChangeError, useChange, type SectionProps } from './useSettings'

/** The zones this browser knows, with the server's own first in case it is not among them. */
function zones(current: string): string[] {
  const known = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : []
  return known.includes(current) || !current ? known : [current, ...known]
}

export function DateTime({ settings, reload }: SectionProps) {
  const { t } = useI18n()
  const change = useChange(reload)
  const { zone, ntp, synced } = settings.time
  const all = useMemo(() => zones(zone), [zone])
  return (
    <>
      <SectionTitle>{t('settings.time.title')}</SectionTitle>
      <ChangeError error={change.error} />
      <Card sx={{ mb: 1.5 }}>
        <TextField select size="small" fullWidth label={t('settings.time.zone')} value={zone} disabled={change.busy}
          slotProps={{ select: { native: true }, inputLabel: { shrink: true } }}
          onChange={(e) => change.run({ what: 'timezone', zone: e.target.value })}>
          {all.map((z) => <option key={z} value={z}>{z.replaceAll('_', ' ')}</option>)}
        </TextField>
      </Card>
      <Card>
        <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 1.5 }}>
          <FormControlLabel label={t('settings.time.ntp')}
            control={<Switch size="small" checked={ntp} disabled={change.busy} onChange={(e) => change.run({ what: 'ntp', on: e.target.checked })} />} />
          <Box role="status" sx={{ ml: 'auto', color: 'text.secondary' }}>
            <Dot color={synced ? colors.success : colors.warning} />
            {t(synced ? 'settings.time.synced' : 'settings.time.unsynced')}
          </Box>
        </Box>
      </Card>
    </>
  )
}
