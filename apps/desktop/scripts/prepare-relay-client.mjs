/** Fetch the pinned official frpc binary for a macOS release build. */

import { createHash } from 'node:crypto'
import { execFile } from 'node:child_process'
import { existsSync } from 'node:fs'
import { copyFile, mkdir, readFile, rename, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { promisify } from 'node:util'

const VERSION = '0.71.0'
const CHECKSUMS = {
  arm64: '45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6',
  x64: '1b1b4e2f1836e21e8733f1dddaacd4ed9ae67d7dbee39046b9d7b7eda6253637',
}

/** Prepare a verified frpc executable in one target's private build tree.
 * @param {string} directory - Target build directory.
 * @param {'arm64' | 'x64'} architecture - Target Mac CPU architecture.
 * @param {NodeJS.ProcessEnv} environment - Target download environment.
 * @returns {Promise<string>} The executable path to package.
 */
export async function prepareRelayClient(directory, architecture, environment = process.env) {
  const expected = CHECKSUMS[architecture]
  if (expected === undefined) throw new Error(`Tapgo relay client has no pinned ${architecture} artifact`)
  const destination = join(directory, 'frpc')
  if (existsSync(destination)) return destination
  await mkdir(directory, { recursive: true })
  const archive = join(directory, 'frp.tar.gz')
  const releaseArchitecture = architecture === 'x64' ? 'amd64' : architecture
  const url = `https://github.com/fatedier/frp/releases/download/v${VERSION}/frp_${VERSION}_darwin_${releaseArchitecture}.tar.gz`
  await promisify(execFile)('/usr/bin/curl', ['-fLsS', url, '-o', archive], { env: environment })
  const bytes = await readFile(archive)
  if (createHash('sha256').update(bytes).digest('hex') !== expected) {
    throw new Error('Tapgo relay client archive SHA-256 does not match the pinned release')
  }
  try {
    await promisify(execFile)('/usr/bin/tar', ['-xzf', archive, '-C', directory,
      `frp_${VERSION}_darwin_${releaseArchitecture}/frpc`])
    const extracted = join(directory, `frp_${VERSION}_darwin_${releaseArchitecture}`, 'frpc')
    await copyFile(extracted, `${destination}.tmp`)
    await rename(`${destination}.tmp`, destination)
    await readFile(destination)
  } finally {
    await rm(archive, { force: true })
    await rm(join(directory, `frp_${VERSION}_darwin_${releaseArchitecture}`), { recursive: true, force: true })
  }
  return destination
}
