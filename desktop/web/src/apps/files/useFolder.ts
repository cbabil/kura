/** What Files' panes share: a folder asked again now and then, and the words for a refusal. */
import { useCallback } from 'react'
import { ApiError, type ApiErrorCode, type Folder } from '../../api'
import type { MessageKey } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { usePolled } from '../usePolled'

/** How often Files and the Trash ask again. */
export const POLL_MS = 10_000

const REFUSALS: Partial<Record<ApiErrorCode, MessageKey>> = {
  exists: 'files.error.exists', denied: 'files.error.denied', not_found: 'files.error.missing', bad_request: 'files.error.name',
}

/** The message for a change the server did not make. */
export const errorKey = (e: unknown): MessageKey => (e instanceof ApiError ? REFUSALS[e.code] : undefined) ?? 'files.error.failed'

const stamps = new Map<string, Intl.DateTimeFormat>()

/** A file's date with its year and the time, in the user's language (`secs` since 1970). */
export function whenText(lang: string, secs: number): string {
  const stamp = stamps.get(lang) ?? new Intl.DateTimeFormat(lang, { dateStyle: 'medium', timeStyle: 'short' })
  stamps.set(lang, stamp)
  return stamp.format(new Date(secs * 1000))
}

/** Why a folder will not be shown however often it is asked for. */
const UNREADABLE: Partial<Record<ApiErrorCode, MessageKey>> = { denied: 'files.denied', not_found: 'files.missing', no_shell: 'files.noShell' }

/**
 * A folder as last read, or why it cannot be shown. `path` null is the home
 * folder. One reading that fails (the server busy with a long copy, a
 * moment without network) leaves the last one on screen.
 */
export function useFolder(path: string | null, awake: boolean) {
  const api = useApi()
  const load = useCallback(
    () => api.files(path ?? undefined).catch((e: unknown): { unreadable: MessageKey } => {
      const why = e instanceof ApiError ? UNREADABLE[e.code] : undefined
      if (!why) throw e
      return { unreadable: why }
    }),
    [api, path],
  )
  const { data, failed, reload } = usePolled<Folder | { unreadable: MessageKey }>(load, POLL_MS, awake)
  const folder = data ?? (failed ? { unreadable: 'files.unavailable' as const } : null)
  return { folder, reload }
}
