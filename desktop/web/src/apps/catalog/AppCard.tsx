/** One app of the catalog: what it is, whether it is installed, and what can be done with it. */
import { Box, Button, Link } from '@mui/material'
import type { CatalogApp } from '../../api'
import { useI18n, type MessageKey } from '../../i18n'
import { colors } from '../../theme'
import { Card, Dot } from '../parts'

/** What each shipped app is, in a sentence. An app without one shows its name only. */
const BLURBS: Record<string, MessageKey> = {
  'adguard-home': 'catalog.blurb.adguard-home', gitea: 'catalog.blurb.gitea', 'home-assistant': 'catalog.blurb.home-assistant',
  jellyfin: 'catalog.blurb.jellyfin', syncthing: 'catalog.blurb.syncthing', 'uptime-kuma': 'catalog.blurb.uptime-kuma',
}

interface Props {
  app: CatalogApp
  /** A job runs or is being started: nothing else can be. */
  busy: boolean
  onInstall(): void
  onUpdate(): void
  onRemove(): void
}

export function AppCard({ app, busy, onInstall, onUpdate, onRemove }: Props) {
  const { t } = useI18n()
  const { installed } = app
  const outdated = installed !== null && installed.version !== app.version
  const blurb = BLURBS[app.id]
  return (
    <Card sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
      <Box role="listitem" aria-label={app.name} sx={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1 }}>
          <Box sx={{ fontWeight: 600, fontSize: 15 }}>{app.name}</Box>
          <Box sx={{ ml: 'auto', fontSize: 12, color: 'text.secondary' }}>{t('catalog.version', { version: app.version })}</Box>
        </Box>
        {blurb && <Box sx={{ fontSize: 12.5, color: 'text.secondary', flex: 1 }}>{t(blurb)}</Box>}
        <Box sx={{ fontSize: 12.5 }}>
          <Dot color={installed ? colors.success : 'text.disabled'} />
          {installed ? t('catalog.installed', { port: installed.port }) : t('catalog.notInstalled')}
        </Box>
        {outdated && <Box sx={{ fontSize: 12.5, color: colors.warning }}>{t('catalog.updateTo', { installed: installed.version, version: app.version })}</Box>}
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexWrap: 'wrap' }}>
          {installed ? (
            <>
              {/* The app's own page, on its own port: plain HTTP unless the app is set up otherwise. */}
              <Button size="small" variant="contained" component="a" href={`http://${location.hostname}:${installed.port}`} target="_blank" rel="noopener noreferrer">
                {t('catalog.open')}
              </Button>
              {outdated && <Button size="small" disabled={busy} onClick={onUpdate}>{t('catalog.update')}</Button>}
              <Button size="small" color="error" disabled={busy} onClick={onRemove}>{t('catalog.remove')}</Button>
            </>
          ) : (
            <Button size="small" variant="contained" disabled={busy} onClick={onInstall}>{t('catalog.install')}</Button>
          )}
          <Link href={app.homepage} target="_blank" rel="noopener noreferrer" sx={{ ml: 'auto', fontSize: 12.5 }}>{t('catalog.website')}</Link>
        </Box>
      </Box>
    </Card>
  )
}
