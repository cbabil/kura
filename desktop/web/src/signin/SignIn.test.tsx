import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../test/render'
import { createMockApi, MOCK_PASSWORD } from '../api/mock'
import type { Api } from '../api'
import { SignIn } from './SignIn'

function setup(api: Api = createMockApi()) {
  const onSignedIn = vi.fn()
  renderWithTheme(<SignIn api={api} onSignedIn={onSignedIn} />)
  return { onSignedIn, user: screen.getByLabelText('User name'), password: screen.getByLabelText('Password'), button: screen.getByRole('button', { name: 'Sign in' }) }
}

describe('SignIn', () => {
  it('shows the host and keeps the button off until both fields are filled', async () => {
    const { user, button } = setup()
    expect(await screen.findByText('kura-nuc.local')).toBeInTheDocument()
    expect(button).toBeDisabled()
    await userEvent.type(user, 'chris')
    expect(button).toBeDisabled()
  })

  it('signs in with the right password', async () => {
    const { onSignedIn, user, password } = setup()
    await userEvent.type(user, ' chris ')
    await userEvent.type(password, `${MOCK_PASSWORD}{Enter}`)
    expect(onSignedIn).toHaveBeenCalledWith({ name: 'chris', uid: 1000, admin: true })
  })

  it('says why a sign-in was refused, and clears the password', async () => {
    const { onSignedIn, user, password } = setup()
    await userEvent.type(user, 'chris')
    await userEvent.type(password, 'nope{Enter}')
    expect(await screen.findByText('Wrong user name or password.')).toBeInTheDocument()
    expect(password).toHaveValue('')
    await userEvent.clear(user)
    await userEvent.type(user, 'expired')
    await userEvent.type(password, `${MOCK_PASSWORD}{Enter}`)
    expect(await screen.findByText(/must be changed first/)).toBeInTheDocument()
    expect(onSignedIn).not.toHaveBeenCalled()
  })

  it('shows the wait after too many attempts, and a network failure', async () => {
    const api = createMockApi()
    api.login = vi.fn()
      .mockResolvedValueOnce({ ok: false, error: 'rate', retryAfter: 30 })
      .mockResolvedValueOnce({ ok: false, error: 'network' })
    api.system = () => Promise.reject(new Error('down'))
    const { user, password } = setup(api)
    await userEvent.type(user, 'chris')
    await userEvent.type(password, 'x{Enter}')
    expect(await screen.findByText(/Too many attempts.*\(30 s\)/)).toBeInTheDocument()
    await userEvent.type(password, 'x{Enter}')
    expect(await screen.findByText(/Cannot reach the server/)).toBeInTheDocument()
  })
})
