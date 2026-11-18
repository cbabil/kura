/**
 * The sign-in page (approved mockup `signin.png`): the device's own users
 * and passwords, checked by kura-helper through PAM on the server.
 */
import { useEffect, useState, type FormEvent } from 'react'
import { Alert, Box, Button, InputBase } from '@mui/material'
import { useTheme } from '@mui/material/styles'
import type { Api, LoginError, User } from '../api'
import { Kicker } from '../shell/Panels'
import { MINCHO } from '../theme'

const MESSAGES: Record<LoginError, string> = {
  wrong: 'Wrong user name or password.',
  expired: 'This password must be changed first. Set a new one at the console or over SSH, then sign in here.',
  rate: 'Too many attempts. Wait a moment and try again.',
  network: 'Cannot reach the server. Check that it is on and try again.',
}

interface Props {
  api: Api
  onSignedIn(user: User): void
}

export function SignIn({ api, onSignedIn }: Props) {
  const k = useTheme().kura
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
      <Box component="form" onSubmit={submit} aria-label="Sign in" sx={{ width: 'min(380px, 100%)', textAlign: 'center' }}>
        <Box aria-hidden sx={{ fontFamily: MINCHO, fontSize: 96, lineHeight: 1, mb: 1,
          background: 'linear-gradient(160deg, #e9ddff, #9146ff)', WebkitBackgroundClip: 'text', color: 'transparent' }}>蔵</Box>
        <Kicker>THE STOREHOUSE</Kicker>
        <Box component="h1" sx={{ fontSize: 34, fontWeight: 700, letterSpacing: '-1px', m: '4px 0 0' }}>Kura</Box>
        <Box sx={{ color: 'text.secondary', mb: 4, minHeight: 20 }}>{hostname ? `${hostname}.local` : ''}</Box>
        <InputBase sx={field} placeholder="User name" value={user} autoFocus autoComplete="username"
          inputProps={{ 'aria-label': 'User name', autoCapitalize: 'none', spellCheck: false }}
          onChange={(e) => setUser(e.target.value)} />
        <InputBase sx={field} placeholder="Password" type="password" value={password} autoComplete="current-password"
          inputProps={{ 'aria-label': 'Password' }} onChange={(e) => setPassword(e.target.value)} />
        {error && (
          <Alert severity={error.kind === 'wrong' ? 'error' : 'warning'} sx={{ textAlign: 'left', mb: '10px' }}>
            {MESSAGES[error.kind]}{error.wait ? ` (${error.wait} s)` : ''}
          </Alert>
        )}
        <Button type="submit" variant="contained" fullWidth disabled={busy || !user || !password}
          sx={{ py: '10px', borderRadius: '10px', fontSize: 14 }}>
          {busy ? 'Signing in…' : 'Sign in'}
        </Button>
        <Box sx={{ fontSize: 12, color: 'text.secondary', mt: 3, lineHeight: 1.6 }}>
          Same user and password as the console and SSH.<br />
          Check the certificate fingerprint against the one on the device's login screen.
        </Box>
      </Box>
    </Box>
  )
}
