/**
 * The mock API's files (see mock.ts): a small home folder kept in memory,
 * with the server's answers for what exists, what is missing and the trash.
 */
import { baseName, parentOf } from './paths'
import { ApiError, type Api, type FileChange, type FileEntry, type Trashed } from './types'

type Part = Pick<Api, 'files' | 'fileChange' | 'trash' | 'fileUrl' | 'fileText' | 'upload'>

interface Node {
  /** null for a folder. */
  text: string | null
  modified: number
}

const HOME = '/home/chris'
/** A 1x1 picture, for previews. */
const PIXEL = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
const VALID = /^\/(?:[^/\0]+(?:\/[^/\0]+)*)?$/

export function createMockFiles(): Part {
  const now = Math.floor(Date.now() / 1000)
  const tree = new Map<string, Node>([
    ['/', { text: null, modified: now }],
    ['/home', { text: null, modified: now }],
    [HOME, { text: null, modified: now }],
    [`${HOME}/Documents`, { text: null, modified: now - 86_400 }],
    [`${HOME}/Documents/notes.txt`, { text: 'Buy a second disk.\n', modified: now - 3600 }],
    [`${HOME}/Photos`, { text: null, modified: now - 7 * 86_400 }],
    [`${HOME}/Photos/attic.png`, { text: PIXEL, modified: now - 7 * 86_400 }],
    [`${HOME}/.bashrc`, { text: '# shell settings\n', modified: now - 30 * 86_400 }],
    [`${HOME}/backup.tar`, { text: 'x'.repeat(2048), modified: now - 120 }],
    ['/srv', { text: null, modified: now }],
  ])
  let trash: (Trashed & { nodes: [string, Node][] })[] = []

  const need = (path: string, ok = VALID.test(path) && !path.split('/').some((p) => p === '.' || p === '..')) => {
    if (!ok) throw new ApiError('bad_request')
  }
  const under = (path: string) => [...tree.entries()].filter(([p]) => p === path || p.startsWith(`${path}/`))
  const mustExist = (path: string) => {
    need(path)
    if (!tree.has(path)) throw new ApiError('not_found')
  }
  const mustBeFree = (path: string) => {
    need(path)
    if (tree.has(path)) throw new ApiError('exists')
    if (tree.get(parentOf(path))?.text !== null) throw new ApiError('not_found')
  }
  const move = (from: string, to: string, keep: boolean) => {
    mustExist(from)
    mustBeFree(to)
    if (to.startsWith(`${from}/`)) throw new ApiError('bad_request')
    for (const [p, node] of under(from)) {
      tree.set(to + p.slice(from.length), { ...node })
      if (!keep) tree.delete(p)
    }
  }
  const change = (c: FileChange) => {
    switch (c.op) {
      case 'make-dir': mustBeFree(c.path); tree.set(c.path, { text: null, modified: Math.floor(Date.now() / 1000) }); break
      case 'rename': move(c.from, c.to, false); break
      case 'copy': move(c.from, c.to, true); break
      case 'delete': mustExist(c.path); under(c.path).forEach(([p]) => tree.delete(p)); break
      case 'trash': {
        mustExist(c.path)
        // Like the server: the trash is on the home's volume only.
        if (!c.path.startsWith(`${HOME}/`)) throw new ApiError('other_volume')
        const nodes = under(c.path)
        const node = tree.get(c.path)!
        let name = baseName(c.path)
        for (let n = 2; trash.some((t) => t.name === name); n++) name = `${baseName(c.path)}.${n}`
        trash = [{ name, path: c.path, dir: node.text === null, size: node.text?.length ?? 0, deleted: Math.floor(Date.now() / 1000), nodes }, ...trash]
        nodes.forEach(([p]) => tree.delete(p))
        break
      }
      case 'restore': {
        const item = trash.find((t) => t.name === c.name)
        if (!item) throw new ApiError('not_found')
        mustBeFree(item.path)
        item.nodes.forEach(([p, node]) => tree.set(p, node))
        trash = trash.filter((t) => t !== item)
        break
      }
      case 'empty-trash': trash = []; break
    }
  }
  const entries = (path: string): FileEntry[] =>
    [...tree.entries()].filter(([p]) => p !== '/' && parentOf(p) === path).map(([p, node]) => (
      { name: baseName(p), dir: node.text === null, link: false, size: node.text?.length ?? 0, modified: node.modified }
    ))
  const file = (path: string) => {
    mustExist(path)
    const text = tree.get(path)!.text
    if (text === null) throw new ApiError('bad_request')
    return text
  }

  return {
    async files(path = HOME) {
      mustExist(path)
      if (tree.get(path)!.text !== null) throw new ApiError('bad_request')
      return { path, home: HOME, entries: entries(path), truncated: false }
    },
    async fileChange(c) {
      change(c)
    },
    trash: async () => trash.map(({ name, path, dir, size, deleted }) => ({ name, path, dir, size, deleted })),
    fileUrl: (path, inline) => {
      const text = tree.get(path)?.text ?? ''
      if (inline && path.endsWith('.png')) return `data:image/png;base64,${text}`
      return `data:application/octet-stream,${encodeURIComponent(text)}`
    },
    fileText: async (path) => file(path),
    async upload(path, data) {
      mustBeFree(path)
      tree.set(path, { text: await data.text(), modified: Math.floor(Date.now() / 1000) })
    },
  }
}
