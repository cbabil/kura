/**
 * English: the source catalogue. Every other language must have exactly
 * these keys (the type system and i18n.test.tsx enforce it) and the same
 * {placeholders}. Counted messages come as `<key>.one` and `<key>.other`;
 * a language with more plural forms (few, many, two, zero) adds those keys
 * too. Keys are grouped by where they appear.
 */
import { apps } from './en.apps'
import { catalog } from './en.catalog'
import { files } from './en.files'
import { settings } from './en.settings'

export const en = {
  // Brand (the name and the kanji stay as they are in every language)
  'brand.kicker': 'THE STOREHOUSE',
  'brand.tagline': 'The lightweight OS for your home server.',

  // Sign-in
  'signin.form': 'Sign in',
  'signin.user': 'User name',
  'signin.password': 'Password',
  'signin.submit': 'Sign in',
  'signin.busy': 'Signing in…',
  'signin.wrong': 'Wrong user name or password.',
  'signin.expired': 'This password must be changed first. Set a new one at the console or over SSH, then sign in here.',
  'signin.rate': 'Too many attempts. Wait a moment and try again.',
  'signin.network': 'Cannot reach the server. Check that it is on and try again.',
  'signin.wait': '({seconds} s)',
  'signin.same': 'Same user and password as the console and SSH.',
  'signin.cert': "Check the certificate fingerprint against the one on the device's login screen.",

  // Menu bar
  'menu.kura': 'Kura menu',
  'menu.about': 'About Kura',
  'menu.language': 'Language…',
  'menu.signOut': 'Sign Out {name}',
  'menu.restart': 'Restart…',
  'menu.shutdown': 'Shut Down…',
  'menu.file': 'File',
  'menu.view': 'View',
  'menu.window': 'Window',
  'menu.help': 'Help',
  'menu.edit': 'Edit',
  'menu.closeWindow': 'Close Window',
  'menu.quitBrowser': 'Quit Browser',
  'menu.pasteText': 'Paste Text…',
  'menu.minimize': 'Minimize',
  'menu.zoom': 'Zoom',
  'menu.desktopHelp': 'Kura Desktop Help',
  'status.temp': 'CPU temperature',
  'status.tempShort': 'CPU {degrees}°',
  'status.connected': 'Connected to the server',
  'status.disconnected': 'Not connected',
  'status.online': 'Online',
  'status.offline': 'Offline',
  'status.light': 'Use light theme',
  'status.dark': 'Use dark theme',
  'status.search': 'Search (Ctrl K)',
  'status.update': 'Kura {version} is available',
  'status.restartDue': 'A restart is needed to finish an update',
  'status.updateShort': 'Update {version}',
  'status.restartShort': 'Restart needed',

  // Restart and shut down
  'power.restart.title': 'Restart this server?',
  'power.shutdown.title': 'Shut down this server?',
  'power.restart.text': 'Everything running on it stops for a moment. Containers set to restart come back by themselves.',
  'power.shutdown.text': 'Everything running on it stops. To start it again you will need to be at the machine.',
  'power.restart.confirm': 'Restart',
  'power.shutdown.confirm': 'Shut Down',
  'power.cancel': 'Cancel',
  'power.restart.going': 'The server is restarting. This page comes back by itself when it has.',
  'power.shutdown.going': 'The server is shutting down. You can close this page.',
  'power.failed': 'The server did not do it. Try again, or use the console.',

  // Windows and dock
  'window.close': 'Close',
  'window.minimize': 'Minimize',
  'window.zoom': 'Zoom',
  'dock.label': 'Dock',
  'dock.minimised': '{name} (minimised)',
  'dock.open': 'Open',
  'dock.remove': 'Remove from Dock',
  'dock.keep': 'Keep in Dock',
  'dock.options': 'Options',
  'dock.quit': 'Quit',
  'comingSoon': 'Arrives in a coming update of Kura.',
  'layout.notSaved': 'Your desktop layout could not be saved. It will be tried again on the next change.',

  // Launcher
  'launcher.label': 'Search',
  'launcher.placeholder': 'Search apps and sections',
  'launcher.apps': 'Apps',
  'launcher.section': '{app} section',
  'launcher.none': 'Nothing matches “{query}”',
  'launcher.open': '↵ open',

  // About and language
  'about.version': 'Version',
  'about.host': 'Host',
  'about.kernel': 'Kernel',
  'about.processor': 'Processor',
  'about.cores.one': '{arch} · {count} core',
  'about.cores.other': '{arch} · {count} cores',
  'about.memory': 'Memory',
  'language.title': 'Language',
  'language.auto': 'Automatic ({language})',
  'language.done': 'Done',

  // Apps
  'app.activity.name': 'Activity Monitor',
  'app.activity.blurb': 'CPU, memory, storage, network and services',
  'app.containers.name': 'Containers',
  'app.containers.blurb': 'Docker apps and compose stacks',
  'app.terminal.name': 'Terminal',
  'app.terminal.blurb': 'A shell on this server, in a window',
  'app.files.name': 'Files',
  'app.files.blurb': 'Browse, upload and download your data',
  'app.console.name': 'Console',
  'app.console.blurb': 'The system logs',
  'app.settings.name': 'Settings',
  'app.settings.blurb': 'Network, users, time, storage and updates',
  'app.catalog.name': 'App Catalog',
  'app.catalog.blurb': 'Install apps in one click',
  'app.browser.name': 'Browser',
  'app.browser.blurb': 'Your own web browser, running on this server',
  'app.trash.name': 'Trash',
  'app.trash.blurb': 'Deleted files, kept until you empty it',

  // Activity Monitor
  'activity.view.Summary': 'Summary',
  'activity.view.CPU': 'CPU',
  'activity.view.Memory': 'Memory',
  'activity.view.Storage': 'Storage',
  'activity.view.Network': 'Network',
  'activity.view.Services': 'Services',
  'activity.sections': 'Sections',
  'activity.range': 'Time range',
  'activity.waiting': 'Waiting for the first measurement…',
  'activity.cpu.one': 'CPU · {count} core',
  'activity.cpu.other': 'CPU · {count} cores',
  'activity.memory': 'Memory · {total}',
  'activity.storage': 'Storage · {total}',
  'activity.network': 'Network',
  'activity.used': 'used',
  'activity.down': 'down',
  'activity.apps': 'Apps',
  'activity.appsSize': 'Apps {size}',
  'activity.cache': 'Cache',
  'activity.cacheSize': 'Cache {size}',
  'activity.appsAndCache': 'Apps and cache',
  'activity.free': 'Free',
  'activity.volumes.one': '{count} volume',
  'activity.volumes.other': '{count} volumes',
  'activity.volumesTitle': 'Volumes',
  'activity.of': '{used} of {size}',
  'activity.now': 'Now',
  'activity.average': 'Average',
  'activity.peak': 'Peak',
  'activity.download': 'Download',
  'activity.upload': 'Upload',
  'activity.cpuHistory': 'CPU history',
  'activity.memoryHistory': 'Memory history',
  'activity.networkHistory': 'Network history',
  'activity.busiest': 'Busiest processes',
  'activity.col.process': 'Process',
  'activity.col.user': 'User',
  'activity.col.pid': 'PID',
  'activity.col.cpu': 'CPU',
  'activity.col.memory': 'Memory',
  'activity.col.service': 'Service',
  'activity.col.state': 'State',
  'activity.col.for': 'For',
  'activity.services': 'Services',
  'activity.used.meter': '{mount} used',
  'state.active': 'active',
  'state.inactive': 'inactive',
  'state.failed': 'failed',
  'state.activating': 'starting',
  'state.deactivating': 'stopping',

  ...apps,
  ...catalog,
  ...files,
  ...settings,

  // Size units, smallest first (binary multiples)
  'unit.b': 'B',
  'unit.kb': 'KB',
  'unit.mb': 'MB',
  'unit.gb': 'GB',
  'unit.tb': 'TB',
  'unit.pb': 'PB',
} as const

export type MessageKey = keyof typeof en
/** Keys of counted messages, without their `.one` / `.other` ending. */
export type PluralKey = MessageKey extends infer K ? (K extends `${infer B}.other` ? B : never) : never
/** A catalogue for another language: every key, translated. */
export type Messages = Record<MessageKey, string>
