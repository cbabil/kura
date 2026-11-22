/** Languages that are not part of the page are fetched when chosen (mock build). */
import { expect, test } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { signIn } from './sign-in'

test.describe('in a language that is fetched', () => {
  test.use({ locale: 'ja-JP' })

  test('the sign-in page follows the browser, and another language is a choice away', async ({ page }) => {
    await page.goto('/')
    // The words arrive a moment after the page: the file is fetched.
    await expect(page.getByRole('button', { name: 'サインイン' })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.lang)).toBe('ja')
  })
})

test('a language is chosen from the 蔵 menu and the desktop follows', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  await page.getByRole('button', { name: 'Kura menu' }).click()
  await page.getByRole('menuitem', { name: 'Language…' }).click()
  const choose = page.getByRole('dialog', { name: 'Language' })
  await expect(choose.getByRole('radio')).toHaveCount(27)
  await choose.getByRole('radio', { name: 'עברית' }).check()
  await expect.poll(() => page.evaluate(() => document.documentElement.lang)).toBe('he')
  await page.getByRole('radio', { name: 'Deutsch' }).check()
  // The dialog itself now speaks German; behind it, so does the desktop.
  await page.getByRole('button', { name: 'Fertig' }).click()
  await expect(page.getByRole('navigation', { name: 'Dock' }).getByLabel('Dateien', { exact: true })).toBeVisible()
  await page.screenshot({ path: 'test-results/screens/language-de.png' })
})
