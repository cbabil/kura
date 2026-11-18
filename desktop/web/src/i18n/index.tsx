/**
 * Kura Desktop's languages. Each catalogue has every key of en.ts; the
 * language is the user's choice, or the browser's first one Kura has, or
 * English. Numbers, sizes, dates and plurals follow the language.
 * Adding a language: a catalogue file and one line in CATALOGUES and NAMES.
 */
import { createContext, useContext, useEffect, useMemo, type ReactNode } from 'react'
import { en, type MessageKey, type Messages, type PluralKey } from './en'
import { makeFormat, type Format } from './format'
import { fr } from './fr'

export const CATALOGUES = { en, fr } satisfies Record<string, Messages>
export type Lang = keyof typeof CATALOGUES
/** What a user can choose: a language code, or 'auto' for the browser's. */
export type LanguageChoice = 'auto' | Lang

/** Each language named in itself, for the language menu. */
export const NAMES: Record<Lang, string> = { en: 'English', fr: 'Français' }

const isLang = (code: string): code is Lang => code in CATALOGUES

/** The language to show: a valid stored choice, else the browser's first one Kura has, else English. */
export function pickLanguage(choice: string, browser: readonly string[]): Lang {
  if (isLang(choice)) return choice
  for (const tag of browser) {
    const main = tag.toLowerCase().split('-')[0]
    if (isLang(main)) return main
  }
  return 'en'
}

export type Vars = Record<string, string | number>

export interface I18n {
  lang: Lang
  t(key: MessageKey, vars?: Vars): string
  /** A counted message: picks `<key>.one`, `.other` (or the language's other forms) for `count`. */
  tn(key: PluralKey, count: number, vars?: Vars): string
  format: Format
}

const UNITS = ['unit.b', 'unit.kb', 'unit.mb', 'unit.gb', 'unit.tb', 'unit.pb'] as const

export function makeI18n(lang: Lang): I18n {
  const messages: Record<string, string> = CATALOGUES[lang]
  const plural = new Intl.PluralRules(lang)
  // A key the language lacks falls back to English, then to the key itself
  const t = (key: string, vars?: Vars) => {
    const text = messages[key] ?? (en as Record<string, string>)[key] ?? key
    if (!vars || !text.includes('{')) return text
    return text.replace(/\{(\w+)\}/g, (all, name: string) => (name in vars ? String(vars[name]) : all))
  }
  return {
    lang,
    t,
    tn: (key, count, vars) => {
      const form = `${key}.${plural.select(count)}`
      return t(form in messages ? form : `${key}.other`, { count, ...vars })
    },
    format: makeFormat(lang, UNITS.map((u) => messages[u])),
  }
}

const I18nContext = createContext<I18n>(makeI18n('en'))

export function I18nProvider({ lang, children }: { lang: Lang; children: ReactNode }) {
  const value = useMemo(() => makeI18n(lang), [lang])
  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export const useI18n = () => useContext(I18nContext)
export type { MessageKey, PluralKey }
