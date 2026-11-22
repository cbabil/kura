import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type User } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Catalog } from './Catalog'

const GUEST: User = { name: 'guest', uid: 1002, admin: false }

async function show(change: (api: Api) => Partial<Api> = () => ({}), user = CHRIS, lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(user.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Catalog view="" setView={() => {}} compact={false} minimized={false} />, { api, user, lang })
  return api
}

const card = (name: string) => screen.findByRole('listitem', { name })

describe('App Catalog', () => {
  it('shows what Kura ships and what is installed', async () => {
    await show()
    const jellyfin = await card('Jellyfin')
    expect(jellyfin).toHaveTextContent('Version 10.10.7')
    expect(jellyfin).toHaveTextContent('Not installed')
    expect(jellyfin).toHaveTextContent('Your films, shows and music')
    expect(within(screen.getByRole('list', { name: 'Apps' })).getAllByRole('listitem')).toHaveLength(6)
    const gitea = await card('Gitea')
    expect(gitea).toHaveTextContent('Installed, on port 3003')
    expect(gitea).toHaveTextContent('Version 1.22.0 is installed; 1.23.1 is ready.')
    expect(within(gitea).getByRole('link', { name: 'Open' })).toHaveAttribute('href', 'http://localhost:3003')
    expect(within(jellyfin).queryByRole('link', { name: 'Open' })).toBeNull()
  })

  it('installs on the port chosen and shows what the job wrote', async () => {
    const api = await show((mock) => ({ changeApp: vi.fn(mock.changeApp) }))
    await userEvent.click(within(await card('AdGuard Home')).getByRole('button', { name: 'Install…' }))
    const ask = screen.getByRole('dialog', { name: 'Install AdGuard Home' })
    expect(ask).toHaveTextContent('It also uses port 53, which cannot be changed.')
    const port = within(ask).getByLabelText('Port')
    expect(port).toHaveValue('3000')
    await userEvent.clear(port)
    await userEvent.type(port, '80')
    expect(within(ask).getByRole('button', { name: 'Install' })).toBeDisabled()
    await userEvent.clear(port)
    await userEvent.type(port, '3100')
    await userEvent.click(within(ask).getByRole('button', { name: 'Install' }))
    expect(api.changeApp).toHaveBeenCalledWith({ what: 'install', id: 'adguard-home', port: 3100 })
    expect(await within(await card('AdGuard Home')).findByText('Installed, on port 3100')).toBeInTheDocument()
    expect(await screen.findByText('kura-apps install adguard-home')).toBeInTheDocument()
    expect(screen.getByText('Done.', { selector: '[role=status]' })).toBeInTheDocument()
  })

  it('updates, and removes after asking whether the data goes too', async () => {
    const api = await show((mock) => ({ changeApp: vi.fn(mock.changeApp) }))
    const gitea = await card('Gitea')
    await userEvent.click(within(gitea).getByRole('button', { name: 'Update' }))
    expect(api.changeApp).toHaveBeenLastCalledWith({ what: 'update', id: 'gitea' })
    await vi.waitFor(() => expect(gitea).not.toHaveTextContent('is ready'))
    expect(within(gitea).queryByRole('button', { name: 'Update' })).toBeNull()

    await userEvent.click(within(gitea).getByRole('button', { name: 'Remove…' }))
    const sure = screen.getByRole('dialog', { name: 'Remove Gitea?' })
    expect(sure).toHaveTextContent('/srv/apps/gitea/data')
    await userEvent.click(within(sure).getByRole('checkbox', { name: 'Also delete its data' }))
    await userEvent.click(within(sure).getByRole('button', { name: 'Remove' }))
    expect(api.changeApp).toHaveBeenLastCalledWith({ what: 'remove', id: 'gitea', data: true })
    expect(await within(gitea).findByText('Not installed')).toBeInTheDocument()
  })

  it('says when the server does not start a job, and while one runs nothing else can be started', async () => {
    let running = false
    await show((mock) => ({
      changeApp: () => Promise.reject(new ApiError('busy')),
      catalog: async () => ({ ...(await mock.catalog()), job: running ? { state: 'running', output: ['Pulling'] } : { state: 'failed', output: ['no space left'] } }),
    }))
    expect(await screen.findByText('It did not finish. The lines below say why.')).toBeInTheDocument()
    expect(screen.getByText('no space left')).toBeInTheDocument()
    await userEvent.click(within(await card('Gitea')).getByRole('button', { name: 'Update' }))
    expect(await screen.findByText(/The server did not start it/)).toBeInTheDocument()
    running = true
    await userEvent.click(within(await card('Gitea')).getByRole('button', { name: 'Update' }))
    expect(await screen.findByRole('progressbar', { name: 'Working…' })).toBeInTheDocument()
    await vi.waitFor(() => expect(within(screen.getByRole('listitem', { name: 'Gitea' })).getByRole('button', { name: 'Update' })).toBeDisabled())
  })

  it('is for administrators, says when it cannot be read, and speaks French', async () => {
    await show(() => ({}), GUEST)
    expect(await screen.findByText('Apps are installed by administrators.')).toBeInTheDocument()
    await show(() => ({ catalog: () => Promise.reject(new ApiError('unavailable')) }), CHRIS, 'fr')
    expect(await screen.findByText("Le serveur n'a pas pu montrer son catalogue.")).toBeInTheDocument()
  })
})
