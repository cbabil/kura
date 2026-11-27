import { screen } from '@testing-library/react'
import type { SystemInfo } from '../api'
import { renderWithTheme } from '../test/render'
import { About, Wallpaper } from './Panels'

const system = (version: string): SystemInfo => ({
  hostname: 'adminworks', os: 'Kura 0.7.0', kernel: '6.12', arch: 'x86_64', cores: 4, memTotal: 8 * 1024 ** 3,
  uptime: 1, browser: false, version,
})

describe('the running version', () => {
  it('sits under the server’s name in the corner, once known', () => {
    const { rerender } = renderWithTheme(<Wallpaper hostname="adminworks" version="0.8.1" />)
    expect(screen.getByText('adminworks.local')).toBeInTheDocument()
    expect(screen.getByText('Kura 0.8.1')).toBeInTheDocument()
    rerender(<Wallpaper hostname="adminworks" version="" />)
    expect(screen.queryByText(/^Kura \d/)).not.toBeInTheDocument()
  })

  it('in About is the installed one, not the image’s', () => {
    renderWithTheme(<About open system={system('0.8.1')} onClose={() => {}} />)
    expect(screen.getByText('Kura 0.8.1')).toBeInTheDocument()
    expect(screen.queryByText('Kura 0.7.0')).not.toBeInTheDocument()
  })

  it('in About falls back to the system’s name when the version is unknown', () => {
    renderWithTheme(<About open system={system('')} onClose={() => {}} />)
    expect(screen.getByText('Kura 0.7.0')).toBeInTheDocument()
  })
})
