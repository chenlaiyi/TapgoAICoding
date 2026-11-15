/** Exact-window activation verification for native window-control compositor surfaces. */
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { z } from 'zod'
import { HarnessError } from '@deepseek-ai/dsh-error'
import type { InteractionConfig } from './interaction.ts'
import type { NativeCall } from './restoring-drag.ts'

const WindowId = z.number().int().positive()
const Inspection = z.object({
  type: z.literal('focus'), pid: WindowId,
  requested_window_id: WindowId.nullable(), resolved_window_id: WindowId.nullable(),
  focused_window_id: WindowId.nullable(), front_window_id: WindowId.nullable(),
  eligible_window_ids: z.array(WindowId), ignored_control_window_ids: z.array(WindowId),
  unmapped_window_ids: z.array(WindowId), verified: z.boolean(), reason: z.string(),
})
const Attempt = z.object({ isError: z.literal(true), structuredContent: z.object({
  code: z.literal('bring_to_front_exact_window_unverified'), pid: WindowId, window_id: WindowId,
  request_accepted: z.literal(true), process_activated: z.literal(true),
  exact_window_effect: z.object({ focused: z.literal(true) }),
}) })
const Envelope = z.looseObject({
  content: z.array(z.unknown()), structuredContent: z.record(z.string(), z.unknown()).optional(), isError: z.boolean().optional(),
})

async function inspect(config: InteractionConfig, pid: number, window: number | undefined, signal: AbortSignal) {
  const { stdout } = await promisify(execFile)(config.helperPath,
    ['--inspect-focus', String(pid), String(window ?? 0), String(config.timeoutMs)],
    { encoding: 'utf8', env: {}, timeout: config.timeoutMs, maxBuffer: 65_536, signal })
  const result = Inspection.parse(JSON.parse(stdout))
  if (result.pid !== pid || result.requested_window_id !== (window ?? null)) throw new Error('native focus inspection target differs')
  return result
}

/**
 * Activate through the SDK, correcting only independently verified window-control surfaces.
 * @param args - Upstream app and optional exact-window arguments.
 * @param config - Signed read-only inspection executable and operation bounds.
 * @param call - SDK dispatcher; activation and session registration remain SDK-owned.
 * @param signal - Caller and provider cancellation.
 * @returns SDK result or an independently verified exact-window result with both observations.
 */
export async function nativeBringToFront(
  args: Record<string, unknown>, config: InteractionConfig, call: NativeCall, signal: AbortSignal,
): Promise<unknown> {
  const target = z.object({ pid: WindowId, window_id: WindowId.optional() }).safeParse(args)
  if (!target.success) return call('bring_to_front', args, signal)
  let request = args
  if (target.data.window_id === undefined) {
    let info: z.infer<typeof Inspection>
    try { info = await inspect(config, target.data.pid, undefined, signal) }
    catch (cause) {
      signal.throwIfAborted()
      throw new HarnessError('Native window inspection is unavailable; no activation was sent. Check the packaged macOS helper.',
        'NATIVE_FOCUS_UNAVAILABLE', { cause })
    }
    if (info.eligible_window_ids.length === 1 && info.ignored_control_window_ids.length > 0
      && info.unmapped_window_ids.length === 0 && info.resolved_window_id !== null) {
      const listed = Envelope.parse(await call('list_windows',
        { pid: target.data.pid, ...args.session === undefined ? {} : { session: args.session } }, signal))
      if (listed.isError) return listed
      const windows = z.object({ windows: z.array(z.object({ pid: WindowId, window_id: WindowId })) }).parse(listed.structuredContent)
      if (windows.windows.some(window => window.pid === target.data.pid && window.window_id === info.resolved_window_id)) {
        request = { ...args, window_id: info.resolved_window_id }
      }
    }
  }
  const result = Envelope.parse(await call('bring_to_front', request, signal))
  const attempt = Attempt.safeParse(result)
  if (!attempt.success || attempt.data.structuredContent.pid !== target.data.pid) return result
  const requested = attempt.data.structuredContent.window_id
  if (request.window_id !== undefined && requested !== request.window_id) return result
  try {
    const info = await inspect(config, target.data.pid, requested, signal)
    if (!info.verified || info.resolved_window_id !== requested || info.ignored_control_window_ids.length === 0) {
      return { ...result, content: [...result.content, { type: 'text', text: JSON.stringify({ native_window_verification: info }) }] }
    }
    return { isError: false,
      content: [{ type: 'text', text: `Verified exact focused window ${requested} for pid ${target.data.pid}.` }],
      structuredContent: { status: 'activated', code: 'bring_to_front_native_ax_verified', activated: true,
        pid: target.data.pid, window_id: requested, native_window_verification: info, sdk_observation: result.structuredContent },
    }
  } catch (cause) {
    signal.throwIfAborted()
    return { ...result, content: [...result.content, { type: 'text',
      text: 'Native exact-window verification is unavailable; activation remains unverified.' }],
    structuredContent: { ...result.structuredContent, native_verification_error: cause instanceof Error ? cause.message : String(cause) } }
  }
}
