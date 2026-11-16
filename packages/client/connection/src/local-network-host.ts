/**
 * Local-network classification for phone pairing. A phone that is on the same
 * network as the Host may connect over plain HTTP, which ATS admits only for
 * local destinations; any other host still requires HTTPS.
 */

import { isLoopbackHostname } from './loopback-hostname.ts'

function ipv4(hostname: string): readonly number[] | undefined {
  const parts = hostname.split('.')
  if (parts.length !== 4) return undefined
  if (!parts.every(part => /^\d{1,3}$/u.test(part) && Number(part) <= 255)) return undefined
  return parts.map(Number)
}

/**
 * Whether a hostname names an address the phone can reach without the public internet.
 * @param hostname - WHATWG URL hostname (IPv6 literals retain brackets).
 * @returns true for loopback, private IPv4, link-local IPv4, mDNS `.local`, and IPv6 ULA or link-local addresses.
 */
export function isLocalNetworkHostname(hostname: string): boolean {
  const host = hostname.toLowerCase()
  if (isLoopbackHostname(host) || host === 'localhost' || host.endsWith('.local')) return true
  const address = ipv4(host)
  if (address !== undefined) {
    const [first, second] = address as [number, number, number, number]
    if (first === 10) return true
    if (first === 172 && second >= 16 && second <= 31) return true
    if (first === 192 && second === 168) return true
    if (first === 169 && second === 254) return true
    return false
  }
  // IPv6 literals arrive bracketed: ULA fc00::/7 and link-local fe80::/10.
  if (host.startsWith('[')) {
    const literal = host.slice(1, -1)
    return /^f[cd][0-9a-f]{2}:/u.test(literal) || /^fe[89ab][0-9a-f]:/u.test(literal)
  }
  return false
}
