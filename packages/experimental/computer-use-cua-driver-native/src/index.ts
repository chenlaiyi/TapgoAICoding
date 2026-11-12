/**
 * Computer use through the Cua Driver native SDK and its own tools.
 * @module @deepseek-ai/dsh-experimental-computer-use-cua-driver-native
 */

import type { Context } from '@deepseek-ai/cordis'
import Schema from '@deepseek-ai/schemastery'
import { ComputerUseProviderName } from '@deepseek-ai/dsh-computer-use/brand'
import { createMcpToolDefinition } from '@deepseek-ai/dsh-mcp-client'
import { z } from 'zod'
import type { CuaDriver as NativeDriver } from '@trycua/cua-driver'
import type {} from '@deepseek-ai/dsh-computer-use'
import type {} from '@deepseek-ai/dsh-system-prompt'
import type {} from '@deepseek-ai/dsh-tools'
import { NativeWorkerError } from './errors.ts'

/** Optional supervised native process for hosts without an AppKit main loop. */
export interface Config {
  /** False selects the in-process runtime; an object selects the supervised private process. */
  worker?: false | {
    /** Absolute path to the executable matching the installed SDK version. */
    binaryPath: string
    /** Installed host application identifier used for permission attribution. */
    hostBundleId: string
    /** Maximum private-process startup handshake time in milliseconds. */
    startupTimeoutMs: number
    /** Maximum graceful private-process shutdown time in milliseconds. */
    shutdownTimeoutMs: number
    /** Maximum authorization session lifetime in seconds. */
    maxSessionTtlSeconds: number
    /** Maximum authorization session idle lifetime in seconds. */
    maxIdleTtlSeconds: number
  }
}

/** Cordis plugin identity for the native Cua Driver provider. */
export const name = 'experimental-computer-use-cua-driver-native'

/** Services required before the native runtime can publish tools. */
export const inject = ['computerUse', 'tools', 'systemPrompt']

/** In-process defaults, or a standard-mode worker owned through inherited stdio. */
export const Config = Schema.object({
  worker: Schema.union([Schema.const(false), Schema.object({
    binaryPath: Schema.string().required(),
    hostBundleId: Schema.string().required(),
    startupTimeoutMs: Schema.natural().min(1).max(Number.MAX_SAFE_INTEGER).default(10_000),
    shutdownTimeoutMs: Schema.natural().min(1).max(Number.MAX_SAFE_INTEGER).default(2_000),
    maxSessionTtlSeconds: Schema.natural().min(1).max(Number.MAX_SAFE_INTEGER).default(86_400),
    maxIdleTtlSeconds: Schema.natural().min(1).max(Number.MAX_SAFE_INTEGER).default(3_600),
  })]).default(false),
})

const ToolCatalog = z.object({
  tools: z.array(z.object({
    name: z.string().min(1),
    description: z.string().optional(),
    inputSchema: z.record(z.string(), z.unknown()),
    outputSchema: z.unknown().optional(),
  })),
})

/** DeepSeek's function-name alphabet and maximum length are protocol constants. */
const TOOL_NAME = /^[A-Za-z0-9_-]{1,64}$/u

const GUIDANCE = `Cua Driver native computer-use tools operate the host desktop. For native window actions, discover the exact app and window, then get a fresh window snapshot before acting. Use element_token from that snapshot, or coordinates from its screenshot. A new snapshot of that window invalidates its earlier element tokens. Select either target or the legacy pid/window_id fields; do not combine them. For browser actions, bind the exact tab with get_browser_state and use its page refs or viewport screenshot; do not infer viewport coordinates from a native window screenshot.

Prefer background delivery. A refusal does not authorize a foreground retry. Verify the requested outcome from fresh state after an action; a delivered click alone does not prove the outcome. After cancellation, inspect current state before retrying because completed input is not rolled back. Other sessions and applications may change the same desktop.

On macOS, in-process cursor-overlay operations may return facility_unavailable even when screenshots and input work. If no active application is reported, focus is unknown; the presence of another process does not identify what changed it.`

/**
 * Own one native runtime and expose its catalog through the MCP result adapter.
 * Startup failures roll back every registration. Unload removes tools, aborts
 * calls and image admission, awaits settlement and SDK shutdown, then releases computer use.
 * @param ctx - context providing the exclusive registration and tool services.
 * @param config - Optional supervised worker and operation bounds.
 * @returns after native import, runtime creation, and tool discovery complete.
 */
export async function apply(ctx: Context, config: Config): Promise<void> {
  const lifetime = new AbortController()
  const pending = new Set<Promise<unknown>>()
  let driver: NativeDriver | undefined
  // Cordis announces disposal before it awaits asynchronous plugin startup.
  ctx.on('internal/plugin', (fiber) => {
    if (fiber === ctx.fiber && fiber.uid === null) lifetime.abort()
  }, { global: true })
  let ready: Promise<void> = Promise.resolve()
  const dispose = ctx.effect(function* () {
    yield ctx.computerUse.register(ComputerUseProviderName('cua-driver-native'))
    yield async () => {
      lifetime.abort()
      // apply() reports startup failure; teardown still owns its native handle.
      await ready.catch(() => {})
      await Promise.allSettled(pending)
      if (driver !== undefined) {
        try {
          await driver.shutdown()
        } catch (error) {
          if (config.worker) throw new NativeWorkerError('shutdown', error)
          throw error
        }
        driver.uniffiDestroy()
      }
    }
    const child = ctx.plugin({
      name: 'computer-use-cua-driver-native-runtime',
      inject: ['tools', 'systemPrompt'],
      apply: mountRuntime,
    })
    yield child.dispose
    ready = Promise.resolve(child).then(() => {})
  }, 'computer-use-cua-driver-native.runtime')
  try {
    await ready
  } catch (error) {
    await dispose()
    throw error
  }

  /** The child owns tool registrations; the outer effect owns native teardown. */
  async function mountRuntime(inner: Context): Promise<void> {
    const { CuaDriver, SessionPermissionMode } = await import('@trycua/cua-driver')
    lifetime.signal.throwIfAborted()
    // The generated constructor returns its class with an owned binding handle,
    // but declares only CuaDriverLike, which omits uniffiDestroy().
    const worker = config.worker
    if (worker && Object.keys(process.env).some(key => key.startsWith('CUA_DRIVER_'))) {
      throw new NativeWorkerError('configuration')
    }
    let activeDriver: NativeDriver
    try {
      activeDriver = driver = (!worker
        ? CuaDriver.create({ embedded: true, claudeCodeCompatibility: false })
        : CuaDriver.createPrivateWorker({
          binaryPath: worker.binaryPath,
          hostBundleId: worker.hostBundleId,
          startupTimeoutMs: BigInt(worker.startupTimeoutMs),
          shutdownTimeoutMs: BigInt(worker.shutdownTimeoutMs),
          configuredDriver: {
            claudeCodeCompatibility: false,
            authorization: {
              allowedModes: [SessionPermissionMode.Standard],
              compatibilityMode: SessionPermissionMode.Standard,
              unrestrictedAcknowledged: false,
              maxSessionTtlSeconds: BigInt(worker.maxSessionTtlSeconds),
              maxIdleTtlSeconds: BigInt(worker.maxIdleTtlSeconds),
            },
          },
          environment: [],
          inheritStderr: false,
        })) as NativeDriver
    } catch (error) {
      if (worker) throw new NativeWorkerError('startup', error)
      throw error
    }
    let rawCatalog: string
    try {
      rawCatalog = await activeDriver.listToolsJson({ signal: lifetime.signal })
    } catch (error) {
      lifetime.signal.throwIfAborted()
      if (worker) throw new NativeWorkerError('startup', error)
      throw error
    }
    const catalog = ToolCatalog.parse(JSON.parse(rawCatalog))
    lifetime.signal.throwIfAborted()
    const names = new Set<string>()
    for (const tool of catalog.tools) {
      const publicName = `cua_driver_native__${tool.name}`
      if (!TOOL_NAME.test(publicName)) {
        throw new Error(`Cua Driver tool "${tool.name}" exceeds the supported function-name format`)
      }
      if (names.has(publicName)) throw new Error(`Cua Driver listed tool "${tool.name}" more than once`)
      names.add(publicName)
      const definition = createMcpToolDefinition(inner, {
        name: publicName,
        rawName: tool.name,
        description: tool.description ?? '',
        inputSchema: tool.inputSchema,
        outputSchema: tool.outputSchema,
        includeStructuredContent: true,
        async call(args, execution) {
          const combined = AbortSignal.any([execution.signal, lifetime.signal])
          combined.throwIfAborted()
          let result: Awaited<ReturnType<NativeDriver['callTool']>>
          try {
            result = await activeDriver.callTool(tool.name, JSON.stringify(args), { signal: combined })
          } catch (error) {
            combined.throwIfAborted()
            if (worker) throw new NativeWorkerError('call', error)
            throw error
          }
          combined.throwIfAborted()
          return JSON.parse(result.rawJson) as unknown
        },
      })
      inner.tools.register(definition)
    }
    inner.on('tools/execute', async (exec, next) => {
      if (!names.has(exec.name)) return next()
      const upstream = exec.signal
      exec.signal = AbortSignal.any([upstream, lifetime.signal])
      const operation = Promise.resolve().then(next)
      pending.add(operation)
      try {
        return await operation
      } finally {
        pending.delete(operation)
        exec.signal = upstream
      }
    })
    inner.systemPrompt.section({
      name: 'computer-use:cua-driver-native',
      order: inner.systemPrompt.getSectionOrder('TOOL_COMPUTER_USE'),
      text: GUIDANCE,
    })
  }
}
