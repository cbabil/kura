/**
 * End-to-end: sign in, use windows, the dock and the launcher, switch theme,
 * and check the phone layout. Runs against the mock build (see playwright.config.ts).
 */
import { expect, test, type Page } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'

async function submit(page: Page, password: string) {
  await page.getByLabel('User name').fill('chris')
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
}

async function signIn(page: Page) {
  await page.goto('/')
  await submit(page, MOCK_PASSWORD)
  await expect(page.getByRole('dialog', { name: 'Activity Monitor' })).toBeVisible()
}

test('refuses a wrong password, then signs in to Activity Monitor', async ({ page }) => {
  await page.goto('/')
  await submit(page, 'wrong')
  await expect(page.getByText('Wrong user name or password.')).toBeVisible()
  await submit(page, MOCK_PASSWORD)
  await expect(page.getByText('CPU · 4 cores')).toBeVisible()
  await expect(page.getByRole('table', { name: 'Busiest processes' })).toBeVisible()
})

test('moves a window by its title bar and keeps it on screen', async ({ page }) => {
  await signIn(page)
  const win = page.getByRole('dialog', { name: 'Activity Monitor' })
  const before = await win.boundingBox()
  const title = win.getByText('Activity Monitor', { exact: true }).first()
  const box = (await title.boundingBox())!
  // the title spans the whole bar; grab it left of centre, clear of the buttons and the range switch
  await page.mouse.move(box.x + 300, box.y + box.height / 2)
  await page.mouse.down()
  await page.mouse.move(box.x + 400, box.y + box.height / 2 + 60, { steps: 5 })
  await page.mouse.up()
  const after = (await win.boundingBox())!
  expect(after.x - before!.x).toBeCloseTo(100, -1)
  expect(after.y - before!.y).toBeCloseTo(60, -1)
})

test('dock opens and minimises apps; Ctrl K finds a section', async ({ page }) => {
  await signIn(page)
  const dock = page.getByRole('navigation', { name: 'Dock' })
  await dock.getByLabel('Terminal').click()
  const terminal = page.getByRole('dialog', { name: 'Terminal' })
  await expect(terminal.getByText('Arrives in a coming update of Kura.')).toBeVisible()
  await terminal.getByLabel('Minimize').click()
  await expect(dock.getByLabel('Terminal (minimised)')).toBeVisible()
  await page.keyboard.press('Control+k')
  await page.getByRole('combobox', { name: 'Search' }).fill('stor')
  await page.keyboard.press('Enter')
  await expect(page.getByText('/var/lib/docker')).toBeVisible()
})

test('switches between dark and light themes', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' })
  await signIn(page)
  const bg = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor)
  expect(await bg()).toBe('rgb(15, 23, 42)')
  await page.getByRole('button', { name: 'Use light theme' }).click()
  expect(await bg()).toBe('rgb(247, 247, 250)')
})

test('phone width: one full-screen window and a bottom dock', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page)
  const win = (await page.getByRole('dialog', { name: 'Activity Monitor' }).boundingBox())!
  expect(win.x).toBe(0)
  expect(win.width).toBe(390)
  const scroll = await page.evaluate(() => document.documentElement.scrollWidth)
  expect(scroll).toBeLessThanOrEqual(390)
})
