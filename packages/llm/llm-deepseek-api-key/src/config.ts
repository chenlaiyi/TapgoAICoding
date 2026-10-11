/** API-key configuration resolved together with one Messages endpoint generation. */
import type { Volatile } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { credentialRef, type CredentialRef } from '@deepseek-ai/dsh-credentials'
import type { LaunchEnvironmentSnapshot } from '@deepseek-ai/dsh-launch-environment'
import { deepSeekConfigFields, type Config as ProtocolConfig, plainOptions as protocolOptions, resolveAdapterOptions as resolveProtocolOptions } from '@deepseek-ai/dsh-llm-deepseek'
import type { Options as ProtocolOptions, DeepSeekConnectionOptions } from '@deepseek-ai/dsh-llm-deepseek'

/** Messages configuration with a per-request API-key reference. */
export interface Config extends ProtocolConfig {
  /** Credential reference resolved per request; defaults to DEEPSEEK_API_KEY. */
  apiKeyEnv: Volatile<string>
  /** Maximum duration of one API-key balance query, including its response body. */
  balanceTimeoutMs: Volatile<number>
}
export const Config = z.object({
  ...deepSeekConfigFields,
  apiKeyEnv: z.string().role('credential-ref').default('DEEPSEEK_API_KEY').volatile(),
  balanceTimeoutMs: z.number().step(1).min(1).max(120_000).default(30_000).volatile(),
})
/** Plain deployment inputs for the API-key provider. */
export type Options = ProtocolOptions & { apiKeyEnv?: string; balanceTimeoutMs?: number }
/** Endpoint and credential reference captured from the same configuration generation. */
export interface ResolvedDeepSeekOptions extends DeepSeekConnectionOptions {
  /** Credential reference used only for this connection snapshot. */
  apiKeyEnv: CredentialRef
  /** Validated balance query deadline in milliseconds. */
  balanceTimeoutMs: number
}
/** Read one validated provider configuration.
 * @param config - live plugin configuration.
 * @returns detached resolver inputs.
 */
export function plainOptions(config: Config): Options {
  return { ...protocolOptions(config), apiKeyEnv: config.apiKeyEnv.get(), balanceTimeoutMs: config.balanceTimeoutMs.get() }
}
/** Resolve API-key and protocol settings together.
 * @param config - raw deployment settings.
 * @param environment - application launch environment.
 * @returns validated endpoint facts and the matching credential reference.
 */
export function resolveAdapterOptions(config: Options, environment?: LaunchEnvironmentSnapshot): ResolvedDeepSeekOptions {
  const balanceTimeoutMs = config.balanceTimeoutMs ?? 30_000
  if (!Number.isSafeInteger(balanceTimeoutMs) || balanceTimeoutMs < 1 || balanceTimeoutMs > 120_000) {
    throw new Error('llm-deepseek-api-key: balanceTimeoutMs must be an integer from 1 through 120000')
  }
  return { ...resolveProtocolOptions(config, environment), apiKeyEnv: credentialRef(config.apiKeyEnv ?? 'DEEPSEEK_API_KEY'), balanceTimeoutMs }
}
