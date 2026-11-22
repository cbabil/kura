/**
 * What Settings' sections share: the settings themselves (asked again now
 * and then, and after each change), one change at a time with its error,
 * and the frame that shows "loading", "administrators only" or the section.
 */
import { useCallback, useState, type ReactNode } from 'react'
import { Alert } from '@mui/material'
import { ApiError, type SettingChange, type Settings } from '../../api'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi, useUser } from '../../shell/DesktopData'
import { Notice, ViewBody } from '../parts'
import { useAwake, usePolled } from '../usePolled'

const REFRESH_MS = 15_000

/** What a section gets: the settings as last read, and how to read them again. */
export interface SectionProps {
  settings: Settings
  reload(): void
}

export interface Changer {
  busy: boolean
  /** Why the last change was refused, or null. */
  error: MessageKey | null
  /** Forgets the last refusal (a dialog closed, another opens). */
  clear(): void
  /** Makes one change; `then` runs when it worked. */
  run(change: SettingChange, then?: () => void): void
}

/** The message for a refused change: a value that is not right, or the server saying no. */
export const refusalKey = (e: unknown): MessageKey =>
  e instanceof ApiError && e.code === 'bad_request' ? 'settings.invalid' : 'settings.failed'

export function useChange(reload: () => void): Changer {
  const api = useApi()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<MessageKey | null>(null)
  const run = useCallback((change: SettingChange, then?: () => void) => {
    setBusy(true)
    setError(null)
    api.changeSetting(change).then(
      () => then?.(),
      (e: unknown) => setError(refusalKey(e)),
    ).finally(() => {
      reload()
      setBusy(false)
    })
  }, [api, reload])
  const clear = useCallback(() => setError(null), [])
  return { busy, error, clear, run }
}

/** The line that says why a change was refused. */
export function ChangeError({ error }: { error: MessageKey | null }) {
  const { t } = useI18n()
  return error ? <Alert severity="error" sx={{ mb: 1.5 }}>{t(error)}</Alert> : null
}

/** The settings, asked again now and then while the window is in view. */
export function useSettings(minimized: boolean) {
  const api = useApi()
  const load = useCallback(() => api.settings(), [api])
  return usePolled(load, REFRESH_MS, useAwake(minimized))
}

/** A section only administrators see: it reads the settings and hands them to `Section`. */
export function adminSection(Section: (p: SectionProps) => ReactNode) {
  function Loaded({ minimized }: { minimized: boolean }) {
    const { t } = useI18n()
    const { data, failed, reload } = useSettings(minimized)
    if (!data) return <Notice>{t(failed ? 'settings.unavailable' : 'settings.loading')}</Notice>
    return <ViewBody><Section settings={data} reload={reload} /></ViewBody>
  }
  return function AdminSection({ minimized }: { minimized: boolean }) {
    const { t } = useI18n()
    // The server refuses others too; not asking spares them an error.
    return useUser().admin ? <Loaded minimized={minimized} /> : <Notice>{t('settings.adminOnly')}</Notice>
  }
}
