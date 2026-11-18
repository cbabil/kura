/**
 * Playwright end-to-end tests. They run against `vite preview` of a mock build
 * (VITE_MOCK=1), so they need no device; the CI boot test covers the real server.
 */
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL: 'http://localhost:4173', trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } }],
  webServer: {
    command: 'VITE_MOCK=1 bunx vite build --outDir dist-mock && bunx vite preview --outDir dist-mock',
    port: 4173,
    reuseExistingServer: true,
    timeout: 120_000,
  },
})
