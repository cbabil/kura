import { fireEvent, screen } from '@testing-library/react'
import { renderWithTheme } from '../test/render'
import { APP_BY_ID } from '../apps/registry'
import { boundsFor } from './layout'
import { Window } from './Window'
import type { WindowActions } from './useDesktop'
import type { Win } from './windows'

const win: Win = { app: 'catalog', x: 100, y: 80, w: 800, h: 500, minimized: false, maximized: false }

function setup(width = 1440) {
  const actions: WindowActions = {
    open: vi.fn(), focus: vi.fn(), close: vi.fn(), minimize: vi.fn(), zoom: vi.fn(),
    move: vi.fn(), resize: vi.fn(), settle: vi.fn(), setView: vi.fn(), command: vi.fn(),
  }
  renderWithTheme(
    <Window win={win} def={{ ...APP_BY_ID.catalog, Body: undefined }} focused={false} bounds={boundsFor(width, 900)} z={1} view="" actions={actions} />,
  )
  return { actions, bar: screen.getAllByText('App Catalog')[0].parentElement as HTMLElement /* the title, before the body's name */ }
}

describe('Window', () => {
  it('shows the app (or what is coming) and runs the three buttons', () => {
    const { actions } = setup()
    expect(screen.getByRole('dialog', { name: 'App Catalog' })).toBeInTheDocument()
    expect(screen.getByText('Arrives in a coming update of Kura.')).toBeInTheDocument()
    fireEvent.click(screen.getByLabelText('Close'))
    fireEvent.click(screen.getByLabelText('Minimize'))
    fireEvent.click(screen.getByLabelText('Zoom'))
    expect(actions.close).toHaveBeenCalledWith('catalog')
    expect(actions.minimize).toHaveBeenCalledWith('catalog')
    expect(actions.zoom).toHaveBeenCalledWith('catalog')
  })

  it('focuses on press, moves by the title bar and settles when released', () => {
    const { actions, bar } = setup()
    fireEvent.pointerDown(bar, { button: 0, clientX: 200, clientY: 100, pointerId: 1 })
    fireEvent.pointerMove(bar, { clientX: 260, clientY: 140, pointerId: 1 })
    fireEvent.pointerUp(bar, { pointerId: 1 })
    expect(actions.focus).toHaveBeenCalledWith('catalog')
    expect(actions.move).toHaveBeenCalledWith('catalog', 160, 120)
    expect(actions.settle).toHaveBeenCalledTimes(1)
  })

  it('zooms on a title bar double-click and resizes from the edges and corner', () => {
    const { actions, bar } = setup()
    fireEvent.doubleClick(bar)
    expect(actions.zoom).toHaveBeenCalled()
    for (const [id, dx, dy, w, h] of [['corner', 50, 20, 850, 520], ['right', 30, 99, 830, 500], ['bottom', 99, 10, 800, 510]] as const) {
      const handle = screen.getByTestId(`resize-${id}`)
      fireEvent.pointerDown(handle, { button: 0, clientX: 0, clientY: 0, pointerId: 2 })
      fireEvent.pointerMove(handle, { clientX: dx, clientY: dy, pointerId: 2 })
      fireEvent.pointerUp(handle, { pointerId: 2 })
      expect(actions.resize).toHaveBeenLastCalledWith('catalog', w, h)
    }
  })

  it('does not move or resize on a phone', () => {
    const { actions, bar } = setup(390)
    fireEvent.pointerDown(bar, { button: 0, clientX: 1, clientY: 1, pointerId: 1 })
    fireEvent.pointerMove(bar, { clientX: 50, clientY: 50, pointerId: 1 })
    fireEvent.doubleClick(bar)
    expect(actions.move).not.toHaveBeenCalled()
    expect(actions.zoom).not.toHaveBeenCalled()
    expect(screen.queryByTestId('resize-corner')).toBeNull()
  })
})
