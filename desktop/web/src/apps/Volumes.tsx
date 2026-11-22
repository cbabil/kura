/** The volumes with what they hold, one card each (Activity and Settings). */
import { Box } from '@mui/material'
import type { DiskUsage } from '../api'
import { useI18n } from '../i18n'
import { colors } from '../theme'
import { Meter } from './activity/Charts'
import { Card, MONO, SectionTitle } from './parts'

/** Above this part of a volume in use, its bar turns red. */
const NEARLY_FULL = 0.9

export function Volumes({ disks }: { disks: DiskUsage[] }) {
  const { t, format } = useI18n()
  return (
    <>
      <SectionTitle>{t('activity.volumesTitle')}</SectionTitle>
      {disks.map((d) => (
        <Card key={d.mount} sx={{ mb: 1.25 }}>
          <Box sx={{ display: 'flex', mb: 1 }}>
            <Box component="span" sx={{ fontFamily: MONO }}>{d.mount}</Box>
            <Box component="span" sx={{ ml: 'auto', color: 'text.secondary' }}>
              {t('activity.of', { used: format.bytes(d.used), size: format.bytes(d.size) })}
            </Box>
          </Box>
          <Meter label={t('activity.used.meter', { mount: d.mount })} total={d.size}
            parts={[{ value: d.used, color: d.size > 0 && d.used / d.size > NEARLY_FULL ? colors.error : colors.success }]} />
        </Card>
      ))}
    </>
  )
}
