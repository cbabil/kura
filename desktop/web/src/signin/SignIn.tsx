/**
 * The sign-in page (approved mockup `signin.png`): the device's own users
 * and passwords, checked by kura-helper through PAM on the server.
 */
import { useEffect, useState, type FormEvent } from 'react'
import { Alert, Box, Button, InputBase } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { Api, LoginError, User } from '../api'
import { useI18n, type MessageKey } from '../i18n'
import { Kicker } from '../shell/Panels'
import { MINCHO } from '../theme'

const MESSAGES: Record<LoginError, MessageKey> = {
  wrong: 'signin.wrong',
  expired: 'signin.expired',
  rate: 'signin.rate',
  network: 'signin.network',
}

interface Props {
  api: Api
  onSignedIn(user: User): void
}

export function SignIn({ api, onSignedIn }: Props) {
  const k = useTheme().kura
  const { t } = useI18n()
  const [user, setUser] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<{ kind: LoginError; wait?: number } | null>(null)
  const [hostname, setHostname] = useState<string | null>(null)

  useEffect(() => {
    api.system().then((s) => setHostname(s.hostname), () => setHostname(null))
  }, [api])

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (!user || !password || busy) return
    setBusy(true)
    const res = await api.login(user.trim(), password)
    setBusy(false)
    if (res.ok) return onSignedIn(res.user)
    setPassword('')
    setError({ kind: res.error, wait: res.retryAfter })
  }

  const field = {
    width: '100%', border: `1px solid ${k.edge}`, bgcolor: 'background.paper', borderRadius: '10px', px: '14px', py: '6px',
    mb: '10px', '&.Mui-focused': { borderColor: 'primary.main' },
  }
  return (
    <Box component="main" sx={{ position: 'fixed', inset: 0, display: 'grid', placeItems: 'center', background: k.wall, p: 2, overflow: 'auto' }}>
      <Box component="form" onSubmit={submit} aria-label={t('signin.form')} sx={{ width: 'min(380px, 100%)', textAlign: 'center' }}>
        <Box aria-hidden sx={{ fontFamily: MINCHO, fontSize: 96, lineHeight: 1, mb: 1,
          background: 'linear-gradient(160deg, #e9ddff, #9146ff)', WebkitBackgroundClip: 'text', color: 'transparent' }}>蔵</Box>
        <Kicker>{t('brand.kicker')}</Kicker>
        <Box component="h1" sx={{ fontSize: 34, fontWeight: 700, letterSpacing: '-1px', m: '4px 0 0' }}>Kura</Box>
        <Box sx={{ color: 'text.secondary', mb: 4, minHeight: 20 }}>{hostname ? `${hostname}.local` : ''}</Box>
        <InputBase sx={field} placeholder={t('signin.user')} value={user} autoFocus autoComplete="username"
          inputProps={{ 'aria-label': t('signin.user'), autoCapitalize: 'none', spellCheck: false }}
          onChange={(e) => setUser(e.target.value)} />
        <InputBase sx={field} placeholder={t('signin.password')} type="password" value={password} autoComplete="current-password"
          inputProps={{ 'aria-label': t('signin.password') }} onChange={(e) => setPassword(e.target.value)} />
        {error && (
          <Alert severity={error.kind === 'wrong' ? 'error' : 'warning'} sx={{ textAlign: 'left', mb: '10px' }}>
            {t(MESSAGES[error.kind])}{error.wait ? ` ${t('signin.wait', { seconds: error.wait })}` : ''}
          </Alert>
        )}
        <Button type="submit" variant="contained" fullWidth disabled={busy || !user || !password}
          sx={{ py: '10px', borderRadius: '10px', fontSize: 14 }}>
          {t(busy ? 'signin.busy' : 'signin.submit')}
        </Button>
        <Box sx={{ fontSize: 12, color: 'text.secondary', mt: 3, lineHeight: 1.6 }}>
          {t('signin.same')}<br />
          {t('signin.cert')}
        </Box>
      </Box>
    </Box>
  )
}
