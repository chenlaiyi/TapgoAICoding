import { describe, expect, it, vi } from 'vitest'
import { offerManualDesktopUpdate, type ManualDesktopUpdateOptions } from '../src/manual-update.ts'
import { resolveDesktopLocale } from '../src/locale.ts'

function fixture(overrides: Partial<ManualDesktopUpdateOptions> = {}): ManualDesktopUpdateOptions {
  return { platform: 'win32', packaged: true, hasSource: false, locale: resolveDesktopLocale('zh'),
    version: '0.6.13', show: vi.fn(async () => ({ response: 0 })), open: vi.fn(async () => {}), ...overrides }
}

describe('Windows manual update entry', () => {
  it.each(['zh', 'en'])('offers localized installation guidance and opens the official page (%s)', async (language) => {
    const options = fixture({ locale: resolveDesktopLocale(language) })
    expect(await offerManualDesktopUpdate(options)).toBe(true)
    expect(vi.mocked(options.show).mock.calls).toMatchSnapshot()
    expect(options.open).toHaveBeenCalledExactlyOnceWith('https://itapgo.com/terminal/')
  })

  it.each([{ hasSource: true }, { platform: 'darwin' }, { packaged: false }])(
    'leaves configured automatic updates and development unchanged: %j', async (facts) => {
      const options = fixture(facts)
      expect(await offerManualDesktopUpdate(options)).toBe(false)
      expect(options.show).not.toHaveBeenCalled()
      expect(options.open).not.toHaveBeenCalled()
    },
  )

  it('cancels without opening a browser or attempting installation', async () => {
    const options = fixture({ show: vi.fn(async () => ({ response: 1 })) })
    expect(await offerManualDesktopUpdate(options)).toBe(true)
    expect(options.open).not.toHaveBeenCalled()
  })

  it('keeps the official address visible when browser dispatch fails', async () => {
    const options = fixture({ open: vi.fn(async () => { throw new Error('Browser unavailable') }) })
    expect(await offerManualDesktopUpdate(options)).toBe(true)
    expect(options.show).toHaveBeenCalledTimes(2)
    expect(vi.mocked(options.show).mock.calls[1]?.[0]).toMatchObject({ type: 'error',
      message: options.locale.messages.updateManualOpenFailed, detail: 'https://itapgo.com/terminal/' })
  })
})
