/** Settings › General › Remote Desktop (ADR-035) against the mock build. */
import { expect, test } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { openApp } from './apps'
import { signIn } from './sign-in'

test('Settings: Remote Desktop is turned on and says where to connect', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  const win = await openApp(page, 'Settings')
  const rdp = win.getByRole('switch', { name: 'Let a Remote Desktop client open Kura Desktop' })
  await expect(rdp).not.toBeChecked()
  await expect(win.getByText('connect to kura-nuc.local')).toBeVisible()
  await rdp.click()
  await expect(rdp).toBeChecked()
  // the server's own screen has a switch of its own, untouched
  await expect(win.getByRole('switch', { name: 'Show Kura Desktop on it' })).not.toBeChecked()
  await page.screenshot({ path: 'test-results/screens/remote-desktop.png' })
})
