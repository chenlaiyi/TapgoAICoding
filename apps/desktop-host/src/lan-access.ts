/** Plain-HTTP phone entry on the local network, forwarding to the loopback Host. */

import { networkInterfaces } from 'node:os'

/** LAN HTTP entry the iPhone dials when it is on the same network as this Mac. */
export interface LanAccess {
  readonly origin: string
  readonly authority: string
  readonly address: string
  readonly port: number
}

/** Port the LAN entry uses; the relay path keeps its own fixed loopback port. */
export const LAN_PORT = 19389

const PRIVATE_IPV4 = /^(?:10\.|192\.168\.|169\.254\.|172\.(?:1[6-9]|2[0-9]|3[01])\.)/u

/** Normalized IPv4 text of one interface entry, or undefined for other families. */
function ipv4Of(entry: { family: string | number; address: string }): string | undefined {
  const isIpv4 = entry.family === 'IPv4' || entry.family === 4
  return isIpv4 ? entry.address : undefined
}

/**
 * Pick the private IPv4 address a phone on the same network can dial.
 * @param interfaces - Network interfaces snapshot, injectable for tests.
 * @returns the first private, non-internal IPv4 address, or undefined when no LAN is up.
 */
export function lanAddress(
  interfaces: ReturnType<typeof networkInterfaces> = networkInterfaces(),
): string | undefined {
  for (const entries of Object.values(interfaces)) {
    for (const entry of entries ?? []) {
      if (entry.internal) continue
      const address = ipv4Of(entry)
      if (address !== undefined && PRIVATE_IPV4.test(address)) return address
    }
  }
  return undefined
}

/**
 * Resolve the LAN origin for one Desktop Host.
 * @param environment - launch environment; `TAPGO_MOBILE_LAN_ORIGIN` overrides the detected address, `off` disables it.
 * @param preferredPort - port the entry listens on unless the environment names another.
 * @returns the LAN origin and listening coordinates, or undefined when LAN access is unavailable or disabled.
 */
export function resolveLanAccess(environment: NodeJS.ProcessEnv, preferredPort = LAN_PORT):
LanAccess | undefined {
  const configured = environment.TAPGO_MOBILE_LAN_ORIGIN?.trim()
  if (configured === 'off') return undefined
  if (configured !== undefined && configured !== '') {
    let url: URL
    try { url = new URL(configured) } catch { throw new Error('TAPGO_MOBILE_LAN_ORIGIN must be an http local-network origin') }
    const port = url.port === '' ? 80 : Number(url.port)
    if (url.protocol !== 'http:' || url.username !== '' || url.password !== '' || url.pathname !== '/'
      || url.search !== '' || url.hash !== '' || !PRIVATE_IPV4.test(url.hostname)
      || !Number.isSafeInteger(port) || port < 1 || port > 65535) {
      throw new Error('TAPGO_MOBILE_LAN_ORIGIN must be an http local-network origin')
    }
    return { origin: url.origin, authority: url.host, address: url.hostname, port }
  }
  const address = lanAddress()
  if (address === undefined) return undefined
  return {
    origin: `http://${address}:${String(preferredPort)}`,
    authority: `${address}:${String(preferredPort)}`,
    address,
    port: preferredPort,
  }
}
