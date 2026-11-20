/** The wallpaper, the "coming in an update" window body, and About Kura. */
import type { ReactNode } from 'react'
import { Box, Dialog, DialogContent } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { SystemInfo } from '../api'
import type { AppDef } from '../apps/types'
import { MINCHO } from '../theme'
import { AppIcon } from '../icons/AppIcon'
import { appText } from '../apps/registry'
import { useI18n } from '../i18n'

export function Wallpaper({ hostname }: { hostname: string }) {
  const k = useTheme().kura
  const { t } = useI18n()
  return (
    <Box aria-hidden sx={{ position: 'absolute', inset: 0, background: k.wall, overflow: 'hidden' }}>
      <Box sx={{ position: 'absolute', right: '5%', bottom: '10%', fontSize: 'min(62vh, 560px)', lineHeight: 1,
        fontFamily: MINCHO, color: k.glyph, userSelect: 'none' }}>蔵</Box>
      <Box sx={{ position: 'absolute', left: 44, bottom: 120, color: 'text.secondary', display: { xs: 'none', md: 'block' } }}>
        <Kicker>蔵 · {t('brand.kicker')}</Kicker>
        {hostname}.local
      </Box>
    </Box>
  )
}

/** The small spaced caps line above "Kura" (the README banner's kicker). */
export function Kicker({ children }: { children: ReactNode }) {
  return <Box sx={{ fontSize: 11, letterSpacing: '2.4px', color: 'primary.light', fontWeight: 500 }}>{children}</Box>
}

export function ComingSoon({ app }: { app: AppDef }) {
  const { t } = useI18n()
  const name = appText(t, app.id, 'name')
  return (
    <Box sx={{ flex: 1, display: 'grid', placeItems: 'center', textAlign: 'center', p: 3 }}>
      <Box>
        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}><AppIcon app={app.id} name={name} size={112} /></Box>
        <Box sx={{ fontSize: 20, fontWeight: 600 }}>{name}</Box>
        <Box sx={{ color: 'text.secondary', mt: 0.5 }}>{appText(t, app.id, 'blurb')}</Box>
        <Box sx={{ color: 'text.secondary', mt: 2, fontSize: 13 }}>{t('comingSoon')}</Box>
      </Box>
    </Box>
  )
}

export function About({ open, system, onClose }: { open: boolean; system: SystemInfo | null; onClose(): void }) {
  const { t, tn, format } = useI18n()
  const rows: [string, string][] = system
    ? [
        [t('about.version'), system.os],
        [t('about.host'), system.hostname],
        [t('about.kernel'), system.kernel],
        [t('about.processor'), tn('about.cores', system.cores, { arch: system.arch })],
        [t('about.memory'), format.bytes(system.memTotal)],
      ]
    : []
  return (
    <Dialog open={open} onClose={onClose} aria-labelledby="about-title" slotProps={{ paper: { sx: { width: 360, textAlign: 'center' } } }}>
      <DialogContent>
        <Box sx={{ fontFamily: MINCHO, fontSize: 64, lineHeight: 1, color: 'primary.light' }}>蔵</Box>
        <Box id="about-title" sx={{ fontSize: 24, fontWeight: 700, mt: 1 }}>Kura</Box>
        <Box sx={{ color: 'text.secondary', mb: 2 }}>{t('brand.tagline')}</Box>
        {rows.map(([k, v]) => (
          <Box key={k} sx={{ display: 'flex', gap: 2, fontSize: 13, py: 0.25 }}>
            <Box sx={{ flex: 1, textAlign: 'right', color: 'text.secondary' }}>{k}</Box>
            <Box sx={{ flex: 1.4, textAlign: 'left' }}>{v}</Box>
          </Box>
        ))}
      </DialogContent>
    </Dialog>
  )
}
