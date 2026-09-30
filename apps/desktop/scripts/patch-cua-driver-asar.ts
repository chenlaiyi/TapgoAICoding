/** Make the Cua Driver's native library path usable after Electron ASAR unpacking. */

import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

/**
 * Patch the pinned @ubjs resolver so dlopen receives the physical unpacked path.
 * @param runtimeRoot - Materialized Desktop DSH runtime.
 */
export function patchCuaDriverAsarResolution(runtimeRoot: string): void {
  const path = join(runtimeRoot, 'node_modules', '@ubjs', 'node', 'typescript', 'dist', 'resolve-lib.js')
  const source = readFileSync(path, 'utf8')
  const target = '    return binaryPath;\n}'
  if (source.split(target).length !== 2) {
    throw new Error('desktop runtime: pinned @ubjs native resolver changed')
  }
  const replacement = `    const unpackedPath = binaryPath.replace(/([\\\\/])app\\.asar([\\\\/])/, '$1app.asar.unpacked$2');
    return unpackedPath !== binaryPath && (0, node_fs_1.existsSync)(unpackedPath) ? unpackedPath : binaryPath;
}`
  writeFileSync(path, source.replace(target, replacement))
}
