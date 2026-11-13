/** Replace only the external SDK; the harness selects source or built provider code. */
import { registerHooks } from 'node:module'
import { rm } from 'node:fs/promises'

export const name = 'computer-use-native-fixture'
export const inject = ['computerUse', 'tools', 'systemPrompt']

export async function apply(ctx) {
  const fixture = new URL('../../../packages/experimental/computer-use-cua-driver-native/tests/fixtures/cua-driver.ts', import.meta.url).href
  ctx.effect(() => {
    const hooks = registerHooks({
      resolve(specifier, context, nextResolve) {
        return specifier === '@trycua/cua-driver'
          ? { url: fixture, shortCircuit: true }
          : nextResolve(specifier, context)
      },
    })
    return () => hooks.deregister()
  }, 'computer-use-native-fixture.module')
  const provider = await import('@deepseek-ai/dsh-experimental-computer-use-cua-driver-native')
  const { createInteractionFixture } = await import(new URL('../../../packages/experimental/computer-use-cua-driver-native/tests/fixtures/interaction-helper.ts', import.meta.url))
  const helper = await createInteractionFixture()
  let fiber
  ctx.effect(() => async () => { await fiber?.dispose(); await rm(helper.root, { recursive: true, force: true }) }, 'computer-use-native-fixture.observer')
  fiber = ctx.plugin(provider, { worker: { binaryPath: '/fixture/native-worker', hostBundleId: 'com.example.desktop', restoration: helper.config } })
  await fiber
}
