import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../../test/render'
import { createMockApi } from '../../api/mock'
import type { Api } from '../../api'
import { ActivityMonitor, RangeSwitch } from './ActivityMonitor'

function show(view: string, api: Api = createMockApi(), compact = false) {
  const setView = vi.fn()
  renderWithTheme(<ActivityMonitor view={view} setView={setView} compact={compact} minimized={false} />, { api })
  return setView
}

describe('ActivityMonitor', () => {
  it('summarises CPU, memory, storage, network and the busiest processes', async () => {
    show('Summary')
    expect(await screen.findByText('CPU · 4 cores')).toBeInTheDocument()
    expect(screen.getByText('Memory · 16 GB')).toBeInTheDocument()
    expect(screen.getByText('4 volumes')).toBeInTheDocument()
    expect(screen.getAllByRole('row')[1]).toHaveTextContent('immich-server')
    expect(screen.getByRole('meter', { name: 'Memory' })).toBeInTheDocument()
  })

  it('switches sections from the sidebar, and falls back to Summary for an unknown one', async () => {
    const setView = show('nope')
    expect(screen.getByRole('button', { name: 'Summary' })).toHaveAttribute('aria-current', 'page')
    await userEvent.click(screen.getByRole('button', { name: 'Services' }))
    expect(setView).toHaveBeenCalledWith('Services')
  })

  it.each([
    ['CPU', 'Peak'],
    ['Memory', 'Free'],
    ['Network', 'Download'],
    ['Storage', '/var/lib/docker'],
    ['Services', 'docker'],
  ])('shows the %s view', async (view, text) => {
    show(view)
    expect((await screen.findAllByText(text)).length).toBeGreaterThan(0)
  })

  it('speaks the desktop’s language, plurals included', async () => {
    renderWithTheme(<ActivityMonitor view="Summary" setView={() => {}} compact={false} minimized={false} />, { api: createMockApi(), lang: 'fr' })
    expect(await screen.findByText('Processeur · 4 cœurs')).toBeInTheDocument()
    expect(screen.getByText('4 volumes')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Résumé' })).toHaveAttribute('aria-current', 'page')
  })

  it('waits for the first measurement, except for services', () => {
    const quiet = { ...createMockApi(), stats: () => () => {} }
    show('CPU', quiet, true)
    expect(screen.getByText(/Waiting for the first measurement/)).toBeInTheDocument()
  })
})

describe('RangeSwitch', () => {
  it('reports a new range and ignores deselecting', async () => {
    const onRange = vi.fn()
    render(<RangeSwitch range="1h" onRange={onRange} />)
    await userEvent.click(screen.getByRole('button', { name: '24 h' }))
    await userEvent.click(screen.getByRole('button', { name: '1 h' }))
    expect(onRange).toHaveBeenCalledTimes(1)
    expect(onRange).toHaveBeenCalledWith('24h')
  })
})
