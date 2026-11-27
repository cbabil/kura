/**
 * The mock build's shared Browser: a small VNC server in the page that
 * speaks just enough RFB 3.8 for noVNC (no security, raw pixels) and draws
 * one still page, so the Browser app can be seen and tested with no device.
 */
import type { BrowserChannel } from './types'

/** The mock screen and the colours of what it draws (r, g, b). */
export const MOCK_SCREEN = { width: 1024, height: 640 }
export const MOCK_COLOURS = {
  tabs: [222, 225, 230],
  page: [255, 255, 255],
  heading: [145, 70, 255],
  text: [107, 114, 128],
} as const
type Colour = readonly [number, number, number]

/** The page as solid rectangles: x, y, width, height, colour. */
const PAGE: [number, number, number, number, Colour][] = [
  [0, 0, 1024, 72, MOCK_COLOURS.tabs],
  [0, 72, 1024, 568, MOCK_COLOURS.page],
  [64, 120, 480, 48, MOCK_COLOURS.heading],
  ...[0, 1, 2, 3].map((i): [number, number, number, number, Colour] => [64, 200 + i * 32, 720 - i * 90, 14, MOCK_COLOURS.text]),
]
const NAME = new TextEncoder().encode('Kura Browser (mock)')

const u16 = (n: number) => [(n >> 8) & 255, n & 255]
const u32 = (n: number) => [(n >>> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]

/** One framebuffer update with every rectangle, in noVNC's pixel format (R, G, B, X); built once. */
function buildFrame(): Uint8Array {
  const head = [0, 0, ...u16(PAGE.length)]
  const size = head.length + PAGE.reduce((n, [, , w, h]) => n + 12 + w * h * 4, 0)
  const out = new Uint8Array(size)
  out.set(head)
  let at = head.length
  for (const [x, y, w, h, [r, g, b]] of PAGE) {
    out.set([...u16(x), ...u16(y), ...u16(w), ...u16(h), ...u32(0)], at)
    at += 12
    // Each pixel is the bytes r, g, b, 0: one 32-bit value in memory order.
    const pixel = new Uint32Array(Uint8Array.from([r, g, b, 0]).buffer)[0]
    new Uint32Array(out.buffer, at, w * h).fill(pixel)
    at += w * h * 4
  }
  return out
}
let frame: Uint8Array | null = null

/** How long a client message of `type` is, from what has come so far; 0 until it can tell, -1 for an unknown type. */
function messageLength(buf: Uint8Array): number {
  const need = (n: number) => (buf.length >= n ? n : 0)
  switch (buf[0]) {
    case 0: return need(20) // SetPixelFormat
    case 2: return buf.length < 4 ? 0 : need(4 + 4 * ((buf[2] << 8) | buf[3])) // SetEncodings
    case 3: return need(10) // FramebufferUpdateRequest
    case 4: return need(8) // KeyEvent
    case 5: return need(6) // PointerEvent
    case 6: return buf.length < 8 ? 0 : need(8 + ((buf[4] << 24) | (buf[5] << 16) | (buf[6] << 8) | buf[7])) // ClientCutText
    default: return -1
  }
}

/** A stand-in for the WebSocket to `/api/browser`, with the VNC server behind it. */
export class MockVncChannel implements BrowserChannel {
  binaryType = 'arraybuffer'
  readonly protocol = ''
  readyState = 0
  onopen: ((event: Event) => void) | null = null
  onmessage: ((event: MessageEvent) => void) | null = null
  onclose: ((event: CloseEvent) => void) | null = null
  onerror: ((event: Event) => void) | null = null
  /** What the viewer pasted, newest last. */
  readonly pasted: string[] = []
  /** How far the handshake is: an index into the steps below, then messages. */
  private step = 0
  private buf = new Uint8Array(0)
  /** The handshake: how many bytes the viewer sends at each step, and the answer. */
  private readonly handshake: [number, () => number[] | Uint8Array][] = [
    [12, () => [1, 1]], // its version; one security type: None
    [1, () => u32(0)], // its choice; SecurityResult: OK
    [1, () => { // ClientInit; ServerInit: the screen, a 32-bit true-colour format, the name
      const format = [32, 24, 0, 1, ...u16(255), ...u16(255), ...u16(255), 0, 8, 16, 0, 0, 0]
      return [...u16(MOCK_SCREEN.width), ...u16(MOCK_SCREEN.height), ...format, ...u32(NAME.length), ...NAME]
    }],
  ]

  constructor() {
    setTimeout(() => {
      this.readyState = 1
      this.onopen?.(new Event('open'))
      this.reply(new TextEncoder().encode('RFB 003.008\n'))
    }, 0)
  }

  send(data: ArrayBuffer | ArrayBufferView): void {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    const joined = new Uint8Array(this.buf.length + bytes.length)
    joined.set(this.buf)
    joined.set(bytes, this.buf.length)
    this.buf = joined
    this.read()
  }

  close(): void {
    if (this.readyState === 3) return
    this.readyState = 3
    setTimeout(() => this.onclose?.(new CloseEvent('close', { code: 1000, wasClean: true })), 0)
  }

  private reply(bytes: Uint8Array | number[]) {
    if (this.readyState !== 1) return
    // The page's frame is shared: the viewer gets its own copy.
    const data = Uint8Array.from(bytes).buffer
    setTimeout(() => this.onmessage?.(new MessageEvent('message', { data })), 0)
  }

  private take(n: number): Uint8Array {
    const head = this.buf.slice(0, n)
    this.buf = this.buf.slice(n)
    return head
  }

  private read() {
    while (this.step < this.handshake.length) {
      const [length, answer] = this.handshake[this.step]
      if (this.buf.length < length) return
      this.take(length)
      this.step++
      this.reply(answer())
    }
    while (this.buf.length > 0) {
      const n = messageLength(this.buf)
      if (n < 0) return this.close()
      if (n === 0) return
      this.handle(this.take(n))
    }
  }

  private handle(message: Uint8Array) {
    // A full (not incremental) request gets the page; incremental ones see no change.
    if (message[0] === 3 && message[1] === 0) this.reply((frame ??= buildFrame()))
    if (message[0] === 6) this.pasted.push(new TextDecoder('latin1').decode(message.slice(8)))
  }
}
