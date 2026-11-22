/**
 * The JSON contract of Files and Trash (ADR-031): what kura-desktopd passes
 * on from the signed-in user's own file agent (kura-desktop-core's files.rs).
 */

/** One entry of a folder. */
export interface FileEntry {
  name: string
  /** A folder, or a link to one. */
  dir: boolean
  link: boolean
  /** Bytes; 0 for a folder. */
  size: number
  /** Unix time in seconds of the last change. */
  modified: number
}

/** GET /api/files: a folder, and the user's home folder. */
export interface Folder {
  path: string
  home: string
  entries: FileEntry[]
  /** The folder holds more than the server lists. */
  truncated: boolean
}

/** One thing in the trash. */
export interface Trashed {
  /** Its name in the trash, which restoring takes. */
  name: string
  /** Where it was. */
  path: string
  dir: boolean
  size: number
  /** Unix time in seconds it was put there. */
  deleted: number
}

/** One change, POSTed to /api/files. Nothing that exists is ever written over. */
export type FileChange =
  | { op: 'make-dir'; path: string }
  | { op: 'rename'; from: string; to: string }
  | { op: 'copy'; from: string; to: string }
  /** For good. */
  | { op: 'delete'; path: string }
  | { op: 'trash'; path: string }
  | { op: 'restore'; name: string }
  | { op: 'empty-trash' }
