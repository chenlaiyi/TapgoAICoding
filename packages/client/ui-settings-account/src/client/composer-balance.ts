/** Session-owned balance projection for the composer's selected provider. */
import { createSnapshotStore } from '@deepseek-ai/dsh-client-store'
import type { HostObservable } from '@deepseek-ai/dsh-client-ui-slots'
import type { ModelDirectoryState } from '@deepseek-ai/dsh-client-ui-model-selection/client'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'
import type { AccountSnapshot } from './AccountSection.tsx'

/** Reads the selected provider without retaining balances across credentials or session disposal. */
export class ComposerBalanceController {
  /** Available funds for the current provider; null while unresolved or unavailable. */
  readonly store = createSnapshotStore<readonly LlmBalance[] | null>(null)
  private provider: string | null = null
  private readonly lifetime = new AbortController()
  private request: AbortController | undefined
  private readonly unsubscribe: (() => void)[]

  /**
   * @param directory - authoritative selection and model availability for one Session.
   * @param account - shared account wallet snapshot used only by deepseek-account.
   * @param read - provider balance query; rejects failed queries and returns null when unsupported.
   */
  constructor(
    private readonly directory: HostObservable<ModelDirectoryState>,
    private readonly account: HostObservable<AccountSnapshot>,
    private readonly read: (provider: string, signal: AbortSignal) => Promise<readonly LlmBalance[] | null>,
  ) {
    this.unsubscribe = [
      directory.subscribe(() => { this.syncDirectory() }),
      account.subscribe(() => { this.syncAccount() }),
    ]
    this.syncDirectory()
  }

  /**
   * Re-read API-key funds after activity; invalidate also clears funds from replaced credentials.
   * @param invalidate - whether the previous amount must be hidden immediately.
   */
  refresh(invalidate = false): void {
    if (this.lifetime.signal.aborted) return
    this.request?.abort()
    this.request = undefined
    if (invalidate) this.store.set(null)
    if (this.provider === null) return
    if (this.provider === 'deepseek-account') {
      this.syncAccount()
      return
    }
    const request = new AbortController()
    this.request = request
    void this.read(this.provider, request.signal).then(
      (value) => { if (!request.signal.aborted) this.store.set(value) },
      (_error: unknown) => { if (!request.signal.aborted) this.store.set(null) },
    )
  }

  /** Release subscriptions and cancel pending reads before the Session or plugin disappears. */
  dispose(): void {
    if (this.lifetime.signal.aborted) return
    this.lifetime.abort()
    this.request?.abort()
    for (const unsubscribe of this.unsubscribe) unsubscribe()
    this.store.set(null)
  }

  private syncDirectory(): void {
    const directory = this.directory.getSnapshot()
    const provider = directory.status === 'ready' && directory.routable === true
      ? directory.current?.provider ?? null : null
    if (provider === this.provider) return
    this.provider = provider
    this.refresh(true)
  }

  private syncAccount(): void {
    if (this.provider !== 'deepseek-account' || this.lifetime.signal.aborted) return
    const account = this.account.getSnapshot()
    const balance = account.details?.balance
    this.store.set(account.view?.status === 'credential-stored' && balance?.status === 'ready'
      ? [...balance.value, ...balance.bonusWallets].map(wallet => ({ currency: wallet.currency, amount: wallet.balance }))
      : null)
  }
}
