import type { PropsLocale } from '@deepseek-ai/dsh-client-ui-slots'

/** Render the Tapgo icon in sidebar and conversation brand slots. */
export function OfficialBrandMark({ size, className }: { size: number; className?: string | undefined }) {
  return <img src="/tapgo-icon.png" width={size} height={size} className={className} alt="" aria-hidden="true" />
}

/** Render the Tapgo product name beside its icon. */
export function OfficialBrandName({ t }: PropsLocale<'brand-official'>) {
  return <span>{t('name')}</span>
}
