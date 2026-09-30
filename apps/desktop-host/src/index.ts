/** Launch the Desktop profile through the Web application and report its URL to Electron. */

import { delimiter, join } from 'node:path'
import { inspect } from 'node:util'
import { fileURLToPath } from 'node:url'
import { loadLayeredEnv, loadProfileDirectory, reportSkippedBundles } from '@deepseek-ai/dsh-app-boot'
import { runProfile } from '@deepseek-ai/dsh/profile-boot'
import type {} from '@deepseek-ai/dsh-client-connection'
import type {} from '@deepseek-ai/dsh-host-webserver'
import type {} from '@deepseek-ai/dsh-deepseek-account'
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths'
import * as desktopOffice from './office.ts'

import { installDesktopUpdateTaskControl } from './update-tasks.ts'
import { installDesktopQuitInspection } from './quit-inspection.ts'
import { installPlatformSessionPublisher } from './platform-session.ts'
import { installOfficeEngineResolution } from './office-engine.ts'
import { resolveMobileOrigin } from './mobile-origin.ts'
import { relayDeviceId, remoteRelayOrigin, resolveRemoteRelay, startRemoteRelay } from './remote-relay.ts'

async function main(): Promise<void> {
  const runtimeDir = process.argv[2] as string
  const projectDir = process.argv[3] as string
  installOfficeEngineResolution(runtimeDir)
  const installAnchor = join(runtimeDir, 'node_modules', '@deepseek-ai', 'dsh-desktop-host', 'package.json')
  const profile = loadProfileDirectory('dsh', projectDir, installAnchor)
  reportSkippedBundles('dsh', profile)
  const environment = loadLayeredEnv('dsh')
  const relay = resolveRemoteRelay(process.env, join(resolveDshHome(), 'tapgo-mobile-relay'), join(runtimeDir, '..', '..', 'frpc'))
  const relayId = relay === undefined ? undefined : relayDeviceId(relay.stateDirectory)
  const mobile = resolveMobileOrigin(relay === undefined
    ? process.env.TAPGO_MOBILE_HTTPS_ORIGIN
    : remoteRelayOrigin(relay, relayId ?? relayDeviceId(relay.stateDirectory)))
  const application = runProfile({
    environment,
    profile: 'desktop',
    resolvedProfile: { profile, installAnchor },
    patchFiles: mobile === undefined ? [] : [fileURLToPath(new URL('../mobile-picker.overlay.yml', import.meta.url))],
    args: ['--no-open', '--port', '19388', ...(mobile === undefined ? [] : ['--trusted-host', mobile.authority])],
    ...(process.argv[5] === undefined ? {} : {
      packageManager: {
        command: process.execPath,
        args: ['--expose-internals', process.argv[5]],
        env: {
          ELECTRON_RUN_AS_NODE: '1',
          DSH_DESKTOP_NODE_EXECUTABLE: process.execPath,
          PATH: `${process.argv[6] ?? ''}${delimiter}${process.env.PATH ?? ''}`,
        },
      },
    }),
  })
  let stopping: Promise<void> | undefined
  let closeRelay: (() => Promise<void>) | undefined
  const control: {
    updateTasks?: ReturnType<typeof installDesktopUpdateTaskControl>
    quitInspection?: ReturnType<typeof installDesktopQuitInspection>
  } = {}
  const send = (message: object): Promise<void> => new Promise((resolve, reject) => {
    if (!process.connected || process.send === undefined) { resolve(); return }
    process.send(message, (error) => { if (error === null) resolve(); else reject(error) })
  })
  const stop = (): Promise<void> => stopping ??= (async () => {
    // Startup failure is reported by main; shutdown only owns a tree that booted.
    await closeRelay?.()
    const running = await application.catch(() => undefined)
    await running?.shutdown.shutdown(0)
    await send({ type: 'shutdown-complete' })
    if (process.connected) process.disconnect()
  })()
  process.on('message', (message: unknown) => {
    if (typeof message !== 'object' || message === null || !('type' in message)) return
    if (message.type === 'shutdown') { void stop(); return }
    if (message.type === 'quit-inspection') {
      if (!('requestId' in message) || !Number.isSafeInteger(message.requestId)) return
      const requestId = message.requestId
      void (async () => {
        try {
          if (stopping !== undefined || control.quitInspection === undefined) throw new Error('desktop quit: Host is unavailable')
          const inspection = await control.quitInspection()
          await send({ type: 'quit-inspection', requestId, ...inspection })
        } catch (error) {
          // The shell treats an unknown state as interruptible work and asks before quitting.
          await send({ type: 'quit-inspection', requestId, activeTasks: true, scheduledTasks: false,
            error: error instanceof Error ? error.message : String(error) })
        }
      })().catch((error: unknown) => { console.error(error) })
      return
    }
    if (message.type === 'mobile-pairing') {
      if (!('requestId' in message) || !Number.isSafeInteger(message.requestId)
        || !('action' in message) || !['create', 'list', 'revoke'].includes(String(message.action))) return
      void (async () => {
        try {
          if (stopping !== undefined || mobile === undefined) throw new Error('mobile pairing is unavailable')
          if (message.action === 'create') {
            if (!('name' in message) || typeof message.name !== 'string' || ctx.connection.createMobilePairing === undefined) return
            const created = await ctx.connection.createMobilePairing(mobile.origin, message.name)
            await send({ type: 'mobile-pairing', requestId: message.requestId, action: 'create', ...created })
          } else if (message.action === 'list') {
            await send({ type: 'mobile-pairing', requestId: message.requestId, action: 'list',
              pairings: ctx.connection.listMobilePairings?.() ?? [] })
          } else {
            if (!('id' in message) || typeof message.id !== 'string' || ctx.connection.revokeMobilePairing === undefined) return
            await ctx.connection.revokeMobilePairing(message.id)
            await send({ type: 'mobile-pairing', requestId: message.requestId, action: 'revoke' })
          }
        } catch (error) {
          await send({ type: 'mobile-pairing', requestId: message.requestId, action: message.action,
            error: error instanceof Error ? error.message : String(error) })
        }
      })().catch((error: unknown) => { console.error(error) })
      return
    }
    if (message.type !== 'update-tasks' || !('requestId' in message) || !Number.isSafeInteger(message.requestId)
      || !('action' in message) || !['inspect', 'lock', 'unlock'].includes(String(message.action))) return
    void (async () => {
      try {
        if (stopping !== undefined || control.updateTasks === undefined) throw new Error('desktop update: Host is unavailable')
        const active = await control.updateTasks(message.action as 'inspect' | 'lock' | 'unlock')
        await send({ type: 'update-tasks', requestId: message.requestId, active })
      } catch (error) {
        await send({ type: 'update-tasks', requestId: message.requestId, active: true,
          error: error instanceof Error ? error.message : String(error) })
      }
    })().catch((error: unknown) => { console.error(error) })
  })
  process.once('disconnect', () => { void stop() })
  const { ctx } = await application
  if (relay !== undefined && relayId !== undefined) closeRelay = startRemoteRelay(relay, relayId)
  control.updateTasks = installDesktopUpdateTaskControl(ctx)
  control.quitInspection = installDesktopQuitInspection(ctx)
  await ctx.plugin(desktopOffice, {
    runtimeDir,
    source: process.argv[4] ?? join(runtimeDir, '..', 'runtime', 'primary-runtime'),
    root: join(resolveDshHome(), 'dsh-runtimes', 'dsh-primary-runtime'),
  })
  installPlatformSessionPublisher(ctx, (session) => {
    if (process.connected) process.send?.({ type: 'platform-session', session })
  })
  const url = ctx.connection.authenticatedUrl(`http://127.0.0.1:${String(ctx.webServer.port)}`)
  const mobileUrl = mobile === undefined ? undefined : ctx.connection.authenticatedUrl(mobile.origin)
  if (process.connected) process.send?.({ type: 'ready', url, mobileUrl, mobileOrigin: mobile?.origin,
    injections: ctx.webServer.collectIndexInjections() }, (error) => { if (error !== null) console.error(error) })
}

/** Upper bound of the startup diagnostic carried over IPC; the head holds the message and stack. */
const MAX_FATAL_DIAGNOSTIC_CHARS = 64 * 1024

if (import.meta.main) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error)
    // The shell receives the complete inspected error here, not through stderr:
    // stderr bytes and this IPC message race, and the shell reports the first
    // failure it sees.
    const diagnostic = inspect(error, { depth: 4, maxArrayLength: 50 }).slice(0, MAX_FATAL_DIAGNOSTIC_CHARS)
    if (process.connected) process.send?.({ type: 'fatal', message, diagnostic }, (error) => { if (error !== null) console.error(error) })
    console.error(error)
    process.exitCode = 1
    if (process.connected) process.disconnect()
  })
}
