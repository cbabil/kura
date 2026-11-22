/** What can be done with the selected entry, and the paste of what was picked elsewhere. */
import { Box, Button } from '@mui/material'
import type { FileEntry } from '../../api'
import { parentOf } from '../../api/paths'
import { useI18n } from '../../i18n'
import { useApi } from '../../shell/DesktopData'
import { previewKind } from './FileDialogs'

/** Something picked to be pasted elsewhere: copied, or moved when `cut`. */
export type Clip = { path: string; name: string; cut: boolean } | null

interface Props {
  chosen: FileEntry | null
  /** The path of a name in this folder. */
  at(name: string): string
  here: string
  clip: Clip
  setClip(clip: Clip): void
  onPaste(): void
  onOpen(entry: FileEntry): void
  onRename(entry: FileEntry): void
  onTrash(entry: FileEntry): void
}

export function FolderActions({ chosen, at, here, clip, setClip, onPaste, onOpen, onRename, onTrash }: Props) {
  const api = useApi()
  const { t } = useI18n()
  const pick = (entry: FileEntry, cut: boolean) => setClip({ path: at(entry.name), name: entry.name, cut })
  return (
    // Always there, so selecting a row does not move it under the pointer before the second click.
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexShrink: 0, minHeight: 39, p: '4px 10px', borderBottom: 1, borderColor: 'divider', flexWrap: 'wrap' }}>
      {chosen && (
        <>
          {(chosen.dir || previewKind(chosen.name, chosen.size)) && <Button size="small" onClick={() => onOpen(chosen)}>{t('files.open')}</Button>}
          {!chosen.dir && <Button size="small" component="a" href={api.fileUrl(at(chosen.name))} download={chosen.name}>{t('files.download')}</Button>}
          <Button size="small" onClick={() => onRename(chosen)}>{t('files.rename')}</Button>
          <Button size="small" onClick={() => pick(chosen, false)}>{t('files.copy')}</Button>
          <Button size="small" onClick={() => pick(chosen, true)}>{t('files.move')}</Button>
          <Button size="small" color="error" onClick={() => onTrash(chosen)}>{t('files.trash')}</Button>
        </>
      )}
      {clip && parentOf(clip.path) !== here && (
        <Button size="small" variant="outlined" sx={{ ml: 'auto' }} onClick={onPaste}>{t('files.paste', { name: clip.name })}</Button>
      )}
    </Box>
  )
}
