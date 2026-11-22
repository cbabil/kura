/**
 * The mock API's App Catalog (see mock.ts): the six apps Kura ships, Gitea
 * installed in an older version, and jobs that are done as soon as asked.
 */
import { ApiError, type Api, type AppChange, type Catalog, type CatalogApp, type User } from './types'

type Part = Pick<Api, 'catalog' | 'changeApp'>

const app = (id: string, name: string, version: string, port: number, fixedPorts: number[] = []): CatalogApp => (
  { id, name, version, port, fixedPorts, shared: [], homepage: `https://example.org/${id}`, installed: null }
)

export function createMockCatalog(currentUser: () => User | null): Part {
  const state: Catalog = {
    apps: [
      app('adguard-home', 'AdGuard Home', '0.107.56', 3000, [53]),
      { ...app('gitea', 'Gitea', '1.23.1', 3003), installed: { port: 3003, version: '1.22.0' } },
      app('home-assistant', 'Home Assistant', '2025.1.4', 8123),
      app('jellyfin', 'Jellyfin', '10.10.7', 8096),
      app('syncthing', 'Syncthing', '1.29.2', 8384, [22000, 21027]),
      app('uptime-kuma', 'Uptime Kuma', '1.23.16', 3001),
    ],
    job: null,
  }
  const admin = () => {
    if (!currentUser()?.admin) throw new ApiError('admin')
  }
  const apply = (change: AppChange) => {
    const found = state.apps.find((a) => a.id === change.id)
    const taken = (port: number) => state.apps.some((a) => a.installed?.port === port)
    const ok =
      found !== undefined &&
      (change.what === 'install'
        ? !found.installed && Number.isInteger(change.port) && change.port >= 1024 && change.port <= 65535 && !taken(change.port)
        : found.installed !== null)
    if (!ok) throw new ApiError('bad_request')
    if (change.what === 'install') found.installed = { port: change.port, version: found.version }
    else if (change.what === 'update') found.installed = { port: found.installed!.port, version: found.version }
    else found.installed = null
    state.job = { state: 'done', output: [`kura-apps ${change.what} ${change.id}`, 'Done.'] }
  }
  return {
    async catalog() {
      admin()
      return structuredClone(state)
    },
    async changeApp(change) {
      admin()
      apply(change)
    },
  }
}
