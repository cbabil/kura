/** The shared Browser (ADR-036) against the mock build: its VNC server draws one page. */
import { expect, test } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { MOCK_COLOURS } from '../src/api/mockBrowser'
import { browserScreen, openApp } from './apps'
import { signIn } from './sign-in'

test('Browser: anyone signed in opens it and sees the page it shows', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'guest', MOCK_PASSWORD)
  const win = await openApp(page, 'Browser')
  const pixel = await browserScreen(win)
  expect(await pixel(20, 20)).toEqual([...MOCK_COLOURS.tabs])
  expect(await pixel(100, 140)).toEqual([...MOCK_COLOURS.heading])
  expect(await pixel(900, 600)).toEqual([...MOCK_COLOURS.page])
  await page.screenshot({ path: 'test-results/screens/browser.png' })

  // its menus: quitting it for everyone, and text for its clipboard
  await page.getByRole('button', { name: 'Edit' }).click()
  await page.getByRole('menuitem', { name: 'Paste Text…' }).click()
  const dialog = page.getByRole('dialog', { name: 'Paste Text' })
  await dialog.getByLabel('Text for the browser’s clipboard').fill('hello')
  await dialog.getByRole('button', { name: 'Paste' }).click()
  await expect(dialog).toBeHidden()
})
