/** Steps for the D2 apps, shared by the mock e2e tests and the device screenshots. */
import { expect, type Locator, type Page } from '@playwright/test'

/** Opens an app from the dock and returns its window. */
export async function openApp(page: Page, name: string): Promise<Locator> {
  await page.getByRole('navigation', { name: 'Dock' }).getByLabel(name, { exact: true }).click()
  const win = page.getByRole('dialog', { name })
  await expect(win).toBeVisible()
  return win
}

/** Opens an app from the launcher (⌘K / Ctrl K), for one the dock does not show, and returns its window. */
export async function launchApp(page: Page, name: string): Promise<Locator> {
  await page.keyboard.press('Control+k')
  await page.getByRole('combobox', { name: 'Search' }).fill(name)
  await page.keyboard.press('Enter')
  const win = page.getByRole('dialog', { name })
  await expect(win).toBeVisible()
  return win
}

/** Types a command into an open Terminal window once its shell shows a prompt. */
export async function runInTerminal(terminal: Locator, command: string) {
  const screen = terminal.locator('.xterm-rows')
  // "user@host:~$" in most shells; "user@host:~ >" with Kura's own prompt
  await expect(screen).toContainText(/@[\w.-]+:.*[$>#]/, { timeout: 20_000 })
  await terminal.locator('.xterm').click()
  await terminal.page().keyboard.type(command)
  await terminal.page().keyboard.press('Enter')
  return screen
}

/**
 * Waits until the Browser window's screen (noVNC's canvas) shows a drawn
 * page: at least four colours (the mock page has four; Chromium's own pages
 * many more), not a blank fill with a pointer on it. Returns a function
 * reading one pixel of it.
 */
export async function browserScreen(win: Locator) {
  const canvas = win.getByRole('application', { name: 'The server’s browser' }).locator('canvas')
  await expect(canvas).toBeVisible({ timeout: 30_000 })
  const pixel = (x: number, y: number) =>
    canvas.evaluate((c: HTMLCanvasElement, [px, py]) => [...c.getContext('2d')!.getImageData(px, py, 1, 1).data.slice(0, 3)], [x, y])
  const colours = () =>
    canvas.evaluate((c: HTMLCanvasElement) => {
      const { data } = c.getContext('2d')!.getImageData(0, 0, c.width, c.height)
      const seen = new Set<number>()
      for (let i = 0; i < data.length && seen.size < 4; i += 4 * 7) seen.add((data[i] << 16) | (data[i + 1] << 8) | data[i + 2])
      return seen.size
    })
  await expect.poll(colours, { timeout: 45_000 }).toBeGreaterThanOrEqual(4)
  return pixel
}
