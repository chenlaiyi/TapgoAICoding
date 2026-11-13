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
    'For macOS desktop-scope foreground drags, defaults to true: restore the original application focus and physical pointer only after the gesture ends and no outside input or unexpected activation was observed. Fails before input if observation is unavailable. False keeps the upstream behavior. Restoration is reported separately from whether the drop landed. Other drag modes do not use this option.' } } }
}

/**
 * Deliver one drag and report verified restoration independently of its drop result.
 * @param args - Parsed model arguments, including the optional restoration choice.
 * @param config - Native observation executable and bounded operation timing.
 * @param call - Cancellation-aware raw SDK dispatcher.
 * @param signal - Caller and provider lifetime cancellation.
 * @returns Upstream result with a logged restoration report for protected drags.
 */
export async function restoringDrag(
  args: Record<string, unknown>, config: InteractionConfig, call: NativeCall, signal: AbortSignal,
): Promise<unknown> {
  const target = args.target
  const desktop = args.scope === 'desktop' || (target !== null && typeof target === 'object' && 'kind' in target && target.kind === 'desktop')
  const supported = desktop && args.delivery_mode === 'foreground'
  const requested = args.restore_user_state
  if (requested !== undefined && typeof requested !== 'boolean') throw new ToolArgsError(['restore_user_state must be a boolean'])
  if (requested === true && !supported) throw new ToolArgsError(['restore_user_state:true requires a desktop-scope foreground drag'])
  const rawArgs = { ...args }
  delete rawArgs.restore_user_state
  if (!supported || requested === false) return call('drag', rawArgs, signal)
  const { structuredContent: { source: { pid } } } = PermissionSource.parse(await call('check_permissions', { prompt: false }, signal))
  const lease = await beginInteraction(config, pid, signal)
  try {
    const result = Envelope.parse(await call('drag', rawArgs, signal))
    signal.throwIfAborted()
    const report = await lease.finish(result.isError !== true)
    signal.throwIfAborted()
    const restored = report.status === 'restored'
    return { ...result, structuredContent: { ...result.structuredContent, user_state_restoration: report },
      content: [...result.content, { type: 'text', text: `User-state restoration: ${report.status}; focus_restored=${report.focus_restored}, pointer_restored=${report.pointer_restored}. This does not verify the drop.${restored ? '' : `\n${JSON.stringify(report)}`}` }],
      ...!restored && result.isError !== true ? { isError: true } : {},
    }
  } catch (error) {
    signal.throwIfAborted()
    if (error instanceof InteractionError) throw error
    throw new InteractionError('NATIVE_INTERACTION_FAILED', error)
  } finally { await lease.close() }
}
