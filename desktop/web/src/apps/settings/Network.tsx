/**
 * Settings › Network: the devices as they are, the Ethernet address
 * (automatic or one you set), and the Wi-Fi networks Kura knows. A changed
 * address goes back by itself unless it is kept from a browser that still
 * reaches the server, so a mistake cannot cut a server without a screen off.
 */
import { useState, type FormEvent } from 'react'
import { Alert, Box, Button, FormControlLabel, Link, Radio, RadioGroup, TextField } from '@mui/material'
import { useI18n } from '../../i18n'
import { colors } from '../../theme'
import { Card, Dot, MONO, SectionTitle } from '../parts'
import { ChangeError, useChange, type SectionProps } from './useSettings'
import { Wifi } from './Wifi'

function Devices({ settings }: SectionProps) {
  const { t } = useI18n()
  return (
    <>
      <SectionTitle>{t('settings.network.devices')}</SectionTitle>
      {settings.network.devices.map((d) => (
        <Card key={d.name} sx={{ mb: 1.25 }}>
          <Box role="group" aria-label={d.name} sx={{ display: 'flex', flexWrap: 'wrap', columnGap: 2, rowGap: 0.5, alignItems: 'baseline' }}>
            <Box sx={{ fontWeight: 500 }}><Dot color={d.connected ? colors.success : 'text.disabled'} />{d.name}</Box>
            <Box sx={{ color: 'text.secondary' }}>
              {t(d.kind === 'wifi' ? 'settings.network.wifi' : 'settings.network.ethernet')}
              {' · '}
              {d.connected ? d.connection || t('settings.network.connected') : t('settings.network.disconnected')}
            </Box>
            <Box sx={{ ml: 'auto', fontFamily: MONO, fontSize: 12.5 }}>{d.addresses.join(', ')}</Box>
            {d.connected && (
              <Box sx={{ flexBasis: '100%', fontSize: 12.5, color: 'text.secondary', fontFamily: MONO }}>
                {t('settings.network.detail', { gateway: d.gateway || '—', dns: d.dns.join(', ') || '—', mac: d.mac })}
              </Box>
            )}
          </Box>
        </Card>
      ))}
    </>
  )
}

function EthernetAddress({ settings, reload }: SectionProps) {
  const { t } = useI18n()
  const saved = settings.network.ethernet
  const [manual, setManual] = useState(saved.method === 'manual')
  const [address, setAddress] = useState(saved.address)
  const [gateway, setGateway] = useState(saved.gateway)
  const [dns, setDns] = useState(saved.dns.join(', '))
  const change = useChange(reload)
  // Known only for an address set here; an automatic one is the network's to give.
  const newUrl = saved.method === 'manual' && saved.address ? `https://${saved.address.split('/')[0]}` : null
  const servers = dns.split(/[\s,]+/).filter(Boolean)
  const submit = (e: FormEvent) => {
    e.preventDefault()
    change.run(manual ? { what: 'ethernet-static', address, gateway, dns: servers } : { what: 'ethernet-auto' })
  }
  const field = { size: 'small' as const, disabled: !manual, sx: { flex: '1 1 170px' } }
  return (
    <Card sx={{ mb: 2 }}>
      <SectionTitle>{t('settings.network.address')}</SectionTitle>
      {settings.network.pending && (
        <Alert severity="warning" sx={{ mb: 1.5 }}
          action={<Button color="inherit" size="small" disabled={change.busy} onClick={() => change.run({ what: 'network-confirm' })}>{t('settings.network.keep')}</Button>}>
          {t('settings.network.pending')}
          {newUrl && <> {t('settings.network.pending.at')} <Link href={newUrl} color="inherit">{newUrl}</Link></>}
        </Alert>
      )}
      <ChangeError error={change.error} />
      <Box component="form" onSubmit={submit}>
        <RadioGroup row value={manual ? 'manual' : 'auto'} onChange={(e) => setManual(e.target.value === 'manual')} aria-label={t('settings.network.address')}>
          <FormControlLabel value="auto" control={<Radio size="small" />} label={t('settings.network.auto')} />
          <FormControlLabel value="manual" control={<Radio size="small" />} label={t('settings.network.manual')} />
        </RadioGroup>
        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1.5, my: 1 }}>
          <TextField {...field} label={t('settings.network.cidr')} placeholder="192.168.1.50/24" value={address} onChange={(e) => setAddress(e.target.value)} />
          <TextField {...field} label={t('settings.network.gateway')} placeholder="192.168.1.1" value={gateway} onChange={(e) => setGateway(e.target.value)} />
          <TextField {...field} label={t('settings.network.dns')} placeholder="192.168.1.1, 9.9.9.9" value={dns} onChange={(e) => setDns(e.target.value)} />
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, flexWrap: 'wrap' }}>
          <Button type="submit" variant="contained" disabled={change.busy || (manual && (!address || !gateway || servers.length === 0))}>
            {t('settings.apply')}
          </Button>
          <Box sx={{ flex: '1 1 240px', fontSize: 12.5, color: 'text.secondary' }}>{t('settings.network.note')}</Box>
        </Box>
      </Box>
    </Card>
  )
}

export function Network(p: SectionProps) {
  return (
    <>
      <Devices {...p} />
      <Box sx={{ mt: 2 }} />
      <EthernetAddress key={JSON.stringify(p.settings.network.ethernet)} {...p} />
      <Wifi {...p} />
    </>
  )
}
