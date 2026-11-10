/** API-key configuration resolved together with one Messages endpoint generation and its model listing. */
import type { Volatile } from '@deepseek-ai/cordis'
import z from '@deepseek-ai/schemastery'
import { credentialRef, type CredentialRef } from '@deepseek-ai/dsh-credentials'
import type { LaunchEnvironmentSnapshot } from '@deepseek-ai/dsh-launch-environment'
import {
  deepSeekConfigFields, isBuiltInCatalog, modelListingConfigFields, modelListingURL, plainOptions as protocolOptions, PUBLIC_BASE_URL,
  resolveAdapterOptions as resolveProtocolOptions, resolveListingTiming,
} from '@deepseek-ai/dsh-llm-deepseek'
import type {
  Config as ProtocolConfig, DeepSeekConnectionOptions, ListingSettings, ModelListingConfig, ModelListingOptions, Options as ProtocolOptions,
} from '@deepseek-ai/dsh-llm-deepseek'

/** Origin of the official API, the only endpoint whose `/models` listing this route follows. */
const OFFICIAL_ORIGIN = new URL(PUBLIC_BASE_URL).origin

/** Messages configuration with a per-request API-key reference. */
export interface Config extends ProtocolConfig, ModelListingConfig {
  /** Credential reference resolved per request; defaults to DEEPSEEK_API_KEY. */
  apiKeyEnv: Volatile<string>
  /** Maximum duration of one API-key balance query, including its response body. */
  balanceTimeoutMs: Volatile<number>
}
export const Config = z.object({
  ...deepSeekConfigFields,
  ...modelListingConfigFields,
  apiKeyEnv: z.string().role('credential-ref').default('DEEPSEEK_API_KEY').volatile(),
  balanceTimeoutMs: z.number().step(1).min(1).max(120_000).default(30_000).volatile(),
})
/** Plain deployment inputs for the API-key provider. */
export type Options = ProtocolOptions & ModelListingOptions & { apiKeyEnv?: string; balanceTimeoutMs?: number }
/** Endpoint and credential reference captured from the same configuration generation. */
export interface ResolvedDeepSeekOptions extends DeepSeekConnectionOptions {
  /** Credential reference used only for this connection snapshot. */
  apiKeyEnv: CredentialRef
  /** Validated balance query deadline in milliseconds. */
  balanceTimeoutMs: number
  /**
   * The official `/models` listing this generation follows; absent when `models`
   * differs from the built-in catalog or the endpoint is not the official API.
   */
  listing?: ListingSettings
}
/** Read one validated provider configuration.
 * @param config - live plugin configuration.
 * @returns detached resolver inputs.
 */
export function plainOptions(config: Config): Options {
  return { ...protocolOptions(config), apiKeyEnv: config.apiKeyEnv.get(), balanceTimeoutMs: config.balanceTimeoutMs.get() }
}
/** Resolve API-key, listing, and protocol settings together.
 * @param config - raw deployment settings.
 * @param environment - application launch environment.
 * @returns validated endpoint facts, the matching credential reference, and the listing the catalog follows.
 */
export function resolveAdapterOptions(config: Options, environment?: LaunchEnvironmentSnapshot): ResolvedDeepSeekOptions {
  const {
    modelsTimeoutMs: _timeout, modelsMaxAgeMs: _maxAge, apiKeyEnv, balanceTimeoutMs: rawBalanceTimeoutMs, ...messages
  } = config
  const balanceTimeoutMs = rawBalanceTimeoutMs ?? 30_000
  if (!Number.isSafeInteger(balanceTimeoutMs) || balanceTimeoutMs < 1 || balanceTimeoutMs > 120_000) {
    throw new Error('llm-deepseek-api-key: balanceTimeoutMs must be an integer from 1 through 120000')
  }
  const timing = resolveListingTiming(config, 'llm-deepseek-api-key')
  const connection = resolveProtocolOptions(messages, environment)
  const listed = new URL(connection.baseURL).origin === OFFICIAL_ORIGIN && isBuiltInCatalog(connection.models)
  return {
    ...connection,
    apiKeyEnv: credentialRef(apiKeyEnv ?? 'DEEPSEEK_API_KEY'),
    balanceTimeoutMs,
    ...listed ? { listing: { url: modelListingURL(connection.baseURL), ...timing } } : {},
  }
}
