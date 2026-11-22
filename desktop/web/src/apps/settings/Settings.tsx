/**
 * Settings: a sidebar of sections and the chosen one. General and Updates
 * are for everyone (one's own password; whether an update waits); the
 * others are for administrators.
 */
import { memo } from 'react'
import { Box } from '@mui/material'
import type { GlyphName } from '../../icons/Glyph'
import { useI18n, type MessageKey } from '../../i18n'
import { Sidebar } from '../parts'
import type { AppProps } from '../types'
import { DateTime } from './DateTime'
import { General } from './General'
import { Network } from './Network'
import { Storage } from './Storage'
import { Updates } from './Updates'
import { Users } from './Users'
import { adminSection } from './useSettings'

export const SETTINGS_VIEWS = ['General', 'Network', 'Users', 'DateTime', 'Storage', 'Updates'] as const
export type SettingsView = (typeof SETTINGS_VIEWS)[number]

export const SETTINGS_LABELS: Record<SettingsView, MessageKey> = {
  General: 'settings.view.General',
  Network: 'settings.view.Network',
  Users: 'settings.view.Users',
  DateTime: 'settings.view.DateTime',
  Storage: 'settings.view.Storage',
  Updates: 'settings.view.Updates',
}

const VIEWS: Record<SettingsView, { glyph: GlyphName; Component: (p: { minimized: boolean }) => React.ReactNode }> = {
  General: { glyph: 'gear', Component: General },
  Network: { glyph: 'network', Component: adminSection(Network) },
  Users: { glyph: 'user', Component: adminSection(Users) },
  DateTime: { glyph: 'clock', Component: adminSection(DateTime) },
  Storage: { glyph: 'disk', Component: adminSection(Storage) },
  Updates: { glyph: 'update', Component: Updates },
}

const isView = (v: string): v is SettingsView => v in VIEWS

function SettingsBody({ view: requested, setView, compact, minimized }: AppProps) {
  const { t } = useI18n()
  const view = isView(requested) ? requested : SETTINGS_VIEWS[0]
  const { Component } = VIEWS[view]

  return (
    <Box sx={{ flex: 1, display: 'flex', flexDirection: compact ? 'column' : 'row', minWidth: 0, minHeight: 0 }}>
      <Sidebar<SettingsView> label={t('settings.sections')} views={SETTINGS_VIEWS} current={view} compact={compact}
        glyph={(v) => VIEWS[v].glyph} name={(v) => t(SETTINGS_LABELS[v])} onChoose={setView} />
      <Component minimized={minimized} />
    </Box>
  )
}

export const Settings = memo(SettingsBody)
