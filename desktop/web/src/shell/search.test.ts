import { rankEntries, type Entry } from './search'

const e = (id: string, title: string, subtitle = '', section: Entry['section'] = 'Apps'): Entry => ({
  id, title, subtitle, section, app: 'activity',
})

const entries = [
  e('a', 'Activity Monitor', 'CPU, memory, storage, network'),
  e('c', 'Containers', 'Docker apps and compose stacks'),
  e('t', 'Terminal', 'A shell in a window'),
  e('m', 'Memory', 'Activity Monitor section', 'Activity Monitor'),
  e('s', 'Settings', 'Network, users, time'),
]

describe('rankEntries', () => {
  it('lists apps when the query is empty', () => {
    expect(rankEntries(entries, '  ').map((x) => x.id)).toEqual(['a', 'c', 't', 's'])
  })

  it('ranks a title prefix above a word prefix above a substring above the subtitle', () => {
    expect(rankEntries(entries, 'mon').map((x) => x.id)).toEqual(['a', 'm'])
    expect(rankEntries(entries, 'me').map((x) => x.id)).toEqual(['m', 'a', 's'])
    expect(rankEntries(entries, 'net').map((x) => x.id)).toEqual(['a', 's'])
    expect(rankEntries(entries, 'TER').map((x) => x.id)).toEqual(['t'])
    expect(rankEntries(entries, 'ain').map((x) => x.id)).toEqual(['c'])
  })

  it('matches every word of the query', () => {
    expect(rankEntries(entries, 'activity cpu').map((x) => x.id)).toEqual(['a'])
    expect(rankEntries(entries, 'zzz')).toEqual([])
  })

  it('returns at most the limit', () => {
    expect(rankEntries(entries, 'e', 2)).toHaveLength(2)
  })
})
