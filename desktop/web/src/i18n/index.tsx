/**
 * Kura Desktop's languages. English and French are part of the page; the
 * others (locales/<code>.json, translated by machine: see languages.ts) are
 * fetched when chosen. Each catalogue has every key of en.ts; the language
 * is the user's choice, or the browser's first one Kura has, or English.
 * Numbers, sizes, dates and plurals follow the language.
 */
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { en, type MessageKey, type PluralKey } from './en'
import { makeFormat, type Format } from './format'
import { catalogueOf, isLang, loadCatalogue, NAMES, type Lang } from './languages'

export { NAMES, loadCatalogue }
export type { Lang }
/** What a user can choose: a language code, or 'auto' for the browser's. */
export type LanguageChoice = 'auto' | Lang

/** Browser tags that mean a catalogue under another name. */
const ALIASES: Record<string, Lang> = { 'zh-hant': 'zh-TW', 'zh-hk': 'zh-TW', 'zh-mo': 'zh-TW', 'zh-hans': 'zh', 'zh-cn': 'zh', 'zh-sg': 'zh' }

/** The catalogue for one browser tag: itself, its alias, or its main part ("pt-PT" is "pt", "pt-BR" its own). */
function langOf(tag: string): Lang | null {
  const lower = tag.toLowerCase()
  const exact = Object.keys(NAMES).find((code) => code.toLowerCase() === lower)
  const alias = Object.entries(ALIASES).find(([prefix]) => lower === prefix || lower.startsWith(`${prefix}-`))?.[1]
  const main = lower.split('-')[0]
  return (exact as Lang | undefined) ?? alias ?? (isLang(main) ? main : null)
}

/** The language to show: a valid stored choice, else the browser's first one Kura has, else English. */
export function pickLanguage(choice: string, browser: readonly string[]): Lang {
  if (isLang(choice)) return choice
  for (const tag of browser) {
    const lang = langOf(tag)
    if (lang) return lang
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

/** `messages` is the language's catalogue; without it (not fetched yet) the words are English. */
export function makeI18n(lang: Lang, messages: Record<string, string> = catalogueOf(lang) ?? en): I18n {
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
  // Counts the catalogues that arrived, so the words follow once theirs has.
  const [arrived, setArrived] = useState(0)
  useEffect(() => {
    let live = true
    // A catalogue that cannot be fetched leaves the desktop in English.
    if (!catalogueOf(lang)) loadCatalogue(lang).then(() => live && setArrived((n) => n + 1), () => {})
    return () => {
      live = false
    }
  }, [lang])
  // eslint-disable-next-line react-hooks/exhaustive-deps -- `arrived` says the catalogue is there now
  const value = useMemo(() => makeI18n(lang), [lang, arrived])
  useEffect(() => {
    document.documentElement.lang = lang
  }, [lang])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export const useI18n = () => useContext(I18nContext)
export type { MessageKey, PluralKey }
