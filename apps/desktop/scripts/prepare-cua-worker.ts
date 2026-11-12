/** Prepare the pinned Cua Driver executable for Desktop's private SDK worker. */
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { x as extractTar } from 'tar'
import { downloadPrimaryRuntimeAsset } from '../../../scripts/primary-runtime/prepare.ts'
import lock from './cua-worker.lock.json' with { type: 'json' }

/**
 * Extract only the regular executable from the pinned release archive.
 * @param archive - Verified upstream tar archive.
 * @param destination - Directory receiving the executable.
 * @returns After extraction and executable permissions are complete.
 */
export async function installCuaWorkerArchive(archive: string, destination: string): Promise<void> {
  const staging = mkdtempSync(join(tmpdir(), 'dsh-cua-worker-'))
  let found = false
  let invalid = false
  try {
    await extractTar({ file: archive, cwd: staging, filter(path, entry) {
      if (path !== 'cua-driver') return false
      if (found || !('type' in entry) || entry.type !== 'File') {
        invalid = true
        return false
      }
      found = true
      return true
    } })
    if (invalid) throw new Error('desktop Cua worker: expected one regular executable')
    if (!found) throw new Error('desktop Cua worker: archive omits cua-driver')
    mkdirSync(destination, { recursive: true })
    copyFileSync(join(staging, 'cua-driver'), join(destination, 'cua-driver'))
    chmodSync(join(destination, 'cua-driver'), 0o755)
  } finally {
    rmSync(staging, { recursive: true, force: true })
  }
}

/**
 * Download a checksum-pinned executable matching the native SDK dependency.
 * @param destination - Directory receiving the worker.
 * @param cache - Verified build download cache.
 * @returns Pinned worker version after successful installation.
 */
export async function prepareCuaWorker(destination: string, cache: string): Promise<string> {
  const manifest = JSON.parse(readFileSync(new URL('../../../packages/experimental/computer-use-cua-driver-native/package.json', import.meta.url), 'utf8')) as { dependencies: Record<string, string> }
  if (manifest.dependencies['@trycua/cua-driver'] !== lock.version) {
    throw new Error('desktop Cua worker: executable lock must match the native SDK version')
  }
  const archive = await downloadPrimaryRuntimeAsset(lock.url, lock.sha256, cache)
  await installCuaWorkerArchive(archive, destination)
  return lock.version
}
