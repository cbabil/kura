/**
 * The signed-in user's preferences: loaded once, changed locally at once,
 * and saved to the server shortly after the last change.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import type { Api, Prefs } from './api'
import { DEFAULT_DOCK } from './shell/dockOrder'

export const DEFAULT_PREFS: Prefs = { theme: 'system', language: 'auto', dock: DEFAULT_DOCK, windows: {} }
const SAVE_DELAY_MS = 400

export function usePrefs(api: Api, signedIn: boolean) {
  const [prefs, setPrefs] = useState<Prefs>(DEFAULT_PREFS)
  const [saveFailed, setSaveFailed] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (!signedIn) return
    let live = true
    api.prefs().then(
      (saved) => live && setPrefs({ ...DEFAULT_PREFS, ...saved }),
      () => live && setPrefs(DEFAULT_PREFS),
    )
    return () => {
      live = false
    }
  }, [api, signedIn])

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current)
  }, [])

  const update = useCallback(
    (change: Partial<Prefs>) => {
      setPrefs((old) => {
        const next = { ...old, ...change }
        if (timer.current) clearTimeout(timer.current)
        timer.current = setTimeout(() => {
          api.savePrefs(next).then(() => setSaveFailed(false), () => setSaveFailed(true))
        }, SAVE_DELAY_MS)
        return next
      })
    },
    [api],
  )

  return { prefs, update, saveFailed, dismissSaveError: () => setSaveFailed(false) }
}
