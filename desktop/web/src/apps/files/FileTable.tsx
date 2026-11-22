/** A folder's entries as a table: one click selects, two (or Enter) open. */
import { Box, Table, TableBody, TableCell, TableHead, TableRow } from '@mui/material'
import type { FileEntry } from '../../api'
import { Glyph } from '../../icons/Glyph'
import { useI18n } from '../../i18n'
import { whenText } from './useFolder'

const CELL = { py: '6px', px: '10px', borderColor: 'divider', fontSize: 13, whiteSpace: 'nowrap' } as const
const HEAD = { ...CELL, color: 'text.secondary', fontWeight: 500, fontSize: 12, bgcolor: 'background.paper' } as const

/** Folders first, then by name as people sort names. */
export function sorted(entries: FileEntry[], hidden: boolean): FileEntry[] {
  const shown = hidden ? entries : entries.filter((e) => !e.name.startsWith('.'))
  return [...shown].sort((a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name, undefined, { numeric: true }))
}

export function FileTable(p: { label: string; entries: FileEntry[]; selected: string | null; onSelect(name: string): void; onOpen(entry: FileEntry): void }) {
  const { t, format, lang } = useI18n()
  return (
    <Table size="small" aria-label={p.label} stickyHeader>
      <TableHead>
        <TableRow>
          <TableCell sx={HEAD}>{t('files.col.name')}</TableCell>
          <TableCell sx={HEAD} align="right">{t('files.col.size')}</TableCell>
          <TableCell sx={HEAD} align="right">{t('files.col.modified')}</TableCell>
        </TableRow>
      </TableHead>
      <TableBody>
        {p.entries.map((e) => (
            <TableRow key={e.name} hover tabIndex={0} selected={e.name === p.selected} aria-selected={e.name === p.selected}
              onClick={() => p.onSelect(e.name)} onFocus={() => p.onSelect(e.name)} onDoubleClick={() => p.onOpen(e)}
              onKeyDown={(k) => k.key === 'Enter' && p.onOpen(e)} sx={{ cursor: 'default', userSelect: 'none' }}>
              <TableCell sx={{ ...CELL, maxWidth: 320, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', gap: 1, color: e.dir ? 'primary.main' : 'text.secondary', verticalAlign: 'middle', mr: 1 }}>
                  <Glyph name={e.dir ? 'folder' : 'file'} />
                </Box>
                {e.name}
              </TableCell>
              <TableCell sx={{ ...CELL, fontVariantNumeric: 'tabular-nums', color: 'text.secondary' }} align="right">
                {e.dir ? t('files.folder') : format.bytes(e.size)}
              </TableCell>
              <TableCell sx={{ ...CELL, fontVariantNumeric: 'tabular-nums', color: 'text.secondary' }} align="right">
                {whenText(lang, e.modified)}
              </TableCell>
            </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
