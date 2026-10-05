/** Available DeepSeek account funds beside the composer's model selector. */
import { Big } from 'big.js'
import type { HostObservable, InjectFace, PropsLocale } from '@deepseek-ai/dsh-client-ui-slots'
import type { AccountSnapshot } from './AccountSection.tsx'
import { formatBalance } from './formatBalance.ts'
import css from './AccountComposerBalance.module.css'

/** Account state provided by the Desktop account plugin. */
export interface AccountComposerBalanceInjected {
  /** Current account snapshot shared with Settings. */
  hooks: { account: HostObservable<AccountSnapshot> }
}

/** @param props - localized label and shared account snapshot. @returns available funds, or nothing without a ready balance. */
export function AccountComposerBalance({ useAccount, t }:
  InjectFace<AccountComposerBalanceInjected> & PropsLocale<'settings.account'>) {
  const account = useAccount(value => value)
  if (account.view?.status !== 'credential-stored' || account.details?.balance?.status !== 'ready') return null
  const amounts = new Map<string, Big>()
  for (const wallet of [...account.details.balance.value, ...account.details.balance.bonusWallets]) {
    amounts.set(wallet.currency, (amounts.get(wallet.currency) ?? new Big(0)).plus(wallet.balance))
  }
  if (amounts.size === 0) return null
  const value = [...amounts].map(([currency, amount]) =>
    formatBalance(amount.toString(), currency === 'CNY' ? '¥' : '$')).join(' · ')
  return <span className={css.balance} title={`${t('availableBalance')} ${value}`}
    aria-label={`${t('availableBalance')} ${value}`}>{t('availableBalance')} {value}</span>
}
