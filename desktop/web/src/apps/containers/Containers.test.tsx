import { act, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type User } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Containers } from './Containers'

const GUEST: User = { name: 'guest', uid: 1001, admin: false }

async function show(change: (api: Api) => Partial<Api> = () => ({}), user = CHRIS, lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(user.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Containers view="" setView={() => {}} compact={false} minimized={false} />, { api, user, lang })
  return api
}

const row = (name: string) => screen.getByRole('listitem', { name })

describe('Containers', () => {
  it('lists compose stacks and single containers with their state', async () => {
    await show()
    const immich = await screen.findByRole('group', { name: 'immich' })
    expect(within(immich).getByText('4 of 4 running')).toBeInTheDocument()
    expect(within(immich).getAllByRole('listitem')).toHaveLength(4)
    expect(within(row('jellyfin')).getByText('Running')).toBeInTheDocument()
    expect(within(row('jellyfin')).getByText(':8096')).toBeInTheDocument()
    expect(within(row('jellyfin')).getByText('jellyfin/jellyfin:10.11')).toBeInTheDocument()
    expect(within(row('pihole')).getByText('Stopped')).toBeInTheDocument()
    expect(within(row('pihole')).getByText('Exited (0) 2 hours ago')).toBeInTheDocument()
  })

  it('searches by name, image and stack', async () => {
    await show()
    const search = await screen.findByRole('searchbox', { name: 'Search containers' })
    await userEvent.type(search, 'JELLY')
    expect(screen.getAllByRole('listitem')).toHaveLength(1)
    await userEvent.clear(search)
    await userEvent.type(search, 'immich')
    expect(screen.getAllByRole('listitem')).toHaveLength(4)
    await userEvent.clear(search)
    await userEvent.type(search, 'nothing here')
    expect(screen.getByText('Nothing matches “nothing here”')).toBeInTheDocument()
  })

  it('lets an administrator stop, start and restart a container', async () => {
    const api = await show((mock) => ({ containerAction: vi.fn(mock.containerAction) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Stop jellyfin' }))
    expect(api.containerAction).toHaveBeenCalledWith('eeeeeeeeeeee', 'stop')
    expect(await within(row('jellyfin')).findByText('Stopped')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Restart jellyfin' })).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: 'Start jellyfin' }))
    expect(await within(row('jellyfin')).findByText('Running')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Restart jellyfin' }))
    expect(api.containerAction).toHaveBeenLastCalledWith('eeeeeeeeeeee', 'restart')
  })

  it('says when an action fails', async () => {
    await show(() => ({ containerAction: () => Promise.reject(new ApiError('unavailable')) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Stop jellyfin' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not stop jellyfin.')
  })

  it('shows other users the list without the controls', async () => {
    await show(undefined, GUEST)
    expect(await screen.findByText(/Only administrators can start or stop/)).toBeInTheDocument()
    expect(row('jellyfin')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Stop jellyfin' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Logs of jellyfin' })).toBeNull()
  })

  it('opens a container’s logs and comes back', async () => {
    await show()
    await userEvent.click(await screen.findByRole('button', { name: 'Logs of jellyfin' }))
    const log = await screen.findByRole('log', { name: 'Logs · jellyfin' })
    expect(within(log).getByText('jellyfin: handled request 1')).toBeInTheDocument()
    expect(within(log).getAllByText('jellyfin: request took 2.1 s')[0].parentElement).toHaveAttribute('data-tone', 'warning')
    await userEvent.click(screen.getByRole('button', { name: 'Back to containers' }))
    expect(row('jellyfin')).toBeInTheDocument()
  })

  it('says when logs are empty or cannot be read', async () => {
    let fail = false
    await show(() => ({ containerLogs: () => (fail ? Promise.reject(new ApiError('unavailable')) : Promise.resolve([])) }))
    await userEvent.click(await screen.findByRole('button', { name: 'Logs of jellyfin' }))
    expect(await screen.findByText('This container has written nothing yet.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Back to containers' }))
    fail = true
    await userEvent.click(screen.getByRole('button', { name: 'Logs of pihole' }))
    expect(await screen.findByText('The logs could not be read.')).toBeInTheDocument()
  })

  it('says when there is nothing, or Docker does not answer', async () => {
    await show(() => ({ containers: () => Promise.resolve([]) }))
    expect(await screen.findByText('No containers yet.')).toBeInTheDocument()
    await show(() => ({ containers: () => Promise.reject(new ApiError('unavailable')) }))
    expect(await screen.findByText('Docker is not answering.')).toBeInTheDocument()
  })

  it('refreshes the list every few seconds', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const api = await show((mock) => ({ containers: vi.fn(mock.containers) }))
    await screen.findByRole('group', { name: 'immich' })
    expect(api.containers).toHaveBeenCalledTimes(1)
    await act(() => vi.advanceTimersByTimeAsync(5000))
    expect(api.containers).toHaveBeenCalledTimes(2)
    vi.useRealTimers()
  })

  it('speaks French', async () => {
    await show(undefined, CHRIS, 'fr')
    const immich = await screen.findByRole('group', { name: 'immich' })
    expect(within(immich).getByText('4 sur 4 en marche')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Arrêter jellyfin' })).toBeInTheDocument()
    expect(within(row('pihole')).getByText('Arrêté')).toBeInTheDocument()
  })
})
