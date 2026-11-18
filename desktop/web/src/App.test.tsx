import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMockApi, MOCK_PASSWORD } from './api/mock'
import type { Api } from './api'
import { App } from './App'

async function signIn(api: Api) {
  render(<App api={api} />)
  await userEvent.type(await screen.findByLabelText('User name'), 'chris')
  await userEvent.type(screen.getByLabelText('Password'), `${MOCK_PASSWORD}{Enter}`)
  return screen.findByRole('dialog', { name: 'Activity Monitor' })
}

describe('App', () => {
  it('signs in to a desktop with Activity Monitor open, and signs out', async () => {
    const api = createMockApi()
    await signIn(api)
    expect(screen.getByRole('navigation', { name: 'Dock' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Kura menu' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Sign Out chris' }))
    expect(await screen.findByLabelText('User name')).toBeInTheDocument()
  })

  it('opens apps from the dock, minimises and restores them, and closes from the menu', async () => {
    await signIn(createMockApi())
    const dock = screen.getByRole('navigation', { name: 'Dock' })
    await userEvent.click(within(dock).getByLabelText('Files'))
    const files = await screen.findByRole('dialog', { name: 'Files' })
    expect(within(files).getByText('Arrives in a coming update of Kura.')).toBeInTheDocument()
    await userEvent.click(within(files).getByLabelText('Minimize'))
    await userEvent.click(within(dock).getByLabelText('Files (minimised)'))
    expect(screen.getByRole('dialog', { name: 'Files' })).toBeVisible()
    await userEvent.click(screen.getByRole('button', { name: 'File' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Close Window' }))
    expect(screen.queryByRole('dialog', { name: 'Files' })).toBeNull()
  })

  it('finds a section with Ctrl K, and switches theme, saving prefs', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const api = createMockApi()
    const save = vi.spyOn(api, 'savePrefs')
    await signIn(api)
    await userEvent.keyboard('{Control>}k{/Control}')
    await userEvent.type(screen.getByRole('combobox', { name: 'Search' }), 'servi{Enter}')
    expect(screen.getByRole('button', { name: 'Services' })).toHaveAttribute('aria-current', 'page')
    await userEvent.click(screen.getByRole('button', { name: /Use (light|dark) theme/ }))
    await act(() => vi.advanceTimersByTimeAsync(500))
    expect(save).toHaveBeenCalledWith(expect.objectContaining({ theme: expect.stringMatching(/light|dark/) }))
    vi.useRealTimers()
  })

  it('tells the user when the layout cannot be saved', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const api = createMockApi()
    api.savePrefs = () => Promise.reject(new Error('down'))
    await signIn(api)
    await userEvent.click(screen.getByRole('button', { name: /Use (light|dark) theme/ }))
    await act(() => vi.advanceTimersByTimeAsync(500))
    expect(await screen.findByText(/could not be saved/)).toBeInTheDocument()
    vi.useRealTimers()
  })

  it('shows About Kura and the Zoom and View menus', async () => {
    await signIn(createMockApi())
    await userEvent.click(screen.getByRole('button', { name: 'Kura menu' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'About Kura' }))
    expect(await screen.findByText('Kura 0.6.0')).toBeInTheDocument()
    await userEvent.keyboard('{Escape}')
    await userEvent.click(await screen.findByRole('button', { name: 'View' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Network' }))
    expect(screen.getByRole('button', { name: 'Network' })).toHaveAttribute('aria-current', 'page')
    await userEvent.click(screen.getByRole('button', { name: 'Window' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Zoom' }))
    await userEvent.click(screen.getByRole('button', { name: 'Window' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Minimize' }))
    expect(await screen.findByLabelText('Activity Monitor (minimised)')).toBeInTheDocument()
    expect(screen.queryByRole('dialog', { name: 'Activity Monitor' })).toBeNull()
  })
})

describe('languages', () => {
  it('switches the desktop to French from the Kura menu, and saves the choice', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const api = createMockApi()
    const save = vi.spyOn(api, 'savePrefs')
    await signIn(api)
    await userEvent.click(screen.getByRole('button', { name: 'Kura menu' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Language…' }))
    await userEvent.click(await screen.findByRole('radio', { name: 'Français' }))
    await userEvent.click(screen.getByRole('button', { name: 'OK' }))
    expect(await screen.findByRole('dialog', { name: "Moniteur d'activité" })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Fichier' })).toBeInTheDocument()
    expect(screen.getByText('Résumé')).toBeInTheDocument()
    expect(document.documentElement.lang).toBe('fr')
    await act(() => vi.advanceTimersByTimeAsync(500))
    expect(save).toHaveBeenLastCalledWith(expect.objectContaining({ language: 'fr' }))
    vi.useRealTimers()
  })

  it('signs in in the browser’s language', async () => {
    const spy = vi.spyOn(navigator, 'languages', 'get').mockReturnValue(['fr-FR', 'en'])
    render(<App api={createMockApi()} />)
    expect(await screen.findByRole('button', { name: 'Se connecter' })).toBeInTheDocument()
    expect(screen.getByLabelText("Nom d'utilisateur")).toBeInTheDocument()
    spy.mockRestore()
  })
})
