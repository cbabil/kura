import { fireEvent, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../test/render'
import { Dock } from './Dock'

function setup(over: Partial<Parameters<typeof Dock>[0]> = {}) {
  const onOpen = vi.fn()
  const onPinnedChange = vi.fn()
  renderWithTheme(
    <Dock pinned={['activity', 'files', 'terminal']} running={['activity']} minimized={[]} compact={false}
      onOpen={onOpen} onPinnedChange={onPinnedChange} {...over} />,
  )
  return { onOpen, onPinnedChange, dock: screen.getByRole('navigation', { name: 'Dock' }) }
}

describe('Dock', () => {
  it('shows pinned apps in order, then Trash, and marks running ones', () => {
    const { dock } = setup()
    const names = within(dock).getAllByRole('button').map((b) => b.getAttribute('aria-label'))
    expect(names).toEqual(['Activity Monitor', 'Files', 'Terminal', 'Trash'])
    expect(screen.getByLabelText('Activity Monitor')).toHaveAttribute('data-running', 'true')
    expect(screen.getByLabelText('Files')).toHaveAttribute('data-running', 'false')
  })

  it('opens an app on click', async () => {
    const { onOpen } = setup()
    await userEvent.click(screen.getByLabelText('Files'))
    expect(onOpen).toHaveBeenCalledWith('files')
  })

  it('adds running apps that are not pinned, and minimised windows', () => {
    setup({ running: ['activity', 'console'], minimized: ['activity'] })
    expect(screen.getByLabelText('Console')).toHaveAttribute('data-running', 'true')
    fireEvent.click(screen.getByLabelText('Activity Monitor (minimised)'))
  })

  it('removes and keeps apps from the context menu', async () => {
    const { onPinnedChange, onOpen } = setup({ running: ['activity', 'console'] })
    fireEvent.contextMenu(screen.getByLabelText('Files'))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Remove from Dock' }))
    expect(onPinnedChange).toHaveBeenCalledWith(['activity', 'terminal'])
    fireEvent.contextMenu(screen.getByLabelText('Console'))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Keep in Dock' }))
    expect(onPinnedChange).toHaveBeenLastCalledWith(['activity', 'files', 'terminal', 'console'])
    fireEvent.contextMenu(screen.getByLabelText('Terminal'))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Open' }))
    expect(onOpen).toHaveBeenCalledWith('terminal')
  })

  it('reorders by drag and drop', () => {
    const { onPinnedChange, dock } = setup()
    const data = { setData: vi.fn() }
    fireEvent.dragStart(screen.getByLabelText('Terminal'), { dataTransfer: data })
    fireEvent.dragOver(screen.getByLabelText('Activity Monitor'))
    fireEvent.drop(screen.getByLabelText('Activity Monitor'))
    expect(onPinnedChange).toHaveBeenCalledTimes(1)
    expect(onPinnedChange).toHaveBeenCalledWith(['terminal', 'activity', 'files'])
    fireEvent.dragStart(screen.getByLabelText('Activity Monitor'), { dataTransfer: data })
    fireEvent.drop(dock)
    expect(onPinnedChange).toHaveBeenLastCalledWith(['files', 'terminal', 'activity'])
  })
})
