import { describe, expect, it, vi } from 'vitest'
import { probeMobileConnection } from '../src/mobile-diagnostics.ts'

const pairing = 'https://mac.remote.example/?token=private-token&name=Office'

describe('public iPhone connection check', () => {
  it('checks token exchange and the authenticated WebSocket without returning credentials', async () => {
    const send = vi.fn(async () => ({ status: 303, cookie: 'dsh-auth-test=signed; Path=/; HttpOnly' }))
    const connect = vi.fn(async () => {})
    const result = await probeMobileConnection(pairing, send, connect)
    expect(result.state).toBe('connected')
    expect(send).toHaveBeenCalledWith(pairing, expect.any(AbortSignal))
    expect(connect).toHaveBeenCalledWith('wss://mac.remote.example/api/remote.mux',
      'dsh-auth-test=signed', expect.any(AbortSignal))
    expect(JSON.stringify(result)).not.toContain('private-token')
  })

  it.each([
    [401, 'authentication'],
    [403, 'authentication'],
    [503, 'relay'],
  ] as const)('identifies HTTP %i at the correct stage', async (status, state) => {
    const connect = vi.fn(async () => {})
    expect((await probeMobileConnection(pairing, async () => ({ status, cookie: null }), connect)).state).toBe(state)
    expect(connect).not.toHaveBeenCalled()
  })

  it('distinguishes certificate failures from network failures', async () => {
    for (const [code, state] of [['CERT_HAS_EXPIRED', 'tls'], ['ENOTFOUND', 'network']] as const) {
      const result = await probeMobileConnection(pairing, async () => { throw Object.assign(new Error('failed'), { code }) })
      expect(result.state).toBe(state)
    }
  })

  it('reports a WebSocket failure after a successful pairing exchange', async () => {
    const result = await probeMobileConnection(pairing,
      async () => ({ status: 303, cookie: 'dsh-auth-test=signed; Path=/' }),
      async () => { throw new Error('upgrade rejected') })
    expect(result.state).toBe('websocket')
  })
})
