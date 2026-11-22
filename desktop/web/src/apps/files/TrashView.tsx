/**
 * The Trash: what was removed, where it was, and when. Something is put
 * back where it was, or everything is deleted for good after asking.
 */
import { useCallback, useState } from 'react'
import { Alert, Box, Button } from '@mui/material'
import { ApiError, type FileChange, type Trashed } from '../../api'
import { parentOf } from '../../api/paths'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { DataTable, Notice, ViewBody, type Column } from '../parts'
import { usePolled } from '../usePolled'
import { ConfirmDialog } from './FileDialogs'
import { errorKey, POLL_MS, whenText } from './useFolder'

export function TrashView({ awake }: { awake: boolean }) {
  const api = useApi()
  const { t, format, lang } = useI18n()
  const load = useCallback(() => api.trash(), [api])
  const { data, failed, reload } = usePolled(load, POLL_MS, awake)
  const [error, setError] = useState<MessageKey | null>(null)
  const [asking, setAsking] = useState(false)
  if (!data) return <Notice>{t(failed ? 'trash.unavailable' : 'files.loading')}</Notice>

  const run = (change: FileChange) => {
    setError(null)
    // What cannot be put back lacks the folder it was in, not itself.
    const why = (e: unknown) => (change.op === 'restore' && e instanceof ApiError && e.code === 'not_found' ? 'trash.error.parent' : errorKey(e))
    api.fileChange(change).catch((e: unknown) => setError(why(e))).finally(reload)
  }
  const columns: Column<Trashed>[] = [
    { label: t('files.col.name'), cell: (i) => i.name },
    { label: t('trash.col.from'), cell: (i) => parentOf(i.path) },
    { label: t('trash.col.deleted'), cell: (i) => whenText(lang, i.deleted) },
    { label: t('files.col.size'), numeric: true, cell: (i) => (i.dir ? t('files.folder') : format.bytes(i.size)) },
    {
      label: '', numeric: true,
      cell: (i) => <Button size="small" aria-label={t('trash.restoreItem', { name: i.name })} onClick={() => run({ op: 'restore', name: i.name })}>{t('trash.restore')}</Button>,
    },
  ]
  return (
    <ViewBody>
      {error && <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 1.5 }}>{t(error)}</Alert>}
      {data.length === 0 ? <Notice>{t('trash.empty')}</Notice> : (
        <>
          <Box sx={{ display: 'flex', justifyContent: 'flex-end', mb: 1 }}>
            <Button size="small" color="error" onClick={() => setAsking(true)}>{t('trash.emptyNow')}</Button>
          </Box>
          <DataTable rows={data} columns={columns} rowKey={(i) => i.name} label={t('app.trash.name')} />
        </>
      )}
      {asking && (
        <ConfirmDialog title={t('trash.confirm.title')} text={t('trash.confirm.text')} confirm={t('trash.confirm')} onClose={() => setAsking(false)}
          onConfirm={() => {
            setAsking(false)
            run({ op: 'empty-trash' })
          }} />
      )}
    </ViewBody>
  )
}
