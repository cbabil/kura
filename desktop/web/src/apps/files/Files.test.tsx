import { act, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ApiError, type Api } from '../../api'
import { createMockApi, MOCK_PASSWORD } from '../../api/mock'
import { CHRIS, renderWithTheme } from '../../test/render'
import { Files } from './Files'
import { Trash } from './Trash'

async function show(change: (api: Api) => Partial<Api> = () => ({}), lang: 'en' | 'fr' = 'en') {
  const mock = createMockApi()
  await mock.login(CHRIS.name, MOCK_PASSWORD)
  const api = { ...mock, ...change(mock) }
  renderWithTheme(<Files view="" setView={() => {}} compact={false} minimized={false} />, { api, lang })
  return api
}

const list = (path: string) => screen.findByRole('table', { name: `Files in ${path}` })
const rows = (table: HTMLElement) => within(table).getAllByRole('row').slice(1).map((r) => within(r).getAllByRole('cell')[0].textContent)
const row = (name: string) => screen.getByRole('row', { name: new RegExp(`^${name}`) })
const button = (name: string) => screen.getByRole('button', { name })

describe('Files', () => {
  it('shows the home folder, folders first, hidden files on request', async () => {
    await show()
    const table = await list('/home/chris')
    expect(rows(table)).toEqual(['Documents', 'Photos', 'backup.tar'])
    expect(within(row('backup.tar')).getByText(/^2(\.0)? KB$/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('checkbox', { name: 'Hidden files' }))
    expect(rows(table)).toEqual(['Documents', 'Photos', '.bashrc', 'backup.tar'])
    expect(screen.getByRole('navigation', { name: 'Places' })).toHaveTextContent('Home')
  })

  it('opens folders, goes back up and to the places', async () => {
    await show()
    await list('/home/chris')
    await userEvent.dblClick(row('Documents'))
    expect(rows(await list('/home/chris/Documents'))).toEqual(['notes.txt'])
    await userEvent.click(button('Enclosing Folder'))
    await list('/home/chris')
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Path' })).getByRole('button', { name: 'home' }))
    expect(rows(await list('/home'))).toEqual(['chris'])
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Places' })).getByText('Home'))
    await list('/home/chris')
  })

  it('makes a folder, renames, and says when a name is taken', async () => {
    const api = await show((mock) => ({ fileChange: vi.fn(mock.fileChange) }))
    await list('/home/chris')
    await userEvent.click(button('New Folder…'))
    const ask = screen.getByRole('dialog', { name: 'New folder' })
    await userEvent.type(within(ask).getByLabelText('Name'), 'Music')
    await userEvent.click(within(ask).getByRole('button', { name: 'Create' }))
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'make-dir', path: '/home/chris/Music' })
    await vi.waitFor(() => expect(row('Music')).toBeInTheDocument())

    await userEvent.click(row('Music'))
    await userEvent.click(button('Rename…'))
    const rename = screen.getByRole('dialog', { name: 'Rename “Music”' })
    const name = within(rename).getByLabelText('Name')
    expect(name).toHaveValue('Music')
    await userEvent.clear(name)
    await userEvent.type(name, 'Photos')
    await userEvent.click(within(rename).getByRole('button', { name: 'Rename' }))
    expect(await screen.findByText('Something with that name is already there.')).toBeInTheDocument()
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'rename', from: '/home/chris/Music', to: '/home/chris/Photos' })
  })

  it('copies and moves by pasting in another folder', async () => {
    const api = await show((mock) => ({ fileChange: vi.fn(mock.fileChange) }))
    await list('/home/chris')
    await userEvent.click(row('backup.tar'))
    await userEvent.click(button('Copy'))
    await userEvent.dblClick(row('Documents'))
    await list('/home/chris/Documents')
    await userEvent.click(button('Paste “backup.tar” Here'))
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'copy', from: '/home/chris/backup.tar', to: '/home/chris/Documents/backup.tar' })
    await vi.waitFor(() => expect(row('backup.tar')).toBeInTheDocument())

    await userEvent.click(row('notes.txt'))
    await userEvent.click(button('Move'))
    await userEvent.click(button('Enclosing Folder'))
    await list('/home/chris')
    await userEvent.click(button('Paste “notes.txt” Here'))
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'rename', from: '/home/chris/Documents/notes.txt', to: '/home/chris/notes.txt' })
    await vi.waitFor(() => expect(row('notes.txt')).toBeInTheDocument())
    expect(screen.queryByRole('button', { name: /Paste/ })).toBeNull()
  })

  it('moves to the Trash, puts back, and empties after asking', async () => {
    await show()
    await list('/home/chris')
    await userEvent.click(row('backup.tar'))
    await userEvent.click(button('Move to Trash'))
    await vi.waitFor(() => expect(screen.queryByRole('row', { name: /^backup.tar/ })).toBeNull())
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Places' })).getByText('Trash'))
    const trash = await screen.findByRole('table', { name: 'Trash' })
    expect(within(trash).getByRole('row', { name: /backup.tar/ })).toHaveTextContent('/home/chris')
    await userEvent.click(screen.getByRole('button', { name: 'Put back backup.tar' }))
    expect(await screen.findByText('The Trash is empty.')).toBeInTheDocument()
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Places' })).getByText('Home'))
    await list('/home/chris')
    expect(row('backup.tar')).toBeInTheDocument()

    await userEvent.click(row('backup.tar'))
    await userEvent.click(button('Move to Trash'))
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Places' })).getByText('Trash'))
    await userEvent.click(await screen.findByRole('button', { name: 'Empty Trash…' }))
    const sure = screen.getByRole('dialog', { name: 'Empty the Trash?' })
    await userEvent.click(within(sure).getByRole('button', { name: 'Empty Trash' }))
    expect(await screen.findByText('The Trash is empty.')).toBeInTheDocument()
  })

  it('asks before deleting what the Trash cannot keep', async () => {
    const api = await show((mock) => ({ fileChange: vi.fn(mock.fileChange) }))
    await list('/home/chris')
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Path' })).getByRole('button', { name: 'home' }))
    await list('/home')
    await userEvent.click(row('chris'))
    await userEvent.click(button('Move to Trash'))
    const sure = await screen.findByRole('dialog', { name: 'Delete “chris” for good?' })
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'trash', path: '/home/chris' })
    await userEvent.click(within(sure).getByRole('button', { name: 'Delete' }))
    expect(api.fileChange).toHaveBeenLastCalledWith({ op: 'delete', path: '/home/chris' })
    expect(await screen.findByText('This folder is empty.')).toBeInTheDocument()
  })

  it('uploads, offers downloads, and previews text and pictures', async () => {
    const api = await show((mock) => ({ upload: vi.fn(mock.upload) }))
    await list('/home/chris')
    const picked = [new File(['one'], 'one.txt', { type: 'text/plain' }), new File(['two'], 'two.txt', { type: 'text/plain' })]
    await userEvent.upload(screen.getByLabelText('Files to upload'), picked)
    await vi.waitFor(() => expect(row('two.txt')).toBeInTheDocument())
    expect(api.upload).toHaveBeenCalledWith('/home/chris/one.txt', picked[0])

    await userEvent.click(row('backup.tar'))
    expect(screen.getByRole('link', { name: 'Download' })).toHaveAttribute('download', 'backup.tar')
    await userEvent.dblClick(row('one.txt'))
    const text = await screen.findByRole('dialog', { name: 'one.txt' })
    expect(await within(text).findByText('one')).toBeInTheDocument()
    await userEvent.click(within(text).getByRole('button', { name: 'Close' }))
    await userEvent.dblClick(row('Photos'))
    await list('/home/chris/Photos')
    await userEvent.dblClick(row('attic.png'))
    const picture = await screen.findByRole('dialog', { name: 'attic.png' })
    expect(within(picture).getByRole('img', { name: 'attic.png' })).toHaveAttribute('src', expect.stringMatching(/^data:image\/png/))
  })

  it('works from the keyboard, and keeps the folder on screen when one reading fails', async () => {
    let fail = false
    await show((mock) => ({ files: (path) => (fail ? Promise.reject(new ApiError('busy')) : mock.files(path)) }))
    await list('/home/chris')
    act(() => row('Photos').focus())
    expect(row('Photos')).toHaveAttribute('aria-selected', 'true')
    expect(button('Rename…')).toBeInTheDocument()
    // The next reading fails: what was read before stays.
    fail = true
    await userEvent.click(button('New Folder…'))
    await userEvent.type(screen.getByLabelText('Name'), 'Music')
    await userEvent.click(screen.getByRole('button', { name: 'Create' }))
    await vi.waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
    expect(row('Photos')).toBeInTheDocument()
    expect(screen.queryByText('The server could not read the folder.')).toBeNull()
    fail = false
    act(() => row('Photos').focus())
    await userEvent.keyboard('{Enter}')
    await list('/home/chris/Photos')
  })

  it('tells people without a shell that Files is not for their account', async () => {
    await show(() => ({ files: () => Promise.reject(new ApiError('no_shell')) }))
    expect(await screen.findByText('Files needs an account with a login shell.')).toBeInTheDocument()
  })

  it('says why a folder cannot be shown, and speaks French', async () => {
    await show(() => ({ files: () => Promise.reject(new ApiError('denied')) }), 'fr')
    expect(await screen.findByText("Vous n'avez pas le droit d'ouvrir ce dossier.")).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Emplacements' })).toHaveTextContent('Corbeille')
  })
})

describe('Trash', () => {
  it('is the Trash of Files in a window of its own', async () => {
    const api = createMockApi()
    await api.login(CHRIS.name, MOCK_PASSWORD)
    await api.fileChange({ op: 'trash', path: '/home/chris/backup.tar' })
    renderWithTheme(<Trash view="" setView={() => {}} compact={false} minimized={false} />, { api })
    expect(await screen.findByRole('button', { name: 'Put back backup.tar' })).toBeInTheDocument()
    const failing = { ...api, trash: () => Promise.reject(new ApiError('unavailable')) }
    renderWithTheme(<Trash view="" setView={() => {}} compact={false} minimized={false} />, { api: failing })
    expect(await screen.findByText('The server could not read the Trash.')).toBeInTheDocument()
  })
})
