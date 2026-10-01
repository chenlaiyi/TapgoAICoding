import type { Context } from '@deepseek-ai/cordis'
import type { CredentialProvider, CredentialRecord } from '@deepseek-ai/dsh-credentials'

/** Mutable credential-record double for Connection authentication tests. */
export class RecordCredentials {
  record: CredentialRecord | undefined
  mobileRecord: CredentialRecord | undefined
  discardWrites = false
  reads = 0
  modifies = 0

  readRecord(key?: unknown): Promise<CredentialRecord | undefined> {
    this.reads += 1
    return Promise.resolve(String(key).endsWith('/mobile-pairings') ? this.mobileRecord : this.record)
  }

  async modifyRecord(
    key: unknown,
    mutate: (current: CredentialRecord | undefined) => Promise<CredentialRecord | undefined>,
  ): Promise<CredentialRecord | undefined> {
    this.modifies += 1
    const mobile = String(key).endsWith('/mobile-pairings')
    const next = await mutate(mobile ? this.mobileRecord : this.record)
    if (this.discardWrites) return undefined
    if (next !== undefined) {
      if (mobile) this.mobileRecord = next
      else this.record = next
    }
    return mobile ? this.mobileRecord : this.record
  }

  deleteRecord(): Promise<void> {
    this.record = undefined
    return Promise.resolve()
  }
}

/** Provide the record operations Connection needs during authentication setup. */
export function provideBrowserCredentials(ctx: Context): void {
  ctx.provide('credentials', new RecordCredentials() as unknown as CredentialProvider)
}
