/** Sign-in steps shared by the mock e2e tests and the device screenshots. */
import { expect, type Page } from '@playwright/test'

export async function submit(page: Page, user: string, password: string) {
  await page.getByLabel('User name').fill(user)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
}

/** Signs in and waits for the desktop, where Activity Monitor opens first. */
export async function signIn(page: Page, user: string, password: string) {
  await submit(page, user, password)
  await expect(page.getByRole('dialog', { name: 'Activity Monitor' })).toBeVisible()
}
