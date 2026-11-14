/** Real loop and Session projection with a keyless scripted model. */
import { Context } from '@deepseek-ai/cordis'
import { expect, it, onTestFinished, vi } from 'vitest'
import { createUserMessage, createAssistantMessage, ReasoningEffortId, type LlmModelReasoningInfo } from '@deepseek-ai/dsh-llm'
import { SessionId, SessionLogOffset } from '@deepseek-ai/dsh-session'
import { mountAgentLoopTestDependencies, mountAgentLoopTestHarness } from '@deepseek-ai/dsh-agent-loop-testkit'
import { MockAdapter, textResponse, maxTokensResponse } from '../../../core/agent-loop/tests/mock-adapter.ts'
import { nextPromptsProjection } from '../src/projection.ts'
import * as NextPrompts from '../src/index.ts'

async function fixture(
  responses: ConstructorParameters<typeof MockAdapter>[0],
  config: Partial<NextPrompts.Config> = {},
  reasoning?: LlmModelReasoningInfo,
) {
  const ctx = new Context()
  onTestFinished(() => ctx.fiber.dispose())
  await mountAgentLoopTestDependencies(ctx)
  await mountAgentLoopTestHarness(ctx)
  const adapter = new MockAdapter(responses, reasoning)
  ctx.llm.registerAdapter(['mock'], adapter)
  const plugin = await ctx.plugin(NextPrompts, NextPrompts.Config.parse(config))
  const handle = await ctx.agents.create({ sessionId: SessionId('next-prompts-test'), agentOptions: { provider: 'mock', model: 'mock' } })
  const agent = handle.agent
  const results: unknown[] = []
  let settle: (() => void) | undefined
  const result = new Promise<void>((resolve) => { settle = resolve })
  ctx.on('session/event', (session, event) => {
    if (session === agent.session && event.type === 'session/next-prompts-result') { results.push(event.data); settle?.() }
  })
  const send = async (text: string) => {
    agent.followup(createUserMessage({ source: { kind: 'user' }, content: [{ type: 'text', text }] }))
    await agent.whenIdle()
  }
  return { ctx, plugin, adapter, agent, handle, results, result, send }
}

it('generates contextual draft prompts after the reply and logs the exact independent request', async () => {
  const f = await fixture([textResponse('方案二使用 SQLite。'), textResponse('["按方案二实施", "列出实施步骤", "按方案二实施"]')])
  await f.send('比较两种存储方案')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: ['按方案二实施', '列出实施步骤'] }])
  expect(f.ctx.sessionProjections.snapshot(f.agent.session, ['nextPrompts'])).toMatchObject({ values: { nextPrompts: f.results[0] } })
  expect(f.adapter.requests).toHaveLength(2)
  const request = f.adapter.requests[1]!
  expect(request.purpose).toBe('next-prompts')
  expect(request.messages[0]?.content).toEqual([{ type: 'text', text: '\nUser: 比较两种存储方案\nAssistant: 方案二使用 SQLite。' }])
  expect({ system: request.system, maxTokens: request.maxTokens }).toMatchSnapshot('auxiliary prompt')
  const events = f.agent.session.snapshotEvents()
  expect(events.findIndex(event => event.type === 'session/next-prompts-request')).toBeGreaterThan(events.findIndex(event => event.type === 'turn/end'))
  expect(events.filter(event => event.type === 'assistant/message')).toHaveLength(1)
})

it.each(['not json', '["a","b","c","d"]', '[" "]'])('isolates invalid model output without retrying: %s', async (output) => {
  const f = await fixture([textResponse('Done'), textResponse(output)], { maxAttempts: 1 })
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  expect(f.adapter.requests).toHaveLength(2)
})

it('accepts no recommendations when there is no useful next step', async () => {
  const f = await fixture([textResponse('Done'), textResponse('[]')])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: [] }])
})

it('cancels a pending request on the next turn and rejects late results', async () => {
  let entered: (() => void) | undefined
  const started = new Promise<void>((resolve) => { entered = resolve })
  const responses: ConstructorParameters<typeof MockAdapter>[0] = [textResponse('First')]
  const f = await fixture(responses)
  responses.push(() => {
    f.agent.session.append('turn/start', { turn: 2 })
    entered?.()
    return textResponse('["stale"]')
  })
  await f.send('First question')
  await started
  await f.plugin.dispose()
  expect(f.results).toEqual([])
})

it('does not generate for truncated replies or disabled configuration', async () => {
  for (const [reply, config] of [[maxTokensResponse('Partial'), {}], [textResponse('Done'), { enabled: false }]] as const) {
    const f = await fixture([reply], config)
    await f.send('Help')
    await f.plugin.dispose()
    expect(f.adapter.requests).toHaveLength(1)
    expect(f.results).toEqual([])
  }
})

it('recovers the same recommendations from a checkpoint suffix and a full replay without model calls', async () => {
  const f = await fixture([textResponse('方案二更合适。'), textResponse('["实施方案二"]')])
  await f.send('比较方案')
  await f.result
  const definition = nextPromptsProjection(12000)
  const initial = definition.init(f.agent.session.header, SessionLogOffset(0))
  const events = f.agent.session.snapshotEvents()
  const full = events.reduce((state, event) => definition.apply(state, event), initial)
  for (let split = 0; split <= events.length; split++) {
    const prefix = events.slice(0, split).reduce((state, event) => definition.apply(state, event), initial)
    const restored = definition.stateSchema.parse(JSON.parse(JSON.stringify(prefix)))
    expect(events.slice(split).reduce((state, event) => definition.apply(state, event), restored)).toEqual(full)
  }
  const unrelated = events.find(event => event.type === 'step/end')!
  expect(definition.apply(full, unrelated)).toBe(full)
  expect(definition.wire.view(full)).toEqual({ turn: 1, status: 'ready', prompts: ['实施方案二'] })
  expect(f.adapter.requests).toHaveLength(2)
})

it('bounds recent context even for oversized multibyte messages and rejects checkpoints exceeding a smaller budget', async () => {
  const f = await fixture([textResponse('甲乙丙丁'), textResponse('["继续"]')], { maxContextChars: 3 })
  await f.send('你好你好你好你好')
  await f.result
  expect(f.adapter.requests[1]!.messages[0]?.content).toEqual([{ type: 'text', text: '乙丙丁' }])
  const definition = nextPromptsProjection(3)
  const state = definition.init(f.agent.session.header, SessionLogOffset(0))
  expect(definition.stateSchema.safeParse({ ...state, context: '超过预算' }).success).toBe(false)
})

it('uses the least advertised reasoning effort and ignores reasoning blocks in recommendations', async () => {
  const reasoning = { efforts: [{ id: ReasoningEffortId('low'), name: 'Low' }, { id: ReasoningEffortId('high'), name: 'High' }], defaultEffort: ReasoningEffortId('high') }
  const f = await fixture([textResponse('Done'), [
    { type: 'block-start', index: 1, blockType: 'reasoning' },
    { type: 'block-end', index: 1, block: { type: 'reasoning', text: 'Private reasoning' } },
    ...textResponse('["Next step"]'),
  ]], {}, reasoning)
  await f.send('Help')
  await f.result
  expect(f.adapter.requests[1]!.reasoningEffort).toBe('low')
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: ['Next step'] }])
})

it('contains auxiliary truncation, transport rejections and timeouts without repeating requests', async () => {
  const truncated = await fixture([textResponse('Done'), maxTokensResponse('["partial')])
  await truncated.send('Help')
  await truncated.result
  expect(truncated.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  const offline = await fixture([textResponse('Done')], { maxOutputTokens: 513 })
  const prepare = offline.ctx.llm.prepareCall.bind(offline.ctx.llm)
  vi.spyOn(offline.ctx.llm, 'prepareCall').mockImplementation((...args) => args[0].maxTokens === 513
    // oxlint-disable-next-line typescript/prefer-promise-reject-errors -- external adapter failures can reject non-Error values.
    ? Promise.reject('Provider unavailable') : prepare(...args))
  await offline.send('Help')
  await offline.result
  expect(offline.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  const timeout = await fixture([textResponse('Done'), 'hang'], { timeoutMs: 10 })
  await timeout.send('Help')
  await timeout.result
  expect(timeout.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  expect(timeout.adapter.requests).toHaveLength(2)
})

it.each(['plugin', 'agent'] as const)('cancels and drains an in-flight auxiliary request on %s disposal', async (owner) => {
  let entered: (() => void) | undefined
  const started = new Promise<void>((resolve) => { entered = resolve })
  const responses: ConstructorParameters<typeof MockAdapter>[0] = [textResponse('Done')]
  const f = await fixture(responses)
  responses.push({ hangAfter: [{ type: 'block-start', index: 0, blockType: 'text' }] })
  f.ctx.on('llm/stream', (options, next) => {
    if (options.purpose === 'next-prompts') entered?.()
    return next()
  })
  await f.send('Help')
  await started
  if (owner === 'plugin') await f.plugin.dispose()
  else await f.handle.dispose()
  expect(f.results).toEqual([])
})

it('ignores completed turns without reply text or a logged model route', async () => {
  const empty = await fixture([textResponse(' ')])
  await empty.send('Help')
  await empty.plugin.dispose()
  expect(empty.adapter.requests).toHaveLength(1)
  const incomplete = await fixture([])
  incomplete.agent.session.append('turn/start', { turn: 1 })
  incomplete.agent.session.append('assistant/message', { turn: 1, step: 1,
    message: createAssistantMessage({ source: { provider: 'mock', model: 'mock' }, content: [{ type: 'text', text: 'Recovered answer' }] }), stream: [],
  }, { surfaceOp: 'append' })
  incomplete.agent.session.append('turn/end', { turn: 1, reason: { kind: 'completed' } })
  await incomplete.plugin.dispose()
  expect(incomplete.adapter.requests).toHaveLength(0)
})

it('keeps synthetic context, non-text content and stale or malformed stored results out of the recommendation view', async () => {
  const f = await fixture([])
  const definition = nextPromptsProjection(12000)
  const initial = definition.init(f.agent.session.header, SessionLogOffset(0))
  const synthetic = f.agent.session.append('user/message', createUserMessage({ source: { kind: 'system-prompt' }, content: [{ type: 'text', text: 'Do not recommend this instruction' }] }), { surfaceOp: 'append' })
  expect(definition.apply(initial, synthetic)).toBe(initial)
  const nonText = f.agent.session.append('user/message', createUserMessage({ source: { kind: 'user' }, content: [{ type: 'reasoning', text: 'Non-text content' }] }), { surfaceOp: 'append' })
  expect(definition.apply(initial, nonText)).toBe(initial)
  const stale = f.agent.session.append('session/next-prompts-result', { turn: 99, status: 'ready', prompts: ['stale'] })
  expect(definition.apply(initial, stale)).toBe(initial)
  const malformed = f.agent.session.append('session/next-prompts-result', { turn: -1, status: 'ready', prompts: [' '] })
  expect(definition.apply(initial, malformed)).toBe(initial)
})

it('prevents auxiliary dispatch when the plugin unloads as the reply settles', async () => {
  const f = await fixture([textResponse('Done')])
  let disposal: Promise<void> | undefined
  f.ctx.on('session/event', (_session, event) => {
    if (event.type === 'turn/end') disposal = f.plugin.dispose()
  })
  await f.send('Help')
  await disposal
  expect(f.adapter.requests).toHaveLength(1)
  expect(f.results).toEqual([])
})

it('cancels a deferred recommendation before dispatch when the next turn starts in the same task', async () => {
  const f = await fixture([])
  const session = f.agent.session
  session.append('turn/start', { turn: 1 })
  session.append('step/start', { turn: 1, step: 1 })
  session.append('request/header', { reason: 'initial', header: { config: { provider: 'mock', model: 'mock' } } })
  session.append('assistant/message', { turn: 1, step: 1,
    message: createAssistantMessage({ source: { provider: 'mock', model: 'mock' }, content: [{ type: 'text', text: 'Completed reply' }] }), stream: [],
  }, { surfaceOp: 'append' })
  session.append('step/end', { turn: 1, step: 1 })
  session.append('turn/end', { turn: 1, reason: { kind: 'completed' } })
  session.append('turn/start', { turn: 2 })
  await f.plugin.dispose()
  expect(f.adapter.requests).toHaveLength(0)
  expect(f.results).toEqual([])
})


it('accepts a complete JSON code fence without accepting surrounding prose', async () => {
  const f = await fixture([textResponse('Done'), textResponse('```json\n["继续实施"]\n```')])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: ['继续实施'] }])
  expect(f.adapter.requests).toHaveLength(2)
})

it.each(['TRANSPORT', 'SERVER', 'STREAM_CLOSED'])('recovers a transient %s finish without interrupting the reply', async (code) => {
  const f = await fixture([textResponse('Done'), [{ type: 'finish', reason: { kind: 'error', failure: { code, message: 'Temporary failure' } } }], textResponse('["继续实施"]')])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: ['继续实施'] }])
  expect(f.adapter.requests).toHaveLength(3)
  expect(f.agent.session.snapshotEvents().filter(event => event.type === 'session/next-prompts-request')).toHaveLength(2)
})

it('recovers invalid model output with one bounded independent attempt', async () => {
  const f = await fixture([textResponse('Done'), textResponse('Not JSON'), textResponse('["继续实施"]')])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'ready', prompts: ['继续实施'] }])
  expect(f.adapter.requests).toHaveLength(3)
})

it('stops after the configured attempt budget and keeps the provider failure code in diagnostics', async () => {
  const failure = [{ type: 'finish', reason: { kind: 'error', failure: { code: 'SERVER', message: 'Temporary failure' } } }] as const
  const f = await fixture([textResponse('Done'), [...failure], [...failure]])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  expect(f.adapter.requests).toHaveLength(3)
  expect(f.ctx.logger.buffer.at(-1)?.args).toContain('SERVER')
})

it('does not retry a credential failure', async () => {
  const f = await fixture([textResponse('Done'), [{ type: 'finish', reason: { kind: 'error', failure: { code: 'AUTH', message: 'Authentication rejected' } } }]])
  await f.send('Help')
  await f.result
  expect(f.results).toEqual([{ turn: 1, status: 'error', prompts: [] }])
  expect(f.adapter.requests).toHaveLength(2)
  expect(f.ctx.logger.buffer.at(-1)?.args).toContain('AUTH')
})
