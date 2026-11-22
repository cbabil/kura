/**
 * Settings › Storage: how the disk layout chosen at installation went, and
 * the volumes with what they hold. Nothing is changed from here: a layout
 * is chosen when Kura is written to the disk.
 */
import { Box } from '@mui/material'
import { useI18n } from '../../i18n'
import { useStats } from '../../shell/DesktopData'
import { Card, SectionTitle } from '../parts'
import { Volumes } from '../Volumes'
import type { SectionProps } from './useSettings'

export function Storage({ settings }: SectionProps) {
  const { t } = useI18n()
  const disks = useStats((s) => s.latest?.disks)
  return (
    <>
      <SectionTitle>{t('settings.storage.title')}</SectionTitle>
      <Card sx={{ mb: 2 }}>
        <Box sx={{ color: 'text.secondary', fontSize: 12.5 }}>{t('settings.storage.layout')}</Box>
        <Box>{settings.storage || t('settings.storage.simple')}</Box>
      </Card>
      <Volumes disks={disks ?? []} />
      <Box sx={{ fontSize: 12.5, color: 'text.secondary' }}>{t('settings.storage.note')}</Box>
    </>
  )
}
