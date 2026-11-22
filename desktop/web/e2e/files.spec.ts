/** Files and Trash against the mock build (see desktop.spec.ts for the rest of the desktop). */
import { expect, test } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { openApp } from './apps'
import { signIn } from './sign-in'

const shot = (name: string) => ({ path: `test-results/screens/${name}.png` })

test('Files: a folder is made, a file previewed and moved to the Trash, and put back from the dock', async ({ page }) => {
  await page.goto('/')
  await signIn(page, 'chris', MOCK_PASSWORD)
  const win = await openApp(page, 'Files')
  const list = win.getByRole('table', { name: 'Files in /home/chris' })
  await expect(list.getByRole('row', { name: /^Documents/ })).toBeVisible()
  await win.getByRole('button', { name: 'New Folder…' }).click()
  const ask = page.getByRole('dialog', { name: 'New folder' })
  await ask.getByLabel('Name').fill('Music')
  await ask.getByRole('button', { name: 'Create' }).click()
  await expect(list.getByRole('row', { name: /^Music/ })).toBeVisible()
  await list.getByRole('row', { name: /^backup.tar/ }).click()
  await expect(win.getByRole('link', { name: 'Download' })).toBeVisible()
  await page.screenshot(shot('files'))

  await list.getByRole('row', { name: /^Documents/ }).dblclick()
  const documents = win.getByRole('table', { name: 'Files in /home/chris/Documents' })
  await documents.getByRole('row', { name: /^notes.txt/ }).dblclick()
  const preview = page.getByRole('dialog', { name: 'notes.txt' })
  await expect(preview).toContainText('Buy a second disk.')
  await preview.getByRole('button', { name: 'Close' }).click()
  await documents.getByRole('row', { name: /^notes.txt/ }).click()
  await win.getByRole('button', { name: 'Move to Trash' }).click()
  await expect(win.getByText('This folder is empty.')).toBeVisible()

  const trash = await openApp(page, 'Trash')
  await expect(trash.getByRole('row', { name: /notes.txt/ })).toContainText('/home/chris/Documents')
  await page.screenshot(shot('trash'))
  await trash.getByRole('button', { name: 'Put back notes.txt' }).click()
  await expect(trash.getByText('The Trash is empty.')).toBeVisible()
})
