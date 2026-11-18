/**
 * Playwright against a real Kura device (the CI boot test, tests/boot/
 * desktop-checks.sh): the base config's browser and viewport, no mock server,
 * and the device's self-signed certificate accepted. KURA_DEVICE_URL, _USER,
 * _PASS and _SHOTS come from the boot test.
 */
import { defineConfig } from '@playwright/test'
import base from './playwright.config'

export default defineConfig({
  ...base,
  testDir: 'e2e-device',
  timeout: 60_000,
  webServer: undefined,
  use: { ...base.use, baseURL: process.env.KURA_DEVICE_URL, ignoreHTTPSErrors: true },
})
