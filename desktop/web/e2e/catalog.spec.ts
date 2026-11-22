/** The App Catalog against the mock build. */
import { expect, test } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { openApp } from './apps'
import { signIn } from './sign-in'

test('App Catalog: an app is installed on a chosen port, another updated and removed', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  const win = await openApp(page, 'App Catalog')
  const jellyfin = win.getByRole('listitem', { name: 'Jellyfin' })
  await expect(jellyfin).toContainText('Not installed')
  await jellyfin.getByRole('button', { name: 'Install…' }).click()
  const ask = page.getByRole('dialog', { name: 'Install Jellyfin' })
  await ask.getByLabel('Port').fill('8100')
  await ask.getByRole('button', { name: 'Install' }).click()
  await expect(jellyfin).toContainText('Installed, on port 8100')
  await expect(win.getByText('kura-apps install jellyfin')).toBeVisible()
  await page.screenshot({ path: 'test-results/screens/catalog.png' })

  const gitea = win.getByRole('listitem', { name: 'Gitea' })
  await gitea.getByRole('button', { name: 'Update' }).click()
  await expect(gitea).not.toContainText('is ready')
  await gitea.getByRole('button', { name: 'Remove…' }).click()
  await page.getByRole('dialog', { name: 'Remove Gitea?' }).getByRole('button', { name: 'Remove' }).click()
  await expect(gitea).toContainText('Not installed')
})
