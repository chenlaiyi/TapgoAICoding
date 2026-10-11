import { Context } from '@deepseek-ai/cordis'
import { afterEach, expect, it, vi } from 'vitest'
import LlmRuntime, { LlmAdapter } from '../src/index.ts'
import type { LlmBalance, StreamChunk } from '../src/types.ts'

class BalanceAdapter extends LlmAdapter {
  override getBalance = vi.fn<(provider: string, signal?: AbortSignal) => Promise<LlmBalance[] | null>>()
    .mockResolvedValue([{ currency: 'CNY', amount: '12.50' }])
  async *stream(): AsyncIterable<StreamChunk> {}
}

const contexts: Context[] = []
afterEach(async () => { await Promise.all(contexts.splice(0).map(ctx => ctx.fiber.dispose())) })

async function runtime() {
  const ctx = new Context()
  contexts.push(ctx)
  await ctx.plugin(LlmRuntime)
  return ctx
}

it('queries only the requested provider and forwards cancellation', async () => {
  const ctx = await runtime()
  const adapter = new BalanceAdapter()
  ctx.llm.registerAdapter(['chosen'], adapter)
  const controller = new AbortController()
  expect(await ctx.llm.getBalance('chosen', controller.signal)).toEqual([{ currency: 'CNY', amount: '12.50' }])
  expect(adapter.getBalance).toHaveBeenCalledWith('chosen', controller.signal)
  expect(await ctx.llm.getBalance('other')).toBeNull()
  expect(adapter.getBalance).toHaveBeenCalledTimes(1)
})

it('returns no balance when an adapter does not offer queries', async () => {
  const ctx = await runtime()
  class UnsupportedAdapter extends LlmAdapter { async *stream(): AsyncIterable<StreamChunk> {} }
  ctx.llm.registerAdapter(['unsupported'], new UnsupportedAdapter())
  expect(await ctx.llm.getBalance('unsupported')).toBeNull()
})

it('does not publish balances from a removed adapter', async () => {
  const ctx = await runtime()
  const adapter = new BalanceAdapter()
  const response = Promise.withResolvers<LlmBalance[]>()
  adapter.getBalance.mockReturnValueOnce(response.promise)
  const dispose = ctx.llm.registerAdapter(['chosen'], adapter)
  const reading = ctx.llm.getBalance('chosen')
  dispose()
  response.resolve([{ currency: 'CNY', amount: '99.00' }])
  expect(await reading).toBeNull()
})

it('reports query failure without exposing provider errors or querying another account', async () => {
  const ctx = await runtime()
  const adapter = new BalanceAdapter()
  adapter.getBalance.mockRejectedValueOnce(new Error('private provider response'))
  ctx.llm.registerAdapter(['chosen'], adapter)
  await expect(ctx.llm.getBalance('chosen')).rejects.toMatchObject({ code: 'llm/balance-unavailable', message: 'The provider balance could not be read.' })
})

it('rejects cancelled reads before and after adapter work', async () => {
  const ctx = await runtime()
  const adapter = new BalanceAdapter()
  ctx.llm.registerAdapter(['chosen'], adapter)
  const controller = new AbortController()
  controller.abort()
  await expect(ctx.llm.getBalance('chosen', controller.signal)).rejects.toMatchObject({ code: 'llm/balance-unavailable' })
  expect(adapter.getBalance).not.toHaveBeenCalled()
  const pending = new AbortController()
  adapter.getBalance.mockImplementationOnce(async () => { pending.abort(); return [] })
  await expect(ctx.llm.getBalance('chosen', pending.signal)).rejects.toMatchObject({ code: 'llm/balance-unavailable' })
})
