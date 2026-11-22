/** The two questions of the App Catalog: which port to install on, and whether the data goes too. */
import { useState, type FormEvent } from 'react'
import { Box, Button, Checkbox, Dialog, DialogActions, DialogContent, DialogTitle, FormControlLabel, TextField } from '@mui/material'
import type { CatalogApp } from '../../api'
import { useI18n } from '../../i18n'

const PAPER = { paper: { sx: { width: 420 } } }
const MIN_PORT = 1024
const MAX_PORT = 65535

export function InstallDialog({ app, onInstall, onClose }: { app: CatalogApp; onInstall(port: number): void; onClose(): void }) {
  const { t } = useI18n()
  const [text, setText] = useState(String(app.port))
  const port = /^\d{4,5}$/.test(text) ? Number(text) : 0
  const valid = port >= MIN_PORT && port <= MAX_PORT
  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (valid) onInstall(port)
  }
  return (
    <Dialog open onClose={onClose} aria-labelledby="catalog-install" slotProps={PAPER}>
      <Box component="form" onSubmit={submit}>
        <DialogTitle id="catalog-install">{t('catalog.install.title', { name: app.name })}</DialogTitle>
        <DialogContent>
          <TextField size="small" fullWidth autoFocus sx={{ mt: 1 }} label={t('catalog.install.port')} value={text} error={!valid}
            onChange={(e) => setText(e.target.value.trim())} helperText={t('catalog.install.portHint')}
            slotProps={{ htmlInput: { inputMode: 'numeric' } }} />
          {app.fixedPorts.length > 0 && (
            <Box sx={{ mt: 1.5, fontSize: 12.5, color: 'text.secondary' }}>{t('catalog.install.fixed', { ports: app.fixedPorts.join(', ') })}</Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={onClose}>{t('power.cancel')}</Button>
          <Button type="submit" variant="contained" disabled={!valid}>{t('catalog.install.confirm')}</Button>
        </DialogActions>
      </Box>
    </Dialog>
  )
}

export function RemoveDialog({ app, onRemove, onClose }: { app: CatalogApp; onRemove(data: boolean): void; onClose(): void }) {
  const { t } = useI18n()
  const [data, setData] = useState(false)
  return (
    <Dialog open onClose={onClose} aria-labelledby="catalog-remove" slotProps={PAPER}>
      <DialogTitle id="catalog-remove">{t('catalog.remove.title', { name: app.name })}</DialogTitle>
      <DialogContent>
        <Box sx={{ mb: 1 }}>{t('catalog.remove.text', { id: app.id })}</Box>
        <FormControlLabel label={t('catalog.remove.data')} control={<Checkbox size="small" checked={data} onChange={(e) => setData(e.target.checked)} />} />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('power.cancel')}</Button>
        <Button variant="contained" color="error" onClick={() => onRemove(data)}>{t('catalog.remove.confirm')}</Button>
      </DialogActions>
    </Dialog>
  )
}
