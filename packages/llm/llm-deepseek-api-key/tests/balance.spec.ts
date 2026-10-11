/** Isolated API-key wallet requests, including endpoint and credential changes. */
import { createServer } from 'node:http'
import type { IncomingHttpHeaders, ServerResponse } from 'node:http'
import { Context, Service } from '@deepseek-ai/cordis'
import LlmRuntime, { attributionHeaders } from '@deepseek-ai/dsh-llm'
import type { CredentialRef } from '@deepseek-ai/dsh-credentials'
import { afterEach, expect, it, vi } from 'vitest'
import * as ApiKey from '../src/index.ts'
import { queryBalance } from '../src/balance.ts'

const cleanups: Array<() => Promise<void>> = []
afterEach(async () => {
  while (cleanups.length > 0) await cleanups.pop()!()
  vi.unstubAllEnvs()
})

const funds = { is_available: true, balance_infos: [
  { currency: 'CNY', total_balance: '12.345600', granted_balance: '2.00', topped_up_balance: '10.345600' },
  { currency: 'USD', total_balance: '0E-16', granted_balance: '0', topped_up_balance: '0' },
] }

async function server(reply: (response: ServerResponse) => void = response => response.end(JSON.stringify(funds))) {
  const requests: Array<{ path: string; headers: IncomingHttpHeaders }> = []
  const seen = Promise.withResolvers<undefined>()
  const http = createServer((request, response) => {
    requests.push({ path: request.url!, headers: request.headers })
    response.setHeader('content-type', 'application/json')
    seen.resolve(undefined)
    reply(response)
  })
  await new Promise<void>(resolve => http.listen(0, '127.0.0.1', resolve))
  const address = http.address()
  if (address === null || typeof address === 'string') throw new Error('missing loopback port')
  cleanups.push(async () => {
    const closed = new Promise<void>((resolve, reject) => http.close((error) => {
      if (error) reject(error)
      else resolve()
    }))
    http.closeAllConnections()
    await closed
  })
  return { url: `http://127.0.0.1:${address.port}`, requests, seen: seen.promise }
}

async function runtime(config: ApiKey.Options) {
  const ctx = new Context()
  cleanups.push(() => ctx.fiber.dispose())
  await ctx.plugin(LlmRuntime)
  await ctx.plugin(ApiKey, config)
  return ctx
}

it.each(['/anthropic', '/anthropic/v1', '/v1', '', '/gateway/anthropic/v1', '/gateway'])('keeps balance requests on the configured endpoint %s', async (path) => {
  const endpoint = await server()
  const config = ApiKey.resolveAdapterOptions({ baseURL: `${endpoint.url}${path}` })
  expect(await queryBalance(config, 'test-only-key')).toEqual([
    { currency: 'CNY', amount: '12.345600' }, { currency: 'USD', amount: '0E-16' },
  ])
  expect(endpoint.requests).toHaveLength(1)
  expect(endpoint.requests[0]!.path).toBe(`${path.startsWith('/gateway') ? '/gateway' : ''}/user/balance`)
  expect(endpoint.requests[0]!.headers).toMatchObject({ authorization: 'Bearer test-only-key', ...attributionHeaders() })
  expect(endpoint.requests[0]!.headers).not.toHaveProperty('x-dsh-auth-token')
})

it('resolves the configured credential on every balance query without account authentication', async () => {
  const endpoint = await server()
  vi.stubEnv('CUSTOM_BALANCE_KEY', 'first-test-key')
  const ctx = await runtime({ baseURL: `${endpoint.url}/anthropic`, apiKeyEnv: 'CUSTOM_BALANCE_KEY' })
  expect(await ctx.llm.getBalance('deepseek-official')).toHaveLength(2)
  vi.stubEnv('CUSTOM_BALANCE_KEY', 'second-test-key')
  await ctx.llm.getBalance('deepseek-official')
  expect(endpoint.requests.map(request => request.headers.authorization)).toEqual(['Bearer first-test-key', 'Bearer second-test-key'])
})

it('uses the credential service instead of an ambient key and follows stored-key rotation', async () => {
  const endpoint = await server()
  vi.stubEnv('CUSTOM_BALANCE_KEY', 'ambient-test-key')
  const ctx = new Context()
  cleanups.push(() => ctx.fiber.dispose())
  let key = 'stored-test-key'
  class Credentials extends Service {
    constructor(context: Context) { super(context, 'credentials') }
    async resolve(ref: CredentialRef) {
      expect(ref).toBe('CUSTOM_BALANCE_KEY')
      return { value: key, source: 'test' }
    }
  }
  await ctx.plugin(Credentials)
  await ctx.plugin(LlmRuntime)
  await ctx.plugin(ApiKey, { baseURL: endpoint.url, apiKeyEnv: 'CUSTOM_BALANCE_KEY' })
  await ctx.llm.getBalance('deepseek-official')
  key = 'rotated-test-key'
  await ctx.llm.getBalance('deepseek-official')
  expect(endpoint.requests.map(request => request.headers.authorization)).toEqual(['Bearer stored-test-key', 'Bearer rotated-test-key'])
})

it.each(['', 'invalid\nheader'])('does not query an endpoint without a usable credential %j', async (key) => {
  const endpoint = await server()
  vi.stubEnv('CUSTOM_BALANCE_KEY', key)
  const ctx = await runtime({ baseURL: endpoint.url, apiKeyEnv: 'CUSTOM_BALANCE_KEY' })
  await expect(ctx.llm.getBalance('deepseek-official')).rejects.toMatchObject({ code: 'llm/balance-unavailable' })
  expect(endpoint.requests).toHaveLength(0)
})

it.each([
  null, {}, { is_available: 'true', balance_infos: [] },
  { is_available: true, balance_infos: [null] },
  { is_available: true, balance_infos: [{ currency: 'EUR', total_balance: '1' }] },
  { is_available: true, balance_infos: [{ currency: 'CNY', total_balance: 'NaN' }] },
  { is_available: true, balance_infos: [{ currency: 'CNY', total_balance: 'Infinity' }] },
  { is_available: true, balance_infos: [{ currency: 'CNY', total_balance: 1 }] },
])('rejects malformed balance responses without returning an amount: %j', async (value) => {
  const endpoint = await server(response => response.end(JSON.stringify(value)))
  await expect(queryBalance(ApiKey.resolveAdapterOptions({ baseURL: endpoint.url }), 'test-key'))
    .rejects.toMatchObject({ code: 'INVALID_RESPONSE' })
})

it('keeps a successful zero or empty balance distinct from a query failure', async () => {
  const endpoint = await server(response => response.end(JSON.stringify({ is_available: false, balance_infos: [] })))
  expect(await queryBalance(ApiKey.resolveAdapterOptions({ baseURL: endpoint.url }), 'test-key')).toEqual([])
  const failed = await server(response => response.writeHead(401).end('private error'))
  await expect(queryBalance(ApiKey.resolveAdapterOptions({ baseURL: failed.url }), 'test-key'))
    .rejects.toMatchObject({ code: 'BALANCE_UNAVAILABLE', failure: { status: 401 } })
})

it('refuses redirects before sending the API key to their destination', async () => {
  const destination = await server()
  const endpoint = await server(response => response.writeHead(302, { location: `${destination.url}/user/balance` }).end())
  await expect(queryBalance(ApiKey.resolveAdapterOptions({ baseURL: endpoint.url }), 'test-key')).rejects.toThrow()
  expect(destination.requests).toHaveLength(0)
})

it('cancels a pending response and enforces its configured deadline', async () => {
  const endpoint = await server((response) => { response.writeHead(200); response.flushHeaders() })
  const controller = new AbortController()
  const cancelled = queryBalance(ApiKey.resolveAdapterOptions({ baseURL: endpoint.url }), 'test-key', controller.signal)
  const assertion = expect(cancelled).rejects.toThrow()
  await endpoint.seen
  controller.abort()
  await assertion
  await expect(queryBalance(ApiKey.resolveAdapterOptions({ baseURL: endpoint.url, balanceTimeoutMs: 30 }), 'test-key')).rejects.toThrow()
})

it.each([0, -1, 1.5, 120_001, Infinity, NaN])('rejects invalid balance query deadlines: %s', (balanceTimeoutMs) => {
  expect(() => ApiKey.resolveAdapterOptions({ balanceTimeoutMs })).toThrow('balanceTimeoutMs')
})
