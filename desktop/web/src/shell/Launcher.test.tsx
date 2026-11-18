import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../test/render'
import { launcherEntries } from '../apps/registry'
import { makeI18n } from '../i18n'
import { Launcher } from './Launcher'

const LAUNCHER_ENTRIES = launcherEntries(makeI18n('en').t)

function setup() {
  const onChoose = vi.fn()
  const onClose = vi.fn()
  renderWithTheme(<Launcher entries={LAUNCHER_ENTRIES} onChoose={onChoose} onClose={onClose} />)
  return { onChoose, onClose, input: screen.getByRole('combobox', { name: 'Search' }) }
}

describe('Launcher', () => {
  it('lists apps first, then narrows as you type', async () => {
    const { input } = setup()
    expect(screen.getAllByRole('option')[0]).toHaveTextContent('Activity Monitor')
    await userEvent.type(input, 'memo')
    expect(screen.getAllByRole('option')[0]).toHaveTextContent('Memory')
    // the section heading, and the app itself (its blurb mentions memory)
    expect(screen.getAllByText('Activity Monitor')).toHaveLength(2)
  })

  it('moves with arrows and opens with Enter', async () => {
    const { input, onChoose } = setup()
    await userEvent.type(input, '{ArrowDown}{ArrowDown}{ArrowUp}{Enter}')
    expect(onChoose).toHaveBeenCalledWith(expect.objectContaining({ app: 'containers' }))
  })

  it('wraps around and opens on click', async () => {
    const { input, onChoose } = setup()
    await userEvent.type(input, '{ArrowUp}')
    expect(screen.getAllByRole('option').at(-1)).toHaveAttribute('aria-selected', 'true')
    await userEvent.click(screen.getByText('Terminal'))
    expect(onChoose).toHaveBeenCalledWith(expect.objectContaining({ app: 'terminal' }))
  })

  it('says when nothing matches, and closes with Escape or a click outside', async () => {
    const { input, onClose } = setup()
    await userEvent.type(input, 'zzzz')
    expect(screen.getByText(/Nothing matches/)).toBeInTheDocument()
    await userEvent.type(input, '{Enter}{Escape}')
    expect(onClose).toHaveBeenCalledTimes(1)
    await userEvent.click(document.querySelector('.MuiBackdrop-root') as HTMLElement)
    expect(onClose).toHaveBeenCalledTimes(2)
  })
})
