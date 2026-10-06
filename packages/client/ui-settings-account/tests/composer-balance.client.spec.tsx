// @vitest-environment jsdom
import { render, screen, cleanup } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import type { AccountSnapshot } from '../src/client/AccountSection.tsx'
import { AccountComposerBalance } from '../src/client/AccountComposerBalance.tsx'
import { en, zh, type AccountKey } from '../src/client/locales.ts'

afterEach(cleanup)

it('updates the displayed funds from the refreshed account snapshot', () => {
  const view: AccountSnapshot['view'] = { status: 'credential-stored', attempt: null, links: {
    usageUrl: 'https://example.com/usage', topUpUrl: 'https://example.com/top_up',
  } }
  const snapshot = (balance: string): AccountSnapshot => ({ view, failed: false, details: {
    balance: { status: 'ready', value: [{ currency: 'CNY', balance }], bonusWallets: [] },
  } })
  const { container, rerender } = mount(snapshot('10.00'), zh)
  const displayed = [container.textContent]
  rerender(<AccountComposerBalance useAccount={select => select(snapshot('9.50'))} t={key => zh[key as AccountKey]} />)
  displayed.push(container.textContent)
  expect(displayed).toMatchInlineSnapshot(`
    [
      "余额 ¥10.00",
      "余额 ¥9.50",
    ]
  `)
})

function mount(snapshot: AccountSnapshot, copy: typeof en | typeof zh) {
  return render(<AccountComposerBalance
    useAccount={select => select(snapshot)}
    t={key => copy[key as AccountKey]}
  />)
}

it.each([en, zh])('shows summed available funds before the model using the account currency formatter', (copy) => {
  mount({ view: { status: 'credential-stored', attempt: null, links: {
    usageUrl: 'https://example.com/usage', topUpUrl: 'https://example.com/top_up',
  } }, failed: false, details: { balance: { status: 'ready',
    value: [{ currency: 'CNY', balance: '123.4567' }],
    bonusWallets: [{ currency: 'CNY', balance: '5.00' }],
  } } }, copy)
  expect(screen.getByLabelText(`${copy.availableBalance} ¥128.45`)).toBeTruthy()
})

it.each([en, zh])('hides the composer balance when it has not been read', (copy) => {
  mount({ view: { status: 'signed-out', attempt: null, links: {
    usageUrl: 'https://example.com/usage', topUpUrl: 'https://example.com/top_up',
  } }, failed: false, details: undefined }, copy)
  expect(screen.queryByText(copy.availableBalance)).toBeNull()
})

it('keeps currencies separate and hides failed reads', () => {
  const view: AccountSnapshot['view'] = { status: 'credential-stored', attempt: null, links: {
    usageUrl: 'https://example.com/usage', topUpUrl: 'https://example.com/top_up',
  } }
  const { rerender } = mount({ view, failed: false, details: { balance: { status: 'ready',
    value: [{ currency: 'CNY', balance: '1.00' }, { currency: 'USD', balance: '2.00' }],
    bonusWallets: [{ currency: 'CNY', balance: '0.25' }],
  } } }, zh)
  expect(screen.getByLabelText('余额 ¥1.25 · $2.00')).toBeTruthy()
  rerender(<AccountComposerBalance useAccount={select => select({ view, failed: false,
    details: { balance: { status: 'failed' } } })} t={key => zh[key as AccountKey]} />)
  expect(screen.queryByLabelText(/余额/u)).toBeNull()
})

it('hides a ready account whose wallet list is empty', () => {
  mount({ view: { status: 'credential-stored', attempt: null, links: {
    usageUrl: 'https://example.com/usage', topUpUrl: 'https://example.com/top_up',
  } }, failed: false, details: { balance: { status: 'ready', value: [], bonusWallets: [] } } }, en)
  expect(screen.queryByText(en.availableBalance)).toBeNull()
})
