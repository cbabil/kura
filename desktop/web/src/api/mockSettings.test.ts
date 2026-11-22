import { createMockApi, MOCK_PASSWORD } from './mock'
import { ApiError, type SettingChange } from './types'

const code = (p: Promise<unknown>) => p.then(() => 'resolved', (e: unknown) => (e instanceof ApiError ? e.code : 'other'))

async function signedIn(name = 'chris') {
  const api = createMockApi()
  await api.login(name, MOCK_PASSWORD)
  return api
}

describe('mock api: settings', () => {
  it('shows a small device to administrators only', async () => {
    const api = await signedIn()
    const s = await api.settings()
    expect([s.hostname, s.time.zone, s.network.devices.length, s.users.length]).toEqual(['kura-nuc', 'Europe/Paris', 2, 3])
    expect(await code((await signedIn('guest')).settings())).toBe('admin')
    expect(await code((await signedIn('guest')).changeSetting({ what: 'ntp', on: false }))).toBe('admin')
  })

  it('applies each change', async () => {
    const api = await signedIn()
    const changes: SettingChange[] = [
      { what: 'hostname', name: 'attic' },
      { what: 'timezone', zone: 'America/Chicago' },
      { what: 'ntp', on: false },
      { what: 'wifi-add', ssid: 'Home', password: 'correct horse', hidden: false },
      { what: 'wifi-remove', ssid: 'Attic' },
      { what: 'ethernet-static', address: '192.168.1.60/24', gateway: '192.168.1.1', dns: ['192.168.1.1'] },
      { what: 'user-add', name: 'paul', password: 'x', admin: false },
      { what: 'user-admin', name: 'guest', admin: true },
      { what: 'user-password', name: 'guest', password: 'new' },
      { what: 'user-remove', name: 'anna' },
    ]
    for (const c of changes) await api.changeSetting(c)
    const s = await api.settings()
    expect([s.hostname, s.time.zone, s.time.ntp, s.network.wifi, s.network.pending]).toEqual(['attic', 'America/Chicago', false, ['Home'], true])
    expect(s.network.ethernet).toEqual({ method: 'manual', address: '192.168.1.60/24', gateway: '192.168.1.1', dns: ['192.168.1.1'] })
    expect(s.users.map((u) => [u.name, u.admin])).toEqual([['chris', true], ['guest', true], ['paul', false]])
    await api.changeSetting({ what: 'network-confirm' })
    await api.changeSetting({ what: 'ethernet-auto' })
    expect((await api.settings()).network.ethernet.method).toBe('auto')
  })

  it('refuses what the server refuses', async () => {
    const api = await signedIn()
    const bad: SettingChange[] = [
      { what: 'hostname', name: 'Not A Host' },
      { what: 'timezone', zone: '../etc' },
      { what: 'wifi-add', ssid: 'Home', password: 'short', hidden: false },
      { what: 'ethernet-static', address: '192.168.1.60', gateway: '192.168.1.1', dns: ['1.1.1.1'] },
      { what: 'ethernet-static', address: '192.168.1.60/24', gateway: '192.168.1.1', dns: [] },
      { what: 'user-add', name: 'anna', password: 'x', admin: false },
      { what: 'user-add', name: 'Paul', password: 'x', admin: false },
      { what: 'user-remove', name: 'chris' },
      { what: 'user-remove', name: 'ghost' },
      { what: 'user-password', name: 'anna', password: '' },
    ]
    for (const c of bad) expect(await code(api.changeSetting(c))).toBe('bad_request')
    await api.changeSetting({ what: 'user-admin', name: 'anna', admin: false })
    expect(await code(api.changeSetting({ what: 'user-admin', name: 'chris', admin: false }))).toBe('unavailable')
  })

  it('changes one’s own password with the current one', async () => {
    const api = await signedIn('guest')
    await expect(api.changePassword(MOCK_PASSWORD, 'new pass')).resolves.toBeUndefined()
    expect(await code(api.changePassword('wrong', 'new pass'))).toBe('bad_request')
    expect(await code(api.changePassword(MOCK_PASSWORD, ''))).toBe('bad_request')
    expect(await code(createMockApi().changePassword(MOCK_PASSWORD, 'x'))).toBe('signed_out')
  })
})
