import { render, screen } from '@testing-library/react'
import { en } from './en'
import { CATALOGUES, NAMES, pickLanguage, makeI18n, I18nProvider, useI18n } from './index'

const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort()
/** Plural forms a language may add beyond English's one/other. */
const EXTRA_PLURAL = /\.(zero|two|few|many)$/

describe('catalogues', () => {
  it.each(Object.entries(CATALOGUES))('%s has every English key and the same placeholders', (_, messages) => {
    const keys = Object.keys(messages).filter((k) => !EXTRA_PLURAL.test(k))
    expect(keys.sort()).toEqual(Object.keys(en).sort())
    for (const [key, text] of Object.entries(en)) {
      expect([key, placeholders((messages as Record<string, string>)[key])]).toEqual([key, placeholders(text)])
    }
  })

  it('names every language in its own words', () => {
    expect(Object.keys(NAMES).sort()).toEqual(Object.keys(CATALOGUES).sort())
    expect(NAMES.fr).toBe('Français')
  })
})

describe('pickLanguage', () => {
  it('takes the first browser language Kura has, by its main part', () => {
    expect(pickLanguage('auto', ['de-DE', 'fr-CA', 'en'])).toBe('fr')
    expect(pickLanguage('auto', ['en-GB'])).toBe('en')
  })

  it('falls back to English; a valid stored choice wins, an unknown one is ignored', () => {
    expect(pickLanguage('auto', ['ja', 'zh'])).toBe('en')
    expect(pickLanguage('auto', [])).toBe('en')
    expect(pickLanguage('fr', ['en-US'])).toBe('fr')
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
})
