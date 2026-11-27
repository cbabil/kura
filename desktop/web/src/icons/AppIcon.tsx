/**
 * App icons: the hand-drawn SVGs in ./apps (approved 2026-11-17), shown as
 * images so the browser caches them. Apps without a drawn icon (container
 * apps, from D2) get a generated squircle with their initial.
 */
import activity from './apps/activity.svg'
import browser from './apps/browser.svg'
import catalog from './apps/catalog.svg'
import consoleIcon from './apps/console.svg'
import containers from './apps/containers.svg'
import files from './apps/files.svg'
import settings from './apps/settings.svg'
import terminal from './apps/terminal.svg'
import trash from './apps/trash.svg'

export const ICONS: Record<string, string> = {
  activity, browser, catalog, console: consoleIcon, containers, files, settings, terminal, trash,
}

const FALLBACK_HUES = [262, 228, 199, 160, 32, 340]

/** A stable hue for an app without its own icon. */
export function hueFor(name: string): number {
  let h = 0
  for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0
  return FALLBACK_HUES[h % FALLBACK_HUES.length]
}

interface Props {
  app: string
  name: string
  size: number
}

export function AppIcon({ app, name, size }: Props) {
  const src = ICONS[app]
  if (src) return <img src={src} width={size} height={size} alt="" draggable={false} style={{ display: 'block' }} />
  const hue = hueFor(name)
  return (
    <span
      aria-hidden
      style={{
        width: size * 0.8, height: size * 0.8, margin: size * 0.1, borderRadius: size * 0.18,
        display: 'grid', placeItems: 'center', color: '#fff', fontWeight: 700, fontSize: size * 0.36,
        background: `linear-gradient(145deg, hsl(${hue} 85% 62%), hsl(${hue} 70% 38%))`,
        boxShadow: `0 ${size * 0.04}px ${size * 0.08}px rgba(2,6,23,.35)`,
      }}
    >
      {name.slice(0, 1).toUpperCase()}
    </span>
  )
}
