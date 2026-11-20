import { render, screen } from '@testing-library/react'
import { AppIcon, hueFor, ICONS } from './AppIcon'
import { Glyph } from './Glyph'

describe('AppIcon', () => {
  it('uses the drawn icon for built-in apps', () => {
    const { container } = render(<AppIcon app="activity" name="Activity Monitor" size={64} />)
    const img = container.querySelector('img')
    expect(img).toHaveAttribute('src', ICONS.activity)
    expect(img).toHaveAttribute('width', '64')
  })

  it('draws an initial on a stable colour for other apps', () => {
    render(<AppIcon app="immich" name="immich" size={64} />)
    expect(screen.getByText('I')).toBeInTheDocument()
    expect(hueFor('immich')).toBe(hueFor('immich'))
    expect(new Set(['immich', 'jellyfin', 'pihole', 'nextcloud', 'gitea'].map(hueFor)).size).toBeGreaterThan(1)
  })
})

describe('Glyph', () => {
  it('renders a stroked 24-unit icon', () => {
    const { container } = render(<Glyph name="search" size={20} />)
    const svg = container.querySelector('svg')
    expect(svg).toHaveAttribute('width', '20')
    expect(svg).toHaveAttribute('viewBox', '0 0 24 24')
  })
})
