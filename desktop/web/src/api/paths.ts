/** Paths as Files writes them: absolute, parts joined by '/'. */

/** `name` inside the folder `dir`. */
export const joinPath = (dir: string, name: string) => (dir === '/' ? `/${name}` : `${dir}/${name}`)

/** The folder a path is in ('/' for the root's own entries). */
export const parentOf = (path: string) => path.slice(0, path.lastIndexOf('/')) || '/'

/** The last name of a path. */
export const baseName = (path: string) => path.slice(path.lastIndexOf('/') + 1)
