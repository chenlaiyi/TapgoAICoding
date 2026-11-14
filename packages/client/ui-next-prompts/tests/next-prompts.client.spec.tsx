// @vitest-environment jsdom
/** Clicks use the real draft shell and never enter its send path. */
import type { ComponentProps } from 'react'
import { Context } from '@deepseek-ai/cordis'
import { SlotRegistry } from '@deepseek-ai/dsh-client-ui-renderer/client'
import { LocaleRuntime } from '@deepseek-ai/dsh-client-locale/client'
import { SessionId, SessionSeq } from '@deepseek-ai/dsh-session/types'
import type { DraftInitializationOptions, InputState } from '@deepseek-ai/dsh-client-ui-conversation/client'
import { makeTranslate } from '@deepseek-ai/dsh-client-test-runtime'
import { fireEvent, render, screen, cleanup } from '@testing-library/react'
import { afterEach, expect, it, onTestFinished, vi } from 'vitest'
import { SessionInputShell } from '../../../client/ui-conversation/src/client/input/facade.ts'
import { NextPrompts, type NextPromptsInjected } from '../src/client/NextPrompts.tsx'
import { apply as hostApply } from '../src/index.ts'
import * as Client from '../src/client/index.ts'
import type { NextPromptsView } from '@deepseek-ai/dsh-next-prompts/types'

afterEach(cleanup)
type Props = ComponentProps<typeof NextPrompts>
const end = { type: 'turn/end', seq: SessionSeq(1), time: 0, data: { turn: 1, reason: { kind: 'completed' } } } as const
const inputState: InputState = { draft: '', attachmentIds: [], draftRev: 0, phase: 'plain', occurrences: [], queue: [] }

function props(view: NextPromptsView | undefined): Props {
  return {
    turn: { turn: 1, status: 'closed', start: undefined, end, steps: [], data: { get: () => undefined,
      source: () => ({ getSnapshot: () => undefined, subscribe: () => () => {} }) } },
    useInput: selector => selector(inputState),
    useProjection: vi.fn().mockReturnValue(view),
    t: makeTranslate({ label: '下一步建议', loading: '正在准备下一步建议…', error: '暂时无法生成建议，可直接输入继续对话' }),
    fillPrompt: vi.fn(),
  }
}

it('renders 1–3 suggestions as keyboard-accessible draft actions and hides stale turns', () => {
  const p = props({ turn: 1, status: 'ready', prompts: ['实施方案二', '列出步骤', '比较成本'] })
  const { rerender } = render(<NextPrompts {...p} />)
  expect(screen.getAllByRole('button')).toHaveLength(3)
  fireEvent.click(screen.getByRole('button', { name: '实施方案二' }))
  expect(p.fillPrompt).toHaveBeenCalledExactlyOnceWith('实施方案二')
  rerender(<NextPrompts {...props({ turn: 2, status: 'ready', prompts: ['new'] })} />)
  expect(screen.queryByRole('group')).toBeNull()
  rerender(<NextPrompts {...props({ turn: 1, status: 'ready', prompts: [] })} />)
  expect(screen.queryByRole('group')).toBeNull()
  rerender(<NextPrompts {...props(undefined)} />)
  expect(screen.queryByRole('group')).toBeNull()
})

it.each(['adjudicating', 'submitting', 'sending'] as const)('disables recommendations while the composer is %s', (phase) => {
  const p: Props = { ...props({ turn: 1, status: 'ready', prompts: ['实施方案二'] }), useInput: selector => selector({ ...inputState, phase }) }
  render(<NextPrompts {...p} />)
  const button = screen.getByRole('button', { name: '实施方案二' })
  expect(button.hasAttribute('disabled')).toBe(true)
  fireEvent.click(button)
  expect(p.fillPrompt).not.toHaveBeenCalled()
})

it('shows an isolated failure notice without blocking input', () => {
  render(<NextPrompts {...props({ turn: 1, status: 'error', prompts: [] })} />)
  expect(screen.getByRole('status').textContent).toContain('可直接输入')
  expect(screen.queryByRole('button')).toBeNull()
})

it('appends into the displayed session draft, preserves existing text and waits for explicit send', async () => {
  hostApply()
  const ctx = new Context()
  onTestFinished(() => ctx.fiber.dispose())
  await ctx.plugin(SlotRegistry)
  ctx.provide('locale', new LocaleRuntime(ctx))
  ctx.slots.register({ name: 'root', children: { 'conversation.chat.turnTail': { kind: 'list', scope: 'session' } } }, (_props: { renderSlot?: unknown }) => null)
  const send = vi.fn(async () => ({ kind: 'success' as const }))
  const shell = new SessionInputShell({ actx: ctx, defaultSink: send,
    commandAttachments: { serialize: async () => [], release: () => {}, unsupportedNotice: token => token } })
  onTestFinished(() => { shell.dispose() })
  shell.setDraft('已有草稿')
  const binding = { ctx }
  const resolveBinding = vi.fn((): typeof binding | undefined => binding)
  ctx.provide('sessions', { binding: resolveBinding })
  ctx.provide('conversation', { input: {
    requestDraftInitialization: vi.fn((_binding: object, options: DraftInitializationOptions) => shell.requestDraftInitialization(options)),
    for: () => shell,
  } })
  const fiber = await ctx.plugin(Client)
  const entry = ctx.slots.entries('conversation.chat.turnTail')[0]!
  const resolve = entry.inject as NonNullable<typeof entry.inject> & ((sessionId: SessionId) => NextPromptsInjected)
  const bound = resolve(SessionId('displayed-session'))
  render(<NextPrompts {...props({ turn: 1, status: 'ready', prompts: ['实施方案二'] })} {...bound} />)
  fireEvent.click(screen.getByRole('button', { name: '实施方案二' }))
  expect(resolveBinding).toHaveBeenCalledWith('displayed-session')
  expect(shell.snapshot.draft).toBe('已有草稿\n实施方案二')
  expect(send).not.toHaveBeenCalled()
  const focus = vi.spyOn(shell, 'focus')
  resolveBinding.mockReturnValueOnce(undefined)
  bound.fillPrompt('missing session')
  expect(focus).not.toHaveBeenCalled()
  shell.dispose()
  bound.fillPrompt('locked input')
  expect(focus).not.toHaveBeenCalled()
  await fiber.dispose()
  expect(ctx.slots.entries('conversation.chat.turnTail')).toHaveLength(0)
})
