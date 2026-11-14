/** Mount recommendations in Chat's completed-turn extension position. */
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client'
import type { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-client-locale/client'
import type {} from '@deepseek-ai/dsh-client-ui-conversation/client'
import type {} from '@deepseek-ai/dsh-api-session-controller/client'
export type { NextPromptsView } from '@deepseek-ai/dsh-next-prompts/types'
import { NextPrompts, type NextPromptsInjected } from './NextPrompts.tsx'

const en = { label: 'Suggested next prompts', error: 'Next prompts unavailable. You can continue typing.' }
const zh: typeof en = { label: '下一步建议', error: '暂时无法生成建议，可直接输入继续对话' }
const ja: typeof en = { label: '次の質問の候補', error: '候補を生成できません。入力して続行できます。' }
const es: typeof en = { label: 'Sugerencias para continuar', error: 'Sugerencias no disponibles. Puedes seguir escribiendo.' }
const fr: typeof en = { label: 'Suggestions pour continuer', error: 'Suggestions indisponibles. Vous pouvez continuer à écrire.' }
const de: typeof en = { label: 'Vorschläge zum Fortfahren', error: 'Vorschläge nicht verfügbar. Du kannst weiterschreiben.' }
const ru: typeof en = { label: 'Следующие запросы', error: 'Предложения недоступны. Можно продолжить ввод.' }
const pt: typeof en = { label: 'Sugestões para continuar', error: 'Sugestões indisponíveis. Você pode continuar digitando.' }

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap { nextPrompts: keyof typeof en }
}

/** Required browser owners for recommendations and draft edits. */
export const inject = ['slots', 'locale', 'sessions', 'conversation']

/**
 * Register localized suggestions and a draft-only click handler.
 * @param ctx - Client plugin context.
 */
export function apply(ctx: Context): void {
  ctx.effect(() => ctx.locale.register('nextPrompts', { en, zh, ja, es, fr, de, ru, pt }))
  ctx.slots.inject('conversation.chat.turnTail', () => ctx.slots.register({
    name: 'conversation.chat.turnTail', id: 'next-prompts', locale: 'nextPrompts', order: 100,
    inject: (sessionId): NextPromptsInjected => ({
      fillPrompt: (prompt) => {
        const binding = ctx.sessions.binding(sessionId)
        if (binding === undefined) return
        const result = ctx.conversation.input.requestDraftInitialization(binding, { prompt, whenDraftExists: 'append' })
        if (result === 'applied') ctx.conversation.input.for(binding.ctx).focus()
      },
    }),
  }, NextPrompts))
}
