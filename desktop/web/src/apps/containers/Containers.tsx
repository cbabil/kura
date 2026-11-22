/**
 * Containers (D2): every Docker container, compose stacks together, with
 * start, stop, restart and logs for administrators. The server's helper
 * talks to Docker; this window asks again every few seconds.
 */
import { memo, useCallback, useState } from 'react'
import { Alert, Box, IconButton, TextField, Tooltip } from '@mui/material'
import type { Container, ContainerAction } from '../../api'
import { Glyph, type GlyphName } from '../../icons/Glyph'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi, useUser } from '../../shell/DesktopData'
import { colors } from '../../theme'
import type { AppProps } from '../types'
import { Card, Dot, MONO, Notice, ViewBody } from '../parts'
import { useAwake, usePolled } from '../usePolled'
import { groupContainers, isUp, matches } from './group'
import { Logs } from './Logs'

const POLL_MS = 5000

const CONTAINER_COLORS: Record<string, string> = {
  running: colors.success, restarting: colors.warning, paused: colors.warning, created: colors.info, dead: colors.error,
}
const STATE_LABELS: Record<string, MessageKey> = {
  running: 'containers.state.running', exited: 'containers.state.exited', paused: 'containers.state.paused',
  restarting: 'containers.state.restarting', created: 'containers.state.created', dead: 'containers.state.dead',
  removing: 'containers.state.removing',
}
const ACTION_GLYPHS: Record<ContainerAction, GlyphName> = { start: 'play', stop: 'stop', restart: 'restart' }

interface RowProps {
  container: Container
  /** null for users who may only look. */
  controls: null | { busy: boolean; act(action: ContainerAction): void; logs(): void }
}

function Row({ container: c, controls }: RowProps) {
  const { t } = useI18n()
  const button = (label: string, glyph: GlyphName, run: () => void) => (
    <Tooltip title={label} key={glyph}>
      <span><IconButton size="small" aria-label={label} disabled={controls?.busy} onClick={run}><Glyph name={glyph} /></IconButton></span>
    </Tooltip>
  )
  const actions: ContainerAction[] = isUp(c) ? ['restart', 'stop'] : ['start']
  return (
    <Box role="listitem" aria-label={c.name} sx={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', columnGap: 1.5, rowGap: 0.25, py: '5px' }}>
      <Box sx={{ minWidth: 0, flex: '1 1 220px' }}>
        <Box sx={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          <Dot color={CONTAINER_COLORS[c.state] ?? 'text.disabled'} />{c.name}
        </Box>
        <Box sx={{ fontFamily: MONO, fontSize: 11.5, color: 'text.secondary', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.image}</Box>
      </Box>
      {c.ports.map((p) => <Box key={p} sx={{ fontFamily: MONO, fontSize: 12, color: 'text.secondary' }}>:{p}</Box>)}
      <Box sx={{ fontSize: 12.5, textAlign: 'right', flexShrink: 0 }}>
        <Box>{c.state in STATE_LABELS ? t(STATE_LABELS[c.state]) : c.state}</Box>
        {/* Docker's own words, shown as they are */}
        <Box sx={{ color: 'text.secondary', fontSize: 11.5 }}>{c.status}</Box>
      </Box>
      {controls && (
        <Box sx={{ display: 'flex', flexShrink: 0 }}>
          {actions.map((a) => button(t(`containers.${a}`, { name: c.name }), ACTION_GLYPHS[a], () => controls.act(a)))}
          {button(t('containers.logs', { name: c.name }), 'log', controls.logs)}
        </Box>
      )}
    </Box>
  )
}

function ContainersBody({ compact, minimized }: AppProps) {
  const api = useApi()
  const { admin } = useUser()
  const { t, tn } = useI18n()
  const load = useCallback(() => api.containers(), [api])
  const { data, failed, reload } = usePolled(load, POLL_MS, useAwake(minimized))
  const [query, setQuery] = useState('')
  /** The containers an action is running on. */
  const [busy, setBusy] = useState<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = useState<string | null>(null)
  const [logsOf, setLogsOf] = useState<Container | null>(null)

  const act = async (c: Container, action: ContainerAction) => {
    setBusy((ids) => new Set(ids).add(c.id))
    setProblem(null)
    try {
      await api.containerAction(c.id, action)
    } catch {
      setProblem(t(`containers.failed.${action}`, { name: c.name }))
    }
    reload()
    setBusy((ids) => new Set([...ids].filter((id) => id !== c.id)))
  }

  if (logsOf) return <Logs container={logsOf} minimized={minimized} onBack={() => setLogsOf(null)} />
  if (!data) return <Notice>{t(failed ? 'containers.unavailable' : 'containers.loading')}</Notice>
  if (data.length === 0) return <Notice>{t('containers.none')}</Notice>

  const groups = groupContainers(data.filter((c) => matches(c, query)))
  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ flexShrink: 0, p: compact ? '10px 12px 0' : '14px 20px 0' }}>
        <TextField type="search" size="small" fullWidth value={query} placeholder={t('containers.search')}
          onChange={(e) => setQuery(e.target.value)} slotProps={{ htmlInput: { 'aria-label': t('containers.search') } }} />
        {!admin && <Box sx={{ mt: 1, fontSize: 12.5, color: 'text.secondary' }}>{t('containers.readOnly')}</Box>}
        {failed && <Alert severity="warning" sx={{ mt: 1 }}>{t('containers.unavailable')}</Alert>}
        {problem && <Alert severity="error" sx={{ mt: 1 }} onClose={() => setProblem(null)}>{problem}</Alert>}
      </Box>
      <ViewBody>
        {groups.length === 0 && <Box sx={{ color: 'text.secondary' }}>{t('containers.noMatch', { query })}</Box>}
        {groups.map((g) => (
          <Card key={g.project ?? g.items[0].id} sx={{ mb: 1.25, py: '8px' }}>
            <Box role={g.project ? 'group' : undefined} aria-label={g.project ?? undefined}>
              {g.project && (
                <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1, mb: 0.5 }}>
                  <Box sx={{ fontWeight: 600 }}>{g.project}</Box>
                  <Box sx={{ fontSize: 12.5, color: 'text.secondary' }}>
                    {t('containers.running', { running: g.items.filter(isUp).length, count: g.items.length })}
                  </Box>
                  <Box sx={{ ml: 'auto', fontSize: 12.5, color: 'text.secondary' }}>{tn('containers.count', g.items.length)}</Box>
                </Box>
              )}
              <Box role="list" aria-label={g.project ?? t('containers.list')}>
                {g.items.map((c) => (
                  <Row key={c.id} container={c}
                    controls={admin ? { busy: busy.has(c.id), act: (a) => void act(c, a), logs: () => setLogsOf(c) } : null} />
                ))}
              </Box>
            </Box>
          </Card>
        ))}
      </ViewBody>
    </Box>
  )
}

export const Containers = memo(ContainersBody)
