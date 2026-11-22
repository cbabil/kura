import type { Container } from '../../api'
import { groupContainers, isUp, matches } from './group'

const c = (name: string, project: string | null = null, state = 'running'): Container => ({
  id: name, name, image: `img/${name}:1`, state, status: '', created: 0, project, service: null, ports: [],
})

describe('container groups', () => {
  it('keeps stacks together where their first container is', () => {
    const groups = groupContainers([c('a'), c('s1', 'stack'), c('b'), c('s2', 'stack'), c('t1', 'other')])
    expect(groups.map((g) => [g.project, g.items.map((i) => i.name)])).toEqual([
      [null, ['a']], ['stack', ['s1', 's2']], [null, ['b']], ['other', ['t1']],
    ])
    expect(groupContainers([])).toEqual([])
  })

  it('matches name, image or stack, ignoring case', () => {
    const web = c('web', 'Shop')
    for (const q of ['', '  ', 'WEB', 'img/', 'shop']) expect(matches(web, q)).toBe(true)
    expect(matches(web, 'db')).toBe(false)
    expect(matches(c('solo'), 'shop')).toBe(false)
  })

  it('knows which containers are up', () => {
    expect(['running', 'restarting', 'paused', 'exited', 'created', 'dead'].map((s) => isUp(c('x', null, s)))).toEqual([true, true, true, false, false, false])
  })
})
