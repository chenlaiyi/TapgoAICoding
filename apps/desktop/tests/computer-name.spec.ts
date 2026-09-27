import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { namedMobileUrl, readComputerName, saveComputerName } from '../src/computer-name.ts'
import { mobilePairingPage } from '../src/mobile-pairing.ts'
import { en } from '../src/locale.ts'

describe('computer name in mobile pairing', () => {
  it('defaults to the current system name and persists an override', () => {
    const path = join(mkdtempSync(join(tmpdir(), 'tapgo-computer-name-')), 'name')
    expect(readComputerName(path, 'System Mac')).toBe('System Mac')
    expect(saveComputerName(path, '  Studio Mac  ')).toBe('Studio Mac')
    expect(readComputerName(path, 'Another system name')).toBe('Studio Mac')
    expect(readFileSync(path, 'utf8')).toBe('Studio Mac')
    expect(() => saveComputerName(path, '\n')).toThrow('Invalid computer name')
  })

  it('shows the same name and authentication token in the pairing page', async () => {
    const url = namedMobileUrl('https://mac.example/?token=secret', '工作 Mac')
    expect(new URL(url).searchParams.get('name')).toBe('工作 Mac')
    expect(new URL(url).searchParams.get('token')).toBe('secret')
    const page = await mobilePairingPage(url, '工作 Mac', en)
    expect(page).toContain('value="工作 Mac"')
    expect(page).toContain('token=secret&amp;name=')
    expect(page).toContain('tapgo-pairing://computer-name')
  })
})
