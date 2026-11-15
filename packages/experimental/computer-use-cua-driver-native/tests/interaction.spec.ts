/** Native observer protocol ownership without access to any host desktop. */
import { readFile, rm } from 'node:fs/promises'
import { afterEach, describe, expect, it } from 'vitest'
import { beginInteraction } from '../src/interaction.ts'
import { restoringDrag as dispatchDrag, type NativeCall } from '../src/restoring-drag.ts'
import type { InteractionConfig } from '../src/interaction.ts'

// Fake dispatchers own no native work after their returned promise settles.
const restoringDrag = (args: Record<string, unknown>, config: InteractionConfig, call: NativeCall, signal: AbortSignal) =>
  dispatchDrag(args, config, call, signal, async () => {})
import { createInteractionFixture } from './fixtures/interaction-helper.ts'

const roots: string[] = []
afterEach(async () => { for (const path of roots.splice(0)) await rm(path, { recursive: true, force: true }) })
async function fixture(mode = 'restored') {
  const value = await createInteractionFixture(mode)
  roots.push(value.root)
  return { ...value,
    async exited() { const pid = Number(await readFile(value.pidPath, 'utf8')); expect(() => process.kill(pid, 0)).toThrow() } }
}

describe.skipIf(process.platform === 'win32')('macOS observer process transport', () => {
  it('returns separately observed restoration and reaps the observer before completion', async () => {
    const helper = await fixture()
    const calls: string[] = []
    const result = await restoringDrag({ scope: 'desktop', delivery_mode: 'foreground', from_x: 1, from_y: 2, to_x: 3, to_y: 4 }, helper.config,
      async (name) => { calls.push(name); return name === 'check_permissions' ? { structuredContent: { source: { pid: 123 } } } : { content: [{ type: 'text', text: 'drag posted' }], structuredContent: { effect: 'unverifiable' } } }, new AbortController().signal)
    expect(calls).toEqual(['check_permissions', 'drag'])
    expect(result).toMatchObject({ structuredContent: { effect: 'unverifiable',
      user_state_restoration: { status: 'restored', focus_restored: true, pointer_restored: true } } })
    await helper.exited()
  })

  it('reports takeover without turning a delivered drag into claimed success', async () => {
    const helper = await fixture('outside_input_or_activation')
    const result = await restoringDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config,
      async name => name === 'check_permissions'
        ? { structuredContent: { source: { pid: 123 } } }
        : { content: [], structuredContent: { effect: 'unverifiable' } }, new AbortController().signal)
    expect(result).toMatchObject({ isError: true, structuredContent: {
      user_state_restoration: { outside_input: true, focus_restored: false, pointer_restored: false } } })
    expect(JSON.stringify(result)).toContain('external_source_pids')
    await helper.exited()
  })

  it('refuses unavailable observation before sending input', async () => {
    const helper = await fixture('unavailable'); const calls: string[] = []
    await expect(restoringDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name) => {
      calls.push(name); return { structuredContent: { source: { pid: 123 } } }
    }, new AbortController().signal)).rejects.toMatchObject({ code: 'NATIVE_INTERACTION_UNAVAILABLE' })
    expect(calls).toEqual(['check_permissions']); await helper.exited()
  })

  it('closes the observer when a caller cancels the drag', async () => {
    const helper = await fixture(); const controller = new AbortController()
    await expect(restoringDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name) => {
      if (name === 'check_permissions') return { structuredContent: { source: { pid: 123 } } }
      controller.abort(new Error('cancelled by caller')); return { content: [] }
    }, controller.signal)).rejects.toThrow('cancelled by caller')
    await helper.exited()
  })

  it('fences cancellation while retaining the SDK operation until its completion', async () => {
    const helper = await fixture('interrupted'); const owner = new AbortController()
    const entered = Promise.withResolvers<AbortSignal>(); const complete = Promise.withResolvers<unknown>()
    const task = dispatchDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name, _args, signal) => {
      if (name === 'check_permissions') return { structuredContent: { source: { pid: 123 } } }
      entered.resolve(signal); return complete.promise
    }, owner.signal, async () => {})
    const outcome = task.then(() => ({ code: 'unexpected_success' }), (error: unknown) => error)
    try {
      const delivery = await entered.promise
      owner.abort(new Error('user stopped'))
      await expect.poll(() => readFile(helper.cancelPath, 'utf8'), { timeout: helper.config.timeoutMs }).toBe('1')
      expect(delivery.aborted).toBe(false)
      const pid = Number(await readFile(helper.pidPath, 'utf8')); expect(() => process.kill(pid, 0)).not.toThrow()
    } finally { complete.resolve({ content: [] }); await outcome; await helper.exited() }
    expect(await outcome).toMatchObject({ message: 'user stopped' })
  })

  it('awaits worker quiescence after a dispatch loses its result before reaping the fence', async () => {
    const helper = await fixture(); const draining = Promise.withResolvers<undefined>(); const drained = Promise.withResolvers<undefined>()
    const task = dispatchDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name) => {
      if (name === 'check_permissions') return { structuredContent: { source: { pid: 123 } } }
      throw new Error('transport closed after dispatch')
    }, new AbortController().signal, async () => { draining.resolve(undefined); await drained.promise })
    const outcome = task.then(() => ({ code: 'unexpected_success' }), (error: unknown) => error)
    try {
      await draining.promise
      await expect.poll(() => readFile(helper.cancelPath, 'utf8'), { timeout: helper.config.timeoutMs }).toBe('1')
      const pid = Number(await readFile(helper.pidPath, 'utf8')); expect(() => process.kill(pid, 0)).not.toThrow()
    } finally { drained.resolve(undefined); await outcome; await helper.exited() }
    expect(await outcome).toMatchObject({ code: 'NATIVE_INTERACTION_FAILED' })
  })

  it('keeps interruption protection when focus and pointer restoration are disabled', async () => {
    const helper = await fixture('interrupted')
    const result = await restoringDrag({ scope: 'desktop', delivery_mode: 'foreground', restore_user_state: false }, helper.config,
      async name => name === 'check_permissions' ? { structuredContent: { source: { pid: 123 } } } : { content: [] }, new AbortController().signal)
    expect(JSON.parse(await readFile(helper.beginPath, 'utf8'))).toMatchObject({ begin: { protect: true } })
    expect(result).toMatchObject({ isError: true, structuredContent: { user_state_restoration: { input_stopped: true } } })
    await helper.exited()
  })

  it('reports uncertain native cancellation before the caller cancellation', async () => {
    const helper = await fixture('native_drag_cancel_unconfirmed'); const owner = new AbortController()
    await expect(restoringDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name) => {
      if (name === 'check_permissions') return { structuredContent: { source: { pid: 123 } } }
      owner.abort(new Error('cancelled')); return { content: [] }
    }, owner.signal)).rejects.toMatchObject({ code: 'NATIVE_GESTURE_CANCEL_UNCONFIRMED' })
    await helper.exited()
  })

  it('reports failed worker shutdown as untrusted rather than claiming cancellation', async () => {
    const helper = await fixture()
    await expect(dispatchDrag({ scope: 'desktop', delivery_mode: 'foreground' }, helper.config, async (name) => {
      if (name === 'check_permissions') return { structuredContent: { source: { pid: 123 } } }
      throw new Error('lost delivery result')
    }, new AbortController().signal, async () => { throw new Error('shutdown failed') })).rejects.toMatchObject({ code: 'NATIVE_INTERACTION_UNTRUSTED' })
    await expect.poll(async () => {
      const pid = Number(await readFile(helper.pidPath, 'utf8'))
      try { process.kill(pid, 0); return false } catch { return true }
    }, { timeout: helper.config.timeoutMs }).toBe(true)
  })

  it('bounds and reaps a stalled finish after the observer is ready', { timeout: 20_000 }, async () => {
    const helper = await fixture('hang')
    const lease = await beginInteraction(helper.config, 123, new AbortController().signal)
    try { await expect(lease.finish(true)).rejects.toMatchObject({ code: 'NATIVE_INTERACTION_FAILED' }) }
    finally { await lease.close() }
    await helper.exited()
  })
})

it('keeps explicit opt-out and background drags on their original route', async () => {
  const helper = { helperPath: '/not-started', timeoutMs: 1000, pollMs: 20, leaseMs: 30000 }
  const seen: unknown[] = []
  for (const args of [{ scope: 'desktop', delivery_mode: 'foreground', restore_user_state: false, interrupt_on_user_input: false }, { pid: 1, window_id: 2, delivery_mode: 'background' }]) {
    await restoringDrag(args, helper, async (_name, values) => { seen.push(values); return { content: [] } }, new AbortController().signal)
  }
  expect(seen).toEqual([{ scope: 'desktop', delivery_mode: 'foreground' }, { pid: 1, window_id: 2, delivery_mode: 'background' }])
  await expect(restoringDrag({ pid: 1, restore_user_state: true }, helper, async () => undefined, new AbortController().signal)).rejects.toMatchObject({ code: 'INVALID_ARGS' })
})

it('rejects protected modifier drags before dispatch and accepts an explicit upstream opt-out', async () => {
  const helper = { helperPath: '/not-started', timeoutMs: 1000, pollMs: 20, leaseMs: 30000 }
  const calls: unknown[] = []
  const call: NativeCall = async (_name, args) => { calls.push(args); return { content: [] } }
  const args = { scope: 'desktop', delivery_mode: 'foreground', modifier: ['shift'] }
  await expect(restoringDrag(args, helper, call, new AbortController().signal)).rejects.toMatchObject({ code: 'INVALID_ARGS' })
  expect(calls).toEqual([])
  await restoringDrag({ ...args, restore_user_state: false, interrupt_on_user_input: false }, helper, call, new AbortController().signal)
  expect(calls).toEqual([args])
})
