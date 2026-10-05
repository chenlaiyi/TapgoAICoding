import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { expect, it } from 'vitest'

const DIST_ROOT = fileURLToPath(new URL('../dist', import.meta.url))

it('ships install metadata with the built web application', async () => {
  const index = await readFile(join(DIST_ROOT, 'index.html'), 'utf8')
  expect(index).toContain('<link rel="manifest" href="./manifest.webmanifest" />')

  const manifest: unknown = JSON.parse(await readFile(join(DIST_ROOT, 'manifest.webmanifest'), 'utf8'))
  // No `id`: a browser resolves an explicit `id` against the start URL's origin,
  // so only an absent `id`, which defaults to the resolved `start_url`, gives
  // each mount its own identity. `public-mount.e2e.ts` reads the resolved form.
  expect(manifest).toEqual({
    name: '点点够终端',
    short_name: '点点够',
    start_url: './',
    scope: './',
    display: 'fullscreen',
    icons: [{
      src: 'tapgo-icon.png',
      sizes: '1024x1024',
      type: 'image/png',
      purpose: 'any',
    }],
  })
})

it('ships the Tapgo favicon for both system color schemes', async () => {
  const index = await readFile(join(DIST_ROOT, 'index.html'), 'utf8')
  expect(index).toContain('<link rel="icon" type="image/png" href="./tapgo-icon.png" />')
  const icon = await readFile(join(DIST_ROOT, 'tapgo-icon.png'))
  expect(icon.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  expect(icon.readUInt32BE(16)).toBe(1024)
  expect(icon.readUInt32BE(20)).toBe(1024)
})
