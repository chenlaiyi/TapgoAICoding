import { generateKeyPairSync, verify } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  apnsJwt, createApnsSender, derToJose, endPayload, isPushToken, liveActivityTopic, updatePayload,
  type ApnsOptions,
} from '../src/apns.ts'

/** Read a value the test just produced, failing loudly when it is missing. */
function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error('missing test value')
  return value
}

function keyPair(): { privateKey: string; publicKey: string } {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  return {
    privateKey: privateKey.export({ format: 'pem', type: 'pkcs8' }).toString(),
    publicKey: publicKey.export({ format: 'pem', type: 'spki' }).toString(),
  }
}

const state = { startedAt: 1_700_000_000, detail: '正在运行命令 · git status', running: true }

describe('APNs Live Activity delivery', () => {
  it('signs a verifiable ES256 provider token', () => {
    const pair = keyPair()
    const token = apnsJwt('TEAM123456', 'KEY1234567', pair.privateKey, 1_700_000_000)
    const [header, claims, signature] = token.split('.').map(required)
    expect(JSON.parse(Buffer.from(required(header), 'base64url').toString())).toEqual({ alg: 'ES256', kid: 'KEY1234567' })
    expect(JSON.parse(Buffer.from(required(claims), 'base64url').toString())).toEqual({ iss: 'TEAM123456', iat: 1_700_000_000 })
    const jose = Buffer.from(required(signature), 'base64url')
    expect(jose.byteLength).toBe(64)
    expect(verify('sha256', Buffer.from(`${required(header)}.${required(claims)}`), { key: pair.publicKey, dsaEncoding: 'ieee-p1363' }, jose))
      .toBe(true)
  })

  it('converts DER signatures with fixed-width components', () => {
    const der = Buffer.concat([
      Buffer.from([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02]),
    ])
    const jose = derToJose(der)
    expect(jose.byteLength).toBe(64)
    expect(jose[31]).toBe(1)
    expect(jose[63]).toBe(2)
  })

  it('builds update and end payloads the widget can decode', () => {
    const topic = liveActivityTopic('com.devtools.terminalSimple')
    expect(topic).toBe('com.devtools.terminalSimple.push-type.liveactivity')
    expect(JSON.parse(updatePayload(state, 1_700_000_100, 120))).toEqual({
      aps: { timestamp: 1_700_000_100, event: 'update', 'content-state': state, 'stale-date': 1_700_000_220 },
    })
    expect(JSON.parse(endPayload({ ...state, running: false }, 1_700_000_200))).toEqual({
      aps: { timestamp: 1_700_000_200, event: 'end', 'content-state': { ...state, running: false },
        'dismissal-date': 1_700_000_260 },
    })
  })

  it('accepts hex activity tokens only', () => {
    expect(isPushToken('a'.repeat(64))).toBe(true)
    expect(isPushToken('A1'.repeat(32))).toBe(true)
    expect(isPushToken('a'.repeat(63))).toBe(false)
    expect(isPushToken('z'.repeat(64))).toBe(false)
    expect(isPushToken('')).toBe(false)
  })

  it('sends update and end through the injected transport', async () => {
    const pair = keyPair()
    const options: ApnsOptions = { bundleId: 'com.example.app', teamId: 'TEAM', keyId: 'KEY',
      privateKey: pair.privateKey, environment: 'development' }
    const seen: { headers: Readonly<Record<string, string>>; token: string; body: string }[] = []
    const sender = createApnsSender(options, async (_options, headers, token, body) => {
      seen.push({ headers, token, body })
      return { status: 200 }
    })
    expect(await sender.update('ab'.repeat(32), state)).toBe('ok')
    expect(await sender.end('ab'.repeat(32), { ...state, running: false })).toBe('ok')
    expect(seen).toHaveLength(2)
    expect(required(seen[0]).headers['apns-topic']).toBe('com.example.app.push-type.liveactivity')
    expect(required(seen[0]).headers['apns-push-type']).toBe('liveactivity')
    expect(required(seen[0]).headers.authorization).toMatch(/^bearer /u)
    expect(required(seen[1]).body).toContain('"event":"end"')
  })

  it('drops a token the service reports as unregistered', async () => {
    const pair = keyPair()
    const options: ApnsOptions = { bundleId: 'com.example.app', teamId: 'TEAM', keyId: 'KEY',
      privateKey: pair.privateKey, environment: 'production' }
    const gone = createApnsSender(options, async () => ({ status: 410, reason: 'Unregistered' }))
    expect(await gone.update('ab'.repeat(32), state)).toBe('unregistered')
    const failed = createApnsSender(options, async () => ({ status: 500 }))
    expect(await failed.update('ab'.repeat(32), state)).toBe('failed')
    const offline = createApnsSender(options, async () => { throw new Error('offline') })
    expect(await offline.update('ab'.repeat(32), state)).toBe('failed')
  })
})
