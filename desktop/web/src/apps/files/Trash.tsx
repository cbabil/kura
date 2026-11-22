/** The Trash from the dock: the same Trash Files shows, in a window of its own. */
import type { AppProps } from '../types'
import { useAwake } from '../usePolled'
import { TrashView } from './TrashView'

export function Trash({ minimized }: AppProps) {
  return <TrashView awake={useAwake(minimized)} />
}
