/** Name carried by Desktop pairing links. */

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { hostname } from 'node:os'

/** Read the macOS computer name, with the network hostname as a fallback.
 * @returns The current system computer name.
 */
export function systemComputerName(): string {
  if (process.platform === 'darwin') {
    try {
      const name = execFileSync('/usr/sbin/scutil', ['--get', 'ComputerName'], { encoding: 'utf8' }).trim()
      if (name !== '') return name
    } catch (error) {
      // A Mac without ComputerName still has a hostname.
      void error
    }
  }
  return hostname()
}

/** Read a saved override; an absent file follows the current system name.
 * @param path - Desktop's local computer-name file.
 * @param fallback - Current system computer name.
 * @returns The saved or system name.
 */
export function readComputerName(path: string, fallback: string): string {
  try {
    const name = readFileSync(path, 'utf8').trim()
    return name || fallback
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return fallback
    throw error
  }
}

/** Save a local name used by subsequent pairing links.
 * @param path - Desktop's local computer-name file.
 * @param name - User-entered display name.
 * @returns The trimmed name.
 */
export function saveComputerName(path: string, name: string): string {
  const value = name.trim()
  if (value.length === 0 || value.length > 80 || /[\u0000-\u001f]/u.test(value)) {
    throw new Error('Invalid computer name')
  }
  writeFileSync(path, value, { encoding: 'utf8', mode: 0o600 })
  return value
}

/** Add the display name without changing the Host authentication token.
 * @param url - Host-authenticated pairing URL.
 * @param name - Name to show on iOS.
 * @returns Pairing URL carrying the name.
 */
export function namedMobileUrl(url: string, name: string): string {
  const result = new URL(url)
  result.searchParams.set('name', name)
  return result.toString()
}
