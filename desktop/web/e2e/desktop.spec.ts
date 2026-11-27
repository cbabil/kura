/**
 * End-to-end: sign in, use windows, the dock and the launcher, the Terminal,
 * Containers, Console and Settings apps, restart and shut down, switch
 * theme, and check the phone layout.
 * Runs against the mock build (see playwright.config.ts).
 */
import { expect, test, type Page } from '@playwright/test'
import { MOCK_PASSWORD } from '../src/api/mock'
import { openApp, runInTerminal } from './apps'
import { signIn as signInAs, submit as submitAs } from './sign-in'

const submit = (page: Page, password: string) => submitAs(page, 'chris', password)

async function signIn(page: Page) {
  await page.goto('/')
  await signInAs(page, 'chris', MOCK_PASSWORD)
}

test('refuses a wrong password, then signs in to Activity Monitor', async ({ page }) => {
  await page.goto('/')
  await submit(page, 'wrong')
  await expect(page.getByText('Wrong user name or password.')).toBeVisible()
  await submit(page, MOCK_PASSWORD)
  await expect(page.getByText('CPU · 4 cores')).toBeVisible()
  await expect(page.getByRole('table', { name: 'Busiest processes' })).toBeVisible()
  // the menu bar's temperature is short: "CPU 48°", its name in the tooltip
  const temp = page.getByText(/^CPU \d+(\.\d)?°$/)
  await expect(temp).toBeVisible()
  await temp.hover()
  await expect(page.getByRole('tooltip', { name: 'CPU temperature' })).toBeVisible()
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
  await dock.getByLabel('Files').click()
  const files = page.getByRole('dialog', { name: 'Files' })
  await expect(files.getByRole('navigation', { name: 'Places' })).toBeVisible()
  await files.getByLabel('Minimize').click()
  await expect(dock.getByLabel('Files (minimised)')).toBeVisible()
  await page.keyboard.press('Control+k')
  await page.getByRole('combobox', { name: 'Search' }).fill('stor')
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog', { name: 'Activity Monitor' }).getByText('/var/lib/docker')).toBeVisible()
})

/** Screenshots of the D2 apps land in test-results/screens/. */
const shot = (name: string) => ({ path: `test-results/screens/${name}.png` })

test('Terminal: a shell in a window', async ({ page }) => {
  await signIn(page)
  const terminal = await openApp(page, 'Terminal')
  const screen = await runInTerminal(terminal, 'whoami')
  await expect(screen).toContainText('chris@kura-nuc:~$ whoami')
  await expect(screen.getByText('chris', { exact: true })).toBeVisible()
  await page.screenshot(shot('terminal'))
  await terminal.page().keyboard.type('exit')
  await terminal.page().keyboard.press('Enter')
  await expect(terminal.getByText('The shell has ended.')).toBeVisible()
  await terminal.getByRole('button', { name: 'New Shell' }).click()
  await expect(terminal.getByText('The shell has ended.')).toHaveCount(0)
  // Ctrl K belongs to the shell here, not to the launcher
  await terminal.locator('.xterm').click()
  await page.keyboard.press('Control+k')
  await expect(page.getByRole('combobox', { name: 'Search' })).toHaveCount(0)
})

test('Containers: stacks, stop and start, logs', async ({ page }) => {
  await signIn(page)
  const win = await openApp(page, 'Containers')
  await expect(win.getByRole('group', { name: 'immich' }).getByText('4 of 4 running')).toBeVisible()
  await page.screenshot(shot('containers'))
  const jellyfin = win.getByRole('listitem', { name: 'jellyfin' })
  await win.getByRole('button', { name: 'Stop jellyfin' }).click()
  await expect(jellyfin.getByText('Stopped')).toBeVisible()
  await win.getByRole('button', { name: 'Start jellyfin' }).click()
  await expect(jellyfin.getByText('Running')).toBeVisible()
  await win.getByRole('button', { name: 'Logs of jellyfin' }).click()
  await expect(win.getByRole('log', { name: 'Logs · jellyfin' })).toContainText('jellyfin: handled request 40')
  await win.getByRole('button', { name: 'Back to containers' }).click()
  await win.getByRole('searchbox', { name: 'Search containers' }).fill('pihole')
  await expect(win.getByRole('listitem')).toHaveCount(1)
})

test('Containers: other users only look', async ({ page }) => {
  await page.goto('/')
  await signInAs(page, 'guest', MOCK_PASSWORD)
  const win = await openApp(page, 'Containers')
  await expect(win.getByText(/Only administrators can start or stop/)).toBeVisible()
  await expect(win.getByRole('button', { name: 'Stop jellyfin' })).toHaveCount(0)
  const console = await openApp(page, 'Console')
  await expect(console.getByText('The system journal is for administrators.')).toBeVisible()
})

test('Console: the journal, filtered', async ({ page }) => {
  await signIn(page)
  const win = await openApp(page, 'Console')
  const log = win.getByRole('log', { name: 'System journal' })
  await expect(log.getByRole('listitem')).toHaveCount(8)
  await page.screenshot(shot('console'))
  await win.getByLabel('Unit').selectOption('ssh.service')
  await expect(log.getByRole('listitem')).toHaveCount(2)
  await win.getByLabel('Priority').selectOption({ label: 'Errors' })
  await expect(log.getByRole('listitem')).toHaveCount(1)
  await expect(log).toContainText('Failed password for invalid user admin')
  await win.getByRole('searchbox', { name: 'Filter messages' }).fill('nothing like this')
  await expect(win.getByText('No entries match.')).toBeVisible()
})

test('Settings: an update waits, is installed, and asks for a restart', async ({ page }) => {
  await signIn(page)
  await page.getByRole('button', { name: 'Kura 0.6.2 is available' }).click()
  const win = page.getByRole('dialog', { name: 'Settings' })
  await expect(win.getByText('Kura 0.6.2 is available.')).toBeVisible()
  await page.screenshot(shot('settings-updates'))
  await win.getByRole('button', { name: 'Install' }).click()
  await expect(win.getByText('Kura is up to date.')).toBeVisible()
  await expect(win.getByRole('log', { name: 'What the update wrote' })).toContainText('Setting up kura (0.6.2)')
  await expect(page.getByRole('button', { name: 'A restart is needed to finish an update' })).toBeVisible()
  await win.getByRole('button', { name: 'Restart…' }).click()
  const ask = page.getByRole('dialog', { name: 'Restart this server?' })
  await ask.getByRole('button', { name: 'Cancel' }).click()
  await expect(ask).toHaveCount(0)
})

test('Settings: a person is added, made an administrator and removed; the address asks to be kept', async ({ page }) => {
  await signIn(page)
  const win = await openApp(page, 'Settings')
  await win.getByRole('button', { name: 'Users' }).click()
  await win.getByLabel('User name').fill('paul')
  await win.getByLabel('Password').fill('s3cret pass')
  await win.getByRole('button', { name: 'Add' }).click()
  const paul = win.getByRole('listitem', { name: 'paul' })
  await paul.getByRole('switch', { name: 'Administrator' }).check()
  await expect(paul.getByRole('switch', { name: 'Administrator' })).toBeChecked()
  await page.screenshot(shot('settings-users'))
  await paul.getByRole('button', { name: 'Remove' }).click()
  await page.getByRole('dialog', { name: 'Remove paul?' }).getByRole('button', { name: 'Remove' }).click()
  await expect(paul).toHaveCount(0)

  await win.getByRole('button', { name: 'Network' }).click()
  await expect(win.getByRole('group', { name: 'enp1s0' })).toContainText('192.168.1.50/24')
  await win.getByRole('radio', { name: 'Set here' }).check()
  await win.getByLabel('Address and prefix').fill('192.168.1.60/24')
  await win.getByLabel('Gateway').fill('192.168.1.1')
  await win.getByLabel('DNS servers').fill('192.168.1.1')
  await win.getByRole('button', { name: 'Apply' }).click()
  await page.screenshot(shot('settings-network'))
  await win.getByRole('button', { name: 'Keep' }).click()
  await expect(win.getByRole('button', { name: 'Keep' })).toHaveCount(0)
})

test('Settings: others change their own password and nothing else', async ({ page }) => {
  await page.goto('/')
  await signInAs(page, 'guest', MOCK_PASSWORD)
  const win = await openApp(page, 'Settings')
  await expect(win.getByLabel('Server name')).toHaveCount(0)
  await win.getByLabel('Current password').fill(MOCK_PASSWORD)
  await win.getByLabel('New password', { exact: true }).fill('a new one')
  await win.getByLabel('New password, again').fill('a new one')
  await win.getByRole('button', { name: 'Change Password' }).click()
  await expect(win.getByText(/Your password is changed/)).toBeVisible()
  await win.getByRole('button', { name: 'Users' }).click()
  await expect(win.getByText('These settings are for administrators.')).toBeVisible()
})

test('the 蔵 menu restarts and shuts down, after asking', async ({ page }) => {
  await signIn(page)
  await page.getByRole('button', { name: 'Kura menu' }).click()
  await page.getByRole('menuitem', { name: 'Shut Down…' }).click()
  const ask = page.getByRole('dialog', { name: 'Shut down this server?' })
  await page.screenshot(shot('shut-down'))
  await ask.getByRole('button', { name: 'Shut Down' }).click()
  await expect(ask.getByText('You can close this page.')).toBeVisible()
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

test.describe('in French', () => {
  test.use({ locale: 'fr-FR' })

  test('signs in and shows the desktop in the browser’s language', async ({ page }) => {
    await page.goto('/')
    await page.getByLabel("Nom d'utilisateur").fill('chris')
    await page.getByLabel('Mot de passe').fill(MOCK_PASSWORD)
    await page.getByRole('button', { name: 'Se connecter' }).click()
    await expect(page.getByRole('dialog', { name: "Moniteur d'activité" })).toBeVisible()
    await expect(page.getByRole('table', { name: 'Processus les plus actifs' })).toBeVisible()
    await expect(page.getByText(/\d+,\d Go/).first()).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.lang)).toBe('fr')
  })
})
