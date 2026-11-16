import { createServer } from 'node:http'
import { connect } from 'node:net'
import { describe, expect, it } from 'vitest'
import { startLanProxy } from '../src/lan-proxy.ts'

function target(): Promise<{ port: number; close: () => Promise<void>; seen: string[] }> {
  const seen: string[] = []
  const server = createServer((request, response) => {
    seen.push(`${request.headers.host ?? ''} ${request.headers.cookie ?? ''}`)
    response.writeHead(200, { 'content-type': 'text/plain' })
    response.end('ok')
  })
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const address = server.address()
      resolve({
        port: typeof address === 'object' && address !== null ? address.port : 0,
        seen,
        close: () => new Promise<void>((closed) => { server.close(() => { closed() }) }),
      })
    })
  })
}

describe('LAN proxy', () => {
  it('forwards plain HTTP with the trusted Host header and its cookie', async () => {
    const upstream = await target()
    const proxy = await startLanProxy({ address: '127.0.0.1', port: 0, targetPort: upstream.port,
      authority: '192.168.1.20:19389' })
    try {
      const response = await fetch(`http://127.0.0.1:${String(proxy.port)}/api/session/list`, {
        headers: { cookie: 'dsh-auth-test=1' },
      })
      expect(response.status).toBe(200)
      expect(await response.text()).toBe('ok')
      expect(upstream.seen).toEqual(['192.168.1.20:19389 dsh-auth-test=1'])
    } finally {
      await proxy.close()
      await upstream.close()
    }
  })

  it('refuses a port another listener already owns', async () => {
    const first = await startLanProxy({ address: '127.0.0.1', port: 0, targetPort: 1, authority: '192.168.1.20:19389' })
    try {
      await expect(startLanProxy({ address: '127.0.0.1', port: first.port, targetPort: 1,
        authority: '192.168.1.20:19389' })).rejects.toThrow()
    } finally {
      await first.close()
    }
  })

  it('forwards a WebSocket upgrade with the trusted Host header', async () => {
    const upstream = await target()
    const upgradeServer = createServer()
    upgradeServer.on('upgrade', (request, socket) => {
      upstream.seen.push(`upgrade ${request.headers.host ?? ''}`)
      socket.end('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
    })
    await new Promise<void>((ready) => { upgradeServer.listen(0, '127.0.0.1', () => { ready() }) })
    const address = upgradeServer.address()
    const proxy = await startLanProxy({ address: '127.0.0.1', port: 0,
      targetPort: typeof address === 'object' && address !== null ? address.port : 0,
      authority: '192.168.1.20:19389' })
    try {
      const head = await new Promise<string>((resolve, reject) => {
        const socket = connect(proxy.port, '127.0.0.1', () => {
          socket.write('GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n'
            + 'Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n')
        })
        socket.once('data', (chunk) => { socket.destroy(); resolve(chunk.toString()) })
        socket.once('error', reject)
      })
      expect(head).toContain('101 Switching Protocols')
      expect(upstream.seen).toContain('upgrade 192.168.1.20:19389')
    } finally {
      await proxy.close()
      await upstream.close()
      upgradeServer.close()
    }
  })
})
