/** Plain-HTTP phone entry on the LAN that forwards to the loopback Host. */

import { createServer, request as httpRequest, type IncomingMessage, type ServerResponse } from 'node:http'
import { connect } from 'node:net'
import type { Duplex } from 'node:stream'

/** Coordinates for one LAN entry. */
export interface LanProxyOptions {
  /** Local interface address to bind. */
  readonly address: string
  /** Port phones dial. */
  readonly port: number
  /** Loopback port of the running Host. */
  readonly targetPort: number
  /** Authority the Host trusts; requests carry it as their Host header. */
  readonly authority: string
}

/** A running LAN entry. */
export interface LanProxy {
  /** Bound port, useful when the caller asked the OS for one. */
  readonly port: number
  close(): Promise<void>
}

const HOP_BY_HOP = new Set(['connection', 'keep-alive', 'proxy-connection', 'transfer-encoding', 'upgrade'])

/** Copy request headers for the upstream hop, replacing Host and dropping hop-by-hop fields. */
function upstreamHeaders(request: IncomingMessage, authority: string): Record<string, string> {
  const headers: Record<string, string> = {}
  for (const [name, value] of Object.entries(request.headers)) {
    if (value === undefined || HOP_BY_HOP.has(name.toLowerCase()) || name.toLowerCase() === 'host') continue
    headers[name] = Array.isArray(value) ? value.join(', ') : value
  }
  headers.host = authority
  return headers
}

function forwardHttp(request: IncomingMessage, response: ServerResponse, options: LanProxyOptions): void {
  const upstream = httpRequest({
    host: '127.0.0.1',
    port: options.targetPort,
    method: request.method,
    path: request.url,
    headers: upstreamHeaders(request, options.authority),
  }, (answer) => {
    response.writeHead(answer.statusCode ?? 502, answer.headers)
    answer.pipe(response)
  })
  upstream.on('error', () => {
    if (!response.headersSent) response.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    response.end('Host unreachable\n')
  })
  request.pipe(upstream)
}

function forwardUpgrade(request: IncomingMessage, socket: Duplex, head: Buffer, options: LanProxyOptions): void {
  const upstream = connect(options.targetPort, '127.0.0.1')
  const fail = (): void => {
    socket.destroy()
    upstream.destroy()
  }
  upstream.once('error', fail)
  socket.once('error', fail)
  upstream.once('connect', () => {
    const lines = [`${request.method ?? 'GET'} ${request.url ?? '/'} HTTP/1.1`]
    for (let index = 0; index < request.rawHeaders.length; index += 2) {
      const name = request.rawHeaders[index] ?? ''
      if (name.toLowerCase() === 'host') continue
      lines.push(`${name}: ${request.rawHeaders[index + 1] ?? ''}`)
    }
    lines.push(`host: ${options.authority}`, '', '')
    upstream.write(lines.join('\r\n'))
    if (head.length > 0) upstream.write(head)
    upstream.pipe(socket)
    socket.pipe(upstream)
  })
}

/**
 * Start the LAN entry, forwarding plain HTTP and WebSocket upgrades to the loopback Host.
 * @param options - listening coordinates and the trusted authority the Host expects.
 * @returns the running entry, or a rejection when the address or port is unavailable.
 */
export function startLanProxy(options: LanProxyOptions): Promise<LanProxy> {
  const server = createServer((request, response) => { forwardHttp(request, response, options) })
  server.on('upgrade', (request, socket, head) => { forwardUpgrade(request, socket, head, options) })
  return new Promise((resolve, reject) => {
    const onError = (error: Error): void => { reject(error) }
    server.once('error', onError)
    server.listen(options.port, options.address, () => {
      server.off('error', onError)
      const bound = server.address()
      resolve({
        port: typeof bound === 'object' && bound !== null ? bound.port : options.port,
        close: async () => {
          server.closeAllConnections()
          await new Promise<void>((closed) => { server.close(() => { closed() }) })
        },
      })
    })
  })
}
