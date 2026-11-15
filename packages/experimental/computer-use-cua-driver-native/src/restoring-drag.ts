/** SDK drag delivery with a separately observed, conditional user-state restore. */
import { z } from 'zod'
import { ToolArgsError } from '@deepseek-ai/dsh-tools'
import { beginInteraction, InteractionError, type InteractionConfig } from './interaction.ts'

/** Raw SDK tool dispatcher with the provider's cancellation and failure handling. */
export type NativeCall = (name: string, args: Record<string, unknown>, signal: AbortSignal) => Promise<unknown>

const PermissionSource = z.object({ structuredContent: z.object({ source: z.object({ pid: z.number().int().positive() }) }) })
const Envelope = z.looseObject({
  content: z.array(z.unknown()), isError: z.boolean().optional(), structuredContent: z.record(z.string(), z.unknown()).optional(),
})

/**
 * Extend only the configured macOS drag schema with conditional restoration.
 * @param input - Upstream object-parameter schema.
 * @returns Parameters including the Desktop-owned restoration option.
 */
export function restoringDragSchema(input: Record<string, unknown>): Record<string, unknown> {
  const properties = z.record(z.string(), z.unknown()).parse(input.properties)
  return { ...input, properties: { ...properties, restore_user_state: { type: 'boolean', description:
    'For macOS desktop-scope foreground drags, defaults to true: restore the original application focus and physical pointer after an uninterrupted gesture. Restoration does not verify the drop. Other drag modes do not use this option.' },
  interrupt_on_user_input: { type: 'boolean', description:
    'For macOS desktop-scope foreground drags, defaults to true: stop subsequent driver input and cancel the source gesture when outside input or caller cancellation is observed. External input is never blocked. The SDK call may remain busy while its input is fenced. Requires no modifier keys; set false to keep upstream delivery. If safe observation is unavailable, no drag is sent.' } } }
}

/**
 * Deliver one drag and report verified restoration independently of its drop result.
 * @param args - Parsed model arguments, including the optional restoration choice.
 * @param config - Native observation executable and bounded operation timing.
 * @param call - Cancellation-aware raw SDK dispatcher.
 * @param signal - Caller and provider lifetime cancellation.
 * @param quiesce - Close SDK admission and await admitted operations after an uncertain dispatch failure.
 * @returns Upstream result with a logged restoration report for protected drags.
 */
export async function restoringDrag(
  args: Record<string, unknown>, config: InteractionConfig, call: NativeCall, signal: AbortSignal, quiesce: () => Promise<void>,
): Promise<unknown> {
  const target = args.target
  const desktop = args.scope === 'desktop' || (target !== null && typeof target === 'object' && 'kind' in target && target.kind === 'desktop')
  const supported = desktop && args.delivery_mode === 'foreground'
  const requested = args.restore_user_state
  const interruption = args.interrupt_on_user_input
  if (requested !== undefined && typeof requested !== 'boolean') throw new ToolArgsError(['restore_user_state must be a boolean'])
  if (interruption !== undefined && typeof interruption !== 'boolean') throw new ToolArgsError(['interrupt_on_user_input must be a boolean'])
  if (requested === true && !supported) throw new ToolArgsError(['restore_user_state:true requires a desktop-scope foreground drag'])
  if (interruption === true && !supported) throw new ToolArgsError(['interrupt_on_user_input:true requires a desktop-scope foreground drag'])
  const protect = interruption !== false
  const restore = requested !== false
  if (supported && protect && Array.isArray(args.modifier) && args.modifier.length > 0) {
    throw new ToolArgsError(['interrupt_on_user_input with modifier keys is unavailable; explicitly set interrupt_on_user_input:false to use upstream modifier delivery'])
  }
  const rawArgs = { ...args }
  delete rawArgs.restore_user_state
  delete rawArgs.interrupt_on_user_input
  if (!supported || (!restore && !protect)) return call('drag', rawArgs, signal)
  const { structuredContent: { source: { pid } } } = PermissionSource.parse(await call('check_permissions', { prompt: false }, signal))
  const lease = await beginInteraction(config, pid, signal, protect)
  let dispatched = false
  let settled = false
  try {
    // The SDK's blocking gesture must settle before the native input fence closes.
    const deliverySignal = protect ? new AbortController().signal : signal
    signal.throwIfAborted()
    dispatched = true
    const rawResult = await call('drag', rawArgs, deliverySignal)
    settled = true
    const result = Envelope.parse(rawResult)
    const report = await lease.finish(restore && result.isError !== true && !signal.aborted)
    if (report.monitor_lost) throw new InteractionError('NATIVE_INPUT_STOP_UNCONFIRMED', report)
    if (report.status === 'native_drag_cancel_unconfirmed') throw new InteractionError('NATIVE_GESTURE_CANCEL_UNCONFIRMED', report)
    signal.throwIfAborted()
    const completed = report.status === 'restored' || (!restore && report.status === 'not_requested' && !report.input_stopped)
    return { ...result, structuredContent: { ...result.structuredContent, user_state_restoration: report },
      content: [...result.content, { type: 'text', text: `User-state restoration: ${report.status}; focus_restored=${report.focus_restored}, pointer_restored=${report.pointer_restored}. This does not verify the drop.${completed ? '' : `\n${JSON.stringify(report)}`}` }],
      ...!completed && result.isError !== true ? { isError: true } : {},
    }
  } catch (error) {
    lease.interrupt()
    if (dispatched && !settled) {
      try { await quiesce() }
      catch (cause) {
        lease.retainUntilDriverExit()
        throw new InteractionError('NATIVE_INTERACTION_UNTRUSTED', cause)
      }
    }
    if (error instanceof InteractionError) throw error
    signal.throwIfAborted()
    throw new InteractionError('NATIVE_INTERACTION_FAILED', error)
  } finally { await lease.close() }
}
