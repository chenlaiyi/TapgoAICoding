/** Official API funds retain safe results and exclude superseded credential responses. */
import { expect, it, vi } from 'vitest'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'
import { ApiBalanceController } from '../src/client/api-balance.ts'

const funds: readonly LlmBalance[] = [{ currency: 'CNY', amount: '86.77' }]

it('retains current-key funds during refresh and reports unsupported, empty and failed reads', async () => {
  const read = vi.fn(async (): Promise<readonly LlmBalance[] | null> => funds)
  const controller = new ApiBalanceController(read)
  try {
    controller.refresh()
    await vi.waitFor(() => { expect(controller.store.getSnapshot()).toEqual({ status: 'ready', value: funds }) })
    for (const value of [null, []] as const) {
      read.mockResolvedValueOnce(value)
      controller.refresh()
      expect(controller.store.getSnapshot()).toEqual({ status: 'loading', value: funds })
      await vi.waitFor(() => { expect(controller.store.getSnapshot()).toEqual({ status: 'unavailable', value: funds }) })
    }
    read.mockRejectedValueOnce(new Error('unavailable'))
    controller.refresh(true)
    expect(controller.store.getSnapshot()).toEqual({ status: 'loading', value: null })
    await vi.waitFor(() => { expect(controller.store.getSnapshot()).toEqual({ status: 'unavailable', value: null }) })
    controller.refresh()
    await vi.waitFor(() => { expect(controller.store.getSnapshot()).toEqual({ status: 'ready', value: funds }) })
  } finally { controller.dispose() }
})

it.each(['resolve', 'reject'] as const)('ignores a replaced or disposed request that later %ss', async (outcome) => {
  const stale = Promise.withResolvers<readonly LlmBalance[] | null>()
  const read = vi.fn<(signal: AbortSignal) => Promise<readonly LlmBalance[] | null>>()
    .mockReturnValueOnce(stale.promise).mockResolvedValue(funds)
  const controller = new ApiBalanceController(read)
  try {
    controller.refresh()
    const signal = read.mock.calls[0]![0]
    controller.refresh(true)
    expect(signal.aborted).toBe(true)
    await vi.waitFor(() => { expect(controller.store.getSnapshot()).toEqual({ status: 'ready', value: funds }) })
    if (outcome === 'resolve') stale.resolve([{ currency: 'CNY', amount: '999' }])
    else stale.reject(new Error('old credential'))
    await stale.promise.catch(() => {})
    expect(controller.store.getSnapshot()).toEqual({ status: 'ready', value: funds })
    const pending = Promise.withResolvers<readonly LlmBalance[] | null>()
    read.mockReturnValueOnce(pending.promise)
    controller.refresh()
    const latest = read.mock.calls.at(-1)![0]
    controller.dispose()
    expect(latest.aborted).toBe(true)
    const before = controller.store.getSnapshot()
    controller.refresh()
    expect(read).toHaveBeenCalledTimes(3)
    if (outcome === 'resolve') pending.resolve(funds)
    else pending.reject(new Error('disposed'))
    await pending.promise.catch(() => {})
    expect(controller.store.getSnapshot()).toBe(before)
  } finally {
    stale.resolve(null)
    controller.dispose()
  }
})
