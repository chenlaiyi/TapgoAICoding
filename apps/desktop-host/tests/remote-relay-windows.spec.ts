import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { remoteRelayToml, resolveRemoteRelay } from '../src/remote-relay.ts'

const execute = vi.hoisted(() => vi.fn())
vi.mock('node:child_process', async importOriginal => ({
  ...await importOriginal<typeof import('node:child_process')>(), execFileSync: execute,
}))
const directories: string[] = []
afterEach(() => {
  vi.unstubAllGlobals()
  execute.mockReset()
  for (const directory of directories.splice(0)) rmSync(directory, { recursive: true, force: true })
})

describe('Windows mobile relay', () => {
  it('uses Windows ACLs instead of POSIX modes and the system certificate store', () => {
    vi.stubGlobal('process', { ...process, platform: 'win32' })
    const directory = mkdtempSync(join(tmpdir(), 'tapgo-win-relay-'))
    directories.push(directory)
    const tokenFile = join(directory, 'token')
    const executable = join(directory, 'frpc.exe')
    writeFileSync(tokenFile, 'isolated-test-token', { mode: 0o644 })
    writeFileSync(executable, '', { mode: 0o700 })
    const environment = { TAPGO_RELAY_DOMAIN: 'remote.example.com', TAPGO_RELAY_SERVER: 'relay.example.com',
      TAPGO_RELAY_TOKEN_FILE: tokenFile }
    execute.mockReturnValue('private\r\n')
    const config = resolveRemoteRelay(environment, directory, executable)!
    expect(config.executable).toBe(executable)
    expect(remoteRelayToml(config, 'a'.repeat(32), 49152)).not.toContain('/etc/ssl/cert.pem')
    expect(execute.mock.calls[0]?.[0]).toBe('powershell.exe')
    expect(execute.mock.calls[0]?.[2]).toMatchObject({ windowsHide: true,
      env: { TAPGO_RELAY_ACL_PATH: tokenFile } })
    execute.mockReturnValue('unsafe\r\n')
    expect(() => resolveRemoteRelay(environment, directory, executable)).toThrow('private Windows ACL')
    execute.mockImplementation(() => { throw new Error('ACL inspection failed') })
    expect(() => resolveRemoteRelay(environment, directory, executable)).toThrow('ACL inspection failed')
  })
})
