/**
 * What an app declares to the desktop: its window, menus, sections and where
 * it sits in the dock. Adding an app (D2: Containers, Terminal, Console)
 * means adding an AppDef; the shell itself does not change.
 */
import type { ComponentType } from 'react'

/** What the desktop hands an app's window body. */
export interface AppProps {
  /** The section shown (one of AppDef.views), or '' for apps without sections. */
  view: string
  setView(view: string): void
  compact: boolean
}

/** Actions a menu item can take on the focused window. */
export interface MenuCtx {
  close(): void
  minimize(): void
  zoom(): void
  setView(view: string): void
  about(): void
}

export interface MenuItem {
  label: string
  run(ctx: MenuCtx): void
}

export interface AppMenu {
  title: string
  items: MenuItem[]
}

export interface AppDef {
  id: string
  name: string
  blurb: string
  size: { w: number; h: number }
  /** 'dock': pinnable, in the launcher. 'end': fixed at the dock's end (Trash), not searchable. */
  placement: 'dock' | 'end'
  menus: AppMenu[]
  /** Sections the launcher can open directly; the first is the default. */
  views?: readonly string[]
  /** The window body; apps without one show what is coming. */
  Body?: ComponentType<AppProps>
}
