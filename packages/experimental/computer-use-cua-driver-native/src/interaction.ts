/** Supervised content-free native observation around one foreground drag. */
import { spawn } from 'node:child_process'
import { z } from 'zod'
import { HarnessError } from '@deepseek-ai/dsh-error'

/** Bounds and executable for the packaged macOS restoration observer. */
export interface InteractionConfig {
  /** Signed native executable owned by the Desktop application. */
  helperPath: string
  /** Deadline for the observer handshake and post-drag restoration. */
  timeoutMs: number
  /** Native observation polling interval. */
  pollMs: number
  /** Absolute lifetime limit for the observer process. */
  leaseMs: number
}

const Point = z.object({ x: z.number(), y: z.number() })
const Finished = z.object({
  type: z.literal('finished'), status: z.string(), focus_restored: z.boolean(), pointer_restored: z.boolean(),
  before_pid: z.number().int().positive(), before_pointer: Point,
  after_pid: z.number().int().positive().nullable(), after_pointer: Point.nullable(),
  driver_pid: z.number().int().positive(), source_pid: z.number().int().positive().nullable(),
  destination_pid: z.number().int().positive().nullable(), activated_pids: z.array(z.number().int().positive()),
  focus_requested: z.boolean(),
  outside_input: z.boolean(), external_source_pids: z.array(z.number().int()),
})
/** Native observation and independently verified restoration outcomes. */
export type InteractionReport = z.infer<typeof Finished>

/** Failure before input, or an uncertain outcome after native input. */
export class InteractionError extends HarnessError {
  /**
   * @param code - Stable failure identity for the interaction observer.
   * @param cause - Retained native process or protocol failure.
   */
  constructor(code: 'NATIVE_INTERACTION_UNAVAILABLE' | 'NATIVE_INTERACTION_FAILED', cause?: unknown) {
    super(code === 'NATIVE_INTERACTION_UNAVAILABLE'
      ? 'Safe foreground drag restoration is unavailable; no drag was sent. Check host accessibility access or explicitly set restore_user_state:false.'
      : 'Foreground drag restoration failed; the drag may have landed. Inspect fresh desktop state before retrying.', code, { cause })
  }
}

/** One supervised process; closing it never restores desktop state. */
export interface InteractionLease {
  /** Restore only after the SDK call settles and the caller still permits it. */
  finish(restore: boolean): Promise<InteractionReport>
  /** Close stdin and await process exit, terminating an unresponsive observer. */
  close(): Promise<void>
}

/**
 * Start a native observer before dispatching input; fail closed on missing observation.
 * @param config - Signed helper and bounded operation durations.
 * @param driverPid - Worker process whose input events belong to this operation.
 * @param signal - Cancellation that prevents any later restoration.
 * @returns Ready observer, owned until close settles.
 */
export async function beginInteraction(config: InteractionConfig, driverPid: number, signal: AbortSignal): Promise<InteractionLease> {
  signal.throwIfAborted()
  const child = spawn(config.helperPath, [], { stdio: ['pipe', 'pipe', 'ignore'], env: {}, windowsHide: true })
  const ended = new Promise<void>((resolve) => { child.once('close', () => { resolve() }) })
  // Spawn errors still have a close event; their failure is delivered to the waiter below.
  let failure: unknown
  const lines: string[] = []
  let buffered = ''
  let receivedBytes = 0
  let wake: (() => void) | undefined
  child.on('error', (error) => { failure = error; wake?.() })
  child.stdout.setEncoding('utf8')
  child.stdout.on('data', (chunk: string) => {
    buffered += chunk
    receivedBytes += Buffer.byteLength(chunk)
    if (receivedBytes > 65_536) { failure = new Error('interaction observer exceeded protocol limit'); child.kill(); wake?.(); return }
    const parts = buffered.split('\n')
    buffered = parts.pop() ?? ''
    lines.push(...parts)
    wake?.()
  })
  child.on('close', () => { failure ??= new Error('interaction observer closed'); wake?.() })
  child.stdin.on('error', (error) => { failure = error; wake?.() })
  const abort = () => { child.kill() }
  signal.addEventListener('abort', abort, { once: true })
  let closing: Promise<void> | undefined
  function close(): Promise<void> {
    return closing ??= (async () => {
      signal.removeEventListener('abort', abort)
      child.stdin.end()
      const timer = setTimeout(() => { child.kill('SIGKILL') }, config.timeoutMs)
      try { await ended } finally { clearTimeout(timer) }
    })()
  }
  async function read(): Promise<unknown> {
    const deadline = AbortSignal.timeout(config.timeoutMs)
    const cancelled = AbortSignal.any([signal, deadline])
    while (lines.length === 0) {
      cancelled.throwIfAborted()
      if (failure !== undefined) throw failure instanceof Error ? failure : new Error('interaction observer failed', { cause: failure })
      await new Promise<void>((resolve, reject) => {
        const onAbort = () => { wake = undefined; reject(cancelled.reason instanceof Error ? cancelled.reason : new Error('Interaction observation cancelled')) }
        wake = () => { cancelled.removeEventListener('abort', onAbort); wake = undefined; resolve() }
        cancelled.addEventListener('abort', onAbort, { once: true })
      })
    }
    const line = lines.shift()
    if (line === undefined) throw new Error('interaction observer omitted its response')
    return JSON.parse(line)
  }
  try {
    child.stdin.write(JSON.stringify({ command: 'begin', begin: { driverPid, timeoutMs: config.timeoutMs, pollMs: config.pollMs, leaseMs: config.leaseMs } }) + '\n')
    z.object({ type: z.literal('ready') }).parse(await read())
    signal.throwIfAborted()
    return {
      async finish(restore) {
        signal.throwIfAborted()
        child.stdin.write(JSON.stringify({ command: 'finish', restore }) + '\n')
        try { return Finished.parse(await read()) } catch (error) {
          signal.throwIfAborted()
          throw new InteractionError('NATIVE_INTERACTION_FAILED', error)
        }
      },
      close,
    }
  } catch (error) {
    await close()
    signal.throwIfAborted()
    throw new InteractionError('NATIVE_INTERACTION_UNAVAILABLE', error)
  }
}
