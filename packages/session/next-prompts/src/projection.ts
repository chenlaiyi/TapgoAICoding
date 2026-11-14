/** Bounded recent text and route recovery; replay never starts model requests. */
import { z } from 'zod'
import type { ProjectionDefinition } from '@deepseek-ai/dsh-session-projection'
import type { NextPromptsView } from './types.ts'

const viewSchema = z.object({
  turn: z.number().int(), status: z.enum(['idle', 'ready', 'error']),
  prompts: z.array(z.string().trim().min(1)).max(3),
})
const stateSchema = z.object({
  context: z.string(), route: z.object({ provider: z.string(), model: z.string() }).nullable(),
  reply: z.boolean(), view: viewSchema,
})
/** Recoverable request input and the latest Client view. */
export type NextPromptsState = z.infer<typeof stateSchema>

/**
 * Build the bounded fold using the deployment's context budget.
 * @param maxContextChars - maximum UTF-16 units retained from recent text messages.
 * @returns deterministic Session projection.
 */
export function nextPromptsProjection(maxContextChars: number): Omit<ProjectionDefinition<'nextPrompts', NextPromptsState>, 'wire'> & { wire: NonNullable<ProjectionDefinition<'nextPrompts', NextPromptsState>['wire']> } {
  return {
    key: 'nextPrompts', stateVersion: 1, stateSchema: stateSchema.extend({ context: z.string().max(maxContextChars) }),
    init: () => ({ context: '', route: null, reply: false, view: { turn: -1, status: 'idle', prompts: [] } }),
    apply: (state, event) => {
      if (event.type === 'turn/start') return { ...state, reply: false, view: { turn: event.data.turn, status: 'idle', prompts: [] } }
      if (event.type === 'request/header') {
        const { provider, model } = event.data.header.config
        return { ...state, route: { provider, model } }
      }
      if (event.type === 'user/message' || event.type === 'assistant/message') {
        const message = event.type === 'user/message' ? event.data : event.data.message
        if (event.type === 'user/message' && event.data.source.kind !== 'user') return state
        const text = message.content.flatMap(block => block.type === 'text' ? [block.text] : []).join('\n').trim()
        if (text === '') return state
        return { ...state,
          reply: event.type === 'assistant/message' ? event.data.interrupted !== true : state.reply,
          context: (state.context + '\n' + (event.type === 'user/message' ? 'User: ' : 'Assistant: ') + text).slice(-maxContextChars),
        }
      }
      if (event.type !== 'session/next-prompts-result') return state
      const parsed = viewSchema.safeParse(event.data)
      return parsed.success && parsed.data.turn === state.view.turn ? { ...state, view: parsed.data } : state
    },
    wire: { summary: false, viewSchema, view: (state): NextPromptsView => state.view },
  }
}
