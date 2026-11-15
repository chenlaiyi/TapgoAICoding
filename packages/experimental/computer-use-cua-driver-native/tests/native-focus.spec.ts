/** Native inspection is read-only; only a fully verified correction changes activation success. */
import { rm } from 'node:fs/promises'
import { afterEach, describe, expect, it } from 'vitest'
import { nativeBringToFront } from '../src/native-focus.ts'
import { createInteractionFixture } from './fixtures/interaction-helper.ts'

const roots: string[] = []
afterEach(async () => { for (const root of roots.splice(0)) await rm(root, { recursive: true, force: true }) })
async function fixture(mode: string) {
  const value = await createInteractionFixture(mode); roots.push(value.root); return value.config
}
const partial = { isError: true, content: [{ type: 'text', text: 'exact window unverified' }], structuredContent: {
  code: 'bring_to_front_exact_window_unverified', pid: 123, window_id: 7, request_accepted: true,
  process_activated: true, exact_window_effect: { focused: true, front_in_process_on_display: false },
} }

describe.skipIf(process.platform === 'win32')('native exact-window verification', () => {
  it('corrects an exact focused window only when native window-control surfaces account for the discrepancy', async () => {
    const config = await fixture('focus-verified'); const calls: string[] = []
    const result = await nativeBringToFront({ pid: 123, window_id: 7 }, config,
      async (name) => { calls.push(name); return partial }, new AbortController().signal)
    expect(calls).toEqual(['bring_to_front'])
    expect(result).toMatchObject({ isError: false, structuredContent: { code: 'bring_to_front_native_ax_verified',
      native_window_verification: { ignored_control_window_ids: [8], verified: true }, sdk_observation: partial.structuredContent } })
  })

  it.each(['focus-competing', 'focus-modal'])('preserves an activation failure for %s', async (mode) => {
    const result = await nativeBringToFront({ pid: 123, window_id: 7 }, await fixture(mode),
      async () => partial, new AbortController().signal)
    expect(result).toMatchObject({ isError: true })
    expect(JSON.stringify(result)).toContain('native_window_verification')
  })

  it('registers a sole AX window with the SDK before replacing an ambiguous pid-only target', async () => {
    const calls: { name: string; args: Record<string, unknown> }[] = []
    const result = await nativeBringToFront({ pid: 123, session: 'focused' }, await fixture('focus-verified'), async (name, args) => {
      calls.push({ name, args })
      return name === 'list_windows' ? { content: [], structuredContent: { windows: [{ pid: 123, window_id: 7 }, { pid: 123, window_id: 8 }] } } : partial
    }, new AbortController().signal)
    expect(calls).toEqual([{ name: 'list_windows', args: { pid: 123, session: 'focused' } },
      { name: 'bring_to_front', args: { pid: 123, session: 'focused', window_id: 7 } }])
    expect(result).toMatchObject({ isError: false })
  })

  it('keeps real pid-only multi-window ambiguity on the upstream route', async () => {
    const calls: Record<string, unknown>[] = []; const refused = { content: [], isError: true }
    const result = await nativeBringToFront({ pid: 123 }, await fixture('focus-competing'), async (_name, args) => { calls.push(args); return refused }, new AbortController().signal)
    expect(calls).toEqual([{ pid: 123 }]); expect(result).toMatchObject(refused)
  })

  it('does not turn a mismatched native report into a verified activation', async () => {
    const result = await nativeBringToFront({ pid: 124, window_id: 7 }, await fixture('focus-verified'), async () => ({ ...partial, structuredContent: { ...partial.structuredContent, pid: 124 } }), new AbortController().signal)
    expect(result).toMatchObject({ isError: true })
  })
})
