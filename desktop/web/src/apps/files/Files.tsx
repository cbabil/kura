/**
 * Files (D3): the signed-in user's own view of the server's disk. The
 * places down the side are their home folder, the volumes and the Trash;
 * the server does everything as that user, so what they may open and change
 * is what the system lets them (ADR-031).
 */
import { useState } from 'react'
import { Box } from '@mui/material'
import { useI18n } from '../../i18n'
import { useStats } from '../../shell/DesktopData'
import type { AppProps } from '../types'
import { Sidebar } from '../parts'
import { useAwake } from '../usePolled'
import { FolderPane, type Clip } from './Folder'
import { TrashView } from './TrashView'

const HOME = 'home'
const TRASH = 'trash'

export function Files({ compact, minimized }: AppProps) {
  const { t } = useI18n()
  const awake = useAwake(minimized)
  const mounts = useStats((s) => s.latest?.disks)?.map((d) => d.mount) ?? []
  // The place last chosen stays marked while its folders are walked.
  const [place, setPlace] = useState(HOME)
  const [path, setPath] = useState<string | null>(null)
  const [clip, setClip] = useState<Clip>(null)
  const choose = (chosen: string) => {
    setPlace(chosen)
    setPath(chosen === HOME || chosen === TRASH ? null : chosen)
  }
  return (
    // A file dropped beside the folder must not make the browser leave the desktop for it.
    <Box sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: compact ? 'column' : 'row' }}
      onDragOver={(e) => e.preventDefault()} onDrop={(e) => e.preventDefault()}>
      <Sidebar label={t('files.places')} views={[HOME, ...mounts, TRASH]} current={place} compact={compact} onChoose={choose}
        glyph={(v) => (v === HOME ? 'home' : v === TRASH ? 'trash' : 'disk')}
        name={(v) => (v === HOME ? t('files.home') : v === TRASH ? t('app.trash.name') : v)} />
      {place === TRASH
        ? <TrashView awake={awake} />
        // A new folder starts afresh: nothing selected, no old message.
        : <FolderPane key={path ?? HOME} path={path} setPath={setPath} clip={clip} setClip={setClip} awake={awake} />}
    </Box>
  )
}
