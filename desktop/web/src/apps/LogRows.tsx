/**
 * Lines of a log, newest last: a container's output or the system journal.
 * The view stays at the bottom while new lines arrive, unless the reader
 * has scrolled up.
 */
import { memo, useLayoutEffect, useRef } from 'react'
import { Box } from '@mui/material'
import { useI18n } from '../i18n'
import { MONO } from './parts'

export interface LogRow {
  key: string | number
  /** Unix ms, or null when the line has no time. */
  t: number | null
  /** Who wrote it (the journal's program or unit). */
  source?: string
  text: string
  tone?: 'error' | 'warning'
}

const TONES = { error: 'error.main', warning: 'warning.main' } as const
/** How close to the bottom still counts as "at the bottom", in pixels. */
const NEAR = 40

function Rows({ label, rows }: { label: string; rows: LogRow[] }) {
  const { format } = useI18n()
  const box = useRef<HTMLDivElement>(null)
  const pinned = useRef(true)

  useLayoutEffect(() => {
    const el = box.current
    if (el && pinned.current) el.scrollTop = el.scrollHeight
  }, [rows])

  return (
    <Box ref={box} role="log" aria-label={label} tabIndex={0} className="no-scrollbar"
      onScroll={(e) => {
        const el = e.currentTarget
        pinned.current = el.scrollHeight - el.scrollTop - el.clientHeight < NEAR
      }}
      sx={{ flex: 1, minWidth: 0, minHeight: 0, overflowY: 'auto', p: '10px 14px', fontFamily: MONO, fontSize: 12.5, lineHeight: 1.55 }}>
      <Box role="list">
        {rows.map((r) => (
          <Box key={r.key} role="listitem" data-tone={r.tone} sx={{ display: 'flex', gap: '10px', color: r.tone ? TONES[r.tone] : 'text.primary' }}>
            {r.t !== null && <Box component="time" sx={{ flexShrink: 0, color: 'text.secondary' }}>{format.clock(new Date(r.t))}</Box>}
            {r.source !== undefined && (
              <Box component="span" sx={{ flexShrink: 0, width: '16ch', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: 'text.secondary' }}>
                {r.source}
              </Box>
            )}
            <Box component="span" sx={{ minWidth: 0, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{r.text}</Box>
          </Box>
        ))}
      </Box>
    </Box>
  )
}

/** Draws again only when its rows change (hundreds of them, in windows that re-render for other reasons). */
export const LogRows = memo(Rows)
