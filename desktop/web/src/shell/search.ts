/**
 * Ranking for the ⌘K launcher. Every word of the query must appear in the
 * title or subtitle; titles that start with the query rank first.
 */

export interface Entry {
  id: string
  title: string
  subtitle: string
  /** Heading the entry is listed under: "Apps", or the app whose section it is (translated). */
  section: string
  /** App to open. */
  app: string
  /** Section inside the app, if any. */
  view?: string
}

function score(entry: Entry, words: string[], query: string): number {
  const title = entry.title.toLowerCase()
  const text = `${title} ${entry.subtitle.toLowerCase()}`
  if (!words.every((w) => text.includes(w))) return 0
  if (title.startsWith(query)) return 4
  if (title.split(/\s+/).some((t) => t.startsWith(words[0]))) return 3
  if (title.includes(words[0])) return 2
  return 1
}

export function rankEntries(entries: Entry[], raw: string, limit = 8): Entry[] {
  const query = raw.trim().toLowerCase()
  if (!query) return entries.filter((x) => x.view === undefined).slice(0, limit)
  const words = query.split(/\s+/)
  return entries
    .map((entry, i) => ({ entry, i, s: score(entry, words, query) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .slice(0, limit)
    .map((x) => x.entry)
}
