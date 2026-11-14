/** Recommendations remain plain draft edits until the user explicitly sends them. */
import { Button } from '@deepseek-ai/dsh-client-ui-primitives'
import type { InjectFace, PropsLocale, PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import type {} from '@deepseek-ai/dsh-client-ui-chat/client'
import type {} from '@deepseek-ai/dsh-next-prompts/types'
import css from './NextPrompts.module.css'

/** Session-bound draft action, with no send operation. */
export interface NextPromptsInjected {
  /** Append a recommendation to the current draft and focus the composer. @param prompt - selected recommendation. */
  fillPrompt: (prompt: string) => void
}

type Props = Pick<PropsRuntime<'conversation.chat.turnTail'>, 'turn' | 'useProjection' | 'useInput'> & PropsLocale<'nextPrompts'> & InjectFace<NextPromptsInjected>

/**
 * Render recommendations only beside the matching completed turn.
 * @param props - turn, framework projection hook, translator and draft callback.
 * @returns accessible recommendation buttons or a compact failure notice.
 */
export function NextPrompts({ turn, useProjection, useInput, fillPrompt, t }: Props) {
  const view = useProjection('nextPrompts')
  const locked = useInput(input => input.phase === 'adjudicating' || input.phase === 'submitting' || input.phase === 'sending')
  if (view === undefined || view.turn !== turn.turn || turn.end === undefined || view.status === 'idle') return null
  if (view.status === 'error') return <div className={css.notice} role="status">{t('error')}</div>
  if (view.prompts.length === 0) return null
  return <div className={css.root} role="group" aria-label={t('label')}>
    <span className={css.notice}>{t('label')}</span>
    <div className={css.prompts}>
      {view.prompts.map(prompt => <Button key={prompt} disabled={locked} variant="outline" size="sm" className={css.prompt}
        onClick={() => { fillPrompt(prompt) }}>{prompt}</Button>)}
    </div>
  </div>
}
