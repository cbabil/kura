/**
 * Dragging in the dock, as on a Mac: press an icon and move, and the icons
 * part where it will land; let go to put it there. A running app that is not
 * kept is kept by dropping it among the others. A kept app pulled up and away
 * from the dock is removed from it (its window, if open, stays). Escape
 * cancels. A press that does not move is a click.
 *
 * The pointer, not the browser's drag and drop: once a press moves, the dock
 * captures the pointer (as a window's title bar does), so the release lands
 * on the dock and never opens the app under it. The gap is a real empty slot
 * (no moving or animated buttons, per the theme). The dragged icon follows
 * the pointer by its own style; the dock re-renders only when the slot
 * changes. Touch keeps the long-press menu; dragging is for a mouse or a pen.
 */
import { useEffect, useRef, useState, type PointerEvent } from 'react'
import { placeAt, slotAt, unpin } from './dockOrder'

/** How far a press moves before it is a drag, in pixels. */
const START = 4
/** How far above the dock a kept app must be pulled to be removed. */
const PULL_OUT = 56

/** What is being dragged and where it would land: a slot among the kept apps, or out of the dock. */
export interface DockDrag {
  app: string
  slot: number | null
  out: boolean
}

interface Press {
  app: string
  kept: boolean
  x0: number
  y0: number
  /** The centres of the other kept icons, measured when the press began. */
  centres: number[]
  top: number
  /** Set once the press has moved far enough; null while it is still a click. */
  drag: DockDrag | null
  cancelled: boolean
}

export function useDockDrag(pinned: string[], onPinnedChange: (next: string[]) => void) {
  const [drag, setDrag] = useState<DockDrag | null>(null)
  const press = useRef<Press | null>(null)
  const dock = useRef<HTMLElement>(null)
  /** The dragged icon's element and the pointer's last place, to move it without a render. */
  const floating = useRef<HTMLElement | null>(null)
  const at = useRef({ x: 0, y: 0 })
  const place = () => {
    const el = floating.current
    if (el) el.style.transform = `translate(${at.current.x}px, ${at.current.y}px) translate(-50%, -50%)`
  }

  // Escape cancels a drag; the release that follows still lands on the dock.
  useEffect(() => {
    if (!drag) return
    const key = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || !press.current) return
      press.current.cancelled = true
      setDrag(null)
    }
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  }, [drag])

  /** On an icon: a press that may become a drag. */
  const begin = (app: string, e: PointerEvent<HTMLElement>) => {
    if (e.button !== 0 || e.pointerType === 'touch' || !dock.current) return
    const others = [...dock.current.querySelectorAll<HTMLElement>('[data-kept]')].filter((el) => el.dataset.kept !== app)
    press.current = {
      app, kept: pinned.includes(app), x0: e.clientX, y0: e.clientY, cancelled: false, drag: null,
      centres: others.map((el) => {
        const r = el.getBoundingClientRect()
        return r.left + r.width / 2
      }),
      top: dock.current.getBoundingClientRect().top,
    }
  }

  const move = (e: PointerEvent<HTMLElement>) => {
    const p = press.current
    if (!p || p.cancelled) return
    // A press let go away from the dock, before it was a drag, was a click elsewhere
    if (!p.drag && e.buttons === 0) {
      press.current = null
      return
    }
    if (!p.drag && Math.hypot(e.clientX - p.x0, e.clientY - p.y0) < START) return
    if (!p.drag) dock.current?.setPointerCapture?.(e.pointerId)
    at.current = { x: e.clientX, y: e.clientY }
    place()
    const away = e.clientY < p.top - PULL_OUT
    const next = { app: p.app, out: away && p.kept, slot: away ? null : slotAt(p.centres, e.clientX) }
    if (next.out !== p.drag?.out || next.slot !== p.drag?.slot) setDrag(next)
    p.drag = next
  }

  /** The release: puts the icon where it was shown landing. */
  const end = () => {
    const p = press.current
    press.current = null
    if (!p?.drag) return
    setDrag(null)
    if (p.cancelled) return
    if (p.drag.out) onPinnedChange(unpin(pinned, p.app))
    else if (p.drag.slot !== null) {
      const next = placeAt(pinned, p.app, p.drag.slot)
      if (next.join() !== pinned.join()) onPinnedChange(next)
    }
  }

  /** The pointer stream was lost (another program took it): nothing moves. */
  const cancel = () => {
    if (press.current) press.current.cancelled = true
    end()
  }

  /** Gives the dragged icon's element, placed at once where the pointer is. */
  const floatRef = (el: HTMLElement | null) => {
    floating.current = el
    place()
  }

  const dockProps = { ref: dock, onPointerMove: move, onPointerUp: end, onPointerCancel: cancel }
  return { drag, begin, dockProps, floatRef }
}
