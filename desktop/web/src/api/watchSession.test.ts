import { createMockApi } from './mock'
import { ApiError } from './types'
import { watchSession } from './watchSession'

describe('watchSession', () => {
  it('reports a session the server has ended, and passes everything else through', async () => {
    const api = createMockApi()
    const ended = vi.fn()
    let code: ApiError['code'] = 'signed_out'
    const fail = () => Promise.reject(new ApiError(code))
    const watched = watchSession({ ...api, containers: fail, containerAction: fail, containerLogs: fail, journal: fail }, ended)
    await expect(watched.containers()).rejects.toThrow('signed_out')
    await expect(watched.containerAction('a', 'stop')).rejects.toThrow('signed_out')
    await expect(watched.containerLogs('a', 5)).rejects.toThrow('signed_out')
    await expect(watched.journal({})).rejects.toThrow('signed_out')
    expect(ended).toHaveBeenCalledTimes(4)
    code = 'admin'
    await expect(watched.journal({})).rejects.toThrow('admin')
    expect(ended).toHaveBeenCalledTimes(4)
    expect(await watchSession(api, ended).system()).toEqual(await api.system())
  })

  it('asks about the session when a terminal is refused', async () => {
    const api = createMockApi()
    const ended = vi.fn()
    const ends: string[] = []
    const refuse: typeof api.terminal = (_size, h) => (h.onEnd('refused'), { write() {}, resize() {}, close() {} })
    const handlers = { onOpen() {}, onData() {}, onEnd: (r: string) => ends.push(r) }
    watchSession({ ...api, terminal: refuse }, ended).terminal({ cols: 80, rows: 24 }, handlers)
    await Promise.resolve()
    await Promise.resolve()
    expect(ended).toHaveBeenCalledTimes(1)
    expect(ends).toEqual(['refused'])
    await api.login('chris', 'kura')
    watchSession({ ...api, terminal: refuse }, ended).terminal({ cols: 80, rows: 24 }, handlers)
    await Promise.resolve()
    await Promise.resolve()
    expect(ended).toHaveBeenCalledTimes(1)
  })
})
