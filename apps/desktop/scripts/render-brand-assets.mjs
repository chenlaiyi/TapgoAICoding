import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import sharp from 'sharp'

const root = fileURLToPath(new URL('../', import.meta.url))
const at = (path) => resolve(root, path)
const master = await readFile(at('resources/dot-master.png'))
const app = await sharp(master).resize(1024, 1024).removeAlpha().png().toBuffer()
const mask = Buffer.from('<svg width="1024" height="1024"><rect width="1024" height="1024" rx="225" fill="white"/></svg>')
const transparentApp = await sharp(app).ensureAlpha().composite([{ input: mask, blend: 'dest-in' }]).png().toBuffer()
const compact = await sharp(transparentApp).resize(256, 256).png().toBuffer()
const mark = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><g id="tray-glyph"><image width="1024" height="1024" href="data:image/png;base64,${compact.toString('base64')}"/></g></svg>\n`)
await writeFile(at('resources/dot-mark.svg'), mark)
const iconFiles = [
  'resources/icon.png',
  'resources/icon-macos.png',
  'resources/icon-windows.png',
  '../web/public/tapgo-icon.png',
]
await Promise.all(iconFiles.map((path) => writeFile(at(path), transparentApp)))
await writeFile(at('../../mobile/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png'), app)
await Promise.all([
  'resources/icon.svg', 'resources/icon-macos.svg', 'resources/icon-windows.svg',
  '../web/public/favicon.svg', '../web/public/favicon-dark.svg',
  '../../website/public/favicon.svg',
].map((path) => writeFile(at(path), mark)))

const small = await sharp(mark).resize(48, 48).png().toBuffer()
const brand = `<svg xmlns="http://www.w3.org/2000/svg" width="472" height="48" viewBox="0 0 472 48"><style>text{fill:#0f1115}@media(prefers-color-scheme:dark){text{fill:#f9fafb}}</style><image href="data:image/png;base64,${small.toString('base64')}" width="48" height="48"/><text x="62" y="34" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="30" font-weight="700">点点够终端</text></svg>\n`
await writeFile(at('renderer/assets/welcome-brand.svg'), brand)

for (const dark of [false, true]) {
  for (const scale of [1, 2]) {
    const width = 600 * scale
    const height = 196 * scale
    const badge = 148 * scale
    const icon = await sharp(transparentApp).resize(badge, badge).png().toBuffer()
    const label = Buffer.from(`<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><text x="${180 * scale}" y="${116 * scale}" font-family="PingFang SC,Arial,sans-serif" font-size="${40 * scale}" font-weight="700" fill="${dark ? '#f6f7ff' : '#111827'}">点点够终端</text></svg>`)
    const background = dark ? '#151517' : '#ffffff'
    const output = await sharp({ create: { width, height, channels: 4, background } })
      .composite([{ input: icon, left: 16 * scale, top: 24 * scale }, { input: label, left: 0, top: 0 }])
      .png().toBuffer()
    await writeFile(at(`installer/assets/brand${dark ? '-dark' : ''}${scale === 2 ? '-2x' : ''}.png`), output)
  }
}
const sideIcon = await sharp(transparentApp).resize(118, 118).png().toBuffer()
const sidebar = await sharp({ create: { width: 164, height: 314, channels: 4, background: '#f1f2f6' } })
  .composite([{ input: sideIcon, left: 23, top: 82 }]).png().toBuffer()
await writeFile(at('installer/assets/uninstaller-sidebar.png'), sidebar)
