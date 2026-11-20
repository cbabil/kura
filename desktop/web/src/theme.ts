/**
 * Kura's MUI theme (dark and light), from the owner's design tokens:
 * purple #9146FF on navy, Inter 14 px, no ripple or click effects, and icon
 * buttons that only change colour on hover.
 */
import { createTheme, type Theme } from '@mui/material/styles'

export const colors = {
  primary: '#9146FF',
  boost: '#7B31FF',
  iconHover: '#B388FF',
  error: '#ef4444',
  success: '#23ce6b',
  warning: '#f59e0b',
  info: '#4c6ef5',
}

const modes = {
  dark: {
    background: '#0f172a', paper: '#111a2e', chrome: '#0c1424', text: '#e2e8f0', muted: '#94a3b8',
    faint: '#64748b', divider: '#1f2937', edge: '#1f2a40', selected: colors.iconHover, selectedBg: 'rgba(145, 70, 255, .18)',
    bar: 'rgba(15, 23, 42, .72)', dock: 'rgba(17, 26, 46, .62)',
    wall: `radial-gradient(1200px 700px at 78% 18%, rgba(145,70,255,.28), transparent 60%),
      radial-gradient(900px 600px at 10% 95%, rgba(76,110,245,.16), transparent 60%), #0b1222`,
    glyph: 'rgba(145, 70, 255, .10)', shadow: '0 24px 70px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.04)',
  },
  light: {
    background: '#f7f7fa', paper: '#ffffff', chrome: '#f7f7fa', text: '#111827', muted: '#6b7280',
    faint: '#9ca3af', divider: '#d1d5db', edge: '#d1d5db', selected: colors.boost, selectedBg: 'rgba(145, 70, 255, .14)',
    bar: 'rgba(255, 255, 255, .72)', dock: 'rgba(255, 255, 255, .55)',
    wall: `radial-gradient(1200px 700px at 78% 18%, rgba(145,70,255,.22), transparent 60%),
      radial-gradient(900px 600px at 10% 95%, rgba(76,110,245,.14), transparent 60%), #eef0f6`,
    glyph: 'rgba(145, 70, 255, .09)', shadow: '0 24px 60px rgba(17,24,39,.18), 0 0 0 1px rgba(17,24,39,.06)',
  },
}

/** The serif stack for the 蔵 glyph (Hiragino on macOS, Noto Serif JP elsewhere). */
export const MINCHO = '"Hiragino Mincho ProN", "Noto Serif JP", serif'

export type Mode = keyof typeof modes
/** Kura's extra surface tokens; text, background and divider colours come from the palette. */
export type Surface = Omit<(typeof modes)[Mode], 'background' | 'paper' | 'text' | 'muted' | 'divider'>

declare module '@mui/material/styles' {
  interface Theme {
    kura: Surface
  }
  interface ThemeOptions {
    kura?: Surface
  }
}

export function makeTheme(mode: Mode): Theme {
  const s = modes[mode]
  const { background, paper, text, muted, divider, ...kura } = s
  return createTheme({
    kura,
    palette: {
      mode,
      primary: { main: colors.primary, dark: colors.boost },
      error: { main: colors.error },
      success: { main: colors.success },
      warning: { main: colors.warning },
      info: { main: colors.info },
      background: { default: background, paper },
      text: { primary: text, secondary: muted },
      divider,
      action: { selected: s.selectedBg },
    },
    typography: { fontFamily: '"Inter Variable", Inter, system-ui, -apple-system, sans-serif', fontSize: 14 },
    shape: { borderRadius: 8 },
    components: {
      MuiButtonBase: { defaultProps: { disableRipple: true } },
      MuiButton: {
        defaultProps: { disableElevation: true },
        styleOverrides: { root: { textTransform: 'none', fontWeight: 500, transition: 'background-color 120ms, color 120ms' } },
      },
      MuiIconButton: {
        styleOverrides: {
          root: {
            color: muted,
            backgroundColor: 'transparent',
            '&:hover, &:focus-visible, &:active': { backgroundColor: 'transparent', color: colors.iconHover },
          },
        },
      },
      MuiTooltip: {
        styleOverrides: {
          tooltip: { background: paper, color: text, border: `1px solid ${s.edge}`, fontSize: 13, fontWeight: 400 },
        },
      },
      MuiMenu: { styleOverrides: { paper: { border: `1px solid ${s.edge}`, backgroundImage: 'none' } } },
      MuiPaper: { styleOverrides: { outlined: { borderRadius: 10, borderColor: divider, backgroundColor: 'transparent' } } },
    },
  })
}
