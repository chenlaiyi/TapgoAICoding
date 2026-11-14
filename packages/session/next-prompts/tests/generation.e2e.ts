/** Real provider recovery with isolated in-memory Sessions and synthetic conversation. */
import { Context } from '@deepseek-ai/cordis'
import { expect, it, onTestFinished } from 'vitest'
import { createUserMessage } from '@deepseek-ai/dsh-llm'
import { SessionId } from '@deepseek-ai/dsh-session'
import { mountAgentLoopTestDependencies, mountAgentLoopTestHarness } from '@deepseek-ai/dsh-agent-loop-testkit'
import { textResponse } from '../../../core/agent-loop/tests/mock-adapter.ts'
import { adapter } from '../../../llm/llm-deepseek/tests/helpers.ts'
import type { NextPromptsView } from '../src/types.ts'
import * as NextPrompts from '../src/index.ts'

it.skipIf(!process.env.DEEPSEEK_API_KEY)('recovers real recommendations after invalid output without sending a user message', async () => {
  const ctx = new Context()
  onTestFinished(() => ctx.fiber.dispose())
  await mountAgentLoopTestDependencies(ctx)
  await mountAgentLoopTestHarness(ctx)
  const key = process.env.DEEPSEEK_API_KEY!
  ctx.llm.registerAdapter(['deepseek-official'], adapter({
    ...process.env.DEEPSEEK_BASE_URL === undefined ? {} : { baseURL: process.env.DEEPSEEK_BASE_URL },
  }, { resolveAuth: async () => ({ headers: { 'x-api-key': key } }) }))
  let attempts = 0
  ctx.on('llm/stream', (options, next) => {
    if (options.purpose === 'next-prompts' && ++attempts > 1) return next()
    return (async function* () {
      yield* textResponse(options.purpose === 'next-prompts'
        ? 'Invalid recommendation JSON'
        : 'SQLite 适合查询和事务，JSON 文件适合小型配置。')
    })()
  })
  await ctx.plugin(NextPrompts, NextPrompts.Config.parse({}))
  const handle = await ctx.agents.create({
    sessionId: SessionId('isolated-next-prompts-recovery'),
    agentOptions: { provider: 'deepseek-official', model: 'deepseek-flash' },
  })
  let settle: ((value: NextPromptsView) => void) | undefined
  const completed = new Promise<NextPromptsView>((resolve) => { settle = resolve })
  ctx.on('session/event', (_session, event) => {
    if (event.type === 'session/next-prompts-result') settle?.(event.data)
  })
  handle.agent.followup(createUserMessage({
    source: { kind: 'user' }, content: [{ type: 'text', text: '比较 SQLite 和 JSON 文件存储的适用场景。' }],
  }))
  const result = await completed
  expect(result.status).toBe('ready')
  expect(result.prompts.length).toBeGreaterThanOrEqual(1)
  expect(result.prompts.length).toBeLessThanOrEqual(3)
  expect(result.prompts.every(prompt => prompt.length <= 200)).toBe(true)
  expect(attempts).toBe(2)
  const events = handle.agent.session.snapshotEvents()
  expect(events.filter(event => event.type === 'user/message' && event.data.source.kind === 'user')).toHaveLength(1)
  expect(events.filter(event => event.type === 'session/next-prompts-request')).toHaveLength(2)
})
