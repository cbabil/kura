/** The wallpaper, the "coming in an update" window body, and About Kura. */
import type { ReactNode } from 'react'
import { Box, Dialog, DialogContent } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { SystemInfo } from '../api'
import type { AppDef } from '../apps/types'
import { MINCHO } from '../theme'
import { AppIcon } from '../icons/AppIcon'
import { bytes } from '../apps/activity/format'

export function Wallpaper({ hostname }: { hostname: string }) {
  const k = useTheme().kura
  return (
    <Box aria-hidden sx={{ position: 'absolute', inset: 0, background: k.wall, overflow: 'hidden' }}>
      <Box sx={{ position: 'absolute', right: '5%', bottom: '10%', fontSize: 'min(62vh, 560px)', lineHeight: 1,
        fontFamily: MINCHO, color: k.glyph, userSelect: 'none' }}>蔵</Box>
      <Box sx={{ position: 'absolute', left: 44, bottom: 120, color: 'text.secondary', display: { xs: 'none', md: 'block' } }}>
        <Kicker>蔵 · THE STOREHOUSE</Kicker>
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
  return (
    <Box sx={{ flex: 1, display: 'grid', placeItems: 'center', textAlign: 'center', p: 3 }}>
      <Box>
        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}><AppIcon app={app.id} name={app.name} size={112} /></Box>
        <Box sx={{ fontSize: 20, fontWeight: 600 }}>{app.name}</Box>
        <Box sx={{ color: 'text.secondary', mt: 0.5 }}>{app.blurb}</Box>
        <Box sx={{ color: 'text.secondary', mt: 2, fontSize: 13 }}>Arrives in a coming update of Kura.</Box>
      </Box>
    </Box>
  )
}

export function About({ open, system, onClose }: { open: boolean; system: SystemInfo | null; onClose(): void }) {
  const rows: [string, string][] = system
    ? [
        ['Version', system.os],
        ['Host', system.hostname],
        ['Kernel', system.kernel],
        ['Processor', `${system.arch} · ${system.cores} cores`],
        ['Memory', bytes(system.memTotal)],
      ]
    : []
  return (
    <Dialog open={open} onClose={onClose} aria-labelledby="about-title" slotProps={{ paper: { sx: { width: 360, textAlign: 'center' } } }}>
      <DialogContent>
        <Box sx={{ fontFamily: MINCHO, fontSize: 64, lineHeight: 1, color: 'primary.light' }}>蔵</Box>
        <Box id="about-title" sx={{ fontSize: 24, fontWeight: 700, mt: 1 }}>Kura</Box>
        <Box sx={{ color: 'text.secondary', mb: 2 }}>The lightweight OS for your home server.</Box>
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
