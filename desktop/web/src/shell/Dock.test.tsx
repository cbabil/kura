import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../test/render'
import { Dock } from './Dock'

function setup(over: Partial<Parameters<typeof Dock>[0]> = {}) {
  const onOpen = vi.fn()
  const onQuit = vi.fn()
  const onPinnedChange = vi.fn()
  renderWithTheme(
    <Dock pinned={['activity', 'files', 'terminal']} running={['activity']} minimized={[]} compact={false}
      onOpen={onOpen} onQuit={onQuit} onPinnedChange={onPinnedChange} {...over} />,
  )
  return { onOpen, onQuit, onPinnedChange, dock: screen.getByRole('navigation', { name: 'Dock' }) }
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

  describe('the menu, as on a Mac', () => {
    /** Right-clicks `label` and opens its Options submenu. */
    async function options(label: string) {
      fireEvent.contextMenu(screen.getByLabelText(label))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Options' }))
    }

    it('removes a kept app that is not open, and opens it', async () => {
      const { onPinnedChange, onOpen } = setup()
      fireEvent.contextMenu(screen.getByLabelText('Files'))
      expect(await screen.findByRole('menuitem', { name: 'Open' })).toBeInTheDocument()
      expect(screen.queryByRole('menuitem', { name: 'Quit' })).not.toBeInTheDocument()
      await userEvent.click(screen.getByRole('menuitem', { name: 'Options' }))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Remove from Dock' }))
      expect(onPinnedChange).toHaveBeenCalledWith(['activity', 'terminal'])
      await waitFor(() => expect(screen.queryByRole('menu')).not.toBeInTheDocument())
      fireEvent.contextMenu(screen.getByLabelText('Terminal'))
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Open' }))
      expect(onOpen).toHaveBeenCalledWith('terminal')
    })

    it('ticks Keep in Dock for an open app that is kept; unticking it and quitting removes it', async () => {
      const { onPinnedChange, onQuit } = setup()
      await options('Activity Monitor')
      const keep = await screen.findByRole('menuitemcheckbox', { name: 'Keep in Dock' })
      expect(keep).toHaveAttribute('aria-checked', 'true')
      await userEvent.click(keep)
      expect(onPinnedChange).toHaveBeenCalledWith(['files', 'terminal'])
      fireEvent.contextMenu(screen.getByLabelText('Activity Monitor'))
      expect(screen.queryByRole('menuitem', { name: 'Open' })).not.toBeInTheDocument()
      await userEvent.click(await screen.findByRole('menuitem', { name: 'Quit' }))
      expect(onQuit).toHaveBeenCalledWith('activity')
    })

    it('keeps an open app that is not kept', async () => {
      const { onPinnedChange } = setup({ running: ['activity', 'console'] })
      await options('Console')
      const keep = await screen.findByRole('menuitemcheckbox', { name: 'Keep in Dock' })
      expect(keep).toHaveAttribute('aria-checked', 'false')
      await userEvent.click(keep)
      expect(onPinnedChange).toHaveBeenLastCalledWith(['activity', 'files', 'terminal', 'console'])
    })

    it('opens Options from the keyboard too', async () => {
      setup()
      fireEvent.contextMenu(screen.getByLabelText('Files'))
      const item = await screen.findByRole('menuitem', { name: 'Options' })
      expect(item).toHaveAttribute('aria-haspopup', 'menu')
      fireEvent.keyDown(item, { key: 'ArrowRight' })
      expect(await screen.findByRole('menuitem', { name: 'Remove from Dock' })).toBeInTheDocument()
    })
  })

  describe('dragging, as on a Mac', () => {
    // jsdom lays nothing out: each icon is 64 px wide at 66 px steps; the dock's top is at y 800
    const LEFT: Record<string, number> = { 'Activity Monitor': 0, Files: 66, Terminal: 132, Console: 198 }
    beforeEach(() => {
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
        const left = LEFT[this.getAttribute('aria-label') ?? ''] ?? 0
        return { left, width: 64, top: 800 } as DOMRect
      })
    })
    afterEach(() => vi.restoreAllMocks())

    /** Presses `label` and moves the pointer through `path` with the button held; the dock gets the moves. */
    function press(label: string, path: [number, number][], options: { pointerType?: string } = {}) {
      const dock = screen.getByRole('navigation', { name: 'Dock' })
      fireEvent.pointerDown(screen.getByLabelText(label), { button: 0, clientX: LEFT[label] + 32, clientY: 830, ...options })
      for (const [x, y] of path) fireEvent.pointerMove(dock, { clientX: x, clientY: y, buttons: 1 })
      return () => fireEvent.pointerUp(dock)
    }

    it('opens a gap where the icon will land, and puts it there', () => {
      const { onPinnedChange, dock } = setup()
      const letGo = press('Terminal', [[100, 830], [10, 830]])
      // the dragged icon has left its place; the gap is first
      const row = within(dock).getAllByRole('button').map((b) => b.getAttribute('aria-label'))
      expect(row).toEqual(['Activity Monitor', 'Files', 'Trash'])
      expect(dock.firstElementChild).toHaveAttribute('data-testid', 'dock-gap')
      letGo()
      expect(onPinnedChange).toHaveBeenCalledWith(['terminal', 'activity', 'files'])
      expect(screen.queryByTestId('dock-gap')).not.toBeInTheDocument()
    })

    it('moves a kept app to the end, and leaves the order alone when it lands where it was', () => {
      const { onPinnedChange } = setup()
      press('Activity Monitor', [[500, 830]])()
      expect(onPinnedChange).toHaveBeenLastCalledWith(['files', 'terminal', 'activity'])
      onPinnedChange.mockClear()
      press('Files', [[90, 830]])()
      expect(onPinnedChange).not.toHaveBeenCalled()
    })

    it('keeps a running app dropped among the kept ones', () => {
      const { onPinnedChange } = setup({ running: ['activity', 'console'] })
      press('Console', [[180, 830], [70, 830]])()
      expect(onPinnedChange).toHaveBeenCalledWith(['activity', 'console', 'files', 'terminal'])
    })

    it('removes a kept app pulled up and away, and says so while it is out', () => {
      const { onPinnedChange } = setup()
      const letGo = press('Files', [[100, 820], [100, 600]])
      expect(screen.getByText('Remove from Dock')).toBeInTheDocument()
      letGo()
      expect(onPinnedChange).toHaveBeenCalledWith(['activity', 'terminal'])
    })

    it('changes nothing for a running app pulled out, Escape, a lost pointer, a click or a touch', () => {
      const { onPinnedChange, onOpen, dock } = setup({ running: ['activity', 'console'] })
      press('Console', [[200, 600]])()
      const escaped = press('Terminal', [[10, 830]])
      fireEvent.keyDown(window, { key: 'Escape' })
      expect(screen.queryByTestId('dock-gap')).not.toBeInTheDocument()
      escaped()
      press('Terminal', [[10, 830]])
      fireEvent.pointerCancel(dock)
      expect(onPinnedChange).not.toHaveBeenCalled()
      // a press that hardly moves is a click
      press('Files', [[101, 831]])()
      fireEvent.click(screen.getByLabelText('Files'))
      expect(onOpen).toHaveBeenCalledWith('files')
      // a press let go elsewhere is forgotten: a later move with no button down drags nothing
      press('Files', [])
      fireEvent.pointerMove(dock, { clientX: 10, clientY: 830, buttons: 0 })
      fireEvent.pointerMove(dock, { clientX: 10, clientY: 830, buttons: 1 })
      expect(screen.queryByTestId('dock-gap')).not.toBeInTheDocument()
      // touch keeps its long-press menu and its scrolling
      press('Files', [[10, 830]], { pointerType: 'touch' })
      expect(screen.queryByTestId('dock-gap')).not.toBeInTheDocument()
    })
  })
})
