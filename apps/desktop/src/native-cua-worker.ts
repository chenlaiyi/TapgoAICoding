/** Signed Desktop resources used by the native computer-use worker. */
import { join } from 'node:path'

/** Trusted startup values passed to the profile through the Host environment. */
export interface DesktopNativeCuaWorker {
  readonly binaryPath: string
  readonly hostBundleId: string
}

/**
 * Resolve the packaged macOS worker without replacing custom driver policy.
 * @param platform - Application process platform.
 * @param packaged - Whether Electron runs a packaged application.
 * @param resources - Signed application resources directory.
 * @param manifest - Installed package metadata.
 * @param environment - Login-shell environment inherited by the Host.
 * @returns Worker configuration, or undefined for development, other platforms, or custom driver configuration.
 */
export function resolveDesktopNativeCuaWorker(
  platform: NodeJS.Platform, packaged: boolean, resources: string, manifest: unknown, environment: NodeJS.ProcessEnv,
): DesktopNativeCuaWorker | undefined {
  if (platform !== 'darwin' || !packaged || Object.keys(environment).some(key => key.startsWith('CUA_DRIVER_'))) return undefined
  if (manifest === null || typeof manifest !== 'object' || !('dshDesktopAppId' in manifest)
    || typeof manifest.dshDesktopAppId !== 'string' || !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/u.test(manifest.dshDesktopAppId)) {
    throw new Error('desktop native computer use: missing or invalid packaged application identifier')
  }
  return { binaryPath: join(resources, 'runtime', 'cua-driver', 'cua-driver'), hostBundleId: manifest.dshDesktopAppId }
}
