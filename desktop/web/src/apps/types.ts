/**
 * What an app declares to the desktop: its window, menus, sections and where
 * it sits in the dock. Adding an app (D2: Containers, Terminal, Console)
 * means adding an AppDef; the shell itself does not change.
 */
import type { ComponentType } from 'react'
import type { MessageKey, Vars } from '../i18n'

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

/** Labels are catalogue keys, so menus follow the user's language. */
export interface MenuItem {
  label: MessageKey
  vars?: Vars
  run(ctx: MenuCtx): void
}

export interface AppMenu {
  /** A catalogue key, or a symbol shown as it is (the 蔵 menu). */
  title: MessageKey | '蔵'
  items: MenuItem[]
}

/** A section of an app, which the launcher can open directly. */
export interface AppView {
  id: string
  label: MessageKey
}

export interface AppDef {
  id: string
  /** Catalogue keys, so a missing translation fails to compile. */
  name: MessageKey
  blurb: MessageKey
  size: { w: number; h: number }
  /** 'dock': pinnable, in the launcher. 'end': fixed at the dock's end (Trash), not searchable. */
  placement: 'dock' | 'end'
  menus: AppMenu[]
  /** Sections; the first is the default. */
  views?: readonly AppView[]
  /** The window body; apps without one show what is coming. */
  Body?: ComponentType<AppProps>
}
