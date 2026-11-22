import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type User } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Settings } from './Settings'

const GUEST: User = { name: 'guest', uid: 1002, admin: false }

async function show(view: string, change: (api: Api) => Partial<Api> = () => ({}), user = CHRIS, lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(user.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Settings view={view} setView={() => {}} compact={false} minimized={false} />, { api, user, lang })
  return api
}

describe('Settings › General', () => {
  it('renames the server and says where to find it again', async () => {
    const api = await show('General', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    const name = await screen.findByLabelText('Server name')
    expect(name).toHaveValue('kura-nuc')
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled()
    await userEvent.clear(name)
    await userEvent.type(name, 'Attic')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'hostname', name: 'attic' })
    expect(await screen.findByText(/open https:\/\/attic\.local/)).toBeInTheDocument()
  })

  it('changes one’s own password, and says when the current one is wrong', async () => {
    const api = await show('General', (mock) => ({ changePassword: vi.fn(mock.changePassword) }), GUEST)
    expect(screen.queryByLabelText('Server name')).toBeNull()
    await userEvent.type(screen.getByLabelText('Current password'), 'wrong')
    await userEvent.type(screen.getByLabelText('New password'), 'new pass')
    await userEvent.type(screen.getByLabelText('New password, again'), 'new pas')
    expect(screen.getByText('The two do not match.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Change Password' })).toBeDisabled()
    await userEvent.type(screen.getByLabelText('New password, again'), 's')
    await userEvent.click(screen.getByRole('button', { name: 'Change Password' }))
    expect(await screen.findByText(/current password is not right/)).toBeInTheDocument()
    await userEvent.clear(screen.getByLabelText('Current password'))
    await userEvent.type(screen.getByLabelText('Current password'), MOCK_PASSWORD)
    await userEvent.click(screen.getByRole('button', { name: 'Change Password' }))
    expect(await screen.findByText(/Your password is changed/)).toBeInTheDocument()
    expect(api.changePassword).toHaveBeenLastCalledWith(MOCK_PASSWORD, 'new pass')
    expect(screen.getByLabelText('Current password')).toHaveValue('')
  })
})

describe('Settings › Network', () => {
  it('shows the devices as they are', async () => {
    await show('Network')
    const wired = await screen.findByRole('group', { name: 'enp1s0' })
    expect(wired).toHaveTextContent('192.168.1.50/24')
    expect(wired).toHaveTextContent('gateway 192.168.1.1')
    expect(screen.getByRole('group', { name: 'wlp2s0' })).toHaveTextContent('not connected')
  })

  it('sets an address, then asks to keep it', async () => {
    const api = await show('Network', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    await userEvent.click(await screen.findByRole('radio', { name: 'Set here' }))
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
    await userEvent.type(screen.getByLabelText('Address and prefix'), '192.168.1.60/24')
    await userEvent.type(screen.getByLabelText('Gateway'), '192.168.1.1')
    await userEvent.type(screen.getByLabelText('DNS servers'), '192.168.1.1, 9.9.9.9')
    await userEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'ethernet-static', address: '192.168.1.60/24', gateway: '192.168.1.1', dns: ['192.168.1.1', '9.9.9.9'] })
    // The page at the old address cannot keep it: it says where to go.
    expect(await screen.findByRole('link', { name: 'https://192.168.1.60' })).toHaveAttribute('href', 'https://192.168.1.60')
    expect(screen.getByText(/sign in and press Keep within two minutes/)).toBeInTheDocument()
    await userEvent.click(await screen.findByRole('button', { name: 'Keep' }))
    expect(api.changeSetting).toHaveBeenLastCalledWith({ what: 'network-confirm' })
    await vi.waitFor(() => expect(screen.queryByRole('button', { name: 'Keep' })).toBeNull())
    expect(screen.getByLabelText('Address and prefix')).toHaveValue('192.168.1.60/24')
  })

  it('says when the server does not accept an address', async () => {
    await show('Network')
    await userEvent.click(await screen.findByRole('radio', { name: 'Set here' }))
    await userEvent.type(screen.getByLabelText('Address and prefix'), 'nonsense')
    await userEvent.type(screen.getByLabelText('Gateway'), '192.168.1.1')
    await userEvent.type(screen.getByLabelText('DNS servers'), '1.1.1.1')
    await userEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(await screen.findByText('That is not a value the server accepts.')).toBeInTheDocument()
  })

  it('adds and forgets Wi-Fi networks', async () => {
    const api = await show('Network', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    const list = await screen.findByRole('list', { name: 'Wi-Fi networks' })
    expect(within(list).getByText('Attic')).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Network name'), 'Home')
    await userEvent.type(screen.getByLabelText('Wi-Fi password'), 'short')
    expect(screen.getByRole('button', { name: 'Add' })).toBeDisabled()
    await userEvent.type(screen.getByLabelText('Wi-Fi password'), ' but longer')
    await userEvent.click(screen.getByRole('checkbox', { name: 'Hidden network' }))
    await userEvent.click(screen.getByRole('button', { name: 'Add' }))
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'wifi-add', ssid: 'Home', password: 'short but longer', hidden: true })
    expect(await within(list).findByText('Home')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Forget Attic' }))
    await vi.waitFor(() => expect(within(list).queryByText('Attic')).toBeNull())
  })
})

describe('Settings › Users', () => {
  const row = (name: string) => screen.getByRole('listitem', { name })

  it('lists people, gives and takes administrator rights', async () => {
    const api = await show('Users', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    expect(await screen.findByRole('listitem', { name: 'chris' })).toHaveTextContent('you')
    expect(within(row('chris')).getByRole('button', { name: 'Remove' })).toBeDisabled()
    await userEvent.click(within(row('guest')).getByRole('switch', { name: 'Administrator' }))
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'user-admin', name: 'guest', admin: true })
    await vi.waitFor(() => expect(within(row('guest')).getByRole('switch', { name: 'Administrator' })).toBeChecked())
  })

  it('adds a person, gives a new password, and removes after asking', async () => {
    const api = await show('Users', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    await screen.findByRole('listitem', { name: 'anna' })
    await userEvent.type(screen.getByLabelText('User name'), 'Paul')
    await userEvent.type(screen.getByLabelText('Password'), 's3cret')
    await userEvent.click(screen.getByRole('button', { name: 'Add' }))
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'user-add', name: 'paul', password: 's3cret', admin: false })
    expect(await screen.findByRole('listitem', { name: 'paul' })).toBeInTheDocument()

    await userEvent.click(within(row('paul')).getByRole('button', { name: 'New Password…' }))
    const ask = screen.getByRole('dialog', { name: 'A new password for paul' })
    await userEvent.type(within(ask).getByLabelText('New password'), 'another')
    await userEvent.click(within(ask).getByRole('button', { name: 'Save' }))
    expect(api.changeSetting).toHaveBeenLastCalledWith({ what: 'user-password', name: 'paul', password: 'another' })

    await userEvent.click(within(row('paul')).getByRole('button', { name: 'Remove' }))
    const sure = await screen.findByRole('dialog', { name: 'Remove paul?' })
    expect(sure).toHaveTextContent('Their files stay in /home/paul.')
    await userEvent.click(within(sure).getByRole('button', { name: 'Remove' }))
    await vi.waitFor(() => expect(screen.queryByRole('listitem', { name: 'paul' })).toBeNull())
  })

  it('does not show an old refusal in the next dialog', async () => {
    await show('Users', () => ({ changeSetting: () => Promise.reject(new ApiError('unavailable')) }))
    await userEvent.click(within(await screen.findByRole('listitem', { name: 'anna' })).getByRole('button', { name: 'Remove' }))
    const sure = await screen.findByRole('dialog', { name: 'Remove anna?' })
    await userEvent.click(within(sure).getByRole('button', { name: 'Remove' }))
    expect(await within(sure).findByText('The server did not make the change.')).toBeInTheDocument()
    await userEvent.click(within(sure).getByRole('button', { name: 'Cancel' }))
    await vi.waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(screen.queryByText('The server did not make the change.')).toBeNull()
    await userEvent.click(within(screen.getByRole('listitem', { name: 'anna' })).getByRole('button', { name: 'New Password…' }))
    expect(within(screen.getByRole('dialog')).queryByText('The server did not make the change.')).toBeNull()
  })

  it('says when the server refuses, as for the last administrator', async () => {
    await show('Users', () => ({ changeSetting: () => Promise.reject(new ApiError('unavailable')) }))
    await userEvent.click(within(await screen.findByRole('listitem', { name: 'chris' })).getByRole('switch', { name: 'Administrator' }))
    expect(await screen.findByText('The server did not make the change.')).toBeInTheDocument()
  })
})

describe('Settings › Date & Time and Storage', () => {
  it('changes the zone and network time', async () => {
    const api = await show('DateTime', (mock) => ({ changeSetting: vi.fn(mock.changeSetting) }))
    const zone = await screen.findByLabelText('Time zone')
    expect(zone).toHaveValue('Europe/Paris')
    expect(screen.getByRole('status')).toHaveTextContent('The clock is set from the network.')
    await userEvent.selectOptions(zone, 'America/Chicago')
    expect(api.changeSetting).toHaveBeenCalledWith({ what: 'timezone', zone: 'America/Chicago' })
    await userEvent.click(screen.getByRole('switch', { name: 'Set the clock from the network' }))
    expect(api.changeSetting).toHaveBeenLastCalledWith({ what: 'ntp', on: false })
    expect(await screen.findByText('The clock is not set from the network.')).toBeInTheDocument()
  })

  it('shows the layout and the volumes, read only', async () => {
    await show('Storage')
    expect(await screen.findByText('applied')).toBeInTheDocument()
    expect(await screen.findByRole('meter', { name: '/var/lib/docker used' })).toBeInTheDocument()
    expect(screen.getByText(/cannot be changed from here/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Apply|Save/ })).toBeNull()
  })
})

describe('Settings for everyone else', () => {
  it.each(['Network', 'Users', 'DateTime', 'Storage'])('keeps %s for administrators, without asking the server', async (view) => {
    const api = await show(view, (mock) => ({ settings: vi.fn(mock.settings) }), GUEST)
    expect(screen.getByText('These settings are for administrators.')).toBeInTheDocument()
    expect(api.settings).not.toHaveBeenCalled()
  })

  it('says when the settings cannot be read, and speaks French', async () => {
    await show('Users', () => ({ settings: () => Promise.reject(new ApiError('unavailable')) }))
    expect(await screen.findByText('The server could not show its settings.')).toBeInTheDocument()
    await show('Network', undefined, CHRIS, 'fr')
    expect(await screen.findByRole('radio', { name: 'Fixée ici' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Oublier Attic' })).toBeInTheDocument()
  })
})
