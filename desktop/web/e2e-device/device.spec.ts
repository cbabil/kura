/**
 * Signs in to a booted Kura image through the browser and saves signin.png
 * and desktop.png for the boot logs (ADR-023), then opens the D2 apps
 * against the real helper (ADR-027): a shell that runs as the login user,
 * Docker's containers and the journal, with a screenshot of each.
 */
import { expect, test } from '@playwright/test'
import { openApp, runInTerminal } from '../e2e/apps'
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

test('opens a shell as the login user, the containers and the journal', async ({ page }) => {
  const shots = need('KURA_DEVICE_SHOTS')
  const user = need('KURA_DEVICE_USER')
  await page.goto('/')
  await signIn(page, user, need('KURA_DEVICE_PASS'))

  // The shell is the login user's own: never root, never the desktop's user
  const terminal = await openApp(page, 'Terminal')
  const screen = await runInTerminal(terminal, 'echo "shell of $(id -un), uid $(id -u)"')
  await expect(screen).toContainText(`shell of ${user}, uid 1`, { timeout: 15_000 })
  await page.screenshot({ path: `${shots}/terminal.png` })
  await terminal.getByLabel('Close').click()

  // A fresh image has Docker and no containers; either answer comes from Docker through the helper
  const containers = await openApp(page, 'Containers')
  await expect(containers.getByText('No containers yet.').or(containers.getByRole('listitem').first())).toBeVisible({ timeout: 15_000 })
  await page.screenshot({ path: `${shots}/containers.png` })
  await containers.getByLabel('Close').click()

  const console = await openApp(page, 'Console')
  await expect(console.getByRole('log', { name: 'System journal' }).getByRole('listitem').first()).toBeVisible({ timeout: 15_000 })
  await page.screenshot({ path: `${shots}/console.png` })
})
