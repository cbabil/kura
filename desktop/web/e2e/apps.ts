/** Steps for the D2 apps, shared by the mock e2e tests and the device screenshots. */
import { expect, type Locator, type Page } from '@playwright/test'

/** Opens an app from the dock and returns its window. */
export async function openApp(page: Page, name: string): Promise<Locator> {
  await page.getByRole('navigation', { name: 'Dock' }).getByLabel(name, { exact: true }).click()
  const win = page.getByRole('dialog', { name })
  await expect(win).toBeVisible()
  return win
}

/** Types a command into an open Terminal window once its shell shows a prompt. */
export async function runInTerminal(terminal: Locator, command: string) {
  const screen = terminal.locator('.xterm-rows')
  await expect(screen).toContainText('$', { timeout: 20_000 })
  await terminal.locator('.xterm').click()
  await terminal.page().keyboard.type(command)
  await terminal.page().keyboard.press('Enter')
  return screen
}
