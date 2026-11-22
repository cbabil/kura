import { act, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type JournalPage } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Console } from './Console'

async function show(change: (api: Api) => Partial<Api> = () => ({}), user = CHRIS, lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(user.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Console view="" setView={() => {}} compact={false} minimized={false} />, { api, user, lang })
  return api
}

const rows = () => within(screen.getByRole('log', { name: 'System journal' })).getAllByRole('listitem')

describe('Console', () => {
  it('shows the newest journal entries with their source', async () => {
    await show()
    expect(await screen.findByText('Failed password for invalid user admin from 192.168.1.77')).toBeInTheDocument()
    expect(rows()).toHaveLength(8)
    expect(rows()[0]).toHaveTextContent('kura-desktopd')
    expect(rows()[0]).toHaveTextContent(/\d\d:\d\d:\d\d/)
    expect(rows()[5]).toHaveAttribute('data-tone', 'error')
    expect(rows()[3]).toHaveAttribute('data-tone', 'warning')
  })

  it('asks the server for one unit or one priority', async () => {
    const api = await show((mock) => ({ journal: vi.fn(mock.journal) }))
    await screen.findByText(/Synchronized to time server/)
    await userEvent.selectOptions(screen.getByLabelText('Unit'), 'ssh.service')
    expect(api.journal).toHaveBeenLastCalledWith({ lines: 300, unit: 'ssh.service', priority: undefined })
    await vi.waitFor(() => expect(rows()).toHaveLength(2))
    await userEvent.selectOptions(screen.getByLabelText('Priority'), 'Errors')
    expect(api.journal).toHaveBeenLastCalledWith({ lines: 300, unit: 'ssh.service', priority: 3 })
    await vi.waitFor(() => expect(rows()).toHaveLength(1))
    await userEvent.selectOptions(screen.getByLabelText('Unit'), 'All units')
    await vi.waitFor(() => expect(rows()).toHaveLength(1))
    expect(api.journal).toHaveBeenLastCalledWith({ lines: 300, unit: '', priority: 3 })
  })

  it('filters the messages on screen as you type', async () => {
    await show()
    await screen.findByText(/Synchronized to time server/)
    await userEvent.type(screen.getByRole('searchbox', { name: 'Filter messages' }), 'IMMICH')
    expect(rows()).toHaveLength(2)
    await userEvent.type(screen.getByRole('searchbox', { name: 'Filter messages' }), ' zzz')
    expect(screen.getByText('No entries match.')).toBeInTheDocument()
  })

  it('follows the journal, adding what is new, until told to stop', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const fresh: JournalPage = { cursor: 's=mock;i=9', entries: [{ t: Date.now(), priority: 5, unit: 'cron.service', ident: 'cron', pid: 1, message: 'a new line' }] }
    const journal = vi.fn((f: { after?: string }) => Promise.resolve(f.after === 's=mock;i=8' ? fresh : { entries: [], cursor: null }))
    await show((mock) => ({ journal: (f) => (f.after ? journal(f) : mock.journal(f)) }))
    await screen.findByText(/Synchronized to time server/)
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(journal).toHaveBeenCalledWith({ lines: 300, unit: '', priority: undefined, after: 's=mock;i=8' })
    expect(await screen.findByText('a new line')).toBeInTheDocument()
    expect(rows()).toHaveLength(9)
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(journal).toHaveBeenLastCalledWith(expect.objectContaining({ after: 's=mock;i=9' }))
    await userEvent.click(screen.getByRole('switch', { name: 'Follow' }))
    const calls = journal.mock.calls.length
    await act(() => vi.advanceTimersByTimeAsync(9000))
    expect(journal).toHaveBeenCalledTimes(calls)
    vi.useRealTimers()
  })

  it('tries again after a failure, and shows what a quiet filter gets later', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const late = { cursor: 's=mock;i=1', entries: [{ t: 1, priority: 3, unit: 'x.service', ident: 'x', pid: 1, message: 'it came' }] }
    const journal = vi.fn().mockRejectedValueOnce(new ApiError('unavailable')).mockResolvedValueOnce({ entries: [], cursor: null }).mockResolvedValue(late)
    await show(() => ({ journal }))
    expect(await screen.findByText('The journal could not be read.')).toBeInTheDocument()
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(await screen.findByText('No entries match.')).toBeInTheDocument()
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(await screen.findByText('it came')).toBeInTheDocument()
    expect(journal.mock.calls[2][0]).not.toHaveProperty('after')
    vi.useRealTimers()
  })

  it('is for administrators', async () => {
    const api = await show((mock) => ({ journal: vi.fn(mock.journal) }), { name: 'guest', uid: 1001, admin: false })
    expect(screen.getByText('The system journal is for administrators.')).toBeInTheDocument()
    expect(api.journal).not.toHaveBeenCalled()
  })

  it('says when the journal cannot be read', async () => {
    await show(() => ({ journal: () => Promise.reject(new ApiError('unavailable')) }))
    expect(await screen.findByText('The journal could not be read.')).toBeInTheDocument()
  })

  it('speaks French', async () => {
    await show(undefined, CHRIS, 'fr')
    await screen.findByText(/Synchronized to time server/)
    expect(screen.getByLabelText('Unité')).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Avertissements et erreurs' })).toBeInTheDocument()
    expect(screen.getByRole('switch', { name: 'Suivre' })).toBeChecked()
  })
})
