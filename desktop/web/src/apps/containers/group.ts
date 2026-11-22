/** How the Containers window arranges its list: compose stacks together, other containers on their own. */
import type { Container } from '../../api'

export interface Group {
  /** The compose project, or null for a container started alone. */
  project: string | null
  items: Container[]
}

/** Stacks keep the place of their first container; single containers keep theirs. */
export function groupContainers(list: Container[]): Group[] {
  const groups: Group[] = []
  const stacks = new Map<string, Group>()
  for (const c of list) {
    const stack = c.project ? stacks.get(c.project) : undefined
    if (stack) {
      stack.items.push(c)
      continue
    }
    const group = { project: c.project, items: [c] }
    if (c.project) stacks.set(c.project, group)
    groups.push(group)
  }
  return groups
}

/** True when the search text is in the container's name, image or stack. */
export function matches(c: Container, query: string): boolean {
  const q = query.trim().toLowerCase()
  return !q || [c.name, c.image, c.project ?? ''].some((text) => text.toLowerCase().includes(q))
}

/** States in which a container can be stopped or restarted; in any other it can be started. */
export const isUp = (c: Container) => ['running', 'restarting', 'paused'].includes(c.state)
