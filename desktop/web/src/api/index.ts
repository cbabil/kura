/**
 * The API the interface uses: the mock in development (VITE_MOCK=1), the real
 * server otherwise. The mock is tree-shaken out of production builds.
 */
import { httpApi } from './client'
import { createMockApi } from './mock'
import type { Api } from './types'

export const api: Api = import.meta.env.VITE_MOCK === '1' ? createMockApi() : httpApi
export type * from './types'
export { DAY_POINTS, DAY_STEP_MS, HOUR_POINTS } from './types'
