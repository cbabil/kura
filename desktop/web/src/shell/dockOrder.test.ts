import { keepHidden, moveItem, normalizeDock, unpin, DEFAULT_DOCK } from './dockOrder'

describe('dock order', () => {
  it('moves an item before another', () => {
    expect(moveItem(['a', 'b', 'c', 'd'], 'd', 'b')).toEqual(['a', 'd', 'b', 'c'])
    expect(moveItem(['a', 'b', 'c'], 'a', 'c')).toEqual(['b', 'a', 'c'])
    expect(moveItem(['a', 'b'], 'a', 'a')).toEqual(['a', 'b'])
    expect(moveItem(['a', 'b'], 'x', 'a')).toEqual(['a', 'b'])
  })

  it('moves an item to the end when dropped on no item', () => {
    expect(moveItem(['a', 'b', 'c'], 'a', null)).toEqual(['b', 'c', 'a'])
  })

  it('unpins an app', () => {
    expect(unpin(['a', 'b'], 'a')).toEqual(['b'])
  })

  it('keeps known apps only, without duplicates, defaulting when empty', () => {
    const known = ['activity', 'files', 'terminal']
    expect(normalizeDock(['files', 'nope', 'files', 'activity'], known)).toEqual(['files', 'activity'])
    expect(normalizeDock(undefined, known)).toEqual(DEFAULT_DOCK.filter((a) => known.includes(a)))
    expect(normalizeDock(['trash', 'files'])).toEqual(['files'])
  })

  it('keeps the pins the dock could not show when it is reordered', () => {
    // the Browser is pinned but hidden (the server's facts not known yet)
    expect(keepHidden(['b', 'a'], ['a', 'browser', 'b'], ['a', 'b'])).toEqual(['b', 'a', 'browser'])
    // an app unpinned while shown stays unpinned
    expect(keepHidden(['a'], ['a', 'b'], ['a', 'b'])).toEqual(['a'])
    // nothing saved yet: the default dock's hidden apps are kept
    expect(keepHidden(['files'], undefined, ['files'])).toEqual(['files', ...DEFAULT_DOCK.filter((id) => id !== 'files')])
  })
})
