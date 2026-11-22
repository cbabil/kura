import { render, screen } from '@testing-library/react'
import { en } from './en'
import { NAMES, pickLanguage, makeI18n, I18nProvider, useI18n, type Lang } from './index'
import { BUNDLED } from './languages'

const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort()
/** Plural forms a language may add beyond English's one/other. */
const EXTRA_PLURAL = /\.(zero|two|few|many)$/

const FETCHED = import.meta.glob<{ default: Record<string, string> }>('./locales/*.json', { eager: true })
const ALL: Record<string, Record<string, string>> = {
  ...BUNDLED,
  ...Object.fromEntries(Object.entries(FETCHED).map(([path, file]) => [path.slice('./locales/'.length, -'.json'.length), file.default])),
}

describe('catalogues', () => {
  it.each(Object.entries(ALL))('%s has every English key and the same placeholders', (_, messages) => {
    const keys = Object.keys(messages).filter((k) => !EXTRA_PLURAL.test(k))
    expect(keys.sort()).toEqual(Object.keys(en).sort())
    for (const [key, text] of Object.entries(en)) {
      expect([key, placeholders(messages[key])]).toEqual([key, placeholders(text)])
    }
    for (const [key, text] of Object.entries(messages)) expect([key, text.trim().length > 0]).toEqual([key, true])
  })

  it.each(Object.keys(ALL))('%s has the plural forms its numbers ask for', (lang) => {
    const { tn } = makeI18n(lang as Lang, ALL[lang])
    const forms = new Intl.PluralRules(lang).resolvedOptions().pluralCategories
    for (const count of [0, 1, 2, 3, 5, 11, 21, 100]) {
      const form = new Intl.PluralRules(lang).select(count)
      expect(forms).toContain(form)
      expect([lang, count, `activity.volumes.${form}` in ALL[lang] || form === 'other']).toEqual([lang, count, true])
      expect(tn('activity.volumes', count)).toContain(String(count))
    }
  })

  it('names every language in its own words, and has a catalogue for each', () => {
    expect(Object.keys(NAMES).sort()).toEqual(Object.keys(ALL).sort())
    expect(Object.keys(NAMES)).toHaveLength(26)
    expect([NAMES.fr, NAMES.ja, NAMES['pt-BR']]).toEqual(['Français', '日本語', 'Português (Brasil)'])
  })
})

describe('pickLanguage', () => {
  it('takes the first browser language Kura has: the tag itself, or its main part', () => {
    expect(pickLanguage('auto', ['xx-XX', 'fr-CA', 'en'])).toBe('fr')
    expect(pickLanguage('auto', ['en-GB'])).toBe('en')
    expect(pickLanguage('auto', ['pt-BR', 'pt'])).toBe('pt-BR')
    expect(pickLanguage('auto', ['pt-PT'])).toBe('pt')
    expect(pickLanguage('auto', ['de-AT'])).toBe('de')
  })

  it('tells the two Chinese apart by what the browser says', () => {
    expect(pickLanguage('auto', ['zh-TW'])).toBe('zh-TW')
    expect(pickLanguage('auto', ['zh-Hant-HK'])).toBe('zh-TW')
    expect(pickLanguage('auto', ['zh-HK'])).toBe('zh-TW')
    expect(pickLanguage('auto', ['zh-CN'])).toBe('zh')
    expect(pickLanguage('auto', ['zh'])).toBe('zh')
  })

  it('falls back to English; a valid stored choice wins, an unknown one is ignored', () => {
    expect(pickLanguage('auto', ['xx', 'yy'])).toBe('en')
    expect(pickLanguage('auto', [])).toBe('en')
    expect(pickLanguage('fr', ['en-US'])).toBe('fr')
    expect(pickLanguage('zh-TW', ['en-US'])).toBe('zh-TW')
    expect(pickLanguage('xx', ['fr'])).toBe('fr')
  })
})

describe('makeI18n', () => {
  it('fills placeholders, and leaves unknown ones visible', () => {
    expect(makeI18n('fr').t('menu.signOut', { name: 'chris' })).toBe('Déconnecter chris')
    expect(makeI18n('en').t('activity.of', { used: '2 GB', size: '4 GB' })).toBe('2 GB of 4 GB')
    expect(makeI18n('en').t('menu.signOut')).toBe('Sign Out {name}')
  })

  it('falls back to English, then to the key, instead of failing', () => {
    expect(makeI18n('en').t('no.such.key' as never)).toBe('no.such.key')
  })

  it('chooses the plural form for the count', () => {
    const { tn } = makeI18n('en')
    expect(tn('activity.volumes', 1)).toBe('1 volume')
    expect(tn('activity.volumes', 4)).toBe('4 volumes')
    expect(makeI18n('fr').tn('activity.cpu', 1)).toBe('Processeur · 1 cœur')
    expect(makeI18n('fr').tn('activity.cpu', 0)).toBe('Processeur · 0 cœur')
  })
})

function Probe() {
  const { t, lang, format } = useI18n()
  return <p>{`${lang} ${t('dock.open')} ${format.bytes(5.8 * 1024 ** 3)}`}</p>
}

describe('I18nProvider', () => {
  it('provides the language, its words and its number format', () => {
    render(<I18nProvider lang="fr"><Probe /></I18nProvider>)
    expect(screen.getByText('fr Ouvrir 5,8 Go')).toBeInTheDocument()
    expect(document.documentElement.lang).toBe('fr')
  })

  it('defaults to English without a provider', () => {
    render(<Probe />)
    expect(screen.getByText('en Open 5.8 GB')).toBeInTheDocument()
  })

  it('fetches a language that is not part of the page, in English meanwhile', async () => {
    render(<I18nProvider lang="de"><Probe /></I18nProvider>)
    expect(document.documentElement.lang).toBe('de')
    const german = ALL.de['dock.open']
    expect(german).not.toBe('Open')
    expect(await screen.findByText(new RegExp(`^de ${german} `))).toBeInTheDocument()
  })
})
