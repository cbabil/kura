import { keepHidden, normalizeDock, placeAt, slotAt, unpin, DEFAULT_DOCK } from './dockOrder'

describe('dock order', () => {
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

  it('finds the slot under the pointer from the other icons’ centres', () => {
    const centres = [32, 98, 164]
    expect([slotAt(centres, 0), slotAt(centres, 40), slotAt(centres, 120), slotAt(centres, 500)]).toEqual([0, 1, 2, 3])
    expect(slotAt([], 10)).toBe(0)
  })

  it('places an app at a slot, whether it was pinned or not', () => {
    expect(placeAt(['a', 'b', 'c'], 'c', 0)).toEqual(['c', 'a', 'b'])
    expect(placeAt(['a', 'b', 'c'], 'a', 2)).toEqual(['b', 'c', 'a'])
    expect(placeAt(['a', 'b'], 'x', 1)).toEqual(['a', 'x', 'b'])
    // a slot past the end is the end
    expect(placeAt(['a', 'b'], 'x', 9)).toEqual(['a', 'b', 'x'])
  })
})
