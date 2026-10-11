// @vitest-environment jsdom
/** Selected-provider funds rendered through the production Session slots and selector hook. */
import { afterEach, expect, onTestFinished, vi } from 'vitest'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { createClientTest, webApp } from '@deepseek-ai/dsh-client-test-runtime/src/assembly/index.ts'
import { ok } from '@deepseek-ai/dsh-remote-mock'
import type { SessionId } from '@deepseek-ai/dsh-api-remotes/client'
import { SESSION_FORMAT_VERSION } from '@deepseek-ai/dsh-session/types'
import type { PropsRenderSlots, SessionProviderComponent } from '@deepseek-ai/dsh-client-ui-slots'

const it = createClientTest({ roster: webApp })
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); vi.restoreAllMocks() })

it.for(['deepseek-account', 'deepseek-official'])('renders provider funds through the real slots from %s', { timeout: 60_000 }, async (initialProvider, { start, mock }) => {
  const scrollDescriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollIntoView')
  Object.defineProperty(Element.prototype, 'scrollIntoView', { configurable: true, value: vi.fn() })
  onTestFinished(() => {
    if (scrollDescriptor === undefined) Reflect.deleteProperty(Element.prototype, 'scrollIntoView')
    else Object.defineProperty(Element.prototype, 'scrollIntoView', scrollDescriptor)
  })
  vi.stubGlobal('dshDesktop', {})
  vi.stubEnv('DSH_CLIENT_VERSION', '0.0.0-test')
  vi.stubGlobal('fetch', vi.fn(() => { throw new Error('External network is forbidden in this fixture') }))
  const sessionId = 'rendered-balance-session' as SessionId
  mock.remote.session.list.mockResolvedValue(ok({ items: [{
    sessionId, updatedAt: 1, running: false, blank: true, agentAvailable: true,
  }] }))
  mock.stream('session/follow', (_request, stream) => {
    stream.push({ type: 'snapshot',
      header: { version: SESSION_FORMAT_VERSION, id: sessionId, createdAt: 1, isSeeded: false },
      cursor: -1, records: [], hasMore: false,
      projections: { asOfSeq: -1, values: {} }, assistantStream: { revision: 0 },
    })
  })
  mock.remote.session.modelCatalog.mockResolvedValue(ok({
    default: { provider: 'deepseek-account', model: 'flash' },
    routableProviders: ['deepseek-account', 'deepseek-official'], failures: [],
    groups: ['deepseek-account', 'deepseek-official'].map(id => ({
      id, name: id === 'deepseek-account' ? 'Account' : 'DeepSeek',
      models: [{ id: 'flash', name: 'Flash' }],
    })),
  }))
  mock.remote.account.getBalance.mockResolvedValue(ok({
    status: 'ready', value: [{ currency: 'CNY', balance: '-0.04' }], bonusWallets: [],
  }))
  mock.remote.llm.getBalance.mockResolvedValue(ok([{ currency: 'CNY', amount: '12.34' }]))
  mock.remote.commands.list.mockResolvedValue(ok([]))
  mock.remote.skills.list.mockResolvedValue(ok({ skills: [] }))
  const client = await start()
  await client.unload('@deepseek-ai/dsh-client-ui-conversation')
  using reference = client.ctx.sessions.retain(sessionId, { source: 'mainView' })
  await reference.ready
  let seq = 1
  const selectProjection = async (provider: string): Promise<void> => {
    mock.streams.push('session/control', {
      type: 'projection', sessionId, key: 'modelSelection', seq: seq++,
      value: { next: { provider, model: 'flash' }, lastUsed: null },
    })
    await mock.streams.drained('session/control')
  }
  mock.remote.session.selectModel.mockImplementation(async (request) => {
    await selectProjection(request.provider)
    return ok({ selected: { provider: request.provider, model: request.model } })
  })
  await selectProjection(initialProvider)
  mock.streams.push('account/watch', {
    status: 'credential-stored', attempt: null,
    links: { usageUrl: 'https://example.invalid/usage', topUpUrl: 'https://example.invalid/top-up' },
  })
  type FrameProps = PropsRenderSlots<'conversation.input.right' | 'conversation.input.model'> & {
    SessionProvider: SessionProviderComponent
  }
  const unregister = client.ctx.slots.register({
    name: 'root', priority: -1, children: {
      'conversation.input.right': { kind: 'list', scope: 'session' },
      'conversation.input.model': { kind: 'single', scope: 'session' },
    },
  }, ({ renderSlot, SessionProvider }: FrameProps) => <SessionProvider session={reference}>
    {renderSlot('conversation.input.right', {})}
    {renderSlot('conversation.input.model', { locked: false })}
  </SessionProvider>)
  const view = render(client.ctx.slots.renderSlot('root', {}))
  try {
    const choose = async (group: string): Promise<void> => {
      fireEvent.click(screen.getByRole('button', { name: 'Select model, current Flash' }))
      fireEvent.click(screen.getByRole('menuitem', { name: /Model/ }))
      const section = screen.getByRole('group', { name: group })
      await act(async () => { fireEvent.click(within(section).getByRole('menuitemradio', { name: 'Flash' })) })
    }
    if (initialProvider === 'deepseek-official') {
      await waitFor(() => { expect(screen.getByLabelText('Balance ¥12.34')).toBeTruthy() })
      await choose('DeepSeek Account')
    }
    await waitFor(() => { expect(screen.getByLabelText('Balance -¥0.04')).toBeTruthy() })
    await choose('DeepSeek')
    await waitFor(() => { expect(mock.remote.llm.getBalance).toHaveBeenCalledWith('deepseek-official') })
    await waitFor(() => { expect(screen.getByLabelText('Balance ¥12.34')).toBeTruthy() })
    expect(screen.queryByLabelText('Balance -¥0.04')).toBeNull()
    mock.remote.account.getBalance.mockResolvedValue(ok({
      status: 'ready', value: [{ currency: 'CNY', balance: '99.00' }], bonusWallets: [],
    }))
    await act(async () => { window.dispatchEvent(new Event('focus')); await client.flush() })
    expect(screen.getByLabelText('Balance ¥12.34')).toBeTruthy()
    expect(screen.queryByLabelText('Balance ¥99.00')).toBeNull()
  } finally {
    view.unmount()
    unregister()
  }
})
