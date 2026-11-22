/**
 * One folder of Files: its entries, the way up, and what can be done with
 * the selected one. Changes are made by the server as the signed-in user,
 * and nothing that exists is ever written over.
 */
import { useState } from 'react'
import { Alert, Box, Button, Checkbox, FormControlLabel, IconButton, Tooltip } from '@mui/material'
import { ApiError, type FileChange, type FileEntry } from '../../api'
import { joinPath, parentOf } from '../../api/paths'
import { Glyph } from '../../icons/Glyph'
import { useI18n, type MessageKey } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { Notice } from '../parts'
import { ConfirmDialog, NameDialog, Preview, previewKind } from './FileDialogs'
import { FileTable, sorted } from './FileTable'
import { FolderActions, type Clip } from './FolderActions'
import { PathBar } from './PathBar'
import { errorKey, useFolder } from './useFolder'

export type { Clip }

type Asking = null | { what: 'new' } | { what: 'rename' | 'delete' | 'preview'; entry: FileEntry }

interface Props {
  /** null is the home folder. */
  path: string | null
  setPath(path: string): void
  clip: Clip
  setClip(clip: Clip): void
  awake: boolean
}

export function FolderPane({ path, setPath, clip, setClip, awake }: Props) {
  const api = useApi()
  const { t } = useI18n()
  const { folder, reload } = useFolder(path, awake)
  const [selected, setSelected] = useState<string | null>(null)
  const [hidden, setHidden] = useState(false)
  const [asking, setAsking] = useState<Asking>(null)
  const [error, setError] = useState<MessageKey | null>(null)
  const [progress, setProgress] = useState<string | null>(null)
  if (!folder) return <Notice>{t('files.loading')}</Notice>
  if ('unreadable' in folder) return <Notice>{t(folder.unreadable)}</Notice>

  const here = folder.path
  const entries = sorted(folder.entries, hidden)
  const chosen = entries.find((e) => e.name === selected) ?? null
  const at = (name: string) => joinPath(here, name)
  const run = (change: FileChange, then?: () => void) => {
    setError(null)
    setAsking(null)
    return api.fileChange(change).then(() => then?.(), (e: unknown) => setError(errorKey(e))).finally(reload)
  }
  const open = (e: FileEntry) => {
    if (e.dir) return setPath(at(e.name))
    if (previewKind(e.name, e.size)) setAsking({ what: 'preview', entry: e })
  }
  const trash = (e: FileEntry) => {
    setError(null)
    api.fileChange({ op: 'trash', path: at(e.name) }).then(reload, (why: unknown) => {
      // The Trash is on the home's volume: elsewhere, deleting is all there is.
      if (why instanceof ApiError && why.code === 'other_volume') setAsking({ what: 'delete', entry: e })
      else setError(errorKey(why))
    })
  }
  const upload = async (picked: File[]) => {
    setError(null)
    try {
      for (const [i, file] of picked.entries()) {
        setProgress(t('files.uploading', { name: file.name, done: i + 1, total: picked.length }))
        await api.upload(at(file.name), file)
      }
    } catch (e) {
      setError(errorKey(e))
    }
    setProgress(null)
    reload()
  }
  const paste = () => clip && run({ op: clip.cut ? 'rename' : 'copy', from: clip.path, to: at(clip.name) }, () => setClip(null))

  return (
    <Box sx={{ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' }}
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault()
        void upload([...e.dataTransfer.files])
      }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexShrink: 0, p: '6px 10px', borderBottom: 1, borderColor: 'divider', flexWrap: 'wrap' }}>
        <Tooltip title={t('files.up')}>
          <span><IconButton size="small" aria-label={t('files.up')} disabled={here === '/'} onClick={() => setPath(parentOf(here))}><Glyph name="back" /></IconButton></span>
        </Tooltip>
        <PathBar path={here} setPath={setPath} />
        <FormControlLabel label={t('files.hidden')} sx={{ mr: 0.5, '& .MuiFormControlLabel-label': { fontSize: 12.5 } }}
          control={<Checkbox size="small" checked={hidden} onChange={(e) => setHidden(e.target.checked)} />} />
        <Button size="small" onClick={() => setAsking({ what: 'new' })}>{t('files.newFolder')}</Button>
        <Button size="small" component="label">
          {t('files.upload')}
          <Box component="input" type="file" multiple aria-label={t('files.uploadInput')} sx={{ position: 'absolute', width: 1, height: 1, opacity: 0, overflow: 'hidden' }}
            onChange={(e) => {
              void upload([...(e.target.files ?? [])])
              e.target.value = ''
            }} />
        </Button>
      </Box>
      <FolderActions chosen={chosen} at={at} here={here} clip={clip} setClip={setClip} onPaste={paste}
        onOpen={open} onRename={(entry) => setAsking({ what: 'rename', entry })} onTrash={trash} />
      {error && <Alert severity="error" onClose={() => setError(null)} sx={{ m: 1, flexShrink: 0 }}>{t(error)}</Alert>}
      {progress && <Alert severity="info" sx={{ m: 1, flexShrink: 0 }}>{progress}</Alert>}
      {folder.truncated && <Alert severity="warning" sx={{ m: 1, flexShrink: 0 }}>{t('files.truncated')}</Alert>}
      <Box className="no-scrollbar" sx={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
        <FileTable label={t('files.list', { path: here })} entries={entries} selected={selected} onSelect={setSelected} onOpen={open} />
        {entries.length === 0 && <Notice>{t('files.empty')}</Notice>}
      </Box>
      {asking?.what === 'new' && (
        <NameDialog title={t('files.newFolder.title')} initial="" confirm={t('files.create')} onClose={() => setAsking(null)}
          onConfirm={(name) => run({ op: 'make-dir', path: at(name) })} />
      )}
      {asking?.what === 'rename' && (
        <NameDialog title={t('files.rename.title', { name: asking.entry.name })} initial={asking.entry.name} confirm={t('files.rename.confirm')}
          onClose={() => setAsking(null)} onConfirm={(name) => run({ op: 'rename', from: at(asking.entry.name), to: at(name) })} />
      )}
      {asking?.what === 'delete' && (
        <ConfirmDialog title={t('files.delete.title', { name: asking.entry.name })} text={t('files.delete.text')} confirm={t('files.delete.confirm')}
          onClose={() => setAsking(null)} onConfirm={() => run({ op: 'delete', path: at(asking.entry.name) })} />
      )}
      {asking?.what === 'preview' && (
        <Preview path={at(asking.entry.name)} name={asking.entry.name} kind={previewKind(asking.entry.name, asking.entry.size) ?? 'text'} onClose={() => setAsking(null)} />
      )}
    </Box>
  )
}
