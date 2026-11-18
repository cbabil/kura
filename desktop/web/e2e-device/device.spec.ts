/**
 * Signs in to a booted Kura image through the browser and saves signin.png
 * and desktop.png for the boot logs (ADR-023).
 */
import { expect, test } from '@playwright/test'
import { signIn } from '../e2e/sign-in'

/** A setting the boot test passes; a missing one fails the run, never fills in a blank. */
function need(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`${name} is not set (tests/boot/desktop-checks.sh sets it)`)
  return value
}

test('signs in to the device and shows the desktop', async ({ page }) => {
  const shots = need('KURA_DEVICE_SHOTS')
  need('KURA_DEVICE_URL')
  await page.goto('/')
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible()
  await page.screenshot({ path: `${shots}/signin.png` })
  await signIn(page, need('KURA_DEVICE_USER'), need('KURA_DEVICE_PASS'))
  await expect(page.getByText(/CPU · \d+ cores?/)).toBeVisible({ timeout: 15_000 })
  await page.screenshot({ path: `${shots}/desktop.png` })
})
