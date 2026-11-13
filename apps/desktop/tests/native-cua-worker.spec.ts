/** Packaged worker selection preserves custom native driver policy. */
import { expect, it } from 'vitest'
import { resolveDesktopNativeCuaWorker } from '../src/native-cua-worker.ts'

it('selects the signed packaged resource using the installed application identity', () => {
  expect(resolveDesktopNativeCuaWorker('darwin', true, '/App/Resources', { dshDesktopAppId: 'com.example.desktop' }, {}))
    .toEqual({ binaryPath: '/App/Resources/runtime/cua-driver/cua-driver', hostBundleId: 'com.example.desktop', restoration: { helperPath: '/App/Resources/runtime/cua-driver/interaction-lease' } })
})

it.each([
  ['win32', true, {}], ['darwin', false, {}], ['darwin', true, { CUA_DRIVER_PERMISSION_MODE: 'bounded' }],
] as const)('keeps the existing runtime for %s packaged=%s environment=%j', (platform, packaged, environment) => {
  expect(resolveDesktopNativeCuaWorker(platform, packaged, '/App/Resources', {}, environment)).toBeUndefined()
})

it.each([{}, { dshDesktopAppId: '' }, { dshDesktopAppId: 'invalid/id' }])('rejects invalid packaged identity %j', (manifest) => {
  expect(() => resolveDesktopNativeCuaWorker('darwin', true, '/App/Resources', manifest, {})).toThrow('application identifier')
})
