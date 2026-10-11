/** Settings-owned DeepSeek API balance, independent of account login and Session selection. */
import { createSnapshotStore } from '@deepseek-ai/dsh-client-store'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'

/** Safe query state; credential replacement clears previously displayed funds. */
export type ApiBalanceSnapshot =
  | { status: 'loading'; value: readonly LlmBalance[] | null }
  | { status: 'ready'; value: readonly LlmBalance[] }
  | { status: 'unavailable'; value: readonly LlmBalance[] | null }

/** Owns the settings balance request and rejects responses from superseded credentials. */
export class ApiBalanceController {
  /** Latest official API funds and query status. */
  readonly store = createSnapshotStore<ApiBalanceSnapshot>({ status: 'loading', value: null })
  private request: AbortController | undefined
  private disposed = false

  /** @param read - official provider query using its currently configured credential reference. */
  constructor(private readonly read: (signal: AbortSignal) => Promise<readonly LlmBalance[] | null>) {}

  /**
   * Query current API funds, cancelling any previous request.
   * @param invalidate - clear funds when their credential or provider configuration changes.
   */
  refresh(invalidate = false): void {
    if (this.disposed) return
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const previous = invalidate ? null : this.store.getSnapshot().value
    this.store.set({ status: 'loading', value: previous })
    void this.read(request.signal).then(
      (value) => {
        if (request.signal.aborted) return
        this.store.set(value !== null && value.length > 0
          ? { status: 'ready', value } : { status: 'unavailable', value: previous })
      },
      (_error: unknown) => {
        if (!request.signal.aborted) this.store.set({ status: 'unavailable', value: previous })
      },
    )
  }

  /** Cancel pending reads before the settings plugin disappears. */
  dispose(): void {
    this.disposed = true
    this.request?.abort()
  }
}
