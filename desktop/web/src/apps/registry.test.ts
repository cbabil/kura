import { makeI18n } from '../i18n'
import type { SystemInfo } from '../api'
import { APP_BY_ID, DOCKABLE, dockable, launcherEntries, offered } from './registry'

const facts = (browser: boolean): SystemInfo =>
  ({ hostname: 'kura', os: 'Kura', kernel: '6', arch: 'x86_64', cores: 2, memTotal: 1, uptime: 1, browser, version: '0.8.1' })

describe('apps a server offers', () => {
  it('shows the Browser only where its packages are installed', () => {
    const browser = APP_BY_ID.browser
    expect([offered(browser, null), offered(browser, facts(false)), offered(browser, facts(true))]).toEqual([false, false, true])
    expect(offered(APP_BY_ID.terminal, null)).toBe(true)
    expect(dockable(facts(false))).toEqual(DOCKABLE.filter((id) => id !== 'browser'))
    expect(dockable(facts(true))).toEqual(DOCKABLE)
    const { t } = makeI18n('en')
    const names = (system: SystemInfo | null) => launcherEntries(t, system).map((e) => e.title)
    expect(names(null)).not.toContain('Browser')
    expect(names(facts(true))).toContain('Browser')
  })

  it('gives the Browser its own menus: quit it, paste text', () => {
    const labels = APP_BY_ID.browser.menus.flatMap((m) => m.items.map((i) => i.label))
    expect(labels).toEqual(expect.arrayContaining(['menu.quitBrowser', 'menu.pasteText', 'menu.closeWindow']))
  })
})
