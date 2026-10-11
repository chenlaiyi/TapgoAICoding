// @vitest-environment jsdom
import { render, screen, cleanup } from '@testing-library/react'
import { afterEach, expect, it } from 'vitest'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'
import { AccountComposerBalance } from '../src/client/AccountComposerBalance.tsx'
import { en, zh, type AccountKey } from '../src/client/locales.ts'

afterEach(cleanup)

function mount(balance: readonly LlmBalance[] | null, copy: typeof en | typeof zh) {
  return render(<AccountComposerBalance useBalance={select => select(balance)} t={key => copy[key as AccountKey]} />)
}

it('replaces account funds with API-key funds without retaining the previous amount while loading', () => {
  const { container, rerender } = mount([{ currency: 'CNY', amount: '10.00' }], zh)
  const displayed = [container.textContent]
  for (const balance of [null, [{ currency: 'USD', amount: '3.25' }]]) {
    rerender(<AccountComposerBalance useBalance={select => select(balance)} t={key => zh[key as AccountKey]} />)
    displayed.push(container.textContent)
  }
  expect(displayed).toMatchInlineSnapshot(`
    [
      "余额 ¥10.00",
      "",
      "余额 $3.25",
    ]
  `)
})

it.each([en, zh])('sums available funds using the account currency formatter', (copy) => {
  mount([{ currency: 'CNY', amount: '123.4567' }, { currency: 'CNY', amount: '5.00' }], copy)
  expect(screen.getByLabelText(`${copy.availableBalance} ¥128.45`)).toBeTruthy()
})

it.each([null, []])('hides unavailable or empty balances', (balance) => {
  mount(balance, en)
  expect(screen.queryByText(en.availableBalance)).toBeNull()
})

it('keeps currencies separate and displays unfamiliar currencies by their ISO code', () => {
  mount([{ currency: 'CNY', amount: '1.00' }, { currency: 'USD', amount: '2.00' },
    { currency: 'CNY', amount: '0.25' }, { currency: 'EUR', amount: '3.456' }], zh)
  expect(screen.getByLabelText('余额 ¥1.25 · $2.00 · EUR 3.45')).toBeTruthy()
})
