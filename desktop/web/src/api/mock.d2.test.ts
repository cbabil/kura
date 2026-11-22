import { createMockApi, MOCK_PASSWORD } from './mock'
import { ApiError, type TerminalEnd } from './types'

const code = (p: Promise<unknown>) => p.then(() => 'resolved', (e: unknown) => (e instanceof ApiError ? e.code : 'other'))

async function signedIn(name = 'chris') {
  const api = createMockApi()
  await api.login(name, MOCK_PASSWORD)
  return api
}

describe('mock api: containers', () => {
  it('lists the sample stacks and changes a container’s state', async () => {
    const api = await signedIn()
    const list = await api.containers()
    expect(list).toHaveLength(7)
    expect(list.filter((c) => c.project === 'immich')).toHaveLength(4)
    const pihole = list.find((c) => c.name === 'pihole')!
    expect(pihole.state).toBe('exited')
    await api.containerAction(pihole.id, 'start')
    expect((await api.containers()).find((c) => c.name === 'pihole')!.state).toBe('running')
    await api.containerAction(pihole.id, 'stop')
    expect((await api.containers()).find((c) => c.name === 'pihole')!.state).toBe('exited')
    expect(await code(api.containerAction('nope', 'stop'))).toBe('not_found')
  })

  it('gives logs, to administrators only', async () => {
    const api = await signedIn()
    const [first] = await api.containers()
    const lines = await api.containerLogs(first.id, 5)
    expect(lines).toHaveLength(5)
    expect(lines[4].text).toContain(first.name)
    expect(await code(api.containerLogs('nope', 5))).toBe('not_found')
    const guest = await signedIn('guest')
    expect((await guest.session())?.admin).toBe(false)
    expect(await guest.containers()).toHaveLength(7)
    expect(await code(guest.containerAction(first.id, 'stop'))).toBe('admin')
    expect(await code(guest.containerLogs(first.id, 5))).toBe('admin')
    expect(await code(guest.journal({}))).toBe('admin')
  })
})

describe('mock api: updates and power', () => {
  it('has an update waiting, which an administrator installs', async () => {
    const api = await signedIn()
    expect(await api.updates()).toEqual({ current: '0.6.1', available: '0.6.2', restartRequired: false, job: null })
    await api.startUpdate('check')
    expect((await api.updates()).job?.output[1]).toBe('Reading package lists...')
    await api.startUpdate('install')
    const after = await api.updates()
    expect(after).toMatchObject({ current: '0.6.2', available: null, restartRequired: true })
    expect(after.job?.state).toBe('done')
    await expect(api.power('restart')).resolves.toBeUndefined()
  })

  it('lets others look only', async () => {
    const guest = await signedIn('guest')
    expect((await guest.updates()).available).toBe('0.6.2')
    expect(await code(guest.startUpdate('install'))).toBe('admin')
    expect(await code(guest.power('shutdown'))).toBe('admin')
  })
})

describe('mock api: the journal', () => {
  it('filters by unit and priority, and pages by cursor', async () => {
    const api = await signedIn()
    const all = await api.journal({})
    expect(all.entries).toHaveLength(8)
    expect(all.cursor).toBe('s=mock;i=8')
    expect((await api.journal({ unit: 'ssh.service' })).entries).toHaveLength(2)
    expect((await api.journal({ priority: 4 })).entries).toHaveLength(2)
    expect((await api.journal({ lines: 3 })).entries).toHaveLength(3)
    expect(await api.journal({ after: 's=mock;i=8' })).toEqual({ entries: [], cursor: null })
  })
})

describe('mock api: the terminal', () => {
  function start(name = 'chris') {
    const api = createMockApi()
    void api.login(name, MOCK_PASSWORD)
    let screen = ''
    const ends: TerminalEnd[] = []
    const opened = vi.fn()
    const session = api.terminal(
      { cols: 80, rows: 24 },
      { onOpen: opened, onData: (b) => (screen += new TextDecoder().decode(b)), onEnd: (r) => ends.push(r) },
    )
    return { session, ends, opened, text: () => screen }
  }

  it('is a small shell that echoes and answers a few commands', async () => {
    const t = start()
    await Promise.resolve()
    expect(t.opened).toHaveBeenCalled()
    expect(t.text()).toContain('chris@kura-nuc:~$ ')
    t.session.write('whoami\r')
    expect(t.text()).toContain('whoami\r\nchris\r\n')
    t.session.write('echo hello there\r')
    expect(t.text()).toContain('hello there\r\n')
    t.session.write(new TextEncoder().encode('lx\x7fs\r'))
    expect(t.text()).toContain('ls: not in this demonstration shell')
    t.session.write('\r')
    t.session.resize(100, 30)
    t.session.write('exit\r')
    expect(t.ends).toEqual(['exit'])
    const before = t.text()
    t.session.write('whoami\r')
    expect(t.text()).toBe(before)
  })

  it('stops when closed', async () => {
    const t = start()
    await Promise.resolve()
    t.session.close()
    const before = t.text()
    t.session.write('whoami\r')
    expect(t.text()).toBe(before)
    expect(t.ends).toEqual([])
  })
})
