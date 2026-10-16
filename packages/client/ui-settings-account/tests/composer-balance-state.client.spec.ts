/** Provider changes and credential races in the session-owned composer balance. */
import { expect, it, onTestFinished, vi } from 'vitest'
import { createSnapshotStore } from '@deepseek-ai/dsh-client-store'
import type { ModelDirectoryState } from '@deepseek-ai/dsh-client-ui-model-selection/client'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'
import { ComposerBalanceController } from '../src/client/composer-balance.ts'
import type { AccountSnapshot } from '../src/client/AccountSection.tsx'

const funds = [{ currency: 'USD', amount: '8.00' }]
const selected = (provider: string): ModelDirectoryState => ({
  current: { provider, model: 'model' }, routable: true, status: 'ready', groups: [], failures: [], pending: null, error: null,
})
const accountState: AccountSnapshot = {
  avatar: undefined,
  view: { status: 'credential-stored', attempt: null, links: { usageUrl: '', topUpUrl: '' } }, failed: false,
  details: { balance: { status: 'ready', value: [{ currency: 'CNY', balance: '10.00' }],
    bonusWallets: [{ currency: 'CNY', balance: '1.00' }] } },
}

function bench(provider = 'deepseek-account') {
  const directory = createSnapshotStore(selected(provider))
  const account = createSnapshotStore(accountState)
  const read = vi.fn<(provider: string, signal: AbortSignal) => Promise<readonly LlmBalance[] | null>>()
    .mockResolvedValue(funds)
  const balance = new ComposerBalanceController(directory, account, read)
  onTestFinished(() => { balance.dispose() })
  return { directory, account, read, balance }
}

it('uses account wallets only for an available account model and keeps API-key funds after sign-out', async () => {
  const b = bench()
  expect(b.balance.store.getSnapshot()).toEqual([{ currency: 'CNY', amount: '10.00' }, { currency: 'CNY', amount: '1.00' }])
  expect(b.read).not.toHaveBeenCalled()
  b.directory.set(selected('deepseek-official'))
  expect(b.balance.store.getSnapshot()).toBeNull()
  await vi.waitFor(() => { expect(b.balance.store.getSnapshot()).toEqual(funds) })
  b.account.set({ avatar: undefined, failed: false, view: undefined, details: undefined })
  expect(b.balance.store.getSnapshot()).toEqual(funds)
  b.directory.set(selected('deepseek-account'))
  expect(b.balance.store.getSnapshot()).toBeNull()
  b.account.set({ ...accountState, details: { balance: { status: 'failed' } } })
  expect(b.balance.store.getSnapshot()).toBeNull()
  b.account.set(accountState)
  expect(b.balance.store.getSnapshot()).toHaveLength(2)
  b.balance.refresh()
  expect(b.read).toHaveBeenCalledOnce()
})

it.each(['loading', 'selecting', 'error'] as const)('hides the old balance while selection is %s', (status) => {
  const b = bench()
  b.directory.set({ ...selected('deepseek-account'), status })
  expect(b.balance.store.getSnapshot()).toBeNull()
})

it('hides missing or unavailable selections', () => {
  const b = bench()
  b.directory.set({ ...selected('deepseek-account'), routable: false })
  expect(b.balance.store.getSnapshot()).toBeNull()
  b.directory.set({ ...selected('deepseek-account'), current: null })
  expect(b.balance.store.getSnapshot()).toBeNull()
})

it('discards stale providers, credential reads and failures after a newer balance commits', async () => {
  const b = bench()
  const stale = Promise.withResolvers<readonly LlmBalance[] | null>()
  const replaced = Promise.withResolvers<readonly LlmBalance[] | null>()
  b.read.mockReturnValueOnce(stale.promise).mockReturnValueOnce(replaced.promise)
  onTestFinished(() => { stale.resolve(funds); replaced.resolve(funds) })
  b.directory.set(selected('old-key'))
  const firstSignal = b.read.mock.calls[0]![1]
  b.directory.set(selected('new-key'))
  expect(firstSignal.aborted).toBe(true)
  b.balance.refresh(true)
  expect(b.balance.store.getSnapshot()).toBeNull()
  expect(b.read.mock.calls[1]![1].aborted).toBe(true)
  await vi.waitFor(() => { expect(b.balance.store.getSnapshot()).toEqual(funds) })
  stale.resolve([{ currency: 'CNY', amount: '99.00' }])
  replaced.reject(new Error('replaced credential'))
  await Promise.allSettled([stale.promise, replaced.promise])
  expect(b.balance.store.getSnapshot()).toEqual(funds)
})

it('hides failed or unsupported queries and refreshes the same provider after activity', async () => {
  const b = bench('deepseek-official')
  await vi.waitFor(() => { expect(b.balance.store.getSnapshot()).toEqual(funds) })
  b.read.mockRejectedValueOnce(new Error('offline'))
  b.balance.refresh()
  await vi.waitFor(() => { expect(b.balance.store.getSnapshot()).toBeNull() })
  b.read.mockResolvedValueOnce(null)
  b.balance.refresh()
  await Promise.resolve()
  expect(b.balance.store.getSnapshot()).toBeNull()
  b.balance.refresh()
  await vi.waitFor(() => { expect(b.balance.store.getSnapshot()).toEqual(funds) })
})

it('aborts reads and releases both subscriptions when disposed', async () => {
  const b = bench()
  const pending = Promise.withResolvers<readonly LlmBalance[] | null>()
  b.read.mockReturnValueOnce(pending.promise)
  onTestFinished(() => { pending.resolve(funds) })
  b.directory.set(selected('deepseek-official'))
  b.balance.dispose()
  expect(b.read.mock.calls[0]![1].aborted).toBe(true)
  pending.resolve(funds)
  await pending.promise
  b.directory.set(selected('other'))
  b.account.set({ ...accountState })
  b.balance.refresh()
  b.balance.dispose()
  expect(b.read).toHaveBeenCalledOnce()
  expect(b.balance.store.getSnapshot()).toBeNull()
})
