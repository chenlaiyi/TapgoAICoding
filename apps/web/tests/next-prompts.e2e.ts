/** Real Web profile, scripted model and browser: recommendations edit the draft and wait for explicit send. */
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { chromium } from 'playwright'
import { expect, it, onTestFinished } from 'vitest'
import type {} from '@deepseek-ai/dsh-next-prompts/types'
import type { SessionEvent } from '@deepseek-ai/dsh-session'
import type { StreamChunk } from '@deepseek-ai/dsh-llm'
import { launchWebScaffold } from './scaffold.ts'
import { connectFreshWorkspace, newEnglishPage } from './support.ts'

function response(text: string): StreamChunk[] {
  return [
    { type: 'block-start', index: 0, blockType: 'text' },
    { type: 'text-delta', index: 0, text },
    { type: 'block-end', index: 0, block: { type: 'text', text } },
    { type: 'finish', reason: { kind: 'stop' } },
  ]
}

it.each([false, true])('recommends contextual prompts and waits for confirmation (mobile=%s)', async (mobile) => {
  const dir = await mkdtemp(join(tmpdir(), 'dsh-next-prompts-'))
  onTestFinished(() => rm(dir, { recursive: true, force: true }))
  const override = join(dir, 'replay.override.json')
  const prompts = ['Implement the SQLite option', 'Compare migration costs', 'Explain how the recommended SQLite design handles concurrent writes and preserves all data during a rolling upgrade'] as const
  await writeFile(override, JSON.stringify([
    { kind: 'chunks', chunks: response('SQLite fits this local application. The alternative is a hosted database.') },
    { kind: 'chunks', chunks: response(JSON.stringify(prompts)) },
    { kind: 'chunks', chunks: response('Here is the implementation plan.') },
    { kind: 'chunks', chunks: response('[]') },
  ]))
  const scaffold = await launchWebScaffold({ nextPrompts: true, replayFixture: join(dir, 'override-only.jsonl'), replayOverride: override })
  onTestFinished(() => scaffold.close())
  const executablePath = process.env.DSH_PLAYWRIGHT_EXECUTABLE_PATH
  const browser = await chromium.launch(executablePath === undefined ? {} : { executablePath })
  onTestFinished(() => browser.close())
  const events: SessionEvent[] = []
  scaffold.ctx.on('session/event', (_session, event) => { events.push(event) })
  const page = mobile ? await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true,
    locale: 'en-US', userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 Version/18.6 Mobile/15E148 Safari/604.1' })
    : await newEnglishPage(browser, 900)
  await page.goto(scaffold.authenticatedUrl)
  await connectFreshWorkspace(page, scaffold.workspaceCwd, 'recommendation-test')
  const composer = page.locator('[data-composer-input][contenteditable="true"]')
  await composer.fill('Compare SQLite and a hosted database for this local application.')
  if (mobile) await page.getByRole('button', { name: 'Send message', exact: true }).tap()
  else await composer.press('Enter')
  const group = page.getByRole('group', { name: 'Suggested next prompts' })
  await group.waitFor()
  expect(await group.getByRole('button').count()).toBe(3)
  expect(events.filter(event => event.type === 'session/next-prompts-request')).toHaveLength(1)
  await composer.fill('Keep my existing draft.')
  const suggestion = group.getByRole('button', { name: prompts[0], exact: true })
  if (mobile) await suggestion.tap()
  else await suggestion.click()
  expect(await composer.innerText()).toBe('Keep my existing draft.\n\nImplement the SQLite option')
  expect(await composer.evaluate(element => element.contains(document.activeElement))).toBe(true)
  expect(events.filter(event => event.type === 'user/message' && event.data.source.kind === 'user')).toHaveLength(1)
  await mkdir('output/playwright', { recursive: true })
  await page.screenshot({ path: `output/playwright/next-prompts-${mobile ? 'mobile' : 'light'}.png` })
  if (!mobile) await page.getByRole('button', { name: 'Collapse sidebar', exact: true }).click()
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.getByRole('dialog', { name: 'Navigation', exact: true }).count()).toBe(0)
  const longPrompt = group.getByRole('button', { name: prompts[2], exact: true })
  await longPrompt.scrollIntoViewIfNeeded()
  const bounds = await longPrompt.boundingBox()
  expect(bounds).not.toBeNull()
  expect(bounds!.x).toBeGreaterThanOrEqual(0)
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(390)
  await page.screenshot({ path: 'output/playwright/next-prompts-narrow.png' })
  await page.emulateMedia({ colorScheme: 'dark' })
  await page.screenshot({ path: 'output/playwright/next-prompts-dark.png' })
  await page.reload()
  await group.waitFor()
  expect(await composer.innerText()).toBe('Keep my existing draft.\n\nImplement the SQLite option')
  expect(events.filter(event => event.type === 'session/next-prompts-request')).toHaveLength(1)
  if (mobile) await page.getByRole('button', { name: 'Send message', exact: true }).tap()
  else await composer.press('Enter')
  await expect.poll(() => events.filter(event => event.type === 'session/next-prompts-result').length).toBe(2)
  expect(events.filter(event => event.type === 'user/message' && event.data.source.kind === 'user')).toHaveLength(2)
  await expect.poll(() => group.count()).toBe(0)
  await page.reload()
  await expect.poll(() => group.count()).toBe(0)
  expect(events.filter(event => event.type === 'session/next-prompts-request')).toHaveLength(2)
})
