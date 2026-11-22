/**
 * App Catalog (D4): the apps Kura ships as fixed templates. An
 * administrator installs one on a port of their choosing, updates it to the
 * version this Kura ships, or removes it; the server does it as a job and
 * this window shows what the job wrote (ADR-032).
 */
import { useCallback, useMemo, useState } from 'react'
import { Alert, Box, LinearProgress } from '@mui/material'
import type { AppChange, Catalog as CatalogData, CatalogApp } from '../../api'
import { useI18n } from '../../i18n'
import { useApi, useUser } from '../../shell/DesktopData'
import { LogRows, type LogRow } from '../LogRows'
import type { AppProps } from '../types'
import { Card, Notice, SectionTitle, ViewBody } from '../parts'
import { useAwake, usePolled, useSettle } from '../usePolled'
import { AppCard } from './AppCard'
import { InstallDialog, RemoveDialog } from './CatalogDialogs'

/** While a job runs the server is asked often; otherwise now and then. */
const BUSY_MS = 2000
/** A start whose answer looks like the last one stops being waited for after this. */
const SETTLE_MS = 3 * BUSY_MS
const IDLE_MS = 15_000

type Asking = null | { what: 'install' | 'remove'; app: CatalogApp }

function Loaded({ minimized }: { minimized: boolean }) {
  const api = useApi()
  const { t } = useI18n()
  /** A change was sent and the server's next answer is awaited. */
  const [asked, setAsked] = useState(false)
  const settle = useCallback(() => setAsked(false), [])
  useSettle(asked, settle, SETTLE_MS)
  const [refused, setRefused] = useState(false)
  const [asking, setAsking] = useState<Asking>(null)
  const [shown, setShown] = useState<CatalogData | null>(null)
  const load = useCallback(() => api.catalog(), [api])
  const { data, failed, reload } = usePolled(load, asked || shown?.job?.state === 'running' ? BUSY_MS : IDLE_MS, useAwake(minimized))
  if (data && data !== shown) {
    setShown(data)
    setAsked(false)
  }
  const rows = useMemo<LogRow[]>(() => (data?.job?.output ?? []).map((text, i) => ({ key: i, t: null, text })), [data])
  if (!data) return <Notice>{t(failed ? 'catalog.unavailable' : 'catalog.loading')}</Notice>

  const busy = asked || data.job?.state === 'running'
  const run = (change: AppChange) => {
    setAsking(null)
    setAsked(true)
    setRefused(false)
    api.changeApp(change).then(reload, () => {
      setAsked(false)
      setRefused(true)
    })
  }
  return (
    <ViewBody>
      <SectionTitle>{t('app.catalog.name')}</SectionTitle>
      <Box sx={{ mb: 1.5, fontSize: 12.5, color: 'text.secondary' }}>{t('catalog.intro')}</Box>
      {busy && <LinearProgress aria-label={t('catalog.running')} sx={{ mb: 1.5 }} />}
      {refused && <Alert severity="error" sx={{ mb: 1.5 }} onClose={() => setRefused(false)}>{t('catalog.refused')}</Alert>}
      {data.job?.state === 'failed' && <Alert severity="error" sx={{ mb: 1.5 }}>{t('catalog.failed')}</Alert>}
      <Box role="list" aria-label={t('catalog.list')}
        sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: '12px', alignContent: 'start', mb: 2 }}>
        {data.apps.map((app) => (
          <AppCard key={app.id} app={app} busy={busy} onInstall={() => setAsking({ what: 'install', app })}
            onUpdate={() => run({ what: 'update', id: app.id })} onRemove={() => setAsking({ what: 'remove', app })} />
        ))}
      </Box>
      {data.job?.state === 'done' && <Box role="status" sx={{ mb: 1, color: 'text.secondary' }}>{t('catalog.done')}</Box>}
      {rows.length > 0 && <Card sx={{ p: 0, display: 'flex', maxHeight: 200 }}><LogRows label={t('catalog.output')} rows={rows} /></Card>}
      {asking?.what === 'install' && (
        <InstallDialog app={asking.app} onClose={() => setAsking(null)} onInstall={(port) => run({ what: 'install', id: asking.app.id, port })} />
      )}
      {asking?.what === 'remove' && (
        <RemoveDialog app={asking.app} onClose={() => setAsking(null)} onRemove={(data) => run({ what: 'remove', id: asking.app.id, data })} />
      )}
    </ViewBody>
  )
}

export function Catalog({ minimized }: AppProps) {
  const { t } = useI18n()
  // The server refuses others too; not asking spares them an error.
  return useUser().admin ? <Loaded minimized={minimized} /> : <Notice>{t('catalog.adminOnly')}</Notice>
}
