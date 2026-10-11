/** API-key wallet queries using the same endpoint and credential as model requests. */
import { attributionHeaders, LlmError } from '@deepseek-ai/dsh-llm'
import type { LlmBalance } from '@deepseek-ai/dsh-llm'
import type { ResolvedDeepSeekOptions } from './config.ts'

const decimal = /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/iu

function balances(value: unknown): LlmBalance[] {
  if (typeof value !== 'object' || value === null || !('is_available' in value)
    || typeof value.is_available !== 'boolean' || !('balance_infos' in value) || !Array.isArray(value.balance_infos)) {
    throw new LlmError('DeepSeek balance response is invalid.', 'INVALID_RESPONSE')
  }
  return value.balance_infos.map((row: unknown) => {
    if (typeof row !== 'object' || row === null || !('currency' in row)
      || (row.currency !== 'CNY' && row.currency !== 'USD') || !('total_balance' in row)
      || typeof row.total_balance !== 'string' || !decimal.test(row.total_balance)) {
      throw new LlmError('DeepSeek balance response is invalid.', 'INVALID_RESPONSE')
    }
    return { currency: row.currency, amount: row.total_balance }
  })
}

/**
 * Read total funds for one captured API-key connection.
 * @param connection - validated endpoint and balance query deadline.
 * @param apiKey - credential resolved from that connection's reference.
 * @param signal - caller cancellation, combined with the configured deadline.
 * @returns validated total balances in provider order, preserving decimal strings.
 * @throws Error when transport, HTTP status, or JSON validation fails; aborts retain their reason.
 */
export async function queryBalance(connection: ResolvedDeepSeekOptions, apiKey: string,
  signal?: AbortSignal): Promise<LlmBalance[]> {
  const lifetime = AbortSignal.timeout(connection.balanceTimeoutMs)
  const requestSignal = signal === undefined ? lifetime : AbortSignal.any([signal, lifetime])
  requestSignal.throwIfAborted()
  const url = new URL(connection.baseURL)
  // Messages' protocol suffix is not part of the balance API; gateway prefixes stay local.
  url.pathname = `${url.pathname.replace(/\/+$/u, '').replace(/\/(?:anthropic(?:\/v1)?|v1)$/u, '')}/user/balance`
  const response = await fetch(url, {
    method: 'GET', redirect: 'error', signal: requestSignal,
    headers: { ...attributionHeaders(), authorization: `Bearer ${apiKey}`, accept: 'application/json' },
  })
  if (!response.ok) {
    await response.body?.cancel()
    throw new LlmError(`DeepSeek balance query failed (HTTP ${response.status}).`, 'BALANCE_UNAVAILABLE', { status: response.status })
  }
  const value: unknown = await response.json()
  return balances(value)
}
