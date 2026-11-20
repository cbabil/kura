/**
 * The desktop's fixed measurements and the viewport they leave for windows.
 * Every component that places chrome reads these, so they stay in step.
 */

export const MENU_BAR = 30
export const TITLE_BAR = 40
/** Space the dock takes at the bottom, on a wide screen and on a phone. */
export const DOCK_SPACE = 96
export const COMPACT_DOCK_SPACE = 76
export const DOCK_ICON = 64
export const COMPACT_DOCK_ICON = 38
/** Below this width windows go full screen, one at a time. */
export const COMPACT_WIDTH = 768

/** The desktop area: viewport size, the bars above and below, and whether it is a phone layout. */
export interface Bounds {
  width: number
  height: number
  top: number
  bottom: number
  compact: boolean
}

export function boundsFor(width: number, height: number): Bounds {
  const compact = width < COMPACT_WIDTH
  return { width, height, top: MENU_BAR, bottom: compact ? COMPACT_DOCK_SPACE : DOCK_SPACE, compact }
}
