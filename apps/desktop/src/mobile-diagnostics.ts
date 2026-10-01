/** Checks the same public authentication and WebSocket path used by iPhone. */

import WebSocket from 'ws'

/** Stage at which the public mobile connection last failed. */
export type MobileConnectionState = 'connected' | 'network' | 'tls' | 'relay' | 'authentication' | 'websocket'

/** Result contains no pairing URL, cookie, or server response body. */
export interface MobileConnectionDiagnostic {
  readonly state: MobileConnectionState
  readonly checkedAt: number
}

type Exchange = (url: string, signal: AbortSignal) => Promise<{ status: number; cookie: string | null }>
type Upgrade = (url: string, cookie: string, signal: AbortSignal) => Promise<void>

const DEADLINE_MS = 8_000

async function exchange(url: string, signal: AbortSignal): Promise<{ status: number; cookie: string | null }> {
  const response = await fetch(url, { redirect: 'manual', cache: 'no-store', signal })
  return { status: response.status, cookie: response.headers.get('set-cookie') }
}

function upgrade(url: string, cookie: string, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url, { headers: { Cookie: cookie }, handshakeTimeout: DEADLINE_MS })
    const stop = (): void => { socket.terminate(); reject(new Error('cancelled')) }
    signal.addEventListener('abort', stop, { once: true })
    socket.once('open', () => {
      signal.removeEventListener('abort', stop)
      socket.close()
      resolve()
    })
    socket.once('error', (error) => {
      signal.removeEventListener('abort', stop)
      reject(error)
    })
    socket.once('unexpected-response', (_request, response) => {
      signal.removeEventListener('abort', stop)
      response.resume()
      socket.terminate()
      reject(new Error(`HTTP ${String(response.statusCode)}`))
    })
  })
}

function transportFailure(error: unknown): MobileConnectionState {
  if (typeof error !== 'object' || error === null) return 'relay'
  const candidate = error as { code?: unknown; cause?: { code?: unknown } }
  const code = candidate.code ?? candidate.cause?.code
  if (typeof code === 'string' && /CERT|TLS|SSL/u.test(code)) return 'tls'
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') return 'network'
  return 'relay'
}

/** Probe public routing, token exchange, and authenticated WebSocket upgrade.
 * @param pairingUrl - Host-issued HTTPS pairing URL, kept only in memory.
 * @param send - exchange transport for isolated tests.
 * @param connect - WebSocket transport for isolated tests.
 * @returns the first failed stage, or connected after all three stages succeed.
 */
export async function probeMobileConnection(
  pairingUrl: string,
  send: Exchange = exchange,
  connect: Upgrade = upgrade,
): Promise<MobileConnectionDiagnostic> {
  const origin = new URL(pairingUrl)
  if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.searchParams.getAll('token').length !== 1) {
    throw new Error('Invalid mobile pairing URL')
  }
  const checkedAt = Date.now()
  const controller = new AbortController()
  const deadline = setTimeout(() => { controller.abort() }, DEADLINE_MS)
  try {
    let response: Awaited<ReturnType<Exchange>>
    try { response = await send(pairingUrl, controller.signal) }
    catch (error) { return { state: transportFailure(error), checkedAt } }
    if (response.status === 401 || response.status === 403) return { state: 'authentication', checkedAt }
    if (response.status === 502 || response.status === 503 || response.status === 504) return { state: 'relay', checkedAt }
    if (response.status !== 303 || response.cookie === null) return { state: 'authentication', checkedAt }
    const cookie = response.cookie.split(';', 1)[0]
    if (cookie === undefined || cookie.length === 0) return { state: 'authentication', checkedAt }
    const socketUrl = new URL(origin)
    socketUrl.protocol = 'wss:'
    socketUrl.pathname = '/api/remote.mux'
    socketUrl.search = ''
    try { await connect(socketUrl.href, cookie, controller.signal) }
    catch { return { state: 'websocket', checkedAt } }
    return { state: 'connected', checkedAt }
  } finally {
    clearTimeout(deadline)
    controller.abort()
  }
}
