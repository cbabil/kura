import { bytes, rate, percent, since, unitName } from './format'

describe('format', () => {
  it('formats sizes in binary units with sensible precision', () => {
    expect(bytes(0)).toBe('0 B')
    expect(bytes(512)).toBe('512 B')
    expect(bytes(1536)).toBe('1.5 KB')
    expect(bytes(28 * 1024 ** 2)).toBe('28 MB')
    expect(bytes(5.8 * 1024 ** 3)).toBe('5.8 GB')
    expect(bytes(256 * 1024 ** 3)).toBe('256 GB')
    expect(bytes(2.5 * 1024 ** 4)).toBe('2.5 TB')
    expect(bytes(null)).toBe('—')
  })

  it('formats rates and percentages', () => {
    expect(rate(4.2 * 1024 ** 2)).toBe('4.2 MB/s')
    expect(percent(18.44)).toBe('18%')
    expect(percent(6.43, 1)).toBe('6.4%')
  })

  it('says how long ago, in the largest whole unit', () => {
    const now = 1_000_000_000_000
    expect(since(now - 30e3, now)).toBe('30 s')
    expect(since(now - 5 * 60e3, now)).toBe('5 min')
    expect(since(now - 2 * 3600e3, now)).toBe('2 h')
    expect(since(now - 3 * 86400e3, now)).toBe('3 d')
    expect(since(null, now)).toBe('—')
  })

  it('drops the .service suffix', () => {
    expect(unitName('docker.service')).toBe('docker')
    expect(unitName('foo.timer')).toBe('foo.timer')
  })
})
