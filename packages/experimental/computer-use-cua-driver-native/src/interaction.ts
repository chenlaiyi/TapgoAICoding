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
  /** Deadline before an unfinished lease stops input; teardown still awaits worker quiescence. */
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
  input_stopped: z.boolean(), monitor_lost: z.boolean(), blocked_driver_events: z.number().int().nonnegative(),
  delivered_driver_events: z.number().int().nonnegative(), driver_release_seen: z.boolean(),
  interruption_reason: z.string().nullable(), interrupted_at_ms: z.number().nonnegative().nullable(),
  first_blocked_at_ms: z.number().nonnegative().nullable(), last_delivered_at_ms: z.number().nonnegative().nullable(),
  button_released_at_ms: z.number().nonnegative().nullable(), synthetic_buttons_released: z.boolean(),
  native_drag_seen: z.boolean(), native_drag_cancelled: z.boolean(), cancel_sent: z.boolean(),
})
/** Native observation and independently verified restoration outcomes. */
export type InteractionReport = z.infer<typeof Finished>

/** Failure before input, or an uncertain outcome after native input. */
export class InteractionError extends HarnessError {
  /**
   * @param code - Stable failure identity for the interaction observer.
   * @param cause - Retained native process or protocol failure.
   */
  constructor(code: 'NATIVE_INTERACTION_UNAVAILABLE' | 'NATIVE_INTERACTION_FAILED' | 'NATIVE_INTERACTION_UNTRUSTED' | 'NATIVE_GESTURE_CANCEL_UNCONFIRMED' | 'NATIVE_INPUT_STOP_UNCONFIRMED', cause?: unknown) {
    super(code === 'NATIVE_INTERACTION_UNAVAILABLE'
      ? 'Safe foreground drag restoration is unavailable; no drag was sent. Check host accessibility access or explicitly set both restore_user_state:false and interrupt_on_user_input:false.'
      : code === 'NATIVE_INTERACTION_UNTRUSTED'
        ? 'Native gesture shutdown is unverified. The input fence remains until the worker settles or exits. Restart the Host before further computer input.'
        : code === 'NATIVE_GESTURE_CANCEL_UNCONFIRMED'
          ? 'Driver input stopped, but native drag cancellation is unverified. Press Escape locally and inspect desktop state before further input.'
          : code === 'NATIVE_INPUT_STOP_UNCONFIRMED'
            ? 'Native input observation was interrupted; gesture input may have continued. Inspect desktop state before further input.'
            : 'Foreground drag restoration failed; the drag may have landed. Inspect fresh desktop state before retrying.', code, { cause })
  }
}

/** One supervised process; closing it never restores desktop state. */
export interface InteractionLease {
  /** Stop the leased worker's input without suppressing external events. */
  interrupt(): void
  /** Detach an orphan fence after failed worker shutdown; it exits only after driver release or exit. */
  retainUntilDriverExit(): void
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
 * @param protect - Whether outside input fences the worker; false observes without filtering.
 * @returns Ready observer, owned until close settles.
 */
export async function beginInteraction(
  config: InteractionConfig, driverPid: number, signal: AbortSignal, protect = true,
): Promise<InteractionLease> {
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
    if (receivedBytes > 65_536) { failure = new Error('interaction observer exceeded protocol limit'); child.stdout.pause(); wake?.(); return }
    const parts = buffered.split('\n')
    buffered = parts.pop() ?? ''
    lines.push(...parts)
    wake?.()
  })
  child.on('close', () => { failure ??= new Error('interaction observer closed'); wake?.() })
  child.stdin.on('error', (error) => { failure = error; wake?.() })
  let ready = false
  const interrupt = () => { if (!child.stdin.destroyed) child.stdin.write('{"command":"cancel"}\n') }
  const abort = () => { if (ready) interrupt(); else child.kill() }
  signal.addEventListener('abort', abort, { once: true })
  let closing: Promise<void> | undefined
  let retained = false
  function retainUntilDriverExit(): void {
    retained = true
    signal.removeEventListener('abort', abort)
    interrupt()
    child.stdin.end()
    child.stdout.destroy()
    child.unref()
  }
  function close(): Promise<void> {
    if (retained) return Promise.resolve()
    return closing ??= (async () => {
      signal.removeEventListener('abort', abort)
      child.stdin.end()
      const timer = setTimeout(() => { child.kill('SIGKILL') }, config.timeoutMs)
      try { await ended } finally { clearTimeout(timer) }
    })()
  }
  async function read(observeCancellation: boolean): Promise<unknown> {
    const deadline = AbortSignal.timeout(config.timeoutMs)
    const cancelled = observeCancellation ? AbortSignal.any([signal, deadline]) : deadline
    for (;;) {
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
      const value: unknown = JSON.parse(line)
      const progress = z.object({ type: z.literal('progress'), phase: z.enum(['pressed', 'native_drag', 'interrupted']), elapsed_ms: z.number().nonnegative() }).safeParse(value)
      if (!progress.success) return value
    }
  }
  try {
    child.stdin.write(JSON.stringify({ command: 'begin', begin: { driverPid, timeoutMs: config.timeoutMs, pollMs: config.pollMs, leaseMs: config.leaseMs, protect, notify: true } }) + '\n')
    z.object({ type: z.literal('ready'), protocol: z.literal(2) }).parse(await read(true))
    ready = true
    signal.throwIfAborted()
    return {
      interrupt,
      retainUntilDriverExit,
      async finish(restore) {
        child.stdin.write(JSON.stringify({ command: 'finish', restore }) + '\n')
        try { return Finished.parse(await read(false)) } catch (error) {
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
