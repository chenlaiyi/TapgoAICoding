/** Fetch the pinned official frpc binary for a Desktop release build. */

import { createHash } from 'node:crypto'
import { execFile } from 'node:child_process'
import { existsSync } from 'node:fs'
import { copyFile, mkdir, readFile, rename, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { promisify } from 'node:util'
import extractZip from 'extract-zip'

const VERSION = '0.71.0'
const CHECKSUMS = {
  'win32-x64': '9e5062e3e5cf07e67144a3a4acf175ef6a2486f3605dd6cf288bae34ab39819f',
  'darwin-arm64': '45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6',
  'darwin-x64': '1b1b4e2f1836e21e8733f1dddaacd4ed9ae67d7dbee39046b9d7b7eda6253637',
}

/** Prepare a verified frpc executable in one target's private build tree.
 * @param {string} directory - Target build directory.
 * @param {'arm64' | 'x64'} architecture - Target CPU architecture.
 * @param {NodeJS.ProcessEnv} environment - Target download environment.
 * @param {'darwin' | 'win32'} platform - Target operating system.
 * @returns {Promise<string>} The executable path to package.
 */
export async function prepareRelayClient(directory, architecture, environment = process.env, platform = 'darwin') {
  const expected = CHECKSUMS[`${platform}-${architecture}`]
  if (expected === undefined) throw new Error(`Tapgo relay client has no pinned ${platform}-${architecture} artifact`)
  const destination = join(directory, platform === 'win32' ? 'frpc.exe' : 'frpc')
  if (existsSync(destination)) return destination
  await mkdir(directory, { recursive: true })
  const archive = join(directory, platform === 'win32' ? 'frp.zip' : 'frp.tar.gz')
  const releaseArchitecture = architecture === 'x64' ? 'amd64' : architecture
  const releaseDirectory = `frp_${VERSION}_${platform === 'win32' ? 'windows' : 'darwin'}_${releaseArchitecture}`
  const binary = platform === 'win32' ? 'frpc.exe' : 'frpc'
  const url = `https://github.com/fatedier/frp/releases/download/v${VERSION}/${releaseDirectory}.${platform === 'win32' ? 'zip' : 'tar.gz'}`
  await promisify(execFile)(process.platform === 'win32' ? 'curl.exe' : '/usr/bin/curl', ['-fLsS', url, '-o', archive], { env: environment })
  const bytes = await readFile(archive)
  if (createHash('sha256').update(bytes).digest('hex') !== expected) {
    throw new Error('Tapgo relay client archive SHA-256 does not match the pinned release')
  }
  try {
    if (platform === 'win32') await extractZip(archive, { dir: directory })
    else await promisify(execFile)('/usr/bin/tar', ['-xzf', archive, '-C', directory, `${releaseDirectory}/${binary}`])
    const extracted = join(directory, releaseDirectory, binary)
    await copyFile(extracted, `${destination}.tmp`)
    await rename(`${destination}.tmp`, destination)
    await readFile(destination)
  } finally {
    await rm(archive, { force: true })
    await rm(join(directory, releaseDirectory), { recursive: true, force: true })
  }
  return destination
}
