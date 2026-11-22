import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type User } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Settings } from './Settings'

const GUEST: User = { name: 'guest', uid: 1001, admin: false }

async function show(change: (api: Api) => Partial<Api> = () => ({}), user = CHRIS, lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(user.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  const setView = vi.fn()
  renderWithTheme(<Settings view="Updates" setView={setView} compact={false} minimized={false} />, { api, user, lang })
  return { api, setView }
}

describe('Settings › Updates', () => {
  it('shows the installed version and the one that waits', async () => {
    await show()
    expect(await screen.findByText('Kura 0.6.1')).toBeInTheDocument()
    expect(screen.getByText('Kura 0.6.2 is available.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Updates' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByText(/installed only when you ask/)).toBeInTheDocument()
  })

  it('installs when asked, shows what was written, and then offers the restart', async () => {
    const { api } = await show((mock) => ({ startUpdate: vi.fn(mock.startUpdate), power: vi.fn(mock.power) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Install' }))
    expect(api.startUpdate).toHaveBeenCalledWith('install')
    expect(await screen.findByText('Kura is up to date.')).toBeInTheDocument()
    expect(screen.getByText('Kura 0.6.2')).toBeInTheDocument()
    expect(within(screen.getByRole('log', { name: 'What the update wrote' })).getByText('Setting up kura (0.6.2) ...')).toBeInTheDocument()
    expect(screen.getByText('A restart is needed to finish the update.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Install' })).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: 'Restart…' }))
    await userEvent.click(within(screen.getByRole('dialog', { name: 'Restart this server?' })).getByRole('button', { name: 'Restart' }))
    expect(api.power).toHaveBeenCalledWith('restart')
  })

  it('looks for a newer version when asked', async () => {
    const { api } = await show((mock) => ({ startUpdate: vi.fn(mock.startUpdate) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Check Now' }))
    expect(api.startUpdate).toHaveBeenCalledWith('check')
    expect(await screen.findByText('Reading package lists...')).toBeInTheDocument()
    expect(screen.getByText('Done.')).toBeInTheDocument()
  })

  it('shows a running update and one that failed', async () => {
    const status = { current: '0.6.1', available: '0.6.2', restartRequired: false }
    await show(() => ({ updates: () => Promise.resolve({ ...status, job: { state: 'running' as const, output: ['Get:1'] } }) }))
    expect(await screen.findByRole('progressbar', { name: 'Working…' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Install' })).toBeDisabled()
    await show(() => ({ updates: () => Promise.resolve({ ...status, job: { state: 'failed' as const, output: ['E: no space'] } }) }))
    expect(await screen.findByText(/did not finish/)).toBeInTheDocument()
  })

  it('offers no restart and no second update while one runs', async () => {
    const running = { current: '0.6.1', available: '0.6.2', restartRequired: true, job: { state: 'running' as const, output: [] } }
    await show(() => ({ updates: () => Promise.resolve(running) }))
    expect(await screen.findByText('A restart is needed to finish the update.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Restart…' })).toBeNull()
    expect(screen.getByRole('button', { name: 'Check Now' })).toBeDisabled()
  })

  it('says when the server did not start an update', async () => {
    await show(() => ({ startUpdate: () => Promise.reject(new ApiError('busy')) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Check Now' }))
    expect(await screen.findByText(/did not start it/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Check Now' })).toBeEnabled()
  })

  it('lets others look only', async () => {
    await show(undefined, GUEST)
    expect(await screen.findByText('Kura 0.6.2 is available.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Install' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Check Now' })).toBeNull()
    expect(screen.getByText('Only administrators can install updates.')).toBeInTheDocument()
  })

  it('says when the server cannot say, and speaks French', async () => {
    await show(() => ({ updates: () => Promise.reject(new ApiError('unavailable')) }))
    expect(await screen.findByText('The server could not say.')).toBeInTheDocument()
    await show(undefined, CHRIS, 'fr')
    expect(await screen.findByText('Kura 0.6.2 est disponible.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Vérifier maintenant' })).toBeInTheDocument()
  })

  it('falls back to its first section and switches from the sidebar', async () => {
    const mock = createMockApi()
    const setView = vi.fn()
    renderWithTheme(<Settings view="nope" setView={setView} compact minimized={false} />, { api: mock })
    await userEvent.click(screen.getByRole('button', { name: 'Updates' }))
    expect(setView).toHaveBeenCalledWith('Updates')
  })
})
