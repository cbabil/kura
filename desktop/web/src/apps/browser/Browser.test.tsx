import { act, fireEvent, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMockApi } from '../../api/mock'
import type { Api } from '../../api'
import { renderWithTheme } from '../../test/render'
import { Browser } from './Browser'
import type { AppCommand } from '../types'

/** What the fake noVNC records; reset before each test. */
const novnc = vi.hoisted(() => ({
  views: [] as {
    channel: unknown
    shared?: boolean
    resizeSession: boolean
    focusOnClick: boolean
    pasted: string[]
    keys: string[]
    disconnected: boolean
    focused: number
    emit(type: string, detail?: unknown): void
  }[],
}))

vi.mock('@novnc/novnc', () => ({
  default: class extends EventTarget {
    resizeSession = false
    focusOnClick = false
    background = ''
    pasted: string[] = []
    keys: string[] = []
    disconnected = false
    focused = 0
    shared?: boolean
    constructor(public target: HTMLElement, public channel: unknown, options?: { shared?: boolean }) {
      super()
      this.shared = options?.shared
      novnc.views.push(this)
    }
    focus() {
      this.focused++
    }
    clipboardPasteFrom(text: string) {
      this.pasted.push(text)
    }
    sendKey(_keysym: number, code: string, down?: boolean) {
      this.keys.push(`${code}${down === undefined ? '' : down ? '↓' : '↑'}`)
    }
    disconnect() {
      this.disconnected = true
      this.emit('disconnect', { clean: true })
    }
    emit(type: string, detail?: unknown) {
      this.dispatchEvent(new CustomEvent(type, { detail }))
    }
  },
}))

function setup() {
  const channels: object[] = []
  const browserStop = vi.fn(() => Promise.resolve())
  const api: Api = {
    ...createMockApi(),
    browserStop,
    browser() {
      const channel = { id: channels.length }
      channels.push(channel)
      return channel as unknown as ReturnType<Api['browser']>
    },
  }
  const ui = (command: AppCommand | null) => <Browser view="" setView={() => {}} compact={false} minimized={false} command={command} />
  const view = renderWithTheme(ui(null), { api })
  /** Sends the window a command, as its menus do. */
  const send = (name: string, seq: number) => view.rerender(ui({ name, seq }))
  return { channels, view, send, browserStop }
}

const clipboard = { writeText: vi.fn(() => Promise.resolve()), readText: vi.fn(() => Promise.resolve('')) }

describe('Browser', () => {
  beforeEach(() => {
    novnc.views.length = 0
    clipboard.writeText.mockClear()
    clipboard.readText.mockReset().mockResolvedValue('')
    Object.defineProperty(navigator, 'clipboard', { value: clipboard, configurable: true })
  })

  it('shows the browser at the window’s size, sharing it with one’s other windows, and focuses it once connected', async () => {
    const { channels } = setup()
    expect(await screen.findByRole('application', { name: 'The server’s browser' })).toBeInTheDocument()
    const view = novnc.views[0]
    expect(view.channel).toBe(channels[0])
    expect([view.shared, view.resizeSession, view.focusOnClick]).toEqual([true, true, true])
    act(() => view.emit('connect'))
    expect(view.focused).toBe(1)
  })

  it('passes the clipboard both ways, but reads this one only on a paste', async () => {
    setup()
    const screenBox = await screen.findByRole('application')
    const view = novnc.views[0]
    act(() => view.emit('clipboard', { text: 'from the server' }))
    expect(clipboard.writeText).toHaveBeenCalledWith('from the server')
    // a click is not a paste: nothing is read
    fireEvent.focusIn(screenBox)
    fireEvent.mouseDown(screenBox)
    expect(clipboard.readText).not.toHaveBeenCalled()
    // Ctrl+V hands over what was copied here, then pastes it there
    clipboard.readText.mockResolvedValue('from here')
    await act(async () => fireEvent.keyDown(screenBox, { key: 'v', ctrlKey: true }))
    expect(view.pasted).toEqual(['from here'])
    expect(view.keys).toEqual(['ControlLeft↓', 'KeyV', 'ControlLeft↑'])
    // ⌘+V: the same, with ⌘ let go there first; the same text is not sent twice
    view.keys.length = 0
    await act(async () => fireEvent.keyDown(screenBox, { key: 'V', metaKey: true }))
    expect(view.pasted).toEqual(['from here'])
    expect(view.keys).toEqual(['MetaLeft↑', 'ControlLeft↓', 'KeyV', 'ControlLeft↑'])
    // the server's own copy is not overwritten by an older one here
    clipboard.readText.mockResolvedValue('from the server')
    act(() => view.emit('clipboard', { text: 'from the server' }))
    await act(async () => fireEvent.keyDown(screenBox, { key: 'v', ctrlKey: true }))
    expect(view.pasted).toEqual(['from here'])
    // a browser that will not share its clipboard still pastes the server's
    view.keys.length = 0
    clipboard.readText.mockRejectedValue(new Error('denied'))
    await act(async () => fireEvent.keyDown(screenBox, { key: 'v', ctrlKey: true }))
    expect(view.keys).toEqual(['ControlLeft↓', 'KeyV', 'ControlLeft↑'])
    // other keys are left to noVNC
    view.keys.length = 0
    fireEvent.keyDown(screenBox, { key: 'c', ctrlKey: true })
    fireEvent.keyDown(screenBox, { key: 'v' })
    expect(view.keys).toEqual([])
  })

  it('pastes text typed in a dialog, for browsers that keep their clipboard', async () => {
    const { send } = setup()
    await screen.findByRole('application')
    send('paste', 1)
    const dialog = await screen.findByRole('dialog', { name: 'Paste Text' })
    expect(dialog).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Text for the browser’s clipboard'), 'a password')
    await userEvent.click(screen.getByRole('button', { name: 'Paste' }))
    expect(novnc.views[0].pasted).toEqual(['a password'])
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it.each([
    [true, 'The browser was closed, or nobody had watched it for a while.'],
    [false, /The browser could not start/],
  ] as const)('says how the view ended (connected first: %s) and opens it again', async (connected, text) => {
    const { channels } = setup()
    await screen.findByRole('application')
    const first = novnc.views[0]
    act(() => {
      if (connected) first.emit('connect')
      first.emit('disconnect', { clean: false })
    })
    expect(screen.getByRole('status')).toHaveTextContent(text)
    await userEvent.click(screen.getByRole('button', { name: 'Open Browser' }))
    expect(await screen.findByRole('application')).toBeInTheDocument()
    expect(channels).toHaveLength(2)
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('quits one’s own browser from its menu, once per command', async () => {
    const { send, browserStop } = setup()
    await screen.findByRole('application')
    send('quit', 1)
    send('quit', 1) // the same command again is not a new one
    expect(browserStop).toHaveBeenCalledTimes(1)
    send('quit', 2)
    expect(browserStop).toHaveBeenCalledTimes(2)
  })

  it('leaves the browser running when the window closes, and says nothing', async () => {
    const { view } = setup()
    await screen.findByRole('application')
    view.unmount()
    expect(novnc.views[0].disconnected).toBe(true)
  })
})
