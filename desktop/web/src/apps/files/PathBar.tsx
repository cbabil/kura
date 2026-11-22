/** Where the folder is: each part of its path is a way back to that folder. */
import { Box, Button } from '@mui/material'
import { useI18n } from '../../i18n'
import { MONO } from '../parts'

export function PathBar({ path, setPath }: { path: string; setPath(path: string): void }) {
  const { t } = useI18n()
  const parts = path.split('/').filter(Boolean)
  const part = { minWidth: 0, px: '5px', py: '1px', fontFamily: MONO, fontSize: 12.5, textTransform: 'none' } as const
  return (
    <Box component="nav" aria-label={t('files.path')} className="no-scrollbar"
      sx={{ flex: '1 1 160px', minWidth: 0, display: 'flex', alignItems: 'center', overflowX: 'auto', whiteSpace: 'nowrap' }}>
      <Button size="small" color="inherit" sx={part} onClick={() => setPath('/')}>/</Button>
      {parts.map((name, i) => (
        <Box key={i} sx={{ display: 'flex', alignItems: 'center', color: 'text.secondary' }}>
          {i > 0 && <Box component="span" aria-hidden sx={{ fontFamily: MONO, fontSize: 12.5 }}>/</Box>}
          <Button size="small" color="inherit" sx={part} onClick={() => setPath(`/${parts.slice(0, i + 1).join('/')}`)}>{name}</Button>
        </Box>
      ))}
    </Box>
  )
}
