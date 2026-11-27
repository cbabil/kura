/**
 * The server's browser on screen: noVNC draws what the VNC server sends and
 * passes the keyboard, the pointer and the clipboard back. One mount is one
 * view; the browser itself keeps running when this unmounts. The screen
 * follows the window's size. A separate chunk (see Browser.tsx).
 */
import { useEffect, useRef, type RefObject } from 'react'
import { Box } from '@mui/material'
import RFB from '@novnc/novnc'
import type { Api } from '../../api'
import { useI18n } from '../../i18n'

/** The X keysyms of the keys a paste sends. */
const XK = { Control: 0xffe3, Super: 0xffeb, v: 0x0076 }

/** Why a view ended: the browser went away, or never let it in. */
export type BrowserEnd = 'closed' | 'refused'
/** Types text into the server's clipboard. */
export type Paste = (text: string) => void

interface Props {
  api: Api
  onEnd(reason: BrowserEnd): void
  /** Set to this view's paste while it is mounted. */
  pasteRef: RefObject<Paste | null>
}

export default function RfbView({ api, onEnd, pasteRef }: Props) {
  const host = useRef<HTMLDivElement>(null)
  const { t } = useI18n()

  useEffect(() => {
    const target = host.current
    if (!target) return
    const rfb = new RFB(target, api.browser(), { shared: true })
    rfb.resizeSession = true
    rfb.focusOnClick = true
    rfb.background = 'transparent'
    let connected = false
    let leaving = false
    /** The clipboard text last passed either way, so neither side's copy is overwritten by an old one. */
    let last = ''
    rfb.addEventListener('connect', () => {
      connected = true
      rfb.focus()
    })
    rfb.addEventListener('disconnect', () => {
      if (!leaving) onEnd(connected ? 'closed' : 'refused')
    })
    rfb.addEventListener('clipboard', (e) => {
      last = e.detail.text
      navigator.clipboard?.writeText(last).catch(() => {}) // a refused write leaves the server's copy where it is
    })
    // Ctrl+V or ⌘+V here pastes what was copied here: the clipboard is read
    // then, and only then (never on a mere click: everyone watching would get
    // it), handed over, and the server's browser is sent Ctrl+V. A browser
    // that will not share its clipboard pastes the server's own.
    const onKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey) || e.altKey || e.key.toLowerCase() !== 'v') return
      e.preventDefault()
      e.stopPropagation()
      const ctrlV = () => {
        if (e.metaKey) rfb.sendKey(XK.Super, 'MetaLeft', false)
        rfb.sendKey(XK.Control, 'ControlLeft', true)
        rfb.sendKey(XK.v, 'KeyV')
        rfb.sendKey(XK.Control, 'ControlLeft', false)
      }
      const read = navigator.clipboard?.readText?.()
      if (!read) return ctrlV()
      read.then((text) => {
        if (text && text !== last) {
          last = text
          rfb.clipboardPasteFrom(text)
        }
      }, () => {}).finally(ctrlV)
    }
    pasteRef.current = (text) => {
      last = text
      rfb.clipboardPasteFrom(text)
      rfb.focus()
    }
    // Before noVNC's own listeners on the canvas inside
    target.addEventListener('keydown', onKey, true)
    return () => {
      leaving = true
      pasteRef.current = null
      target.removeEventListener('keydown', onKey, true)
      rfb.disconnect()
    }
  }, [api, onEnd, pasteRef])

  return (
    <Box ref={host} data-keys="app" role="application" aria-label={t('browser.label')}
      sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', overflow: 'hidden', bgcolor: 'background.paper' }} />
  )
}
