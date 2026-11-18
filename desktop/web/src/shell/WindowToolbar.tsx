/**
 * Lets an app put controls in its window's title bar (like Activity Monitor's
 * range switch) while keeping their state inside the app.
 */
import { createContext, useContext, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

export const ToolbarSlot = createContext<HTMLElement | null>(null)

export function WindowToolbar({ children }: { children: ReactNode }) {
  const slot = useContext(ToolbarSlot)
  return slot ? createPortal(children, slot) : null
}
