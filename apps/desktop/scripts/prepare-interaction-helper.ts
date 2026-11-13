/** Build the signed-app-only native observation and restoration executable. */
import { execFile } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import { promisify } from 'node:util'
import { fileURLToPath } from 'node:url'

/**
 * Compile a native helper matching the target Desktop architecture.
 * @param destination - Runtime directory signed before the parent application.
 * @param arch - Target CPU, independent of the build host.
 * @returns After compilation and permission-free decision checks complete.
 */
export async function prepareInteractionHelper(destination: string, arch: 'arm64' | 'x64'): Promise<void> {
  await mkdir(destination, { recursive: true })
  const binary = join(destination, 'interaction-lease')
  const target = `${arch === 'x64' ? 'x86_64' : 'arm64'}-apple-macos13.0`
  await promisify(execFile)('/usr/bin/swiftc', ['-O', '-parse-as-library', '-target', target,
    fileURLToPath(new URL('../native/InteractionLease.swift', import.meta.url)), '-o', binary])
  await promisify(execFile)(binary, ['--self-test'])
}
