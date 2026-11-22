/**
 * The languages Kura Desktop has. English is the source and French was
 * written with it; both are part of the page. The others were translated by
 * machine from English (2026-11) and are fetched when chosen: corrections
 * from people who speak them are welcome. Hebrew is shown in the
 * left-to-right layout: a mirrored desktop is not done.
 * Adding a language: locales/<code>.json and one line in NAMES.
 */
import { en, type Messages } from './en'
import { fr } from './fr'

/** Each language named in itself, for the language menu. */
export const NAMES = {
  en: 'English', fr: 'Français', bn: 'বাংলা', ca: 'Català', cs: 'Čeština', de: 'Deutsch', es: 'Español', ga: 'Gaeilge',
  he: 'עברית', hu: 'Magyar', it: 'Italiano', ja: '日本語', ka: 'ქართული', ko: '한국어', nl: 'Nederlands', pl: 'Polski',
  pt: 'Português', 'pt-BR': 'Português (Brasil)', ro: 'Română', ru: 'Русский', sk: 'Slovenčina', sl: 'Slovenščina',
  tr: 'Türkçe', uk: 'Українська', zh: '简体中文', 'zh-TW': '繁體中文',
} as const
export type Lang = keyof typeof NAMES

export const isLang = (code: string): code is Lang => code in NAMES

/** The catalogues that are part of the page. */
export const BUNDLED: Partial<Record<Lang, Messages>> = { en, fr }

/** The others, each a file of its own that is fetched once. */
const files = import.meta.glob<{ default: Record<string, string> }>('./locales/*.json')
const fetched = new Map<Lang, Record<string, string>>()

/** The languages that have a file (every one but the bundled). */
export const FETCHED_CODES = Object.keys(files).map((path) => path.slice('./locales/'.length, -'.json'.length))

/** A language's catalogue if it is at hand: bundled, or fetched before. */
export function catalogueOf(lang: Lang): Record<string, string> | undefined {
  return BUNDLED[lang] ?? fetched.get(lang)
}

/** Fetches a language's catalogue (at once for one at hand). Rejects when it cannot be had. */
export async function loadCatalogue(lang: Lang): Promise<Record<string, string>> {
  const known = catalogueOf(lang)
  if (known) return known
  const load = files[`./locales/${lang}.json`]
  if (!load) throw new Error(`no catalogue for ${lang}`)
  const messages = (await load()).default
  fetched.set(lang, messages)
  return messages
}
