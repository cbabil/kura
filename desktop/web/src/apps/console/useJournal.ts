/**
 * The journal entries a Console window shows: the newest ones for the
 * chosen unit and priority, then, while following, whatever is written
 * after them. A request that fails, or a filter that matches nothing yet,
 * is asked again on the next turn.
 */
import { useEffect, useRef, useState } from 'react'
import type { Api, JournalEntry } from '../../api'

/** Entries asked for at first. */
export const LINES = 300
/** Entries kept on screen; older ones drop off the top while following. */
const KEEP = 1000
const POLL_MS = 3000

/** An entry with a number of its own, so a row keeps its place as others come and go. */
export type Row = JournalEntry & { id: number }

export interface Journal {
  /** null until the first answer for this unit and priority. */
  entries: Row[] | null
  failed: boolean
}

const WAITING: Journal = { entries: null, failed: false }

export function useJournal(api: Api, unit: string, priority: number | undefined, follow: boolean, awake = true): Journal {
  const filter = `${unit}|${priority ?? ''}`
  const [state, setState] = useState<Journal & { filter: string }>({ ...WAITING, filter })
  /** The cursor after the last entry shown, and the filter it belongs to. */
  const place = useRef<{ filter: string; cursor: string | null }>({ filter, cursor: null })
  const nextId = useRef(0)

  useEffect(() => {
    if (!awake) return
    let live = true
    if (place.current.filter !== filter) place.current = { filter, cursor: null }
    const ask = () => {
      const after = place.current.cursor
      api.journal({ lines: LINES, unit, priority, ...(after ? { after } : {}) }).then(
        (page) => {
          if (!live) return
          const fresh = page.entries.map((e) => ({ ...e, id: nextId.current++ }))
          place.current = { filter, cursor: page.cursor ?? after }
          setState((s) => {
            const shown = s.filter === filter ? s.entries : null
            if (after && shown && fresh.length === 0) return s
            return { filter, failed: false, entries: after && shown ? [...shown, ...fresh].slice(-KEEP) : fresh }
          })
        },
        // What is on screen stays; with nothing on screen, say so.
        () => live && setState((s) => (s.filter === filter && s.entries ? s : { filter, entries: null, failed: true })),
      )
    }
    // A new filter, nothing shown yet, or following again after a pause: ask now.
    if (follow || !place.current.cursor) ask()
    const timer = follow ? setInterval(ask, POLL_MS) : undefined
    return () => {
      live = false
      clearInterval(timer)
    }
  }, [api, unit, priority, filter, follow, awake])

  return state.filter === filter ? state : WAITING
}
