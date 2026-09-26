/** Tapgo occupants for the browser brand slots. */
import type { Context as ClientContext } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-client-ui-renderer/client'
import type {} from '@deepseek-ai/dsh-client-ui-sidebar/client'
import type {} from '@deepseek-ai/dsh-client-ui-conversation/client'
import type {} from '@deepseek-ai/dsh-client-locale/client'
import { OfficialBrandMark, OfficialBrandName } from './Brand.tsx'
import { en, zh, type BrandKey } from './locales.ts'

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    /** Tapgo product name in official client brand slots. */
    'brand-official': BrandKey
  }
}

/** Required service: the UI slot registry. */
export const inject = ['slots', 'locale']

/**
 * Fill the sidebar and conversation brand slots in the bundled client.
 * @param ctx - Client root context.
 */
export function apply(ctx: ClientContext): void {
  if (process.env.DSH_CLIENT_BUILD_PROFILE !== 'official') return
  ctx.effect(() => ctx.locale.register('brand-official', { zh, en }), 'ui-brand-official: dictionaries')
  ctx.slots.inject('sidebar.brand.mark', () =>
    ctx.slots.inject('sidebar.brand.name', function* () {
      yield ctx.slots.register({ name: 'sidebar.brand.mark' }, OfficialBrandMark)
      yield ctx.slots.register({ name: 'sidebar.brand.name', locale: 'brand-official' }, OfficialBrandName)
    }))
  ctx.slots.inject('conversation.hero.brand.mark', function* () {
    yield ctx.slots.register({ name: 'conversation.hero.brand.mark' }, OfficialBrandMark)
  })
}
