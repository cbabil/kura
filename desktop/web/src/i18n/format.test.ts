import { makeFormat } from './format'

const en = makeFormat('en', ['B', 'KB', 'MB', 'GB', 'TB', 'PB'])
const fr = makeFormat('fr', ['o', 'Ko', 'Mo', 'Go', 'To', 'Po'])

describe('format', () => {
  it('formats sizes in binary units with sensible precision', () => {
    expect(en.bytes(0)).toBe('0 B')
    expect(en.bytes(512)).toBe('512 B')
    expect(en.bytes(1536)).toBe('1.5 KB')
    expect(en.bytes(28 * 1024 ** 2)).toBe('28 MB')
    expect(en.bytes(5.8 * 1024 ** 3)).toBe('5.8 GB')
    expect(en.bytes(256 * 1024 ** 3)).toBe('256 GB')
    expect(en.bytes(2.5 * 1024 ** 4)).toBe('2.5 TB')
    expect(en.bytes(null)).toBe('—')
  })

  it('uses the language’s decimal mark and unit names', () => {
    expect(fr.bytes(5.8 * 1024 ** 3)).toBe('5,8 Go')
    expect(fr.bytes(512)).toBe('512 o')
    expect(fr.rate(4.2 * 1024 ** 2)).toBe('4,2 Mo/s')
    // French keeps no-break spaces: U+00A0 before %, U+202F before a duration's unit
    expect(fr.percent(6.43, 1)).toBe('6,4 %')
  })

  it('formats rates and percentages', () => {
    expect(en.rate(4.2 * 1024 ** 2)).toBe('4.2 MB/s')
    expect(en.percent(18.44)).toBe('18%')
    expect(en.percent(6.43, 1)).toBe('6.4%')
  })

  it('says how long ago, in the largest whole unit', () => {
    const now = 1_000_000_000_000
    expect(en.since(now - 30e3, now)).toBe('30 sec')
    expect(en.since(now - 5 * 60e3, now)).toBe('5 min')
    expect(en.since(now - 2 * 3600e3, now)).toBe('2 hr')
    expect(en.since(now - 3 * 86400e3, now)).toBe('3 days')
    expect(fr.since(now - 3 * 86400e3, now)).toBe('3 j')
    expect(en.since(null, now)).toBe('—')
  })

  it('writes dates and times the language’s way', () => {
    const d = new Date(2026, 10, 17, 9, 41)
    expect(en.date(d)).toBe('Tue, Nov 17')
    expect(fr.date(d)).toBe('mar. 17 nov.')
    expect(fr.time(d)).toBe('09:41')
    expect(en.clock(new Date(2026, 10, 17, 21, 5, 9))).toBe('21:05:09')
  })
})
