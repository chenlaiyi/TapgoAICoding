/** Optional suggestions and exact auxiliary requests, excluded from Session summaries. */
import type { Message, LlmCallConfig } from '@deepseek-ai/dsh-llm'
import type { SessionProjectionSummaryExcluded } from '@deepseek-ai/dsh-session-projection/types'

/** Latest completed turn's recommendations; a newer turn clears them. */
export interface NextPromptsView {
  readonly turn: number
  readonly status: 'idle' | 'ready' | 'error'
  readonly prompts: readonly string[]
}

declare module '@deepseek-ai/dsh-session/types' {
  interface SessionEventMap {
    /** Exact auxiliary request, recorded before dispatch and never added to conversation history. */
    'session/next-prompts-request': { turn: number; system: string; messages: Message[]; config: LlmCallConfig }
    /** Optional recommendations or a generation failure, correlated with their completed turn. */
    'session/next-prompts-result': NextPromptsView
  }
}

declare module '@deepseek-ai/dsh-session-projection/types' {
  interface SessionProjectionMap {
    /** Suggestions for the latest completed turn only. */
    nextPrompts: SessionProjectionSummaryExcluded<NextPromptsView>
  }
}

declare module '@deepseek-ai/dsh-llm/types' {
  interface LlmRequestPurposeMap { 'next-prompts': true }
}
