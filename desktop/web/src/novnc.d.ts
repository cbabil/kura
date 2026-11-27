/** The part of noVNC's RFB client (MPL-2.0) the Browser app uses; noVNC ships no types. */
declare module '@novnc/novnc' {
  interface RfbEvents {
    connect: Event
    disconnect: CustomEvent<{ clean: boolean }>
    clipboard: CustomEvent<{ text: string }>
  }
  export default class RFB extends EventTarget {
    constructor(target: HTMLElement, urlOrChannel: string | object, options?: { shared?: boolean })
    resizeSession: boolean
    focusOnClick: boolean
    background: string
    focus(): void
    disconnect(): void
    clipboardPasteFrom(text: string): void
    /** Sends one key press or release: an X keysym and the DOM code. */
    sendKey(keysym: number, code: string | null, down?: boolean): void
    addEventListener<K extends keyof RfbEvents>(type: K, listener: (event: RfbEvents[K]) => void): void
  }
}
