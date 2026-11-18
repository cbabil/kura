/**
 * Small line glyphs for menus, sidebars and the menu bar (24-unit grid,
 * stroked in currentColor), drawn for Kura so no icon font is needed.
 */
const PATHS = {
  pulse: 'M3 12h4l3-8 4 16 3-8h4',
  cpu: 'M6 6h12v12H6zM9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4',
  memory: 'M3 7h18v10H3zM7 17v3M12 17v3M17 17v3M7 10v4M11 10v4',
  disk: 'M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3',
  network: 'M7 4v16M3 8l4-4 4 4M17 20V4M13 16l4 4 4-4',
  services: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
  search: 'M11 4a7 7 0 1 1 0 14 7 7 0 0 1 0-14M20 20l-4-4',
  temp: 'M10 14V5a2 2 0 0 1 4 0v9a4 4 0 1 1-4 0z',
  ethernet: 'M5 4h14v11H5zM9 15v3M15 15v3M7 18h10M9 8v3M12 8v3M15 8v3',
  offline: 'M5 4h14v11H5zM7 18h10M4 20L20 2',
  sun: 'M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  moon: 'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5',
} as const

export type GlyphName = keyof typeof PATHS

export function Glyph({ name, size = 16 }: { name: GlyphName; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden style={{ display: 'block', flexShrink: 0 }}>
      <path d={PATHS[name]} />
    </svg>
  )
}
