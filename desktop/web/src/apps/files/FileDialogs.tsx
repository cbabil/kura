/** The small dialogs of Files: a name to give, a deletion to confirm, a file to look at. */
import { useEffect, useState, type FormEvent } from 'react'
import { Box, Button, Dialog, DialogActions, DialogContent, DialogTitle, TextField } from '@mui/material'
import { useI18n } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { MONO } from '../parts'

const PAPER = { paper: { sx: { width: 400 } } }

/** Asks for a name: a new folder's, or a new one for something. */
export function NameDialog(p: { title: string; initial: string; confirm: string; onConfirm(name: string): void; onClose(): void }) {
  const { t } = useI18n()
  const [name, setName] = useState(p.initial)
  const submit = (e: FormEvent) => {
    e.preventDefault()
    p.onConfirm(name.trim())
  }
  return (
    <Dialog open onClose={p.onClose} aria-labelledby="file-name" slotProps={PAPER}>
      <Box component="form" onSubmit={submit}>
        <DialogTitle id="file-name">{p.title}</DialogTitle>
        <DialogContent>
          <TextField size="small" fullWidth autoFocus sx={{ mt: 1 }} label={t('files.name')} value={name} onChange={(e) => setName(e.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={p.onClose}>{t('power.cancel')}</Button>
          <Button type="submit" variant="contained" disabled={!name.trim() || name.trim() === p.initial}>{p.confirm}</Button>
        </DialogActions>
      </Box>
    </Dialog>
  )
}

/** Asks before something that cannot be undone. */
export function ConfirmDialog(p: { title: string; text: string; confirm: string; onConfirm(): void; onClose(): void }) {
  const { t } = useI18n()
  return (
    <Dialog open onClose={p.onClose} aria-labelledby="file-confirm" slotProps={PAPER}>
      <DialogTitle id="file-confirm">{p.title}</DialogTitle>
      <DialogContent>{p.text}</DialogContent>
      <DialogActions>
        <Button onClick={p.onClose}>{t('power.cancel')}</Button>
        <Button variant="contained" color="error" onClick={p.onConfirm}>{p.confirm}</Button>
      </DialogActions>
    </Dialog>
  )
}

const PICTURE = /\.(png|jpe?g|gif|webp)$/i
const TEXT = /\.(txt|md|log|json|ya?ml|conf)$/i
/** Text longer than this is downloaded, not shown. */
const MAX_TEXT_BYTES = 512 * 1024

/** What a file can be shown as in the page; null for one that is only downloaded. */
export function previewKind(name: string, size: number): 'picture' | 'text' | null {
  if (PICTURE.test(name)) return 'picture'
  return TEXT.test(name) && size <= MAX_TEXT_BYTES ? 'text' : null
}

/** A picture or a text file, shown without leaving the desktop. */
export function Preview({ path, name, kind, onClose }: { path: string; name: string; kind: 'picture' | 'text'; onClose(): void }) {
  const api = useApi()
  const { t } = useI18n()
  const [text, setText] = useState<string | null>(null)
  useEffect(() => {
    if (kind !== 'text') return
    let live = true
    api.fileText(path).then((got) => live && setText(got), () => live && setText(t('files.error.failed')))
    return () => {
      live = false
    }
  }, [api, path, kind, t])
  return (
    <Dialog open onClose={onClose} aria-labelledby="file-preview" maxWidth="md" fullWidth>
      <DialogTitle id="file-preview">{name}</DialogTitle>
      <DialogContent className="no-scrollbar" sx={{ display: 'grid', placeItems: kind === 'picture' ? 'center' : 'stretch' }}>
        {kind === 'picture'
          ? <Box component="img" src={api.fileUrl(path, true)} alt={name} sx={{ maxWidth: '100%', maxHeight: '60vh' }} />
          : <Box component="pre" sx={{ m: 0, fontFamily: MONO, fontSize: 12.5, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{text ?? t('files.loading')}</Box>}
      </DialogContent>
      <DialogActions>
        <Button component="a" href={api.fileUrl(path)} download={name}>{t('files.download')}</Button>
        <Button variant="contained" onClick={onClose}>{t('files.close')}</Button>
      </DialogActions>
    </Dialog>
  )
}
