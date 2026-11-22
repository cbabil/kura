import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { Api } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Settings } from './Settings'

async function show(view: string, change: (api: Api) => Partial<Api> = () => ({})) {
  const mock = createMockApi()
  await mock.login(CHRIS.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Settings view={view} setView={() => {}} compact={false} minimized={false} />, { api })
  return api
}

describe('Settings › General › the server’s own screen', () => {
  it('turns the server’s own screen on where the image has one', async () => {
    const api = await show('General', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    const screenSwitch = await screen.findByRole('switch', { name: 'Show Kura Desktop on it' })
    expect(screenSwitch).not.toBeChecked()
    await userEvent.click(screenSwitch)
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'screen', on: true })
    await vi.waitFor(() => expect(screen.getByRole('switch', { name: 'Show Kura Desktop on it' })).toBeChecked())
  })

  it('shows no such switch on a server without one', async () => {
    await show('General', (mock) => ({ settings: async () => ({ ...(await mock.settings()), screen: null }) }))
    await screen.findByLabelText('Server name')
    expect(screen.queryByRole('switch', { name: 'Show Kura Desktop on it' })).toBeNull()
  })
})
