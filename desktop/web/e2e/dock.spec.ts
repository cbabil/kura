/** Dragging in the dock, as on a Mac, against the mock build. */
import { expect, test, type Locator, type Page } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { launchApp } from './apps'
import { signIn } from './sign-in'

const order = (dock: Locator) => dock.getByRole('button').evaluateAll((els) => els.map((e) => e.getAttribute('aria-label')))

/** Presses the icon, moves in steps to (x, y), and lets go, as a hand does. */
async function dragTo(page: Page, icon: Locator, x: number, y: number) {
  const box = (await icon.boundingBox())!
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.mouse.down()
  await page.mouse.move(x, y, { steps: 12 })
  await page.mouse.up()
}

test('the dock: drag to reorder, drop a running app to keep it, pull one out to remove it', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  const dock = page.getByRole('navigation', { name: 'Dock' })
  const first = (await order(dock))[0]
  expect(first).toBe('Activity Monitor')

  // Terminal to the front: the icons part, and it lands first; nothing opens
  const front = (await dock.getByLabel('Activity Monitor').boundingBox())!
  await dragTo(page, dock.getByLabel('Terminal'), front.x + 4, front.y + front.height / 2)
  expect((await order(dock))[0]).toBe('Terminal')
  await expect(page.getByRole('dialog', { name: 'Terminal' })).toHaveCount(0)

  // Files pulled up and away is removed from the dock
  const files = (await dock.getByLabel('Files').boundingBox())!
  await dragTo(page, dock.getByLabel('Files'), files.x + 30, files.y - 200)
  await expect(dock.getByLabel('Files', { exact: true })).toHaveCount(0)

  // ...and back: open it, then drop its running icon among the kept ones
  await launchApp(page, 'Files')
  await dragTo(page, dock.getByLabel('Files', { exact: true }), front.x + 4, front.y + front.height / 2)
  expect((await order(dock)).slice(0, 2)).toEqual(['Files', 'Terminal'])
  await page.screenshot({ path: 'test-results/screens/dock.png' })
})

test('the dock\'s menu, as on a Mac: Options ▸ Keep in Dock, Remove from Dock, Quit', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  const dock = page.getByRole('navigation', { name: 'Dock' })

  // an open, kept app: Keep in Dock is ticked; untick it, then Quit, and it leaves the dock
  await dock.getByLabel('Activity Monitor').click({ button: 'right' })
  await page.getByRole('menuitem', { name: 'Options' }).hover()
  const keep = page.getByRole('menuitemcheckbox', { name: 'Keep in Dock' })
  await expect(keep).toHaveAttribute('aria-checked', 'true')
  await page.screenshot({ path: 'test-results/screens/dock-menu.png' })
  await keep.click()
  await expect(dock.getByLabel('Activity Monitor')).toBeVisible() // still open, so still shown
  await dock.getByLabel('Activity Monitor').click({ button: 'right' })
  await page.getByRole('menuitem', { name: 'Quit' }).click()
  await expect(page.getByRole('dialog', { name: 'Activity Monitor' })).toHaveCount(0)
  await expect(dock.getByLabel('Activity Monitor', { exact: true })).toHaveCount(0)

  // a kept app that is not open: Options ▸ Remove from Dock
  await dock.getByLabel('Terminal').click({ button: 'right' })
  await page.getByRole('menuitem', { name: 'Options' }).click()
  await page.getByRole('menuitem', { name: 'Remove from Dock' }).click()
  await expect(dock.getByLabel('Terminal', { exact: true })).toHaveCount(0)
})
