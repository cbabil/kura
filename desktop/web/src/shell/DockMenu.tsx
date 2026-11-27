/**
 * An icon's menu in the dock, as on a Mac: Options ▸ (Keep in Dock, ticked
 * while kept, for an open app; Remove from Dock for a kept app that is not
 * open), then Open, or Quit for an open app. An open app that is not kept
 * stays in the dock until it quits, as on a Mac.
 */
import { useState, type KeyboardEvent } from 'react'
import { Box, Divider, Menu, MenuItem } from '@mui/material'
import { Glyph } from '../icons/Glyph'
import { useI18n } from '../i18n'

interface Props {
  /** The icon the menu is for, and its element; null while closed. */
  menu: { app: string; el: HTMLElement } | null
  kept: boolean
  running: boolean
  onClose(): void
  onOpen(app: string): void
  onQuit(app: string): void
  onKeep(app: string, keep: boolean): void
}

const ABOVE = { anchorOrigin: { vertical: 'top', horizontal: 'center' }, transformOrigin: { vertical: 'bottom', horizontal: 'center' } } as const
const BESIDE = { anchorOrigin: { vertical: 'top', horizontal: 'right' }, transformOrigin: { vertical: 'top', horizontal: 'left' } } as const
/** Room for the tick, so the items line up whether or not one is ticked. */
const TICK = 22

export function DockMenu({ menu, kept, running, onClose, onOpen, onQuit, onKeep }: Props) {
  const { t } = useI18n()
  const [options, setOptions] = useState<HTMLElement | null>(null)
  const close = () => {
    setOptions(null)
    onClose()
  }
  /** Runs `act` on the menu's app, then closes both menus. */
  const choose = (act: (app: string) => void) => () => {
    if (menu) act(menu.app)
    close()
  }
  const openOptions = (el: HTMLElement) => setOptions(el)

  return (
    <>
      <Menu open={Boolean(menu)} anchorEl={menu?.el} onClose={close} {...ABOVE}>
        <MenuItem aria-haspopup="menu" aria-expanded={Boolean(options)} onClick={(e) => openOptions(e.currentTarget)}
          onMouseEnter={(e) => openOptions(e.currentTarget)}
          onKeyDown={(e: KeyboardEvent<HTMLElement>) => e.key === 'ArrowRight' && openOptions(e.currentTarget)}
          sx={{ gap: 3, justifyContent: 'space-between' }}>
          {t('dock.options')}
          <Glyph name="chevron" size={14} />
        </MenuItem>
        <Divider />
        {running
          ? <MenuItem onClick={choose(onQuit)}>{t('dock.quit')}</MenuItem>
          : <MenuItem onClick={choose(onOpen)}>{t('dock.open')}</MenuItem>}
      </Menu>
      <Menu open={Boolean(menu && options)} anchorEl={options} onClose={() => setOptions(null)} {...BESIDE}>
        {running ? (
          <MenuItem role="menuitemcheckbox" aria-checked={kept} onClick={choose((app) => onKeep(app, !kept))} sx={{ pl: 1 }}>
            <Box sx={{ width: TICK, display: 'flex' }}>{kept && <Glyph name="check" size={16} />}</Box>
            {t('dock.keep')}
          </MenuItem>
        ) : (
          <MenuItem onClick={choose((app) => onKeep(app, false))} sx={{ pl: `${8 + TICK}px` }}>{t('dock.remove')}</MenuItem>
        )}
      </Menu>
    </>
  )
}
