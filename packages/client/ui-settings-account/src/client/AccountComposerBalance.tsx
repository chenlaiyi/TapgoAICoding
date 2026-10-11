/** Available selected-provider funds beside the composer's model selector. */
import { Big } from 'big.js'
import type { HostObservable, InjectFace, PropsLocale } from '@deepseek-ai/dsh-client-ui-slots'
import type { LlmBalance } from '@deepseek-ai/dsh-llm/types'
import { formatBalance } from './formatBalance.ts'
import css from './AccountComposerBalance.module.css'

/** Provider balance provided by the Desktop account plugin. */
export interface AccountComposerBalanceInjected {
  /** Funds belonging to the current Session model provider. */
  hooks: { balance: HostObservable<readonly LlmBalance[] | null> }
}

/** @param props - localized label and selected-provider funds. @returns available funds, or nothing without a ready balance. */
export function AccountComposerBalance({ useBalance, t }:
  InjectFace<AccountComposerBalanceInjected> & PropsLocale<'settings.account'>) {
  const balance = useBalance(value => value)
  if (balance === null) return null
  const amounts = new Map<string, Big>()
  for (const wallet of balance) {
    amounts.set(wallet.currency, (amounts.get(wallet.currency) ?? new Big(0)).plus(wallet.amount))
  }
  if (amounts.size === 0) return null
  const value = [...amounts].map(([currency, amount]) =>
    formatBalance(amount.toString(), currency === 'CNY' ? '¥' : currency === 'USD' ? '$' : `${currency} `)).join(' · ')
  return <span className={css.balance} title={`${t('availableBalance')} ${value}`}
    aria-label={`${t('availableBalance')} ${value}`}>{t('availableBalance')} {value}</span>
}
