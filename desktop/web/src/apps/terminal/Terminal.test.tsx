import { act, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMockApi } from '../../api/mock'
import type { Api, TerminalHandlers } from '../../api'
import { renderWithTheme } from '../../test/render'
import { Terminal } from './Terminal'

/** What the fake xterm records; reset before each test. */
const xterm = vi.hoisted(() => ({
  terms: [] as { written: unknown[]; type(text: string): void; disposed: boolean; focused: boolean; options: { theme?: { background?: string } } }[],
  size: { cols: 100, rows: 30 },
}))

vi.mock('@xterm/xterm/css/xterm.css', () => ({}))
vi.mock('@xterm/xterm', () => ({
  Terminal: class {
    cols = 80
    rows = 24
    written: unknown[] = []
    disposed = false
    focused = false
    private typed: (text: string) => void = () => {}
    private resized: (size: { cols: number; rows: number }) => void = () => {}
    constructor(public options: { theme?: { background?: string } }) {
      xterm.terms.push(this)
    }
    loadAddon(addon: { term: unknown }) {
      addon.term = this
    }
    open() {}
    focus() {
      this.focused = true
    }
    write(data: unknown) {
      this.written.push(data)
    }
    onData(cb: (text: string) => void) {
      this.typed = cb
      return { dispose: () => {} }
    }
    onResize(cb: (size: { cols: number; rows: number }) => void) {
      this.resized = cb
      return { dispose: () => {} }
    }
    /** As xterm does: tells its listener only when the size really changes. */
    fitTo(size: { cols: number; rows: number }) {
      const changed = size.cols !== this.cols || size.rows !== this.rows
      Object.assign(this, size)
      if (changed) this.resized(size)
    }
    type(text: string) {
      this.typed(text)
    }
    dispose() {
      this.disposed = true
    }
  },
}))
vi.mock('@xterm/addon-fit', () => ({
  FitAddon: class {
    term: { fitTo(size: { cols: number; rows: number }): void } | null = null
    fit() {
      this.term!.fitTo(xterm.size)
    }
  },
}))

let resized: () => void = () => {}
class FakeObserver {
  constructor(cb: () => void) {
    resized = cb
  }
  observe() {}
  disconnect() {}
}

function setup() {
  const sessions: { handlers: TerminalHandlers; size: { cols: number; rows: number }; write: ReturnType<typeof vi.fn>; resize: ReturnType<typeof vi.fn>; close: ReturnType<typeof vi.fn> }[] = []
  const api: Api = {
    ...createMockApi(),
    terminal(size, handlers) {
      const session = { handlers, size, write: vi.fn(), resize: vi.fn(), close: vi.fn() }
      sessions.push(session)
      return session
    },
  }
  const view = renderWithTheme(<Terminal view="" setView={() => {}} compact={false} minimized={false} />, { api })
  return { sessions, view }
}

describe('Terminal', () => {
  beforeEach(() => {
    xterm.terms.length = 0
    xterm.size = { cols: 100, rows: 30 }
    vi.stubGlobal('ResizeObserver', FakeObserver)
    // jsdom lays nothing out; the terminal only fits a box that has a size
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(800)
    vi.spyOn(HTMLElement.prototype, 'clientHeight', 'get').mockReturnValue(400)
  })
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('opens a shell at the fitted size and relays both ways', async () => {
    const { sessions } = setup()
    expect(await screen.findByLabelText('Terminal')).toBeInTheDocument()
    expect(sessions).toHaveLength(1)
    expect(sessions[0].size).toEqual({ cols: 100, rows: 30 })
    const term = xterm.terms[0]
    act(() => sessions[0].handlers.onOpen())
    expect(term.focused).toBe(true)
    expect(sessions[0].resize).toHaveBeenCalledWith(100, 30)
    const bytes = new TextEncoder().encode('$ ')
    act(() => sessions[0].handlers.onData(bytes))
    expect(term.written).toEqual([bytes])
    term.type('ls\r')
    expect(sessions[0].write).toHaveBeenCalledWith('ls\r')
  })

  it('tells the shell when the window changes size, but not when it is hidden', async () => {
    const { sessions } = setup()
    await screen.findByLabelText('Terminal')
    sessions[0].resize.mockClear()
    act(() => resized())
    expect(sessions[0].resize).not.toHaveBeenCalled()
    xterm.size = { cols: 132, rows: 43 }
    act(() => resized())
    expect(sessions[0].resize).toHaveBeenCalledWith(132, 43)
    vi.spyOn(HTMLElement.prototype, 'clientWidth', 'get').mockReturnValue(0)
    xterm.size = { cols: 2, rows: 1 }
    act(() => resized())
    expect(sessions[0].resize).toHaveBeenCalledTimes(1)
  })

  it.each([
    ['exit', 'The shell has ended.'],
    ['lost', 'The connection to the shell was lost.'],
    ['refused', /The shell could not start/],
  ] as const)('says how the shell ended (%s) and starts a new one', async (reason, text) => {
    const { sessions } = setup()
    await screen.findByLabelText('Terminal')
    act(() => sessions[0].handlers.onEnd(reason))
    expect(screen.getByText(text)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'New Shell' }))
    expect(sessions).toHaveLength(2)
    expect(sessions[0].close).toHaveBeenCalled()
    expect(xterm.terms[0].disposed).toBe(true)
    expect(screen.queryByText(text)).toBeNull()
  })

  it('closes the shell with the window, and follows the theme without restarting', async () => {
    const { sessions, view } = setup()
    await screen.findByLabelText('Terminal')
    expect(xterm.terms[0].options.theme?.background).toBe('#111a2e')
    view.unmount()
    expect(sessions[0].close).toHaveBeenCalled()
    expect(xterm.terms[0].disposed).toBe(true)
  })

  it('speaks French', async () => {
    const api: Api = { ...createMockApi(), terminal: (_s, h) => (queueMicrotask(() => h.onEnd('exit')), { write() {}, resize() {}, close() {} }) }
    renderWithTheme(<Terminal view="" setView={() => {}} compact minimized={false} />, { api, lang: 'fr' })
    expect(await screen.findByText('Le shell est terminé.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Nouveau shell' })).toBeInTheDocument()
  })
})
