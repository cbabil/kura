/**
 * Settings › General: the two ways to see Kura Desktop without a browser of
 * one's own. The server's own screen (ADR-033) and Remote Desktop (ADR-035)
 * are each one switch, shown only where the server's image has the programs.
 */
import { Box, FormControlLabel, Switch } from '@mui/material'
import type { Settings } from '../../api'
import { useI18n } from '../../i18n'
import { Card, SectionTitle } from '../parts'
import { ChangeError, useChange } from './useSettings'

interface SwitchCardProps {
  /** The setting, and the start of its strings: `settings.<what>` and `settings.<what>.on`. */
  what: 'screen' | 'rdp'
  /** On or off, or null on a server whose image has no such thing. */
  on: boolean | null
  reload(): void
  note: string
}

function SwitchCard({ what, on, reload, note }: SwitchCardProps) {
  const { t } = useI18n()
  const change = useChange(reload)
  if (on === null) return null
  return (
    <Card sx={{ mb: 2 }}>
      <SectionTitle>{t(`settings.${what}`)}</SectionTitle>
      <ChangeError error={change.error} />
      <FormControlLabel label={t(`settings.${what}.on`)}
        control={<Switch size="small" checked={on} disabled={change.busy} onChange={(e) => change.run({ what, on: e.target.checked })} />} />
      <Box sx={{ fontSize: 12.5, color: 'text.secondary' }}>{note}</Box>
    </Card>
  )
}

/** Both switches, each where the server has it. */
export function Screens({ settings, reload }: { settings: Settings; reload(): void }) {
  const { t } = useI18n()
  return (
    <>
      <SwitchCard what="screen" on={settings.screen} reload={reload} note={t('settings.screen.note')} />
      <SwitchCard what="rdp" on={settings.rdp} reload={reload} note={t('settings.rdp.note', { name: settings.hostname })} />
    </>
  )
}
