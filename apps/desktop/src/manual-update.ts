/** Official manual installation for Windows packages without an automatic update source. */
import type { DesktopLocale } from './locale.ts'
import { formatDesktopMessage } from './locale.ts'
import type { UpdateDialogOptions } from './update-dialog.ts'

const DOWNLOAD_PAGE = 'https://itapgo.com/terminal/'

/** Dependencies and installed application facts for the manual update prompt. */
export interface ManualDesktopUpdateOptions {
  platform: string
  packaged: boolean
  hasSource: boolean
  locale: DesktopLocale
  version: string
  show: (options: UpdateDialogOptions) => Promise<{ response: number }>
  open: (url: string) => Promise<void>
}

/**
 * Offer the official download page instead of invoking an unavailable updater.
 * @param options - Installed application facts and shell-owned dialog/browser actions.
 * @returns Whether manual updating handled this request, including cancellation.
 */
export async function offerManualDesktopUpdate(options: ManualDesktopUpdateOptions): Promise<boolean> {
  if (!options.packaged || options.platform !== 'win32' || options.hasSource) return false
  const messages = options.locale.messages
  const result = await options.show({ type: 'info', title: messages.updateCheckTitle,
    message: messages.updateManualTitle,
    detail: `${formatDesktopMessage(messages.updateCurrentDetail, { version: options.version })}\n${messages.updateManualDetail}`,
    buttons: [messages.updateManualOpen, messages.cancel], defaultId: 0, cancelId: 1 })
  if (result.response === 0) {
    try { await options.open(DOWNLOAD_PAGE) }
    catch (error) {
      // Browser dispatch can fail; retain the official address for manual opening.
      await options.show({ type: 'error', title: messages.updateCheckTitle,
        message: messages.updateManualOpenFailed, detail: DOWNLOAD_PAGE,
        technicalDetails: error instanceof Error ? error.message : String(error) })
    }
  }
  return true
}
