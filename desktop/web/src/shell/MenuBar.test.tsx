import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../test/render'
import { createMockApi } from '../api/mock'
import type { Api } from '../api'
import type { AppMenu } from '../apps/types'
import { MenuBar, Clock } from './MenuBar'

const close = vi.fn()
const about = vi.fn()
const menus: AppMenu[] = [
  { title: 'menu.file', items: [{ label: 'menu.closeWindow', run: close }] },
  { title: 'menu.window', items: [] },
]
const kuraMenu: AppMenu = { title: '蔵', items: [{ label: 'menu.about', run: about }] }

function setup(over: Partial<Parameters<typeof MenuBar>[0]> = {}, api: Api = createMockApi()) {
  const h = { onRun: vi.fn((item) => item.run({})), onToggleTheme: vi.fn(), onLauncher: vi.fn() }
  renderWithTheme(
    <MenuBar appName="Activity Monitor" kuraMenu={kuraMenu} menus={menus} compact={false} mode="dark" {...h} {...over} />,
    { api },
  )
  return h
}

describe('MenuBar', () => {
  it('shows the app, its menus, and live temperature and connection', () => {
    setup()
    expect(screen.getByText('Activity Monitor')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'File' })).toBeInTheDocument()
    expect(screen.getByText(/^\d+°$/)).toBeInTheDocument()
    expect(screen.getByLabelText('Online')).toBeInTheDocument()
  })

  it('runs the chosen item of an app menu or the Kura menu', async () => {
    const h = setup()
    await userEvent.click(screen.getByRole('button', { name: 'File' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Close Window' }))
    expect(close).toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Kura menu' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'About Kura' }))
    expect(about).toHaveBeenCalled()
    expect(h.onRun).toHaveBeenCalledTimes(2)
  })

  it('hides app menus on a phone, says when offline, switches theme and opens search', async () => {
    const quiet = { ...createMockApi(), stats: () => () => {} }
    const h = setup({ compact: true, mode: 'light' }, quiet)
    expect(screen.queryByRole('button', { name: 'File' })).toBeNull()
    expect(screen.getByLabelText('Offline')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Use dark theme' }))
    await userEvent.click(screen.getByRole('button', { name: 'Search (Ctrl K)' }))
    expect(h.onToggleTheme).toHaveBeenCalled()
    expect(h.onLauncher).toHaveBeenCalled()
  })
})

describe('Clock', () => {
  it('ticks', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 10, 17, 9, 41))
    render(<Clock />)
    const before = document.body.textContent
    act(() => {
      vi.setSystemTime(new Date(2026, 10, 17, 9, 42))
      vi.advanceTimersByTime(15_000)
    })
    expect(document.body.textContent).not.toBe(before)
    vi.useRealTimers()
  })
})
