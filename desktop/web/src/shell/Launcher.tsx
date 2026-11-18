/**
 * The ⌘K / Ctrl+K launcher: type to find apps and app sections, arrows to
 * move, Enter to open. A MUI Dialog, so focus is trapped while it is open
 * and returns where it was; Escape or a click outside closes it.
 */
import { useMemo, useState, type KeyboardEvent } from 'react'
import { Box, Dialog, InputBase } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import { AppIcon } from '../icons/AppIcon'
import { Glyph } from '../icons/Glyph'
import { APP_BY_ID } from '../apps/registry'
import { rankEntries, type Entry } from './search'

interface Props {
  entries: Entry[]
  onChoose(entry: Entry): void
  onClose(): void
}

export function Launcher({ entries, onChoose, onClose }: Props) {
  const k = useTheme().kura
  const [query, setQuery] = useState('')
  const [index, setIndex] = useState(0)
  const results = useMemo(() => rankEntries(entries, query), [entries, query])
  const current = Math.min(index, Math.max(results.length - 1, 0))
  const count = Math.max(results.length, 1)

  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'ArrowDown') setIndex((current + 1) % count)
    else if (e.key === 'ArrowUp') setIndex((current - 1 + count) % count)
    else if (e.key === 'Enter' && results[current]) onChoose(results[current])
    else return
    e.preventDefault()
  }

  return (
    <Dialog open onClose={onClose} aria-label="Search" fullWidth maxWidth={false}
      slotProps={{
        backdrop: { sx: { bgcolor: 'rgba(2,6,23,.45)' } },
        paper: { sx: { position: 'absolute', top: { xs: 44, md: 120 }, m: 0, width: 'min(640px, calc(100vw - 32px))',
          borderRadius: '14px', border: `1px solid ${k.edge}`, boxShadow: k.shadow, backgroundImage: 'none' } },
      }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, px: 2.25, py: 2, borderBottom: 1, borderColor: 'divider', color: 'text.secondary' }}>
        <Glyph name="search" size={20} />
        <InputBase autoFocus fullWidth placeholder="Search apps and sections" value={query} onKeyDown={onKey}
          onChange={(e) => {
            setQuery(e.target.value)
            setIndex(0)
          }}
          inputProps={{ 'aria-label': 'Search', role: 'combobox', 'aria-expanded': true, 'aria-controls': 'launcher-results' }}
          sx={{ fontSize: 19, color: 'text.primary' }} />
      </Box>
      <Box id="launcher-results" role="listbox" sx={{ maxHeight: '50vh', overflowY: 'auto', py: 0.5 }}>
        {results.length === 0 && <Box sx={{ px: 2.25, py: 2, color: 'text.secondary' }}>Nothing matches “{query}”</Box>}
        {results.map((entry, i) => (
          <Box key={entry.id}>
            {entry.section !== results[i - 1]?.section && (
              <Box sx={{ px: 2.25, pt: 1.5, pb: 0.75, fontSize: 11, fontWeight: 600, letterSpacing: '.4px',
                textTransform: 'uppercase', color: k.faint }}>{entry.section}</Box>
            )}
            <Box role="option" aria-selected={i === current} onMouseEnter={() => setIndex(i)} onClick={() => onChoose(entry)}
              sx={{ display: 'flex', alignItems: 'center', gap: 1.5, px: 2.25, py: 1, cursor: 'default',
                bgcolor: i === current ? 'action.selected' : 'transparent' }}>
              <AppIcon app={entry.app} name={APP_BY_ID[entry.app]?.name ?? entry.title} size={32} />
              <Box>
                <Box>{entry.title}</Box>
                <Box sx={{ color: 'text.secondary', fontSize: 12.5 }}>{entry.subtitle}</Box>
              </Box>
              {i === current && <Box sx={{ ml: 'auto', color: k.faint, fontSize: 12 }}>↵ open</Box>}
            </Box>
          </Box>
        ))}
      </Box>
    </Dialog>
  )
}
