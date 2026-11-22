/** A container's latest output, refreshed every few seconds, with the way back to the list. */
import { useCallback, useMemo } from 'react'
import { Box, IconButton, Tooltip } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { Container } from '../../api'
import { Glyph } from '../../icons/Glyph'
import { useI18n } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { LogRows, type LogRow } from '../LogRows'
import { Notice } from '../parts'
import { useAwake, usePolled } from '../usePolled'

const LINES = 300
const POLL_MS = 3000

export function Logs({ container, minimized, onBack }: { container: Container; minimized: boolean; onBack(): void }) {
  const api = useApi()
  const k = useTheme().kura
  const { t } = useI18n()
  const load = useCallback(() => api.containerLogs(container.id, LINES), [api, container.id])
  const { data, failed } = usePolled(load, POLL_MS, useAwake(minimized))
  const title = t('containers.logs.title', { name: container.name })
  const rows = useMemo<LogRow[]>(
    () => (data ?? []).map((l, i) => ({ key: i, t: l.t, text: l.text, tone: l.stream === 'stderr' ? 'warning' : undefined })),
    [data],
  )

  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 0.5, px: 1, py: 0.5, bgcolor: k.chrome, borderBottom: 1, borderColor: 'divider' }}>
        <Tooltip title={t('containers.logs.back')}>
          <IconButton size="small" aria-label={t('containers.logs.back')} onClick={onBack}><Glyph name="back" /></IconButton>
        </Tooltip>
        <Box sx={{ fontWeight: 600, fontSize: 13, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</Box>
      </Box>
      {!data && <Notice>{t(failed ? 'containers.logs.failed' : 'containers.loading')}</Notice>}
      {data?.length === 0 && <Notice>{t('containers.logs.none')}</Notice>}
      {data && data.length > 0 && <LogRows label={title} rows={rows} />}
    </Box>
  )
}
