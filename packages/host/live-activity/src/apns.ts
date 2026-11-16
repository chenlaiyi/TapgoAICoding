/** APNs client for ActivityKit push updates: ES256 provider tokens and HTTP/2 delivery. */

import { createSign, randomUUID } from 'node:crypto'
import { connect } from 'node:http2'

/** Content state shared with the iOS app's ActivityAttributes. */
export interface LiveActivityContentState {
  /** Turn start in epoch seconds; the widget renders it as a system timer. */
  readonly startedAt: number
  /** Current work summary. */
  readonly detail: string
  /** Whether the turn still runs. */
  readonly running: boolean
}

/** Options resolved once per Host activation. */
export interface ApnsOptions {
  readonly bundleId: string
  readonly teamId: string
  readonly keyId: string
  readonly privateKey: string
  readonly environment: 'development' | 'production'
  /** Seconds after which iOS may treat the pushed state as stale. */
  readonly staleSeconds?: number
}

/** Outcome of one push attempt. */
export type ApnsOutcome = 'ok' | 'unregistered' | 'failed'

const AUTHORITY = {
  development: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
} as const

/** Live Activity updates use the bundle's liveactivity topic.
 * @param bundleId - App bundle identifier.
 * @returns The APNs topic that routes pushes to the Live Activity extension.
 */
export function liveActivityTopic(bundleId: string): string {
  return `${bundleId}.push-type.liveactivity`
}

function base64url(value: Buffer | string): string {
  return Buffer.from(value).toString('base64url')
}

/** Read one byte from a DER signature, failing on truncation. */
function byteAt(der: Buffer, offset: number): number {
  const value = der[offset]
  if (value === undefined) throw new Error('apns: truncated DER signature')
  return value
}

/**
 * Convert an ASN.1 DER ECDSA signature into the fixed-width JOSE form ES256 requires.
 * @param der - DER-encoded signature from `crypto.sign`.
 * @param size - Bytes per curve coordinate; 32 for P-256.
 * @returns The raw `r || s` signature.
 */
export function derToJose(der: Buffer, size = 32): Buffer {
  let offset = 0
  if (byteAt(der, offset) !== 0x30) throw new Error('apns: signature is not a DER sequence')
  offset += 1
  const lengthByte = byteAt(der, offset)
  offset += 1
  if ((lengthByte & 0x80) !== 0) offset += lengthByte & 0x7f
  if (byteAt(der, offset) !== 0x02) throw new Error('apns: signature has no r integer')
  offset += 1
  const rLength = byteAt(der, offset)
  offset += 1
  const r = der.subarray(offset, offset + rLength)
  offset += rLength
  if (byteAt(der, offset) !== 0x02) throw new Error('apns: signature has no s integer')
  offset += 1
  const sLength = byteAt(der, offset)
  offset += 1
  const s = der.subarray(offset, offset + sLength)
  const raw = Buffer.alloc(size * 2)
  const rTrimmed = r.length > size ? r.subarray(r.length - size) : r
  const sTrimmed = s.length > size ? s.subarray(s.length - size) : s
  rTrimmed.copy(raw, size - rTrimmed.length)
  sTrimmed.copy(raw, size * 2 - sTrimmed.length)
  return raw
}

/**
 * Build one APNs provider token.
 * @param teamId - Apple developer team identifier.
 * @param keyId - Key identifier of the APNs .p8 key.
 * @param privateKey - PEM contents of that key.
 * @param issuedAt - Token issue time in seconds.
 * @returns Signed ES256 JWT.
 */
export function apnsJwt(teamId: string, keyId: string, privateKey: string, issuedAt: number): string {
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }))
  const claims = base64url(JSON.stringify({ iss: teamId, iat: issuedAt }))
  const signingInput = `${header}.${claims}`
  const der = createSign('SHA256').update(signingInput).sign({ key: privateKey })
  return `${signingInput}.${base64url(derToJose(der))}`
}

/**
 * Build the APNs update payload for one activity state.
 * @param state - Content state the widget decodes.
 * @param now - Push timestamp in epoch seconds.
 * @param staleSeconds - Age after which iOS may treat the state as stale.
 * @returns JSON payload body.
 */
export function updatePayload(state: LiveActivityContentState, now: number, staleSeconds: number): string {
  return JSON.stringify({
    aps: {
      timestamp: now,
      event: 'update',
      'content-state': state,
      'stale-date': now + staleSeconds,
    },
  })
}

/**
 * Build the APNs end payload for one activity state; the system removes it after the dismissal delay.
 * @param state - Final content state the widget decodes.
 * @param now - Push timestamp in epoch seconds.
 * @returns JSON payload body.
 */
export function endPayload(state: LiveActivityContentState, now: number): string {
  return JSON.stringify({
    aps: {
      timestamp: now,
      event: 'end',
      'content-state': state,
      'dismissal-date': now + 60,
    },
  })
}

/**
 * Validate one ActivityKit push token.
 * @param token - Hex token reported by the iOS app.
 * @returns True for an even-length hex token of at least 32 bytes.
 */
export function isPushToken(token: string): boolean {
  return /^(?:[0-9a-f]{2}){32,}$/iu.test(token) && token.length % 2 === 0
}

/** One APNs request, injectable for tests. */
export type ApnsTransport = (
  options: ApnsOptions,
  headers: Readonly<Record<string, string>>,
  token: string,
  body: string,
) => Promise<{ status: number; reason?: string }>

const transport: ApnsTransport = (options, headers, token, body) => new Promise((resolve, reject) => {
  const session = connect(AUTHORITY[options.environment])
  let settled = false
  const finish = (value: { status: number; reason?: string }): void => {
    if (settled) return
    settled = true
    session.close()
    resolve(value)
  }
  session.once('error', (error) => { if (!settled) { settled = true; session.close(); reject(error) } })
  const request = session.request({
    ':method': 'POST',
    ':path': `/3/device/${token}`,
    ...headers,
  })
  let status = 0
  let reason: string | undefined
  request.on('response', (responseHeaders) => {
    status = Number(responseHeaders[':status'] ?? 0)
    const header = responseHeaders['apns-reason']
    if (typeof header === 'string') reason = header
  })
  request.setEncoding('utf8')
  request.on('data', (chunk: string) => {
    if (reason !== undefined || chunk.trim() === '') return
    try { reason = String(Reflect.get(JSON.parse(chunk), 'reason')) } catch { reason = undefined }
  })
  request.on('end', () => { finish({ status, ...(reason === undefined ? {} : { reason }) }) })
  request.on('error', (error) => { if (!settled) { settled = true; session.close(); reject(error) } })
  request.end(body)
})

/**
 * Create the sender bound to one activation's credentials.
 * @param options - APNs topic and signing credentials.
 * @param send - transport override for tests.
 * @returns Sender for update and end payloads.
 */
export function createApnsSender(options: ApnsOptions, send: ApnsTransport = transport): {
  update(token: string, state: LiveActivityContentState, now?: number): Promise<ApnsOutcome>
  end(token: string, state: LiveActivityContentState, now?: number): Promise<ApnsOutcome>
} {
  let cached: { token: string; issuedAt: number } | undefined
  const authorization = (now: number): string => {
    if (cached !== undefined && now - cached.issuedAt < 45 * 60) return cached.token
    const token = apnsJwt(options.teamId, options.keyId, options.privateKey, now)
    cached = { token, issuedAt: now }
    return token
  }
  const deliver = async (token: string, body: string, now: number): Promise<ApnsOutcome> => {
    try {
      const result = await send(options, {
        authorization: `bearer ${authorization(now)}`,
        'apns-topic': liveActivityTopic(options.bundleId),
        'apns-push-type': 'liveactivity',
        'apns-priority': '5',
        'apns-id': randomUUID(),
        'content-type': 'application/json',
      }, token, body)
      if (result.status === 200) return 'ok'
      if (result.status === 410 || result.reason === 'Unregistered' || result.reason === 'BadDeviceToken') {
        return 'unregistered'
      }
      return 'failed'
    } catch {
      return 'failed'
    }
  }
  return {
    update: (token, state, now = Math.floor(Date.now() / 1000)) =>
      deliver(token, updatePayload(state, now, options.staleSeconds ?? 120), now),
    end: (token, state, now = Math.floor(Date.now() / 1000)) =>
      deliver(token, endPayload(state, now), now),
  }
}
