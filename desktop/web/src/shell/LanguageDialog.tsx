/**
 * Choosing the desktop's language: automatic (the browser's), or one of the
 * languages Kura has, each named in itself. Opens from the 蔵 menu.
 */
import { Button, Dialog, DialogActions, DialogContent, DialogTitle, FormControlLabel, Radio, RadioGroup } from '@mui/material'
import { NAMES, pickLanguage, useI18n } from '../i18n'

interface Props {
  open: boolean
  /** 'auto' or a language code (prefs.language). */
  choice: string
  onChoose(choice: string): void
  onClose(): void
}

export function LanguageDialog({ open, choice, onChoose, onClose }: Props) {
  const { t } = useI18n()
  return (
    <Dialog open={open} onClose={onClose} aria-labelledby="language-title" slotProps={{ paper: { sx: { minWidth: 300, height: 520 } } }}>
      <DialogTitle id="language-title" sx={{ fontSize: 17 }}>{t('language.title')}</DialogTitle>
      <DialogContent className="no-scrollbar">
        <RadioGroup value={choice} onChange={(e) => onChoose(e.target.value)}>
          <FormControlLabel value="auto" control={<Radio size="small" />}
            label={t('language.auto', { language: NAMES[pickLanguage('auto', navigator.languages)] })} />
          {Object.entries(NAMES).map(([code, name]) => (
            <FormControlLabel key={code} value={code} control={<Radio size="small" />} label={name}
              slotProps={{ typography: { lang: code } }} />
          ))}
        </RadioGroup>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('language.done')}</Button>
      </DialogActions>
    </Dialog>
  )
}
