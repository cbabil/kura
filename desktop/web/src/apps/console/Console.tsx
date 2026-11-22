/**
 * Console (D2): the system journal for administrators, filtered by unit and
 * priority on the server and by text on screen, and followed live.
 */
import { memo, useMemo, useState } from 'react'
import { Box, FormControlLabel, Switch, TextField } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi, useStats, useUser } from '../../shell/DesktopData'
import type { AppProps } from '../types'
import { LogRows, type LogRow } from '../LogRows'
import { Notice, unitName } from '../parts'
import { useAwake } from '../usePolled'
import { useJournal } from './useJournal'

/** syslog priorities offered: this one and anything more serious. */
const PRIORITIES: [value: string, label: MessageKey][] = [
  ['', 'console.priority.all'], ['5', 'console.priority.5'], ['4', 'console.priority.4'], ['3', 'console.priority.3'],
]
const ERROR = 3
const WARNING = 4

function Journal({ compact, minimized }: Pick<AppProps, 'compact' | 'minimized'>) {
  const api = useApi()
  const k = useTheme().kura
  const { t } = useI18n()
  const units = useStats((s) => s.units)
  const [unit, setUnit] = useState('')
  const [priority, setPriority] = useState('')
  const [text, setText] = useState('')
  const [follow, setFollow] = useState(true)
  const { entries, failed } = useJournal(api, unit, priority === '' ? undefined : Number(priority), follow, useAwake(minimized))

  const rows = useMemo<LogRow[]>(() => {
    const q = text.trim().toLowerCase()
    return (entries ?? [])
      .filter((e) => !q || `${e.message} ${e.unit} ${e.ident}`.toLowerCase().includes(q))
      .map((e) => ({
        key: e.id, t: e.t, source: e.ident || unitName(e.unit), text: e.message,
        tone: e.priority <= ERROR ? 'error' : e.priority === WARNING ? 'warning' : undefined,
      }))
  }, [entries, text])
  // A native select always shows a value, so its label stays above it
  const select = { size: 'small', select: true, slotProps: { select: { native: true }, inputLabel: { shrink: true } }, sx: { minWidth: 150, flex: '1 1 150px' } } as const

  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ flexShrink: 0, display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 1.25, p: compact ? '10px 12px' : '12px 16px',
        bgcolor: k.chrome, borderBottom: 1, borderColor: 'divider' }}>
        <TextField {...select} label={t('console.unit')} value={unit} onChange={(e) => setUnit(e.target.value)}>
          <option value="">{t('console.allUnits')}</option>
          {units.map((u) => <option key={u.name} value={u.name}>{unitName(u.name)}</option>)}
        </TextField>
        <TextField {...select} label={t('console.priority')} value={priority} onChange={(e) => setPriority(e.target.value)}>
          {PRIORITIES.map(([value, label]) => <option key={value} value={value}>{t(label)}</option>)}
        </TextField>
        <TextField type="search" size="small" value={text} placeholder={t('console.search')} sx={{ flex: '2 1 180px' }}
          onChange={(e) => setText(e.target.value)} slotProps={{ htmlInput: { 'aria-label': t('console.search') } }} />
        <FormControlLabel label={t('console.follow')} sx={{ mr: 0 }}
          control={<Switch size="small" checked={follow} onChange={(e) => setFollow(e.target.checked)} />} />
      </Box>
      {!entries && <Notice>{t(failed ? 'console.failed' : 'console.loading')}</Notice>}
      {entries && rows.length === 0 && <Notice>{t('console.none')}</Notice>}
      {rows.length > 0 && <LogRows label={t('console.log')} rows={rows} />}
    </Box>
  )
}

function ConsoleBody({ compact, minimized }: AppProps) {
  const { t } = useI18n()
  // The server refuses others too; not asking spares them an error.
  return useUser().admin ? <Journal compact={compact} minimized={minimized} /> : <Notice>{t('console.adminOnly')}</Notice>
}

export const Console = memo(ConsoleBody)
