import { act, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api, type PowerKind } from '../api'
import { createMockApi } from '../api/mock'
import { renderWithTheme } from '../test/render'
import { PowerDialog } from './PowerDialog'

function setup(how: PowerKind | null, change: Partial<Api> = {}) {
  const api = { ...createMockApi(), power: vi.fn(() => Promise.resolve()), ...change }
  const onClose = vi.fn()
  const reload = vi.fn()
  renderWithTheme(<PowerDialog how={how} onClose={onClose} reload={reload} />, { api })
  return { api, onClose, reload }
}

describe('PowerDialog', () => {
  it('shows nothing until asked', () => {
    setup(null)
    expect(screen.queryByRole('dialog')).toBeNull()
  })

  it('does nothing when cancelled', async () => {
    const { api, onClose } = setup('shutdown')
    expect(screen.getByRole('dialog', { name: 'Shut down this server?' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(api.power).not.toHaveBeenCalled()
    expect(onClose).toHaveBeenCalled()
  })

  it('shuts down on the second yes, and says the page can be closed', async () => {
    const { api } = setup('shutdown')
    await userEvent.click(screen.getByRole('button', { name: 'Shut Down' }))
    expect(api.power).toHaveBeenCalledWith('shutdown')
    expect(screen.getByText(/You can close this page/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Cancel' })).toBeNull()
  })

  it('restarts, then loads the page again once the server has gone and come back', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    let up = true
    // A restarted server knows no session any more: it answers "nobody", and that is "back"
    const session = vi.fn(() => (up ? Promise.resolve(null) : Promise.reject(new Error('down'))))
    const { reload } = setup('restart', { session })
    await userEvent.click(screen.getByRole('button', { name: 'Restart' }))
    expect(screen.getByText(/comes back by itself/)).toBeInTheDocument()
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(reload).not.toHaveBeenCalled() // still the old server answering
    up = false
    await act(() => vi.advanceTimersByTimeAsync(3000))
    up = true
    await act(() => vi.advanceTimersByTimeAsync(3000))
    expect(reload).toHaveBeenCalledTimes(1)
    vi.useRealTimers()
  })

  it('takes a dropped connection as the server going, not as a failure', async () => {
    setup('restart', { power: () => Promise.reject(new ApiError('network')) })
    await userEvent.click(screen.getByRole('button', { name: 'Restart' }))
    await act(async () => {})
    expect(screen.getByText(/comes back by itself/)).toBeInTheDocument()
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('says when the server refused', async () => {
    setup('restart', { power: () => Promise.reject(new ApiError('unavailable')) })
    await userEvent.click(screen.getByRole('button', { name: 'Restart' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('The server did not do it')
    expect(screen.getByRole('button', { name: 'Restart' })).toBeInTheDocument()
  })
})
