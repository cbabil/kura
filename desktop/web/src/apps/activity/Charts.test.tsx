import { render, screen } from '@testing-library/react'
import { AreaChart, downsample, MAX_POINTS } from './Charts'

describe('downsample', () => {
  it('leaves short series alone', () => {
    expect(downsample([1, 2, 3], 5)).toEqual([1, 2, 3])
  })

  it('averages long series into buckets', () => {
    expect(downsample([1, 3, 5, 7], 2)).toEqual([2, 6])
    expect(downsample(Array.from({ length: 1800 }, (_, i) => i))).toHaveLength(MAX_POINTS)
  })
})

describe('AreaChart', () => {
  it('draws one filled line per series, skipping empty ones', () => {
    const { container } = render(
      <AreaChart label="CPU history" height={40} series={[
        { label: 'a', color: '#000', values: [1, 2, 3] },
        { label: 'b', color: '#fff', values: [] },
        { label: 'c', color: '#f00', values: [5] },
      ]} />,
    )
    expect(screen.getByRole('img', { name: 'CPU history' })).toBeInTheDocument()
    expect(container.querySelectorAll('g')).toHaveLength(2)
  })
})
