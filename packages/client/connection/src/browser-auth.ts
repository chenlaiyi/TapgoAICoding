/** Browser-session authentication for the Host Connection carrier. */

import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto'
import { credentialKey } from '@deepseek-ai/dsh-credentials'
import type { CredentialProvider, CredentialRecord } from '@deepseek-ai/dsh-credentials'
import type {
  ConnectionIndexRequest,
  ConnectionIndexResponse,
  ConnectionTrustRequest,
} from './rpc.ts'

const AUTH_RECORD_KEY = credentialKey('client-connection', 'browser-session')
const MOBILE_RECORD_KEY = credentialKey('client-connection', 'mobile-pairings')
const DAY_MILLISECONDS = 24 * 60 * 60 * 1000
const SECRET_BYTES = 32
const TOKEN_QUERY = 'token'
const COOKIE_PREFIX = 'dsh-auth-'
const COOKIE_PAYLOAD_VERSION = 1
const STORED_SECRET_VERSION = 1
const BASE64URL_PATTERN = /^[A-Za-z0-9_-]*$/
const PROCESS_LAUNCH_TOKENS = new WeakMap<object, string>()

interface StoredSecretPayload {
  readonly version: typeof STORED_SECRET_VERSION
  readonly secret: string
}

interface BrowserCookiePayload {
  readonly version: typeof COOKIE_PAYLOAD_VERSION
  readonly authority: string
  readonly issuedAt: number
  readonly expiresAt: number
  readonly pairingId?: string
}

interface MobilePairingRecord {
  readonly id: string
  readonly name: string
  readonly authority: string
  readonly tokenHash: string
  readonly createdAt: number
}

interface StoredMobilePairings {
  readonly version: 1
  readonly entries: readonly MobilePairingRecord[]
}

/** Public metadata for one independently revocable mobile pairing. */
export type MobilePairing = Omit<MobilePairingRecord, 'tokenHash'>

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function encodeBase64Url(value: Uint8Array): string {
  return Buffer.from(value).toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/u, '')
}

function decodeBase64Url(value: string): Buffer | undefined {
  if (!BASE64URL_PATTERN.test(value) || value.length % 4 === 1) return undefined
  const padding = '='.repeat((4 - value.length % 4) % 4)
  const decoded = Buffer.from(value.replaceAll('-', '+').replaceAll('_', '/') + padding, 'base64')
  return encodeBase64Url(decoded) === value ? decoded : undefined
}

function processLaunchToken(owner: object): string {
  const existing = PROCESS_LAUNCH_TOKENS.get(owner)
  if (existing !== undefined) return existing
  const created = encodeBase64Url(randomBytes(SECRET_BYTES))
  PROCESS_LAUNCH_TOKENS.set(owner, created)
  return created
}

function header(
  headers: ConnectionTrustRequest['headers'],
  name: string,
): string | undefined {
  if (headers instanceof Headers) return headers.get(name) ?? undefined
  const value = headers[name]
  return typeof value === 'string' ? value : undefined
}

/** Canonical request authority used as the cookie name and signed audience. */
function requestAuthority(headers: ConnectionTrustRequest['headers']): string | undefined {
  const host = header(headers, 'host')
  if (host === undefined) return undefined
  try {
    return new URL(`http://${host}`).host
  } catch {
    return undefined
  }
}

function canonicalSecret(value: unknown): Buffer | undefined {
  if (typeof value !== 'string') return undefined
  const decoded = decodeBase64Url(value)
  if (decoded === undefined || decoded.byteLength !== SECRET_BYTES) return undefined
  return decoded
}

function storedSecret(record: CredentialRecord | undefined): Buffer | undefined {
  if (record === undefined) return undefined
  if (record.kind !== 'grant' || !isRecord(record.payload)
    || record.payload.version !== STORED_SECRET_VERSION) {
    throw new Error('client-connection: browser-session credential record has an unsupported format')
  }
  const secret = canonicalSecret(record.payload.secret)
  if (secret === undefined) {
    throw new Error('client-connection: browser-session credential record has an invalid secret')
  }
  return secret
}

function tokenMatches(actual: string, expected: string): boolean {
  const actualBytes = Buffer.from(actual, 'utf8')
  const expectedBytes = Buffer.from(expected, 'utf8')
  return actualBytes.byteLength === expectedBytes.byteLength && timingSafeEqual(actualBytes, expectedBytes)
}

function cookieName(authority: string): string {
  return COOKIE_PREFIX + encodeBase64Url(createHash('sha256').update(authority).digest())
}

/** Read the exact generated cookie without implementing general Cookie decoding. */
function cookieValue(headerValue: string, name: string): string | undefined {
  for (const segment of headerValue.split(';')) {
    const at = segment.indexOf('=')
    if (at === -1 || segment.slice(0, at).trim() !== name) continue
    return segment.slice(at + 1).trim()
  }
  return undefined
}

/** Serialize the fixed browser-session attributes; generated names and values are cookie-safe base64url. */
function sessionCookie(name: string, value: string, expiresAt: number, maxAgeSeconds: number): string {
  return `${name}=${value}; Max-Age=${String(maxAgeSeconds)}; Path=/; Expires=${new Date(expiresAt).toUTCString()}; HttpOnly; SameSite=Strict`
}

function signature(secret: Buffer, body: string): Buffer {
  return createHmac('sha256', secret).update(body).digest()
}

function encodeCookie(payload: BrowserCookiePayload, secret: Buffer): string {
  const body = encodeBase64Url(Buffer.from(JSON.stringify(payload), 'utf8'))
  return `v1.${body}.${encodeBase64Url(signature(secret, body))}`
}

function decodeCookie(value: string, secret: Buffer): BrowserCookiePayload | undefined {
  const parts = value.split('.')
  const [version, body, encodedSignature] = parts
  if (parts.length !== 3 || version !== 'v1' || body === undefined || encodedSignature === undefined) {
    return undefined
  }
  const actualSignature = decodeBase64Url(encodedSignature)
  if (actualSignature === undefined) return undefined
  const expectedSignature = signature(secret, body)
  if (actualSignature.byteLength !== expectedSignature.byteLength
    || !timingSafeEqual(actualSignature, expectedSignature)) return undefined
  let decoded: unknown
  try {
    const bodyBytes = decodeBase64Url(body)
    if (bodyBytes === undefined) return undefined
    decoded = JSON.parse(bodyBytes.toString('utf8'))
  } catch {
    return undefined
  }
  if (!isRecord(decoded)
    || decoded.version !== COOKIE_PAYLOAD_VERSION
    || typeof decoded.authority !== 'string'
    || (decoded.pairingId !== undefined && typeof decoded.pairingId !== 'string')
    || !Number.isSafeInteger(decoded.issuedAt)
    || !Number.isSafeInteger(decoded.expiresAt)) return undefined
  return {
    version: COOKIE_PAYLOAD_VERSION,
    authority: decoded.authority,
    issuedAt: decoded.issuedAt,
    expiresAt: decoded.expiresAt,
    ...(decoded.pairingId === undefined ? {} : { pairingId: decoded.pairingId }),
  } as BrowserCookiePayload
}

function mobilePairings(record: CredentialRecord | undefined): readonly MobilePairingRecord[] {
  if (record === undefined) return []
  if (record.kind !== 'grant') throw new Error('client-connection: mobile-pairings credential record has an unsupported format')
  const value = record.payload
  if (!isRecord(value) || value.version !== 1 || !Array.isArray(value.entries) || value.entries.length > 100
    || value.entries.some((item: unknown) => !isRecord(item) || typeof item.id !== 'string'
      || !/^[A-Za-z0-9_-]{22}$/u.test(item.id)
      || typeof item.name !== 'string' || item.name.length === 0 || item.name.length > 80
      || typeof item.authority !== 'string' || !/^[a-z0-9.-]+(?::[0-9]+)?$/u.test(item.authority)
      || typeof item.tokenHash !== 'string' || !/^[a-f0-9]{64}$/u.test(item.tokenHash)
      || !Number.isSafeInteger(item.createdAt))) {
    throw new Error('client-connection: mobile-pairings credential record has an unsupported format')
  }
  return value.entries as MobilePairingRecord[]
}

async function initializeSecret(credentials: CredentialProvider): Promise<Buffer> {
  const generated: StoredSecretPayload = {
    version: STORED_SECRET_VERSION,
    secret: encodeBase64Url(randomBytes(SECRET_BYTES)),
  }
  const record = await credentials.modifyRecord(AUTH_RECORD_KEY, (current) => {
    if (current !== undefined) {
      storedSecret(current)
      return Promise.resolve(undefined)
    }
    return Promise.resolve({ kind: 'grant', payload: generated })
  })
  const secret = storedSecret(record)
  if (secret === undefined) {
    throw new Error('client-connection: browser-session credential record was not created')
  }
  return secret
}

/**
 * Process launch-token exchange and persistent signed-cookie verification.
 * Connection loads the credential provider's signing secret during activation
 * and retains it for synchronous request authentication.
 */
export class BrowserAuth {
  private readonly launchToken: string
  private readonly maxAgeMilliseconds: number
  private readonly pairings = new Map<string, MobilePairingRecord>()

  private constructor(
    processOwner: object,
    private readonly secret: Buffer,
    maxAgeDays: number,
    private readonly credentials: CredentialProvider,
    entries: readonly MobilePairingRecord[],
  ) {
    this.launchToken = processLaunchToken(processOwner)
    this.maxAgeMilliseconds = maxAgeDays * DAY_MILLISECONDS
    for (const entry of entries) this.pairings.set(entry.id, entry)
    if (!Number.isSafeInteger(this.maxAgeMilliseconds)
      || !Number.isSafeInteger(Date.now() + this.maxAgeMilliseconds)) {
      throw new Error('client-connection: cookieMaxAgeDays exceeds the safe timestamp range')
    }
  }

  /**
   * Initialize browser authentication and create its durable signing secret
   * when this Harness home has none.
   * @param processOwner - root application context retaining one token across Connection reloads.
   * @param credentials - persistent credential provider for the Web profile.
   * @param maxAgeDays - positive absolute browser-cookie lifetime in days.
   * @returns initialized authentication owner with the process owner's launch token.
   */
  static async create(
    processOwner: object,
    credentials: CredentialProvider,
    maxAgeDays: number,
  ): Promise<BrowserAuth> {
    const secret = await initializeSecret(credentials)
    return new BrowserAuth(processOwner, secret, maxAgeDays, credentials,
      mobilePairings(await credentials.readRecord(MOBILE_RECORD_KEY)))
  }

  /** Create one durable, separately revocable public pairing link.
   * @param baseUrl - HTTPS origin assigned to this Host.
   * @param name - Name shown in the Mac connection list.
   * @returns one-time visible link and public pairing metadata.
   */
  async createMobilePairing(baseUrl: string, name: string): Promise<{ url: string; pairing: MobilePairing }> {
    const url = new URL(baseUrl)
    if (url.protocol !== 'https:' || url.pathname !== '/' || url.search !== '' || url.hash !== '') {
      throw new Error('client-connection: mobile pairing requires a clean HTTPS origin')
    }
    const label = name.trim()
    if (label.length === 0 || label.length > 80) throw new Error('client-connection: invalid mobile pairing name')
    if (this.pairings.size >= 100) throw new Error('client-connection: mobile pairing limit reached; revoke an unused link')
    const token = encodeBase64Url(randomBytes(SECRET_BYTES))
    const entry: MobilePairingRecord = {
      id: encodeBase64Url(randomBytes(16)), name: label, authority: url.host,
      tokenHash: createHash('sha256').update(token).digest('hex'), createdAt: Date.now(),
    }
    const record = await this.credentials.modifyRecord(MOBILE_RECORD_KEY, current =>
      Promise.resolve({ kind: 'grant', payload: { version: 1,
        entries: [...mobilePairings(current), entry] } satisfies StoredMobilePairings }))
    const committed = mobilePairings(record)
    if (!committed.some(stored => stored.id === entry.id)) throw new Error('client-connection: mobile pairing was not saved')
    this.pairings.clear()
    for (const stored of committed) this.pairings.set(stored.id, stored)
    url.searchParams.set(TOKEN_QUERY, token)
    return { url: url.href, pairing: { id: entry.id, name: entry.name, authority: entry.authority, createdAt: entry.createdAt } }
  }

  /** List active mobile pairings without exposing bearer tokens.
   * @returns Public pairing metadata.
   */
  listMobilePairings(): readonly MobilePairing[] {
    return [...this.pairings.values()].map(({ id, name, authority, createdAt }) => ({ id, name, authority, createdAt }))
  }

  /** Revoke one pairing's token and every cookie issued from it.
   * @param id - Pairing identifier from {@link listMobilePairings}.
   */
  async revokeMobilePairing(id: string): Promise<void> {
    if (!this.pairings.has(id)) throw new Error('client-connection: mobile pairing not found')
    const record = await this.credentials.modifyRecord(MOBILE_RECORD_KEY, current =>
      Promise.resolve({ kind: 'grant', payload: { version: 1,
        entries: mobilePairings(current).filter(entry => entry.id !== id) } satisfies StoredMobilePairings }))
    if (record === undefined) throw new Error('client-connection: mobile pairing was not revoked')
    const committed = mobilePairings(record)
    if (committed.some(entry => entry.id === id)) throw new Error('client-connection: mobile pairing was not revoked')
    this.pairings.clear()
    for (const stored of committed) this.pairings.set(stored.id, stored)
  }

  /**
   * Add this process's launch token to the caller's application URL.
   * @param baseUrl - clean browser URL whose authority and mount are preserved.
   * @returns the same URL carrying the process token as its sole authentication input.
   */
  authenticatedUrl(baseUrl: string): string {
    const url = new URL(baseUrl)
    url.searchParams.set(TOKEN_QUERY, this.launchToken)
    return url.href
  }

  /**
   * Authenticate an index request. A valid root query token mints the cookie
   * and redirects to the directory-relative clean `./`; a valid cookie lets
   * the caller serve the index; every other request receives the same minimal
   * 401 response.
   * @param req - incoming root or configured-index request.
   * @param res - response owned when this method returns false.
   * @returns true only when the caller may serve index.html.
   */
  authorizeIndex(req: ConnectionIndexRequest, res: ConnectionIndexResponse): boolean {
    /* v8 ignore next -- node:http always supplies url on server requests. */
    const url = new URL(req.url ?? '/', 'http://dsh.invalid')
    const tokens = url.searchParams.getAll(TOKEN_QUERY)
    if (tokens.length > 0) {
      const authority = requestAuthority(req.headers)
      const token = tokens.join('')
      const pairing = [...this.pairings.values()].find(entry => entry.authority === authority
        && tokenMatches(entry.tokenHash, createHash('sha256').update(token).digest('hex')))
      if (req.method === 'GET' && url.pathname === '/' && tokens.length === 1
        && authority !== undefined && (tokenMatches(token, this.launchToken) || pairing !== undefined)) {
        const issuedAt = Date.now()
        const expiresAt = issuedAt + this.maxAgeMilliseconds
        const value = encodeCookie({
          version: COOKIE_PAYLOAD_VERSION,
          authority,
          issuedAt,
          expiresAt,
          ...pairing === undefined ? {} : { pairingId: pairing.id },
        }, this.secret)
        res.writeHead(303, {
          'cache-control': 'no-store',
          'location': './',
          'referrer-policy': 'no-referrer',
          'set-cookie': sessionCookie(
            cookieName(authority), value, expiresAt, Math.floor(this.maxAgeMilliseconds / 1000),
          ),
        })
        res.end()
        return false
      }
      if (req.method === 'GET' && url.pathname === '/' && this.isAuthenticated(req)) {
        res.writeHead(303, {
          'cache-control': 'no-store',
          'location': './',
          'referrer-policy': 'no-referrer',
        })
        res.end()
        return false
      }
      this.writeUnauthorized(req, res)
      return false
    }
    if (this.isAuthenticated(req)) return true
    this.writeUnauthorized(req, res)
    return false
  }

  /**
   * Verify the authority-bound browser cookie on a Host request.
   * @param request - request headers carrying Host and Cookie.
   * @returns true only for an unexpired cookie signed by this activation's loaded secret.
   */
  isAuthenticated(request: ConnectionTrustRequest): boolean {
    const authority = requestAuthority(request.headers)
    const rawCookie = header(request.headers, 'cookie')
    if (authority === undefined || rawCookie === undefined) return false
    const value = cookieValue(rawCookie, cookieName(authority))
    if (value === undefined) return false
    const payload = decodeCookie(value, this.secret)
    if (payload === undefined || payload.authority !== authority) return false
    if (payload.pairingId !== undefined && this.pairings.get(payload.pairingId)?.authority !== authority) return false
    const now = Date.now()
    return payload.issuedAt <= now
      && payload.expiresAt > now
      && payload.expiresAt > payload.issuedAt
      && payload.expiresAt - payload.issuedAt <= this.maxAgeMilliseconds
  }

  private writeUnauthorized(req: ConnectionIndexRequest, res: ConnectionIndexResponse): void {
    res.writeHead(401, {
      'cache-control': 'no-store',
      'content-type': 'text/plain; charset=utf-8',
    })
    res.end(req.method === 'HEAD'
      ? undefined
      : 'dsh web authentication required; reopen the URL printed by dsh web.\n')
  }
}
